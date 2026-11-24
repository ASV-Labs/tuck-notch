import os
import AppKit
import Combine
import CoreAudio
import IOKit.pwr_mgt

// MARK: - Audio devices (output switcher + change notifications)

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

/// Lists output devices, switches the default output, and reports device changes
/// event-driven (CoreAudio property listeners), so nothing polls.
@MainActor
final class AudioDeviceService: ObservableObject {
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var currentOutputID: AudioDeviceID = 0

    /// Called when the default input device changes (MicService re-validates its controls).
    var onInputChanged: (@MainActor () -> Void)?

    private var listenersInstalled = false
    private let listenerQueue = DispatchQueue(label: "app.tucknotch.audio-listeners")

    var currentOutput: AudioDevice? { outputs.first { $0.id == currentOutputID } }

    func start() {
        refresh()
        installListeners()
    }

    func refresh() {
        outputs = Self.allDevices().filter { Self.hasStreams($0, scope: kAudioDevicePropertyScopeOutput) }
            .compactMap { id in Self.name(of: id).map { AudioDevice(id: id, name: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        currentOutputID = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) ?? 0
    }

    func select(_ device: AudioDevice) {
        var id = device.id
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        if status == noErr {
            currentOutputID = device.id
            A11y.announce("Output: \(device.name)")
        } else {
            Log.audio.error("set default output failed: \(status)")
        }
    }

    private func installListeners() {
        guard !listenersInstalled else { return }
        listenersInstalled = true
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice
        ]
        for selector in selectors {
            var addr = Self.address(selector)
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, listenerQueue) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refresh()
                    self?.onInputChanged?()
                }
            }
            if status != noErr { Log.audio.error("listener \(selector) failed: \(status)") }
        }
    }

    // CoreAudio helpers

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func allDevices() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func hasStreams(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    static func name(of device: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let cf = name?.takeRetainedValue() else { return nil }
        return cf as String
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(selector)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return (status == noErr && id != 0) ? id : nil
    }
}

// MARK: - Keep awake

/// Prevents idle display sleep for a chosen time, via a power assertion (no permission needed).
@MainActor
final class KeepAwakeService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var endsAt: Date?

    private var assertionID: IOPMAssertionID = 0
    private var endTask: Task<Void, Never>?

    struct Duration: Identifiable {
        let label: String
        let minutes: Int?
        var id: String { label }
    }

    static let durations: [Duration] = [
        Duration(label: "30 minutes", minutes: 30),
        Duration(label: "1 hour", minutes: 60),
        Duration(label: "2 hours", minutes: 120),
        Duration(label: "Until turned off", minutes: nil)
    ]

    func start(minutes: Int?) {
        stop(announce: false)
        let reason = "Tuck Notch keep awake" as CFString
        let status = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason, &assertionID)
        guard status == 0 else {   // kIOReturnSuccess
            Log.app.error("keep-awake assertion failed: \(status)")
            return
        }
        isActive = true
        if let minutes {
            let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
            endsAt = end
            endTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } else {
            endsAt = nil
        }
        A11y.announce("Keeping Mac awake")
    }

    func stop(announce: Bool = true) {
        endTask?.cancel()
        endTask = nil
        if isActive {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isActive = false
            endsAt = nil
            if announce { A11y.announce("Keep awake off") }
        }
    }

    var remainingText: String? {
        guard let endsAt else { return isActive ? "∞" : nil }
        let minutes = max(0, Int(endsAt.timeIntervalSinceNow / 60.0 + 0.5))
        return minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 > 0 ? " \(minutes % 60)m" : "")" : "\(minutes)m"
    }
}

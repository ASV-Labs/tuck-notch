import AppKit
import Combine
import CoreAudio
import IOKit.ps

// MARK: - Microphone mute

/// Mutes the current default input device. Uses the device's mute control when it exposes one,
/// otherwise drops its input volume to zero. Not universal: apps that capture from a different
/// device, or devices that expose neither control, are unaffected (the button is then hidden).
@MainActor
final class MicService: ObservableObject {
    @Published private(set) var isMuted = false
    @Published private(set) var available = true
    private var savedVolume: Float32?

    func refresh() {
        guard let device = Self.defaultInputDevice() else {
            available = false
            return
        }
        available = Self.canControl(device)
        guard available else { return }
        if let muted = Self.readMute(device) {
            isMuted = muted
        } else if let volume = Self.readVolume(device) {
            isMuted = volume <= 0.001
        }
    }

    func toggle() {
        guard let device = Self.defaultInputDevice() else {
            available = false
            return
        }
        let target = !isMuted
        if Self.setMute(device, target) {
            isMuted = target
        } else if target {
            savedVolume = Self.readVolume(device)
            if Self.setVolume(device, 0) { isMuted = true }
        } else {
            let restore = (savedVolume ?? 0.75) > 0.01 ? (savedVolume ?? 0.75) : 0.75
            if Self.setVolume(device, restore) { isMuted = false }
        }
        A11y.announce(isMuted ? "Microphone muted" : "Microphone on")
    }

    // CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return (status == noErr && id != 0) ? id : nil
    }

    private static func isSettable(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    /// True when the device exposes a settable mute or input-volume control.
    private static func canControl(_ device: AudioDeviceID) -> Bool {
        if isSettable(device, address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)) { return true }
        return volumeElements.contains {
            isSettable(device, address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput, element: $0))
        }
    }

    private static func readMute(_ device: AudioDeviceID) -> Bool? {
        var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func setMute(_ device: AudioDeviceID, _ muted: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// Input volume lives on the main element for some devices and per-channel for others.
    private static let volumeElements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    private static func readVolume(_ device: AudioDeviceID) -> Float32? {
        for element in volumeElements {
            var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput, element: element)
            guard AudioObjectHasProperty(device, &addr) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    private static func setVolume(_ device: AudioDeviceID, _ volume: Float32) -> Bool {
        var didSet = false
        for element in volumeElements {
            var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput, element: element)
            guard AudioObjectHasProperty(device, &addr) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { continue }
            var value = volume
            if AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr {
                didSet = true
            }
        }
        return didSet
    }
}

// MARK: - Battery

@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var percent: Int?
    @Published private(set) var onPower = false
    private var timer: Timer?

    func start() {
        refresh()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            percent = nil
            return
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let capacity = desc[kIOPSMaxCapacityKey] as? Int, capacity > 0 else { continue }
            percent = current * 100 / capacity
            let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let ac = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            onPower = charging || ac
            return
        }
        percent = nil   // desktop Mac, no battery
    }

    var symbol: String {
        guard let p = percent else { return "powerplug" }
        if onPower { return "battery.100.bolt" }
        switch p {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }
}

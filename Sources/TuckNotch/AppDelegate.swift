import os
import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var services: Services!
    private var controllers: [NotchWindowController] = []
    private var statusItem: NSStatusItem?
    private var presentationItem: NSMenuItem?
    private var openItem: NSMenuItem?
    private var hotKey: HotKey?
    private var settingsController: SettingsWindowController?
    private var clickMonitor: Any?
    private var moveMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    func applicationDidFinishLaunching(_ notification: Notification) {
        services = Services()
        services.anyPanelOpen = { [weak self] in
            self?.controllers.contains { $0.viewModel.isOpen } ?? false
        }
        services.start()

        buildStatusItem()
        rebuildWindows()
        registerHotKey()

        // Click anywhere outside the island closes it (global monitors see other apps' clicks only).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeAll() }
        }

        // Mouse pass-through outside the island (global: over other apps; local: over our panel).
        let moveEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveEvents, handler: { [weak self] _ in
            Task { @MainActor in self?.updatePassThrough() }
        }) { moveMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moveEvents, handler: { [weak self] event in
            Task { @MainActor in self?.updatePassThrough() }
            return event
        }) { moveMonitors.append(local) }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindows() }
        }
        // Displays can change while asleep (clamshell, unplugged monitors).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildWindows()
                self?.services.audio.refresh()
                self?.services.mic.refresh()
            }
        }

        let settings = services.settings
        settings.$showOnAllDisplays.dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.rebuildWindows() } }
            .store(in: &cancellables)
        settings.$hideFromScreenSharing.dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.controllers.forEach { $0.applySharing() } } }
            .store(in: &cancellables)
        settings.$hotkey.dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.registerHotKey() } }
            .store(in: &cancellables)
        settings.$presentationMode.dropFirst()
            .sink { [weak self] on in Task { @MainActor in if on { self?.closeAll() } } }
            .store(in: &cancellables)

        if !settings.hasOnboarded, let primary = primaryController {
            primary.viewModel.showOnboarding = true
            primary.viewModel.expand(tab: .home, focus: false)
        }
        Log.app.info("launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        moveMonitors.forEach { NSEvent.removeMonitor($0) }
        services?.keepAwake.stop(announce: false)
        services?.tasks.save()
    }

    // MARK: Windows

    private var primaryController: NotchWindowController? {
        controllers.first { $0.viewModel.metrics.hasNotch } ?? controllers.first
    }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        if services.settings.showOnAllDisplays { return screens }
        let notched = screens.filter { $0.hasNotch }
        if !notched.isEmpty { return notched }
        return NSScreen.main.map { [$0] } ?? Array(screens.prefix(1))
    }

    private func rebuildWindows() {
        let wanted = targetScreens()
        let wantedIDs = wanted.map(\.displayID)
        // Rebuild only when the set of displays or their geometry changed.
        let current = controllers.map { ($0.screenID, $0.viewModel.metrics) }
        let next = wanted.map { ($0.displayID, $0.notchMetrics) }
        if current.count == next.count,
           zip(current, next).allSatisfy({ $0.0 == $1.0 && $0.1 == $1.1 }),
           zip(controllers, wanted).allSatisfy({ $0.panel.frame == NotchWindowController.frame(for: $1) }) {
            return
        }
        controllers.forEach { $0.close() }
        controllers = wanted.map { NotchWindowController(screen: $0, services: services) }
        services.panelOpenChanged()
        Log.app.info("windows rebuilt for \(wantedIDs.count) display(s)")
    }

    private func updatePassThrough() {
        let point = NSEvent.mouseLocation
        controllers.forEach { $0.updateMousePassThrough(at: point) }
    }

    private func togglePrimary() {
        primaryController?.viewModel.toggle(focus: true)
    }

    private func closeAll() {
        for c in controllers where c.viewModel.isOpen && !c.viewModel.showOnboarding {
            c.viewModel.close()
        }
    }

    private func registerHotKey() {
        let preset = services.settings.hotkey
        hotKey = nil   // unregister the previous one first
        hotKey = HotKey(keyCode: preset.keyCode, modifiers: preset.modifiers) { [weak self] in
            Task { @MainActor in self?.togglePrimary() }
        }
        if hotKey == nil { Log.app.error("hotkey \(preset.label, privacy: .public) unavailable (in use?)") }
        openItem?.title = "Open Tuck Notch  \(preset.label)"
    }

    // MARK: Menu bar item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Tuck Notch")
                ?? NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Tuck Notch")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("Tuck Notch")
        }

        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: "Open Tuck Notch  \(services.settings.hotkey.label)", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        openItem = open

        let present = NSMenuItem(title: "Presentation Mode", action: #selector(togglePresentation), keyEquivalent: "")
        present.target = self
        menu.addItem(present)
        presentationItem = present

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if services.updates.isAvailable {
            let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Tuck Notch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        presentationItem?.state = services.settings.presentationMode ? .on : .off
    }

    @objc private func menuOpen() {
        primaryController?.viewModel.expand(focus: true)
    }

    @objc private func checkForUpdates() {
        services.updates.checkNow()
    }

    @objc private func togglePresentation() {
        services.settings.presentationMode.toggle()
    }

    @objc func showSettings() {
        openSettings(pane: nil)
    }

    func openSettings(pane: SettingsPane?) {
        closeAll()
        if settingsController == nil {
            let actions = SettingsActions(
                clearClipboard: { [weak self] in self?.services.clipboard.clear() },
                clearPins: { [weak self] in self?.services.clipboard.clearIncludingPinned() },
                clearShelf: { [weak self] in self?.services.shelf.clear() },
                replayOnboarding: { [weak self] in
                    guard let self, let primary = self.primaryController else { return }
                    self.settingsController?.window?.close()
                    primary.viewModel.showOnboarding = true
                    primary.viewModel.expand(tab: .home, focus: false)
                }
            )
            settingsController = SettingsWindowController(services: services, actions: actions)
        }
        settingsController?.show(pane)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

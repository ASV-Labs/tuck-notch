import AppKit
import SwiftUI

/// Borderless, non-activating panel that sits over the notch on every Space.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        // Above the menu bar so the island can cover the hardware notch.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        // No .fullScreenAuxiliary: the island stays out of full-screen apps, like the menu bar.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    /// Esc arrives here even when no control has focus.
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Owns one island window for one screen.
@MainActor
final class NotchWindowController {
    /// The window is a fixed transparent canvas; the island animates inside it.
    /// Clicks on transparent pixels fall through to whatever is underneath.
    static let canvasSize = CGSize(width: 720, height: 380)

    let screenID: CGDirectDisplayID
    let viewModel: NotchViewModel
    let panel: NotchPanel
    private let services: Services

    init(screen: NSScreen, services: Services) {
        self.services = services
        screenID = screen.displayID
        viewModel = NotchViewModel(metrics: screen.notchMetrics)
        panel = NotchPanel(frame: Self.frame(for: screen))

        let root = NotchRootView(vm: viewModel)
            .environmentObject(services.settings)
            .environmentObject(services.engine)
            .environmentObject(services.nowPlaying)
            .environmentObject(services.clipboard)
            .environmentObject(services.shelf)
            .environmentObject(services.timer)
            .environmentObject(services.mic)
            .environmentObject(services.battery)
            .environmentObject(services.audio)
            .environmentObject(services.keepAwake)
            .environmentObject(services.calendar)
            .environmentObject(services.weather)
            .environmentObject(services.lyrics)
            .environmentObject(services.notion)
            .environmentObject(services.tasks)
            .environmentObject(services.stats)
            .environmentObject(services.downloads)

        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvasSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        applySharing()
        panel.orderFrontRegardless()

        viewModel.onOpenChange = { [weak self] open, focus in
            self?.openChanged(open: open, focus: focus)
        }
        panel.onCancel = { [weak self] in
            Task { @MainActor in self?.viewModel.close() }
        }
        // An alert appearing under a still pointer must be clickable without a move event.
        viewModel.onIslandSizeChange = { [weak self] in
            self?.updateMousePassThrough(at: NSEvent.mouseLocation)
        }
    }

    /// The island's current rect in screen coordinates (top-centred in the canvas).
    var islandScreenRect: NSRect {
        let size = viewModel.islandSize
        let f = panel.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    /// Belt and braces for click-through: the canvas ignores the mouse except over the island
    /// (with a small margin so hover and drag targets still register). Called on mouse moves.
    func updateMousePassThrough(at point: NSPoint) {
        let hot = islandScreenRect.insetBy(dx: -8, dy: -8).contains(point)
        let ignore = !hot
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
        // While capturing, don't depend on move events reaching us: re-check until released.
        if !ignore && recheckTimer == nil {
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let point = NSEvent.mouseLocation
                    let stillHot = self.islandScreenRect.insetBy(dx: -8, dy: -8).contains(point)
                    if !stillHot {
                        self.panel.ignoresMouseEvents = true
                        self.recheckTimer?.invalidate()
                        self.recheckTimer = nil
                    }
                }
            }
            RunLoop.main.add(t, forMode: .common)
            recheckTimer = t
        }
    }

    private var recheckTimer: Timer?

    static func frame(for screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - canvasSize.width / 2,
               y: screen.frame.maxY - canvasSize.height,
               width: canvasSize.width,
               height: canvasSize.height)
    }

    func applySharing() {
        // Best effort only: legacy capture APIs honour .none, but ScreenCaptureKit
        // (Zoom, QuickTime, screenshots on macOS 15+) may still capture the window.
        // There is no public API that guarantees exclusion; presentation mode is the real control.
        panel.sharingType = services.settings.hideFromScreenSharing ? .none : .readOnly
    }

    private func openChanged(open: Bool, focus: Bool) {
        services.panelOpenChanged()
        if open {
            services.calendar.reload()
            services.mic.refresh()
            services.battery.refresh()
            services.shelf.prune()
            if focus { panel.makeKey() }
        } else if panel.isKeyWindow {
            // Hand keyboard focus back to the app the user was in.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    func close() {
        recheckTimer?.invalidate()
        recheckTimer = nil
        viewModel.onOpenChange = nil
        viewModel.onIslandSizeChange = nil
        panel.orderOut(nil)
        panel.close()
    }
}

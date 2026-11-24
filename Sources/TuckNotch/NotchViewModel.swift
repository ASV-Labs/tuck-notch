import AppKit
import SwiftUI
import Combine

/// User-driven presentation for one display's island. The final IslandState also depends on the
/// activity engine (live / attention) and is computed in NotchRootView.
@MainActor
final class NotchViewModel: ObservableObject {
    enum Presentation: Equatable {
        case closed, peek, expanded
    }

    @Published private(set) var presentation: Presentation = .closed
    @Published var tab: NotchTab = .home
    @Published var isDropTargeted = false
    /// Keeps the panel open while the user is typing (e.g. clipboard search).
    @Published var pinned = false
    @Published var showOnboarding = false
    /// The island's current size including the menu-bar flare (reported by NotchRootView).
    var islandSize: CGSize = .zero {
        didSet { if islandSize != oldValue { onIslandSizeChange?() } }
    }
    var onIslandSizeChange: (@MainActor () -> Void)?

    let metrics: NotchMetrics

    /// (isOpen, wantsKeyboardFocus)
    var onOpenChange: (@MainActor (Bool, Bool) -> Void)?

    private var hoverTask: Task<Void, Never>?

    /// Long enough that sweeping across the menu bar doesn't open the island.
    static let hoverOpenDelay: UInt64 = 250_000_000
    static let hoverCloseDelay: UInt64 = 400_000_000

    var isOpen: Bool { presentation != .closed }

    init(metrics: NotchMetrics) {
        self.metrics = metrics
    }

    func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        if inside {
            let settings = AppSettings.shared
            guard presentation == .closed, settings.openOnHover, !settings.presentationMode else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: AppSettings.shared.hoverDelay.nanoseconds)
                guard !Task.isCancelled else { return }
                // Ignore hovers while a mouse button is held (menu tracking, window drags).
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self?.peek()
            }
        } else {
            guard isOpen, !pinned, !showOnboarding else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.hoverCloseDelay)
                guard !Task.isCancelled else { return }
                self?.close()
            }
        }
    }

    func peek() {
        guard presentation == .closed else { return }
        presentation = .peek
        onOpenChange?(true, false)
    }

    func expand(tab: NotchTab? = nil, focus: Bool) {
        hoverTask?.cancel()
        let enabled = AppSettings.shared.enabledTabs
        if let tab, enabled.contains(tab) {
            self.tab = tab
        } else if !enabled.contains(self.tab) {
            self.tab = .home
        }
        let wasOpen = isOpen
        presentation = .expanded
        if !wasOpen || focus { onOpenChange?(true, focus) }
    }

    func close() {
        hoverTask?.cancel()
        guard isOpen else { return }
        presentation = .closed
        pinned = false
        isDropTargeted = false
        onOpenChange?(false, false)
    }

    func toggle(focus: Bool) {
        presentation == .expanded ? close() : expand(focus: focus)
    }

    /// Used after drag-and-drop: the pointer may never have "entered" the island.
    func scheduleClose(after seconds: Double) {
        guard isOpen, !pinned, !showOnboarding else { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func finishOnboarding() {
        showOnboarding = false
        AppSettings.shared.hasOnboarded = true
    }
}

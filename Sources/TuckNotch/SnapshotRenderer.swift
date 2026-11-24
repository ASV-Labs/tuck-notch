import AppKit
import SwiftUI

/// `TuckNotch --render-snapshots <dir>` renders the real island views for every state to PNGs,
/// with sample content, using SwiftUI's ImageRenderer (offscreen; no screen-recording permission).
/// AppKit-backed controls (sliders, menus, text fields) may render as placeholders offscreen.
@MainActor
enum SnapshotRenderer {
    static func renderAll(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = AppDefaults.store
        // Don't let sample data leak into the user's real state.
        let savedShelf = defaults.object(forKey: "shelfItems")
        let savedPins = defaults.object(forKey: "pinnedClips")
        let savedExternal = AppSettings.shared.acceptExternalActivities
        let savedOnboarded = AppSettings.shared.hasOnboarded
        defer {
            defaults.set(savedShelf, forKey: "shelfItems")
            defaults.set(savedPins, forKey: "pinnedClips")
            AppSettings.shared.acceptExternalActivities = savedExternal
            AppSettings.shared.hasOnboarded = savedOnboarded
        }
        AppSettings.shared.acceptExternalActivities = true

        let metrics = (NSScreen.screens.first { $0.hasNotch } ?? NSScreen.main)?.notchMetrics
            ?? NotchMetrics(hasNotch: true, width: 185, height: 32)
        let services = Services()
        seed(services)

        func render(_ name: String, _ configure: (NotchViewModel) -> Void) {
            let vm = NotchViewModel(metrics: metrics)
            configure(vm)
            let view = NotchRootView(vm: vm)
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
                .frame(width: NotchWindowController.canvasSize.width, height: NotchWindowController.canvasSize.height)
                .background(Color(hex: 0x3B4A6B))   // stand-in for a desktop so the black island is visible
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage else { print("FAILED \(name)"); return }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            let url = dir.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }

        // 1 Dormant
        let saved = services.engine.activities
        saved.forEach { services.engine.remove(id: $0.id) }
        render("01-dormant") { _ in }
        // 2 Live (music + timer activities)
        seedActivities(services)
        render("02-live") { _ in }
        // 3 Peek
        render("03-peek") { $0.peek() }
        // 4 Expanded tabs
        for tab in NotchTab.allCases {
            render("04-expanded-\(tab.rawValue)") { $0.expand(tab: tab, focus: false) }
        }
        // 5 Attention
        services.engine.raise(AttentionRequest(
            id: "ext.deploy", source: "external", symbol: "exclamationmark.bubble.fill",
            title: "Deploy web needs approval", subtitle: "Deploy bot · production, build 412",
            tint: .warning, priority: .high,
            actions: [ActivityAction(id: "approve", title: "Approve"), ActivityAction(id: "reject", title: "Reject")],
            autoDismissAfter: nil))
        render("05-attention") { _ in }
        services.engine.dismissAttention()
        // Presentation mode + onboarding
        services.engine.suppressed = true
        render("06-presentation-live-hidden") { _ in }
        services.engine.suppressed = false
        render("07-onboarding") { vm in vm.showOnboarding = true; vm.expand(tab: .home, focus: false) }
    }

    private static func seed(_ s: Services) {
        s.nowPlaying.applyPreview(
            track: .init(title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                         duration: 243, sourceName: "Spotify", providerID: "spotify"),
            playing: true, position: 96, artwork: sampleArtwork())
        s.timer.set(.focus, minutes: 25)
        s.timer.start()
        s.timer.pause()
        s.clipboard.previewInsert(.text("git push origin main"))
        s.clipboard.previewInsert(.text("https://example.com/deploys/412"))
        s.clipboard.previewInsert(.text("Tuck Notch — notch activity center"))
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        s.shelf.add(["README.md", "Package.swift", "Resources/AppIcon.png"].map { root.appendingPathComponent($0) })
        s.battery.refresh()
        s.mic.refresh()
        s.audio.refresh()
    }

    private static func seedActivities(_ s: Services) {
        s.engine.upsert(Activity(id: "media", source: "media", symbol: "music.note", title: "Midnight City",
                                 subtitle: "M83", tint: .live, priority: .normal,
                                 actions: [ActivityAction(id: "previous", title: "Previous", symbol: "backward.fill"),
                                           ActivityAction(id: "playpause", title: "Pause", symbol: "pause.fill"),
                                           ActivityAction(id: "next", title: "Next", symbol: "forward.fill")]))
        s.engine.upsert(Activity(id: "timer", source: "timer", symbol: "timer", title: "Focus",
                                 subtitle: "Until next break", trailing: "18:42", progress: 0.25,
                                 tint: .live, priority: .high,
                                 actions: [ActivityAction(id: "toggle", title: "Pause", symbol: "pause.fill")]))
        s.engine.upsert(Activity(id: "ext.deploy-check", source: "external", symbol: "arrow.triangle.2.circlepath",
                                 title: "Deployment verification", subtitle: "Deploy bot · running",
                                 progress: 0.6, tint: .live, priority: .normal))
        s.engine.upsert(Activity(id: "ext.build", source: "external", symbol: "circle.fill",
                                 title: "Nightly build", subtitle: "Running", trailing: "78%",
                                 tint: .success, priority: .low))
    }

    private static func sampleArtwork() -> NSImage {
        let size = NSSize(width: 300, height: 300)
        return NSImage(size: size, flipped: false) { rect in
            let g = NSGradient(colors: [NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                                        NSColor(calibratedRed: 0.25, green: 0.2, blue: 0.7, alpha: 1)])
            g?.draw(in: rect, angle: -45)
            return true
        }
    }
}

import AppKit
import SwiftUI

/// `TuckNotch --demo-tour <dir>` shows the real island on screen with sample content, one state at a
/// time, for marketing screenshots. Uses throwaway settings (never the user's data or accounts).
/// For each step it writes "<name> <windowID>" to <dir>/ready and waits for <dir>/done-<name>, so a
/// script can capture the window (`screencapture -l <windowID>`). Then it quits.
@MainActor
enum DemoTour {
    static var outputDir: URL?
    static var isActive: Bool { outputDir != nil }

    struct Step {
        let name: String
        let run: () -> Void
        var window: () -> Int? = { nil }
    }

    static func prepareSettings() {
        let s = AppSettings.shared
        s.hasOnboarded = true
        s.homeCards = [HomeCard.nowPlaying, .weather, .calendar, .todos].map(\.rawValue)
        s.acceptExternalActivities = true
        s.panelOpacity = 1
        s.hideFromScreenSharing = false   // the tour exists to be captured
    }

    static func start(services: Services, primary: NotchWindowController, openSettings: @escaping (SettingsPane) -> Void,
                      settingsWindow: @escaping () -> NSWindow?) {
        guard let dir = outputDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        seed(services)
        let vm = primary.viewModel
        let island = { Int(primary.panel.windowNumber) }
        func open(_ tab: NotchTab) { vm.pinned = true; vm.expand(tab: tab, focus: false) }

        var steps: [Step] = [
            Step(name: "01-live") { vm.pinned = false; vm.close(); seedActivities(services) },
            Step(name: "02-peek") { vm.pinned = true; vm.peek() },   // pinned: the pointer is elsewhere
            Step(name: "03-home") { open(.home) },
            Step(name: "04-media") { open(.media) },
            Step(name: "05-calendar") { open(.calendar) },
            Step(name: "06-notes") { open(.notes) },
            Step(name: "07-shelf") { open(.shelf) },
            Step(name: "08-clipboard") { open(.clipboard) },
            Step(name: "09-timer") { open(.timer) },
            Step(name: "10-activity") { open(.activity) },
            Step(name: "11-attention") {
                vm.pinned = false; vm.close()
                services.engine.raise(AttentionRequest(
                    id: "ext.deploy", source: "external", symbol: "exclamationmark.bubble.fill",
                    title: "Deploy needs approval", subtitle: "Deploy bot · production, build 412",
                    tint: .warning, priority: .high,
                    actions: [ActivityAction(id: "approve", title: "Approve"), ActivityAction(id: "reject", title: "Reject")],
                    autoDismissAfter: nil))
            },
            Step(name: "12-glass") {
                services.engine.dismissAttention()
                AppSettings.shared.panelOpacity = 0.55
                AppSettings.shared.panelBlur = false
                open(.home)
            },
        ]
        steps = steps.map { var s = $0; s.window = island; return s }
        steps.append(Step(name: "13-settings-appearance", run: {
            vm.pinned = false; vm.close()
            AppSettings.shared.panelOpacity = 1
            openSettings(.appearance)
        }, window: { settingsWindow().map { Int($0.windowNumber) } }))
        steps.append(Step(name: "14-settings-home", run: { openSettings(.home) },
                          window: { settingsWindow().map { Int($0.windowNumber) } }))

        Task { @MainActor in
            for step in steps {
                step.run()
                try? await Task.sleep(nanoseconds: 1_400_000_000)   // let animations settle
                guard let window = step.window() else { continue }
                let done = dir.appendingPathComponent("done-\(step.name)")
                try? FileManager.default.removeItem(at: done)
                try? "\(step.name) \(window)\n".write(to: dir.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
                for _ in 0..<100 where !FileManager.default.fileExists(atPath: done.path) {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            try? "finished\n".write(to: dir.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    // MARK: Sample content (fictional)

    private static func seed(_ s: Services) {
        s.nowPlaying.applyPreview(
            track: .init(title: "Low Tide", artist: "Glass Coast", album: "Night Ferries",
                         duration: 231, sourceName: "Music", providerID: "music"),
            playing: true, position: 84, artwork: artwork())
        s.timer.set(.focus, minutes: 25)
        s.timer.start()
        s.timer.pause()
        s.clipboard.previewInsert(.text("Meet at the ferry terminal, 7:40"))
        s.clipboard.previewInsert(.text("https://github.com/ASV-Labs/tuck-notch"))
        s.clipboard.previewInsert(.text("Ship the release notes by 3 pm"))
        s.weather.applyPreview(placeLabel: "Lisbon, Portugal",
                               current: .init(temperature: 21, high: 24, low: 15, code: 1, isDay: true, updated: Date()))
        let cal = Calendar.current
        let now = Date()
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let soon = now.addingTimeInterval(25 * 60)
        s.calendar.applyPreview(events: [
            .init(id: "1", title: "Design review", start: soon, end: soon.addingTimeInterval(45 * 60), isAllDay: false,
                  color: Color(hex: 0x8B7CF6), joinURL: URL(string: "https://meet.google.com/abc-defg-hij"), joinService: "Meet"),
            .init(id: "2", title: "Ship 0.7 build", start: at(1, 10), end: at(1, 11), isAllDay: false,
                  color: Color(hex: 0xF5A524), joinURL: nil, joinService: nil),
            .init(id: "3", title: "Community call", start: at(2, 15), end: at(2, 15, 45), isAllDay: false,
                  color: Color(hex: 0x3FA7F5), joinURL: URL(string: "https://zoom.us/j/123456789"), joinService: "Zoom"),
        ], busyDays: Set([3, 7, 12, 16, 21, 25, 26].map { $0 } + [cal.component(.day, from: now)]))
        s.tasks.todos.forEach { s.tasks.remove($0.id) }
        for t in ["Record launch video", "Reply to feature requests", "Water the plants"] { s.tasks.add(t) }
        if let first = s.tasks.todos.last { s.tasks.toggle(first.id) }
        s.tasks.note = "Launch checklist\n• Post on X with the demo clip\n• Pin the release\n• Thank the first contributors"
        let shelfDir = FileManager.default.temporaryDirectory.appendingPathComponent("tucknotch-demo-shelf")
        try? FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
        let files = ["Launch Plan.pdf", "Hero Shot.png", "Release Notes.md"].map { shelfDir.appendingPathComponent($0) }
        files.forEach { try? Data("demo".utf8).write(to: $0) }
        s.shelf.add(files)
        s.battery.refresh()
        s.audio.refresh()
    }

    private static func seedActivities(_ s: Services) {
        s.engine.upsert(Activity(id: "media", source: "media", symbol: "music.note", title: "Low Tide",
                                 subtitle: "Glass Coast", tint: .live, priority: .high,
                                 actions: [ActivityAction(id: "previous", title: "Previous", symbol: "backward.fill"),
                                           ActivityAction(id: "playpause", title: "Pause", symbol: "pause.fill"),
                                           ActivityAction(id: "next", title: "Next", symbol: "forward.fill")]))
        s.engine.upsert(Activity(id: "timer", source: "timer", symbol: "timer", title: "Focus",
                                 subtitle: "Until next break", trailing: "18:42", progress: 0.25,
                                 tint: .live, priority: .normal,
                                 actions: [ActivityAction(id: "toggle", title: "Pause", symbol: "pause.fill")]))
        s.engine.upsert(Activity(id: "download.demo", source: "downloads", symbol: "arrow.down.circle",
                                 title: "Xcode_17.xip", subtitle: "4.1 GB of 7.9 GB · 48 MB/s", trailing: "52%",
                                 progress: 0.52, tint: .accent, priority: .normal))
        s.engine.upsert(Activity(id: "ext.agent", source: "external", symbol: "sparkles",
                                 title: "Agent: refactor tests", subtitle: "Step 3 of 5 · running",
                                 progress: 0.6, tint: .live, priority: .normal))
    }

    private static func artwork() -> NSImage {
        let size = NSSize(width: 600, height: 600)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.85, blue: 0.95, alpha: 1),
                                NSColor(calibratedRed: 0.42, green: 0.25, blue: 0.95, alpha: 1),
                                NSColor(calibratedRed: 0.95, green: 0.3, blue: 0.75, alpha: 1)])?.draw(in: rect, angle: -50)
            let sun = NSBezierPath(ovalIn: NSRect(x: 190, y: 250, width: 220, height: 220))
            NSColor(calibratedWhite: 1, alpha: 0.85).setFill(); sun.fill()
            for i in 0..<6 {
                let y = CGFloat(90 + i * 28)
                let wave = NSBezierPath(rect: NSRect(x: 0, y: y, width: rect.width, height: 10))
                NSColor(calibratedRed: 0.1, green: 0.05, blue: 0.3, alpha: 0.55).setFill(); wave.fill()
            }
            return true
        }
    }
}

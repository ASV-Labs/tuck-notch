import AppKit

@main
enum TuckNotchMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if !args.contains("--render-snapshots") && !args.contains("--demo-tour") { LegacyMigration.run() }
        if let i = args.firstIndex(of: "--demo-tour"), i + 1 < args.count {
            AppDefaults.enterSnapshotMode()
            DemoTour.outputDir = URL(fileURLWithPath: args[i + 1])
            DemoTour.prepareSettings()
        }
        if let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count {
            AppDefaults.enterSnapshotMode()
            _ = NSApplication.shared
            SnapshotRenderer.renderAll(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar style app, no Dock icon
        app.run()
        _ = delegate                          // keep the delegate alive for the app's lifetime
    }
}

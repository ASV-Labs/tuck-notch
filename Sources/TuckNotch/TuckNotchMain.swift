import AppKit

@main
enum TuckNotchMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if !args.contains("--render-snapshots") { LegacyMigration.run() }
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

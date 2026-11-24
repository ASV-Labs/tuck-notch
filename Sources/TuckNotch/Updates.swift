import AppKit
import Combine
import Sparkle

/// Automatic updates through Sparkle. Releases are published on GitHub, each DMG is signed with
/// ASV Labs' Developer ID, notarized by Apple, and carries an EdDSA signature that Sparkle checks
/// against the public key in Info.plist before installing.
@MainActor
final class UpdateService: ObservableObject {
    @Published var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published private(set) var canCheck = false

    private let controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    /// False for snapshot renders and for source builds without a release key.
    var isAvailable: Bool { controller != nil }

    static let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""

    /// A build is updatable only when it carries a real Sparkle public key.
    nonisolated static func isConfigured(publicKey: String?) -> Bool {
        guard let key = publicKey?.trimmingCharacters(in: .whitespaces), key.count >= 40 else { return false }
        return !key.contains("SPARKLE")
    }

    init(enabled: Bool) {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        if enabled, Self.isConfigured(publicKey: key) {
            let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            controller = c
            automaticallyChecks = c.updater.automaticallyChecksForUpdates
            observation = c.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let can = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheck = can }
            }
        } else {
            controller = nil
            automaticallyChecks = false
        }
    }

    func checkNow() {
        controller?.checkForUpdates(nil)
    }
}

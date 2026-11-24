import Foundation
import Security

/// One-time carry-over from the app's previous name ("Top Notch", bundle id com.asvlabs.topnotch):
/// settings, the Application Support folder and the Notion secret. Runs before anything reads them.
enum LegacyMigration {
    static let oldBundleID = "com.asvlabs." + "top" + "notch"
    static let oldFolderName = "Top" + "Notch"
    static let doneKey = "migratedFromLegacyName"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        // Settings: copy the old preferences domain if this one is still empty.
        if let bundleID = Bundle.main.bundleIdentifier, bundleID != oldBundleID,
           (defaults.persistentDomain(forName: bundleID) ?? [:]).isEmpty,
           let old = defaults.persistentDomain(forName: oldBundleID), !old.isEmpty {
            defaults.setPersistentDomain(old, forName: bundleID)
            // Move, don't copy: the old file would otherwise keep pinned clipboard text around.
            defaults.removePersistentDomain(forName: oldBundleID)
        }
        // Files: move ~/Library/Application Support/TopNotch → TuckNotch if the new one doesn't exist.
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldDir = base.appendingPathComponent(oldFolderName, isDirectory: true)
        let newDir = base.appendingPathComponent("TuckNotch", isDirectory: true)
        if fm.fileExists(atPath: oldDir.path), !fm.fileExists(atPath: newDir.path) {
            try? fm.moveItem(at: oldDir, to: newDir)
        }
        // Keychain: the Notion secret moves to the new service name.
        let account = "notion-integration-secret"
        if Keychain.get(account: account) == nil, let secret = readOld(account: account) {
            if Keychain.set(secret, account: account) { deleteOld(account: account) }
        }
        defaults.set(true, forKey: doneKey)
    }

    private static func readOld(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: oldBundleID,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteOld(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: oldBundleID,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { Log.app.error("old keychain item not removed: \(status)") }
    }
}

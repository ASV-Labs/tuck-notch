import AppKit
import Combine
import UniformTypeIdentifiers

/// A temporary stash of files. Holds references (paths) only; files are never moved or copied.
@MainActor
final class ShelfService: ObservableObject {
    @Published private(set) var items: [URL] = []
    private let key = "shelfItems"

    init() {
        let paths = AppDefaults.store.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
        prune()
    }

    func add(_ urls: [URL]) {
        var added = 0
        for url in urls where url.isFileURL && !items.contains(url) {
            items.append(url)
            added += 1
        }
        guard added > 0 else { return }
        save()
        A11y.announce(added == 1 ? "1 file added to shelf" : "\(added) files added to shelf")
    }

    /// Accepts drops from Finder and any app that provides file URLs.
    func handle(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                Task { @MainActor in self?.add([url]) }
            }
        }
        return true
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
        A11y.announce("Shelf cleared")
    }

    func prune() {
        let fm = FileManager.default
        let kept = items.filter { fm.fileExists(atPath: $0.path) }
        if kept.count != items.count {
            items = kept
            save()
        }
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func copyPath(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
    }

    private func save() {
        AppDefaults.store.set(items.map(\.path), forKey: key)
    }
}

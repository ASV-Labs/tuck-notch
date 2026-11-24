import os
import AppKit

/// Local, opt-in activity API. Any process running as this user can publish an activity by
/// atomically writing a JSON file into the inbox folder; button presses are written back to
/// the outbox folder for the publisher to pick up. No network listener, no new permissions.
///
///   ~/Library/Application Support/TuckNotch/Inbox/<id>.json    (publish / update)
///   ~/Library/Application Support/TuckNotch/Outbox/<id>-<ts>.json   (action responses)
///
/// See tools/tucknotch-activity for a ready-made CLI.
struct ExternalActivityPayload: Decodable, Equatable {
    let id: String
    var source: String?
    var title: String
    var subtitle: String?
    var symbol: String?
    /// running | done | failed | needs-input | idle | online | offline | warning
    var state: String?
    var progress: Double?
    var trailing: String?
    var priority: String?
    var attention: Bool?
    var expiresIn: Double?
    var actions: [ActivityAction]?
}

enum ExternalActivityParser {
    static let maxFileBytes = 32 * 1024
    static let idPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]{1,64}$")

    struct Parsed: Equatable {
        var activity: Activity
        var state: String
        var wantsAttention: Bool
    }

    /// Validates and clamps untrusted input. Returns nil for anything malformed.
    static func parse(_ data: Data, now: Date = Date(), symbolExists: (String) -> Bool = { _ in true }) -> Parsed? {
        guard data.count <= maxFileBytes,
              let p = try? JSONDecoder().decode(ExternalActivityPayload.self, from: data) else { return nil }
        let range = NSRange(p.id.startIndex..., in: p.id)
        guard idPattern.firstMatch(in: p.id, range: range) != nil else { return nil }
        let title = clip(p.title, 80)
        guard !title.isEmpty else { return nil }

        let state = (p.state ?? "running").lowercased()
        let (defaultSymbol, tint) = style(for: state)
        var symbol = defaultSymbol
        if let s = p.symbol, s.count <= 64, symbolExists(s) { symbol = s }

        var priority = ActivityPriority(string: p.priority)
        if priority == .critical { priority = .high }   // only the app itself may raise critical
        if state == "needs-input" || state == "failed" { priority = max(priority, .high) }

        let actions = (p.actions ?? []).prefix(3).compactMap { a -> ActivityAction? in
            guard idPattern.firstMatch(in: a.id, range: NSRange(a.id.startIndex..., in: a.id)) != nil else { return nil }
            return ActivityAction(id: a.id, title: clip(a.title, 24), symbol: nil)
        }

        let subtitle: String?
        switch (p.source.map { clip($0, 40) }, p.subtitle.map { clip($0, 120) }) {
        case let (src?, sub?): subtitle = "\(src) · \(sub)"
        case let (src?, nil): subtitle = src
        case let (nil, sub?): subtitle = sub
        default: subtitle = nil
        }

        let activity = Activity(
            id: "ext." + p.id,
            source: "external",
            symbol: symbol,
            title: title,
            subtitle: subtitle,
            trailing: p.trailing.map { clip($0, 8) },
            progress: p.progress.map { min(1, max(0, $0)) },
            tint: tint,
            priority: priority,
            createdAt: now,
            expiresAt: p.expiresIn.flatMap { $0 > 0 ? now.addingTimeInterval(min($0, 7 * 86400)) : nil },
            actions: Array(actions)
        )
        let wantsAttention = (p.attention ?? false) || state == "needs-input" || state == "failed"
        return Parsed(activity: activity, state: state, wantsAttention: wantsAttention)
    }

    static func style(for state: String) -> (String, ActivityTint) {
        switch state {
        case "done", "complete", "completed", "success": return ("checkmark.circle.fill", .success)
        case "failed", "error": return ("xmark.octagon.fill", .danger)
        case "needs-input", "attention", "approval": return ("exclamationmark.bubble.fill", .warning)
        case "warning": return ("exclamationmark.triangle.fill", .warning)
        case "online": return ("circle.fill", .success)
        case "offline": return ("bolt.horizontal.circle.fill", .danger)
        case "idle": return ("moon.zzz.fill", .neutral)
        default: return ("arrow.triangle.2.circlepath", .live)
        }
    }

    static func clip(_ s: String, _ max: Int) -> String {
        let cleaned = s.components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > max ? String(cleaned.prefix(max - 1)) + "…" : cleaned
    }
}

@MainActor
final class ExternalActivityInbox {
    static var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TuckNotch", isDirectory: true)
    }
    static var inboxURL: URL { baseURL.appendingPathComponent("Inbox", isDirectory: true) }
    static var outboxURL: URL { baseURL.appendingPathComponent("Outbox", isDirectory: true) }

    static let maxFiles = 20

    private let engine: ActivityEngine
    private var source: DispatchSourceFileSystemObject?
    private var rescanTimer: Timer?
    private var known: [String: (mtime: Date, state: String)] = [:]
    private var pending: Task<Void, Never>?

    private(set) var isRunning = false

    init(engine: ActivityEngine) {
        self.engine = engine
        engine.registerHandler(source: "external") { [weak self] itemID, actionID in
            self?.respond(itemID: itemID, actionID: actionID)
        }
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard !isRunning else { return }
        let fm = FileManager.default
        for url in [Self.inboxURL, Self.outboxURL] {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let fd = open(Self.inboxURL.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            src.setEventHandler { [weak self] in
                Task { @MainActor in self?.scheduleRescan() }
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
        }
        // Fallback for writers that modify files in place (no directory event).
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
        RunLoop.main.add(t, forMode: .common)
        rescanTimer = t
        isRunning = true
        Log.inbox.info("inbox started")
        rescan()
    }

    private func stop() {
        guard isRunning else { return }
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        rescanTimer?.invalidate()
        rescanTimer = nil
        known.removeAll()
        engine.removeAll(source: "external")
        isRunning = false
    }

    private func scheduleRescan() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    /// Reads a plain file without following symlinks or blocking on FIFOs/devices, and never more
    /// than `limit` bytes. Anything else (symlink, pipe, oversized) returns nil.
    nonisolated static func readRegularFile(_ url: URL, limit: Int) -> Data? {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), Int(info.st_size) <= limit else { return nil }
        var buffer = [UInt8](repeating: 0, count: limit + 1)
        let count = Darwin.read(fd, &buffer, limit + 1)
        guard count >= 0, count <= limit else { return nil }
        return Data(buffer.prefix(count))
    }

    func rescan() {
        guard isRunning else { return }
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: Self.inboxURL,
                                                  includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                  options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(Self.maxFiles)

        var seen = Set<String>()
        for file in files {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = values?.contentModificationDate ?? .distantPast
            let key = file.lastPathComponent
            let basename = (key as NSString).deletingPathExtension
            seen.insert(key)
            if let previous = known[key], previous.mtime == mtime { continue }
            // Size check before reading; the id must match the filename so removal and dismiss agree.
            guard (values?.fileSize ?? Int.max) <= ExternalActivityParser.maxFileBytes,
                  let data = Self.readRegularFile(file, limit: ExternalActivityParser.maxFileBytes),
                  let parsed = ExternalActivityParser.parse(data, symbolExists: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }),
                  parsed.activity.id == "ext." + basename else {
                if known[key]?.state != "rejected" { Log.inbox.error("rejected \(key, privacy: .public)") }
                known[key] = (mtime, "rejected")   // don't re-read until it changes
                engine.remove(id: "ext." + basename)
                engine.withdrawAttention(id: "ext." + basename)
                continue
            }
            let previousState = known[key]?.state
            let stateChanged = previousState != parsed.state
            known[key] = (mtime, parsed.state)
            engine.upsert(parsed.activity)
            if stateChanged && !parsed.wantsAttention {
                engine.withdrawAttention(id: parsed.activity.id)   // resolved by the publisher
            }
            if parsed.wantsAttention && stateChanged {
                let a = parsed.activity
                engine.raise(AttentionRequest(
                    id: a.id, source: "external", symbol: a.symbol, title: a.title, subtitle: a.subtitle,
                    tint: a.tint, priority: a.priority,
                    actions: a.actions.isEmpty ? [ActivityAction(id: "dismiss", title: "Dismiss")] : a.actions,
                    autoDismissAfter: parsed.state == "needs-input" ? nil : 10
                ))
            }
        }
        for gone in Set(known.keys).subtracting(seen) {
            known.removeValue(forKey: gone)
            let id = "ext." + (gone as NSString).deletingPathExtension
            engine.remove(id: id)
            engine.withdrawAttention(id: id)
        }
    }

    /// Writes the user's choice where the publisher can read it. "dismiss" also clears the item.
    private func respond(itemID: String, actionID: String) {
        let rawID = itemID.hasPrefix("ext.") ? String(itemID.dropFirst(4)) : itemID
        if actionID == "dismiss" {
            engine.remove(id: itemID)
            engine.withdrawAttention(id: itemID)
            try? FileManager.default.removeItem(at: Self.inboxURL.appendingPathComponent(rawID + ".json"))
            return
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let payload: [String: Any] = ["id": rawID, "action": actionID, "at": ISO8601DateFormatter().string(from: Date())]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let url = Self.outboxURL.appendingPathComponent("\(rawID)-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            A11y.announce("Sent \(actionID)")
        } catch {
            Log.inbox.error("outbox write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

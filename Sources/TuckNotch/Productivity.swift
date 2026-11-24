import AppKit
import Combine
import Darwin
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paths

/// Where settings live. Snapshot renders use a throwaway suite so they never see or change real data.
enum AppDefaults {
    nonisolated(unsafe) static var isSnapshotMode = false
    nonisolated(unsafe) static var store: UserDefaults = .standard

    static func enterSnapshotMode() {
        isSnapshotMode = true
        let name = "com.asvlabs.tucknotch.snapshots"
        UserDefaults.standard.removePersistentDomain(forName: name)
        store = UserDefaults(suiteName: name) ?? .standard
    }
}

enum AppPaths {
    /// ~/Library/Application Support/TuckNotch (user-only); a temporary folder for snapshot renders.
    static var support: URL {
        let base = AppDefaults.isSnapshotMode
            ? FileManager.default.temporaryDirectory.appendingPathComponent("tucknotch-snapshots")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TuckNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }
}

// MARK: - To-dos and notes

/// Local to-do list and a scratchpad note. Stored as JSON in Application Support (mode 0600).
/// Nothing is synced or sent anywhere.
@MainActor
final class TasksService: ObservableObject {
    struct Todo: Identifiable, Codable, Equatable {
        var id = UUID()
        var text: String
        var done = false
        var created = Date()
    }

    private struct Store: Codable {
        var todos: [Todo]
        var note: String
    }

    @Published private(set) var todos: [Todo] = []
    @Published var note: String = "" { didSet { scheduleSave() } }

    static let maxTodos = 200
    static let maxTodoLength = 300
    static let maxNoteLength = 20_000

    private let fileURL: URL
    private var saveWork: DispatchWorkItem?
    private var loading = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppPaths.support.appendingPathComponent("notes.json")
        load()
    }

    var openCount: Int { todos.filter { !$0.done }.count }

    /// Open items first (oldest first), then finished ones.
    var ordered: [Todo] {
        todos.filter { !$0.done } + todos.filter(\.done)
    }

    func add(_ text: String) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTodoLength))
        guard !trimmed.isEmpty, todos.count < Self.maxTodos else { return }
        todos.append(Todo(text: trimmed))
        save()
        A11y.announce("Added \(trimmed)")
    }

    func toggle(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle()
        save()
    }

    func remove(_ id: UUID) {
        todos.removeAll { $0.id == id }
        save()
    }

    func clearDone() {
        todos.removeAll(where: \.done)
        save()
    }

    // MARK: Persistence

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let store = try? JSONDecoder().decode(Store.self, from: data) else {
            // Keep an unreadable file instead of overwriting it on the next save.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return
        }
        todos = Array(store.todos.prefix(Self.maxTodos))
        note = String(store.note.prefix(Self.maxNoteLength))
    }

    private func scheduleSave() {
        guard !loading else { return }
        if note.count > Self.maxNoteLength { note = String(note.prefix(Self.maxNoteLength)) }   // didSet doesn't re-fire here
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.save() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func save() {
        guard !loading, let data = try? JSONEncoder().encode(Store(todos: todos, note: note)) else { return }
        do {
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.app.error("notes save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Pulse (CPU and memory)

/// Samples CPU and memory with Mach host statistics. Only runs while a panel is open.
@MainActor
final class SystemStatsService: ObservableObject {
    @Published private(set) var cpu: Double = 0          // 0…1 across all cores
    @Published private(set) var memory: Double = 0       // 0…1 used (app + wired + compressed)
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []

    nonisolated static let historyLength = 30
    private var timer: Timer?
    private var lastTicks: (used: UInt64, total: UInt64)?

    var isRunning: Bool { timer != nil }

    func setActive(_ active: Bool) {
        if active, timer == nil {
            sample()
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sample() }
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !active {
            timer?.invalidate()
            timer = nil
            lastTicks = nil
        }
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                cpu = Self.cpuUsage(previous: last, current: ticks)
                append(&cpuHistory, cpu)
            }
            lastTicks = ticks
        }
        if let mem = Self.memoryUsage() {
            memory = mem
            append(&memoryHistory, mem)
        }
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    nonisolated static func cpuUsage(previous: (used: UInt64, total: UInt64), current: (used: UInt64, total: UInt64)) -> Double {
        let total = Double(current.total &- previous.total)
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(current.used &- previous.used) / total))
    }

    private nonisolated static let hostPort = mach_host_self()

    nonisolated static func cpuTicks() -> (used: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    nonisolated static func memoryUsage() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Double(getpagesize())
        let used = (Double(stats.internal_page_count) - Double(stats.purgeable_count)
                    + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return min(1, max(0, used / total))
    }
}

// MARK: - Browser downloads (opt-in)

/// Watches ~/Downloads for in-progress browser downloads and publishes them as live activities.
/// Chrome/Arc/Brave/Edge write `*.crdownload`, Safari a `*.download` bundle (with progress in its
/// Info.plist), Firefox `*.part`. Reads file sizes and names only, never contents.
@MainActor
final class DownloadsService: ObservableObject {
    struct Download: Identifiable, Equatable {
        let id: String            // partial file name
        var name: String          // final file name
        var bytes: Int64
        var total: Int64?         // Safari reports it; Chromium doesn't
        var bytesPerSecond: Double
        var progress: Double? { total.flatMap { $0 > 0 ? min(1, Double(bytes) / Double($0)) : nil } }
    }

    @Published private(set) var active: [Download] = []
    var onFinished: (@MainActor (String) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var poll: Timer?
    private var last: [String: (bytes: Int64, at: Date)] = [:]
    private(set) var isEnabled = false

    /// A partial file that hasn't changed for this long is treated as abandoned.
    nonisolated static let staleAfter: TimeInterval = 60

    nonisolated static var downloadsURL: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        enabled ? start() : stop()
    }

    private func start() {
        fd = Darwin.open(Self.downloadsURL.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            src.setEventHandler { [weak self] in Task { @MainActor in self?.scan() } }
            let descriptor = fd
            src.setCancelHandler { Darwin.close(descriptor) }
            src.resume()
            source = src
        }
        scan()
    }

    private func stop() {
        source?.cancel()
        source = nil
        fd = -1
        poll?.invalidate()
        poll = nil
        active = []
        last = [:]
    }

    /// Maps a partial download name to the final file name, or nil if it isn't one.
    nonisolated static func finalName(for partial: String) -> String? {
        for ext in [".crdownload", ".download", ".part"] where partial.lowercased().hasSuffix(ext) {
            var name = String(partial.dropLast(ext.count))
            // Chrome's not-yet-named downloads look like "Unconfirmed 12345"
            if name.hasPrefix("Unconfirmed ") { name = "Download" }
            return name.isEmpty ? nil : name
        }
        return nil
    }

    func scan() {
        guard isEnabled else { return }
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: Self.downloadsURL.path)) ?? []
        var found: [Download] = []
        let now = Date()
        // Filter first, then cap, so a huge Downloads folder can't hide active downloads.
        for partial in names.lazy.filter({ Self.finalName(for: $0) != nil }).prefix(50) {
            guard let name = Self.finalName(for: partial) else { continue }
            let url = Self.downloadsURL.appendingPathComponent(partial)
            var bytes: Int64 = 0
            var total: Int64?
            var modified: Date?
            if partial.lowercased().hasSuffix(".download") {
                // Safari bundle: progress lives in Info.plist (bounded read, no symlinks or pipes)
                let plist = url.appendingPathComponent("Info.plist")
                modified = (try? fm.attributesOfItem(atPath: plist.path))?[.modificationDate] as? Date
                if let data = ExternalActivityInbox.readRegularFile(plist, limit: 256 * 1024),
                   let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
                    bytes = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                    let t = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value ?? 0
                    total = t > 0 ? t : nil
                }
            } else {
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                modified = attrs?[.modificationDate] as? Date
            }
            // Leftover partial files from stopped or crashed downloads stop changing; ignore them.
            guard let modified, now.timeIntervalSince(modified) < Self.staleAfter else { continue }
            var speed = active.first(where: { $0.id == partial })?.bytesPerSecond ?? 0
            if let previous = last[partial] {
                let dt = now.timeIntervalSince(previous.at)
                if dt >= 1 {
                    speed = max(0, Double(bytes - previous.bytes) / dt)
                    last[partial] = (bytes, now)
                }
            } else {
                last[partial] = (bytes, now)
            }
            found.append(Download(id: partial, name: name, bytes: bytes, total: total, bytesPerSecond: speed))
        }
        // A partial file that's gone, with the final file now present, finished.
        for gone in active where !found.contains(where: { $0.id == gone.id }) {
            last[gone.id] = nil
            let partialGone = !fm.fileExists(atPath: Self.downloadsURL.appendingPathComponent(gone.id).path)
            if partialGone, fm.fileExists(atPath: Self.downloadsURL.appendingPathComponent(gone.name).path) { onFinished?(gone.name) }
        }
        if found != active { active = found }
        // Folder events don't fire for appends to an existing file, so poll while something is running.
        if !found.isEmpty, poll == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.scan() } }
            t.tolerance = 0.3
            RunLoop.main.add(t, forMode: .common)
            poll = t
        } else if found.isEmpty {
            poll?.invalidate()
            poll = nil
        }
    }
}

// MARK: - Shelf tools

enum ShelfTools {
    static func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        service.perform(withItems: urls)
    }

    static func isConvertibleImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && type != .svg
    }

    enum Format: String, CaseIterable {
        case jpeg, png
        var type: UTType { self == .jpeg ? .jpeg : .png }
        var ext: String { self == .jpeg ? "jpg" : "png" }
        var label: String { self == .jpeg ? "JPEG" : "PNG" }
    }

    /// Writes a converted copy next to the original (or in Downloads if that folder isn't writable).
    /// Never overwrites: picks "name 2.jpg" etc. Returns the new file.
    static func convert(_ url: URL, to format: Format) -> URL? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let fm = FileManager.default
        let folder = fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
            ? url.deletingLastPathComponent() : DownloadsService.downloadsURL
        let base = url.deletingPathExtension().lastPathComponent
        var target = folder.appendingPathComponent(base).appendingPathExtension(format.ext)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(format.ext)
            n += 1
        }
        guard let dest = CGImageDestinationCreateWithURL(target as CFURL, format.type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        let meta = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        if let orientation = meta?[kCGImagePropertyOrientation] { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? target : nil
    }
}

// MARK: - Formatting

extension Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

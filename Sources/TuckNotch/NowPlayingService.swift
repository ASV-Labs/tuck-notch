import AppKit
import Combine

// MARK: - Provider abstraction

enum MediaCommand {
    case playPause, next, previous

    var appleScriptVerb: String {
        switch self {
        case .playPause: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        }
    }
}

struct MediaSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var playing: Bool
    var artworkURL: String
    /// Overrides the provider name in the UI, e.g. "YouTube Music · Chrome".
    var sourceLabel: String = ""
}

struct ScriptFailure: Error {
    let code: Int
    /// errAEEventNotPermitted: the user declined (or hasn't granted) Automation access.
    var isPermissionDenied: Bool { code == -1743 }
    var isJavaScriptDisabled: Bool { code == BrowserMediaProvider.javaScriptDisabledCode }
}

/// A source of now-playing information. Providers must only use public, supported mechanisms;
/// anything that bypasses entitlements stays out of the required path.
protocol MediaProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var bundleID: String { get }
    /// Runs off the main thread.
    func snapshot() -> Result<MediaSnapshot?, ScriptFailure>
    func send(_ command: MediaCommand)
    func artwork(for snapshot: MediaSnapshot) -> NSImage?
}

/// Music and Spotify expose AppleScript dictionaries; this is public and permission-gated.
struct AppleScriptMediaProvider: MediaProvider {
    let id: String
    let displayName: String
    let bundleID: String
    let durationIsMilliseconds: Bool
    let artworkKind: ArtworkKind

    enum ArtworkKind: Sendable { case url, rawData }

    static let spotify = AppleScriptMediaProvider(id: "spotify", displayName: "Spotify", bundleID: "com.spotify.client",
                                                  durationIsMilliseconds: true, artworkKind: .url)
    static let music = AppleScriptMediaProvider(id: "music", displayName: "Music", bundleID: "com.apple.Music",
                                                durationIsMilliseconds: false, artworkKind: .rawData)

    func snapshot() -> Result<MediaSnapshot?, ScriptFailure> {
        let durationExpr = durationIsMilliseconds ? "((duration of t) / 1000)" : "(duration of t)"
        let artworkExpr = artworkKind == .url ? "(artwork url of t)" : "\"\""
        // `is running` guard: never relaunch a player that is quitting.
        // -1743 (Automation denied) is re-raised so the app can show the permission state.
        let script = """
        if application "\(displayName)" is not running then return "STOPPED"
        with timeout of 3 seconds
            tell application "\(displayName)"
                try
                    if player state is stopped then return "STOPPED"
                    set t to current track
                    return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & \(durationExpr) & linefeed & (player position) & linefeed & (player state as string) & linefeed & \(artworkExpr)
                on error errMsg number errNum
                    if errNum is -1743 then error errMsg number errNum
                    return "STOPPED"
                end try
            end tell
        end timeout
        """
        switch AppleScriptRunner.run(script) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let desc):
            guard let text = desc.stringValue, text != "STOPPED" else { return .success(nil) }
            let parts = text.components(separatedBy: "\n")
            guard parts.count >= 6 else { return .success(nil) }
            func number(_ s: String) -> Double {
                Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
            }
            return .success(MediaSnapshot(
                title: parts[0], artist: parts[1], album: parts[2],
                duration: number(parts[3]), position: number(parts[4]),
                playing: parts[5].lowercased().contains("playing"),
                artworkURL: parts.count > 6 ? parts[6] : ""
            ))
        }
    }

    func send(_ command: MediaCommand) {
        _ = AppleScriptRunner.run("""
        if application "\(displayName)" is running then
            with timeout of 3 seconds
                tell application "\(displayName)" to \(command.appleScriptVerb)
            end timeout
        end if
        """)
    }

    func artwork(for snapshot: MediaSnapshot) -> NSImage? {
        switch artworkKind {
        case .url:
            return nil   // fetched asynchronously by NowPlayingService (never on the AppleScript queue)
        case .rawData:
            let script = """
            if application "\(displayName)" is not running then return ""
            with timeout of 3 seconds
                tell application "\(displayName)"
                    try
                        return raw data of artwork 1 of current track
                    on error
                        return ""
                    end try
                end tell
            end timeout
            """
            guard case .success(let desc) = AppleScriptRunner.run(script) else { return nil }
            let data = desc.data
            return data.isEmpty ? nil : NSImage(data: data)
        }
    }
}

/// Runs AppleScript on the caller's thread. All callers use NowPlayingService's single serial queue.
/// Known, accepted risk: Apple lists NSAppleScript as main-thread-only. Running it on the main thread
/// would block the UI for up to the 3 s script timeout when a player hangs, so it stays on one
/// dedicated serial queue (never concurrently). Revisit if crashes show up in testing.
enum AppleScriptRunner {
    private static let lock = NSLock()
    private static var cache: [String: NSAppleScript] = [:]

    /// Compiled scripts are cached; the per-tick snapshot no longer recompiles.
    private static func compiled(_ source: String) -> NSAppleScript? {
        lock.lock(); defer { lock.unlock() }
        if let script = cache[source] { return script }
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        script.compileAndReturnError(&error)
        if cache.count > 32 { cache.removeAll() }   // volume commands have varying sources
        cache[source] = script
        return script
    }

    static func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptFailure> {
        guard let script = compiled(source) else { return .failure(ScriptFailure(code: -1)) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return .failure(ScriptFailure(code: (error[NSAppleScript.errorNumber] as? Int) ?? -1))
        }
        return .success(result)
    }
}

// MARK: - Service

/// Picks the best provider (playing beats paused), publishes state, and degrades gracefully:
/// no provider running → nothing shown; permission denied → a clear fix-it state.
@MainActor
final class NowPlayingService: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var sourceName: String
        var providerID: String
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    /// When `position` was last read, for smooth interpolation (lyrics, progress).
    private(set) var positionDate = Date()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var permissionDenied = false
    /// Browsers that have media tabs but refuse JavaScript from Apple Events (needs a one-time setting).
    @Published private(set) var browsersNeedingSetup: [BrowserMediaProvider] = []
    @Published var volume: Double = 50
    /// False when the current output (HDMI, some USB) has no software volume.
    @Published private(set) var volumeAvailable = true
    var isDraggingVolume = false

    /// Set while any panel is open so system volume is only polled when visible.
    var panelOpen = false {
        didSet { if panelOpen && !oldValue { refreshVolume(); poll(force: true) } }
    }

    static let supportedSourcesDescription = "Music, Spotify, or a web player in a browser you turned on in Settings › Media"

    /// Every provider Tuck Notch knows; `settings.mediaSources` decides which are used.
    static let allProviders: [MediaProvider] = [AppleScriptMediaProvider.spotify, AppleScriptMediaProvider.music]
        + BrowserMediaProvider.all

    private var providers: [MediaProvider] {
        let enabled = Set(AppSettings.shared.mediaSources)
        return Self.allProviders.filter { enabled.contains($0.id) }
    }
    /// No cookies, no disk cache: artwork fetches don't carry or leave state.
    nonisolated static let artworkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()
    nonisolated static let maxArtworkBytes = 4_000_000

    nonisolated static func fetchArtwork(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (bytes, response) = try? await artworkSession.bytes(for: request),
              (response.mimeType ?? "image/").hasPrefix("image/"),
              response.expectedContentLength <= Int64(maxArtworkBytes) else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxArtworkBytes { return nil }
            }
        } catch { return nil }
        return data
    }

    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "app.tucknotch.nowplaying", qos: .userInitiated)
    private var artworkKey = ""
    private var pollInFlight = false

    func start() {
        // 1 s while something plays; the timer is cheap when no player is running (no scripts run).
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.poll(force: true) }
            }
            observers.append(token)
        }
        let ws = NSWorkspace.shared.notificationCenter
        let quit = ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.poll(force: true) }
        }
        observers.append(quit)
        poll(force: true)
    }

    private func runningProviders() -> [MediaProvider] {
        providers.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
    }

    private var idleTicks = 0

    /// `force` bypasses the idle back-off (player notifications, user commands, panel opening).
    func poll(force: Bool = false) {
        if panelOpen && !isDraggingVolume { refreshVolume() }
        let running = runningProviders()
        guard !running.isEmpty else {
            if track != nil || permissionDenied || !browsersNeedingSetup.isEmpty {
                clear(); permissionDenied = false; browsersNeedingSetup = []
            }
            return
        }
        // Full 1 s polling only while a panel is open. Closed: every 3 s while playing (the
        // position is extrapolated between polls) and every 5 s when nothing plays. Music and
        // Spotify post notifications on every state change, and commands force a poll.
        if !force && !panelOpen {
            idleTicks += 1
            if idleTicks % (isPlaying ? 3 : 5) != 0 { return }
        }
        guard !pollInFlight else { return }
        pollInFlight = true

        queue.async { [weak self] in
            var results: [(MediaProvider, MediaSnapshot)] = []
            var denied = false
            var needSetup: [BrowserMediaProvider] = []
            for provider in running {
                switch provider.snapshot() {
                case .success(let snap): if let snap { results.append((provider, snap)) }
                case .failure(let f):
                    if f.isPermissionDenied { denied = true }
                    if f.isJavaScriptDisabled, let browser = provider as? BrowserMediaProvider { needSetup.append(browser) }
                }
            }
            let needSetupFinal = needSetup
            let pick = results.first(where: { $0.1.playing }) ?? results.first
            let pickedProvider = pick?.0
            let pickedSnapshot = pick?.1
            let deniedFinal = denied
            Task { @MainActor in
                guard let self else { return }
                self.pollInFlight = false
                self.permissionDenied = deniedFinal && pickedSnapshot == nil
                if self.browsersNeedingSetup.map(\.id) != needSetupFinal.map(\.id) {
                    self.browsersNeedingSetup = needSetupFinal
                }
                if let provider = pickedProvider, let snap = pickedSnapshot {
                    self.apply(snap, from: provider)
                } else {
                    self.clear()
                }
            }
        }
    }

    private func clear() {
        track = nil
        isPlaying = false
        position = 0
        artwork = nil
        artworkKey = ""
    }

    private func apply(_ snap: MediaSnapshot, from provider: MediaProvider) {
        let newTrack = Track(title: snap.title, artist: snap.artist, album: snap.album,
                             duration: snap.duration,
                             sourceName: snap.sourceLabel.isEmpty ? provider.displayName : snap.sourceLabel,
                             providerID: provider.id)
        if track != newTrack { track = newTrack }
        if isPlaying != snap.playing { isPlaying = snap.playing }
        position = snap.position
        positionDate = Date()

        let key = "\(provider.id)|\(snap.title)|\(snap.artist)|\(snap.album)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        if let url = URL(string: snap.artworkURL), url.scheme == "https" {
            Task { [weak self] in
                // Artwork URLs come from the player or page: stream with a hard size cap, images only.
                guard let data = await Self.fetchArtwork(url), let image = NSImage(data: data) else { return }
                guard let self, self.artworkKey == key else { return }
                self.artwork = image
            }
            return
        }
        queue.async { [weak self] in
            let image = provider.artwork(for: snap)
            Task { @MainActor in
                guard let self, self.artworkKey == key else { return }
                self.artwork = image
            }
        }
    }

    // MARK: Controls

    func send(_ command: MediaCommand) {
        guard let provider = providers.first(where: { $0.id == track?.providerID }) ?? runningProviders().first else { return }
        queue.async { [weak self] in
            provider.send(command)
            Task { @MainActor in
                self?.poll(force: true)
                // Web players swap tracks asynchronously; look again once the new one has loaded.
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                self?.poll(force: true)
            }
        }
    }

    func playPause() { send(.playPause) }
    func next() { send(.next) }
    func previous() { send(.previous) }

    func setVolume(_ value: Double) {
        volume = value
        let v = Int(value.rounded())
        queue.async { _ = AppleScriptRunner.run("set volume output volume \(v)") }
    }

    func refreshVolume() {
        queue.async { [weak self] in
            let script = """
            set v to output volume of (get volume settings)
            if v is missing value then return -1
            return v
            """
            guard case .success(let desc) = AppleScriptRunner.run(script) else { return }
            let raw = desc.int32Value
            Task { @MainActor in
                guard let self else { return }
                self.volumeAvailable = raw >= 0
                guard raw >= 0, !self.isDraggingVolume, self.volume != Double(raw) else { return }
                self.volume = Double(raw)
            }
        }
    }

    /// Playback position now, interpolated between polls while playing.
    func estimatedPosition(at date: Date = Date()) -> Double {
        guard isPlaying else { return position }
        let p = position + date.timeIntervalSince(positionDate)
        if let d = track?.duration, d > 0 { return min(d, p) }
        return p
    }

    /// Used only by the snapshot renderer to show sample content.
    func applyPreview(track: Track, playing: Bool, position: Double, artwork: NSImage?) {
        self.track = track
        self.isPlaying = playing
        self.position = position
        self.positionDate = Date()
        self.artwork = artwork
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

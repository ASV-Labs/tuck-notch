import AppKit
import Combine

/// One instance for the app. Owns every module and is the only place that turns module state
/// into activities for the engine. Modules never touch the island window directly.
@MainActor
final class Services {
    let settings: AppSettings
    let engine: ActivityEngine
    let nowPlaying: NowPlayingService
    let clipboard: ClipboardService
    let shelf: ShelfService
    let timer: TimerService
    let mic: MicService
    let battery: BatteryService
    let audio: AudioDeviceService
    let keepAwake: KeepAwakeService
    let inbox: ExternalActivityInbox
    let calendar: CalendarService
    let weather: WeatherService
    let lyrics: LyricsService
    let notion: NotionService
    let tasks: TasksService
    let stats: SystemStatsService
    let downloads: DownloadsService
    let updates: UpdateService

    var anyPanelOpen: @MainActor () -> Bool = { false }
    private var cancellables = Set<AnyCancellable>()
    private var minuteTimer: Timer?

    init() {
        settings = AppSettings.shared
        engine = ActivityEngine()
        nowPlaying = NowPlayingService()
        clipboard = ClipboardService(settings: AppSettings.shared)
        shelf = ShelfService()
        timer = TimerService()
        mic = MicService()
        battery = BatteryService()
        audio = AudioDeviceService()
        keepAwake = KeepAwakeService()
        inbox = ExternalActivityInbox(engine: engine)
        calendar = CalendarService()
        weather = WeatherService()
        lyrics = LyricsService()
        notion = NotionService()
        tasks = TasksService()
        stats = SystemStatsService()
        downloads = DownloadsService()
        updates = UpdateService(enabled: !AppDefaults.isSnapshotMode)
    }

    func start() {
        nowPlaying.start()
        clipboard.start()
        battery.start()
        audio.start()
        mic.refresh()
        audio.onInputChanged = { [weak self] in self?.mic.refresh() }
        calendar.start()
        weather.start()
        lyrics.start(nowPlaying: nowPlaying)
        notion.start()
        downloads.setEnabled(settings.trackDownloads)
        settings.$trackDownloads.dropFirst()
            .sink { [weak self] on in Task { @MainActor in self?.downloads.setEnabled(on) } }
            .store(in: &cancellables)
        downloads.onFinished = { [weak self] name in self?.downloadFinished(name) }

        registerHandlers()
        wireActivities()

        inbox.setEnabled(settings.acceptExternalActivities)
        settings.$acceptExternalActivities.dropFirst()
            .sink { [weak self] enabled in Task { @MainActor in self?.inbox.setEnabled(enabled) } }
            .store(in: &cancellables)

        applyPresentationMode(settings.presentationMode, announce: false)
        settings.$presentationMode.dropFirst()
            .sink { [weak self] on in Task { @MainActor in self?.applyPresentationMode(on) } }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publishKeepAwake() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        minuteTimer = t
    }

    func panelOpenChanged() {
        let open = anyPanelOpen()
        nowPlaying.panelOpen = open
        stats.setActive(open)
        if open { notion.refreshIfStale() }
    }

    // MARK: Presentation mode

    private func applyPresentationMode(_ on: Bool, announce: Bool = true) {
        engine.suppressed = on
        clipboard.temporarilyPaused = on
        if announce { A11y.announce(on ? "Presentation mode on" : "Presentation mode off") }
    }

    // MARK: Actions

    private func registerHandlers() {
        engine.registerHandler(source: "media") { [weak self] _, action in
            guard let self else { return }
            switch action {
            case "previous": self.nowPlaying.previous()
            case "playpause": self.nowPlaying.playPause()
            case "next": self.nowPlaying.next()
            default: break
            }
        }
        engine.registerHandler(source: "timer") { [weak self] _, action in
            guard let self else { return }
            switch action {
            case "toggle": self.timer.toggle()
            case "reset": self.timer.reset()
            case "restart": self.timer.reset(); self.timer.start()
            case "break": self.timer.set(.shortBreak, minutes: 5); self.timer.start()
            case "focus": self.timer.set(.focus, minutes: 25); self.timer.start()
            default: break   // "dismiss"
            }
        }
        engine.registerHandler(source: "downloads") { [weak self] id, action in
            guard action == "reveal", let name = self?.finishedDownloads[id] else { return }
            let url = DownloadsService.downloadsURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        engine.registerHandler(source: "mic") { [weak self] _, action in
            if action == "unmute", self?.mic.isMuted == true { self?.mic.toggle() }
        }
        engine.registerHandler(source: "awake") { [weak self] _, action in
            if action == "stop" { self?.keepAwake.stop() }
        }
        timer.onFinish = { [weak self] in
            guard let self else { return }
            let focus = self.timer.mode == .focus
            self.engine.raise(AttentionRequest(
                id: "timer.finished", source: "timer", symbol: "checkmark.circle.fill",
                title: "\(self.timer.mode.rawValue) finished",
                subtitle: focus ? "Time for a break" : "Ready to focus again",
                tint: .success, priority: .high,
                actions: focus
                    ? [ActivityAction(id: "break", title: "Break 5"), ActivityAction(id: "dismiss", title: "Done")]
                    : [ActivityAction(id: "focus", title: "Focus 25"), ActivityAction(id: "dismiss", title: "Done")],
                autoDismissAfter: 20
            ))
        }
    }

    // MARK: Module state → activities

    private func wireActivities() {
        Publishers.CombineLatest3(nowPlaying.$track, nowPlaying.$isPlaying, settings.$showMedia)
            .receive(on: RunLoop.main)
            .sink { [weak self] track, playing, show in
                Task { @MainActor in self?.publishMedia(track: track, playing: playing, show: show) }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(timer.$remaining, timer.$isRunning, timer.$finished, settings.$showTimer)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                Task { @MainActor in self?.publishTimer() }
            }
            .store(in: &cancellables)

        mic.$isMuted.combineLatest(mic.$available)
            .receive(on: RunLoop.main)
            .sink { [weak self] muted, available in
                Task { @MainActor in self?.publishMic(muted: muted && available) }
            }
            .store(in: &cancellables)

        downloads.$active
            .receive(on: RunLoop.main)
            .sink { [weak self] list in Task { @MainActor in self?.publishDownloads(list) } }
            .store(in: &cancellables)

        keepAwake.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in self?.publishKeepAwake() } }
            .store(in: &cancellables)
    }

    private func publishMedia(track: NowPlayingService.Track?, playing: Bool, show: Bool) {
        guard show, playing, let track else {
            engine.remove(id: "media")
            return
        }
        engine.upsert(Activity(
            id: "media", source: "media", symbol: "music.note",
            title: track.title,
            subtitle: track.artist.isEmpty ? track.sourceName : track.artist,
            tint: .live, priority: .normal,
            actions: [
                ActivityAction(id: "previous", title: "Previous", symbol: "backward.fill"),
                ActivityAction(id: "playpause", title: "Pause", symbol: "pause.fill"),
                ActivityAction(id: "next", title: "Next", symbol: "forward.fill")
            ]
        ))
    }

    private func publishTimer() {
        guard settings.showTimer, timer.isActive, !timer.finished else {
            engine.remove(id: "timer")
            return
        }
        let running = timer.isRunning
        engine.upsert(Activity(
            id: "timer", source: "timer",
            symbol: running ? "timer" : "pause.circle.fill",
            title: timer.mode.rawValue,
            subtitle: running ? (timer.mode == .focus ? "Until next break" : "Remaining") : "Paused",
            trailing: timer.formatted,
            progress: timer.progress,
            tint: .live, priority: .high,
            actions: [
                ActivityAction(id: "toggle", title: running ? "Pause" : "Resume", symbol: running ? "pause.fill" : "play.fill"),
                ActivityAction(id: "reset", title: "Reset", symbol: "arrow.counterclockwise")
            ]
        ))
    }

    private var publishedDownloads = Set<String>()

    private func publishDownloads(_ list: [DownloadsService.Download]) {
        // Ids carry a hash, not the file name, because activity ids are logged.
        func activityID(_ d: DownloadsService.Download) -> String { "download." + String(UInt(bitPattern: d.id.hashValue), radix: 36) }
        let ids = Set(list.map(activityID))
        for stale in publishedDownloads.subtracting(ids) { engine.remove(id: stale) }
        publishedDownloads = ids
        for d in list {
            var detail = Format.bytes(d.bytes)
            if let total = d.total { detail += " of " + Format.bytes(total) }
            if d.bytesPerSecond > 0 { detail += " · " + Format.bytes(Int64(d.bytesPerSecond)) + "/s" }
            engine.upsert(Activity(
                id: activityID(d), source: "downloads", symbol: "arrow.down.circle",
                title: d.name, subtitle: detail,
                trailing: d.progress.map { "\(Int(($0 * 100).rounded()))%" } ?? Format.bytes(d.bytes),
                progress: d.progress,
                tint: .accent, priority: .normal
            ))
        }
    }

    private var finishedDownloads: [String: String] = [:]   // attention id → file name

    private func downloadFinished(_ name: String) {
        let id = "download.finished." + UUID().uuidString
        finishedDownloads[id] = name
        if finishedDownloads.count > 20 { finishedDownloads.removeAll() ; finishedDownloads[id] = name }
        engine.raise(AttentionRequest(
            id: id, source: "downloads", symbol: "checkmark.circle.fill",
            title: "Downloaded", subtitle: name,
            tint: .success, priority: .normal,
            actions: [ActivityAction(id: "reveal", title: "Show in Finder"), ActivityAction(id: "dismiss", title: "OK")],
            autoDismissAfter: 6
        ))
    }

    private func publishMic(muted: Bool) {
        guard muted else {
            engine.remove(id: "mic")
            return
        }
        engine.upsert(Activity(
            id: "mic", source: "mic", symbol: "mic.slash.fill",
            title: "Microphone muted", subtitle: "Default input device",
            tint: .danger, priority: .high,
            actions: [ActivityAction(id: "unmute", title: "Unmute", symbol: "mic.fill")]
        ))
    }

    private func publishKeepAwake() {
        guard keepAwake.isActive else {
            engine.remove(id: "awake")
            return
        }
        engine.upsert(Activity(
            id: "awake", source: "awake", symbol: "cup.and.saucer.fill",
            title: "Keeping awake",
            subtitle: keepAwake.endsAt.map { "Until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Until turned off",
            trailing: keepAwake.remainingText,
            tint: .accent, priority: .low,
            actions: [ActivityAction(id: "stop", title: "Stop", symbol: "stop.fill")]
        ))
    }
}

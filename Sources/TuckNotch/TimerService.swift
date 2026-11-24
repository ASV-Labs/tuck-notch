import AppKit
import Combine

/// Pomodoro-style countdown that shows as a live activity in the collapsed notch.
@MainActor
final class TimerService: ObservableObject {
    enum Mode: String {
        case focus = "Focus"
        case shortBreak = "Break"
        case longBreak = "Long Break"
        case custom = "Timer"
    }

    @Published private(set) var mode: Mode = .focus
    @Published private(set) var duration: TimeInterval = 25 * 60
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var finished = false
    @Published var customMinutes = 10

    var onFinish: (@MainActor () -> Void)?

    private var endDate: Date?
    private var ticker: Timer?

    /// True while the timer is counting or paused part-way, or has just finished.
    var isActive: Bool { isRunning || finished || remaining < duration }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return 1 - remaining / duration
    }

    var formatted: String {
        Format.clock(remaining.rounded(.up))
    }

    func set(_ mode: Mode, minutes: Int) {
        stopTicker()
        self.mode = mode
        duration = TimeInterval(max(1, minutes) * 60)
        remaining = duration
        isRunning = false
        finished = false
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        if remaining <= 0 { remaining = duration }
        finished = false
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        A11y.announce("\(mode.rawValue) timer started")
    }

    func pause() {
        tick()
        stopTicker()
        isRunning = false
        A11y.announce("Timer paused")
    }

    func reset() {
        stopTicker()
        isRunning = false
        finished = false
        remaining = duration
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        stopTicker()
        isRunning = false
        finished = true
        remaining = 0
        NSSound(named: NSSound.Name("Glass"))?.play()
        A11y.announce("\(mode.rawValue) timer finished")
        onFinish?()
    }
}

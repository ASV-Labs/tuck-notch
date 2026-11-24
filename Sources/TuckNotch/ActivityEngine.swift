import os
import SwiftUI
import Combine

// MARK: - Model

enum ActivityPriority: Int, Comparable, Codable {
    case low = 0, normal = 1, high = 2, critical = 3

    static func < (a: ActivityPriority, b: ActivityPriority) -> Bool { a.rawValue < b.rawValue }

    init(string: String?) {
        switch string?.lowercased() {
        case "low": self = .low
        case "high": self = .high
        case "critical": self = .critical
        default: self = .normal
        }
    }
}

enum ActivityTint: String, Codable {
    case neutral, accent, live, success, warning, danger

    var color: Color {
        switch self {
        case .neutral: return DS.Palette.textSecondary
        case .accent: return DS.Palette.accent
        case .live: return DS.Palette.live
        case .success: return DS.Palette.success
        case .warning: return DS.Palette.warning
        case .danger: return DS.Palette.danger
        }
    }
}

struct ActivityAction: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    var symbol: String?
}

/// Anything that wants space in the island goes through the engine as an Activity.
/// Modules never resize or open the island window themselves.
struct Activity: Identifiable, Equatable {
    let id: String
    var source: String
    var symbol: String
    var title: String
    var subtitle: String?
    /// Short text for the right wing of the collapsed island (e.g. "18:42", "78%").
    var trailing: String?
    var progress: Double?
    var tint: ActivityTint = .neutral
    var priority: ActivityPriority = .normal
    var createdAt = Date()
    var expiresAt: Date?
    var actions: [ActivityAction] = []
}

/// A one-off interruption ("timer finished", "agent needs input").
/// Shown compactly without taking keyboard focus; auto-dismisses unless critical.
struct AttentionRequest: Identifiable, Equatable {
    let id: String
    var source: String
    var symbol: String
    var title: String
    var subtitle: String?
    var tint: ActivityTint = .accent
    var priority: ActivityPriority = .high
    var actions: [ActivityAction] = []
    var autoDismissAfter: TimeInterval? = 8
    var createdAt = Date()
}

// MARK: - Engine

@MainActor
final class ActivityEngine: ObservableObject {
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var attention: AttentionRequest?

    /// Presentation mode: hides live activities and holds non-critical interruptions.
    @Published var suppressed = false {
        didSet {
            if suppressed, let current = attention, current.priority < .critical {
                attention = nil
                attentionQueue.insert(current, at: 0)
            } else if !suppressed {
                showNextAttention()
            }
        }
    }

    typealias ActionHandler = @MainActor (_ itemID: String, _ actionID: String) -> Void
    private var handlers: [String: ActionHandler] = [:]
    private var attentionQueue: [AttentionRequest] = []
    private var dismissTask: Task<Void, Never>?
    private var sweepTimer: Timer?

    static let maxActivities = 24
    static let maxQueuedAttention = 10

    init() {
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweepExpired() }
        }
        RunLoop.main.add(t, forMode: .common)
        sweepTimer = t
    }

    /// Activities ordered for display: priority first, then oldest first so rows don't jump.
    var ordered: [Activity] {
        activities.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.createdAt < $1.createdAt
        }
    }

    /// The activity that owns the collapsed island, or nil when it should be dormant.
    var primary: Activity? { suppressed ? nil : ordered.first }

    func registerHandler(source: String, _ handler: @escaping ActionHandler) {
        handlers[source] = handler
    }

    func upsert(_ activity: Activity) {
        if let i = activities.firstIndex(where: { $0.id == activity.id }) {
            var updated = activity
            updated.createdAt = activities[i].createdAt   // keep position stable
            if activities[i] != updated { activities[i] = updated }
        } else {
            if activities.count >= Self.maxActivities,
               let drop = ordered.last, drop.priority <= activity.priority {
                remove(id: drop.id)
            }
            guard activities.count < Self.maxActivities else { return }
            activities.append(activity)
            Log.activity.debug("upsert \(activity.id, privacy: .public)")
        }
    }

    func remove(id: String) {
        activities.removeAll { $0.id == id }
    }

    /// Retracts an alert (queued or showing), e.g. when its publisher clears or resolves it.
    func withdrawAttention(id: String) {
        attentionQueue.removeAll { $0.id == id }
        if attention?.id == id { dismissAttention() }
    }

    func removeAll(source: String) {
        activities.removeAll { $0.source == source }
        attentionQueue.removeAll { $0.source == source }
        if attention?.source == source { dismissAttention() }
    }

    func raise(_ request: AttentionRequest) {
        attentionQueue.removeAll { $0.id == request.id }
        if let current = attention {
            if current.id == request.id {
                show(request)
            } else if request.priority > current.priority && !(suppressed && request.priority < .critical) {
                attentionQueue.insert(current, at: 0)
                show(request)
            } else {
                enqueue(request)
            }
        } else if suppressed && request.priority < .critical {
            enqueue(request)
        } else {
            show(request)
        }
    }

    func dismissAttention() {
        dismissTask?.cancel()
        attention = nil
        showNextAttention()
    }

    /// Routes a button press back to the module that owns the item.
    func perform(actionID: String, itemID: String, source: String) {
        handlers[source]?(itemID, actionID)
        if attention?.id == itemID { dismissAttention() }
    }

    // MARK: Private

    private func enqueue(_ request: AttentionRequest) {
        attentionQueue.append(request)
        attentionQueue.sort { $0.priority > $1.priority }
        if attentionQueue.count > Self.maxQueuedAttention { attentionQueue.removeLast() }
    }

    private func show(_ request: AttentionRequest) {
        dismissTask?.cancel()
        attention = request
        Log.activity.info("attention \(request.id, privacy: .public)")
        A11y.announce(request.subtitle.map { "\(request.title). \($0)" } ?? request.title)
        if let seconds = request.autoDismissAfter, request.priority < .critical {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled, self?.attention?.id == request.id else { return }
                self?.dismissAttention()
            }
        }
    }

    private func showNextAttention() {
        guard attention == nil, !attentionQueue.isEmpty else { return }
        let next: AttentionRequest?
        if suppressed {
            next = attentionQueue.first { $0.priority >= .critical }
        } else {
            next = attentionQueue.first
        }
        guard let next else { return }
        attentionQueue.removeAll { $0.id == next.id }
        show(next)
    }

    private func sweepExpired() {
        let now = Date()
        let expired = activities.filter { ($0.expiresAt ?? .distantFuture) <= now }
        guard !expired.isEmpty else { return }
        activities.removeAll { ($0.expiresAt ?? .distantFuture) <= now }
    }
}

// MARK: - Island state

/// The five presentation states. Computed in one place so no module can fight over the window.
enum IslandState: Equatable {
    case dormant
    case live
    case peek
    case expanded
    case attention
}

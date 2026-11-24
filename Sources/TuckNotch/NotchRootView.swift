import SwiftUI
import UniformTypeIdentifiers

/// The island. One shape that morphs between five states, so it reads as the notch itself
/// growing rather than a separate window appearing.
struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: ActivityEngine
    @EnvironmentObject private var shelf: ShelfService

    private var notchH: CGFloat { vm.metrics.height }

    private var state: IslandState {
        switch vm.presentation {
        case .expanded: return .expanded
        case .peek: return .peek
        case .closed:
            if engine.attention != nil { return .attention }
            if engine.primary != nil { return .live }
            return .dormant
        }
    }

    private var wingWidth: CGFloat {
        guard let p = engine.primary else { return 0 }
        return p.trailing != nil ? 58 : notchH + 8
    }

    private var bodySize: CGSize {
        switch state {
        case .dormant:
            return CGSize(width: vm.metrics.width + (vm.isDropTargeted ? 40 : 0), height: notchH)
        case .live:
            return CGSize(width: vm.metrics.width + wingWidth * 2, height: notchH)
        case .peek:
            return CGSize(width: max(DS.Size.peekWidth, vm.metrics.width + 120), height: notchH + PeekView.height)
        case .attention:
            return CGSize(width: max(DS.Size.attentionWidth, vm.metrics.width + 120), height: notchH + AttentionView.height)
        case .expanded:
            return CGSize(width: max(DS.Size.expandedWidth, vm.metrics.width + 200),
                          height: notchH + DS.Size.tabBarHeight + DS.Size.expandedContentHeight + DS.Space.l)
        }
    }

    private var topRadius: CGFloat { state == .expanded || state == .peek || state == .attention ? 10 : DS.Radius.flare }

    private var bottomRadius: CGFloat {
        switch state {
        case .expanded: return DS.Radius.panel
        case .peek, .attention: return 20
        default: return vm.metrics.hasNotch ? 10 : notchH / 2
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: vm.isDropTargeted) { targeted in
            if targeted && settings.showShelf {
                vm.expand(tab: .shelf, focus: false)
            } else if !targeted {
                vm.scheduleClose(after: 1.5)
            }
        }
        .onAppear { vm.islandSize = CGSize(width: bodySize.width + topRadius * 2, height: bodySize.height) }
        .onChange(of: bodySize) { size in vm.islandSize = CGSize(width: size.width + topRadius * 2, height: size.height) }
    }

    private var island: some View {
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        let isOpen = state == .peek || state == .expanded || state == .attention
        let alpha = isOpen ? DS.panelAlpha : 1   // dormant and live wings stay solid to blend with the notch
        return ZStack(alignment: .top) {
            ZStack {
                if alpha < 1, settings.panelBlur, !AppDefaults.isSnapshotMode {
                    BehindWindowBlur(strength: alpha)
                }
                shape.fill(DS.Palette.exterior.opacity(alpha))
            }
            .onTapGesture { tapped() }   // background only, so it never steals clicks from controls
            content
                .padding(.horizontal, topRadius)
                .transition(.opacity)
                .id(settings.appearanceKey)   // re-render with new appearance settings
        }
        .frame(width: bodySize.width + topRadius * 2, height: bodySize.height)
        .clipShape(shape)
        // A shadow under a see-through island would show through it and darken it, so it fades with opacity.
        .shadow(color: .black.opacity(state == .dormant || state == .live ? 0 : 0.45 * alpha * alpha), radius: 14, y: 6)
        .contentShape(shape)
        .onHover { inside in
            if inside && state == .attention { return }   // keep the alert's buttons where the pointer is going
            vm.hoverChanged(inside)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            guard settings.showShelf, !settings.presentationMode else { return false }
            return shelf.handle(providers)
        }
        .animation(DS.Motion.island, value: state)
        .animation(DS.Motion.island, value: bodySize.width)
        .accessibilityElement(children: state == .dormant || state == .live ? .ignore : .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(state == .dormant || state == .live ? .isButton : [])
        .accessibilityAction { vm.toggle(focus: true) }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .dormant:
            EmptyView()
        case .live:
            if let primary = engine.primary {
                LiveWingsView(activity: primary, wingWidth: wingWidth, height: notchH)
                    .allowsHitTesting(false)   // taps fall through to the island background
            }
        case .peek:
            PeekView(vm: vm)
        case .attention:
            if let request = engine.attention {
                AttentionView(request: request, notchHeight: notchH) {
                    vm.expand(tab: request.source == "timer" ? .timer : (request.source == "external" ? .activity : .home), focus: false)
                }
            }
        case .expanded:
            ExpandedView(vm: vm)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .dormant: return "Tuck Notch"
        case .live: return engine.primary.map { "Tuck Notch, \($0.title)" } ?? "Tuck Notch"
        case .peek: return "Tuck Notch quick view"
        case .attention: return engine.attention.map { "Tuck Notch alert, \($0.title)" } ?? "Tuck Notch"
        case .expanded: return "Tuck Notch panel"
        }
    }

    private func tapped() {
        switch state {
        case .dormant, .live, .peek: vm.expand(focus: true)
        case .attention, .expanded: break
        }
    }
}

// MARK: - Live (collapsed with wings)

struct LiveWingsView: View {
    let activity: Activity
    let wingWidth: CGFloat
    let height: CGFloat
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: wingWidth, alignment: .leading).padding(.leading, 6)
            Spacer(minLength: 0)
            trailing.frame(width: wingWidth, alignment: .trailing).padding(.trailing, 6)
        }
        .frame(height: height)
    }

    @ViewBuilder private var leading: some View {
        if activity.id == "media", settings.showWingArtwork, let art = nowPlaying.artwork {
            let side = max(14, height - 10)
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: activity.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.tint.color)
        }
    }

    @ViewBuilder private var trailing: some View {
        if let text = activity.trailing {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(activity.tint.color)
                .lineLimit(1)
                .fixedSize()
        } else if activity.id == "media" && settings.showEqualizer {
            EqualizerBars(animating: nowPlaying.isPlaying).frame(width: 16, height: 12)
        } else if let progress = activity.progress {
            ProgressRing(progress: progress, tint: activity.tint.color).frame(width: 14, height: 14)
        } else {
            Circle().fill(activity.tint.color).frame(width: 6, height: 6)
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
            Circle().trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

struct EqualizerBars: View {
    let animating: Bool

    var body: some View {
        if animating && !DS.reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                bars(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(t: nil)
        }
    }

    private func bars(t: Double?) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                let phase = Double(i) * 1.3
                let level = t.map { 0.35 + 0.65 * abs(sin($0 * 5 + phase)) } ?? 0.4
                Capsule()
                    .fill(DS.Palette.textPrimary)
                    .frame(width: 2.5, height: 12 * level)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Activity row (shared by Peek, Home and Activity)

struct ActivityRow: View {
    let activity: Activity
    var compact = false
    @EnvironmentObject private var engine: ActivityEngine
    @EnvironmentObject private var nowPlaying: NowPlayingService

    var body: some View {
        HStack(spacing: DS.Space.m) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(DS.Typeface.bodyMedium)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s)
            if let trailing = activity.trailing {
                Text(trailing)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(activity.tint.color)
            }
            HStack(spacing: 2) {
                ForEach(activity.actions.prefix(3)) { action in
                    actionButton(action)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var icon: some View {
        if activity.id == "media", let art = nowPlaying.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.Palette.elevated)
                if let progress = activity.progress {
                    ProgressRing(progress: progress, tint: activity.tint.color).padding(5)
                } else {
                    Image(systemName: activity.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(activity.tint.color)
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func actionButton(_ action: ActivityAction) -> some View {
        let symbol = action.id == "playpause" ? (nowPlaying.isPlaying ? "pause.fill" : "play.fill") : action.symbol
        if let symbol {
            Button { engine.perform(actionID: action.id, itemID: activity.id, source: activity.source) } label: {
                Image(systemName: symbol)
            }
            .buttonStyle(IconButtonStyle(size: DS.Size.hit))
            .help(action.title)
            .accessibilityLabel(action.id == "playpause" ? (nowPlaying.isPlaying ? "Pause" : "Play") : action.title)
        } else {
            Button(action.title) { engine.perform(actionID: action.id, itemID: activity.id, source: activity.source) }
                .buttonStyle(PillButtonStyle())
        }
    }
}

// MARK: - Peek

/// Hover state: the current activities and one-tap controls, without the full dashboard.
struct PeekView: View {
    static let height: CGFloat = 132

    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var engine: ActivityEngine
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var shelf: ShelfService
    @EnvironmentObject private var clipboard: ClipboardService
    @EnvironmentObject private var mic: MicService
    @EnvironmentObject private var battery: BatteryService
    @EnvironmentObject private var keepAwake: KeepAwakeService

    var body: some View {
        VStack(spacing: DS.Space.s) {
            HStack {
                HeaderLeading()
                Spacer()
                Color.clear.frame(width: vm.metrics.width)
                Spacer()
                HeaderTrailing()
            }
            .frame(height: vm.metrics.height)
            .padding(.horizontal, DS.Space.l)

            Group {
                if let first = engine.ordered.first, !settings.presentationMode {
                    ActivityRow(activity: first, compact: true)
                } else {
                    Text(settings.presentationMode ? "Presentation mode is on" : "All quiet")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
            }
            .padding(.horizontal, DS.Space.l)

            HStack(spacing: DS.Space.s) {
                QuickChip(symbol: "tray.full", label: shelf.items.isEmpty ? "Shelf" : "\(shelf.items.count)") {
                    vm.expand(tab: .shelf, focus: true)
                }
                QuickChip(symbol: "doc.on.clipboard", label: "Clips") { vm.expand(tab: .clipboard, focus: true) }
                if mic.available {
                    QuickChip(symbol: mic.isMuted ? "mic.slash.fill" : "mic.fill", label: mic.isMuted ? "Muted" : "Mic",
                              tint: mic.isMuted ? DS.Palette.danger : nil) { mic.toggle() }
                }
                QuickChip(symbol: "cup.and.saucer.fill", label: "Awake",
                          tint: keepAwake.isActive ? DS.Palette.accent : nil) {
                    keepAwake.isActive ? keepAwake.stop() : keepAwake.start(minutes: 60)
                }
                QuickChip(symbol: settings.presentationMode ? "eye.slash.fill" : "eye",
                          label: "Present", tint: settings.presentationMode ? DS.Palette.warning : nil) {
                    settings.presentationMode.toggle()
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.bottom, DS.Space.m)
        }
    }
}

struct QuickChip: View {
    let symbol: String
    let label: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(label).font(DS.Typeface.captionMedium).lineLimit(1)
            }
            .foregroundStyle(tint ?? DS.Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: DS.Size.hit)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Left of the camera: the wordmark (optional).
struct HeaderLeading: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if settings.showWordmark {
            Text("TUCK NOTCH")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(DS.Palette.textSecondary)
                .accessibilityHidden(true)
        }
    }
}

/// Right of the camera: clock and battery (each optional).
struct HeaderTrailing: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: DS.Space.s) {
            if settings.showClock {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(DS.Typeface.captionMedium)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if settings.showBatteryPercent { BatteryLabel().fixedSize() }
        }
    }
}

struct BatteryLabel: View {
    @EnvironmentObject private var battery: BatteryService

    var body: some View {
        if let percent = battery.percent {
            HStack(spacing: 4) {
                Image(systemName: battery.symbol)
                Text("\(percent)%").monospacedDigit()
            }
            .font(DS.Typeface.captionMedium)
            .foregroundStyle(percent <= 15 && !battery.onPower ? DS.Palette.danger : DS.Palette.textSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery \(percent) percent\(battery.onPower ? ", on power" : "")")
        }
    }
}

// MARK: - Attention

/// Interruptions: compact, actionable, never take keyboard focus.
struct AttentionView: View {
    static let height: CGFloat = 76

    let request: AttentionRequest
    let notchHeight: CGFloat
    let openDetails: () -> Void
    @EnvironmentObject private var engine: ActivityEngine

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: DS.Space.m) {
                Image(systemName: request.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(request.tint.color)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title)
                        .font(DS.Typeface.bodyMedium)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    if let subtitle = request.subtitle {
                        Text(subtitle)
                            .font(DS.Typeface.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: openDetails)
                Spacer(minLength: DS.Space.s)
                ForEach(request.actions.prefix(2)) { action in
                    Button(action.title) {
                        engine.perform(actionID: action.id, itemID: request.id, source: request.source)
                    }
                    .buttonStyle(PillButtonStyle(prominent: action.id == request.actions.first?.id))
                }
                Button { engine.dismissAttention() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, DS.Space.l)
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: ActivityEngine

    private var tabs: [NotchTab] { settings.enabledTabs }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, DS.Space.l)
                .padding(.top, DS.Space.s)
                .padding(.bottom, DS.Space.l)
                .id(vm.tab)
                .transition(.opacity)
        }
        .animation(DS.Motion.content, value: vm.tab)
        .overlay {
            if vm.showOnboarding {
                OnboardingCard(notchHeight: vm.metrics.height) { vm.finishOnboarding() }
                    .transition(.opacity)
            }
        }
        .background(shortcuts)
        .onExitCommand { vm.close() }
    }

    private var header: some View {
        HStack {
            HeaderLeading()
            if settings.presentationMode {
                Label("Presenting", systemImage: "eye.slash.fill")
                    .font(DS.Typeface.captionMedium)
                    .foregroundStyle(DS.Palette.warning)
                    .labelStyle(.iconOnly)
                    .help("Presentation mode is on")
            }
            Spacer()
            Color.clear.frame(width: vm.metrics.width)   // camera housing
            Spacer()
            HeaderTrailing()
        }
        .frame(height: vm.metrics.height)
        .padding(.horizontal, DS.Space.l)
    }

    private var tabBar: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(tabs) { tab in
                let selected = vm.tab == tab
                Button { vm.tab = tab } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 12, weight: .semibold))
                        if selected { Text(tab.title).font(DS.Typeface.captionMedium) }
                    }
                    .foregroundStyle(selected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                    .padding(.horizontal, DS.Space.s + 2)
                    .frame(height: DS.Size.hit)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(selected ? DS.Palette.elevated : Color.clear)
                    )
                    .overlay(alignment: .topTrailing) {
                        if tab == .activity, engine.activities.contains(where: { $0.source == "external" }) {
                            Circle().fill(DS.Palette.live).frame(width: 6, height: 6).offset(x: -3, y: 3)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            Button { AppDelegate.shared?.showSettings() } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(IconButtonStyle())
                .help("Settings")
                .accessibilityLabel("Settings")
        }
        .frame(height: DS.Size.tabBarHeight)
        .padding(.horizontal, DS.Space.m)
    }

    @ViewBuilder private var content: some View {
        switch vm.tab {
        case .home: HomeView(vm: vm)
        case .media: MediaView()
        case .calendar: CalendarTabView()
        case .notes: NotesTabView(vm: vm)
        case .shelf: ShelfView(vm: vm)
        case .clipboard: ClipboardView(vm: vm)
        case .timer: TimerView()
        case .activity: ActivityListView()
        }
    }

    /// ⌘1–⌘6 switch tabs while the panel has keyboard focus.
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(tabs.prefix(9).enumerated()), id: \.element) { index, tab in
                Button("") { vm.tab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

// MARK: - Onboarding

struct OnboardingCard: View {
    let notchHeight: CGFloat
    let done: () -> Void
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            DS.Palette.exterior.opacity(0.96)
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("Welcome to Tuck Notch")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                row("cursorarrow.rays", "Hover the notch for a quick view. Click it, or press \(settings.hotkey.label), for everything.")
                row("tray.and.arrow.down", "Drop files on the notch to keep them on the Shelf.")
                row("eye.slash", "Presenting? Turn on Presentation mode to hide the island and pause clipboard history.")
                HStack {
                    Spacer()
                    Button("Got it", action: done)
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.l)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .padding(.top, notchHeight)
        .padding([.horizontal, .bottom], DS.Space.s)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(DS.Palette.textPrimary)
            Text(text)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

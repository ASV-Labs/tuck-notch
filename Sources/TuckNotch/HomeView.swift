import SwiftUI

// MARK: - Home (user-chosen cards)

/// Shows up to four cards the user picked in Settings › Home, in their chosen order.
struct HomeView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let cards = settings.enabledHomeCards
        if cards.isEmpty {
            EmptyCardLabel(symbol: "square.grid.2x2", title: "No Home cards",
                           detail: "Choose cards in Settings › Home.")
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: DS.Space.s) {
                HStack(spacing: DS.Space.s) {
                    ForEach(cards.prefix(2)) { card($0) }
                }
                if cards.count > 2 {
                    HStack(spacing: DS.Space.s) {
                        ForEach(cards.dropFirst(2)) { card($0) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func card(_ card: HomeCard) -> some View {
        switch card {
        case .nowPlaying: NowPlayingCard(vm: vm)
        case .youtube: YouTubeCard(vm: vm)
        case .weather: WeatherCard(vm: vm)
        case .calendar: CalendarCard()
        case .todos: TodoCard(vm: vm)
        case .notes: NotesCard(vm: vm)
        case .pulse: PulseCard()
        case .focus: FocusCard(vm: vm)
        case .shelf: ShelfCard(vm: vm)
        case .controls: QuickControlsCard()
        case .activity: ActivityCard(vm: vm)
        }
    }
}

/// Small caption header used by every card.
struct CardHeader: View {
    let symbol: String
    let title: String
    var tint: Color = DS.Palette.textSecondary
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(DS.Typeface.captionMedium).foregroundStyle(DS.Palette.textSecondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Now playing

struct NowPlayingCard: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var nowPlaying: NowPlayingService

    var body: some View {
        Card {
            if let track = nowPlaying.track {
                HStack(spacing: DS.Space.m) {
                    ArtworkView(image: nowPlaying.artwork, size: 52, radius: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.sourceName).font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
                        Text(track.title).font(DS.Typeface.bodyMedium).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                        Text(track.artist).font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { nowPlaying.playPause() } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(IconButtonStyle(size: 32, active: true))
                    .accessibilityLabel(nowPlaying.isPlaying ? "Pause" : "Play")
                }
            } else {
                EmptyCardLabel(symbol: "music.note", title: "Nothing playing", detail: "Music, Spotify or YouTube")
            }
        }
        .onTapGesture { vm.tab = .media }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").foregroundStyle(DS.Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(DS.Palette.elevated)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: YouTube

struct YouTubeCard: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @State private var input = ""
    @FocusState private var focused: Bool

    private var youTubeTrack: NowPlayingService.Track? {
        guard let t = nowPlaying.track, t.sourceName.hasPrefix("YouTube") else { return nil }
        return t
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardHeader(symbol: "play.rectangle.fill", title: "YouTube", tint: Color(hex: 0xFF3B30),
                           trailing: youTubeTrack.map { _ in nowPlaying.isPlaying ? "Playing" : "Paused" })
                if let t = youTubeTrack {
                    HStack(spacing: DS.Space.s) {
                        ArtworkView(image: nowPlaying.artwork, size: 30, radius: 6)
                        Text(t.title).font(DS.Typeface.bodyMedium).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                        Button { nowPlaying.playPause() } label: {
                            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(IconButtonStyle(active: true))
                        .accessibilityLabel(nowPlaying.isPlaying ? "Pause" : "Play")
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "link").font(.system(size: 11)).foregroundStyle(DS.Palette.textSecondary)
                        TextField("Paste a URL, video ID or search", text: $input)
                            .textFieldStyle(.plain)
                            .font(DS.Typeface.body)
                            .focused($focused)
                            .onSubmit(open)
                            .accessibilityLabel("YouTube link, video ID or search")
                    }
                    .padding(.horizontal, DS.Space.s)
                    .frame(height: DS.Size.hit)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.elevated))
                }
                HStack(spacing: DS.Space.s) {
                    Button(youTubeTrack == nil ? "Open" : "Next") {
                        if youTubeTrack == nil { open() } else { nowPlaying.next() }
                    }
                    .buttonStyle(PillButtonStyle(prominent: true, compact: true))
                    Button("Browse") { YouTubeLink.open(URL(string: "https://www.youtube.com")!, browser: settings.youTubeBrowser) }
                        .buttonStyle(PillButtonStyle(compact: true))
                        .help("Open YouTube")
                    Button("Music") { YouTubeLink.open(URL(string: "https://music.youtube.com")!, browser: settings.youTubeBrowser) }
                        .buttonStyle(PillButtonStyle(compact: true))
                        .help("Open YouTube Music")
                }
            }
        }
        .onChange(of: focused) { vm.pinned = $0 }
    }

    private func open() {
        guard let url = YouTubeLink.url(for: input) else {
            YouTubeLink.open(URL(string: "https://www.youtube.com")!, browser: settings.youTubeBrowser)
            return
        }
        YouTubeLink.open(url, browser: settings.youTubeBrowser)
        input = ""
    }
}

enum YouTubeLink {
    /// URL, youtu.be link, bare 11-character video ID, or anything else as a search.
    static func url(for raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
           HostMatch.host(host, isOrIsUnderAnyOf: ["youtube.com", "youtu.be"]) {
            return url
        }
        if text.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil {
            return URL(string: "https://www.youtube.com/watch?v=\(text)")
        }
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: text)]
        return c.url
    }

    static func open(_ url: URL, browser: String) {
        guard browser != "default",
              let provider = BrowserMediaProvider.all.first(where: { $0.id == browser }),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: provider.bundleID) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: Weather

struct WeatherCard: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var weather: WeatherService

    var body: some View {
        Card {
            if !weather.isConfigured {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardHeader(symbol: "cloud.sun.fill", title: "Weather · pick your city")
                    CitySearchField(islandStyle: true, maxResults: 2,
                                    onFocusChange: { vm.pinned = $0 })
                }
            } else if let c = weather.current {
                let (summary, symbol) = WeatherService.describe(c.code, isDay: c.isDay)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(c.temperature.rounded()))°")
                            .font(DS.Typeface.display).foregroundStyle(DS.Palette.textPrimary)
                        Text(summary).font(DS.Typeface.body).foregroundStyle(DS.Palette.textSecondary)
                        HStack(spacing: 8) {
                            Text("H:\(Int(c.high.rounded()))°").foregroundStyle(DS.Palette.live)
                            Text("L:\(Int(c.low.rounded()))°").foregroundStyle(DS.Palette.accent)
                        }
                        .font(DS.Typeface.captionMedium)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 26))
                        Text(settings.weatherPlace.components(separatedBy: ",").first ?? "")
                            .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Int(c.temperature.rounded())) degrees, \(summary). High \(Int(c.high.rounded())), low \(Int(c.low.rounded())).")
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardHeader(symbol: "cloud.sun.fill", title: "Weather")
                    Text(weather.error ?? "Loading…").font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                    if weather.error != nil {
                        Button("Retry") { weather.refresh() }.buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
    }
}

// MARK: Calendar

struct CalendarCard: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var notion: NotionService

    private var merged: [CalendarService.Event] { Self.mergedEvents(calendar: calendar, notion: notion) }

    /// EventKit events (incl. Google via Internet Accounts) plus Notion items, in time order.
    @MainActor static func mergedEvents(calendar: CalendarService, notion: NotionService) -> [CalendarService.Event] {
        var all: [CalendarService.Event] = []
        if case .granted = calendar.access { all = calendar.events }
        all += notion.items.map { item in
            let end = item.end ?? (item.isAllDay
                ? Calendar.current.date(byAdding: .day, value: 1, to: item.start) ?? item.start
                : item.start.addingTimeInterval(3600))
            return CalendarService.Event(id: "notion-" + item.id, title: item.title, start: item.start, end: end,
                                         isAllDay: item.isAllDay, color: DS.Palette.textSecondary,
                                         joinURL: item.joinURL, joinService: item.joinService, openURL: item.url)
        }
        let cal = Calendar.current
        return all.sorted { a, b in
            let da = cal.startOfDay(for: a.start), db = cal.startOfDay(for: b.start)
            if da != db { return da < db }
            if a.isAllDay != b.isAllDay { return !a.isAllDay }  // within a day: timed first, then all-day
            return a.start < b.start
        }
    }

    private var hasAnySource: Bool {
        if case .granted = calendar.access { return true }
        return !notion.items.isEmpty || notion.isReady
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardHeader(symbol: "calendar", title: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                if hasAnySource {
                    let rows = merged
                    if rows.isEmpty {
                        Text("Nothing coming up").font(DS.Typeface.body).foregroundStyle(DS.Palette.textSecondary)
                    } else {
                        ForEach(rows.prefix(2)) { event in row(event) }
                    }
                } else {
                switch calendar.access {
                case .notConnected, .notDetermined:
                    Text("See your next meetings and join calls in one click.")
                        .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                    Button("Connect Calendar") { calendar.connect() }.buttonStyle(PillButtonStyle())
                case .denied:
                    Text("Calendar access is off for Tuck Notch.")
                        .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                    Button("Open Privacy Settings") { calendar.openPrivacySettings() }.buttonStyle(PillButtonStyle())
                case .granted:
                    EmptyView()
                }
                }
            }
        }
    }

    private func subtitle(_ e: CalendarService.Event) -> String {
        let source = e.openURL != nil ? " · Notion" : ""
        let cal = Calendar.current
        let dayPrefix = cal.isDateInToday(e.start) || e.isHappening ? "" : AgendaGrouping.label(for: cal.startOfDay(for: e.start)) + " "
        if e.isAllDay { return (dayPrefix.isEmpty ? "Today" : dayPrefix.trimmingCharacters(in: .whitespaces)) + source }
        if e.isHappening { return "Now · until \(Self.time.string(from: e.end))" + source }
        return dayPrefix + Self.time.string(from: e.start) + source
    }

    private func row(_ e: CalendarService.Event) -> some View {
        HStack(spacing: DS.Space.s) {
            Circle().fill(e.color).frame(width: 6, height: 6)
            Button {
                if let url = e.openURL { NSWorkspace.shared.open(url) }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.title).font(DS.Typeface.bodyMedium).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                    Text(subtitle(e))
                        .font(DS.Typeface.caption)
                        .foregroundStyle(e.isHappening && !e.isAllDay ? DS.Palette.live : DS.Palette.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(e.openURL == nil ? "" : "Open in Notion")
            Spacer(minLength: 0)
            if let url = e.joinURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Join", systemImage: "video.fill").font(DS.Typeface.captionMedium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Palette.success)
                .padding(.horizontal, DS.Space.s)
                .frame(minHeight: DS.Size.hit)
                .background(Capsule().fill(DS.Palette.success.opacity(0.16)))
                .help("Join on \(e.joinService ?? "the call")")
                .accessibilityLabel("Join \(e.title) on \(e.joinService ?? "video call")")
            }
        }
    }
}

// MARK: Focus, Shelf, Activity

struct FocusCard: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var timer: TimerService

    var body: some View {
        Card {
            HStack(spacing: DS.Space.m) {
                ProgressRing(progress: timer.progress, tint: DS.Palette.live).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.isActive ? timer.mode.rawValue : "Focus session")
                        .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                    Text(timer.formatted).font(DS.Typeface.metric).monospacedDigit().foregroundStyle(DS.Palette.textPrimary)
                    Text(timer.isRunning ? "Until next break" : (timer.isActive ? "Paused" : "Ready"))
                        .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Button { timer.toggle() } label: { Image(systemName: timer.isRunning ? "pause.fill" : "play.fill") }
                    .buttonStyle(IconButtonStyle(size: 32, active: true))
                    .accessibilityLabel(timer.isRunning ? "Pause timer" : "Start timer")
            }
        }
        .onTapGesture { vm.tab = .timer }
    }
}

struct ShelfCard: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var shelf: ShelfService

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader(symbol: "tray.full", title: "File shelf")
                Text(shelf.items.count == 1 ? "1 file" : "\(shelf.items.count) files")
                    .font(DS.Typeface.metric).foregroundStyle(DS.Palette.textPrimary)
                Text(shelf.items.isEmpty ? "Drop files on the notch" : "Ready to drag")
                    .font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .onTapGesture { vm.tab = .shelf }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct ActivityCard: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject private var engine: ActivityEngine

    var body: some View {
        Card {
            if let top = engine.ordered.first(where: { $0.source == "external" }) {
                ActivityRow(activity: top, compact: true)
            } else {
                EmptyCardLabel(symbol: "bolt.horizontal.circle", title: "No activity", detail: "Scripts and agents post here")
            }
        }
        .onTapGesture { vm.tab = .activity }
    }
}

// MARK: - City search (island card and Settings)

/// A clearly boxed search field with live results and status.
/// `islandStyle` uses the island's dark tokens; otherwise it follows the system appearance (Settings).
struct CitySearchField: View {
    @EnvironmentObject private var weather: WeatherService
    var islandStyle = false
    var maxResults = 5
    var onFocusChange: ((Bool) -> Void)? = nil
    var onChoose: (() -> Void)? = nil

    @State private var query = ""
    @FocusState private var focused: Bool

    private var primary: Color { islandStyle ? DS.Palette.textPrimary : .primary }
    private var secondary: Color { islandStyle ? DS.Palette.textSecondary : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(secondary)
                TextField("", text: $query, prompt: Text("Type a city, e.g. Lisbon").foregroundColor(secondary))
                    .textFieldStyle(.plain)
                    .foregroundStyle(primary)
                    .focused($focused)
                    .onSubmit { weather.search(query, immediate: true) }
                    .onChange(of: query) { weather.search($0) }
                    .accessibilityLabel("City name")
                if weather.searchState == .searching {
                    ProgressView().controlSize(.small)
                } else if !query.isEmpty {
                    Button { query = ""; weather.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .font(islandStyle ? DS.Typeface.body : .body)
            .padding(.horizontal, 8)
            .frame(height: islandStyle ? DS.Size.hit : 30)
            .background(
                RoundedRectangle(cornerRadius: islandStyle ? DS.Radius.control : 7, style: .continuous)
                    .fill(islandStyle ? DS.Palette.elevated : Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: islandStyle ? DS.Radius.control : 7, style: .continuous)
                    .strokeBorder(focused ? (islandStyle ? DS.Palette.accent : Color.accentColor) : secondary.opacity(0.35),
                                  lineWidth: focused ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            switch weather.searchState {
            case .idle, .searching:
                EmptyView()
            case .noMatches:
                Text("No cities match “\(query)”.").font(.caption).foregroundStyle(secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
            case .results:
                ForEach(weather.searchResults.prefix(maxResults)) { place in
                    Button {
                        weather.choose(place)
                        query = ""
                        focused = false
                        onChoose?()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(islandStyle ? DS.Palette.accent : Color.accentColor)
                            Text(place.name).fontWeight(.medium).foregroundStyle(primary)
                            Text(place.detail).foregroundStyle(secondary).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(islandStyle ? DS.Typeface.caption : .callout)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(place.name), \(place.detail)")
                }
            }
        }
        .onChange(of: focused) { onFocusChange?($0) }
    }
}

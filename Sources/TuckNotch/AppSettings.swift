import Foundation
import Combine
import Carbon.HIToolbox
import SwiftUI
import AppKit

/// The panels the expanded island can show.
enum NotchTab: String, CaseIterable, Identifiable {
    case home, media, calendar, notes, shelf, clipboard, timer, activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .media: return "Media"
        case .calendar: return "Calendar"
        case .notes: return "Notes"
        case .shelf: return "Shelf"
        case .clipboard: return "Clipboard"
        case .timer: return "Focus"
        case .activity: return "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .notes: return "checklist"
        case .shelf: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .timer: return "timer"
        case .activity: return "bolt.horizontal.circle"
        }
    }
}

/// Global shortcut choices (a full recorder can replace this later).
enum HotkeyPreset: Int, CaseIterable, Identifiable {
    case controlOptionK = 0, controlOptionSpace, optionCommandN, controlCommandN

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .controlOptionK: return "⌃⌥K"
        case .controlOptionSpace: return "⌃⌥Space"
        case .optionCommandN: return "⌥⌘N"
        case .controlCommandN: return "⌃⌘N"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .controlOptionK: return UInt32(kVK_ANSI_K)
        case .controlOptionSpace: return UInt32(kVK_Space)
        case .optionCommandN, .controlCommandN: return UInt32(kVK_ANSI_N)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .controlOptionK, .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .optionCommandN: return UInt32(optionKey | cmdKey)
        case .controlCommandN: return UInt32(controlKey | cmdKey)
        }
    }
}

// MARK: - Appearance options

enum AccentChoice: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, teal, graphite
    var id: String { rawValue }
    var label: String { rawValue == "system" ? "System" : rawValue.capitalized }
    var color: Color {
        switch self {
        case .system: return Color(nsColor: .controlAccentColor)
        case .blue: return Color(hex: 0x0A84FF)
        case .purple: return Color(hex: 0xBF5AF2)
        case .pink: return Color(hex: 0xFF375F)
        case .red: return Color(hex: 0xFF453A)
        case .orange: return Color(hex: 0xFF9F0A)
        case .yellow: return Color(hex: 0xFFD60A)
        case .green: return Color(hex: 0x30D158)
        case .teal: return Color(hex: 0x40C8E0)
        case .graphite: return Color(hex: 0x98989D)
        }
    }
}

enum SurfaceStyle: String, CaseIterable, Identifiable {
    case graphite, black, tinted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .graphite: return "Graphite"
        case .black: return "True Black"
        case .tinted: return "Tinted"
        }
    }
}

enum PanelSize: String, CaseIterable, Identifiable {
    case compact, standard, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var width: CGFloat { switch self { case .compact: return 440; case .standard: return 480; case .large: return 540 } }
    var contentHeight: CGFloat { switch self { case .compact: return 220; case .standard: return 236; case .large: return 264 } }
}

enum CornerStyle: String, CaseIterable, Identifiable {
    case subtle, standard, round
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var panel: CGFloat { switch self { case .subtle: return 16; case .standard: return 22; case .round: return 30 } }
    var card: CGFloat { switch self { case .subtle: return 10; case .standard: return 14; case .round: return 18 } }
    var control: CGFloat { switch self { case .subtle: return 6; case .standard: return 8; case .round: return 12 } }
}

enum TextSizeChoice: String, CaseIterable, Identifiable {
    case standard, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var delta: CGFloat { self == .large ? 2 : 0 }
}

enum MotionStyle: String, CaseIterable, Identifiable {
    case spring, smooth, minimal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .spring: return "Springy"
        case .smooth: return "Smooth"
        case .minimal: return "Minimal"
        }
    }
}

enum HoverDelay: String, CaseIterable, Identifiable {
    case quick, normal, relaxed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var nanoseconds: UInt64 {
        switch self {
        case .quick: return 150_000_000
        case .normal: return 250_000_000
        case .relaxed: return 450_000_000
        }
    }
}

enum HomeCard: String, CaseIterable, Identifiable {
    case nowPlaying, youtube, weather, calendar, todos, notes, pulse, focus, shelf, controls, activity
    var id: String { rawValue }
    var label: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .youtube: return "YouTube"
        case .weather: return "Weather"
        case .calendar: return "Calendar"
        case .todos: return "To-dos"
        case .notes: return "Notes"
        case .pulse: return "Pulse (CPU, memory, battery)"
        case .focus: return "Focus Timer"
        case .shelf: return "File Shelf"
        case .controls: return "Quick Controls"
        case .activity: return "Activity"
        }
    }
    var symbol: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .youtube: return "play.rectangle.fill"
        case .weather: return "cloud.sun.fill"
        case .calendar: return "calendar"
        case .todos: return "checklist"
        case .notes: return "note.text"
        case .pulse: return "waveform.path.ecg"
        case .focus: return "timer"
        case .shelf: return "tray.full"
        case .controls: return "switch.2"
        case .activity: return "bolt.horizontal.circle"
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var label: String { self == .fahrenheit ? "°F" : "°C" }
}

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = AppDefaults.store

    // Panels
    @Published var showMedia: Bool { didSet { save(showMedia, Keys.showMedia) } }
    @Published var showShelf: Bool { didSet { save(showShelf, Keys.showShelf) } }
    @Published var showClipboard: Bool { didSet { save(showClipboard, Keys.showClipboard) } }
    @Published var showTimer: Bool { didSet { save(showTimer, Keys.showTimer) } }
    @Published var showCalendarTab: Bool { didSet { save(showCalendarTab, Keys.showCalendarTab) } }
    @Published var showNotesTab: Bool { didSet { save(showNotesTab, Keys.showNotesTab) } }
    /// Opt-in: watch ~/Downloads for in-progress browser downloads (macOS asks for folder access).
    @Published var trackDownloads: Bool { didSet { save(trackDownloads, Keys.trackDownloads) } }

    // Behaviour
    @Published var openOnHover: Bool { didSet { save(openOnHover, Keys.openOnHover) } }
    @Published var showOnAllDisplays: Bool { didSet { save(showOnAllDisplays, Keys.showOnAllDisplays) } }
    @Published var hotkey: HotkeyPreset { didSet { save(hotkey.rawValue, Keys.hotkey) } }

    // Privacy
    @Published var presentationMode: Bool { didSet { save(presentationMode, Keys.presentationMode) } }
    @Published var hideFromScreenSharing: Bool { didSet { save(hideFromScreenSharing, Keys.hideFromScreenSharing) } }
    @Published var clipboardPaused: Bool { didSet { save(clipboardPaused, Keys.clipboardPaused) } }
    @Published var clipboardMaxItems: Int { didSet { save(clipboardMaxItems, Keys.clipboardMaxItems) } }
    /// 0 = keep until quit.
    @Published var clipboardExpiryHours: Int { didSet { save(clipboardExpiryHours, Keys.clipboardExpiryHours) } }
    @Published var excludedApps: [String] { didSet { save(excludedApps, Keys.excludedApps) } }

    // Developer
    @Published var acceptExternalActivities: Bool { didSet { save(acceptExternalActivities, Keys.acceptExternalActivities) } }

    @Published var hasOnboarded: Bool { didSet { save(hasOnboarded, Keys.hasOnboarded) } }

    // Media sources (provider ids)
    @Published var mediaSources: [String] { didSet { save(mediaSources, Keys.mediaSources) } }

    // Appearance
    @Published var accent: AccentChoice { didSet { save(accent.rawValue, Keys.accent) } }
    @Published var activityColor: AccentChoice { didSet { save(activityColor.rawValue, Keys.activityColor) } }
    @Published var surface: SurfaceStyle { didSet { save(surface.rawValue, Keys.surface) } }
    @Published var panelSize: PanelSize { didSet { save(panelSize.rawValue, Keys.panelSize) } }
    @Published var corners: CornerStyle { didSet { save(corners.rawValue, Keys.corners) } }
    @Published var textSize: TextSizeChoice { didSet { save(textSize.rawValue, Keys.textSize) } }
    @Published var motion: MotionStyle { didSet { save(motion.rawValue, Keys.motion) } }
    @Published var hoverDelay: HoverDelay { didSet { save(hoverDelay.rawValue, Keys.hoverDelay) } }
    @Published var showWingArtwork: Bool { didSet { save(showWingArtwork, Keys.showWingArtwork) } }
    @Published var showEqualizer: Bool { didSet { save(showEqualizer, Keys.showEqualizer) } }
    @Published var showWordmark: Bool { didSet { save(showWordmark, Keys.showWordmark) } }
    @Published var showBatteryPercent: Bool { didSet { save(showBatteryPercent, Keys.showBatteryPercent) } }

    // Home & integrations
    @Published var homeCards: [String] { didSet { save(homeCards, Keys.homeCards) } }
    @Published var showClock: Bool { didSet { save(showClock, Keys.showClock) } }
    /// Background opacity of the open island (0.3…1). Dormant and live wings stay solid to match the notch.
    @Published var panelOpacity: Double { didSet { save(panelOpacity, Keys.panelOpacity) } }
    /// Frost (blur) what's behind the open island. Off = clear glass you can actually see through.
    @Published var panelBlur: Bool { didSet { save(panelBlur, Keys.panelBlur) } }
    @Published var lyricsEnabled: Bool { didSet { save(lyricsEnabled, Keys.lyricsEnabled) } }
    @Published var calendarEnabled: Bool { didSet { save(calendarEnabled, Keys.calendarEnabled) } }
    @Published var weatherEnabled: Bool { didSet { save(weatherEnabled, Keys.weatherEnabled) } }
    @Published var weatherPlace: String { didSet { save(weatherPlace, Keys.weatherPlace) } }
    @Published var weatherLatitude: Double { didSet { save(weatherLatitude, Keys.weatherLatitude) } }
    @Published var weatherLongitude: Double { didSet { save(weatherLongitude, Keys.weatherLongitude) } }
    @Published var temperatureUnit: TemperatureUnit { didSet { save(temperatureUnit.rawValue, Keys.temperatureUnit) } }
    /// "default", or a browser provider id ("chrome", "safari", ...).
    @Published var youTubeBrowser: String { didSet { save(youTubeBrowser, Keys.youTubeBrowser) } }
    // Notion (the secret itself is in the Keychain)
    @Published var notionDataSourceID: String { didSet { save(notionDataSourceID, Keys.notionDataSourceID) } }
    @Published var notionDataSourceName: String { didSet { save(notionDataSourceName, Keys.notionDataSourceName) } }
    @Published var notionDateProperty: String { didSet { save(notionDateProperty, Keys.notionDateProperty) } }

    static let defaultHomeCards = ["nowPlaying", "youtube", "weather", "calendar"]
    static let maxHomeCards = 4

    var enabledHomeCards: [HomeCard] {
        homeCards.compactMap(HomeCard.init(rawValue:)).filter { card in
            switch card {
            case .nowPlaying: return showMedia
            case .focus: return showTimer
            case .shelf: return showShelf
            case .activity: return acceptExternalActivities
            default: return true
            }
        }.prefix(Self.maxHomeCards).map { $0 }
    }

    func toggleHomeCard(_ card: HomeCard) {
        if let i = homeCards.firstIndex(of: card.rawValue) {
            homeCards.remove(at: i)
        } else {
            homeCards.append(card.rawValue)
        }
    }

    func moveHomeCard(_ card: HomeCard, by offset: Int) {
        guard let i = homeCards.firstIndex(of: card.rawValue) else { return }
        let j = max(0, min(homeCards.count - 1, i + offset))
        guard i != j else { return }
        homeCards.swapAt(i, j)
    }

    /// Browsers are opt-in for new installs: scanning them sends Apple Events and triggers an
    /// Automation prompt, so the user turns them on in Settings › Media when they want them.
    static let defaultMediaSources = ["spotify", "music"]
    private static let legacyMediaSources = ["spotify", "music", "chrome", "safari"]

    /// Changes whenever any appearance option changes; the island re-renders on it.
    var appearanceKey: String {
        [accent.rawValue, activityColor.rawValue, surface.rawValue, panelSize.rawValue, corners.rawValue,
         textSize.rawValue, motion.rawValue,
         "\(showWingArtwork)\(showEqualizer)\(showWordmark)\(showBatteryPercent)\(showClock)",
         String(format: "%.2f", panelOpacity), "\(panelBlur)"]
            .joined(separator: "|")
    }

    func resetAppearance() {
        accent = .blue
        activityColor = .orange
        surface = .graphite
        panelSize = .standard
        corners = .standard
        textSize = .standard
        motion = .spring
        hoverDelay = .normal
        showWingArtwork = true
        showEqualizer = true
        showWordmark = true
        showBatteryPercent = true
        showClock = true
        panelOpacity = 1
        panelBlur = false
    }

    private enum Keys {
        static let showMedia = "showMedia"
        static let showShelf = "showShelf"
        static let showClipboard = "showClipboard"
        static let showTimer = "showTimer"
        static let showCalendarTab = "showCalendarTab"
        static let showNotesTab = "showNotesTab"
        static let trackDownloads = "trackDownloads"
        static let openOnHover = "openOnHover"
        static let showOnAllDisplays = "showOnAllDisplays"
        static let hotkey = "hotkeyPreset"
        static let presentationMode = "presentationMode"
        static let hideFromScreenSharing = "hideFromScreenSharing"
        static let clipboardPaused = "clipboardPaused"
        static let clipboardMaxItems = "clipboardMaxItems"
        static let clipboardExpiryHours = "clipboardExpiryHours"
        static let excludedApps = "excludedApps"
        static let acceptExternalActivities = "acceptExternalActivities"
        static let hasOnboarded = "hasOnboarded"
        static let mediaSources = "mediaSources"
        static let mediaDefaultsDecided = "mediaDefaultsDecided"
        static let accent = "appearance.accent"
        static let activityColor = "appearance.activityColor"
        static let surface = "appearance.surface"
        static let panelSize = "appearance.panelSize"
        static let corners = "appearance.corners"
        static let textSize = "appearance.textSize"
        static let motion = "appearance.motion"
        static let hoverDelay = "behaviour.hoverDelay"
        static let showWingArtwork = "appearance.showWingArtwork"
        static let showEqualizer = "appearance.showEqualizer"
        static let showWordmark = "appearance.showWordmark"
        static let showBatteryPercent = "appearance.showBatteryPercent"
        static let homeCards = "home.cards"
        static let showClock = "appearance.showClock"
        static let panelOpacity = "appearance.panelOpacity"
        static let panelBlur = "appearance.panelFrost"   // new key in 0.5.3: clear glass is the default
        static let lyricsEnabled = "media.lyrics"
        static let calendarEnabled = "integrations.calendar"
        static let weatherEnabled = "integrations.weather"
        static let weatherPlace = "integrations.weather.place"
        static let weatherLatitude = "integrations.weather.lat"
        static let weatherLongitude = "integrations.weather.lon"
        static let temperatureUnit = "integrations.weather.unit"
        static let youTubeBrowser = "integrations.youtube.browser"
        static let notionDataSourceID = "integrations.notion.dataSource"
        static let notionDataSourceName = "integrations.notion.dataSourceName"
        static let notionDateProperty = "integrations.notion.dateProperty"
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private init() {
        // Installs from before 0.5 had browsers on by default; keep that for them. Decided once,
        // on the first 0.5+ launch, so a new install never flips browsers on later.
        if defaults.object(forKey: Keys.mediaDefaultsDecided) == nil {
            if defaults.object(forKey: Keys.mediaSources) == nil, defaults.object(forKey: Keys.hasOnboarded) != nil {
                defaults.set(AppSettings.legacyMediaSources, forKey: Keys.mediaSources)
            }
            defaults.set(true, forKey: Keys.mediaDefaultsDecided)
        }
        defaults.register(defaults: [
            Keys.showMedia: true,
            Keys.showShelf: true,
            Keys.showClipboard: true,
            Keys.showTimer: true,
            Keys.showCalendarTab: true,
            Keys.showNotesTab: true,
            Keys.trackDownloads: false,
            Keys.openOnHover: true,
            Keys.showOnAllDisplays: false,
            Keys.hotkey: HotkeyPreset.controlOptionK.rawValue,
            Keys.presentationMode: false,
            Keys.hideFromScreenSharing: true,
            Keys.clipboardPaused: false,
            Keys.clipboardMaxItems: 60,
            Keys.clipboardExpiryHours: 0,
            Keys.excludedApps: [String](),
            Keys.acceptExternalActivities: false,
            Keys.hasOnboarded: false,
            Keys.mediaSources: AppSettings.defaultMediaSources,
            Keys.showWingArtwork: true,
            Keys.showEqualizer: true,
            Keys.showWordmark: true,
            Keys.showBatteryPercent: true,
            Keys.homeCards: AppSettings.defaultHomeCards,
            Keys.showClock: true,
            Keys.panelOpacity: 1.0,
            Keys.panelBlur: false,
            Keys.lyricsEnabled: false,
            Keys.calendarEnabled: false,
            Keys.weatherEnabled: false,
            Keys.weatherPlace: "",
            Keys.temperatureUnit: Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius",
            Keys.youTubeBrowser: "default"
        ])
        showMedia = defaults.bool(forKey: Keys.showMedia)
        showShelf = defaults.bool(forKey: Keys.showShelf)
        showClipboard = defaults.bool(forKey: Keys.showClipboard)
        showTimer = defaults.bool(forKey: Keys.showTimer)
        showCalendarTab = defaults.bool(forKey: Keys.showCalendarTab)
        showNotesTab = defaults.bool(forKey: Keys.showNotesTab)
        trackDownloads = defaults.bool(forKey: Keys.trackDownloads)
        openOnHover = defaults.bool(forKey: Keys.openOnHover)
        showOnAllDisplays = defaults.bool(forKey: Keys.showOnAllDisplays)
        hotkey = HotkeyPreset(rawValue: defaults.integer(forKey: Keys.hotkey)) ?? .controlOptionK
        presentationMode = defaults.bool(forKey: Keys.presentationMode)
        hideFromScreenSharing = defaults.bool(forKey: Keys.hideFromScreenSharing)
        clipboardPaused = defaults.bool(forKey: Keys.clipboardPaused)
        clipboardMaxItems = max(10, defaults.integer(forKey: Keys.clipboardMaxItems))
        clipboardExpiryHours = max(0, defaults.integer(forKey: Keys.clipboardExpiryHours))
        excludedApps = defaults.stringArray(forKey: Keys.excludedApps) ?? []
        acceptExternalActivities = defaults.bool(forKey: Keys.acceptExternalActivities)
        hasOnboarded = defaults.bool(forKey: Keys.hasOnboarded)
        mediaSources = defaults.stringArray(forKey: Keys.mediaSources) ?? AppSettings.defaultMediaSources
        accent = AccentChoice(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .blue
        activityColor = AccentChoice(rawValue: defaults.string(forKey: Keys.activityColor) ?? "") ?? .orange
        surface = SurfaceStyle(rawValue: defaults.string(forKey: Keys.surface) ?? "") ?? .graphite
        panelSize = PanelSize(rawValue: defaults.string(forKey: Keys.panelSize) ?? "") ?? .standard
        corners = CornerStyle(rawValue: defaults.string(forKey: Keys.corners) ?? "") ?? .standard
        textSize = TextSizeChoice(rawValue: defaults.string(forKey: Keys.textSize) ?? "") ?? .standard
        motion = MotionStyle(rawValue: defaults.string(forKey: Keys.motion) ?? "") ?? .spring
        hoverDelay = HoverDelay(rawValue: defaults.string(forKey: Keys.hoverDelay) ?? "") ?? .normal
        showWingArtwork = defaults.bool(forKey: Keys.showWingArtwork)
        showEqualizer = defaults.bool(forKey: Keys.showEqualizer)
        showWordmark = defaults.bool(forKey: Keys.showWordmark)
        showBatteryPercent = defaults.bool(forKey: Keys.showBatteryPercent)
        homeCards = defaults.stringArray(forKey: Keys.homeCards) ?? AppSettings.defaultHomeCards
        showClock = defaults.bool(forKey: Keys.showClock)
        panelOpacity = min(1, max(0.3, defaults.double(forKey: Keys.panelOpacity)))
        panelBlur = defaults.bool(forKey: Keys.panelBlur)
        lyricsEnabled = defaults.bool(forKey: Keys.lyricsEnabled)
        calendarEnabled = defaults.bool(forKey: Keys.calendarEnabled)
        weatherEnabled = defaults.bool(forKey: Keys.weatherEnabled)
        weatherPlace = defaults.string(forKey: Keys.weatherPlace) ?? ""
        weatherLatitude = defaults.double(forKey: Keys.weatherLatitude)
        weatherLongitude = defaults.double(forKey: Keys.weatherLongitude)
        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Keys.temperatureUnit) ?? "") ?? .fahrenheit
        youTubeBrowser = defaults.string(forKey: Keys.youTubeBrowser) ?? "default"
        notionDataSourceID = defaults.string(forKey: Keys.notionDataSourceID) ?? ""
        notionDataSourceName = defaults.string(forKey: Keys.notionDataSourceName) ?? ""
        notionDateProperty = defaults.string(forKey: Keys.notionDateProperty) ?? ""
    }

    func isSourceEnabled(_ id: String) -> Bool { mediaSources.contains(id) }

    func setSource(_ id: String, enabled: Bool) {
        if enabled, !mediaSources.contains(id) { mediaSources.append(id) }
        if !enabled { mediaSources.removeAll { $0 == id } }
    }

    func isEnabled(_ tab: NotchTab) -> Bool {
        switch tab {
        case .home: return true
        case .media: return showMedia
        case .calendar: return showCalendarTab
        case .notes: return showNotesTab
        case .shelf: return showShelf
        case .clipboard: return showClipboard
        case .timer: return showTimer
        case .activity: return acceptExternalActivities
        }
    }

    var enabledTabs: [NotchTab] { NotchTab.allCases.filter { isEnabled($0) } }
}

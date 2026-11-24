import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Window

enum SettingsPane: Int, CaseIterable, Identifiable {
    case general, appearance, home, media, privacy, advanced
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .home: return "Home"
        case .media: return "Media"
        case .privacy: return "Privacy"
        case .advanced: return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .home: return "square.grid.2x2"
        case .media: return "music.note"
        case .privacy: return "hand.raised"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct SettingsActions {
    var clearClipboard: () -> Void
    var clearPins: () -> Void
    var clearShelf: () -> Void
    var replayOnboarding: () -> Void
}

/// Native toolbar-style preferences window (one tab per pane).
@MainActor
final class SettingsWindowController: NSWindowController {
    static let paneSize = CGSize(width: 600, height: 560)
    private let tabs = NSTabViewController()

    init(services: Services, actions: SettingsActions) {
        tabs.tabStyle = .toolbar
        // Keep the app's name in the title bar instead of the (untitled) pane controllers' titles.
        tabs.canPropagateSelectedChildViewControllerTitle = false
        for pane in SettingsPane.allCases {
            let root = SettingsPaneView(pane: pane, actions: actions)
                .environmentObject(services.settings)
                .environmentObject(services.nowPlaying)
                .environmentObject(services.calendar)
                .environmentObject(services.weather)
                .environmentObject(services.notion)
                .environmentObject(services.updates)
                .frame(width: Self.paneSize.width, height: Self.paneSize.height)
            let host = NSHostingController(rootView: root)
            host.title = pane.title
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.title = "Tuck Notch Settings"
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ pane: SettingsPane?) {
        if let pane { tabs.selectedTabViewItemIndex = pane.rawValue }
        // Tuck Notch is a menu-bar (accessory) app, so it has to pull itself forward explicitly.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct SettingsPaneView: View {
    let pane: SettingsPane
    let actions: SettingsActions

    var body: some View {
        switch pane {
        case .general: GeneralPane(actions: actions)
        case .appearance: AppearancePane()
        case .home: HomePane()
        case .media: MediaPane()
        case .privacy: PrivacyPane(actions: actions)
        case .advanced: AdvancedPane()
        }
    }
}

/// Short grey explanatory text under a section.
private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updates: UpdateService
    let actions: SettingsActions
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section("Island") {
                Toggle("Quick view when the pointer rests on the notch", isOn: $settings.openOnHover)
                Picker("Quick view delay", selection: $settings.hoverDelay) {
                    ForEach(HoverDelay.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.openOnHover)
                Picker("Keyboard shortcut", selection: $settings.hotkey) {
                    ForEach(HotkeyPreset.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show a floating island on displays without a notch", isOn: $settings.showOnAllDisplays)
            }

            Section {
                Toggle(isOn: $settings.showMedia) { Label("Media", systemImage: "music.note") }
                Toggle(isOn: $settings.showCalendarTab) { Label("Calendar", systemImage: "calendar") }
                Toggle(isOn: $settings.showNotesTab) { Label("To-dos & notes", systemImage: "checklist") }
                Toggle(isOn: $settings.showShelf) { Label("Shelf", systemImage: "tray.full") }
                Toggle(isOn: $settings.showClipboard) { Label("Clipboard", systemImage: "doc.on.clipboard") }
                Toggle(isOn: $settings.showTimer) { Label("Focus timer", systemImage: "timer") }
            } header: {
                Text("Panels")
            } footer: {
                Footnote("Switch panels with ⌘1 – ⌘8 while the island is open. To-dos and notes are saved on this Mac only.")
            }

            Section {
                Toggle(isOn: $settings.trackDownloads) { Label("Browser downloads", systemImage: "arrow.down.circle") }
            } header: {
                Text("Live activities")
            } footer: {
                Footnote("Shows progress while Chrome, Safari, Arc, Brave, Edge or Firefox download into your Downloads folder. macOS asks once for access to Downloads. Tuck Notch lists the folder and reads names and sizes of in-progress downloads only.")
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section {
                if updates.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                    LabeledContent("Updates") {
                        Button("Check Now") { updates.checkNow() }.disabled(!updates.canCheck)
                    }
                } else {
                    LabeledContent("Updates", value: "Not available in source builds")
                }
            } header: {
                Text("Updates")
            } footer: {
                Footnote(updates.isAvailable
                    ? "Updates come from Tuck Notch's GitHub releases. Each one is signed by ASV Labs and notarized by Apple, and Tuck Notch checks the signature before installing. Checking asks GitHub once a day for the latest version; nothing else is sent."
                    : "This build was compiled from source, so it doesn't update itself. Pull the latest code, or install the signed release from GitHub to get automatic updates.")
            }

            Section {
                LabeledContent("Version", value: version)
                LabeledContent("License", value: "Apache 2.0 · © ASV Labs LLC")
                Button("Show Welcome Again", action: actions.replayOnboarding)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription). Move Tuck Notch to Applications and try again."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                IslandPreview()
                    .id(settings.appearanceKey)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }

            Section("Colors") {
                colorPicker("Accent", selection: $settings.accent)
                colorPicker("Live activity", selection: $settings.activityColor)
            }

            Section("Style") {
                segmented("Surfaces", $settings.surface, SurfaceStyle.allCases) { $0.label }
                segmented("Panel size", $settings.panelSize, PanelSize.allCases) { $0.label }
                segmented("Corners", $settings.corners, CornerStyle.allCases) { $0.label }
                segmented("Text size", $settings.textSize, TextSizeChoice.allCases) { $0.label }
                segmented("Animation", $settings.motion, MotionStyle.allCases) { $0.label }
                LabeledContent("Opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.panelOpacity, in: 0.3...1, step: 0.05)
                            .frame(maxWidth: 220)
                            .accessibilityLabel("Island background opacity")
                            .accessibilityValue("\(Int((settings.panelOpacity * 100).rounded())) percent")
                        Text("\(Int((settings.panelOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Frosted glass (blur what's behind)", isOn: $settings.panelBlur)
                    .disabled(settings.panelOpacity >= 1)
                    .help("Off: clear glass, you see exactly what's behind. On: frosted, easier to read over busy windows.")
                if DS.reduceTransparency || DS.highContrast {
                    Footnote("Reduce Transparency or Increase Contrast is on in System Settings › Accessibility, so the island stays solid.")
                }
            }

            Section {
                Toggle("Album art beside the notch while music plays", isOn: $settings.showWingArtwork)
                Toggle("Equalizer bars", isOn: $settings.showEqualizer)
                Toggle("Clock in the header", isOn: $settings.showClock)
                Toggle("Battery percentage", isOn: $settings.showBatteryPercent)
                Toggle("“TUCK NOTCH” wordmark", isOn: $settings.showWordmark)
            } header: {
                Text("Details")
            } footer: {
                Footnote("The island's outline always stays pure black so it blends with the camera housing. Reduce Motion and Increase Contrast in Accessibility settings take priority.")
            }

            Section {
                Button("Restore Default Appearance") { settings.resetAppearance() }
            }
        }
        .formStyle(.grouped)
    }

    private func colorPicker(_ title: String, selection: Binding<AccentChoice>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AccentChoice.allCases) { choice in
                Label {
                    Text(choice.label)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(choice.color)
                }
                .tag(choice)
            }
        }
    }

    private func segmented<T: Hashable & Identifiable>(_ title: String, _ selection: Binding<T>, _ options: [T],
                                                       label: @escaping (T) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { Text(label($0)).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// A small, static rendering of the expanded island using the current tokens.
private struct IslandPreview: View {
    var body: some View {
        let width: CGFloat = 340
        VStack(spacing: 8) {
            HStack {
                Capsule().fill(DS.Palette.textSecondary.opacity(0.5)).frame(width: 46, height: 5)
                Spacer()
                Capsule().fill(Color.black).frame(width: 70, height: 14)   // camera housing
                Spacer()
                Capsule().fill(DS.Palette.textSecondary.opacity(0.5)).frame(width: 30, height: 5)
            }
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: DS.Radius.control * 0.6, style: .continuous)
                        .fill(i == 0 ? DS.Palette.elevated : Color.clear)
                        .overlay(Circle().fill(i == 0 ? DS.Palette.textPrimary : DS.Palette.textSecondary).frame(width: 5, height: 5))
                        .frame(width: 22, height: 16)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                previewCard {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5).fill(
                            LinearGradient(colors: [DS.Palette.accent, DS.Palette.live], startPoint: .topLeading, endPoint: .bottomTrailing)
                        ).frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(DS.Palette.textPrimary).frame(width: 52, height: 5)
                            Capsule().fill(DS.Palette.textSecondary).frame(width: 34, height: 4)
                            Capsule().fill(DS.Palette.live).frame(width: 60, height: 3)
                        }
                    }
                }
                previewCard {
                    HStack(spacing: 6) {
                        ProgressRing(progress: 0.62, tint: DS.Palette.live).frame(width: 22, height: 22)
                        Text("18:42").font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Palette.textPrimary)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: width)
        .background(
            UnevenRoundedRectangleCompat(bottomRadius: DS.Radius.panel * 0.7)
                .fill(Color.black.opacity(DS.panelAlpha))
        )
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    private func previewCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card * 0.7, style: .continuous).fill(DS.Palette.surface.opacity(DS.cardAlpha)))
    }
}

/// Square top, rounded bottom (UnevenRoundedRectangle needs macOS 14).
private struct UnevenRoundedRectangleCompat: Shape {
    let bottomRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Home

private struct HomePane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var weather: WeatherService
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var notion: NotionService
    @State private var notionSecret = ""

    var body: some View {
        Form {
            Section {
                ForEach(orderedCards) { card in
                    HStack {
                        Toggle(isOn: Binding(get: { settings.homeCards.contains(card.rawValue) },
                                             set: { _ in settings.toggleHomeCard(card) })) {
                            Label(card.label, systemImage: card.symbol)
                        }
                        Spacer()
                        if settings.homeCards.contains(card.rawValue) {
                            Button { settings.moveHomeCard(card, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Move \(card.label) up")
                            Button { settings.moveHomeCard(card, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Move \(card.label) down")
                        }
                    }
                }
            } header: {
                Text("Home cards")
            } footer: {
                Footnote("The first four enabled cards appear on Home, in this order.")
            }

            Section {
                if weather.isConfigured {
                    LabeledContent("City") {
                        HStack {
                            Text(settings.weatherPlace)
                            Button("Remove") { weather.removeCity() }.buttonStyle(.borderless)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(weather.isConfigured ? "Change city" : "Choose your city")
                    CitySearchField()
                }
                Picker("Units", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Weather")
            } footer: {
                Footnote("Forecasts come from Open-Meteo (free, no account). What you type in the search box is sent to find the city; after that, only its coordinates are sent, every 30 minutes.")
            }

            Section {
                LabeledContent("Status", value: calendarStatus)
                HStack {
                    switch calendar.access {
                    case .notConnected, .notDetermined:
                        Button("Connect Calendar") { calendar.connect() }
                    case .denied:
                        Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                    case .granted:
                        Button("Disconnect") { settings.calendarEnabled = false; calendar.reload() }
                    }
                }
                if case .granted = calendar.access, !calendar.accountNames.isEmpty {
                    LabeledContent("Accounts", value: calendar.accountNames.joined(separator: ", "))
                }
                LabeledContent("Google Calendar") {
                    Button("Add Google Account…") { calendar.openInternetAccounts() }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Footnote("Shows the next three days of events from the calendars on this Mac, with a Join button for Zoom, Meet, Teams, Webex, FaceTime and Whereby links. Nothing leaves your Mac.\n\nGoogle Calendar: click Add Google Account…, choose Google, sign in, and leave Calendars switched on. macOS syncs it for free and Tuck Notch picks it up automatically, no extra login here.")
            }

            notionSection

            Section {
                Picker("Open links in", selection: $settings.youTubeBrowser) {
                    Text("Default browser").tag("default")
                    ForEach(BrowserMediaProvider.all.filter(\.isInstalled), id: \.id) { b in
                        Text(BrowserMediaProvider.shortBrowserName(b.displayName)).tag(b.id)
                    }
                }
            } header: {
                Text("YouTube")
            }
        }
        .formStyle(.grouped)
        .onAppear { calendar.refreshAccess() }
    }

    @ViewBuilder private var notionSection: some View {
        Section {
            if !notion.hasSecret {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Create an internal integration in Notion and copy its secret.")
                    Button("Open Notion integrations") {
                        if let url = URL(string: "https://www.notion.so/profile/integrations") { NSWorkspace.shared.open(url) }
                    }
                    Text("2. In Notion, open your calendar or tasks database › ••• › Connections, and add the integration.")
                    Text("3. Paste the secret here:")
                    HStack {
                        SecureField("", text: $notionSecret, prompt: Text("ntn_… or secret_…"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(connectNotion)
                        Button("Connect", action: connectNotion)
                            .keyboardShortcut(.defaultAction)
                            .disabled(notionSecret.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.vertical, 4)
            } else {
                LabeledContent("Status", value: notionStatus)
                if notion.dataSources.isEmpty {
                    LabeledContent("Database") {
                        Button("Look again") { notion.loadDataSources() }
                    }
                } else {
                    Picker("Database", selection: Binding(
                        get: { settings.notionDataSourceID },
                        set: { id in if let src = notion.dataSources.first(where: { $0.id == id }) { notion.select(src) } })) {
                        if settings.notionDataSourceID.isEmpty { Text("Choose…").tag("") }
                        ForEach(notion.dataSources) { Text($0.title).tag($0.id) }
                    }
                    if let src = notion.dataSources.first(where: { $0.id == settings.notionDataSourceID }) {
                        if src.dateProperties.isEmpty {
                            Text("This database has no Date property, so there's nothing to put on a calendar.")
                                .font(.caption).foregroundStyle(.orange)
                        } else {
                            Picker("Date property", selection: Binding(
                                get: { settings.notionDateProperty },
                                set: { settings.notionDateProperty = $0; notion.refresh() })) {
                                ForEach(src.dateProperties, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                }
                HStack {
                    Button("Refresh") { notion.loadDataSources(); notion.refresh() }
                    Button("Disconnect", role: .destructive) { notion.disconnect() }
                }
            }
            if case .failed(let message) = notion.status {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Notion")
        } footer: {
            Footnote("Items from one Notion database for the next three days appear in Calendar next to your events. The secret is stored in your Mac's Keychain and only sent to api.notion.com. Read-only: Tuck Notch never changes your Notion pages.")
        }
    }

    private func connectNotion() {
        notion.connect(secret: notionSecret)
        notionSecret = ""
    }

    private var notionStatus: String {
        switch notion.status {
        case .notConnected: return "Not connected"
        case .working: return "Connecting…"
        case .connected:
            if settings.notionDataSourceName.isEmpty { return "Connected — choose a database" }
            return "Connected · \(notion.items.count) item\(notion.items.count == 1 ? "" : "s") today"
        case .failed: return "Problem"
        }
    }

    /// Enabled cards in their order, then the rest.
    private var orderedCards: [HomeCard] {
        let enabled = settings.homeCards.compactMap(HomeCard.init(rawValue:))
        return enabled + HomeCard.allCases.filter { !enabled.contains($0) }
    }

    private var calendarStatus: String {
        switch calendar.access {
        case .notConnected: return "Not connected"
        case .notDetermined: return "Waiting for permission"
        case .denied: return "Access denied in Privacy settings"
        case .granted: return "Connected"
        }
    }
}

// MARK: - Media

private struct MediaPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var nowPlaying: NowPlayingService

    private struct AppSource: Identifiable {
        let id: String
        let name: String
        let symbol: String
    }

    private static let apps = [AppSource(id: "music", name: "Music", symbol: "music.note"),
                               AppSource(id: "spotify", name: "Spotify", symbol: "music.note.list")]

    var body: some View {
        Form {
            Section {
                ForEach(Self.apps) { app in
                    sourceToggle(id: app.id, title: app.name, symbol: app.symbol, note: nil)
                }
                ForEach(BrowserMediaProvider.all, id: \.id) { b in
                    sourceToggle(id: b.id, title: BrowserMediaProvider.shortBrowserName(b.displayName),
                                 symbol: b.engine == .safari ? "safari" : "globe",
                                 note: b.isInstalled ? nil : "Not installed")
                }
            } header: {
                Text("Sources")
            } footer: {
                Footnote("Browsers show YouTube, YouTube Music, SoundCloud and other web players. Tuck Notch reads the address of each open tab and only runs its script in tabs on known media sites. Controls click that site's buttons.")
            }

            Section {
                ForEach(BrowserMediaProvider.all.filter { $0.isInstalled && settings.isSourceEnabled($0.id) }, id: \.id) { b in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(BrowserMediaProvider.shortBrowserName(b.displayName)).font(.headline)
                            if nowPlaying.browsersNeedingSetup.contains(where: { $0.id == b.id }) {
                                Text("Needs this setting").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Footnote(b.setupInstructions)
                    }
                }
            } header: {
                Text("Browser setup (one time)")
            } footer: {
                Footnote("This browser setting lets Tuck Notch read the page's “now playing” details. macOS also asks once for permission to control each browser.")
            }

            Section {
                Toggle("Show synced lyrics", isOn: $settings.lyricsEnabled)
            } header: {
                Text("Lyrics")
            } footer: {
                Footnote("Lyrics come from LRCLIB (free, community-run). When on, the song title and artist are sent to look them up.")
            }

            Section {
                Button("Open Automation Settings…") { nowPlaying.openAutomationSettings() }
            } header: {
                Text("Permissions")
            } footer: {
                Footnote("If a player or browser stops updating, make sure Tuck Notch is allowed to control it here.")
            }
        }
        .formStyle(.grouped)
    }

    private func sourceToggle(id: String, title: String, symbol: String, note: String?) -> some View {
        Toggle(isOn: Binding(get: { settings.isSourceEnabled(id) }, set: { settings.setSource(id, enabled: $0) })) {
            HStack {
                Label(title, systemImage: symbol)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    @EnvironmentObject private var settings: AppSettings
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                Toggle("Presentation mode", isOn: $settings.presentationMode)
            } footer: {
                Footnote("Hides live activities, holds non-critical alerts, stops quick view on hover and pauses clipboard history. Turn it on whenever you share your screen.")
            }

            Section("Clipboard history") {
                Toggle("Pause recording", isOn: $settings.clipboardPaused)
                Picker("Keep up to", selection: $settings.clipboardMaxItems) {
                    Text("20 items").tag(20)
                    Text("60 items").tag(60)
                    Text("200 items").tag(200)
                }
                Picker("Forget items after", selection: $settings.clipboardExpiryHours) {
                    Text("Never (until quit)").tag(0)
                    Text("1 hour").tag(1)
                    Text("24 hours").tag(24)
                }
                HStack {
                    Button("Clear History", action: actions.clearClipboard)
                    Button("Clear History and Pins", action: actions.clearPins)
                }
            }

            Section {
                ForEach(settings.excludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(appName(bundleID))
                        Spacer()
                        Button("Remove") { settings.excludedApps.removeAll { $0 == bundleID } }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…", action: addExcludedApp)
            } header: {
                Text("Never record copies made in")
            } footer: {
                Footnote("Password managers (Keychain Access, Passwords, 1Password, Bitwarden, LastPass, Dashlane, KeePassXC) and anything marked concealed are always skipped. This lowers the risk of recording secrets; it can't guarantee it.")
            }

            Section {
                Toggle("Ask screen capture to skip the island", isOn: $settings.hideFromScreenSharing)
                Button("Clear Shelf", action: actions.clearShelf)
            } footer: {
                Footnote("Some capture tools ignore this request, so use Presentation mode when it matters. History stays in memory; pinned clipboard text and shelf file paths are saved in Tuck Notch's preferences, and to-dos and notes in Application Support, on this Mac only.")
            }
        }
        .formStyle(.grouped)
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.excludedApps.contains(id) {
                settings.excludedApps.append(id)
            }
        }
    }
}

// MARK: - Advanced

private struct AdvancedPane: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show activity from scripts and agents", isOn: $settings.acceptExternalActivities)
            } header: {
                Text("Activity feed")
            } footer: {
                Footnote("Lets your own tools put status in the island: a build finishing, a server going down, an AI agent waiting for approval. A script writes a small file to the Inbox folder and it appears as a live activity, with optional buttons. Button presses are written to the Outbox folder. Nothing listens on the network.")
            }

            Section("Feed folders") {
                LabeledContent("Inbox") { Button("Reveal in Finder") { reveal(ExternalActivityInbox.inboxURL) } }
                LabeledContent("Outbox") { Button("Reveal in Finder") { reveal(ExternalActivityInbox.outboxURL) } }
                Text("tools/tucknotch-activity post --id build --title \"Build\" --state running")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section {
                Footnote("Logs use the subsystem com.asvlabs.tucknotch in Console.app.")
            } header: {
                Text("Diagnostics")
            }
        }
        .formStyle(.grouped)
    }

    private func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

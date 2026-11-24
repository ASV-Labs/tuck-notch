import AppKit
import Combine
import EventKit
import Security
import SwiftUI
import os

// MARK: - Calendar

/// Today's upcoming events from the Mac's calendars (EventKit), with meeting-link detection.
/// Opt-in: nothing is read until the user connects it, and macOS asks for permission once.
@MainActor
final class CalendarService: ObservableObject {
    enum Access { case notConnected, notDetermined, granted, denied }

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: Color
        let joinURL: URL?
        let joinService: String?
        /// Where clicking the title goes (Notion page). nil for EventKit events.
        var openURL: URL? = nil

        var isHappening: Bool { start <= Date() && end > Date() }
    }

    @Published private(set) var events: [Event] = []
    /// Days of this month (1…31) that have at least one event, for the month grid's dots.
    @Published private(set) var busyDays: Set<Int> = []
    /// Today plus the next two days.
    nonisolated static let agendaDays = 3

    /// Accounts that provide calendars on this Mac (iCloud, Google, Exchange…), for Settings.
    @Published private(set) var accountNames: [String] = []
    @Published private(set) var access: Access = .notConnected

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
        AppSettings.shared.$calendarEnabled
            .sink { [weak self] _ in Task { @MainActor in self?.reload() } }
            .store(in: &cancellables)
    }

    private static var isAuthorized: Bool {
        // 3 == .authorized (≤ macOS 13) and .fullAccess (macOS 14+).
        EKEventStore.authorizationStatus(for: .event).rawValue == 3
    }

    func refreshAccess() {
        guard AppSettings.shared.calendarEnabled else { access = .notConnected; return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: access = .notDetermined
        case .denied, .restricted: access = .denied
        default: access = Self.isAuthorized ? .granted : .denied
        }
    }

    /// Turns the integration on and asks macOS for access if needed.
    func connect() {
        AppSettings.shared.calendarEnabled = true
        refreshAccess()
        guard access == .notDetermined else { reload(); return }
        let completion: @Sendable (Bool, Error?) -> Void = { [weak self] _, _ in
            Task { @MainActor in self?.reload() }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings › Internet Accounts, where a Google account can be added for free.
    /// Once added with Calendars turned on, its events show up through EventKit automatically.
    func openInternetAccounts() {
        let candidates = ["x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
                          "x-apple.systempreferences:com.apple.preferences.internetaccounts"]
        for c in candidates {
            if let url = URL(string: c), NSWorkspace.shared.open(url) { return }
        }
    }

    func reload() {
        refreshAccess()
        guard access == .granted else { events = []; accountNames = []; busyDays = []; return }
        let names = Set(store.calendars(for: .event).compactMap { $0.source?.title }).sorted()
        if names != accountNames { accountNames = names }
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: Self.agendaDays, to: today) ?? now.addingTimeInterval(3 * 86_400)
        let predicate = store.predicateForEvents(withStart: today, end: horizon, calendars: nil)
        let found = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { a, b in
                let sa: Date = a.startDate, sb: Date = b.startDate
                return sa != sb ? sa < sb : (a.isAllDay && !b.isAllDay)
            }
            .prefix(20)
            .map { e -> Event in
                let join = Self.meetingLink(in: e)
                return Event(id: e.eventIdentifier ?? UUID().uuidString,
                             title: e.title ?? "Untitled",
                             start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                             color: Color(nsColor: e.calendar?.color ?? .systemBlue),
                             joinURL: join?.0, joinService: join?.1)
            }
        let list = Array(found)
        if list != events { events = list }
        busyDays = Self.computeBusyDays(in: store, month: now, calendar: calendar)
    }

    private static func computeBusyDays(in store: EKEventStore, month: Date, calendar: Calendar) -> Set<Int> {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let events = store.events(matching: store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil))
        var days = Set<Int>()
        for e in events.prefix(1000) {
            let start: Date = e.startDate, end: Date = e.endDate
            var day = max(calendar.startOfDay(for: start), interval.start)
            let last = min(end.addingTimeInterval(-1), interval.end.addingTimeInterval(-1))
            while day <= last {
                days.insert(calendar.component(.day, from: day))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days
    }

    /// Finds a video-call link in the event's URL, location or notes.
    nonisolated static func meetingLink(in event: EKEvent) -> (URL, String)? {
        var candidates: [URL] = []
        if let url = event.url { candidates.append(url) }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        if !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            candidates += detector.matches(in: text, range: range).compactMap(\.url)
        }
        for url in candidates {
            if let service = meetingService(for: url) { return (url, service) }
        }
        return nil
    }

    /// Recognises a video-call link. Only https links on the real service domains (or a subdomain)
    /// qualify, so an invite can't dress up a lookalike host or a non-web scheme as "Join on Zoom".
    nonisolated static func meetingService(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if HostMatch.host(host, isOrIsUnderAnyOf: ["zoom.us", "zoom.com"]) { return "Zoom" }
        if host == "meet.google.com" { return "Meet" }
        if HostMatch.host(host, isOrIsUnderAnyOf: ["teams.microsoft.com", "teams.live.com"]) { return "Teams" }
        if HostMatch.host(host, isOrIsUnder: "webex.com") { return "Webex" }
        if host == "facetime.apple.com" { return "FaceTime" }
        if HostMatch.host(host, isOrIsUnder: "whereby.com") { return "Whereby" }
        return nil
    }
}

// MARK: - Weather (Open-Meteo, free, no API key)

@MainActor
final class WeatherService: ObservableObject {
    struct Current: Equatable {
        var temperature: Double
        var high: Double
        var low: Double
        var code: Int
        var isDay: Bool
        var updated: Date
    }

    struct Place: Identifiable, Equatable {
        var id: String { "\(latitude),\(longitude)" }
        let name: String
        let detail: String
        let latitude: Double
        let longitude: Double
        var label: String { detail.isEmpty ? name : "\(name), \(detail)" }
    }

    enum SearchState: Equatable { case idle, searching, results, noMatches, failed(String) }

    @Published private(set) var current: Current?
    @Published private(set) var error: String?
    @Published private(set) var searchResults: [Place] = []
    @Published private(set) var searchState: SearchState = .idle
    private var searchDebounce: Task<Void, Never>?
    private var searchTask: URLSessionDataTask?
    private var latestQuery = ""

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "TuckNotch (macOS; open source)"]
        return URLSession(configuration: config)
    }()

    var isConfigured: Bool {
        let s = AppSettings.shared
        return s.weatherEnabled && !s.weatherPlace.isEmpty
    }

    func start() {
        let t = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let s = AppSettings.shared
        Publishers.CombineLatest4(s.$weatherEnabled, s.$weatherLatitude, s.$weatherLongitude, s.$temperatureUnit)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _, _ in Task { @MainActor in self?.refresh() } }
            .store(in: &cancellables)
    }

    func refresh() {
        let s = AppSettings.shared
        guard isConfigured else { current = nil; return }
        guard let url = Self.forecastURL(latitude: s.weatherLatitude, longitude: s.weatherLongitude,
                                         unit: s.temperatureUnit) else { return }
        session.dataTask(with: url) { [weak self] data, _, err in
            let parsed = data.flatMap(Self.parseForecast)
            Task { @MainActor in
                guard let self else { return }
                if let parsed {
                    self.current = parsed
                    self.error = nil
                } else {
                    self.error = err.map { "Couldn't reach Open-Meteo: \($0.localizedDescription)" } ?? "Weather unavailable right now"
                    Log.app.error("weather fetch failed")
                }
            }
        }.resume()
    }

    nonisolated static func parseForecast(_ data: Data) -> Current? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = obj["current"] as? [String: Any],
              let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (cur["weather_code"] as? NSNumber)?.intValue else { return nil }
        let daily = obj["daily"] as? [String: Any]
        let high = ((daily?["temperature_2m_max"] as? [NSNumber])?.first?.doubleValue) ?? temp
        let low = ((daily?["temperature_2m_min"] as? [NSNumber])?.first?.doubleValue) ?? temp
        let isDay = ((cur["is_day"] as? NSNumber)?.intValue ?? 1) == 1
        return Current(temperature: temp, high: high, low: low, code: code, isDay: isDay, updated: Date())
    }

    static func geocodeURL(_ query: String) -> URL? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "6"),
                        .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        return c.url
    }

    static func forecastURL(latitude: Double, longitude: Double, unit: TemperatureUnit) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "temperature_unit", value: unit.rawValue),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1")
        ]
        return c.url
    }

    /// Parses Open-Meteo geocoding results. Exposed for tests and diagnostics.
    nonisolated static func parsePlaces(_ data: Data) -> [Place] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let name = r["name"] as? String,
                  let lat = (r["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (r["longitude"] as? NSNumber)?.doubleValue else { return nil }
            let detail = [r["admin1"] as? String, r["country"] as? String].compactMap { $0 }.joined(separator: ", ")
            return Place(name: name, detail: detail, latitude: lat, longitude: lon)
        }
    }

    /// City search (Open-Meteo geocoding). Debounced while typing; `immediate` for Return.
    func search(_ query: String, immediate: Bool = false) {
        let q = query.trimmingCharacters(in: .whitespaces)
        searchDebounce?.cancel()
        latestQuery = q
        guard q.count >= 2 else {
            searchTask?.cancel()
            searchResults = []
            searchState = .idle
            return
        }
        searchState = .searching
        searchDebounce = Task { [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            self?.performSearch(q)
        }
    }

    private func performSearch(_ q: String) {
        guard let url = Self.geocodeURL(q) else { return }
        searchTask?.cancel()
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            let places = data.map(Self.parsePlaces) ?? []
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let failure: String? = error.map { $0.localizedDescription }
                ?? ((status != 200 && status != 0) ? "Open-Meteo returned HTTP \(status)" : nil)
            Task { @MainActor in
                guard let self, self.latestQuery == q else { return }
                self.searchResults = places
                if !places.isEmpty {
                    self.searchState = .results
                } else if let failure {
                    self.searchState = .failed(failure)
                    Log.app.error("city search failed: \(failure, privacy: .public)")
                } else {
                    self.searchState = .noMatches
                }
            }
        }
        searchTask = task
        task.resume()
    }

    func clearSearch() {
        searchDebounce?.cancel()
        searchTask?.cancel()
        latestQuery = ""
        searchResults = []
        searchState = .idle
    }

    func removeCity() {
        let s = AppSettings.shared
        s.weatherEnabled = false
        s.weatherPlace = ""
        current = nil
    }

    func choose(_ place: Place) {
        let s = AppSettings.shared
        s.weatherPlace = place.label
        s.weatherLatitude = place.latitude
        s.weatherLongitude = place.longitude
        s.weatherEnabled = true
        clearSearch()
        refresh()
    }

    // WMO weather interpretation codes → text + SF Symbol.
    nonisolated static func describe(_ code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0: return ("Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1: return ("Mostly Clear", isDay ? "sun.max.fill" : "moon.fill")
        case 2: return ("Partly Cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return ("Cloudy", "cloud.fill")
        case 45, 48: return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 66: return ("Rain", "cloud.rain.fill")
        case 65, 67: return ("Heavy Rain", "cloud.heavyrain.fill")
        case 71, 73, 75, 77: return ("Snow", "cloud.snow.fill")
        case 80, 81, 82: return ("Showers", "cloud.sun.rain.fill")
        case 85, 86: return ("Snow Showers", "cloud.snow.fill")
        case 95, 96, 99: return ("Thunderstorm", "cloud.bolt.rain.fill")
        default: return ("—", "cloud.fill")
        }
    }
}

// MARK: - Lyrics (LRCLIB, free, no API key)

@MainActor
final class LyricsService: ObservableObject {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    enum State: Equatable { case off, loading, synced, plainOnly, instrumental, notFound }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var state: State = .off

    private var key = ""
    private var cancellables = Set<AnyCancellable>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "TuckNotch (macOS; open source)"]
        return URLSession(configuration: config)
    }()

    func start(nowPlaying: NowPlayingService) {
        Publishers.CombineLatest(nowPlaying.$track, AppSettings.shared.$lyricsEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] track, enabled in
                Task { @MainActor in self?.update(track: track, enabled: enabled) }
            }
            .store(in: &cancellables)
    }

    private func update(track: NowPlayingService.Track?, enabled: Bool) {
        guard enabled, let track, !track.title.isEmpty else {
            key = ""
            lines = []
            state = .off
            return
        }
        let newKey = "\(track.title)|\(track.artist)"
        guard newKey != key else { return }
        key = newKey
        lines = []
        state = .loading

        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [.init(name: "track_name", value: track.title)]
        if !track.artist.isEmpty { c.queryItems?.append(.init(name: "artist_name", value: track.artist)) }
        guard let url = c.url else { return }
        let duration = track.duration
        session.dataTask(with: url) { [weak self] data, _, _ in
            let results = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
            // Prefer synced lyrics with a matching duration (±3 s).
            let synced = results.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
            let best = synced.first { abs((($0["duration"] as? NSNumber)?.doubleValue ?? 0) - duration) <= 3 } ?? synced.first
            let parsed = (best?["syncedLyrics"] as? String).map(Self.parseLRC) ?? []
            let hasPlain = results.contains { ($0["plainLyrics"] as? String)?.isEmpty == false }
            let instrumental = results.first.map { ($0["instrumental"] as? Bool) == true } ?? false
            Task { @MainActor in
                guard let self, self.key == newKey else { return }
                self.lines = parsed
                self.state = parsed.isEmpty ? (instrumental ? .instrumental : (hasPlain ? .plainOnly : .notFound)) : .synced
            }
        }.resume()
    }

    /// Parses LRC text ("[mm:ss.xx] line"); lines with several stamps are repeated. Exposed for tests.
    nonisolated static func parseLRC(_ text: String) -> [Line] {
        var out: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<close]
                let parts = stamp.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    times.append(m * 60 + s)
                }
                rest = rest[rest.index(after: close)...]
            }
            let line = rest.trimmingCharacters(in: .whitespaces)
            for t in times { out.append(Line(time: t, text: line)) }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Index of the line being sung at `position` seconds.
    func index(at position: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= position + 0.25 { result = i } else { break }
        }
        return result
    }
}

// MARK: - Keychain (secrets never go to UserDefaults)

enum Keychain {
    private static let service = "com.asvlabs.tucknotch"

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { Log.app.error("keychain write failed: \(status)") }
        return status == errSecSuccess
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Notion (opt-in, internal integration secret)

/// Shows today's items from one Notion database (data source) that has a Date property.
/// Uses the Notion API version 2025-09-03 (data sources). The secret lives in the Keychain.
@MainActor
final class NotionService: ObservableObject {
    struct DataSource: Identifiable, Equatable {
        let id: String
        let title: String
        let dateProperties: [String]
    }

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date?
        let isAllDay: Bool
        let url: URL?
        let joinURL: URL?
        let joinService: String?
    }

    enum Status: Equatable { case notConnected, working, connected, failed(String) }

    @Published private(set) var status: Status = .notConnected
    @Published private(set) var dataSources: [DataSource] = []
    @Published private(set) var items: [Item] = []

    static let apiVersion = "2025-09-03"
    private static let keychainAccount = "notion-integration-secret"
    private var lastRefresh = Date.distantPast
    private var timer: Timer?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Cached so SwiftUI renders don't hit the Keychain; updated on start/connect/disconnect.
    @Published private(set) var hasSecret = false
    var isReady: Bool {
        status == .connected && !AppSettings.shared.notionDataSourceID.isEmpty && !AppSettings.shared.notionDateProperty.isEmpty
    }

    func start() {
        hasSecret = Keychain.get(account: Self.keychainAccount) != nil
        if hasSecret {
            status = .connected
            loadDataSources()
            refresh()
        }
        let t = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func connect(secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard Keychain.set(trimmed, account: Self.keychainAccount) else {
            status = .failed("Couldn't save the secret to your Keychain. Try again, or check Keychain Access.")
            return
        }
        hasSecret = true
        status = .working
        loadDataSources()
    }

    func disconnect() {
        Keychain.delete(account: Self.keychainAccount)
        hasSecret = false
        let s = AppSettings.shared
        s.notionDataSourceID = ""
        s.notionDataSourceName = ""
        s.notionDateProperty = ""
        dataSources = []
        items = []
        status = .notConnected
    }

    func select(_ source: DataSource) {
        let s = AppSettings.shared
        s.notionDataSourceID = source.id
        s.notionDataSourceName = source.title
        s.notionDateProperty = source.dateProperties.first ?? ""
        refresh()
    }

    func refreshIfStale() {
        if Date().timeIntervalSince(lastRefresh) > 120 { refresh() }
    }

    // MARK: Requests

    private func request(_ path: String, body: [String: Any]) -> URLRequest? {
        guard let secret = Keychain.get(account: Self.keychainAccount),
              let url = URL(string: "https://api.notion.com/v1/\(path)"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.httpBody = data
        r.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        r.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return r
    }

    /// Lists every database (data source) the integration has been given access to.
    func loadDataSources() {
        guard let r = request("search", body: ["filter": ["property": "object", "value": "data_source"], "page_size": 100]) else {
            status = .failed("Couldn't read the secret from your Keychain. Disconnect and paste it again.")
            return
        }
        session.dataTask(with: r) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let sources = data.map(Self.parseDataSources) ?? []
            let message = Self.errorMessage(data: data, code: code, error: error)
            Task { @MainActor in
                guard let self else { return }
                if let message {
                    self.status = .failed(message)
                } else {
                    self.dataSources = sources
                    self.status = .connected
                    if AppSettings.shared.notionDataSourceID.isEmpty, sources.count == 1 { self.select(sources[0]) }
                }
            }
        }.resume()
    }

    func refresh() {
        let s = AppSettings.shared
        guard hasSecret, !s.notionDataSourceID.isEmpty, !s.notionDateProperty.isEmpty else { items = []; return }
        lastRefresh = Date()
        guard Self.isValidID(s.notionDataSourceID) else { status = .failed("Choose the database again."); return }
        let cal = Calendar.current
        let (from, to) = Self.queryWindow(now: Date(), calendar: cal)
        let prop = s.notionDateProperty
        let body: [String: Any] = [
            "filter": ["and": [
                ["property": prop, "date": ["on_or_after": Self.isoTimestamp(from)]],
                ["property": prop, "date": ["on_or_before": Self.isoTimestamp(to)]]
            ]],
            "sorts": [["property": prop, "direction": "ascending"]],
            "page_size": 25
        ]
        guard let r = request("data_sources/\(s.notionDataSourceID)/query", body: body) else { return }
        session.dataTask(with: r) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let parsed = data.map { Self.parseItems($0, dateProperty: prop) } ?? []
            let message = Self.errorMessage(data: data, code: code, error: error)
            Task { @MainActor in
                guard let self else { return }
                if let message {
                    self.status = .failed(message)
                    return
                }
                self.status = .connected
                let now = Date()
                let (dayStart, windowEnd) = Self.queryWindow(now: now, calendar: cal)
                let upcoming = parsed.filter { item in
                    if item.isAllDay { return item.start >= dayStart && item.start < windowEnd }
                    return (item.end ?? item.start.addingTimeInterval(3600)) > now && item.start < windowEnd
                }
                if upcoming != self.items { self.items = upcoming }
            }
        }.resume()
    }

    // MARK: Parsing (exposed for tests)

    /// Notion ids are UUIDs, with or without dashes. Anything else never reaches a URL path.
    nonisolated static func isValidID(_ id: String) -> Bool {
        id.range(of: "^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$", options: .regularExpression) != nil
    }

    /// Start of today through the end of the agenda window (three days), in local time.
    nonisolated static func queryWindow(now: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: CalendarService.agendaDays, to: start) ?? start
        return (start, end)
    }

    /// Full ISO-8601 timestamp with the local offset, always in Latin digits.
    nonisolated static func isoTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    nonisolated static func errorMessage(data: Data?, code: Int, error: Error?) -> String? {
        if let error { return error.localizedDescription }
        guard code != 200 else { return nil }
        let apiMessage = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["message"] as? String
        switch code {
        case 401: return "Notion rejected the secret. Check that you pasted the whole integration secret."
        case 403, 404: return apiMessage ?? "Notion can't see that database. Share it with your integration (••• › Connections)."
        default: return apiMessage ?? "Notion returned HTTP \(code)."
        }
    }

    /// Only https links on Notion's own domains are opened from the Calendar.
    nonisolated static func notionPageURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host,
              HostMatch.host(host, isOrIsUnderAnyOf: ["notion.so", "notion.site"]) else { return nil }
        return url
    }

    nonisolated static func plainText(_ value: Any?) -> String {
        ((value as? [[String: Any]]) ?? []).compactMap { $0["plain_text"] as? String }.joined()
    }

    nonisolated static func parseDataSources(_ data: Data) -> [DataSource] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let id = r["id"] as? String else { return nil }
            let title = plainText(r["title"])
            let props = (r["properties"] as? [String: [String: Any]]) ?? [:]
            let dates = props.filter { ($0.value["type"] as? String) == "date" }.map(\.key).sorted()
            return DataSource(id: id, title: title.isEmpty ? "Untitled" : title, dateProperties: dates)
        }
    }

    nonisolated static func parseDate(_ text: String) -> (Date, Bool)? {
        if text.count == 10 {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: text).map { ($0, true) }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return (d, false) }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: text).map { ($0, false) }
    }

    nonisolated static func parseItems(_ data: Data, dateProperty: String) -> [Item] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: [String: Any]],
                  let date = props[dateProperty]?["date"] as? [String: Any],
                  let startText = date["start"] as? String,
                  let (start, allDay) = parseDate(startText) else { return nil }
            let end = (date["end"] as? String).flatMap(parseDate)?.0
            let title = props.values.first { ($0["type"] as? String) == "title" }.map { plainText($0["title"]) } ?? ""
            let links = props.values.compactMap { $0["url"] as? String }.compactMap(URL.init(string:))
            let join = links.first { CalendarService.meetingService(for: $0) != nil }
            return Item(id: id, title: title.isEmpty ? "Untitled" : title, start: start, end: end, isAllDay: allDay,
                        url: (page["url"] as? String).flatMap(URL.init(string:)).flatMap(notionPageURL),
                        joinURL: join, joinService: join.flatMap(CalendarService.meetingService(for:)))
        }
    }
}

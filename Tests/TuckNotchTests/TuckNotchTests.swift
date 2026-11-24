import XCTest
import AppKit
@testable import TuckNotch

final class FormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(Format.clock(0), "0:00")
        XCTAssertEqual(Format.clock(65), "1:05")
        XCTAssertEqual(Format.clock(3_725), "1:02:05")
        XCTAssertEqual(Format.clock(-3), "0:00")
        XCTAssertEqual(Format.clock(.nan), "0:00")
    }
}

final class ExternalActivityParserTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testValidPayload() throws {
        let json = """
        {"id":"deploy-web","title":"Deploy web","source":"Deploy bot","subtitle":"build 412","state":"needs-input",
         "progress":1.7,"trailing":"40%","priority":"critical","expiresIn":60,
         "actions":[{"id":"approve","title":"Approve"},{"id":"bad id","title":"x"},{"id":"a","title":"1"},{"id":"b","title":"2"}]}
        """
        let now = Date(timeIntervalSince1970: 1_000)
        let parsed = try XCTUnwrap(ExternalActivityParser.parse(data(json), now: now))
        XCTAssertEqual(parsed.activity.id, "ext.deploy-web")
        XCTAssertEqual(parsed.activity.source, "external")
        XCTAssertEqual(parsed.activity.subtitle, "Deploy bot · build 412")
        XCTAssertEqual(parsed.activity.progress, 1, "progress is clamped to 0...1")
        XCTAssertEqual(parsed.activity.priority, .high, "external items can't raise critical")
        XCTAssertEqual(parsed.activity.tint, .warning)
        XCTAssertTrue(parsed.wantsAttention, "needs-input always asks for attention")
        XCTAssertEqual(parsed.activity.expiresAt, now.addingTimeInterval(60))
        // Only the first 3 actions are considered, and invalid ids are dropped.
        XCTAssertEqual(parsed.activity.actions.map(\.id), ["approve", "a"])
    }

    func testRejectsBadIDsAndEmptyTitles() {
        XCTAssertNil(ExternalActivityParser.parse(data(#"{"id":"../etc","title":"x"}"#)))
        XCTAssertNil(ExternalActivityParser.parse(data(#"{"id":"ok","title":"   "}"#)))
        XCTAssertNil(ExternalActivityParser.parse(data("not json")))
        XCTAssertNil(ExternalActivityParser.parse(Data(count: ExternalActivityParser.maxFileBytes + 1)))
    }

    func testClipsLongStringsAndControlCharacters() throws {
        let long = String(repeating: "a", count: 300)
        let parsed = try XCTUnwrap(ExternalActivityParser.parse(data("{\"id\":\"x\",\"title\":\"\(long)\",\"trailing\":\"123456789012\"}")))
        XCTAssertEqual(parsed.activity.title.count, 80)
        XCTAssertEqual(parsed.activity.trailing?.count, 8)
        XCTAssertEqual(ExternalActivityParser.clip("a\nb\tc", 20), "a b c")
    }

    func testUnknownSymbolFallsBackToStateSymbol() throws {
        let parsed = try XCTUnwrap(ExternalActivityParser.parse(data(#"{"id":"x","title":"t","state":"done","symbol":"nope"}"#),
                                                                symbolExists: { _ in false }))
        XCTAssertEqual(parsed.activity.symbol, "checkmark.circle.fill")
        XCTAssertEqual(parsed.activity.tint, .success)
    }
}

final class ClipboardFilterTests: XCTestCase {
    func testConcealedAndTransientTypesAreSkipped() {
        XCTAssertFalse(ClipboardService.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
                                                     frontmostBundleID: "com.apple.Safari", userExcluded: []))
        XCTAssertFalse(ClipboardService.shouldRecord(types: ["org.nspasteboard.TransientType"],
                                                     frontmostBundleID: nil, userExcluded: []))
    }

    func testExcludedApps() {
        XCTAssertFalse(ClipboardService.shouldRecord(types: ["public.utf8-plain-text"],
                                                     frontmostBundleID: "com.1password.1password", userExcluded: []))
        XCTAssertFalse(ClipboardService.shouldRecord(types: ["public.utf8-plain-text"],
                                                     frontmostBundleID: "com.example.bank", userExcluded: ["com.example.bank"]))
        XCTAssertTrue(ClipboardService.shouldRecord(types: ["public.utf8-plain-text"],
                                                    frontmostBundleID: "com.apple.TextEdit", userExcluded: ["com.example.bank"]))
    }
}

@MainActor
final class ActivityEngineTests: XCTestCase {
    func testOrderingIsPriorityThenAge() {
        let engine = ActivityEngine()
        let old = Date(timeIntervalSince1970: 1)
        let new = Date(timeIntervalSince1970: 2)
        engine.upsert(Activity(id: "a", source: "t", symbol: "x", title: "low", priority: .low, createdAt: old))
        engine.upsert(Activity(id: "b", source: "t", symbol: "x", title: "high-new", priority: .high, createdAt: new))
        engine.upsert(Activity(id: "c", source: "t", symbol: "x", title: "high-old", priority: .high, createdAt: old))
        XCTAssertEqual(engine.ordered.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(engine.primary?.id, "c")
    }

    func testUpsertKeepsPosition() {
        let engine = ActivityEngine()
        engine.upsert(Activity(id: "a", source: "t", symbol: "x", title: "1", createdAt: Date(timeIntervalSince1970: 1)))
        engine.upsert(Activity(id: "b", source: "t", symbol: "x", title: "2", createdAt: Date(timeIntervalSince1970: 2)))
        engine.upsert(Activity(id: "a", source: "t", symbol: "x", title: "1 updated", createdAt: Date()))
        XCTAssertEqual(engine.ordered.map(\.id), ["a", "b"])
        XCTAssertEqual(engine.ordered.first?.title, "1 updated")
    }

    func testSuppressionHidesPrimaryAndHoldsNonCriticalAttention() {
        let engine = ActivityEngine()
        engine.upsert(Activity(id: "a", source: "t", symbol: "x", title: "1"))
        engine.suppressed = true
        XCTAssertNil(engine.primary)

        engine.raise(AttentionRequest(id: "n", source: "t", symbol: "x", title: "normal", priority: .high))
        XCTAssertNil(engine.attention, "held while presenting")
        engine.raise(AttentionRequest(id: "c", source: "t", symbol: "x", title: "critical", priority: .critical))
        XCTAssertEqual(engine.attention?.id, "c")

        engine.dismissAttention()
        XCTAssertNil(engine.attention, "non-critical still held")
        engine.suppressed = false
        XCTAssertEqual(engine.attention?.id, "n", "released when presentation ends")
    }

    func testHigherPriorityAttentionPreemptsAndQueues() {
        let engine = ActivityEngine()
        engine.raise(AttentionRequest(id: "1", source: "t", symbol: "x", title: "first", priority: .normal))
        engine.raise(AttentionRequest(id: "2", source: "t", symbol: "x", title: "urgent", priority: .high))
        XCTAssertEqual(engine.attention?.id, "2")
        engine.dismissAttention()
        XCTAssertEqual(engine.attention?.id, "1")
    }

    func testActionsRouteToSourceHandler() {
        let engine = ActivityEngine()
        var received: (String, String)?
        engine.registerHandler(source: "media") { item, action in received = (item, action) }
        engine.perform(actionID: "next", itemID: "media", source: "media")
        XCTAssertEqual(received?.0, "media")
        XCTAssertEqual(received?.1, "next")
    }
}

final class BrowserMediaTests: XCTestCase {
    func testParsesPlayingYouTubeMusicTab() throws {
        let text = #"1{"t":"Blue in Green","a":"Miles Davis","al":"Kind of Blue","d":337.5,"p":121,"art":"https://lh3.googleusercontent.com/x","h":"music.youtube.com"}"#
        let snap = try XCTUnwrap(BrowserMediaProvider.parse(text, browser: "Google Chrome"))
        XCTAssertEqual(snap.title, "Blue in Green")
        XCTAssertEqual(snap.artist, "Miles Davis")
        XCTAssertTrue(snap.playing)
        XCTAssertEqual(snap.duration, 337.5)
        XCTAssertEqual(snap.sourceLabel, "YouTube Music · Chrome")
    }

    func testSkipScriptsCoverYouTubeAndFallbacks() {
        let next = BrowserMediaProvider.actionJS(.next)
        XCTAssertTrue(next.contains("ytmusic-player-bar .next-button"))
        XCTAssertTrue(next.contains(".ytp-next-button"))
        XCTAssertTrue(next.contains("shiftKey:true"))        // YouTube Shift+N fallback
        XCTAssertTrue(next.contains("tnResume(was)"))        // resumes if the browser left it paused
        XCTAssertTrue(next.hasPrefix("(function(){") && next.hasSuffix("})()"))
        let prev = BrowserMediaProvider.actionJS(.previous)
        XCTAssertTrue(prev.contains("ytmusic-player-bar .previous-button"))
        XCTAssertTrue(prev.contains("currentTime=0"))
    }

    func testPausedAndInvalid() {
        XCTAssertEqual(BrowserMediaProvider.parse(#"0{"t":"x","h":"www.youtube.com"}"#, browser: "Safari")?.playing, false)
        XCTAssertEqual(BrowserMediaProvider.parse(#"0{"t":"x","h":"www.youtube.com"}"#, browser: "Safari")?.sourceLabel, "YouTube · Safari")
        XCTAssertNil(BrowserMediaProvider.parse("", browser: "Safari"))
        XCTAssertNil(BrowserMediaProvider.parse("1not json", browser: "Safari"))
        XCTAssertNil(BrowserMediaProvider.parse(#"1{"t":""}"#, browser: "Safari"))
    }
}

final class YouTubeLinkTests: XCTestCase {
    func testLinksIDsAndSearch() {
        XCTAssertEqual(YouTubeLink.url(for: "https://youtu.be/dQw4w9WgXcQ")?.host, "youtu.be")
        XCTAssertEqual(YouTubeLink.url(for: "dQw4w9WgXcQ")?.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeLink.url(for: "miles davis blue in green")?.path, "/results")
        XCTAssertNil(YouTubeLink.url(for: "   "))
    }
}

final class LyricsParserTests: XCTestCase {
    func testParsesLRC() {
        let lrc = "[ti:Song]\n[00:01.50] First\n[00:10.00][01:00.00] Chorus\n[00:05.25]Second"
        let lines = LyricsService.parseLRC(lrc)
        XCTAssertEqual(lines.map(\.text), ["First", "Second", "Chorus", "Chorus"])
        XCTAssertEqual(lines.first?.time ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(lines.last?.time ?? 0, 60, accuracy: 0.001)
    }
}

final class IntegrationParsingTests: XCTestCase {
    func testWeatherForecastParsing() throws {
        let json = #"{"current":{"temperature_2m":72.4,"weather_code":0,"is_day":1},"daily":{"temperature_2m_max":[76.1],"temperature_2m_min":[58.0]}}"#
        let c = try XCTUnwrap(WeatherService.parseForecast(Data(json.utf8)))
        XCTAssertEqual(Int(c.temperature.rounded()), 72)
        XCTAssertEqual(Int(c.high.rounded()), 76)
        XCTAssertEqual(Int(c.low.rounded()), 58)
        XCTAssertTrue(c.isDay)
        XCTAssertEqual(WeatherService.describe(0, isDay: true).0, "Clear")
    }

    func testMeetingServices() {
        XCTAssertEqual(CalendarService.meetingService(for: URL(string: "https://us02web.zoom.us/j/123")!), "Zoom")
        XCTAssertEqual(CalendarService.meetingService(for: URL(string: "https://meet.google.com/abc-defg-hij")!), "Meet")
        XCTAssertEqual(CalendarService.meetingService(for: URL(string: "https://teams.microsoft.com/l/meetup-join/x")!), "Teams")
        XCTAssertNil(CalendarService.meetingService(for: URL(string: "https://example.com")!))
    }
}

@MainActor
final class CitySearchTests: XCTestCase {
    func testParsesGeocodingResults() {
        let json = #"{"results":[{"name":"Lisbon","admin1":"Lisbon","country":"Portugal","latitude":38.7167,"longitude":-9.1333},{"name":"Lisbon","admin1":"Ohio","country":"United States","latitude":40.7723,"longitude":-80.7681}]}"#
        let places = WeatherService.parsePlaces(Data(json.utf8))
        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(places.first?.name, "Lisbon")
        XCTAssertTrue(places.first?.label.contains("Portugal") ?? false)
        XCTAssertEqual(places.first?.latitude ?? 0, 38.7167, accuracy: 0.0001)
    }

    func testNoResultsAndGarbage() {
        XCTAssertTrue(WeatherService.parsePlaces(Data(#"{"generationtime_ms":0.5}"#.utf8)).isEmpty)
        XCTAssertTrue(WeatherService.parsePlaces(Data("not json".utf8)).isEmpty)
    }

    func testGeocodeURLEncodesQuery() throws {
        let url = try XCTUnwrap(WeatherService.geocodeURL("San José"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://geocoding-api.open-meteo.com/v1/search?"))
        XCTAssertTrue(url.absoluteString.contains("San%20Jos"))
    }
}

final class NotionParsingTests: XCTestCase {
    func testDataSourcesListDateProperties() {
        let json = #"{"object":"list","results":[{"object":"data_source","id":"ds-1","title":[{"plain_text":"Content "},{"plain_text":"Calendar"}],"properties":{"Name":{"type":"title"},"Publish":{"type":"date"},"Due":{"type":"date"},"Status":{"type":"status"}}},{"object":"data_source","id":"ds-2","title":[],"properties":{}}]}"#
        let sources = NotionService.parseDataSources(Data(json.utf8))
        XCTAssertEqual(sources.map(\.id), ["ds-1", "ds-2"])
        XCTAssertEqual(sources[0].title, "Content Calendar")
        XCTAssertEqual(sources[0].dateProperties, ["Due", "Publish"])
        XCTAssertEqual(sources[1].title, "Untitled")
    }

    func testParsesPagesWithDatesAndMeetingLinks() throws {
        let json = #"{"results":[{"id":"p1","url":"https://www.notion.so/p1","properties":{"Name":{"type":"title","title":[{"plain_text":"Standup"}]},"When":{"type":"date","date":{"start":"2026-11-24T09:00:00.000-08:00","end":"2026-11-24T09:15:00.000-08:00"}},"Link":{"type":"url","url":"https://meet.google.com/abc-defg-hij"}}},{"id":"p2","url":"https://www.notion.so/p2","properties":{"Name":{"type":"title","title":[{"plain_text":"Ship v0.4"}]},"When":{"type":"date","date":{"start":"2026-11-24"}}}},{"id":"p3","properties":{"Name":{"type":"title","title":[]},"When":{"type":"date","date":null}}}]}"#
        let items = NotionService.parseItems(Data(json.utf8), dateProperty: "When")
        XCTAssertEqual(items.count, 2)
        let standup = try XCTUnwrap(items.first)
        XCTAssertEqual(standup.title, "Standup")
        XCTAssertFalse(standup.isAllDay)
        XCTAssertEqual(standup.joinService, "Meet")
        XCTAssertEqual(standup.end?.timeIntervalSince(standup.start) ?? 0, 900, accuracy: 0.5)
        XCTAssertEqual(standup.url?.absoluteString, "https://www.notion.so/p1")
        XCTAssertTrue(items[1].isAllDay)
        XCTAssertNil(items[1].joinURL)
    }

    func testErrorMessages() {
        XCTAssertNil(NotionService.errorMessage(data: nil, code: 200, error: nil))
        XCTAssertTrue(NotionService.errorMessage(data: nil, code: 401, error: nil)?.contains("secret") ?? false)
        let body = Data(#"{"object":"error","message":"Could not find data source"}"#.utf8)
        XCTAssertEqual(NotionService.errorMessage(data: body, code: 404, error: nil), "Could not find data source")
    }
}

final class SecurityChecksTests: XCTestCase {
    func testJoinLinksNeedRealHostsAndHTTPS() {
        XCTAssertEqual(CalendarService.meetingService(for: URL(string: "https://acme.zoom.us/j/1")!), "Zoom")
        XCTAssertNil(CalendarService.meetingService(for: URL(string: "https://evilzoom.us/j/1")!))
        XCTAssertNil(CalendarService.meetingService(for: URL(string: "http://zoom.us/j/1")!))
        XCTAssertNil(CalendarService.meetingService(for: URL(string: "smb://zoom.us/share")!))
        XCTAssertNil(CalendarService.meetingService(for: URL(string: "https://meet.google.com.evil.io/x")!))
    }

    func testHostMatch() {
        XCTAssertTrue(HostMatch.host("music.youtube.com", isOrIsUnder: "youtube.com"))
        XCTAssertTrue(HostMatch.host("YouTube.com", isOrIsUnder: "youtube.com"))
        XCTAssertFalse(HostMatch.host("notyoutube.com", isOrIsUnder: "youtube.com"))
        XCTAssertFalse(HostMatch.host("youtube.com.evil.io", isOrIsUnder: "youtube.com"))
    }

    func testBrowserSnapshotsFromForeignHostsAreRejected() {
        XCTAssertNil(BrowserMediaProvider.parse(#"1{"t":"x","h":"notyoutube.com"}"#, browser: "Safari"))
        XCTAssertNil(BrowserMediaProvider.parse(#"1{"t":"x","h":"example.com"}"#, browser: "Safari"))
        XCTAssertNil(BrowserMediaProvider.parse(#"1{"t":"x"}"#, browser: "Safari"))
        XCTAssertTrue(BrowserMediaProvider.actionJS(.next).contains("tnH===d"))   // page-side host gate
        // The browser-reported tab address wins over whatever the page claims about itself.
        XCTAssertNil(BrowserMediaProvider.parse(#"1{"t":"x","h":"www.youtube.com"}"#, browser: "Safari",
                                                tabURL: "https://evil.example/?u=youtube.com"))
        XCTAssertNil(BrowserMediaProvider.parse(#"1{"t":"x","h":"www.youtube.com"}"#, browser: "Safari",
                                                tabURL: "https://youtube.com@evil.example/"))
        XCTAssertEqual(BrowserMediaProvider.parse(#"1{"t":"x","h":"evil.example"}"#, browser: "Safari",
                                                  tabURL: "https://music.youtube.com/watch?v=1")?.sourceLabel, "YouTube Music · Safari")
    }

    func testInboxReadsOnlyRegularFilesWithinLimit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let small = dir.appendingPathComponent("a.json")
        try Data("{}".utf8).write(to: small)
        XCTAssertEqual(ExternalActivityInbox.readRegularFile(small, limit: 100), Data("{}".utf8))
        let big = dir.appendingPathComponent("b.json")
        try Data(repeating: 65, count: 200).write(to: big)
        XCTAssertNil(ExternalActivityInbox.readRegularFile(big, limit: 100))
        let link = dir.appendingPathComponent("c.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: small)
        XCTAssertNil(ExternalActivityInbox.readRegularFile(link, limit: 100))
        let fifo = dir.appendingPathComponent("d.json")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertNil(ExternalActivityInbox.readRegularFile(fifo, limit: 100))   // must not block
    }

    func testNotionIDValidationAndTimestamps() {
        XCTAssertTrue(NotionService.isValidID("1a2b3c4d-1a2b-1a2b-1a2b-1a2b3c4d5e6f"))
        XCTAssertTrue(NotionService.isValidID("1a2b3c4d1a2b1a2b1a2b1a2b3c4d5e6f"))
        XCTAssertFalse(NotionService.isValidID("../pages"))
        XCTAssertFalse(NotionService.isValidID(""))
        let stamp = NotionService.isoTimestamp(Date(timeIntervalSince1970: 0))
        XCTAssertNotNil(stamp.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression))
    }
}

@MainActor
final class ProductivityTests: XCTestCase {
    func testTodosPersistAndOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let tasks = TasksService(fileURL: url)
        tasks.add("  Ship it  ")
        tasks.add("")
        tasks.add("Water plants")
        XCTAssertEqual(tasks.todos.map(\.text), ["Ship it", "Water plants"])
        tasks.toggle(tasks.todos[0].id)
        XCTAssertEqual(tasks.ordered.map(\.text), ["Water plants", "Ship it"])
        XCTAssertEqual(tasks.openCount, 1)
        tasks.note = "hello"
        tasks.save()
        let reloaded = TasksService(fileURL: url)
        XCTAssertEqual(reloaded.todos.count, 2)
        XCTAssertEqual(reloaded.note, "hello")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testDownloadNames() {
        XCTAssertEqual(DownloadsService.finalName(for: "report.pdf.crdownload"), "report.pdf")
        XCTAssertEqual(DownloadsService.finalName(for: "movie.mp4.download"), "movie.mp4")
        XCTAssertEqual(DownloadsService.finalName(for: "x.zip.part"), "x.zip")
        XCTAssertEqual(DownloadsService.finalName(for: "Unconfirmed 123.crdownload"), "Download")
        XCTAssertNil(DownloadsService.finalName(for: "photo.jpg"))
    }

    func testCPUUsageMath() {
        XCTAssertEqual(SystemStatsService.cpuUsage(previous: (100, 1000), current: (350, 2000)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(SystemStatsService.cpuUsage(previous: (5, 10), current: (5, 10)), 0)
        XCTAssertNotNil(SystemStatsService.cpuTicks())
        let mem = try? XCTUnwrap(SystemStatsService.memoryUsage())
        XCTAssertTrue((0...1).contains(mem ?? -1))
    }

    func testMonthGridAndAgendaLabels() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // Monday
        cal.timeZone = TimeZone(identifier: "UTC")!
        let nov2026 = cal.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        let cells = MonthGrid.cells(for: nov2026, calendar: cal)
        XCTAssertEqual(cells.prefix(6).compactMap { $0 }.count, 0)   // Nov 1, 2026 is a Sunday
        XCTAssertEqual(cells[6], 1)
        XCTAssertEqual(cells.compactMap { $0 }.count, 30)
        XCTAssertEqual(MonthGrid.weekdaySymbols(cal).count, 7)
        XCTAssertEqual(AgendaGrouping.label(for: Date()), "Today")
        XCTAssertEqual(AgendaGrouping.label(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!), "Tomorrow")
    }

    func testImageConversionWritesANewFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("pic.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: src)
        XCTAssertTrue(ShelfTools.isConvertibleImage(src))
        let out = try XCTUnwrap(ShelfTools.convert(src, to: .jpeg))
        XCTAssertEqual(out.lastPathComponent, "pic.jpg")
        let again = try XCTUnwrap(ShelfTools.convert(src, to: .jpeg))
        XCTAssertEqual(again.lastPathComponent, "pic 2.jpg")    // never overwrites
    }
}

final class UpdateConfigTests: XCTestCase {
    func testUpdaterNeedsARealKey() {
        XCTAssertFalse(UpdateService.isConfigured(publicKey: nil))
        XCTAssertFalse(UpdateService.isConfigured(publicKey: "__SPARKLE_PUBLIC_KEY__"))
        XCTAssertFalse(UpdateService.isConfigured(publicKey: "short"))
        XCTAssertTrue(UpdateService.isConfigured(publicKey: "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="))
    }
}

import AppKit

/// Now Playing for media playing in a browser tab (YouTube, YouTube Music, SoundCloud, …).
///
/// Public and permission-gated: AppleScript asks the browser to run a small read-only script in
/// tabs on known media sites. It reads the page's standard Media Session metadata
/// (`navigator.mediaSession`) and its <video>/<audio> element. It needs:
///   1. Automation permission for the browser (macOS asks once), and
///   2. the browser's "Allow JavaScript from Apple Events" developer setting.
/// Only tabs whose URL matches `mediaHosts` are ever touched.
struct BrowserMediaProvider: MediaProvider {
    enum Engine: Sendable { case chromium, safari }

    let id: String
    let displayName: String      // AppleScript application name
    let bundleID: String
    let engine: Engine

    static let chrome = BrowserMediaProvider(id: "chrome", displayName: "Google Chrome", bundleID: "com.google.Chrome", engine: .chromium)
    static let safari = BrowserMediaProvider(id: "safari", displayName: "Safari", bundleID: "com.apple.Safari", engine: .safari)
    static let arc = BrowserMediaProvider(id: "arc", displayName: "Arc", bundleID: "company.thebrowser.Browser", engine: .chromium)
    static let brave = BrowserMediaProvider(id: "brave", displayName: "Brave Browser", bundleID: "com.brave.Browser", engine: .chromium)
    static let edge = BrowserMediaProvider(id: "edge", displayName: "Microsoft Edge", bundleID: "com.microsoft.edgemac", engine: .chromium)

    static let all: [BrowserMediaProvider] = [.chrome, .safari, .arc, .brave, .edge]

    /// Tabs on these sites are probed. Everything else is left alone.
    static let mediaHosts = ["music.youtube.com", "youtube.com", "youtu.be", "soundcloud.com",
                             "open.spotify.com", "bandcamp.com", "music.apple.com", "tidal.com",
                             "deezer.com", "pandora.com", "twitch.tv", "vimeo.com"]

    /// Sentinel ScriptFailure code: the browser refuses JavaScript from Apple Events.
    static let javaScriptDisabledCode = -9001

    var setupInstructions: String {
        switch engine {
        case .safari:
            return "In Safari, open Settings › Advanced and turn on “Show features for web developers”, then choose Develop › Allow JavaScript from Apple Events."
        case .chromium:
            return "In \(displayName), choose View › Developer › Allow JavaScript from Apple Events."
        }
    }

    // MARK: Page scripts (single quotes only, so they embed cleanly in AppleScript strings)

    /// Page-side gate: bail out unless the tab's real hostname is an allowed media host or a
    /// subdomain of one. The AppleScript URL filter is only a cheap pre-filter.
    static var hostGateJS: String {
        let list = mediaHosts.map { "'\($0)'" }.joined(separator: ",")
        return "var tnH=location.hostname.toLowerCase();if(![\(list)].some(function(d){return tnH===d||tnH.slice(-(d.length+1))==='.'+d;})){return '';}"
    }

    /// Returns "" when the tab has no media; otherwise "1" (playing) or "0" (paused) followed by JSON.
    private static var probeJS: String { "(function(){" + hostGateJS + probeBodyJS }

    private static let probeBodyJS = """
    var m=Array.prototype.slice.call(document.querySelectorAll('video,audio')).filter(function(x){return x.currentSrc||x.src;});\
    var e=m.filter(function(x){return !x.paused;})[0]||m[0];if(!e){return '';}\
    var s=navigator.mediaSession,md=s&&s.metadata,art='';\
    if(md&&md.artwork&&md.artwork.length){art=md.artwork[md.artwork.length-1].src||'';}\
    var t=(md&&md.title)||document.title.replace(/ - YouTube( Music)?$/,'');\
    return (e.paused?'0':'1')+JSON.stringify({t:t,a:(md&&md.artist)||'',al:(md&&md.album)||'',\
    d:isFinite(e.duration)?e.duration:0,p:e.currentTime||0,art:art,h:location.hostname});})()
    """

    /// Finds the media element (playing first) — shared by the action scripts.
    private static let mediaJS = "function tnMedia(){var m=Array.prototype.slice.call(document.querySelectorAll('video,audio')).filter(function(x){return x.currentSrc||x.src;});return m.filter(function(x){return !x.paused;})[0]||m[0];}"

    /// After a skip, sites load the next item into the same element. A script from Apple Events is
    /// not a user gesture, so some browsers (Safari especially) leave the new item paused. If the
    /// page was playing before the skip, nudge it back to playing.
    private static let resumeJS = "function tnResume(was){if(!was){return;}[1200,2500].forEach(function(ms){setTimeout(function(){var x=tnMedia();if(x&&x.paused){var p=x.play();if(p&&p.catch){p.catch(function(){});}}},ms);});}"

    private static func click(_ selectors: [String], tag: String) -> String {
        selectors.map { "var b=document.querySelector('\($0)');if(b){b.click();tnResume(was);return '\(tag)';}" }.joined()
    }

    /// Returns which strategy fired ("" if none) so the app can log it.
    static func actionJS(_ command: MediaCommand) -> String {
        let prelude = "\(hostGateJS)\(mediaJS)\(resumeJS)var e=tnMedia();var was=!!(e&&!e.paused);var yt=location.hostname.indexOf('youtube.com')>=0;"
        switch command {
        case .playPause:
            return "(function(){\(hostGateJS)\(mediaJS)var e=tnMedia();if(!e){return '';}if(e.paused){var p=e.play();if(p&&p.catch){p.catch(function(){});}}else{e.pause();}return 'ok';})()"
        case .next:
            return "(function(){\(prelude)"
                // YouTube Music player bar
                + click(["ytmusic-player-bar .next-button"], tag: "ytm")
                // YouTube: the player's Next link (hidden outside playlists but still carries the up-next href)
                + "var a=document.querySelector('.ytp-next-button');if(a&&a.getAttribute('href')){a.click();tnResume(was);return 'ytp';}"
                // YouTube keyboard shortcut Shift+N
                + "if(yt){document.dispatchEvent(new KeyboardEvent('keydown',{key:'N',code:'KeyN',keyCode:78,which:78,shiftKey:true,bubbles:true,cancelable:true}));tnResume(was);return 'key';}"
                // Other players
                + click(["[data-testid=\"control-button-skip-forward\"]", ".skipControl__next", "button[aria-label=\"Next\"]",
                         "button[aria-label^=\"Next track\"]", "button[title^=\"Next\"]"], tag: "button")
                // Last resort: jump to the end so the site's autoplay moves on
                + "if(e&&isFinite(e.duration)&&e.duration>1){e.currentTime=e.duration-0.25;return 'end';}return '';})()"
        case .previous:
            return "(function(){\(prelude)"
                + "if(e&&e.currentTime>4){e.currentTime=0;return 'restart';}"
                + click(["ytmusic-player-bar .previous-button"], tag: "ytm")
                + "var a=document.querySelector('.ytp-prev-button');if(a&&a.getAttribute('href')&&getComputedStyle(a).display!=='none'){a.click();tnResume(was);return 'ytp';}"
                + click(["[data-testid=\"control-button-skip-back\"]", ".skipControl__previous", "button[aria-label=\"Previous\"]",
                         "button[aria-label^=\"Previous track\"]", "button[title^=\"Previous\"]"], tag: "button")
                + "if(e){e.currentTime=0;return 'restart';}return '';})()"
        }
    }

    // MARK: AppleScript

    /// Exact host test on the URL the browser reports (not on anything the page controls).
    private func hostCondition(_ variable: String) -> String {
        Self.mediaHosts.map { "\(variable) is \"\($0)\" or \(variable) ends with \".\($0)\"" }.joined(separator: " or ")
    }

    /// AppleScript handler: "https://music.youtube.com/watch?v=1" → "music.youtube.com".
    private static let hostOfHandler = """
    on hostOf(u)
        set h to ""
        try
            set AppleScript's text item delimiters to "://"
            if (count of text items of u) > 1 then
                set afterScheme to text item 2 of u
                set AppleScript's text item delimiters to "/"
                set h to text item 1 of afterScheme
            end if
        end try
        set AppleScript's text item delimiters to ""
        return h
    end hostOf
    """

    private func runJS(_ js: String, tab: String) -> String {
        let escaped = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        switch engine {
        case .chromium: return "execute \(tab) javascript \"\(escaped)\""
        case .safari: return "do JavaScript \"\(escaped)\" in \(tab)"
        }
    }

    /// Walks every window and tab, runs `probe` on media-site tabs, and returns the best result:
    /// a playing tab beats a paused one. "JSOFF" means the browser refused to run JavaScript.
    private func scanScript(probe: String, then action: String? = nil) -> String {
        var actionBlock = ""
        if let action {
            actionBlock = "if bestTab is not missing value then\n"
                + "set actionResult to \(runJS(action, tab: "bestTab"))\n"
                + "if actionResult is missing value then set actionResult to \"\"\n"
                + "return \"ACT:\" & actionResult\n"
                + "end if\n"
                + "return \"ACT:notab\""
        }
        return """
        \(Self.hostOfHandler)
        if application "\(displayName)" is not running then return ""
        with timeout of 3 seconds
            tell application "\(displayName)"
                set bestResult to ""
                set bestTab to missing value
                set bestURL to ""
                set jsOff to false
                set seen to 0
                repeat with w in windows
                    repeat with t in tabs of w
                        set seen to seen + 1
                        if seen > 80 then exit repeat
                        set u to ""
                        try
                            set u to URL of t
                        end try
                        if u is missing value then set u to ""
                        set hst to my hostOf(u)
                        if \(hostCondition("hst")) then
                            try
                                set r to \(runJS(probe, tab: "t"))
                                if r is missing value then set r to ""
                                if r is not "" then
                                    if r starts with "1" then
                                        set bestResult to r
                                        set bestTab to t
                                        set bestURL to u
                                        exit repeat
                                    else if bestResult is "" then
                                        set bestResult to r
                                        set bestTab to t
                                        set bestURL to u
                                    end if
                                end if
                            on error errMsg number errNum
                                if errNum is -1743 then error errMsg number errNum
                                if errMsg contains "JavaScript" then set jsOff to true
                            end try
                        end if
                    end repeat
                    if bestResult starts with "1" then exit repeat
                end repeat
                \(actionBlock)
                if bestResult is "" and jsOff then return "JSOFF"
                if bestResult is "" then return ""
                return bestURL & linefeed & bestResult
            end tell
        end timeout
        """
    }

    func snapshot() -> Result<MediaSnapshot?, ScriptFailure> {
        switch AppleScriptRunner.run(scanScript(probe: Self.probeJS)) {
        case .failure(let f):
            return .failure(f)
        case .success(let desc):
            let text = desc.stringValue ?? ""
            if text == "JSOFF" { return .failure(ScriptFailure(code: Self.javaScriptDisabledCode)) }
            // "<tab URL as reported by the browser>\n<page result>"
            guard let newline = text.firstIndex(of: "\n") else { return .success(nil) }
            let tabURL = String(text[..<newline])
            return .success(Self.parse(String(text[text.index(after: newline)...]), browser: displayName, tabURL: tabURL))
        }
    }

    /// Parses "1{json}" / "0{json}". `tabURL` is the browser-reported address; when given, its host
    /// (not the page's own claim) decides whether the tab counts as a media site. Exposed for tests.
    static func parse(_ text: String, browser: String, tabURL: String? = nil) -> MediaSnapshot? {
        guard let flag = text.first, flag == "0" || flag == "1",
              let data = text.dropFirst().data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = obj["t"] as? String, !title.isEmpty else { return nil }
        let host = tabURL.map { URL(string: $0).flatMap { $0.scheme == "https" ? $0.host : nil } ?? "" }
            ?? ((obj["h"] as? String) ?? "")
        guard HostMatch.host(host, isOrIsUnderAnyOf: mediaHosts) else { return nil }
        return MediaSnapshot(
            title: title,
            artist: (obj["a"] as? String) ?? "",
            album: (obj["al"] as? String) ?? "",
            duration: (obj["d"] as? Double) ?? 0,
            position: (obj["p"] as? Double) ?? 0,
            playing: flag == "1",
            artworkURL: (obj["art"] as? String) ?? "",
            sourceLabel: "\(siteName(for: host)) · \(shortBrowserName(browser))"
        )
    }

    static func siteName(for host: String) -> String {
        switch true {
        case HostMatch.host(host, isOrIsUnder: "music.youtube.com"): return "YouTube Music"
        case HostMatch.host(host, isOrIsUnderAnyOf: ["youtube.com", "youtu.be"]): return "YouTube"
        case HostMatch.host(host, isOrIsUnder: "soundcloud.com"): return "SoundCloud"
        case HostMatch.host(host, isOrIsUnder: "open.spotify.com"): return "Spotify Web"
        case HostMatch.host(host, isOrIsUnder: "music.apple.com"): return "Apple Music Web"
        case HostMatch.host(host, isOrIsUnder: "bandcamp.com"): return "Bandcamp"
        case HostMatch.host(host, isOrIsUnder: "twitch.tv"): return "Twitch"
        default: return host.isEmpty ? "Web" : host
        }
    }

    static func shortBrowserName(_ name: String) -> String {
        name.replacingOccurrences(of: "Google ", with: "")
            .replacingOccurrences(of: " Browser", with: "")
            .replacingOccurrences(of: "Microsoft ", with: "")
    }

    func send(_ command: MediaCommand) {
        switch AppleScriptRunner.run(scanScript(probe: Self.probeJS, then: Self.actionJS(command))) {
        case .success(let desc):
            Log.media.info("browser \(self.id, privacy: .public) \(command.appleScriptVerb, privacy: .public) -> \(desc.stringValue ?? "nil", privacy: .public)")
        case .failure(let f):
            Log.media.error("browser \(self.id, privacy: .public) \(command.appleScriptVerb, privacy: .public) failed: \(f.code)")
        }
    }

    func artwork(for snapshot: MediaSnapshot) -> NSImage? { nil }   // fetched from artworkURL by the service
}

extension BrowserMediaProvider {
    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
}

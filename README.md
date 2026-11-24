<p align="center">
  <img src="Resources/Logo.png" width="420" alt="Tuck Notch">
</p>

<h1 align="center">Tuck Notch</h1>

<p align="center">
  A native, privacy-first activity center for the MacBook notch.<br>
  Invisible when nothing's happening. Informative at a glance. Actionable when you need it.
</p>

## What it does

Tuck Notch turns the notch into a live island that grows out of the camera housing.

| | |
|---|---|
| **Live activities** | Album art and an equalizer beside the camera while music plays; countdowns, browser downloads, mic-muted and keep-awake indicators. |
| **Media** | Apple Music and Spotify. Optionally YouTube, YouTube Music, SoundCloud and other web players in Chrome, Safari, Arc, Brave and Edge. Artwork, progress, remaining time, controls, volume, output switching, optional synced lyrics. |
| **Home** | Choose up to four cards: Now Playing, YouTube, Weather, Calendar, To-dos, Notes, Pulse (CPU, memory, battery), Focus timer, File shelf, Quick controls, Activity. |
| **Calendar** | The next three days grouped by day, a month grid with busy-day dots and the week number, and a one-click **Join** button for Zoom, Meet, Teams, Webex, FaceTime and Whereby. Works with every calendar on your Mac (including Google through Internet Accounts) and, optionally, one Notion database. |
| **To-dos & notes** | A checklist and a scratchpad, saved on this Mac. |
| **Shelf** | Drop files on the notch and drag them out later. Files stay where they are. AirDrop from the shelf, or convert images to JPEG/PNG. |
| **Clipboard** | History with search, pinning, on-device OCR, per-app exclusions and retention limits. |
| **Focus** | Focus/Break presets and custom timers that live in the notch. |
| **Activity feed** | Optional: scripts, CI jobs and AI agents can post status and buttons to the island (the `tools/tucknotch-activity` script in this repository). |
| **Appearance** | Accent and activity colours, surface style, background opacity (clear or frosted glass), panel size, corners, text size, animation style, and what shows in the notch. |

Five island states (Dormant, Live, Peek on hover, Expanded on click or ⌃⌥K, and Attention for alerts that never steal focus) are managed by one activity engine, so nothing fights for the notch. See [ARCHITECTURE.md](ARCHITECTURE.md).

## Install

**Download:** get `TuckNotch-<version>.dmg` from [Releases](https://github.com/ASV-Labs/tuck-notch/releases/latest), open it and drag Tuck Notch to Applications. Releases are signed by ASV Labs and notarized by Apple, and they update themselves (Settings › General › Updates). Requires macOS 13 or later on a Mac with a notch; other Macs get a small island at the top of the screen.

**Build from source:** you need Xcode (or the Command Line Tools).

```bash
git clone https://github.com/ASV-Labs/tuck-notch.git
cd tuck-notch
./build.sh install      # builds "Tuck Notch.app", copies it to /Applications and launches it
```

Source builds don't update themselves. Tuck Notch lives in the menu bar and has no Dock icon.

## Requests and feedback

- **Feature ideas:** open a [feature request](https://github.com/ASV-Labs/tuck-notch/issues/new?template=feature_request.yml), or 👍 an existing one; votes decide what gets built next. Half-formed ideas are welcome in [Discussions › Ideas](https://github.com/ASV-Labs/tuck-notch/discussions/categories/ideas).
- **Bugs:** use the [bug report](https://github.com/ASV-Labs/tuck-notch/issues/new?template=bug_report.yml) form.
- **Security:** report privately through the [Security tab](https://github.com/ASV-Labs/tuck-notch/security/advisories/new).

### Media from your browser (optional)

Turn on the browsers you use in Settings › Media. Then let the browser share the page's now-playing details once:

- **Chrome / Arc / Brave / Edge:** View › Developer › **Allow JavaScript from Apple Events**
- **Safari:** Settings › Advanced › *Show features for web developers*, then Develop › **Allow JavaScript from Apple Events**

macOS also asks once for permission to control each browser. Tuck Notch reads the address of each open tab to find media sites, and only runs scripts in tabs whose host is a known media site (YouTube, YouTube Music, SoundCloud, Spotify Web, Apple Music Web, Bandcamp, Twitch and a few others). There it reads the title, artist, artwork and position; when you press a control it clicks that site's play/next/previous button or seeks the player.

## Privacy

- No accounts, no analytics, no tracking.
- Clipboard history stays in memory. Only text you pin is saved, in Tuck Notch's preferences file on this Mac.
- To-dos and notes are saved in `~/Library/Application Support/TuckNotch/notes.json`, readable only by you.
- What leaves your Mac:
  - **Weather** (once you pick a city): the city name you type while searching, then your chosen city's coordinates every 30 minutes, to Open-Meteo.
  - **Lyrics** (off by default): the track title and artist (for browser media, the page's media title) to LRCLIB.
  - **Notion** (only if you connect it): read-only requests to api.notion.com for the one database you choose. The secret is stored in your Keychain.
  - **Artwork** (whenever music plays): album art images are downloaded over HTTPS from the player's or site's image URL, without cookies or a disk cache.
  - **Updates** (release builds, can be turned off): once a day the app asks GitHub for the latest release's `appcast.xml`. No usage data is sent.
- Calendar data never leaves your Mac. Google Calendar works through System Settings › Internet Accounts.
- **Presentation mode** hides live content and pauses clipboard history while you share your screen.

Details: [SECURITY.md](SECURITY.md).

## Develop

```bash
swift build && swift test
./verify.command        # build + tests + launch + idle CPU/memory/energy log
./snapshots.command     # render every island state to snapshots/*.png
```

The snapshot renderer uses your real settings (for example a pinned clipboard item or your weather city). Look at every image before you share it.

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Maintainers: [RELEASING.md](RELEASING.md). Other docs: [UX-DESIGN-SYSTEM.md](UX-DESIGN-SYSTEM.md) · [TEST-PLAN.md](TEST-PLAN.md) · [ROADMAP.md](ROADMAP.md) · [KNOWN-ISSUES.md](KNOWN-ISSUES.md) · [CHANGELOG.md](CHANGELOG.md)

## License

The source code is licensed under the [Apache License 2.0](LICENSE) © 2026 ASV Labs LLC. Redistributions must keep the [NOTICE](NOTICE) file, which credits ASV Labs.

The artwork files `Resources/Logo.png`, `Resources/AppIcon.png` and `Resources/AppIcon.icns` are **not** covered by the Apache License: they are © ASV Labs LLC, all rights reserved. You may keep them unmodified in copies of this repository; to ship a modified or derived app, replace them with your own icon and use a different name. The "Tuck Notch" name is not licensed for other products.

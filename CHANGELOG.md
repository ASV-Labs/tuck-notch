# Changelog

## 0.6.0 (2026-11-24)
First public release.
- **Signed, notarized download:** Tuck Notch ships as a DMG signed with ASV Labs' Developer ID and notarized by Apple.
- **Automatic updates** with Sparkle: release builds check GitHub once a day and install signed updates. Settings › General › Updates has "Check for updates automatically" and "Check Now"; the menu bar has "Check for Updates…".
- **Feature requests:** issue forms for features and bugs, Discussions for ideas and questions.
- Hardened runtime with only the Apple Events and Calendars entitlements.


## 0.5.3 (2026-11-24)
- Opacity is now real see-through: by default the island is clear glass, so lowering opacity shows the windows and wallpaper behind it instead of a lighter grey.
- "Frosted glass" is optional (off by default) and its strength follows the slider, so low opacity stays mostly clear even when frosted.
- The drop shadow fades with opacity (it was showing through and darkening the island), and cards follow the slider more closely.


## 0.5.2 (2026-11-24)
- **Opacity slider** (Settings › Appearance › Style): make the open island see-through, from 30% to 100%. Cards fade less than the background so text stays readable. The notch itself and the live wings beside it stay solid so they still blend with the camera housing.
- **Blur what's behind the island**, on by default whenever opacity is below 100%.
- Reduce Transparency and Increase Contrast (System Settings › Accessibility) keep the island solid.


## 0.5.1 (2026-11-24)
Fixes from a second independent pre-release audit.
- Browser media decides whether a tab is a media site from the address the browser reports, matched on the exact host, before any script runs, and checks it again in the app. A page can no longer pass itself off as YouTube.
- New installs keep browser media off for good (0.5.0 could switch Chrome and Safari on after the first relaunch).
- Downloads: leftover or stalled partial files no longer stay in the notch or keep polling; active downloads are found even in very full Downloads folders; Safari's progress file is read safely.
- Artwork downloads stop as soon as they pass 4 MB instead of after the whole file.
- Notion page links open only if they're https links on notion.so or notion.site.
- The rename moves the old preferences instead of copying them, so no second copy of pinned clipboard text is left behind.
- To-dos and notes save on quit; an unreadable notes file is kept aside instead of overwritten; a note cut to the length limit is saved.
- Snapshot renders use throwaway settings and a temporary notes file, never your real data.
- Download file names are no longer written to the system log.
- `tools/tucknotch-activity` is executable; Settings and docs describe exactly what is read and sent.
- The logo and icon files are explicitly excluded from the Apache License (see NOTICE).

**Tests:** 35 unit tests (browser checks extended).


## 0.5.0 (2026-11-24)
**New name:** Top Notch is now **Tuck Notch**, with a new icon. Settings, the Notion secret and the activity feed folder move over automatically on first launch. macOS will ask again for Automation and Calendar access because the app identifier changed.

**New**
- Calendar panel: the next three days grouped by day ("Tomorrow", "Thu, Nov 26"), a month grid with dots on busy days, the week number, and Join buttons. The Home Calendar card now labels tomorrow's events instead of showing a bare time.
- Notes panel and Home cards: a to-do list (add, check off, delete, clear done) and a scratchpad note, saved on this Mac.
- Pulse card: CPU and memory with live sparklines, plus battery. Sampled every 2 s only while the island is open.
- Browser downloads (opt-in, Settings › General): progress for Chrome, Safari, Arc, Brave, Edge and Firefox downloads as a live activity, then a "Downloaded" alert with Show in Finder.
- Shelf: AirDrop the shelf or a single file, and convert images to JPEG or PNG (never overwrites).

**Security and privacy (from an independent pre-release audit)**
- Browser media only runs where the page's real hostname is an allowed media site (checked in the page and again in the app). Before, any tab whose address merely contained "youtube.com" was probed.
- Join buttons only appear for https links on the real meeting domains, so a calendar invite can't dress up a lookalike host or a non-web link.
- Artwork downloads use an ephemeral session (no cookies, no cache), accept images only and are capped at 4 MB.
- The activity feed reads only regular files (no symlinks, pipes or devices) with a bounded read.
- Notion: Keychain write failures are reported, ids are validated before use, the date filter uses full local timestamps, and items refresh when the island opens.
- Browser media is off by default for new installs (existing installs keep their setting), and the "enable JavaScript" hint only shows for that specific error. Scans are capped at 80 tabs.
- Large clipboard copies no longer stall the UI.
- `tucknotch-activity` drops control characters and checks that progress is between 0 and 1.
- Docs corrected: what leaves the Mac, permissions, polling, storage, and which features are opt-in.

**Tests:** 35 unit tests.


## 0.4.0 (2026-11-24)
**Weather**
- City search is now a clearly visible search box, both in Settings › Home and directly on the Weather card. Results appear as you type (350 ms debounce), with "Searching…", "No matches" and network-error states instead of failing silently.
- "Remove" to clear the city.

**Calendar**
- Google Calendar: an **Add Google Account…** button opens System Settings › Internet Accounts. Once a Google account is added with Calendars on, its events come through the existing EventKit integration (free, no extra login in Tuck Notch). Settings lists the accounts that supply calendars.
- Notion (opt-in): paste an internal-integration secret (stored in the Keychain), pick a database and its Date property, and today's items appear on the Calendar card next to your events. Click a Notion item to open the page; a Zoom/Meet/Teams link in a URL property gets the Join button. Read-only, Notion API 2025-09-03.

**Fixes**
- Next / previous track now work for YouTube and YouTube Music in the browser. The old script only clicked YouTube's playlist button, which isn't there for ordinary videos. It now tries the YouTube Music player bar, YouTube's up-next link, YouTube's Shift+N shortcut, then common Next buttons (Spotify Web, SoundCloud), and finally skips to the end so autoplay moves on. If the browser leaves the new track paused (Safari can, because a script isn't a click), Tuck Notch resumes it. Each skip is logged with the method used.
- Browser polling is lighter: every 3 s while music plays with the island closed (1 s with a panel open), every 5 s when nothing plays, plus an immediate re-check after every control.
- The Settings window now comes to the front on macOS 14 and later (uses `NSApp.activate()`).

**Tests:** 25 unit tests (city search parsing, Notion parsing and error messages, browser skip scripts).


## 0.3.0 (2026-11-24)
**Media**
- Browser media: YouTube, YouTube Music, SoundCloud and other web players in Chrome, Safari, Arc, Brave and Edge. Uses AppleScript plus the page's Media Session metadata. It only touches known media sites and needs a one-time browser setting.
- Remaining-time display and a "Playing from …" label.
- Optional synced lyrics from LRCLIB, with an "Instrumental" state.
- Per-source toggles.

**Home**
- Choose and order up to four cards.
- New cards: YouTube (paste a link, video ID or search), Weather (Open-Meteo, set by city, °F/°C) and Calendar (EventKit, Join button for Zoom/Meet/Teams/Webex/FaceTime/Whereby).

**Appearance**
- Accent and live-activity colours, surface style (Graphite / True Black / Tinted), panel size, corners, text size, animation style and quick-view delay.
- Toggles for wing artwork, equalizer, header clock, battery percentage and wordmark.
- Live preview in Settings.

**Settings**
- New toolbar-style window with General, Appearance, Home, Media, Privacy and Advanced panes.
- "Developer" is now "Advanced", and the inbox is explained in plain language as the Activity feed.

**Open source**
- Apache-2.0 LICENSE, NOTICE crediting ASV Labs, CONTRIBUTING, CI workflow and issue templates.
- Personal sample data removed.

**Tests:** 18 unit tests, up from 12.


## 0.2.0 — build-verified (2026-11-23)
**Verified on hardware:** clean release build (0 warnings), 12/12 tests, launch, idle 0.2% CPU / 38 MB footprint. Added `install.command`, `snapshots.command` and `--render-snapshots` (offscreen renders of every state), and evidence/. Post-review polish: attention card 470 pt wide, "Awake" chip label, and weak captures / nonisolated statics (Swift 6 readiness).
**Architecture:** central ActivityEngine (priority, stable ordering, expiry, attention queue with pre-emption, action routing). There are five computed island states (Dormant/Live/Peek/Expanded/Attention), and Services is the only bridge from modules to the island.
**UX:** design tokens with Increase Contrast variants; Home dashboard; Peek quick view; Attention cards that never take focus; expanded panel 480 pt; morphing single shape.
**Features:** presentation mode; media-provider abstraction; audio output switcher; keep awake; clipboard pinning, app exclusions, item cap, expiry; hotkey presets; opt-in external activity inbox/outbox + `tools/tucknotch-activity` CLI; Settings split into General / Privacy / Developer.
**Fixes from independent review:**
- Missing `import Combine` (compile).
- Automation-denied state was unreachable (AppleScript swallowed -1743).
- Players could be relaunched while quitting (`is running` guard).
- Scripts recompiled every tick (cache added), and AppleScript calls had no timeouts.
- Volume jumped to 0 on outputs without volume control.
- UPS could be reported as the battery.
- Esc didn't close the panel (`cancelOperation`).
- Island tap gesture could steal clicks.
- Panel stuck open after drag-and-drop.
- Return-key conflict.
- Timer "Done" never cleared from the island.
**Fixes from second review:**
- Hovering an alert no longer turns it into Peek.
- Publishers can withdraw alerts (clear, resolve, dismiss).
- Inbox checks file size before reading, stops re-reading rejected files, requires the payload id to match the filename, and can't be revived by a pending rescan after it's turned off.
- Spotify artwork is fetched asynchronously (5 s timeout) so it can't stall controls.
- The pass-through re-check runs while the pointer is over the island.
- Pause banner is published.
- Presentation mode isn't announced at launch.

**Efficiency:** now-playing polling backs off to 5 s when idle and skips entirely when no player runs; CoreAudio and app-quit changes are event-driven.
**Tests:** unit tests for format, inbox parser, clipboard filter, activity engine.


## 0.1.0 — unreleased, unverified (2026-11-23)
- Initial source: island over the notch, Media (Music/Spotify), Shelf, Clipboard + OCR, Timer, battery, mic mute, Settings, onboarding.
- Corrected privacy and mic wording after review (capture hiding and mic mute are best effort, not guarantees).
- Main-actor services are now created inside isolated contexts (`Services.init`, created in `applicationDidFinishLaunching`).
- Mic button is hidden when the input device exposes no controllable mute or volume.

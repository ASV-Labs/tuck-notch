# Architecture

```
TuckNotchMain ─ AppDelegate ─┬─ NotchWindowController × display ── NotchPanel ── NotchRootView (SwiftUI)
                            │        └─ NotchViewModel (user presentation: closed / peek / expanded)
                            └─ Services (one per app)
                                 ├─ ActivityEngine      ← the only path to the island
                                 ├─ NowPlayingService   → [MediaProvider] (AppleScript: Spotify, Music; BrowserMediaProvider: Chrome, Safari, Arc, Brave, Edge)
                                 ├─ CalendarService (EventKit) · NotionService (opt-in) · WeatherService (Open-Meteo) · LyricsService (LRCLIB)
                                 ├─ TasksService (to-dos + note) · SystemStatsService (CPU/memory, panel open only)
                                 ├─ DownloadsService (opt-in, ~/Downloads partial files)
                                 ├─ ClipboardService    (layered privacy filter, retention, pins)
                                 ├─ ShelfService        (file references, persisted)
                                 ├─ TimerService
                                 ├─ MicService · AudioDeviceService (CoreAudio listeners) · BatteryService
                                 ├─ KeepAwakeService    (IOPM assertion)
                                 └─ ExternalActivityInbox (opt-in JSON inbox/outbox)
```

## Island state
`IslandState` is computed in one place (`NotchRootView.state`) from the view model and the engine:

| State | When |
|---|---|
| Dormant | closed, no activities, no attention |
| Live | closed, `engine.primary` exists (wings show its icon + trailing text) |
| Peek | pointer rests on the notch (250 ms, no mouse button held, not presenting) |
| Expanded | click, hotkey, menu, or a file dragged onto the notch |
| Attention | closed and `engine.attention` exists; never takes keyboard focus |

## Activity engine
- `Activity`: id, source, symbol, title, subtitle, trailing, progress, tint, priority, createdAt, expiresAt, actions.
- Order: priority, then age (stable rows). Max 24; expired items swept every 5 s.
- `AttentionRequest`: one at a time, higher priority pre-empts (the current one is re-queued), auto-dismiss unless critical, max 10 queued.
- Presentation mode (`suppressed`): `primary` is nil and only critical attention shows; the rest is held and released afterwards.
- Actions route back via `registerHandler(source:)`. Modules publish through `Services` only, so no module manipulates the window.

## Threading
UI, services and the engine are `@MainActor`. AppleScript runs on one serial queue; Vision OCR runs on a global queue; CoreAudio listeners hop to the main actor.

## Event-driven vs polling
- Event-driven: Music/Spotify distributed notifications, CoreAudio device/default changes, screen changes, wake, inbox folder (DispatchSource).
- Event-driven (also): Downloads folder changes (DispatchSource), then 1 s polling only while a download is in progress.
- Polled (no event API exists): pasteboard changeCount 0.5 s; now playing 1 s while a panel is open, otherwise 3 s while playing and 5 s idle, and nothing when no player is running (plus an immediate re-check after every control); system volume only while a panel is open (with each 1 s now-playing poll); CPU/memory only while a panel is open (2 s); keep-awake countdown 30 s; battery 60 s; calendar 300 s; Notion 600 s (and when a panel opens, if older than 2 min); weather 1800 s; inbox fallback rescan 5 s.

## Persistence
- UserDefaults: settings, shelf paths, pinned clipboard text. Clipboard history is memory-only.
- Keychain: the Notion integration secret.
- `~/Library/Application Support/TuckNotch/`: `notes.json` (to-dos + note, 0600), `Inbox/` and `Outbox/` for the activity feed.
- No HTTP cache: network requests use ephemeral sessions.

## Appearance
`AppSettings` holds the appearance choices; `DS` tokens read them at render time and the island re-renders on `appearanceKey`. The exterior is always black.

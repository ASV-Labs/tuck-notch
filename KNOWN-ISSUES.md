# Known issues

Status: each release is built, unit-tested, launched and measured on a MacBook before it's tagged (see evidence/BASELINE.md). The on-screen checklist in TEST-PLAN.md is run by hand and not every item is recorded yet.

## Accepted risks
- **NSAppleScript off the main thread:** runs on one dedicated serial queue (never concurrently), with 3 s timeouts per Apple event. Apple lists it as main-thread-only; moving it to main would freeze the UI when a player hangs.
- **Browser scans:** with many tabs a single scan can take a few seconds (capped at 80 tabs per browser), which can delay a media control. The 3 s AppleScript timeout applies to each Apple event, not to the whole scan.
- **Click-through:** the canvas ignores the mouse outside the island (`ignoresMouseEvents`, driven by mouse-move monitors).
- **Ad-hoc signing (source builds):** Automation permissions and the Keychain item's access are tied to each build's signature, so macOS may ask again after every rebuild (including a Keychain prompt if Notion is connected). Signed releases keep their permissions across updates. Moving from a source build to a release asks once more.

## Technical limits
- Now Playing: Music, Spotify, and web players in Chrome, Safari, Arc, Brave and Edge. The private MediaRemote framework refuses un-entitled apps since macOS 15.4, so other native players aren't shown.
- Browser next/previous depends on each site's page structure; YouTube and YouTube Music are covered with several fallbacks.
- Chromium downloads don't report a total size, so their progress shows bytes and speed, not a percentage. A download that makes no progress for 60 seconds (paused, stalled or left over) is hidden until it changes again.
- After the rename from Top Notch, macOS may show one Keychain prompt on first launch if Notion was connected, while the secret moves to the new name.
- Screen capture: `sharingType = .none` is a request; ScreenCaptureKit on macOS 15+ may ignore it. Presentation mode is the control to rely on.
- Mic mute: default input device only, and only when it exposes mute or input volume.
- Clipboard filtering is best effort (markers + app exclusions + pause), not a guarantee.
- Hotkey is a preset list, not a recorder.
- Notion: the first 100 shared databases are listed.
- A replacement volume/brightness on-screen display and lock-screen widgets would need private APIs, so they aren't planned.

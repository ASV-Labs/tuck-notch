# Test plan

## Automated (`swift test`)
Format; external activity parser (validation, clamping, clipping, symbol fallback) and inbox file reads (symlinks, FIFOs, size limit); clipboard filter; activity engine (ordering, stable upsert, suppression, pre-emption, action routing); browser media parsing, host checks and skip scripts; YouTube links; LRC lyrics; weather and city-search parsing; meeting links (lookalike hosts, non-https schemes); Notion parsing, ids, timestamps and errors; to-dos persistence; download names; CPU math; month grid; image conversion.

## Baseline evidence (`verify.command`)
Toolchain, build, tests, launch, 60 s idle CPU/RSS, energy column, crash reports → `verify-<timestamp>.log`.

## Manual checklist (record pass/fail + screenshot per row)
1. Dormant island matches the hardware notch exactly (no visible edge) on the built-in display.
2. Peek after resting ~250 ms; no peek when sweeping across the menu bar or opening menu-bar menus.
3. Click → Expanded; Esc, click outside, and pointer leave all close it; hotkey toggles; focus returns to the previous app.
4. Live: music art + bars; timer countdown; mic-muted indicator; keep-awake.
5. Attention: timer finish shows actions, doesn't steal typing focus in TextEdit, auto-dismisses.
6. Presentation mode: no live/peek, clipboard paused, critical-only alerts, held alerts released after.
7. Media: Music and Spotify play/pause/next/prev, artwork, progress, Automation-denied state, nothing-playing state.
8. Audio output switch (built-in ↔ AirPods/USB), list updates on plug/unplug.
9. Mic: mute/unmute on built-in mic; button hidden for devices without controls.
10. Shelf: drop from Finder, drag out to Finder/Mail, context menu, persistence across relaunch, missing files pruned.
11. Clipboard: text/image capture, search, pin persists across relaunch, exclusion via context menu, 1Password copy skipped, OCR.
12. External inbox: `tools/tucknotch-activity` post/update/clear, needs-input attention, action → outbox.
13. Displays: external monitor pill (setting), clamshell, unplug while open, sleep/wake.
14. Full-screen apps and Mission Control: island not shown over full screen.
15. VoiceOver pass over every state; Increase Contrast; Reduce Motion.
16. Browser media: YouTube and YouTube Music in Chrome and Safari (title, artwork, progress, play/pause, next/previous), JS-from-Apple-Events off → setup hint, tab closed → clears.
17. Lyrics: synced song follows playback; instrumental and not-found states; toggle off sends nothing.
18. Calendar: Connect → permission prompt; events today; Join opens Zoom/Meet/Teams links; denied state.
19. Weather: city search, °F/°C, offline → retry state.
20. Appearance: every option changes the island live; Reset restores defaults.
21. Notion: connect with a secret, pick a database and Date property, items appear in Calendar; Disconnect removes the Keychain item.
22. Calendar panel: next three days grouped with Tomorrow/day labels, month grid dots, week number, Join buttons.
23. To-dos & notes: add/check/delete/clear done, note saves while typing, both survive relaunch.
24. Pulse card: CPU and memory move with load; battery shows charging state.
25. Downloads: Chrome and Safari downloads show progress and a "Downloaded" alert with Show in Finder.
26. Shelf: AirDrop sheet opens; Convert to JPEG/PNG adds the new file without overwriting.
27. Upgrade from Top Notch: settings, Notion secret and activity feed folder carry over.
28. Opacity: the slider makes the open island see-through (30–100%), clear by default and optionally frosted; the desktop behind is visible at 30%; dormant and live wings stay solid; Reduce Transparency forces it solid; Reset restores 100%.

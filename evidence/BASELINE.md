# Verification evidence

Logs and renders are produced locally by `verify.command` and `snapshots.command` and are not committed (they contain machine details). The tables below are the recorded results.

## v0.6.0 — 2026-11-24
Same machine and toolchain as below.

| Check | Result |
|---|---|
| Release build | **OK, 0 warnings** |
| Unit tests | **36/36 passed** |
| Launch | **OK**, no crash reports |
| Idle (60 s, 1 Hz) | avg CPU 0.15% of one core, peak 2.6%, RSS 93.7 MB (60 samples) |
| Memory | footprint **31M** (`top`) |
| Install | 0.6.0 in `/Applications`, launches |

## v0.5.3 — 2026-11-24
Same machine and toolchain as below.

| Check | Result |
|---|---|
| Release build | **OK, 0 warnings** |
| Unit tests | **35/35 passed** |
| Launch | **OK**, no crash reports |
| Idle (60 s, 1 Hz) | avg CPU 0.18% of one core, peak 2.4%, RSS 93.2 MB (60 samples) |
| Memory | footprint **30M+** (`top`) |
| Install | 0.5.3 in `/Applications`, launches |

## v0.5.2 — 2026-11-24
Same machine and toolchain as below.

| Check | Result |
|---|---|
| Release build | **OK, 0 warnings** |
| Unit tests | **35/35 passed** |
| Launch | **OK**, no crash reports |
| Idle (60 s, 1 Hz) | avg CPU 0.12% of one core, peak 2.4%, RSS 93.1 MB (60 samples) |
| Memory | footprint **30M** (`top`) |
| Install | 0.5.2 in `/Applications`, launches |

## v0.5.1 — 2026-11-24
Same machine and toolchain as below.

| Check | Result |
|---|---|
| Release build | **OK, 0 warnings** |
| Unit tests | **35/35 passed** |
| Launch | **OK**, no crash reports |
| Idle (60 s, 1 Hz) | avg CPU 0.06% of one core, peak 0.6%, RSS 90.9 MB (60 samples) |
| Memory | footprint **31M+** (`top`) |
| Install | 0.5.1 in `/Applications`, launches |

## v0.5.0 — 2026-11-24
Same machine and toolchain as below (MacBook Pro, Apple Silicon, macOS 27.2.1, Swift 6.4.2).

| Check | Result |
|---|---|
| Release build | **OK, 0 warnings** |
| Unit tests | **35/35 passed** (adds host checks, Join-link validation, inbox file reads, Notion ids/timestamps, to-dos, downloads, CPU math, month grid, image conversion) |
| Launch | **OK**, no crash reports |
| Idle CPU (60 s, 1 Hz) | **avg 0.10% of one core**, peak 1.0% |
| Memory | footprint **30 MB** (`top`); RSS 90.8 MB |
| Energy (`top` POWER) | 0.1 |
| Install | 0.5.0 in `/Applications`, launches |

## v0.4.0 — 2026-11-24
Build OK with 0 warnings, 25/25 tests, installed. The idle sample was taken while YouTube was playing in a browser (avg 6.8% CPU, before polling was reduced), so it isn't comparable to the idle figures above and below.

## v0.3.0 — 2026-11-24
Same machine and toolchain as below.

| Check | Result |
|---|---|
| Release build | **OK, 0 warnings** |
| Unit tests | **18/18 passed** (adds browser media parsing, YouTube links, LRC lyrics, weather parsing, meeting links) |
| Launch | **OK**, no crash reports |
| Idle CPU (60 s, 1 Hz) | **avg 0.09% of one core**, peak 1.0% |
| Memory | footprint **29 MB** (`top`); RSS 87.5 MB |
| Energy (`top` POWER) | 0.2 |
| Live APIs | Open-Meteo forecast + geocoding and LRCLIB search answered with the fields the parsers expect (checked 2026-11-24) |
| Install | 0.3.0 in `/Applications`, launches |

Renders were regenerated for v0.3.

## v0.2.0 — 2026-11-23 (local time)

Machine: MacBook Pro (Apple Silicon, arm64), macOS 27.2.1, Xcode toolchain, Swift 6.4.2.
Produced by `verify.command`.

| Check | Result |
|---|---|
| Release build | **OK**, 0 warnings (after fixing 18 capture/isolation warnings from the first run) |
| Unit tests | **12/12 passed** (engine, inbox parser, clipboard filter, format) |
| Launch | **OK**, process stays running, no crash reports |
| Idle CPU (60 s, 1 Hz) | **avg 0.21% of one core**, peak 0.9% (target < 0.5%) — first run 0.18% / 0.8% |
| Memory | footprint **38 MB** (`top` MEM; target < 100 MB). RSS 103 MB includes shared system frameworks |
| Energy (`top` POWER) | 0.2–0.3 at idle |
| Install | `install.command` → `/Applications`, launches |

## State renders (local `snapshots/`, not committed)
Produced by `snapshots.command` (`TuckNotch --render-snapshots`): the real SwiftUI views rendered offscreen with sample data.
Dormant, Live, Peek, Expanded (Home, Media, Shelf, Clipboard, Focus, Activity), Attention, Presentation mode, Onboarding.

Renderer limits (not app bugs): AppKit-backed controls (sliders, menus, text fields, steppers, the drop/hover target) appear as yellow placeholders, and `ScrollView` contents (shelf, clipboard and activity lists) render empty. Those need on-screen checks.

## Not yet verified on screen
The TEST-PLAN manual checklist (hover/peek timing, menu-bar click-through, drag and drop, Music/Spotify, audio switching, mic, clipboard capture, inbox CLI, multi-display, full screen, VoiceOver). Daily use on the maintainer's MacBook found no problems so far; the formal checklist pass is still to be recorded.

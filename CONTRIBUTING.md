# Contributing to Tuck Notch

Thanks for helping. Tuck Notch is a native SwiftUI + AppKit app built with Swift Package Manager. You don't need an Xcode project.

## Ideas and requests

- New feature? Open a **Feature request** issue (the form asks what you're trying to do), or 👍 an existing one. Reactions are how we rank the backlog.
- Not sure yet? Start a thread in **Discussions › Ideas**.
- Want to build it yourself? Comment on the issue first so we can agree on the approach, then open a pull request that links it.

## Build and test

```bash
swift build            # debug build
swift test             # unit tests
./build.sh run         # build "Tuck Notch.app" and launch it
./build.sh install     # copy to /Applications and launch
./verify.command       # build + tests + launch + 60 s idle CPU/memory/energy log
./snapshots.command    # render every island state to snapshots/*.png
./demo-tour.command    # capture the real app with fictional sample content to demo-captures/
```

Requires macOS 13+ and Xcode (or the Command Line Tools).

## How the code fits together

Read [ARCHITECTURE.md](ARCHITECTURE.md) first. Its core rule is that **modules never touch the island window**. A module publishes `Activity` and `AttentionRequest` values through `Services` into the `ActivityEngine`. The engine decides what is shown, and when.

| Where | What |
|---|---|
| `NotchRootView.swift` | the island and its five states |
| `HomeView.swift`, `PanelViews.swift` | Home cards and the panels |
| `DesignSystem.swift` | design tokens; use `DS.*`, not hard-coded colours or sizes |
| `NowPlayingService.swift`, `BrowserMediaProvider.swift` | media providers |
| `Integrations.swift` | calendar, Notion, Keychain helper, weather, lyrics |
| `Productivity.swift`, `ProductivityViews.swift` | to-dos and notes, Pulse stats, downloads, shelf tools, Calendar and Notes panels |
| `Migration.swift` | one-time carry-over from the old name |
| `Updates.swift` | Sparkle auto-updates (release builds only) |
| `release.sh`, `RELEASING.md` | maintainer release pipeline: sign, notarize, DMG, appcast, GitHub release |
| `SettingsView.swift` | the Settings window |

## Ground rules

- **Privacy first.** A feature that sends data off the Mac must be opt-in, off by default, and disclosed in Settings and in [SECURITY.md](SECURITY.md). Ask for permissions in context, never all up front.
- **Public APIs only** in the required path. Anything that bypasses an entitlement can only ship as an optional, clearly labelled extra.
- **Accessibility:** give every control a VoiceOver label, use hit targets of at least 28 pt, and respect Reduce Motion and Increase Contrast.
- **Performance:** idle CPU must stay under 0.5% of one core. Prefer events to polling. If you must poll, back off when idle.
- Add or update unit tests for logic, and run `swift test` before opening a PR.
- Keep PRs focused, and describe what you changed and how you tested it, with a screenshot for UI changes.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE) (Section 5).

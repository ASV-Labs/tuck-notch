# Security and privacy

| Area | Control | Limit |
|---|---|---|
| Clipboard | Skips concealed/transient/auto-generated pasteboard types; built-in password-manager blocklist; user app exclusions; manual pause; auto-pause in presentation mode; item cap; optional expiry; history is memory-only. Pinned text is stored in the app's preferences (`~/Library/Preferences/com.asvlabs.tucknotch.plist`) | Can't guarantee a secret is never captured (e.g. a password copied from a plain text field in a non-excluded app) |
| Screen capture | `sharingType = .none` request + **presentation mode** (hides content) | No public API prevents ScreenCaptureKit capture (Apple DTS) |
| Music / Spotify | AppleScript via Automation permission; never launches players | No entitlement bypasses in the required path |
| Browser media (opt-in per browser) | Reads every tab's URL to find media sites; runs scripts only where the page's own hostname is an allowed media host (checked by the page script and again in the app). Scripts read title/artist/artwork/position; controls click the site's buttons, send YouTube's Shift+N shortcut, seek, or call `play()`. Needs Automation permission and the browser's "Allow JavaScript from Apple Events" | Media metadata from those sites is shown and, if lyrics are on, sent to LRCLIB |
| Artwork | HTTPS only, ephemeral session (no cookies, no cache), 4 MB cap, image MIME types only | Image URLs are chosen by the player or site |
| Calendar | EventKit, opt-in, read-only; nothing leaves the Mac. Google calendars come through macOS Internet Accounts, so Tuck Notch never sees Google credentials. Join buttons appear only for https links on the real Zoom/Meet/Teams/Webex/FaceTime/Whereby domains | Opening a Join link opens it in your browser or the meeting app |
| Notion (opt-in) | Internal-integration secret stored in the macOS Keychain (never in preferences or logs); read-only search + data-source query; ids validated before use | Anyone with your secret can read the databases you shared with it. Disconnect deletes it from the Keychain |
| Weather (opt-in) | Typed city search text, then the chosen city's coordinates, to Open-Meteo | none |
| Lyrics (opt-in) | Title and artist to LRCLIB | none |
| To-dos & notes | Local JSON file, mode 0600, in Application Support | Not encrypted at rest beyond FileVault |
| Downloads (opt-in) | Lists `~/Downloads` and reads sizes of in-progress `.crdownload`/`.download`/`.part` files (and Safari's progress plist); never reads file contents | macOS asks for Downloads folder access |
| External activities (opt-in) | User-owned folders (0700); regular files only (no symlinks, pipes or devices), 32 KB/file, 20 files, id regex, string clipping, max 3 actions, no critical priority, unknown SF Symbols replaced; outbox responses only | Any process running as the user can publish (same trust boundary as the user account) |
| Permissions | Automation (Music, Spotify and the browsers you turn on), Calendars (when you connect), Downloads folder (when you turn on downloads). The hotkey uses Carbon and needs no Accessibility permission | |
| Updates (release builds) | Sparkle 2 checks GitHub once a day over HTTPS. An update installs only if its EdDSA signature matches the public key built into the app and it's signed with the same Developer ID; releases are notarized by Apple. No system profile is sent | Source builds don't update |
| Not built, by policy | Webcam unlock, stored login credentials, MediaRemote entitlement bypass as a required dependency | |

## Reporting a vulnerability

Please use GitHub's private **Report a vulnerability** button on this repository (Security tab) instead of opening a public issue. We'll acknowledge within a few days.

# Releasing Tuck Notch

Releases are DMGs signed with ASV Labs' Developer ID, notarized by Apple and published as GitHub releases. Installed copies update themselves with [Sparkle](https://sparkle-project.org): every day they read `appcast.xml` from the latest release and check the update's EdDSA signature against the public key in `Resources/Info.plist`.

## One-time setup (maintainer's Mac)

1. **Developer ID certificate:** a "Developer ID Application" certificate in the login keychain (Xcode › Settings › Accounts › Manage Certificates).
2. **Notary credentials:** create an app-specific password at account.apple.com, then
   ```bash
   xcrun notarytool store-credentials "tucknotch-notary" --apple-id <Apple ID> --team-id <Team ID>
   ```
3. **Sparkle signing key:** generated once and kept in the login keychain:
   ```bash
   swift package resolve
   "$(find .build/artifacts -name generate_keys -type f | head -1)"      # prints the public key
   ```
   Put the public key in `SUPublicEDKey` in `Resources/Info.plist`. Back up the private key (`generate_keys -x <file>`) somewhere safe: without it, existing installs can't verify future updates.
4. **GitHub CLI:** `gh auth login` with access to the repository.

## Each release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Add a `## <version> (<date>)` section to `CHANGELOG.md`; it becomes the release notes.
3. If the UI changed, refresh the screenshots: `./demo-tour.command`, then `python3 tools/marketing/compose.py demo-captures out Resources/AppIcon.png` and copy the images you need into `docs/images/` (README images are 1200×675 JPEGs, the hero 1600×900).
4. Commit and push to `main`.
5. Run `./release.sh` (or `./release.sh --dry-run` to stop before publishing).

The script signs Sparkle's helpers and the app with the hardened runtime, notarizes and staples the app, builds and notarizes the DMG, signs it for Sparkle, writes `appcast.xml`, and creates the GitHub release with both files attached.

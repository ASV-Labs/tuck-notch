#!/bin/bash
# Builds, signs (Developer ID + hardened runtime), notarizes and publishes a Tuck Notch release:
#   build/release/TuckNotch-<version>.dmg  +  appcast.xml  →  GitHub release v<version>
# The app's auto-updater (Sparkle) reads appcast.xml from the latest GitHub release.
# One-time setup is described in RELEASING.md.
#   ./release.sh            full release
#   ./release.sh --dry-run  build, sign, notarize and package, but don't publish
set -euo pipefail
cd "$(dirname "$0")"

REPO="${REPO:-ASV-Labs/tuck-notch}"
PROFILE="${NOTARY_PROFILE:-tucknotch-notary}"
DRY_RUN="${1:-}"
PLIST=Resources/Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
IDENTITY="${DEVELOPER_ID:-$(security find-identity -v -p codesigning | grep -m1 '"Developer ID Application' | sed -E 's/.*"(.*)"/\1/')}"

fail() { echo "✗ $*" >&2; exit 1; }
[ -n "$IDENTITY" ] || fail "No 'Developer ID Application' certificate in your keychain."
grep -q "__SPARKLE_PUBLIC_KEY__" "$PLIST" && fail "SUPublicEDKey is not set in $PLIST (see RELEASING.md)."
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || fail "Notary profile '$PROFILE' not found. Run: xcrun notarytool store-credentials \"$PROFILE\" --apple-id <your Apple ID> --team-id <your Team ID>"
if [ "$DRY_RUN" != "--dry-run" ]; then
  command -v gh >/dev/null || fail "GitHub CLI (gh) is required to publish."
  gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 && fail "Release v$VERSION already exists. Bump the version in $PLIST."
fi

echo "→ Tuck Notch $VERSION ($BUILD), signing as: $IDENTITY"
./build.sh
APP="build/Tuck Notch.app"
OUT=build/release
rm -rf "$OUT"; mkdir -p "$OUT"

echo "→ Signing with Developer ID + hardened runtime…"
sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }
SPK="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPK/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPK/Versions/B/XPCServices/Downloader.xpc"
sign "$SPK/Versions/B/Autoupdate"
sign "$SPK/Versions/B/Updater.app"
sign "$SPK"
sign --entitlements Resources/TuckNotch.entitlements "$APP"
codesign --verify --deep --strict "$APP"

echo "→ Notarizing the app (a few minutes)…"
ditto -c -k --keepParent "$APP" "$OUT/app.zip"
xcrun notarytool submit "$OUT/app.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$OUT/app.zip"

echo "→ Building the DMG…"
DMG="$OUT/TuckNotch-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Tuck Notch.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tuck Notch $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "→ Notarizing the DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"

echo "→ Signing the update for Sparkle…"
SIGN_UPDATE=$(find .build/artifacts -type f -name sign_update -perm -u+x | head -1)
[ -n "$SIGN_UPDATE" ] || fail "Sparkle's sign_update tool wasn't found under .build/artifacts."
ED_SIG=$("$SIGN_UPDATE" "$DMG")   # sparkle:edSignature="…" length="…"

# Release notes = this version's section of CHANGELOG.md
awk -v v="## $VERSION " 'index($0, v) == 1 {on=1; next} on && /^## / {exit} on {print}' CHANGELOG.md > "$OUT/notes.md"
[ -s "$OUT/notes.md" ] || echo "Tuck Notch $VERSION" > "$OUT/notes.md"

URL="https://github.com/$REPO/releases/download/v$VERSION/TuckNotch-$VERSION.dmg"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tuck Notch</title>
    <item>
      <title>Tuck Notch $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $ED_SIG />
    </item>
  </channel>
</rss>
XML

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "✓ Dry run complete: $DMG and $OUT/appcast.xml (not published)"
  exit 0
fi

echo "→ Publishing GitHub release v${VERSION}…"
gh release create "v$VERSION" "$DMG" "$OUT/appcast.xml" \
  --repo "$REPO" --target main --title "Tuck Notch $VERSION" --notes-file "$OUT/notes.md"
echo "✓ Released: https://github.com/$REPO/releases/tag/v$VERSION"

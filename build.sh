#!/bin/bash
# Builds "Tuck Notch.app" from this Swift package.
#   ./build.sh           build into ./build
#   ./build.sh run       build, then launch
#   ./build.sh install   build, copy to /Applications, then launch
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tuck Notch.app"

echo "→ Compiling (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "→ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TuckNotch" "$APP/Contents/MacOS/TuckNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# Sparkle (auto-updates) ships inside the app.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

echo "→ Signing (ad-hoc; ./release.sh signs with Developer ID)…"
codesign --force --deep --sign - --timestamp=none "$APP"

echo "✓ Built $APP"

case "${1:-}" in
  run)
    pkill -x TuckNotch 2>/dev/null || true
    open "$APP"
    ;;
  install)
    pkill -x TuckNotch 2>/dev/null || true
    rm -rf "/Applications/Tuck Notch.app"
    cp -R "$APP" "/Applications/Tuck Notch.app"
    echo "✓ Installed to /Applications"
    open "/Applications/Tuck Notch.app"
    ;;
esac

#!/bin/bash
# Double-click: build, copy "Tuck Notch.app" to /Applications and launch it.
cd "$(dirname "$0")" || exit 1
./build.sh install 2>&1 | tail -5
echo
echo "Done. You can close this window."

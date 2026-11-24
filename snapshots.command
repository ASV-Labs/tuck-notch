#!/bin/bash
# Double-click: render every island state to ./snapshots/*.png (real views, sample data).
cd "$(dirname "$0")" || exit 1
swift build -c release 2>&1 | tail -3
"$(swift build -c release --show-bin-path)/TuckNotch" --render-snapshots "$PWD/snapshots" 2>&1 | tee snapshots.log
echo; echo "Done. You can close this window."

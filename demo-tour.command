#!/bin/bash
# Double-click: run the app in demo mode (fictional sample content, throwaway settings) and capture
# each state's window, with transparency, to ./demo-captures/*.png. Your own settings, clipboard,
# calendar and media are never shown. Needs Screen Recording permission for Terminal.
# tools/marketing/compose.py turns the captures into the README and social images.
cd "$(dirname "$0")" || exit 1
OUT="$PWD/demo-captures"
./build.sh >/dev/null 2>&1 || { echo "Build failed: run ./build.sh to see why."; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"
was_running=$(pgrep -x TuckNotch >/dev/null && echo yes)
pkill -x TuckNotch 2>/dev/null; sleep 1
"build/Tuck Notch.app/Contents/MacOS/TuckNotch" --demo-tour "$OUT" &
APP_PID=$!
last=""
for _ in $(seq 1 600); do
  if [ -f "$OUT/ready" ]; then
    line=$(cat "$OUT/ready")
    if [ "$line" != "$last" ]; then
      last="$line"
      name=${line% *}; win=${line##* }
      [ "$name" = "finished" ] && break
      if screencapture -x -o -l"$win" "$OUT/$name.png"; then echo "captured $name"; else echo "FAILED $name"; fi
      touch "$OUT/done-$name"
    fi
  fi
  sleep 0.2
done
wait $APP_PID 2>/dev/null
rm -f "$OUT"/ready "$OUT"/done-*
[ -n "$was_running" ] && open "/Applications/Tuck Notch.app"
echo; echo "Done: $OUT. You can close this window."

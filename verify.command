#!/bin/bash
# Double-click in Finder (or run from Terminal) to build, launch and measure Tuck Notch.
# Writes all evidence to verify-<timestamp>.log next to this file.
cd "$(dirname "$0")" || exit 1
LOG="verify-$(date +%Y%m%d-%H%M%S).log"

{
  echo "== Tuck Notch verification  $(date)"
  echo "-- System";    sw_vers; uname -m
  echo "-- Toolchain"; xcode-select -p; swift --version 2>&1 | head -2

  echo "== Build"
  if ./build.sh; then
    echo "BUILD: OK"
  else
    echo "BUILD: FAILED"
    exit 1
  fi

  echo "== Unit tests"
  if swift test 2>&1 | tail -25; then echo "TESTS: see output above"; fi

  echo "== Launch"
  pkill -x TuckNotch 2>/dev/null; sleep 1
  open "build/Tuck Notch.app"; sleep 5
  PID=$(pgrep -x TuckNotch | head -1)
  if [ -z "$PID" ]; then
    echo "LAUNCH: FAILED (process not running)"
    log show --last 2m --predicate 'process == "TuckNotch"' 2>/dev/null | tail -60
    ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i tucknotch | head -5
    exit 1
  fi
  echo "LAUNCH: OK (pid $PID)"

  echo "== Idle sample: 60 s at 1 Hz (don't touch the notch during this)"
  for i in $(seq 1 60); do ps -o %cpu=,rss= -p "$PID"; sleep 1; done |
    awk '{c+=$1; r=$2; n++; if ($1>m) m=$1}
         END {printf "IDLE: avg CPU %.2f%% of one core, peak %.1f%%, RSS %.1f MB (%d samples)\n", c/n, m, r/1024, n}'

  echo "== Energy (top, power column)"
  top -l 3 -s 5 -pid "$PID" -stats pid,command,cpu,mem,power | tail -2

  echo "== Crash reports"
  ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i tucknotch | head -5 || true

  echo "== Result: still running = $(pgrep -x TuckNotch >/dev/null && echo yes || echo no)"
} 2>&1 | tee "$LOG"

echo
echo "Saved $LOG — you can close this window."

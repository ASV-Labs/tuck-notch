#!/bin/bash
# Double-click: build (release) and run the unit tests. Output also saved to check.log.
cd "$(dirname "$0")" || exit 1
{
  echo "== Build"; swift build -c release 2>&1 | grep -E "error|warning: |Compiling|Build complete" | grep -v "^\[" | tail -60
  echo "== Tests"; swift test 2>&1 | grep -E "error|failed|passed at|Executed .* tests" | tail -30
} 2>&1 | tee check.log
echo; echo "Done. You can close this window."

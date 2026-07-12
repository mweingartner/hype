#!/bin/bash
#
# mpd test-gate wrapper. Runs the reliable Swift test subset for this machine
# (Xcode-beta toolchain; serial; the HypeTests target is headless-unsafe so it
# is compiled but not executed — see .githooks/pre-push and AGENTS.md), then
# emits a libtest-style "N passed" summary line that mpd's pass-count parser
# recognizes. Swift Testing prints "Test run with N tests ... passed", where the
# number is NOT adjacent to "passed", so mpd cannot count it directly.
#
# Exit code is the real `swift test` exit code (mpd requires exit 0 AND a
# non-zero pass count).
set -uo pipefail

LOG="$(mktemp)"
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --no-parallel --filter HypeCoreTests --filter HypeCLITests \
    --filter AppLaunchStateTests >"$LOG" 2>&1
ec=$?

cat "$LOG"
if [ "$ec" -eq 0 ]; then
  # Sum the per-run totals ("Test run with <N> tests ... passed") into a
  # libtest-format line so mpd records a real, non-zero pass count.
  total=$(grep -oE 'Test run with [0-9]+ tests' "$LOG" | grep -oE '[0-9]+' \
            | awk '{s+=$1} END{print s+0}')
  echo "test result: ok. ${total} passed; 0 failed"
fi
rm -f "$LOG"
exit "$ec"

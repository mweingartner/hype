#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources:/opt/homebrew/bin:${PATH:-}"

RUN_TESTS="focused"
RUN_LIVE_IOS=0
OPEN_APP=1
CAPTURE_MAC=1

usage() {
  cat <<'USAGE'
usage: scripts/visual_qa.sh [--skip-tests|--full-tests] [--live-ios] [--no-open] [--no-screenshot]

Verifies local automation, runs visual-debugging oriented regression checks,
builds/deploys Hype, opens the deployed app, and captures screenshot artifacts
under .hype/visual-qa/.

Default:
  - verify local visual automation tools
  - run focused target/runtime/control tests
  - build and deploy /Applications/Hype.app
  - launch Hype
  - capture a macOS screenshot

Options:
  --skip-tests     Build/deploy/open/screenshot only.
  --full-tests     Run the full Swift test suite instead of focused tests.
  --live-ios       Also run opt-in iPhone and iPad simulator runtime smoke tests.
  --no-open        Deploy without launching Hype.
  --no-screenshot  Do not capture a macOS screenshot.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --skip-tests)
      RUN_TESTS="skip"
      ;;
    --full-tests)
      RUN_TESTS="full"
      ;;
    --live-ios)
      RUN_LIVE_IOS=1
      ;;
    --no-open)
      OPEN_APP=0
      ;;
    --no-screenshot)
      CAPTURE_MAC=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT"

timestamp="$(/bin/date -u +"%Y%m%dT%H%M%SZ")"
artifact_dir="$ROOT/.hype/visual-qa/$timestamp"
/bin/mkdir -p "$artifact_dir"

log() {
  printf '[visual-qa] %s\n' "$*"
}

run_test_filter() {
  local filter="$1"
  log "swift test --filter $filter"
  PATH="$PATH" ./scripts/test.sh --filter "$filter"
}

capture_macos_screenshot() {
  local output="$artifact_dir/hype-macos.png"
  if ! /usr/bin/pgrep -x Hype >/dev/null 2>&1; then
    log "Hype is not running; skipping macOS screenshot."
    return
  fi

  /usr/bin/osascript -e 'tell application "Hype" to activate' >/dev/null 2>&1 || true
  /bin/sleep 1
  /usr/sbin/screencapture -x "$output"
  log "captured macOS screenshot: $output"
}

capture_booted_simulator_screenshots() {
  local booted
  booted="$(
    /usr/bin/xcrun simctl list devices booted \
      | /usr/bin/sed -n 's/^    .* (\([A-F0-9-]\{36\}\)) (Booted).*$/\1/p'
  )"
  if [ -z "$booted" ]; then
    log "No booted simulators found for screenshot capture."
    return
  fi

  while IFS= read -r udid; do
    [ -z "$udid" ] && continue
    local output="$artifact_dir/simulator-$udid.png"
    /usr/bin/xcrun simctl io "$udid" screenshot "$output" >/dev/null
    log "captured simulator screenshot: $output"
  done <<< "$booted"
}

shutdown_booted_ios_simulators() {
  local booted
  booted="$(
    /usr/bin/xcrun simctl list devices booted \
      | /usr/bin/sed -n 's/^    .* (\([A-F0-9-]\{36\}\)) (Booted).*$/\1/p'
  )"
  while IFS= read -r udid; do
    [ -z "$udid" ] && continue
    /usr/bin/xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  done <<< "$booted"
}

log "verifying automation tools"
/usr/bin/xcrun --version >/dev/null
/usr/sbin/screencapture -h >/dev/null 2>&1 || true
if /usr/bin/command -v cliclick >/dev/null 2>&1; then
  cliclick -V
else
  log "cliclick not found; pointer-level UI checks will be unavailable."
fi

if [ -d "$ROOT/Tools/hype-mcp-server/node_modules" ]; then
  log "checking Hype MCP server"
  (cd "$ROOT/Tools/hype-mcp-server" && /usr/bin/env npm run check)
else
  log "Hype MCP server dependencies are not installed; run npm install in Tools/hype-mcp-server."
fi

case "$RUN_TESTS" in
  focused)
    run_test_filter TargetPlatformTests
    run_test_filter SimulatorRuntimeLauncherTests
    run_test_filter FormControlsTests
    run_test_filter CalendarPartTests
    ;;
  full)
    log "running full Swift test suite"
    ./scripts/test.sh
    ;;
  skip)
    log "skipping tests"
    ;;
esac

if [ "$RUN_LIVE_IOS" -eq 1 ]; then
  log "running live iOS runtime smoke tests"
  HYPE_LIVE_IOS_CONTROL_SIMULATOR_SMOKE=1 HYPE_KEEP_RUNTIME_TEST_PACKAGES=1 \
    ./scripts/test.sh --filter 'SimulatorRuntimeLauncherTests/liveIOSRuntimeControlSmoke'
  HYPE_LIVE_IOS_ALL_CONTROLS_SMOKE=1 HYPE_KEEP_RUNTIME_TEST_PACKAGES=1 \
    ./scripts/test.sh --filter 'SimulatorRuntimeLauncherTests/liveIPadAllRuntimeControlsSmoke'
  capture_booted_simulator_screenshots
  shutdown_booted_ios_simulators
fi

log "building and deploying Hype"
PATH="$PATH" ./script/build_and_run.sh --deploy

if [ "$OPEN_APP" -eq 1 ]; then
  log "launching /Applications/Hype.app"
  /usr/bin/open -n /Applications/Hype.app
  /bin/sleep 2
fi

if [ "$CAPTURE_MAC" -eq 1 ]; then
  capture_macos_screenshot
fi

log "artifacts: $artifact_dir"

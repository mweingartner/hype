#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources"

cd "$ROOT"

echo "Available Apple simulators:"
/usr/bin/xcrun simctl list devices available

echo
echo "Running quick live simulator smoke test..."
HYPE_LIVE_SIMULATOR_SMOKE=1 /usr/bin/xcrun swift test --filter 'SimulatorRuntimeLauncherTests/liveSimulatorSmoke'

if [[ "${HYPE_FULL_IOS_SIMULATOR_MATRIX:-0}" == "1" ]]; then
  echo
  echo "Running full current-shipping iPhone/iPad simulator matrix..."
  HYPE_LIVE_IOS_SIMULATOR_MATRIX=1 /usr/bin/xcrun swift test --filter 'SimulatorRuntimeLauncherTests/liveInstalledIOSSimulatorMatrix'
else
  echo
  echo "Skipping full simulator matrix. Set HYPE_FULL_IOS_SIMULATOR_MATRIX=1 to launch every installed current-shipping iPhone/iPad simulator."
fi

#!/bin/bash
# Set the tuned model as Hype's default Ollama model.
#
# Hype stores its default model tag in macOS UserDefaults under
# `@AppStorage("ollamaModel")`. We write to it via `defaults write`
# on the Hype app bundle identifier so the next time the app opens
# it uses the tuned model without any code change.
#
# The bundle identifier is pulled from the installed app's
# Info.plist — more robust than hardcoding.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG="$ROOT/config.yaml"

MODEL_TAG="$(python3 -c "
import yaml
print(yaml.safe_load(open('$CONFIG'))['output_model'])
")"

APP_PATH="/Applications/Hype.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
    echo "error: Hype.app not installed at $APP_PATH. Run ./install.sh from the repo root first." >&2
    exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")"

echo "Setting ollamaModel default for $BUNDLE_ID to '$MODEL_TAG'…"
defaults write "$BUNDLE_ID" ollamaModel "$MODEL_TAG"
echo "Done. Quit and relaunch Hype to pick up the change."
echo
echo "To revert: defaults delete $BUNDLE_ID ollamaModel"

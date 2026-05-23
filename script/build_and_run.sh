#!/usr/bin/env bash
set -euo pipefail

log_error() {
  printf 'error: %s\n' "$*" >&2
}

MODE="${1:-run}"
APP_NAME="Hype"
BUNDLE_ID="com.hype.app"
MIN_SYSTEM_VERSION="15.0"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Library/Developer/CommandLineTools/usr/bin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

SWIFT="${SWIFT_BIN:-${SWIFT:-/usr/bin/swift}}"
SWIFTPM_RETRY_ATTEMPTS="${SWIFTPM_RETRY_ATTEMPTS:-3}"
SWIFTPM_RETRY_DELAY_SECONDS="${SWIFTPM_RETRY_DELAY_SECONDS:-2}"

normalize_positive_int() {
  local value="$1"
  local fallback="$2"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s' "$fallback"
    return
  fi

  printf '%s' "$value"
}

SWIFTPM_RETRY_ATTEMPTS="$(normalize_positive_int "$SWIFTPM_RETRY_ATTEMPTS" 3)"
SWIFTPM_RETRY_DELAY_SECONDS="$(normalize_positive_int "$SWIFTPM_RETRY_DELAY_SECONDS" 2)"

run_with_retry() {
  local label="$1"
  shift

  local attempts=1
  local delay_seconds="$SWIFTPM_RETRY_DELAY_SECONDS"
  local cmd=("$@")

  while :; do
    local tmp_output
    tmp_output="$(mktemp)"

    echo "Running ($label): ${cmd[*]}"
    set +e
    ("${cmd[@]}" >"${tmp_output}" 2>&1)
    local status=$?
    set -e

    if [ "$status" -eq 0 ]; then
      cat "${tmp_output}"
      rm -f "${tmp_output}"
      return 0
    fi

    if ! grep -q "Another instance of SwiftPM" "${tmp_output}"; then
      log_error "${label} failed (exit code: ${status})."
      cat "${tmp_output}" >&2
      rm -f "${tmp_output}"
      return "$status"
    fi

    if [ "$attempts" -ge "$SWIFTPM_RETRY_ATTEMPTS" ]; then
      log_error "${label} failed after ${attempts} attempts due to SwiftPM lock contention."
      cat "${tmp_output}" >&2
      rm -f "${tmp_output}"
      return "$status"
    fi

    echo "SwiftPM lock detected; retrying in ${delay_seconds}s..." >&2
    rm -f "${tmp_output}"
    sleep "$delay_seconds"
    attempts=$((attempts + 1))
    delay_seconds=$((delay_seconds * 2))
  done
}

if [ ! -x "$SWIFT" ]; then
  log_error "Swift toolchain not found at $SWIFT"
  log_error "Set SWIFT_BIN (or SWIFT) to a valid swift binary, or install the Swift toolchain."
  exit 2
fi

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true

run_with_retry "swift build" "$SWIFT" build
BUILD_BINARY="$($SWIFT build --show-bin-path)/$APP_NAME"

if [ ! -x "$BUILD_BINARY" ]; then
  log_error "Build artifact not found: $BUILD_BINARY"
  exit 2
fi

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_MACOS" "$APP_RESOURCES"
/bin/cp "$BUILD_BINARY" "$APP_BINARY"
/bin/chmod +x "$APP_BINARY"

if [ -d "$ROOT_DIR/Sources/Hype/Resources" ]; then
  /usr/bin/ditto "$ROOT_DIR/Sources/Hype/Resources" "$APP_RESOURCES"
fi

/bin/cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>hype</string>
      </array>
      <key>CFBundleTypeIconFile</key>
      <string>HypeDocIcon</string>
      <key>CFBundleTypeName</key>
      <string>Hype Stack</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.hype.stack</string>
      </array>
    </dict>
  </array>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0</string>
  <key>CFBundleVersion</key>
  <string>2.0.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Hype uses the microphone for voice input in the AI Chat panel (transcribed locally and sent to your AI model as text) and for recording audio into Audio Recorder parts in your stacks.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Hype uses speech recognition to transcribe voice commands in the AI Chat panel into text prompts for your AI model. Recognition is performed on-device when supported.</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.json</string>
      </array>
      <key>UTTypeDescription</key>
      <string>Hype Stack</string>
      <key>UTTypeIconFiles</key>
      <array>
        <string>HypeDocIcon</string>
      </array>
      <key>UTTypeIdentifier</key>
      <string>com.hype.stack</string>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>hype</string>
        </array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    /bin/sleep 2
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null
    ;;
  --deploy|deploy)
    if [ ! -d "/Applications" ]; then
      log_error "/Applications directory is not available."
      exit 2
    fi

    if [ ! -w "/Applications" ]; then
      log_error "No permission to write /Applications. Run with a writable user session or use sudo."
      exit 2
    fi

    if [ ! -d "$APP_BUNDLE" ]; then
      log_error "Expected app bundle not found at $APP_BUNDLE"
      exit 2
    fi

    /bin/rm -rf "/Applications/$APP_NAME.app"
    /usr/bin/ditto "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--deploy]" >&2
    exit 2
    ;;
esac

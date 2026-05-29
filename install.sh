#!/usr/bin/env bash
# Build and install Hype.app to /Applications
set -euo pipefail

log_error() {
  printf 'error: %s\n' "$*" >&2
}

APP="/Applications/Hype.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFT="${SWIFT_BIN:-${SWIFT:-/usr/bin/swift}}"
SWIFTPM_RETRY_ATTEMPTS="${SWIFTPM_RETRY_ATTEMPTS:-3}"
SWIFTPM_RETRY_DELAY_SECONDS="${SWIFTPM_RETRY_DELAY_SECONDS:-2}"
CONFIGURATION="release"
APP_NAME="Hype"
BUNDLE_ID="com.hype.app"
MIN_SYSTEM_VERSION="15.0"
APP_ICON="$ROOT_DIR/Sources/Hype/Resources/AppIcon.icns"
DOC_ICON="$ROOT_DIR/Sources/Hype/Resources/HypeDocIcon.icns"

cd "$ROOT_DIR"

write_default_info_plist() {
  local target="$1"
  cat >"${target}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
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
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0</string>
  <key>CFBundleVersion</key>
  <string>2.0.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_SYSTEM_VERSION}</string>
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
}

run_with_retry() {
  local label="$1"
  shift

  local attempts=1
  local delay_seconds="$SWIFTPM_RETRY_DELAY_SECONDS"
  local cmd=("$@")

  while :; do
    local tmp_output
    tmp_output="$(mktemp)"

    echo "Running (${label}): ${cmd[*]}"
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

resolve_info_plist() {
  if [ -n "${HYPE_INFO_PLIST:-}" ] && [ -f "$HYPE_INFO_PLIST" ]; then
    echo "$HYPE_INFO_PLIST"
    return
  fi

  if [ -f "dist/Hype.app/Contents/Info.plist" ]; then
    echo "dist/Hype.app/Contents/Info.plist"
    return
  fi

  if [ -f "build/Hype.app/Contents/Info.plist" ]; then
    echo "build/Hype.app/Contents/Info.plist"
    return
  fi

  return 1
}

if [ ! -x "$SWIFT" ]; then
  log_error "Swift toolchain not found at $SWIFT"
  log_error "Set SWIFT_BIN (or SWIFT) to a valid swift binary, or install the Swift toolchain."
  exit 2
fi

if [ ! -d "/Applications" ]; then
  log_error "/Applications directory is not available."
  exit 2
fi

if [ ! -w "/Applications" ]; then
  log_error "No permission to write /Applications. Run with a writable user session or use sudo."
  exit 2
fi

if [ ! -f "$APP_ICON" ]; then
  log_error "Missing app icon: $APP_ICON"
  exit 2
fi

if [ ! -f "$DOC_ICON" ]; then
  log_error "Missing document icon: $DOC_ICON"
  exit 2
fi

echo "Building release..."
run_with_retry "swift build -c ${CONFIGURATION}" "$SWIFT" build -c "$CONFIGURATION"

BUILD_BINARY="$($SWIFT build --show-bin-path -c "$CONFIGURATION")/Hype"

if [ ! -x "$BUILD_BINARY" ]; then
  log_error "Release build artifact not found: $BUILD_BINARY"
  exit 2
fi

/bin/rm -rf "$APP"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Installing binary..."
/bin/cp "$BUILD_BINARY" "$APP/Contents/MacOS/Hype"
/bin/chmod +x "$APP/Contents/MacOS/Hype"

echo "Installing icons..."
/bin/cp "$APP_ICON" "$APP/Contents/Resources/AppIcon.icns"
/bin/cp "$DOC_ICON" "$APP/Contents/Resources/HypeDocIcon.icns"

echo "Installing Info.plist..."
if INFO_PLIST_SOURCE="$(resolve_info_plist)"; then
  /bin/cp "$INFO_PLIST_SOURCE" "$APP/Contents/Info.plist"
else
  if ! write_default_info_plist "$APP/Contents/Info.plist"; then
    log_error "Unable to write fallback Info.plist"
    exit 2
  fi
  log_error "Generated fallback Info.plist; build bundle metadata was not found in dist/ or build/."
fi

echo "Re-signing..."
if ! /usr/bin/codesign --force --sign - --deep "$APP"; then
  log_error "codesign failed. Install may still work for development but binaries may be blocked by Gatekeeper."
  exit 2
fi

echo "Done! Hype.app installed to /Applications"

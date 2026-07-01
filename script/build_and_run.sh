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
LOCAL_CODESIGN_DIR="$ROOT_DIR/.hype-codesign"
LOCAL_CODESIGN_NAME="${HYPE_CODESIGN_IDENTITY:-Hype Local Development Code Signing}"
LOCAL_CODESIGN_KEYCHAIN="${HYPE_CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
LOCAL_CODESIGN_CERT="$LOCAL_CODESIGN_DIR/HypeLocalDevelopmentCodeSigning.crt"
LOCAL_CODESIGN_KEY="$LOCAL_CODESIGN_DIR/HypeLocalDevelopmentCodeSigning.key"
LOCAL_CODESIGN_P12="$LOCAL_CODESIGN_DIR/HypeLocalDevelopmentCodeSigning.p12"
LOCAL_CODESIGN_CONFIG="$LOCAL_CODESIGN_DIR/HypeLocalDevelopmentCodeSigning.cnf"
LOCAL_CODESIGN_VERSION_FILE="$LOCAL_CODESIGN_DIR/version"
LOCAL_CODESIGN_ARTIFACT_VERSION="2"
LOCAL_CODESIGN_PASSWORD="${HYPE_CODESIGN_PASSWORD:-hype-local-development}"

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

codesign_identity_exists() {
  /usr/bin/security find-identity -v -p codesigning "$LOCAL_CODESIGN_KEYCHAIN" 2>/dev/null \
    | /usr/bin/grep -Fq "\"$LOCAL_CODESIGN_NAME\""
}

create_local_codesign_artifact_if_needed() {
  /bin/mkdir -p "$LOCAL_CODESIGN_DIR"
  /bin/chmod 700 "$LOCAL_CODESIGN_DIR"

  if [ -f "$LOCAL_CODESIGN_P12" ] \
    && [ -f "$LOCAL_CODESIGN_CERT" ] \
    && [ -f "$LOCAL_CODESIGN_VERSION_FILE" ] \
    && [ "$(/bin/cat "$LOCAL_CODESIGN_VERSION_FILE")" = "$LOCAL_CODESIGN_ARTIFACT_VERSION" ]; then
    return 0
  fi

  /bin/rm -f "$LOCAL_CODESIGN_KEY" "$LOCAL_CODESIGN_CERT" "$LOCAL_CODESIGN_P12" "$LOCAL_CODESIGN_CONFIG"

  /bin/cat >"$LOCAL_CODESIGN_CONFIG" <<CONFIG
[ req ]
prompt = no
distinguished_name = req_distinguished_name
x509_extensions = v3_req

[ req_distinguished_name ]
commonName = $LOCAL_CODESIGN_NAME

[ v3_req ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
CONFIG

  /usr/bin/openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -keyout "$LOCAL_CODESIGN_KEY" \
    -x509 \
    -days 3650 \
    -out "$LOCAL_CODESIGN_CERT" \
    -config "$LOCAL_CODESIGN_CONFIG" >/dev/null 2>&1

  /usr/bin/openssl pkcs12 \
    -export \
    -out "$LOCAL_CODESIGN_P12" \
    -inkey "$LOCAL_CODESIGN_KEY" \
    -in "$LOCAL_CODESIGN_CERT" \
    -passout "pass:$LOCAL_CODESIGN_PASSWORD" >/dev/null 2>&1

  /bin/chmod 600 "$LOCAL_CODESIGN_KEY" "$LOCAL_CODESIGN_CERT" "$LOCAL_CODESIGN_P12" "$LOCAL_CODESIGN_CONFIG"
  /bin/echo "$LOCAL_CODESIGN_ARTIFACT_VERSION" >"$LOCAL_CODESIGN_VERSION_FILE"
  /bin/chmod 600 "$LOCAL_CODESIGN_VERSION_FILE"
}

ensure_local_codesign_identity() {
  if codesign_identity_exists; then
    return 0
  fi

  create_local_codesign_artifact_if_needed

  /usr/bin/security import "$LOCAL_CODESIGN_P12" \
    -k "$LOCAL_CODESIGN_KEYCHAIN" \
    -P "$LOCAL_CODESIGN_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

  /usr/bin/security add-trusted-cert \
    -d \
    -r trustRoot \
    -p codeSign \
    -k "$LOCAL_CODESIGN_KEYCHAIN" \
    "$LOCAL_CODESIGN_CERT" >/dev/null 2>&1 || true

  if ! codesign_identity_exists; then
    log_error "Failed to install local code-signing identity '$LOCAL_CODESIGN_NAME'."
    log_error "Try opening Keychain Access and trusting $LOCAL_CODESIGN_CERT for code signing, then rerun this script."
    exit 2
  fi
}

sign_app_bundle() {
  if [ "${HYPE_SKIP_CODESIGN:-0}" = "1" ]; then
    echo "Skipping code signing because HYPE_SKIP_CODESIGN=1"
    return 0
  fi

  ensure_local_codesign_identity
  echo "Signing $APP_BUNDLE with '$LOCAL_CODESIGN_NAME'"
  /usr/bin/codesign --force --deep --sign "$LOCAL_CODESIGN_NAME" "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
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

# SwiftPM resource bundles (Bundle.module targets fatalError without them).
BUILD_BIN_DIR="$(/usr/bin/dirname "$BUILD_BINARY")"
for bundle in "$BUILD_BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] || continue
  /usr/bin/ditto "$bundle" "$APP_RESOURCES/$(/usr/bin/basename "$bundle")"
done

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
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Hype uses your location only when a running stack asks for it (the "user location" command or a map's Show User Location option), to center maps and provide your coordinates to the stack.</string>
  <key>NSAppleMusicUsageDescription</key>
  <string>Hype uses Apple Music access only when you enable it, authorize MusicKit, and use a stack that requests catalog or library music references for playback.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Hype uses speech recognition to transcribe voice commands in the AI Chat panel into text prompts for your AI model. Recognition is performed on-device when supported.</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>com.apple.package</string>
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
  <!--
    Names the classic HyperCard stack UTI for import panels and system metadata.
    Extensionless classic stacks are still accepted by the app importer through
    its explicit .data fallback and stack-format validation path.
  -->
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeDescription</key>
      <string>HyperCard Stack</string>
      <key>UTTypeIdentifier</key>
      <string>com.apple.hypercard.stack</string>
    </dict>
  </array>
</dict>
</plist>
PLIST

sign_app_bundle

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

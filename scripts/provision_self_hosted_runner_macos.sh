#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_DIR="${HYPE_RUNNER_DIR:-$HOME/actions-runner/hype}"
REPO_FULL_NAME="${HYPE_RUNNER_REPO_FULL_NAME:-}"
REPO_URL="${HYPE_RUNNER_REPO_URL:-}"
RUNNER_VERSION="${HYPE_RUNNER_VERSION:-2.335.1}"
RUNNER_ARCH="$(uname -m)"
RUNNER_LABELS="${HYPE_RUNNER_LABELS:-self-hosted,macOS,ARM64,hype,xcode-beta}"
DEVELOPER_DIR_DEFAULT="/Applications/Xcode-beta.app/Contents/Developer"
CI_KEYCHAIN_PATH="${HYPE_CI_KEYCHAIN_PATH:-$RUNNER_DIR/hype-ci.keychain-db}"
CI_KEYCHAIN_PASSWORD="${HYPE_CI_KEYCHAIN_PASSWORD:-hype-ci-local}"

case "$RUNNER_ARCH" in
  arm64)
    RUNNER_PACKAGE_ARCH="arm64"
    ;;
  x86_64)
    RUNNER_PACKAGE_ARCH="x64"
    RUNNER_LABELS="${HYPE_RUNNER_LABELS:-self-hosted,macOS,X64,hype,xcode-beta}"
    ;;
  *)
    echo "error: unsupported macOS runner architecture: $RUNNER_ARCH" >&2
    exit 2
    ;;
esac

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$DEVELOPER_DIR_DEFAULT}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 2
  fi
}

require_path() {
  if [ ! -e "$1" ]; then
    echo "error: required path not found: $1" >&2
    exit 2
  fi
}

print_section() {
  printf '\n==> %s\n' "$1"
}

print_section "Checking macOS build dependencies"
require_command curl
require_command git
require_command gh
require_command security
require_command shasum
require_command xcrun
require_path "$DEVELOPER_DIR"

xcrun xcodebuild -version
xcrun swift --version

print_section "Preparing runner directory"
mkdir -p "$RUNNER_DIR"

print_section "Preparing CI keychain"
if [ ! -f "$CI_KEYCHAIN_PATH" ]; then
  security create-keychain -p "$CI_KEYCHAIN_PASSWORD" "$CI_KEYCHAIN_PATH"
fi
security unlock-keychain -p "$CI_KEYCHAIN_PASSWORD" "$CI_KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$CI_KEYCHAIN_PATH"
EXISTING_KEYCHAINS="$(security list-keychains -d user 2>/dev/null | tr -d '"' | xargs || true)"
if [ -n "$EXISTING_KEYCHAINS" ]; then
  security list-keychains -d user -s "$CI_KEYCHAIN_PATH" $EXISTING_KEYCHAINS
else
  security list-keychains -d user -s "$CI_KEYCHAIN_PATH"
fi
security default-keychain -d user -s "$CI_KEYCHAIN_PATH"

print_section "Checking GitHub CLI access"
gh auth status
if [ -z "$REPO_FULL_NAME" ]; then
  REPO_FULL_NAME="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
if [ -z "$REPO_URL" ]; then
  REPO_URL="$(gh repo view --json url --jq .url)"
fi

print_section "Preparing GitHub Actions runner"
cd "$RUNNER_DIR"

if [ ! -x ./config.sh ]; then
  ARCHIVE="actions-runner-osx-${RUNNER_PACKAGE_ARCH}-${RUNNER_VERSION}.tar.gz"
  DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ARCHIVE}"

  echo "Downloading GitHub Actions runner $RUNNER_VERSION for $RUNNER_PACKAGE_ARCH"
  curl -fsSLO "$DOWNLOAD_URL"
  EXPECTED_SHA256="$(
    gh api "repos/actions/runner/releases/tags/v${RUNNER_VERSION}" \
      --jq ".assets[] | select(.name == \"$ARCHIVE\") | .digest" \
      | sed 's/^sha256://'
  )"
  printf '%s  %s\n' "$EXPECTED_SHA256" "$ARCHIVE" | shasum -a 256 -c -
  tar xzf "$ARCHIVE"
fi

if [ ! -f .runner ]; then
  print_section "Registering runner"
  if [ -n "${HYPE_RUNNER_TOKEN:-}" ]; then
    echo "Using HYPE_RUNNER_TOKEN for $REPO_URL"
    TOKEN="$HYPE_RUNNER_TOKEN"
  else
    echo "Requesting a short-lived registration token for $REPO_URL"
    TOKEN="$(gh api "repos/${REPO_FULL_NAME}/actions/runners/registration-token" --jq .token)"
  fi
  ./config.sh \
    --url "$REPO_URL" \
    --token "$TOKEN" \
    --name "$(scutil --get LocalHostName 2>/dev/null || hostname)-hype" \
    --labels "$RUNNER_LABELS" \
    --work _work \
    --unattended \
    --replace
fi

print_section "Installing launchd service"
./svc.sh install
./svc.sh start
./svc.sh status

print_section "Validating Hype test gate"
cd "$ROOT_DIR"
scripts/test.sh --no-parallel --filter HypeCoreTests --filter HypeCLITests

print_section "Done"
echo "Runner labels: $RUNNER_LABELS"
echo "Runner directory: $RUNNER_DIR"

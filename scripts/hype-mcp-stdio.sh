#!/bin/zsh
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources:${PATH:-}"

REPO_DIR="/Users/mweingar/dev/hype-v2"
APP_BUNDLE="/Applications/Hype.app"
BRIDGE="$REPO_DIR/.build/arm64-apple-macosx/debug/hype-mcp"
PORT="${HYPE_MCP_PORT:-47891}"
HEALTH_URL="http://127.0.0.1:${PORT}/health"
BUILD_LOG="/tmp/hype-mcp-build.log"

if [[ ! -x "$BRIDGE" ]]; then
  (cd "$REPO_DIR" && /usr/bin/swift build --product hype-mcp >"$BUILD_LOG" 2>&1)
fi

if ! /usr/bin/curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
  /usr/bin/open -n "$APP_BUNDLE" >/dev/null 2>&1 || true
  for _ in {1..60}; do
    if /usr/bin/curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
      break
    fi
    /bin/sleep 0.25
  done
fi

exec "$BRIDGE"

#!/bin/zsh
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="/Applications/Hype.app"
SERVER="$REPO_DIR/Tools/hype-mcp-server/bin/hype-mcp.js"
export HYPE_DEBUG_SOCKET_DIR="$REPO_DIR/.hype/debug"

/bin/mkdir -p "$HYPE_DEBUG_SOCKET_DIR"
/bin/chmod 700 "$REPO_DIR/.hype" "$HYPE_DEBUG_SOCKET_DIR" 2>/dev/null || true

if [[ ! -f "$SERVER" ]]; then
  (cd "$REPO_DIR/Tools/hype-mcp-server" && /usr/bin/npm run build >/tmp/hype-mcp-build.log 2>&1)
fi

/usr/bin/open -n "$APP_BUNDLE" >/dev/null 2>&1 || true

exec /usr/bin/env node "$SERVER"

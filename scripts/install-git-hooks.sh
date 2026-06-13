#!/bin/bash
#
# Point git at the repo's tracked hooks directory so .githooks/pre-push (the
# local build/test gate) runs. Run this once per clone.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true

echo "Installed: core.hooksPath = .githooks"
echo "The pre-push gate now runs 'swift test --no-parallel' before pushes to main."
echo "Bypass when needed with: git push --no-verify"

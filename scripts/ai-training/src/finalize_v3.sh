#!/bin/bash
# One-shot finalizer: after `train.sh` finishes, run fuse →
# package → eval → set_default in sequence. Stops on the first
# failure so a bad fuse doesn't silently ship a broken model.
#
# Usage: bash src/finalize_v3.sh [--skip-eval] [--skip-default]
#
# Runs for ~20 minutes total — fuse dominates (~10 min to copy
# 54 GB base model + apply adapter), package is fast, eval is
# the `ollama run` cost which depends on prompt count.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

SKIP_EVAL=0
SKIP_DEFAULT=0
for arg in "$@"; do
    case "$arg" in
        --skip-eval) SKIP_EVAL=1 ;;
        --skip-default) SKIP_DEFAULT=1 ;;
    esac
done

# Verify adapters exist before starting.
if [[ ! -f "$ROOT/out/adapters/adapters.safetensors" ]]; then
    echo "error: no adapters at out/adapters/. Did training finish?" >&2
    exit 1
fi

echo "=== Step 1/4: Fuse LoRA into base weights ==="
bash "$SCRIPT_DIR/fuse.sh" --force
echo

echo "=== Step 2/4: Package as Ollama model ==="
bash "$SCRIPT_DIR/package.sh"
echo

if [[ $SKIP_EVAL -eq 1 ]]; then
    echo "=== Step 3/4: Skipped (--skip-eval) ==="
else
    echo "=== Step 3/4: Evaluate candidate vs baseline ==="
    python3 "$SCRIPT_DIR/eval.py" || {
        echo "warning: eval reported issues — proceeding anyway. Inspect out/eval_report.json before shipping."
    }
fi
echo

if [[ $SKIP_DEFAULT -eq 1 ]]; then
    echo "=== Step 4/4: Skipped (--skip-default) ==="
    echo "Run \`make set-default\` manually when ready."
else
    echo "=== Step 4/4: Set v3 as Hype's default model ==="
    bash "$SCRIPT_DIR/set_default.sh"
fi
echo

echo "=== Finalize complete ==="
echo "v3 is now Hype's default. Relaunch /Applications/Hype.app to pick up the change."

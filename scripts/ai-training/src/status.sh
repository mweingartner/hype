#!/bin/bash
# Status snapshot for a running pipeline. Prints the current stage,
# PID, recent log lines, and if training is active the current
# iteration / loss if the trainer has printed one.
#
# Safe to run any time — read-only, no side effects.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

PID_FILE="$ROOT/out/logs/pipeline.pid"
LOG_FILE="$ROOT/out/logs/pipeline.log"

echo "=== HypeTalk training pipeline status ==="
date

if [[ -f "$PID_FILE" ]]; then
    PID="$(cat "$PID_FILE")"
    if ps -p "$PID" >/dev/null 2>&1; then
        echo "Pipeline PID: $PID (running)"
        ps -p "$PID" -o etime= | xargs -I {} echo "  Elapsed: {}"
    else
        echo "Pipeline PID: $PID (not running — pipeline finished or crashed)"
    fi
else
    echo "No pipeline.pid — nothing started yet."
fi
echo

if [[ -f "$LOG_FILE" ]]; then
    echo "=== Last 25 log lines ==="
    tail -25 "$LOG_FILE"
    echo
    # Current stage detection based on log keywords.
    if grep -q "=== Pipeline complete ===" "$LOG_FILE"; then
        echo "Stage: DONE"
    elif grep -q "=== Eval:" "$LOG_FILE"; then
        echo "Stage: EVAL"
    elif grep -q "Creating Ollama model" "$LOG_FILE"; then
        echo "Stage: PACKAGE"
    elif grep -q "Fusing LoRA adapter" "$LOG_FILE"; then
        echo "Stage: FUSE"
    elif grep -q "Iter " "$LOG_FILE"; then
        # Pick the latest iter/loss the trainer reported.
        last=$(grep -E "^Iter " "$LOG_FILE" | tail -1 || true)
        echo "Stage: TRAIN ($last)"
    elif grep -q "Loading pretrained model" "$LOG_FILE"; then
        echo "Stage: TRAIN (model download/load)"
    else
        echo "Stage: CORPUS / SETUP"
    fi
else
    echo "No log file yet."
fi
echo

if [[ -d "$ROOT/out/adapters" ]]; then
    echo "Adapters dir: $(du -sh "$ROOT/out/adapters" | cut -f1)"
fi
if [[ -d "$ROOT/out/fused" ]]; then
    echo "Fused model:  $(du -sh "$ROOT/out/fused" | cut -f1)"
fi

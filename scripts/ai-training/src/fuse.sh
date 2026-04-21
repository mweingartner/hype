#!/bin/bash
# Merge the LoRA adapter weights into a fresh copy of the base
# model, producing a standalone safetensors directory that Ollama
# can `FROM` directly. This avoids the GGUF-conversion path — for
# gemma-3 family models, Ollama 0.1.40+ accepts a safetensors dir
# as-is.
#
# Output: ../out/fused/ — a complete HuggingFace-format model
# (config.json, tokenizer files, *.safetensors shards).
#
# Disk cost: one full copy of the base model (~54 GB for gemma-3-
# 27b at fp16). If space is tight, delete ../out/fused/ between
# iterations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

CONFIG="$ROOT/config.yaml"
ADAPTER_DIR="$ROOT/out/adapters"
FUSED_DIR="$ROOT/out/fused"

if [[ ! -f "$ADAPTER_DIR/adapters.safetensors" ]]; then
    echo "error: no adapters at $ADAPTER_DIR. Run ./src/train.sh first." >&2
    exit 1
fi

BASE_MODEL="$(python3 -c "
import yaml
print(yaml.safe_load(open('$CONFIG'))['base_model'])
")"

if [[ -d "$FUSED_DIR" && "${1:-}" != "--force" ]]; then
    read -rp "Fused model already exists at $FUSED_DIR. Overwrite? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 0
    rm -rf "$FUSED_DIR"
fi

echo "=== Fusing LoRA adapter into $BASE_MODEL ==="

# `mlx_lm.fuse` loads the base, applies the adapter in-place, and
# writes a new standalone checkpoint. The `--save-path` IS the
# output directory, not a parent — it will be created.
python3 -m mlx_lm fuse \
    --model "$BASE_MODEL" \
    --adapter-path "$ADAPTER_DIR" \
    --save-path "$FUSED_DIR"

echo
echo "=== Fuse complete ==="
echo "Fused model at: $FUSED_DIR"
echo "Next step: ./src/package.sh to register with Ollama."

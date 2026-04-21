#!/bin/bash
# MLX-LM LoRA fine-tuning runner.
#
# Reads hyperparameters from ../config.yaml, writes LoRA adapters
# to ../out/adapters/. Idempotent: if an adapter already exists and
# --force is not passed, asks before overwriting.
#
# Hardware: this ran on an M5 Max 128 GB with gemma-3-27b at rank
# 16 in about ~3-4 hours for 2000 iters. Smaller models or lower
# rank finish in under an hour. The 100 GB `iogpu.wired_limit_mb`
# sysctl value is what makes the 27B weights fit at 4-bit; lower
# that and MLX swaps to disk and training stalls.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

CONFIG="$ROOT/config.yaml"
ADAPTER_DIR="$ROOT/out/adapters"
CORPUS_DIR="$ROOT/out"

# Require the corpus to exist before training.
if [[ ! -f "$CORPUS_DIR/train.jsonl" ]]; then
    echo "error: $CORPUS_DIR/train.jsonl not found. Run 'make corpus' first." >&2
    exit 1
fi

# Pull config values via a tiny Python parser to avoid yq/jq deps.
# Keeps the stack pure-Python, which is what the rest of the
# pipeline relies on anyway.
read_config() {
    python3 -c "
import yaml, sys
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
keys = '$1'.split('.')
val = cfg
for k in keys: val = val[k]
print(val)
"
}

BASE_MODEL="$(read_config base_model)"
RANK="$(read_config lora.rank)"
NUM_LAYERS="$(read_config lora.num_layers)"
LR="$(read_config lora.learning_rate)"
BATCH="$(read_config lora.batch_size)"
ITERS="$(read_config lora.iters)"
SAVE_EVERY="$(read_config lora.save_every)"
SEED="$(read_config lora.seed)"

# Ensure MLX-LM is available. `uv` is fast and doesn't require a
# manual venv-activation dance; fall back to pip if missing.
if ! python3 -c "import mlx_lm" 2>/dev/null; then
    echo "MLX-LM not installed; installing via uv…"
    if command -v uv >/dev/null; then
        uv pip install --system "mlx-lm>=0.20" pyyaml
    else
        python3 -m pip install --upgrade "mlx-lm>=0.20" pyyaml
    fi
fi

mkdir -p "$ADAPTER_DIR"

# Overwrite guard: ask unless --force or an unattended run.
if [[ -f "$ADAPTER_DIR/adapters.safetensors" && "${1:-}" != "--force" ]]; then
    read -rp "Adapters already exist at $ADAPTER_DIR. Overwrite? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 0
fi

echo "=== LoRA training ==="
echo "Base model:   $BASE_MODEL"
echo "Rank:         $RANK"
echo "Num layers:   $NUM_LAYERS"
echo "Learning rate: $LR"
echo "Batch size:   $BATCH"
echo "Iterations:   $ITERS"
echo "Adapter dir:  $ADAPTER_DIR"
echo

# `mlx_lm.lora` is the main training entry point. Arguments line
# up 1:1 with config.yaml — if you add knobs to config.yaml, add
# them to `read_config` above and wire them here.
#
# `--data` points at a DIRECTORY that contains {train,valid,test}.jsonl,
# not at a single file. That's the MLX-LM convention.
python3 -m mlx_lm lora \
    --model "$BASE_MODEL" \
    --train \
    --data "$CORPUS_DIR" \
    --num-layers "$NUM_LAYERS" \
    --batch-size "$BATCH" \
    --iters "$ITERS" \
    --learning-rate "$LR" \
    --save-every "$SAVE_EVERY" \
    --adapter-path "$ADAPTER_DIR" \
    --seed "$SEED"

echo
echo "=== Training complete ==="
echo "Adapters written to: $ADAPTER_DIR"
echo "Next step: ./src/fuse.sh to merge LoRA into base weights."

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
PYTHON_BIN="${PYTHON:-python3}"

# Require the corpus to exist before training.
if [[ ! -f "$CORPUS_DIR/train.jsonl" ]]; then
    echo "error: $CORPUS_DIR/train.jsonl not found. Run 'make corpus' first." >&2
    exit 1
fi

# Pull config values via a tiny Python parser to avoid yq/jq deps.
# Keeps the stack pure-Python, which is what the rest of the
# pipeline relies on anyway.
read_config() {
    "$PYTHON_BIN" -c "import yaml
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
keys = '$1'.split('.')
val = cfg
for k in keys: val = val[k]
print(val)
"
}

read_config_default() {
    "$PYTHON_BIN" -c "import yaml
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)

keys = '$1'.split('.')
default = '$2'
val = cfg
for key in keys:
    if not isinstance(val, dict) or key not in val:
        print(default)
        raise SystemExit
    val = val[key]

if isinstance(val, bool):
    print('true' if val else 'false')
else:
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
GRAD_ACCUM="$(read_config lora.grad_accumulation_steps)"
GRAD_CHECKPOINT="$(read_config_default lora.grad_checkpoint false)"
MAX_SEQ_LENGTH="$(read_config_default lora.max_seq_length 4096)"

# LoRA-specific hyperparameters (rank, scale, dropout, target layer
# keys) can ONLY be applied through mlx_lm's --config YAML — the
# CLI has no --rank flag. mlx_lora_config.yaml sits next to this
# script's config.yaml and is the authoritative source for those.
MLX_LORA_CONFIG="$ROOT/mlx_lora_config.yaml"
if [[ ! -f "$MLX_LORA_CONFIG" ]]; then
    echo "error: $MLX_LORA_CONFIG not found. Create it with lora_parameters: {rank, scale, dropout, keys}." >&2
    exit 1
fi

# Ensure MLX-LM is available. `uv` is fast and doesn't require a
# manual venv-activation dance; fall back to pip if missing.
if ! "$PYTHON_BIN" -c "import mlx_lm" 2>/dev/null; then
    echo "MLX-LM not installed; installing via uv…"
    if command -v uv >/dev/null; then
        uv pip install --system "mlx-lm>=0.20" pyyaml
    else
        "$PYTHON_BIN" -m pip install --upgrade "mlx-lm>=0.20" pyyaml
    fi
fi

# A resident Ollama runner can hold tens of GB of Metal memory even
# while idle. That competes directly with MLX training and causes
# misleading OOMs on otherwise-capable machines. Fail fast unless the
# caller explicitly overrides the guard.
if [[ "${HYPE_ALLOW_LOADED_OLLAMA_MODELS:-0}" != "1" ]] && command -v ollama >/dev/null; then
    ACTIVE_OLLAMA_MODELS="$(ollama ps 2>/dev/null | /usr/bin/awk 'NR > 1 && NF { print $1 }')"
    if [[ -n "$ACTIVE_OLLAMA_MODELS" ]]; then
        echo "error: Ollama currently has loaded model runners:" >&2
        printf '  %s\n' $ACTIVE_OLLAMA_MODELS >&2
        echo "Unload them before training (for example: \`ollama stop <model>\`) or rerun with HYPE_ALLOW_LOADED_OLLAMA_MODELS=1." >&2
        exit 1
    fi
fi

mkdir -p "$ADAPTER_DIR"

# Overwrite guard: ask unless --force or an unattended run.
if [[ -f "$ADAPTER_DIR/adapters.safetensors" && "${1:-}" != "--force" ]]; then
    read -rp "Adapters already exist at $ADAPTER_DIR. Overwrite? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 0
fi

echo "=== LoRA training ==="
echo "Base model:        $BASE_MODEL"
echo "Rank (from -c):    $RANK"
echo "Num layers:        $NUM_LAYERS"
echo "Learning rate:     $LR"
echo "Batch size:        $BATCH"
echo "Grad accum steps:  $GRAD_ACCUM"
echo "Grad checkpoint:   $GRAD_CHECKPOINT"
echo "Max seq length:    $MAX_SEQ_LENGTH"
echo "Iterations:        $ITERS"
echo "Adapter dir:       $ADAPTER_DIR"
echo "LoRA -c config:    $MLX_LORA_CONFIG"
echo

# `mlx_lm.lora` is the main training entry point. CLI flags
# handle coarse hyperparameters; rank + scale + dropout + target
# layer keys come from the `-c` config file. Argument order
# matters — the `-c` config is applied as a base and CLI flags
# override it.
#
# `--data` points at a DIRECTORY that contains {train,valid,test}.jsonl,
# not at a single file. That's the MLX-LM convention.
args=(
    -m mlx_lm lora
    -c "$MLX_LORA_CONFIG"
    --model "$BASE_MODEL"
    --train
    --data "$CORPUS_DIR"
    --num-layers "$NUM_LAYERS"
    --batch-size "$BATCH"
    --iters "$ITERS"
    --learning-rate "$LR"
    --grad-accumulation-steps "$GRAD_ACCUM"
    --save-every "$SAVE_EVERY"
    --max-seq-length "$MAX_SEQ_LENGTH"
    --adapter-path "$ADAPTER_DIR"
    --seed "$SEED"
)

if [[ "$(printf '%s' "$GRAD_CHECKPOINT" | /usr/bin/tr '[:upper:]' '[:lower:]')" == "true" ]]; then
    args+=(--grad-checkpoint)
fi

"$PYTHON_BIN" "${args[@]}"

echo
echo "=== Training complete ==="
echo "Adapters written to: $ADAPTER_DIR"
echo "Next step: ./src/fuse.sh to merge LoRA into base weights."

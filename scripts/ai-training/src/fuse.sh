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
PYTHON_BIN="${PYTHON:-python3}"

if [[ ! -f "$ADAPTER_DIR/adapters.safetensors" ]]; then
    echo "error: no adapters at $ADAPTER_DIR. Run ./src/train.sh first." >&2
    exit 1
fi

BASE_MODEL="$("$PYTHON_BIN" -c "import yaml
print(yaml.safe_load(open('$CONFIG'))['base_model'])
")"
MODEL_FAMILY="$("$PYTHON_BIN" -c "import yaml
cfg = yaml.safe_load(open('$CONFIG'))
print(str(cfg.get('model_family') or cfg.get('tool_format') or '').lower())
")"

if [[ -d "$FUSED_DIR" && "${1:-}" != "--force" ]]; then
    read -rp "Fused model already exists at $FUSED_DIR. Overwrite? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 0
    rm -rf "$FUSED_DIR"
fi

echo "=== Fusing LoRA adapter into $BASE_MODEL ==="

args=(
    -m mlx_lm fuse
    --model "$BASE_MODEL" \
    --adapter-path "$ADAPTER_DIR" \
    --save-path "$FUSED_DIR"
)

"$PYTHON_BIN" "${args[@]}"

if [[ "$MODEL_FAMILY" == qwen* ]]; then
    GGUF_MODEL="$FUSED_DIR/ggml-model-f16.gguf"
    LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$ROOT/out/tools/llama.cpp}"
    if [[ -z "${GGUF_PYTHON:-}" ]]; then
        if [[ -x /Users/mweingar/zit-env/bin/python ]]; then
            GGUF_PYTHON=/Users/mweingar/zit-env/bin/python
        else
            GGUF_PYTHON="$(command -v python3 || true)"
        fi
    fi
    CONVERTER="$LLAMA_CPP_DIR/convert_hf_to_gguf.py"

    if [[ ! -f "$CONVERTER" ]]; then
        echo "error: Qwen GGUF export requires llama.cpp at $LLAMA_CPP_DIR." >&2
        echo "hint: git clone https://github.com/ggml-org/llama.cpp.git '$LLAMA_CPP_DIR'" >&2
        exit 1
    fi

    if [[ ! -x "$GGUF_PYTHON" ]]; then
        echo "error: Qwen GGUF export requires an executable Python with torch, transformers, safetensors, and sentencepiece: $GGUF_PYTHON" >&2
        echo "hint: set GGUF_PYTHON=/path/to/python before running this script." >&2
        exit 1
    fi

    echo
    echo "=== Exporting Qwen GGUF via llama.cpp converter ==="
    rm -f "$GGUF_MODEL"
    PYTHONPATH="$LLAMA_CPP_DIR/gguf-py${PYTHONPATH:+:$PYTHONPATH}" \
        "$GGUF_PYTHON" "$CONVERTER" "$FUSED_DIR" \
        --outfile "$GGUF_MODEL" \
        --outtype f16
fi

echo
echo "=== Fuse complete ==="
echo "Fused model at: $FUSED_DIR"
echo "Next step: ./src/package.sh to register with Ollama."

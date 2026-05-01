#!/bin/bash
# Package the currently-fused tuned model into a single tarball that
# can be copied to another Mac and re-registered with Ollama via
# `import_model.sh`. Ships the GGUF + a portable Modelfile (with
# the absolute FROM path rewritten to a relative one) + a tiny
# install script that runs `ollama create` on the destination.
#
# Usage:
#   ./src/export_model.sh                # tarball named after output_model
#   ./src/export_model.sh ~/Desktop      # write tarball to a chosen dir
#
# Output: <output_model>.tar.gz at the chosen path (default: out/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

CONFIG="$ROOT/config.yaml"
FUSED_DIR="$ROOT/out/fused"
MODELFILE="$ROOT/out/Modelfile"
PYTHON_BIN="${PYTHON:-python3}"

if [[ ! -f "$MODELFILE" ]]; then
    echo "error: no Modelfile at $MODELFILE — run ./src/package.sh first." >&2
    exit 1
fi

# Read output model tag and detect family (qwen3 ships a single
# GGUF; gemma3 ships the safetensors directory).
OUTPUT_MODEL="$("$PYTHON_BIN" -c "import yaml; print(yaml.safe_load(open('$CONFIG'))['output_model'])")"
TOOL_FORMAT="$("$PYTHON_BIN" -c "import yaml; cfg=yaml.safe_load(open('$CONFIG')); print(cfg.get('tool_format','functiongemma'))")"
MODEL_FAMILY="$("$PYTHON_BIN" -c "import yaml; cfg=yaml.safe_load(open('$CONFIG')); print(cfg.get('model_family', cfg.get('tool_format','functiongemma')))")"

# Sanitize tag for filenames: hypetalk-qwen3:8b-v6 → hypetalk-qwen3-8b-v6
SAFE_TAG="$(printf '%s' "$OUTPUT_MODEL" | tr ':/' '--')"

OUT_DIR="${1:-$ROOT/out}"
mkdir -p "$OUT_DIR"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

PKG_DIR="$STAGING/$SAFE_TAG"
mkdir -p "$PKG_DIR"

echo "=== Packaging $OUTPUT_MODEL ==="

# Decide what to ship based on family.
if [[ "$MODEL_FAMILY" == "qwen3" || "$TOOL_FORMAT" == "qwen3" ]]; then
    GGUF="$FUSED_DIR/ggml-model-f16.gguf"
    if [[ ! -f "$GGUF" ]]; then
        echo "error: no GGUF at $GGUF — re-run ./src/fuse.sh." >&2
        exit 1
    fi
    echo "Copying $(du -h "$GGUF" | awk '{print $1}') GGUF…"
    cp "$GGUF" "$PKG_DIR/ggml-model-f16.gguf"
    REL_FROM="./ggml-model-f16.gguf"
else
    # Gemma path: ship the whole fused safetensors dir.
    echo "Copying fused safetensors directory ($(du -sh "$FUSED_DIR" | awk '{print $1}'))…"
    cp -R "$FUSED_DIR" "$PKG_DIR/fused"
    REL_FROM="./fused"
fi

# Rewrite the Modelfile so its FROM line is portable.
echo "Rewriting Modelfile FROM to relative path…"
"$PYTHON_BIN" - <<PY
import re, pathlib
src = pathlib.Path("$MODELFILE").read_text()
# Replace the first FROM line only — the block is simple enough.
src = re.sub(r'^FROM .*$', 'FROM $REL_FROM', src, count=1, flags=re.M)
pathlib.Path("$PKG_DIR/Modelfile").write_text(src)
PY

# Drop a minimal installer that re-creates the model on the destination.
cat >"$PKG_DIR/install.sh" <<'INSTALL'
#!/bin/bash
# Register this exported tuned model with the local Ollama install.
# Run from inside the unpacked package directory.
set -euo pipefail

if ! command -v ollama >/dev/null 2>&1; then
    echo "error: 'ollama' not found in PATH. Install Ollama first: https://ollama.com/download" >&2
    exit 1
fi

cd "$(dirname "$0")"

TAG="__OUTPUT_MODEL__"
echo "=== Registering $TAG with Ollama ==="
echo "(this copies the model file into ~/.ollama/models — may take a minute)"
ollama create "$TAG" -f Modelfile

echo
echo "Done. Try it:"
echo "  ollama run $TAG"
echo
echo "To make it Hype's default model:"
echo "  defaults write com.hype.app ollamaModel \"$TAG\""
echo "  (then relaunch Hype)"
INSTALL

# Patch the tag into the installer.
sed -i.bak "s|__OUTPUT_MODEL__|$OUTPUT_MODEL|g" "$PKG_DIR/install.sh"
rm -f "$PKG_DIR/install.sh.bak"
chmod +x "$PKG_DIR/install.sh"

# Ship a README.
cat >"$PKG_DIR/README.txt" <<README
$OUTPUT_MODEL — exported tuned model

Contents:
  Modelfile                  Ollama Modelfile (with relative FROM)
  ggml-model-f16.gguf OR     The fused model weights
    fused/                   (depending on base model family)
  install.sh                 Registers the model with the destination's Ollama
  README.txt                 This file

To install on a Mac that has Ollama already:
  1. tar -xzf $SAFE_TAG.tar.gz
  2. cd $SAFE_TAG
  3. ./install.sh

The installer runs 'ollama create $OUTPUT_MODEL -f Modelfile'.
That copies the weights into Ollama's blob store — you can then
delete this directory.

To use it from Hype on the destination:
  defaults write com.hype.app ollamaModel "$OUTPUT_MODEL"
  open /Applications/Hype.app
README

# Tar it up.
TARBALL="$OUT_DIR/$SAFE_TAG.tar.gz"
echo "Creating tarball $TARBALL…"
tar -czf "$TARBALL" -C "$STAGING" "$SAFE_TAG"

SIZE="$(du -h "$TARBALL" | awk '{print $1}')"
echo
echo "=== Export complete ==="
echo "  Tarball:  $TARBALL ($SIZE)"
echo "  Contains: $OUTPUT_MODEL + portable Modelfile + install.sh"
echo
echo "Next: copy the tarball to the destination Mac (scp, AirDrop, USB),"
echo "then run install.sh from inside the unpacked directory."

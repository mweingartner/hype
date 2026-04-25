#!/bin/bash
# Wrap the fused safetensors directory in an Ollama Modelfile and
# `ollama create` a tagged model. The SYSTEM prompt embedded into
# the Modelfile is extracted directly from `HypeTalkGuide.swift` so
# the published model's built-in system prompt matches what the
# Hype app sends at runtime — no drift.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

CONFIG="$ROOT/config.yaml"
FUSED_DIR="$ROOT/out/fused"
MODELFILE="$ROOT/out/Modelfile"
PYTHON_BIN="${PYTHON:-python3}"

if [[ ! -d "$FUSED_DIR" ]]; then
    echo "error: no fused model at $FUSED_DIR. Run ./src/fuse.sh first." >&2
    exit 1
fi

read_cfg() {
    "$PYTHON_BIN" -c "import yaml
cfg = yaml.safe_load(open('$CONFIG'))
keys = '$1'.split('.')
v = cfg
for k in keys: v = v[k]
print(v)
"
}

read_cfg_default() {
    "$PYTHON_BIN" -c "import yaml
cfg = yaml.safe_load(open('$CONFIG'))
keys = '$1'.split('.')
default = '$2'
v = cfg
for k in keys:
    if not isinstance(v, dict) or k not in v:
        print(default)
        raise SystemExit
    v = v[k]
if isinstance(v, bool):
    print('true' if v else 'false')
else:
    print(v)
"
}

OUTPUT_MODEL="$(read_cfg output_model)"
TEMP="$(read_cfg ollama.temperature)"
TOP_P="$(read_cfg ollama.top_p)"
NUM_CTX="$(read_cfg ollama.num_ctx)"
TOOL_FORMAT="$(read_cfg_default tool_format functiongemma)"
MODEL_FAMILY="$(read_cfg_default model_family "$TOOL_FORMAT")"

# Extract the HypeTalk guide for the embedded SYSTEM prompt. The
# guide is the canonical HypeTalk reference shipped inside the app
# (see HypeTalkGuide.swift); embedding it into the Modelfile means
# every ollama run hypetalk-gemma session starts with the same
# grounding the Hype app provides at chat time.
SYSTEM_PROMPT="$("$PYTHON_BIN" "$SCRIPT_DIR/_extract_guide.py")"

# Write the Modelfile.
#
# IMPORTANT: MLX-LM's fuse drops the chat_template from the
# tokenizer config, so Ollama auto-detects no template and
# defaults TEMPLATE to "{{ .Prompt }}" — no turn markers, no
# stop token. Gemma-3 then generates indefinitely because it has
# no <end_of_turn> signal, and each ollama run hangs until the
# runner is killed.
#
# Fix: embed the canonical Gemma-3 chat template + the
# <end_of_turn> stop sequence directly in our Modelfile. This
# mirrors what ollama show gemma3:27b --modelfile produces for
# the baseline model, so the tuned model behaves identically on
# the wire.
if [[ "$MODEL_FAMILY" == "qwen3" || "$TOOL_FORMAT" == "qwen3" ]]; then
    GGUF_MODEL="$FUSED_DIR/ggml-model-f16.gguf"
    if [[ ! -f "$GGUF_MODEL" ]]; then
        echo "error: no Qwen GGUF model at $GGUF_MODEL. Run ./src/fuse.sh first." >&2
        exit 1
    fi
    {
        cat <<EOF
# Auto-generated Modelfile — do not edit by hand.
# Regenerate with scripts/ai-training/src/package.sh.
FROM $GGUF_MODEL

EOF
        cat <<'EOF'
TEMPLATE """
{{- $lastUserIdx := -1 -}}
{{- range $idx, $msg := .Messages -}}
{{- if eq $msg.Role "user" }}{{ $lastUserIdx = $idx }}{{ end -}}
{{- end }}
{{- if or .System .Tools }}<|im_start|>system
{{ if .System }}
{{ .System }}
{{- end }}
{{- if .Tools }}

# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{{- range .Tools }}
{"type": "function", "function": {{ .Function }}}
{{- end }}
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": <function-name>, "arguments": <args-json-object>}
</tool_call>
{{- end -}}
<|im_end|>
{{ end }}
{{- range $i, $_ := .Messages }}
{{- $last := eq (len (slice $.Messages $i)) 1 -}}
{{- if eq .Role "user" }}<|im_start|>user
{{ .Content }}
{{- if and $.IsThinkSet (eq $i $lastUserIdx) }}
   {{- if $.Think -}}
      {{- " "}}/think
   {{- else -}}
      {{- " "}}/no_think
   {{- end -}}
{{- end }}<|im_end|>
{{ else if eq .Role "assistant" }}<|im_start|>assistant
{{ if (and $.IsThinkSet (and .Thinking (or $last (gt $i $lastUserIdx)))) -}}
<think>{{ .Thinking }}</think>
{{ end -}}
{{ if .Content }}{{ .Content }}
{{- else if .ToolCalls }}<tool_call>
{{ range .ToolCalls }}{"name": "{{ .Function.Name }}", "arguments": {{ .Function.Arguments }}}
{{ end }}</tool_call>
{{- end }}{{ if not $last }}<|im_end|>
{{ end }}
{{- else if eq .Role "tool" }}<|im_start|>user
<tool_response>
{{ .Content }}
</tool_response><|im_end|>
{{ end }}
{{- if and (ne .Role "assistant") $last }}<|im_start|>assistant
{{ if and $.IsThinkSet (not $.Think) -}}
<think>

</think>

{{ end -}}
{{ end }}
{{- end }}"""
EOF
        cat <<EOF
PARAMETER stop <|im_start|>
PARAMETER stop <|im_end|>
PARAMETER temperature $TEMP
PARAMETER top_p $TOP_P
PARAMETER num_ctx $NUM_CTX

# NO SYSTEM block is set here, by design.
#
# Hype injects the active stack/card/background/current-state prompt
# at request time. Qwen's template injects the provided tools into
# that same system turn, preserving native Ollama tool parsing.
EOF
    } >"$MODELFILE"
else
cat >"$MODELFILE" <<EOF
# Auto-generated Modelfile — do not edit by hand.
# Regenerate with scripts/ai-training/src/package.sh.
FROM $FUSED_DIR

# RENDERER + PARSER activate Ollama's built-in Gemma-family chat
# template renderer and tool-call parser. Without these directives
# the model is marked only 'completion, vision' — Hype's AI Chat
# panel passes tools, Ollama rejects the request with
# "<model> does not support tools", and the user sees no answer.
#
# We use functiongemma (not gemma4) because it speaks the
# SAME chat template as Google's upstream Gemma-3 IT model —
# <start_of_turn> turn markers and standard Gemma-3 vocabulary.
# The gemma4 renderer, by contrast, emits <|turn> tokens that
# our base mlx-community/gemma-3-27b-it-bf16 doesn't know; the
# model garbles output when wrapped in that template. Matching
# renderer ↔ base-model vocabulary is essential.
#
# functiongemma's on-wire tool-call format is
# <start_function_call>call:NAME{k:<escape>v<escape>,...}<end_function_call>.
# Our LoRA training (see src/gen_corpus.py make_tool_call_row)
# emits this exact format in the tool-call training rows so Ollama's
# parser lifts the model's output directly into structured
# tool_calls.
RENDERER functiongemma
PARSER functiongemma

PARAMETER stop <end_of_turn>
PARAMETER temperature $TEMP
PARAMETER top_p $TOP_P
PARAMETER num_ctx $NUM_CTX

# NO SYSTEM block is set here, by design.
#
# Ollama's gemma4 renderer owns the system slot — when the /api/chat
# caller passes tools: [...], the renderer formats every tool
# as a callable function declaration and injects that into the
# system prompt at chat time. A user-authored SYSTEM block (e.g.
# the full HypeTalk guide) ends up merged with the rendered tool
# schema, which confuses the model — it stops emitting structured
# tool_call tokens the gemma4 parser knows how to extract and
# falls back to Python-style "tool_code set_part_property(...)"
# fenced blocks that the parser doesn't lift into Ollama's
# structured tool_calls response.
#
# Hype's AIChatPanel already injects the (minus-guide) authoring
# system prompt per chat request, and its conditional-skip
# recognises the hypetalk- tag prefix and does NOT inject the
# full guide (the guide lives in the model's weights). So we
# don't need the guide baked into the Modelfile — leaving SYSTEM
# empty keeps Ollama's tool renderer happy and the model
# responses come back as structured tool_calls, not tool_code
# code fences.
#
# For standalone users running ollama run hypetalk-gemma4:27b-v1
# outside of Hype, supply the guide via their own system message.
EOF
fi

echo "=== Creating Ollama model: $OUTPUT_MODEL ==="
ollama create "$OUTPUT_MODEL" -f "$MODELFILE"

echo
echo "=== Package complete ==="
echo "Model registered as: $OUTPUT_MODEL"
echo "Next step: ./src/eval.py or ./src/set_default.sh"

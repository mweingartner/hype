#!/usr/bin/env python3
'''Generate an MLX-LM training corpus from the seed YAML files.

The pipeline intentionally keeps hand-authored seed examples in
human-friendly YAML (corpus/seed/*.yaml) so they are easy to
review, diff, and extend when the AI regresses on a new pattern.
This script transforms them into the JSONL chat format MLX-LM's
LoRA trainer expects — one message array per line, roles system /
user / assistant. Tool-call examples render as an assistant
message with a tool_calls list (matching OpenAI's tool schema,
which MLX-LM's Gemma-3 template understands natively).

Output: out/corpus.train.jsonl and out/corpus.valid.jsonl with a
90/10 split. Re-run this stage any time you add or edit seeds.
'''

from __future__ import annotations

import argparse
import json
import random
import re
from pathlib import Path
from typing import Iterator

import yaml


ROOT = Path(__file__).resolve().parent.parent   # scripts/ai-training
SEED_DIR = ROOT / "corpus" / "seed"
OUT_DIR = ROOT / "out"
REPO_ROOT = ROOT.parent.parent                   # hype-v2


def load_system_prompt() -> str:
    '''Return the MINIMAL system prompt used during training.

    The first training run made the mistake of embedding the full
    ~20 KB HypeTalk guide into every row's system prompt. Because
    every row shared the exact same 6000-token preamble, the model
    quickly memorized re-emitting the guide — train loss crashed
    to 0.000 by iter ~50 while the actually-useful signal (the
    tiny user-intent → assistant-script mapping at the tail of
    each row) got almost no gradient. By iter 200+ the model had
    mode-collapsed into emitting repeated unicode bytes for any
    prompt that didn't exactly match a training example.

    Fix: keep the training system prompt short and generic. The
    full guide still lands in front of the model at INFERENCE time
    via the Modelfile's SYSTEM block (see package.sh) — we don't
    need to teach the model the guide, we need to teach it the
    user-intent → HypeTalk mapping. The guide's always-present
    reference role doesn't need training data to support it.
    '''
    return (
        "You are a HypeTalk scripting assistant for the Hype "
        "interactive authoring app. Produce valid HypeTalk "
        "scripts or the correct Hype tool call in response to "
        "user requests."
    )


def load_tool_catalog_hint() -> str:
    """A compact description of the tool surface the model should
    reach for when emitting tool_calls, appended to the guide for
    tool-call training rows. This is intentionally short — the
    training labels already encode the right tool choice via the
    assistant message.
    """
    return """
## Available tools for scene authoring

- `set_scene_script(sprite_area_name, script, scene_name?)` — set a SpriteKit scene's HypeTalk script. This is the script visible in the "<area> / <scene>" Script Editor. Prefer this over set_part_property for scene scripts.
- `apply_scene_diff(sprite_area_name, diff_json)` — modify a scene incrementally. Supports sceneUpdates (script, gravity, backgroundColor, isPaused, size, name, scaleMode), addNodes, removeNodeIds, updateNodes.
- `add_sprite_to_scene(sprite_area_name, sprite_name, asset_name?, x?, y?, width?, height?)` — add a single sprite.
- `set_part_property(part_name, property, value)` — for non-scene parts. Properties include text, left, top, width, height, script, visible, enabled, style. NOTE: for a sprite-area part, `property=script` is auto-redirected to the active scene's script.
"""


def iter_script_examples() -> Iterator[tuple[str, str]]:
    """Yield (intent, script) pairs from every seed YAML that
    defines `examples[n].script`."""
    for path in sorted(SEED_DIR.glob("*.yaml")):
        data = yaml.safe_load(path.read_text())
        for ex in data.get("examples", []):
            if "script" in ex:
                intent = ex["intent"].strip()
                script = ex["script"].rstrip()
                yield intent, script


def iter_tool_call_examples() -> Iterator[tuple[str, dict]]:
    """Yield (intent, tool_call_dict) pairs for tool-use training
    rows. `tool_call_dict` has keys {name, arguments}."""
    for path in sorted(SEED_DIR.glob("*.yaml")):
        data = yaml.safe_load(path.read_text())
        for ex in data.get("examples", []):
            if "tool_call" in ex:
                intent = ex["intent"].strip()
                yield intent, ex["tool_call"]


def make_script_row(intent: str, script: str, system: str) -> dict:
    """Build a chat-format row for a script-generation example."""
    return {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": intent},
            {"role": "assistant", "content": script},
        ]
    }


def _format_functiongemma_value(v) -> str:
    """Serialize a single argument value in Ollama's functiongemma format.

    Strings → `<escape>value<escape>`
    Bools   → bare `true` / `false`
    Numbers → bare decimal / integer
    Lists   → `[v1,v2,...]` with each value recursively formatted
    Dicts   → `{key:v1,key:v2,...}` with each value recursively formatted

    Matches Ollama's renderer in `model/renderers/functiongemma.go`
    so training output round-trips through the parser without
    edge-case weirdness.
    """
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v.is_integer():
            return str(int(v))
        return str(v)
    if isinstance(v, list):
        return "[" + ",".join(_format_functiongemma_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ",".join(
            f"{k}:{_format_functiongemma_value(val)}" for k, val in v.items()
        ) + "}"
    # Fall-through: treat as string (covers actual strings AND anything
    # else stringable). Always wrap in <escape> delimiters.
    return f"<escape>{v}<escape>"


def make_tool_call_row(intent: str, tool_call: dict, system: str) -> dict:
    """Build a chat-format row for a tool-call example.

    Emits the tool call in **Ollama's `functiongemma` format** —
    the native on-wire format Ollama's `FunctionGemmaParser`
    extracts into structured `tool_calls` on the `/api/chat`
    response. Format:

        <start_function_call>call:NAME{key:<escape>value<escape>,
        key2:42}<end_function_call>

    String values are wrapped in `<escape>`/`<escape>` delimiters;
    numbers and booleans are emitted bare; keys are bare
    identifiers; args are comma-separated. No newlines inside the
    tags — keeps tokenization predictable.

    Why this format: our base `mlx-community/gemma-3-27b-it-bf16`
    (and all upstream Gemma-3 IT variants) natively emit tool
    calls as ```tool_code``` markdown fences containing JSON.
    That's not a format any stock Ollama parser recognises.
    Training our LoRA to emit `<start_function_call>` tags
    instead is the minimum-complexity way to get tool-calls to
    round-trip as structured JSON via Ollama without running a
    client-side fallback parser — once the model is packaged
    with `RENDERER functiongemma` + `PARSER functiongemma`
    (see package.sh), Ollama lifts these tags directly into the
    `tool_calls` array.
    """
    name = tool_call["name"]
    args = tool_call.get("arguments", {}) or {}
    arg_pairs = [f"{k}:{_format_functiongemma_value(v)}" for k, v in args.items()]
    body = f"<start_function_call>call:{name}{{{','.join(arg_pairs)}}}<end_function_call>"

    return {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": intent},
            {"role": "assistant", "content": body},
        ]
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--split",
        type=float,
        default=0.9,
        help="Train/valid split ratio (default: 0.9)",
    )
    parser.add_argument(
        "--seed", type=int, default=42, help="RNG seed for split"
    )
    parser.add_argument(
        "--include-tools",
        action="store_true",
        default=True,
        help="Include tool-call rows (default: true)",
    )
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # System prompts: plain guide for script rows, guide + tool
    # catalog hint for tool rows. Keeps the token count of non-tool
    # rows lower, which speeds training.
    guide = load_system_prompt()
    script_system = guide
    tool_system = guide + "\n\n" + load_tool_catalog_hint().strip()

    rows: list[dict] = []

    script_count = 0
    for intent, script in iter_script_examples():
        rows.append(make_script_row(intent, script, script_system))
        script_count += 1

    tool_count = 0
    if args.include_tools:
        for intent, tool_call in iter_tool_call_examples():
            rows.append(make_tool_call_row(intent, tool_call, tool_system))
            tool_count += 1

    if not rows:
        raise SystemExit(
            "No training rows generated. Check corpus/seed/ for YAML files."
        )

    rng = random.Random(args.seed)
    rng.shuffle(rows)

    split_idx = int(len(rows) * args.split)
    train_rows = rows[:split_idx]
    valid_rows = rows[split_idx:]

    # Guarantee at least one validation row so MLX-LM's eval loop
    # doesn't divide by zero on tiny corpora.
    if not valid_rows and train_rows:
        valid_rows = [train_rows.pop()]

    # MLX-LM's load_dataset helper looks for exactly these three
    # filenames inside the --data directory. Don't prefix or
    # rename — the trainer fails with "Training set not found or
    # empty" if the files are named anything else.
    train_path = OUT_DIR / "train.jsonl"
    valid_path = OUT_DIR / "valid.jsonl"
    test_path = OUT_DIR / "test.jsonl"

    for path, subset in [
        (train_path, train_rows),
        (valid_path, valid_rows),
        (test_path, valid_rows),
    ]:
        path.write_text("\n".join(json.dumps(r) for r in subset) + "\n")

    print(
        f"Wrote {len(train_rows)} train + {len(valid_rows)} valid rows "
        f"({script_count} script, {tool_count} tool-call) to {OUT_DIR}"
    )


if __name__ == "__main__":
    main()

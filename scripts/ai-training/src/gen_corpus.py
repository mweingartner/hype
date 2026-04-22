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


# ─────────────────────────────────────────────────────────────────────
# Tool declaration injection (matches Ollama's functiongemma renderer)
# ─────────────────────────────────────────────────────────────────────

# Hand-authored minimal declarations for the tools that appear in the
# training corpus. Format mirrors Ollama's
# `renderers/functiongemma.go` `renderToolDeclaration` output:
#
#     <start_function_declaration>declaration:NAME{
#       description:<escape>...<escape>,
#       parameters:{
#         properties:{KEY:{description:<escape>...<escape>,type:<escape>STRING<escape>},...},
#         required:[<escape>KEY<escape>,...],
#         type:<escape>OBJECT<escape>
#       }
#     }<end_function_declaration>
#
# Injecting these into the system prompt of tool-call training rows
# matches what Ollama's functiongemma renderer emits at inference
# time. Without this, the model never saw declaration→call pairing
# during training and only weakly learned the surrounding tags
# (`<start_function_call>call:` / `<end_function_call>`), producing
# tool-call bodies with the middle correct but the anchors missing.
#
# Values are a compact schema — same structure the renderer produces,
# just authored by hand for readability. Only the tools that appear in
# the corpus need entries here; unknown tools skip declaration
# injection silently.
TOOL_DECLARATIONS = {
    "set_scene_script": {
        "description": "Set the HypeTalk script on a sprite-area scene (the script shown in the <area>/<scene> Script Editor). Use this for scene-level scripts.",
        "properties": {
            "sprite_area_name": ("Name of the sprite area part.", "STRING"),
            "script": ("Full HypeTalk script for the scene, wrapped in on <event>/end <event> handler blocks.", "STRING"),
            "scene_name": ("Optional scene name within the sprite area; defaults to the active scene.", "STRING"),
        },
        "required": ["sprite_area_name", "script"],
    },
    "apply_scene_diff": {
        "description": "Apply a JSON diff to modify a sprite scene incrementally. Supports sceneUpdates (backgroundColor, gravity, isPaused, showsPhysics, script), addNodes, removeNodeIds, updateNodes.",
        "properties": {
            "sprite_area_name": ("Name of the sprite area part.", "STRING"),
            "diff_json": ("SceneDiff as a JSON-encoded string.", "STRING"),
        },
        "required": ["sprite_area_name", "diff_json"],
    },
    "add_sprite_to_scene": {
        "description": "Add a single sprite node to a sprite area scene.",
        "properties": {
            "sprite_area_name": ("Name of the sprite area part.", "STRING"),
            "sprite_name": ("Name for the new sprite.", "STRING"),
            "asset_name": ("Repository asset name for texture (optional).", "STRING"),
            "x": ("X position.", "STRING"),
            "y": ("Y position.", "STRING"),
            "width": ("Width in points.", "STRING"),
            "height": ("Height in points.", "STRING"),
        },
        "required": ["sprite_area_name", "sprite_name"],
    },
    "set_part_property": {
        "description": "Set a property on a named Part. Common properties: text, left, top, width, height, visible, enabled, script, style, fillColor.",
        "properties": {
            "part_name": ("Name of the part to modify.", "STRING"),
            "property": ("Property name.", "STRING"),
            "value": ("New value (as a string).", "STRING"),
        },
        "required": ["part_name", "property", "value"],
    },
    "create_button": {
        "description": "Create a button on the current card.",
        "properties": {
            "name": ("Button name/label.", "STRING"),
            "left": ("X position.", "STRING"),
            "top": ("Y position.", "STRING"),
            "width": ("Width in points.", "STRING"),
            "height": ("Height in points.", "STRING"),
            "script": ("HypeTalk command to run on mouseUp (e.g. 'go next').", "STRING"),
        },
        "required": ["name", "left", "top", "width", "height"],
    },
    "create_field": {
        "description": "Create a text field on the current card.",
        "properties": {
            "name": ("Field name.", "STRING"),
            "left": ("X position.", "STRING"),
            "top": ("Y position.", "STRING"),
            "width": ("Width in points.", "STRING"),
            "height": ("Height in points.", "STRING"),
            "text": ("Default text content.", "STRING"),
        },
        "required": ["name", "left", "top", "width", "height"],
    },
    "create_shape": {
        "description": "Create a shape (rectangle / roundRect / oval / line) on the current card.",
        "properties": {
            "name": ("Shape name.", "STRING"),
            "shape_type": ("Shape type: rectangle | roundRect | oval | line.", "STRING"),
            "left": ("X position.", "STRING"),
            "top": ("Y position.", "STRING"),
            "width": ("Width in points.", "STRING"),
            "height": ("Height in points.", "STRING"),
            "fill_color": ("Fill color hex (e.g. #FF0000).", "STRING"),
        },
        "required": ["name", "shape_type", "left", "top", "width", "height"],
    },
    "create_card": {
        "description": "Create a new card in the stack.",
        "properties": {
            "background_name": ("Name of an existing background to use (optional).", "STRING"),
        },
        "required": [],
    },
    "create_sprite_area": {
        "description": "Add a sprite area to the current card.",
        "properties": {
            "name": ("Sprite area name.", "STRING"),
            "left": ("X position.", "STRING"),
            "top": ("Y position.", "STRING"),
            "width": ("Width.", "STRING"),
            "height": ("Height.", "STRING"),
        },
        "required": ["name", "left", "top", "width", "height"],
    },
    "get_scene_spec": {
        "description": "Get the full SceneSpec JSON for a sprite area's active scene.",
        "properties": {
            "sprite_area_name": ("Name of the sprite area part.", "STRING"),
        },
        "required": ["sprite_area_name"],
    },
    "get_scene_diagnostics": {
        "description": "Get diagnostic information (errors, warnings) about a sprite scene.",
        "properties": {
            "sprite_area_name": ("Name of the sprite area part.", "STRING"),
        },
        "required": ["sprite_area_name"],
    },
    "list_repository_assets": {
        "description": "List every asset in the Sprite Repository.",
        "properties": {},
        "required": [],
    },
    "classify_asset_as_tileset": {
        "description": "Mark a Sprite Repository asset as a tileset with tile dimensions.",
        "properties": {
            "name": ("Asset name.", "STRING"),
            "tile_width": ("Width of each tile in pixels.", "STRING"),
            "tile_height": ("Height of each tile in pixels.", "STRING"),
            "tile_columns": ("Number of tile columns in the sheet.", "STRING"),
            "tile_rows": ("Number of tile rows in the sheet.", "STRING"),
        },
        "required": ["name", "tile_width", "tile_height", "tile_columns", "tile_rows"],
    },
    "create_tilemap": {
        "description": "Create a tile map node in a sprite area.",
        "properties": {
            "sprite_area_name": ("Name of the sprite area part.", "STRING"),
            "tilemap_name": ("Name for the new tilemap.", "STRING"),
            "tileset_asset": ("Repository asset name to use as the tileset.", "STRING"),
            "x": ("X position.", "STRING"),
            "y": ("Y position.", "STRING"),
            "columns": ("Number of columns.", "STRING"),
            "rows": ("Number of rows.", "STRING"),
        },
        "required": ["sprite_area_name", "tilemap_name", "tileset_asset"],
    },
    "set_tile": {
        "description": "Set a single tile in a tilemap.",
        "properties": {
            "sprite_area_name": ("Name of the sprite area part.", "STRING"),
            "tilemap_name": ("Name of the tilemap node.", "STRING"),
            "column": ("Column index (0-based).", "STRING"),
            "row": ("Row index (0-based).", "STRING"),
            "tile_index": ("Tile index within the tileset.", "STRING"),
        },
        "required": ["sprite_area_name", "tilemap_name", "column", "row", "tile_index"],
    },
    "check_script": {
        "description": "Validate a HypeTalk script. Returns OK or a parse error with line number.",
        "properties": {
            "script": ("The HypeTalk script source to validate.", "STRING"),
        },
        "required": ["script"],
    },
    "go_to_card": {
        "description": "Navigate to a card by name, number, or direction.",
        "properties": {
            "destination": ("Card name, number, or direction (next | previous | first | last).", "STRING"),
        },
        "required": ["destination"],
    },
}


def render_tool_declaration(tool_name: str) -> str:
    """Render a tool declaration in the exact format Ollama's
    functiongemma renderer produces. Returns empty string for
    unknown tools (silently skipped)."""
    decl = TOOL_DECLARATIONS.get(tool_name)
    if not decl:
        return ""

    sb = [f"<start_function_declaration>declaration:{tool_name}{{"]
    sb.append(f"description:<escape>{decl['description']}<escape>")

    # Parameters block
    sb.append(",parameters:{")
    if decl["properties"]:
        sb.append("properties:{")
        prop_entries = []
        for key in sorted(decl["properties"].keys()):
            desc, typ = decl["properties"][key]
            prop_entries.append(
                f"{key}:{{description:<escape>{desc}<escape>,type:<escape>{typ}<escape>}}"
            )
        sb.append(",".join(prop_entries))
        sb.append("}")
    if decl["required"]:
        if decl["properties"]:
            sb.append(",")
        sb.append("required:[")
        sb.append(",".join(f"<escape>{r}<escape>" for r in decl["required"]))
        sb.append("]")
    if decl["properties"] or decl["required"]:
        sb.append(",")
    sb.append("type:<escape>OBJECT<escape>")
    sb.append("}}<end_function_declaration>")

    return "".join(sb)


# ─────────────────────────────────────────────────────────────────────
# CURRENT STATE block synthesis
# ─────────────────────────────────────────────────────────────────────

# Patterns to harvest object names from an assistant's script or tool-
# call arguments so the synthesized CURRENT STATE block references the
# SAME names the output uses. Teaches the model to read names from
# the CURRENT STATE section and reuse them rather than hallucinating.
_NAME_PATTERNS = [
    (re.compile(r'sprite\s+"([^"]+)"', re.IGNORECASE), "sprite"),
    (re.compile(r'image\s+"([^"]+)"', re.IGNORECASE), "image"),
    (re.compile(r'field\s+"([^"]+)"', re.IGNORECASE), "field"),
    (re.compile(r'button\s+"([^"]+)"', re.IGNORECASE), "button"),
    (re.compile(r'label\s+"([^"]+)"', re.IGNORECASE), "label"),
    (re.compile(r'shape\s+"([^"]+)"', re.IGNORECASE), "shape"),
    (re.compile(r'scene\s+"([^"]+)"', re.IGNORECASE), "scene"),
]


def extract_referenced_names(text: str) -> dict[str, list[str]]:
    """Walk a script or tool-call arguments blob, collect every
    named object reference grouped by type. Case-insensitive match
    on HypeTalk's canonical `<type> "name"` form."""
    found: dict[str, list[str]] = {}
    for pattern, kind in _NAME_PATTERNS:
        for match in pattern.finditer(text):
            name = match.group(1)
            found.setdefault(kind, [])
            if name not in found[kind]:
                found[kind].append(name)
    return found


def synthesize_current_state(referenced: dict[str, list[str]],
                             rng: random.Random,
                             sprite_area_name: str = "") -> str:
    """Build a CURRENT STATE block mirroring what Hype's AIChatPanel
    injects at inference time. Includes only the objects that appear
    in the row's output, so the model learns the correspondence
    between "named object in CURRENT STATE" → "the same name in my
    output".

    If the row uses sprites, they're attributed to a single sprite
    area. When sprite_area_name is empty, pick a common name.
    """
    lines = []
    # Stack + card header (placeholders; the names don't matter for
    # learning the "read names from context" skill).
    lines.append('Stack: "test" (1 cards)')
    lines.append('Current card: "main" | Background: "default"')

    # Card-level parts the output references.
    card_parts = []
    for kind in ("field", "button", "label", "shape", "image"):
        for n in referenced.get(kind, []):
            card_parts.append(f'[{kind}] "{n}"')
    if referenced.get("sprite") or referenced.get("scene"):
        if not sprite_area_name:
            sprite_area_name = rng.choice(["bounder", "playfield", "arena", "level1", "game_area", "stage"])
        card_parts.append(f'[spriteArea] "{sprite_area_name}"')
    lines.append(
        f"Card parts: {', '.join(card_parts) if card_parts else 'none'}"
    )

    # Sprite-area summary matching AIChatPanel's format.
    sprite_info_bits: list[str] = []
    sprites = referenced.get("sprite", [])
    scene_name = (referenced.get("scene") or ["main"])[0]
    if sprites or referenced.get("scene"):
        node_parts = [f'sprite "{s}"' for s in sprites]
        sprite_info_bits.append(
            f'SpriteArea "{sprite_area_name}" active scene "{scene_name}" '
            f'(1 scenes): [{", ".join(node_parts) if node_parts else "empty"}]'
        )
    if sprite_info_bits:
        lines.append("Sprites: " + ". ".join(sprite_info_bits))

    return "CURRENT STATE:\n" + "\n".join(lines)


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


def _inject_current_state(
    row: dict,
    rng: random.Random,
    probability: float = 0.30,
) -> dict:
    """For a fraction of rows, append a CURRENT STATE block to the
    system prompt that references the same names the assistant's
    output uses. Teaches the model to read object names from
    context instead of hallucinating them.

    Mutates and returns the row for chainability. Rows without any
    nameable references are left untouched even when selected.
    """
    if rng.random() >= probability:
        row["_has_current_state"] = False
        return row

    # Harvest referenced names from the assistant content (or, for
    # tool-call rows, from the serialised arguments inside the call).
    assistant = row["messages"][-1].get("content") or ""
    referenced = extract_referenced_names(assistant)
    if not any(referenced.values()):
        row["_has_current_state"] = False
        return row

    current_state = synthesize_current_state(referenced, rng)
    sys_msg = row["messages"][0]
    sys_msg["content"] = sys_msg["content"] + "\n\n" + current_state
    row["_has_current_state"] = True
    return row


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
    parser.add_argument(
        "--current-state-prob",
        type=float,
        default=0.30,
        help=(
            "Fraction of rows that get a synthesized CURRENT STATE "
            "block in their system prompt. Set to 0 to disable."
        ),
    )
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Base system prompts: minimal for script rows, minimal + tool
    # catalog hint for tool rows. For tool-call rows we ALSO inject
    # the specific tool's declaration in the exact functiongemma
    # renderer format so the model sees declaration→call pairing
    # during training (fixes v1's issue where the model learned the
    # call body but not the surrounding tags).
    guide = load_system_prompt()
    script_system = guide
    tool_system_base = guide + "\n\n" + load_tool_catalog_hint().strip()

    rows: list[dict] = []

    script_count = 0
    for intent, script in iter_script_examples():
        rows.append(make_script_row(intent, script, script_system))
        script_count += 1

    tool_count = 0
    if args.include_tools:
        for intent, tool_call in iter_tool_call_examples():
            tool_name = tool_call.get("name", "")
            declaration = render_tool_declaration(tool_name)
            if declaration:
                row_system = (
                    tool_system_base
                    + "\n\nAvailable tool declaration:\n"
                    + declaration
                )
            else:
                row_system = tool_system_base
            rows.append(make_tool_call_row(intent, tool_call, row_system))
            tool_count += 1

    if not rows:
        raise SystemExit(
            "No training rows generated. Check corpus/seed/ for YAML files."
        )

    rng = random.Random(args.seed)

    # Sprinkle CURRENT STATE blocks across ~N% of rows BEFORE the
    # train/valid split so both splits see the pattern.
    if args.current_state_prob > 0:
        for row in rows:
            _inject_current_state(row, rng, probability=args.current_state_prob)

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

    # Strip internal annotation keys before serialising to JSONL so
    # MLX-LM doesn't receive unknown fields on the message rows.
    cs_count = sum(1 for r in rows if r.pop("_has_current_state", False))

    for path, subset in [
        (train_path, train_rows),
        (valid_path, valid_rows),
        (test_path, valid_rows),
    ]:
        path.write_text("\n".join(json.dumps(r) for r in subset) + "\n")

    print(
        f"Wrote {len(train_rows)} train + {len(valid_rows)} valid rows "
        f"({script_count} script, {tool_count} tool-call; "
        f"{cs_count} with CURRENT STATE injected) to {OUT_DIR}"
    )


if __name__ == "__main__":
    main()

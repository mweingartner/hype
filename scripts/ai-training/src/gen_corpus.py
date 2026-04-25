#!/usr/bin/env python3
'''Generate an MLX-LM training corpus from the seed YAML files.

The pipeline intentionally keeps hand-authored seed examples in
human-friendly YAML (corpus/seed/*.yaml) so they are easy to
review, diff, and extend when the AI regresses on a new pattern.
This script transforms them into the JSONL chat format MLX-LM's
LoRA trainer expects — one message array per line, roles system /
user / assistant / tool.

Output: out/train.jsonl, out/valid.jsonl, out/test.jsonl with a
90/10 split. Re-run this stage any time you add or edit seeds.

v3 change (April 2026): every tool-call training row now carries
the FULL runtime tool catalog as rendered `<start_function_declaration>`
blocks, matching byte-for-byte what Ollama's `functiongemma` renderer
injects at inference time. The declarations come from
`out/tool_catalog.json` produced by `_extract_tools.py`, so the
catalog stays in sync with `HypeTools.swift` automatically.
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
TOOL_CATALOG_PATH = OUT_DIR / "tool_catalog.json"
CONFIG_PATH = ROOT / "config.yaml"


# ─────────────────────────────────────────────────────────────────────
# Runtime system prompt shape — must match AIChatPanel.swift verbatim
# ─────────────────────────────────────────────────────────────────────

# Trimmed runtime prompt shape matching the `hypetalk-*` branch of
# AIChatPanel.swift (Apr 2026). This is what Hype actually sends at
# inference time, so training rows must see the same preamble.
RUNTIME_SYSTEM_PROMPT_TEMPLATE = """You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is {canvas_width}x{canvas_height} points.

TOOL-USE PRIORITIES:
- To READ a property: prefer get_part_property / get_node_property / get_stack_property / get_card_property / get_background_property / get_scene_script / list_scene_nodes / list_all_cards / get_card_parts over get_scene_spec (which is 10k+ tokens).
- To MODIFY one property: prefer set_part_property / set_node_property / set_scene_property / set_stack_property / set_card_property / set_background_property / set_physics_body / set_card_script / set_background_script / set_stack_script over apply_scene_diff.
- To CREATE a single node: prefer add_sprite_to_scene / add_label_to_scene / add_shape_to_scene / add_emitter_to_scene / add_joint_to_scene over apply_scene_diff.
- Use apply_scene_diff ONLY for multi-node batch edits.
- When the user says "background", set on_background to "true" in create tools.
- If the user asks to create, set, attach, install, replace, or update a script on the stack, card, background, button, field, sprite area, scene, or node, use the appropriate setter tool. Do not answer with bare HypeTalk unless the user explicitly asks only to write or explain code.
- Before storing any HypeTalk script with create_button, create_field, set_part_property(property=script), set_node_script, set_scene_script, set_card_script, set_background_script, or set_stack_script, call check_script first and only store the script after it returns OK.
- For button scripts, just provide the HypeTalk command (e.g. "go next"). It will be auto-wrapped in on mouseUp/end mouseUp."""


# Common canvas sizes Hype users run with — vary across rows so the
# model doesn't anchor to any single dimension from the system prompt.
CANVAS_SIZES = [
    (800, 600),
    (1024, 768),
    (640, 480),
    (1280, 720),
    (512, 512),
]


# ─────────────────────────────────────────────────────────────────────
# Tool catalog → chat/tool declaration rendering
# ─────────────────────────────────────────────────────────────────────

def load_config() -> dict:
    if not CONFIG_PATH.exists():
        return {}
    return yaml.safe_load(CONFIG_PATH.read_text()) or {}


def configured_tool_format(cfg: dict) -> str:
    value = cfg.get("tool_format") or cfg.get("model_family") or "functiongemma"
    return str(value).strip().lower()

def load_tool_catalog() -> list[dict]:
    '''Load the tool catalog extracted from HypeTools.swift.

    The catalog is produced by `_extract_tools.py` and stored at
    `out/tool_catalog.json`. If the file is missing, emit a clear
    error pointing the user at the Makefile target.
    '''
    if not TOOL_CATALOG_PATH.exists():
        raise SystemExit(
            f"Tool catalog not found at {TOOL_CATALOG_PATH}. "
            "Run `make tool-catalog` (or `python3 src/_extract_tools.py`) first."
        )
    return json.loads(TOOL_CATALOG_PATH.read_text())


def _escape_fg_string(s: str) -> str:
    '''Escape a string for embedding between `<escape>` delimiters.

    The functiongemma renderer uses the literal `<escape>` token as
    a quoting boundary. User-supplied descriptions that happen to
    contain that token would break the format; replace with a
    near-identical ASCII sequence. Newlines are collapsed to spaces
    to keep declarations single-line (matches Ollama's behaviour).
    '''
    return (
        s.replace('<escape>', '<esc>')
         .replace('\n', ' ')
         .replace('\r', ' ')
    )


def render_tool_declaration(tool: dict, minimal: bool = False) -> str:
    '''Render a single tool as a functiongemma `declaration` block.

    Matches Ollama's `renderers/functiongemma.go:renderToolDeclaration`
    output. When `minimal=True`, descriptions (tool and per-param)
    are omitted so each declaration shrinks from ~700 chars to ~200
    chars — small enough that a subset of declarations fits
    comfortably inside training's max-seq-length budget.
    '''
    name = tool["name"]
    props = tool["parameters"]["properties"]
    required = tool["parameters"]["required"]

    sb = [f"<start_function_declaration>declaration:{name}{{"]
    if not minimal:
        description = _escape_fg_string(tool.get("description", ""))
        sb.append(f"description:<escape>{description}<escape>,")

    sb.append("parameters:{")
    if props:
        sb.append("properties:{")
        prop_entries = []
        # Deterministic order so identical training runs yield
        # byte-identical corpora (helps diffability / reproducibility).
        for key in sorted(props.keys()):
            typ = props[key].get("type", "STRING").upper()
            if minimal:
                prop_entries.append(
                    f"{key}:{{type:<escape>{typ}<escape>}}"
                )
            else:
                desc = _escape_fg_string(props[key].get("description", ""))
                prop_entries.append(
                    f"{key}:{{description:<escape>{desc}<escape>,"
                    f"type:<escape>{typ}<escape>}}"
                )
        sb.append(",".join(prop_entries))
        sb.append("}")
    if required:
        if props:
            sb.append(",")
        sb.append("required:[")
        sb.append(",".join(f"<escape>{r}<escape>" for r in required))
        sb.append("]")
    if props or required:
        sb.append(",")
    sb.append("type:<escape>OBJECT<escape>")
    sb.append("}}<end_function_declaration>")

    return "".join(sb)


def _json_schema_for_qwen(value):
    '''Return a JSON schema fragment compatible with Ollama/Qwen tools.

    The Swift extractor emits legacy uppercase schema type strings
    (`STRING`, `OBJECT`, ...). Ollama's public tool schema examples use
    lowercase JSON Schema types, so normalize recursively for Qwen rows.
    '''
    if isinstance(value, dict):
        normalized = {}
        for key, child in value.items():
            if key == "type" and isinstance(child, str):
                normalized[key] = child.lower()
            else:
                normalized[key] = _json_schema_for_qwen(child)
        return normalized
    if isinstance(value, list):
        return [_json_schema_for_qwen(child) for child in value]
    return value


def render_qwen_tool_declaration(tool: dict, minimal: bool = False) -> str:
    '''Render one tool in Qwen's `<tools>` JSON-line format.

    This mirrors the qwen3 Ollama chat template:
    {"type": "function", "function": {...}}
    '''
    props = tool["parameters"]["properties"]
    if minimal:
        properties = {
            key: {"type": (props[key].get("type") or "STRING").lower()}
            for key in sorted(props.keys())
        }
    else:
        properties = {
            key: _json_schema_for_qwen(props[key])
            for key in sorted(props.keys())
        }

    function = {
        "name": tool["name"],
        "parameters": {
            "type": "object",
            "properties": properties,
            "required": tool["parameters"].get("required", []),
        },
    }
    if not minimal:
        function["description"] = tool.get("description", "")

    return json.dumps(
        {"type": "function", "function": function},
        ensure_ascii=False,
    )


def render_qwen_tool_block(catalog: list[dict], minimal: bool = False) -> str:
    declarations = "\n".join(
        render_qwen_tool_declaration(tool, minimal=minimal)
        for tool in catalog
    )
    return f"""# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{declarations}
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{{"name": <function-name>, "arguments": <args-json-object>}}
</tool_call>"""


def render_subset_declarations(
    catalog: list[dict],
    rng: random.Random,
    target_tool_name: str = "",
    subset_size: int = 10,
    minimal: bool = True,
    tool_format: str = "functiongemma",
) -> str:
    '''Render a random subset of the tool catalog as declarations.

    When `target_tool_name` is non-empty, that tool is always
    included (so training rows that produce a tool call for
    NAME see NAME's declaration in-context). The rest of the
    subset is randomly sampled from the catalog WITHOUT
    replacement.

    Subset size is deliberately small (~10 tools × ~200 chars =
    ~2000 chars per block) so each row fits in training's 4k
    max-seq-length budget. At inference time Hype ships 43-66
    declarations depending on route — the model generalises from
    "variable-size subset in context" during training.
    '''
    subset_size = min(subset_size, len(catalog))
    others = [t for t in catalog if t["name"] != target_tool_name]
    picked = rng.sample(others, max(0, subset_size - (1 if target_tool_name else 0)))
    if target_tool_name:
        target = next((t for t in catalog if t["name"] == target_tool_name), None)
        if target is not None:
            picked = [target] + picked
    # Stable order so identical seeds yield identical output.
    picked.sort(key=lambda t: t["name"])
    if tool_format == "qwen3":
        return render_qwen_tool_block(picked, minimal=minimal)
    return "\n".join(render_tool_declaration(t, minimal=minimal) for t in picked)


def render_all_declarations(
    catalog: list[dict],
    tool_format: str = "functiongemma",
) -> str:
    '''Concatenate every tool's declaration with newlines.

    Ollama's runtime injects all tool declarations as a single run;
    training rows should mirror the exact same ordering and
    separator convention so the model doesn't learn a slightly
    different prefix.
    '''
    if tool_format == "qwen3":
        return render_qwen_tool_block(catalog)
    return "\n".join(render_tool_declaration(t) for t in catalog)


# ─────────────────────────────────────────────────────────────────────
# CURRENT STATE block synthesis — now at 80% probability (up from 30%)
# to match Hype's runtime, which always ships a CURRENT STATE section.
# ─────────────────────────────────────────────────────────────────────

# Harvest object names from an assistant's script or tool-call
# arguments so the synthesized CURRENT STATE references the SAME
# names the output uses. Teaches the model to read from context
# rather than hallucinating.
_NAME_PATTERNS = [
    (re.compile(r'sprite\s+"([^"]+)"', re.IGNORECASE), "sprite"),
    (re.compile(r'image\s+"([^"]+)"', re.IGNORECASE), "image"),
    (re.compile(r'field\s+"([^"]+)"', re.IGNORECASE), "field"),
    (re.compile(r'button\s+"([^"]+)"', re.IGNORECASE), "button"),
    (re.compile(r'label\s+"([^"]+)"', re.IGNORECASE), "label"),
    (re.compile(r'shape\s+"([^"]+)"', re.IGNORECASE), "shape"),
    (re.compile(r'scene\s+"([^"]+)"', re.IGNORECASE), "scene"),
    (re.compile(r'node\s+"([^"]+)"', re.IGNORECASE), "node"),
    (re.compile(r'card\s+"([^"]+)"', re.IGNORECASE), "card"),
    (re.compile(r'background\s+"([^"]+)"', re.IGNORECASE), "background"),
    (re.compile(r'chart\s+"([^"]+)"', re.IGNORECASE), "chart"),
]

# Match tool-call argument names that carry named-entity references.
# Used when harvesting names from `tool_call.arguments` blobs that
# don't speak HypeTalk syntax directly.
_ARG_NAME_KEYS = {
    "part_name": "generic_part",
    "sprite_area_name": "spriteArea",
    "sprite_name": "sprite",
    "node_name": "node",
    "tilemap_name": "node",
    "label_name": "label",
    "shape_name": "shape",
    "emitter_name": "emitter",
    "audio_name": "audio",
    "video_name": "video",
    "group_name": "group",
    "chart_name": "chart",
    "card_name": "card",
    "background_name": "background",
    "asset_name": "asset",
    "camera_name": "camera",
    "name": "generic_part",
}


def extract_referenced_names(text: str) -> dict[str, list[str]]:
    '''Walk a script or tool-call arguments blob, collect every
    named object reference grouped by type.'''
    found: dict[str, list[str]] = {}
    for pattern, kind in _NAME_PATTERNS:
        for match in pattern.finditer(text):
            name = match.group(1)
            found.setdefault(kind, [])
            if name not in found[kind]:
                found[kind].append(name)
    for key, kind in _ARG_NAME_KEYS.items():
        pattern = re.compile(
            rf'"{re.escape(key)}"\s*:\s*"([^"]+)"|'
            rf'{re.escape(key)}:<escape>([^<]+)<escape>'
        )
        for match in pattern.finditer(text):
            name = match.group(1) or match.group(2)
            if not name:
                continue
            found.setdefault(kind, [])
            if name not in found[kind]:
                found[kind].append(name)
    return found


def synthesize_current_state(referenced: dict[str, list[str]],
                             rng: random.Random,
                             sprite_area_name: str = "") -> str:
    '''Build a CURRENT STATE block mirroring what Hype's AIChatPanel
    injects at inference time. Includes only the objects that
    appear in the row's output, so the model learns the
    correspondence between "named object in CURRENT STATE" → "same
    name in my output".
    '''
    lines = []
    stack_names = ["test", "game", "demo", "playground", "app", "prototype", "lesson1"]
    card_names = ["main", "start", "title", "level1", "Card 1", "Card 2", "home"]
    bg_names = ["default", "title_bg", "game_bg", "menu_bg", "Background 1"]

    stack_name = rng.choice(stack_names)
    card_count = rng.choice([1, 2, 3, 5, 8, 10])
    card_name = rng.choice(card_names)
    # If the row references a card by name, use it (so the name the
    # model sees in CURRENT STATE matches the name it outputs).
    if referenced.get("card"):
        card_name = referenced["card"][0]
    bg_name = rng.choice(bg_names)
    if referenced.get("background"):
        bg_name = referenced["background"][0]

    lines.append(f'Stack: "{stack_name}" ({card_count} cards)')
    lines.append(f'Current card: "{card_name}" | Background: "{bg_name}"')

    # Card-level parts the output references.
    card_parts = []
    for kind in ("field", "button", "label", "shape", "image", "chart"):
        for n in referenced.get(kind, []):
            card_parts.append(f'[{kind}] "{n}"')
    sprites = referenced.get("sprite", [])
    nodes = referenced.get("node", [])
    if sprites or referenced.get("scene") or nodes:
        if not sprite_area_name:
            sprite_area_name = rng.choice(
                ["bounder", "playfield", "arena", "level1", "game_area", "stage"]
            )
        card_parts.append(f'[spriteArea] "{sprite_area_name}"')
    lines.append(
        f"Card parts: {', '.join(card_parts) if card_parts else 'none'}"
    )

    # Sprite-area summary matching AIChatPanel's format.
    sprite_info_bits: list[str] = []
    scene_name = (referenced.get("scene") or ["main"])[0]
    if sprites or referenced.get("scene") or nodes:
        node_parts = [f'sprite "{s}"' for s in sprites]
        # Also surface any generic `node "X"` references that weren't
        # specifically typed as sprite — they appear in the scene as
        # unknown-typed nodes.
        for n in nodes:
            if n not in sprites:
                node_parts.append(f'node "{n}"')
        sprite_info_bits.append(
            f'SpriteArea "{sprite_area_name}" active scene "{scene_name}" '
            f'(1 scenes): [{", ".join(node_parts) if node_parts else "empty"}]'
        )
    if sprite_info_bits:
        lines.append("Sprites: " + ". ".join(sprite_info_bits))

    return "CURRENT STATE:\n" + "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────
# System prompt assembly for training rows
# ─────────────────────────────────────────────────────────────────────

def build_runtime_system_prompt(
    catalog: list[dict],
    rng: random.Random,
    include_tool_declarations: bool = False,
    subset_declarations: bool = True,
    subset_size: int = 10,
    target_tool: str = "",
    include_tool_hint: bool = False,
    current_state: str = "",
    tool_format: str = "functiongemma",
) -> str:
    '''Build a system prompt that matches Hype's runtime shape.

    Three mutually-exclusive tool-surface modes (in priority order):

    1. `include_tool_declarations=True`: inject the FULL rendered
       catalog (~14k tokens). Matches inference exactly but pushes
       rows past practical max-seq-length. Use only when you have
       the memory + training-time budget for it.
    2. `subset_declarations=True` (v4 default): inject ~10 random
       declarations in minimal format (name + param keys + required
       only, no descriptions). Includes the `target_tool` if set so
       tool-call rows see their target's declaration in-context.
       Matches the KIND of tokens inference injects (same opening
       `<start_function_declaration>declaration:NAME{…}` shape)
       without the volume — each block ~2k tokens.
    3. `include_tool_hint=True`: compact plain-text list of tool
       names + short descriptions. No `<start_function_declaration>`
       tokens, so this mode causes the distribution mismatch that
       broke v3. Retained for reference / A-B comparison only.
    '''
    canvas_w, canvas_h = rng.choice(CANVAS_SIZES)
    sys = RUNTIME_SYSTEM_PROMPT_TEMPLATE.format(
        canvas_width=canvas_w, canvas_height=canvas_h
    )

    if include_tool_declarations:
        sys += "\n\n" + render_all_declarations(
            catalog,
            tool_format=tool_format,
        )
    elif subset_declarations:
        sys += "\n\n" + render_subset_declarations(
            catalog,
            rng,
            target_tool_name=target_tool,
            subset_size=subset_size,
            minimal=True,
            tool_format=tool_format,
        )
    elif include_tool_hint:
        sys += "\n\n" + compact_tool_hint(catalog)

    if current_state:
        sys += "\n\n" + current_state

    return sys


def compact_tool_hint(catalog: list[dict]) -> str:
    '''Return a short multi-line hint listing every tool name with
    its first-sentence description (or the first 80 chars, whichever
    is shorter). Used as a training-time substitute for the full
    functiongemma declaration block: gives the model a grounding
    list of what tools exist without the ~14k-token weight of the
    full declarations.

    Format:
        TOOLS (N available):
        - tool_name — short description...
        ...
    '''
    lines = [f"TOOLS ({len(catalog)} available):"]
    for tool in sorted(catalog, key=lambda t: t["name"]):
        desc = tool.get("description", "").replace("\n", " ").strip()
        first_sentence = desc.split(". ")[0].strip()
        if len(first_sentence) > 80:
            first_sentence = first_sentence[:77] + "..."
        lines.append(f"- {tool['name']} — {first_sentence}")
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────
# Row emitters
# ─────────────────────────────────────────────────────────────────────

def _format_functiongemma_value(v) -> str:
    '''Serialize a single argument value in Ollama's functiongemma
    format.

    Strings → `<escape>value<escape>`
    Bools   → bare `true` / `false`
    Numbers → bare decimal / integer
    Lists   → `[v1,v2,...]` with each value recursively formatted
    Dicts   → `{key:v1,key:v2,...}` with each value recursively formatted

    Trailing whitespace on string values is rstripped — YAML block
    scalars often trail a newline or two, which would otherwise
    ship into the training label and confuse the parser.
    '''
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
    if isinstance(v, str):
        v = v.rstrip("\r\n\t ")
    return f"<escape>{v}<escape>"


def render_tool_call_body(
    tool_call: dict,
    tool_format: str = "functiongemma",
) -> str:
    '''Render a tool_call dict in the configured chat/tool syntax.'''
    name = tool_call["name"]
    args = tool_call.get("arguments", {}) or {}
    if tool_format == "qwen3":
        payload = {"name": name, "arguments": args}
        return (
            "<tool_call>\n"
            + json.dumps(payload, ensure_ascii=False)
            + "\n</tool_call>"
        )
    arg_pairs = [f"{k}:{_format_functiongemma_value(v)}" for k, v in args.items()]
    return f"<start_function_call>call:{name}{{{','.join(arg_pairs)}}}<end_function_call>"


def make_script_row(intent: str, script: str, system: str) -> dict:
    '''Build a chat-format row for a script-generation example.'''
    return {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": intent},
            {"role": "assistant", "content": script},
        ]
    }


def make_tool_call_row(
    intent: str,
    tool_call: dict,
    system: str,
    tool_format: str = "functiongemma",
) -> dict:
    '''Build a chat-format row for a single-turn tool call.'''
    return {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": intent},
            {"role": "assistant", "content": render_tool_call_body(tool_call, tool_format)},
        ]
    }


def make_tool_chain_row(
    intent: str,
    turns: list[dict],
    system: str,
    tool_format: str = "functiongemma",
) -> dict:
    '''Build a chat-format row for a multi-turn tool-use conversation.

    Each turn is one of:
        {"assistant_tool_call": {"name": ..., "arguments": {...}}}
        {"tool_result": "..."}
        {"assistant_text": "..."}

    Turns that start with an assistant_tool_call and are followed
    by a tool_result teach the "call the read tool → consume the
    result → call the write tool" pattern — exactly the multi-step
    flow Hype's AIChatPanel.swift dispatch loop supports at
    runtime.

    Important role mapping: Gemma-3's chat template only accepts
    `user`/`assistant`/`system` roles and strictly enforces
    user/assistant alternation. At inference time, Ollama feeds
    tool results back as user messages prefixed with a tool-result
    marker. We mirror that exactly in training: a `tool_result`
    becomes `{"role": "user", "content": "Tool result: ..."}`. The
    model therefore learns "after I emit a tool call, the next
    user turn carries the result".
    '''
    messages = [
        {"role": "system", "content": system},
        {"role": "user", "content": intent},
    ]
    for turn in turns:
        if "assistant_tool_call" in turn:
            messages.append({
                "role": "assistant",
                "content": render_tool_call_body(
                    turn["assistant_tool_call"],
                    tool_format,
                ),
            })
        elif "tool_result" in turn:
            # Present the tool output as a user message so Gemma-3's
            # alternation-strict Jinja template accepts the chain.
            # The "Tool result:" prefix matches what Ollama
            # injects at inference (see OllamaToolClient on the
            # runtime side) so training and inference see the
            # same surface syntax.
            messages.append({
                "role": "user",
                "content": f"Tool result: {str(turn['tool_result']).rstrip()}",
            })
        elif "assistant_text" in turn:
            messages.append({
                "role": "assistant",
                "content": str(turn["assistant_text"]),
            })
    return {"messages": messages}


# ─────────────────────────────────────────────────────────────────────
# YAML iteration
# ─────────────────────────────────────────────────────────────────────

def iter_script_examples() -> Iterator[tuple[str, str]]:
    '''Yield (intent, script) pairs from every seed YAML that
    defines `examples[n].script`.'''
    for path in sorted(SEED_DIR.glob("*.yaml")):
        data = yaml.safe_load(path.read_text())
        for ex in data.get("examples", []):
            if "script" in ex and "turns" not in ex:
                intent = ex["intent"].strip()
                script = ex["script"].rstrip()
                yield intent, script


def iter_tool_call_examples() -> Iterator[tuple[str, dict]]:
    '''Yield (intent, tool_call_dict) pairs for single-turn tool-use
    training rows.'''
    for path in sorted(SEED_DIR.glob("*.yaml")):
        data = yaml.safe_load(path.read_text())
        for ex in data.get("examples", []):
            if "tool_call" in ex and "turns" not in ex:
                intent = ex["intent"].strip()
                yield intent, ex["tool_call"]


def iter_tool_chain_examples() -> Iterator[tuple[str, list[dict]]]:
    '''Yield (intent, turns) pairs for multi-turn conversation rows.

    Supports chains like get_part_property → set_part_property
    that require the model to consume a tool result before making
    the next call.
    '''
    for path in sorted(SEED_DIR.glob("*.yaml")):
        data = yaml.safe_load(path.read_text())
        for ex in data.get("examples", []):
            if "turns" in ex:
                intent = ex["intent"].strip()
                yield intent, ex["turns"]


# ─────────────────────────────────────────────────────────────────────
# CURRENT STATE injection
# ─────────────────────────────────────────────────────────────────────

def harvest_row_references(row: dict) -> dict[str, list[str]]:
    '''Walk every non-system message in a row and union all
    referenced object names, keyed by entity type. Handles
    multi-turn chain rows (where tool results are injected as
    user messages with a "Tool result:" prefix) as well as
    single-turn rows.
    '''
    combined: dict[str, list[str]] = {}
    for msg in row["messages"]:
        if msg["role"] == "system":
            continue
        content = msg.get("content") or ""
        for kind, names in extract_referenced_names(content).items():
            combined.setdefault(kind, [])
            for n in names:
                if n not in combined[kind]:
                    combined[kind].append(n)
    return combined


def inject_current_state(
    row: dict,
    rng: random.Random,
    probability: float,
) -> bool:
    '''Maybe append a CURRENT STATE block to the row's system prompt,
    referencing the same names that appear in the assistant output.

    Returns True when a CURRENT STATE block was injected.
    '''
    if rng.random() >= probability:
        return False

    referenced = harvest_row_references(row)
    if not any(referenced.values()):
        return False

    current_state = synthesize_current_state(referenced, rng)
    sys_msg = row["messages"][0]
    sys_msg["content"] = sys_msg["content"] + "\n\n" + current_state
    return True


# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--split", type=float, default=0.9,
        help="Train/valid split ratio (default: 0.9)",
    )
    parser.add_argument(
        "--seed", type=int, default=42,
        help="RNG seed for split",
    )
    parser.add_argument(
        "--include-tools", action="store_true", default=True,
        help="Include tool-call rows (default: true)",
    )
    parser.add_argument(
        "--current-state-prob", type=float, default=0.80,
        help=(
            "Fraction of rows that get a synthesized CURRENT STATE "
            "block. Hype's runtime ALWAYS ships a CURRENT STATE "
            "section, so this is high by design (0.80 default)."
        ),
    )
    parser.add_argument(
        "--inject-declarations",
        action="store_true",
        default=False,
        help=(
            "Inject the full functiongemma tool-declaration block "
            "into every row's system prompt (matches runtime). "
            "Default: off — at ~14k tokens per row the full catalog "
            "blows past mlx_lm's practical max-seq-length budget."
        ),
    )
    parser.add_argument(
        "--subset-declarations",
        action="store_true",
        default=True,
        help=(
            "Inject ~10 random MINIMAL tool declarations per row "
            "(including the target tool for tool-call rows). Teaches "
            "the model the declaration→call token pattern without "
            "blowing past max-seq-length. Default: on."
        ),
    )
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Load the tool catalog once. Every row reuses the same
    # `render_all_declarations()` output — the `functiongemma`
    # renderer emits the catalog deterministically at inference
    # time, so sharing the rendered text here keeps training rows
    # byte-identical where they should be.
    cfg = load_config()
    tool_format = configured_tool_format(cfg)
    catalog = load_tool_catalog()
    rng = random.Random(args.seed)

    rows: list[dict] = []
    script_count = 0
    tool_count = 0
    chain_count = 0

    for intent, script in iter_script_examples():
        # Script rows still get a subset of declarations so the
        # model sees the tool-surface context in every row. It
        # learns that declarations don't ALWAYS require a tool
        # call — the negative-examples seed file (18_…) teaches
        # that directly.
        sys = build_runtime_system_prompt(
            catalog, rng,
            include_tool_declarations=args.inject_declarations,
            subset_declarations=args.subset_declarations,
            tool_format=tool_format,
        )
        rows.append(make_script_row(intent, script, sys))
        script_count += 1

    if args.include_tools:
        for intent, tool_call in iter_tool_call_examples():
            # Tool-call rows MUST see the target tool's declaration
            # so the model links declaration→call at the token level.
            target = tool_call.get("name", "")
            sys = build_runtime_system_prompt(
                catalog, rng,
                include_tool_declarations=args.inject_declarations,
                subset_declarations=args.subset_declarations,
                target_tool=target,
                tool_format=tool_format,
            )
            rows.append(make_tool_call_row(intent, tool_call, sys, tool_format))
            tool_count += 1

        for intent, turns in iter_tool_chain_examples():
            # Chain rows: include every tool the chain calls. The
            # first assistant_tool_call sets the subset seed.
            target_tool = ""
            for turn in turns:
                if "assistant_tool_call" in turn:
                    target_tool = turn["assistant_tool_call"].get("name", "")
                    break
            sys = build_runtime_system_prompt(
                catalog, rng,
                include_tool_declarations=args.inject_declarations,
                subset_declarations=args.subset_declarations,
                target_tool=target_tool,
                tool_format=tool_format,
            )
            rows.append(make_tool_chain_row(intent, turns, sys, tool_format))
            chain_count += 1

    if not rows:
        raise SystemExit(
            "No training rows generated. Check corpus/seed/ for YAML files."
        )

    # Sprinkle CURRENT STATE blocks BEFORE the train/valid split so
    # both splits see the pattern.
    cs_count = 0
    if args.current_state_prob > 0:
        for row in rows:
            if inject_current_state(row, rng, args.current_state_prob):
                cs_count += 1

    rng.shuffle(rows)

    split_idx = int(len(rows) * args.split)
    train_rows = rows[:split_idx]
    valid_rows = rows[split_idx:]
    if not valid_rows and train_rows:
        valid_rows = [train_rows.pop()]

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
        f"Wrote {len(train_rows)} train + {len(valid_rows)} valid rows\n"
        f"  script rows:       {script_count}\n"
        f"  tool-call rows:    {tool_count}\n"
        f"  tool-chain rows:   {chain_count}\n"
        f"  CURRENT STATE:     {cs_count} ({100 * cs_count / max(1, len(rows)):.0f}%)\n"
        f"  tool catalog:      {len(catalog)} tools\n"
        f"  tool format:       {tool_format}"
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
'''Extract the canonical tool catalog from HypeTools.swift.

The fine-tuning pipeline needs to inject the EXACT same tool
declarations the runtime (Ollama's `functiongemma` renderer) sends
at inference time. Hand-authoring a duplicate catalog in Python
drifts from Swift: new tools added in HypeTools.swift won't
appear in training rows, and the model will see unfamiliar tool
schemas at inference time.

This script parses HypeTools.swift textually and emits
`out/tool_catalog.json` with one entry per tool:

    {
      "name": "set_scene_script",
      "description": "...",
      "parameters": {
        "properties": {
          "sprite_area_name": {"type": "STRING", "description": "..."},
          ...
        },
        "required": ["sprite_area_name", "script"]
      }
    }

The textual parser is intentionally strict about the
`makeTool(name: ..., description: ..., params: [...])` shape —
any future refactor in Swift must keep that literal syntax or
this script must be re-taught.
'''

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = ROOT.parent.parent
SWIFT_SRC = REPO_ROOT / "Sources" / "HypeCore" / "AI" / "HypeTools.swift"
OUT_PATH = ROOT / "out" / "tool_catalog.json"


# Match a `makeTool(name: "X", description: "Y", description: """..."""," + params: [...])`
# block. Uses DOTALL + MULTILINE so multi-line string literals and
# params dicts are captured in one shot.
TOOL_BLOCK_RE = re.compile(
    r'makeTool\s*\(\s*name:\s*"([^"]+)"\s*,'  # name
    r'\s*description:\s*(?P<desc>"(?:[^"\\]|\\.)*"|"""[\s\S]*?""")\s*,'  # description (single- or triple-quoted)
    r'\s*params:\s*\[(?P<params>[\s\S]*?)\]\s*\)',
    re.MULTILINE,
)

# Inside params: "KEY": (TYPE, DESCRIPTION, REQUIRED)
# where TYPE and DESCRIPTION are string literals and REQUIRED is a
# bool literal (true/false).
PARAM_RE = re.compile(
    r'"(?P<key>[^"]+)"\s*:\s*\(\s*'
    r'"(?P<type>[^"]+)"\s*,\s*'
    r'(?P<desc>"(?:[^"\\]|\\.)*"|"""[\s\S]*?""")\s*,\s*'
    r'(?P<required>true|false)\s*\)',
    re.MULTILINE,
)


def unquote(literal: str) -> str:
    '''Strip enclosing quotes (single or triple) from a Swift string
    literal and collapse multi-line whitespace runs.'''
    literal = literal.strip()
    if literal.startswith('"""') and literal.endswith('"""'):
        literal = literal[3:-3]
    elif literal.startswith('"') and literal.endswith('"'):
        literal = literal[1:-1]
    # Swift triple-quoted string literals support a `\` at end of line
    # as a line continuation — the backslash + newline is elided by
    # the compiler. Our regex captured the raw source so we have to
    # remove those ourselves before any other whitespace collapsing.
    literal = re.sub(r'\\\s*\n', ' ', literal)
    # Un-escape `\"` → `"` and `\\` → `\` (standard Swift escape pairs
    # the compiler honours in both single- and triple-quoted strings).
    literal = literal.replace('\\"', '"').replace('\\\\', '\\')
    # Collapse every remaining whitespace run to a single space.
    literal = re.sub(r'\s+', ' ', literal).strip()
    return literal


def extract_params(block: str) -> list[tuple[str, str, str, bool]]:
    '''Parse the params dict body into a list of
    (key, type, description, required) tuples.'''
    out = []
    for m in PARAM_RE.finditer(block):
        key = m.group("key")
        typ = m.group("type").upper()  # Ollama expects uppercase types
        desc = unquote(m.group("desc"))
        required = m.group("required") == "true"
        out.append((key, typ, desc, required))
    return out


def extract_catalog() -> list[dict]:
    '''Parse HypeTools.swift and return the tool catalog as a list of
    dicts suitable for JSON serialisation.'''
    if not SWIFT_SRC.exists():
        raise SystemExit(f"HypeTools.swift not found at {SWIFT_SRC}")

    source = SWIFT_SRC.read_text()
    tools = []
    seen = set()

    for match in TOOL_BLOCK_RE.finditer(source):
        name = match.group(1)
        if name in seen:
            # Duplicate definition — skip. (Sanity guard; the linter
            # would normally catch this in Swift too.)
            continue
        seen.add(name)

        description = unquote(match.group("desc"))
        params = extract_params(match.group("params"))

        properties = {}
        required = []
        for key, typ, desc, req in params:
            properties[key] = {"type": typ, "description": desc}
            if req:
                required.append(key)

        tools.append({
            "name": name,
            "description": description,
            "parameters": {
                "properties": properties,
                "required": required,
            },
        })

    return tools


def main() -> None:
    catalog = extract_catalog()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(catalog, indent=2))
    print(f"Extracted {len(catalog)} tools from {SWIFT_SRC}")
    print(f"  → {OUT_PATH}")
    # Compact summary so a human can eyeball correctness at a glance.
    print("  tools:", ", ".join(t["name"] for t in catalog[:8]),
          "…" if len(catalog) > 8 else "")


if __name__ == "__main__":
    main()

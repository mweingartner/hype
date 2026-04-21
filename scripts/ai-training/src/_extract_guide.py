#!/usr/bin/env python3
"""Extract the HypeTalkGuide.llmContext string and print to stdout.

Used by `package.sh` to embed the current guide as the Modelfile's
SYSTEM prompt so the published model's built-in system prompt stays
in sync with whatever the Hype app injects at chat time.

Isolated from the shell script so the extraction logic is easy to
test and the script stays trivial.
"""
from __future__ import annotations

import pathlib
import re
import sys


def extract() -> str:
    root = pathlib.Path(__file__).resolve().parents[3]   # hype-v2
    guide_path = root / "Sources" / "HypeCore" / "AI" / "HypeTalkGuide.swift"
    if not guide_path.exists():
        raise SystemExit(f"error: {guide_path} not found")
    src = guide_path.read_text()
    m = re.search(
        r'public static let llmContext: String = """(.+?)"""', src, re.DOTALL
    )
    if not m:
        raise SystemExit(
            f"error: could not find llmContext declaration in {guide_path}"
        )
    text = m.group(1).strip()
    # Modelfile SYSTEM blocks use """ as their own delimiter; escape
    # any internal triple-double-quote so the Modelfile parser doesn't
    # mistake it for the end of the block.
    return text.replace('"""', r'"\"\"')


if __name__ == "__main__":
    sys.stdout.write(extract())

#!/usr/bin/env python3
'''Parametric augmentation of the seed corpus.

Takes each example from corpus/seed/*.yaml and generates N variants
by substituting interchangeable tokens (sprite names, colors, field
names, numeric constants). The goal is to multiply pattern coverage
without hand-authoring hundreds of near-identical examples — the
model learns the SHAPE of a valid script while the substitutions
keep it from memorizing literal strings.

Substitutions are intentionally CONSERVATIVE: we only rewrite
tokens inside double-quoted strings (sprite/field names, color
hex), and numeric literals that appear in safe contexts (velocity,
loc, size). Grammar-level tokens (keywords, operators, handler
names) are NEVER touched. This guarantees augmented examples
remain parseable.

Output: merges augmented rows into the corpus alongside seeds,
re-splits train/valid, rewrites out/corpus.*.jsonl.
'''

from __future__ import annotations

import argparse
import copy
import json
import random
import re
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parent.parent
SEED_DIR = ROOT / "corpus" / "seed"
OUT_DIR = ROOT / "out"

# Interchangeable token pools. Each pool is a list of concrete
# values that are valid in the same grammatical position. The
# augmenter picks matched substitutions across a single example so
# e.g. every mention of "player" swaps together to "hero".

SPRITE_POOL = [
    "player", "hero", "character", "avatar", "ship", "unit",
    "enemy", "monster", "foe", "rival", "enemy_1", "boss",
    "ball", "puck", "sphere", "orb", "coin", "gem",
    "target", "goal", "flag", "marker",
    "platform", "ground", "wall", "boundary",
    "blue_ball", "red_ball", "green_ball", "yellow_dot",
    "asteroid", "meteor", "debris", "fragment",
    "bullet", "projectile", "missile",
    "pickup", "powerup", "bonus",
]

FIELD_POOL = [
    "score", "lives", "points", "health", "mana", "timer",
    "status", "log", "output", "result", "msg", "message",
    "name", "username", "email", "password", "query",
    "count", "total", "bmi", "temperature", "value",
    "title", "heading", "body", "summary", "subtitle",
    "hud", "panel", "display", "readout",
]

BUTTON_POOL = [
    "OK", "Cancel", "Submit", "Confirm", "Apply", "Done",
    "Start", "Play", "Pause", "Stop", "Reset", "Retry",
    "Next", "Previous", "Back", "Home", "Menu", "Exit",
    "Save", "Load", "Delete", "Edit", "New", "Open",
    "Yes", "No", "Maybe", "Later",
    "Submit_form", "clear_btn", "go_btn", "help_btn",
]

LABEL_POOL = [
    "score_label", "title_label", "status_label", "hud_label",
    "message_label", "countdown_label", "timer_label", "health_label",
    "debug_label", "info_label", "scoreboard", "readout",
]

COLOR_POOL = [
    "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF",
    "#00FFFF", "#FFA500", "#800080", "#008080", "#808000",
    "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEEAD",
    "#D4A5A5", "#6C5B7B", "#C06C84", "#F67280", "#355C7D",
    "#000000", "#FFFFFF", "#222244", "#AAAAAA", "#444444",
]

# Numeric variation. Keyed by context tokens that appear just
# before the number in the source. Only applied where safe —
# swapping a 90 in "repeat with i = 1 to 10" would break logic.
NUMERIC_CONTEXTS = {
    # velocity X/Y
    "velocityX": [100, 150, 200, 250, 300, 350, 400, -150, -200, -250, -300],
    "velocityY": [100, 150, 200, 250, 300, 350, 400, -150, -200, -250, -300],
    # angles
    "rotation": [15, 30, 45, 60, 90, 120, 180, 270, 360, -45, -90],
    # scale factors (decimal)
    "xScale": [0.5, 0.75, 1.25, 1.5, 2.0, 3.0],
    "yScale": [0.5, 0.75, 1.25, 1.5, 2.0, 3.0],
    # alpha
    "alpha": [0.1, 0.25, 0.5, 0.75, 0.9],
    # positions (broad — mostly anywhere)
    "left": [0, 50, 100, 150, 200, 300, 400, 500, 600, 700],
    "top": [0, 50, 100, 150, 200, 300, 400, 500],
    "width": [50, 80, 100, 120, 150, 200, 300, 400, 600, 800],
    "height": [30, 40, 60, 80, 100, 150, 200, 300, 400],
    # fonts
    "textSize": [10, 12, 14, 16, 20, 24, 32, 48, 64],
    "fontSize": [10, 12, 14, 16, 20, 24, 32, 48, 64],
}


def substitute_strings(text: str, pool_map: dict, rng: random.Random) -> str:
    '''Replace all "quoted-string" literal occurrences of pool
    members with another pool member — preserving case and quoting.
    Each UNIQUE source token gets a SINGLE consistent mapping so
    every reference in the example stays aligned (e.g. all mentions
    of "player" go to "hero" together).
    '''
    # Build a local mapping for this example so the substitution is
    # consistent across lines. Only build mappings for tokens that
    # actually appear; a pool member that isn't in `text` is never
    # assigned a mapping.
    mapping: dict[str, str] = {}
    for pool_name, pool in pool_map.items():
        for token in pool:
            if f'"{token}"' in text:
                if token not in mapping:
                    candidate = rng.choice(pool)
                    # Avoid mapping to the same token (no-op) —
                    # try a few times, accept any candidate after
                    # that so we still return eventually.
                    for _ in range(5):
                        if candidate != token:
                            break
                        candidate = rng.choice(pool)
                    mapping[token] = candidate

    def repl(match: re.Match) -> str:
        inner = match.group(1)
        return f'"{mapping.get(inner, inner)}"'

    return re.sub(r'"([^"\n]+)"', repl, text)


def substitute_numbers(text: str, rng: random.Random) -> str:
    '''Swap numeric literals that follow a known context keyword.
    E.g. `velocityX of sprite "X" to 250` -> `... to 200`.

    The regex captures `<context> <optional prepositional glue> <number>`
    so it fires on both `set the velocityX of sprite "X" to 250`
    and `the velocityY of me to 300`.
    '''
    for ctx, pool in NUMERIC_CONTEXTS.items():
        pattern = re.compile(
            # context token, word boundary, up to 80 chars of glue,
            # then a number literal
            rf"(\b{re.escape(ctx)}\b[^\n]{{0,80}}?)(-?\d+(?:\.\d+)?)"
        )

        def repl(match: re.Match) -> str:
            glue = match.group(1)
            new_val = rng.choice(pool)
            return f"{glue}{new_val}"

        text = pattern.sub(repl, text, count=1)  # first occurrence only per context
    return text


def augment_example(example: dict, rng: random.Random) -> dict:
    '''Produce a single augmented copy of a seed example. Works on
    both script-style examples (with `script` field) and tool-call
    examples (with `tool_call.arguments`).'''
    pools = {
        "sprite": SPRITE_POOL,
        "field": FIELD_POOL,
        "button": BUTTON_POOL,
        "label": LABEL_POOL,
        "color": COLOR_POOL,
    }

    new_ex = copy.deepcopy(example)

    if "script" in new_ex:
        s = new_ex["script"]
        s = substitute_strings(s, pools, rng)
        s = substitute_numbers(s, rng)
        new_ex["script"] = s
        # Mirror the renamed tokens into the intent where it makes
        # sense — keeps prompt/completion aligned so the model
        # isn't asked "... blue_ball" and told to produce code
        # about "foo".
        new_ex["intent"] = substitute_strings(new_ex["intent"], pools, rng)

    if "tool_call" in new_ex:
        tc = new_ex["tool_call"]
        args = tc.get("arguments", {})
        new_args: dict = {}
        for k, v in args.items():
            if isinstance(v, str):
                v = substitute_strings(v, pools, rng)
                # ONLY augment numeric values for certain arg keys
                # — position/size keys. Don't touch tile indices,
                # loop counts, JSON blobs, etc.
                if k in ("left", "top", "width", "height", "x", "y"):
                    try:
                        float(v)
                        v = str(rng.choice(NUMERIC_CONTEXTS.get(k, [int(v)])))
                    except (ValueError, TypeError):
                        pass
            new_args[k] = v
        tc["arguments"] = new_args
        new_ex["intent"] = substitute_strings(new_ex["intent"], pools, rng)

    return new_ex


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--multiplier",
        type=int,
        default=3,
        help="How many augmented copies to produce per seed example",
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--target",
        type=int,
        default=None,
        help="Target total corpus size; overrides --multiplier to hit it",
    )
    args = parser.parse_args()

    rng = random.Random(args.seed)

    # Collect every seed example.
    seeds: list[tuple[Path, dict]] = []
    for path in sorted(SEED_DIR.glob("*.yaml")):
        data = yaml.safe_load(path.read_text())
        for ex in data.get("examples", []):
            seeds.append((path, ex))

    multiplier = args.multiplier
    if args.target is not None and len(seeds) > 0:
        # Pick multiplier so (originals + originals*mult) >= target.
        multiplier = max(0, (args.target - len(seeds)) // len(seeds) + 1)

    print(f"Seeds: {len(seeds)}; augmentation multiplier: {multiplier}")

    # Produce augmented examples, grouped back into YAML files so
    # the existing gen_corpus.py just reads the directory as before.
    augmented: dict[Path, list[dict]] = {}
    for path, ex in seeds:
        for _ in range(multiplier):
            aug = augment_example(ex, rng)
            augmented.setdefault(path, []).append(aug)

    # Write one augmented file per seed file with a `_aug` suffix
    # so the seed originals stay pristine and diff-able.
    written = 0
    for path, examples in augmented.items():
        out_path = SEED_DIR / (path.stem + "_aug.yaml")
        out_path.write_text(
            "# Auto-generated augmentations of " + path.name + "\n"
            "# Produced by src/augment_corpus.py — do not edit by hand.\n"
            "# Re-run `python3 src/augment_corpus.py` to regenerate.\n"
            + yaml.safe_dump({"examples": examples}, sort_keys=False, allow_unicode=True, width=120)
        )
        written += len(examples)

    print(f"Wrote {written} augmented rows across {len(augmented)} files")
    print(f"Total corpus size after aug: {len(seeds) + written}")
    print("Now run `python3 src/gen_corpus.py` (or `make corpus`) to regenerate JSONL.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Multi-turn aware tournament — fixes the single-turn grading bug.

Background
----------
The single-turn eval (`tournament.py`) grades each model on the
tool calls emitted on its FIRST conversational turn. But the
HypeTalkGuide MANDATES that models call `check_script` BEFORE any
storage tool (`set_part_property`, `set_card_script`,
`set_background_script`, etc.). Models that obey the rule call
`check_script` first, wait for the validator's "OK:" response, then
emit the storage tool on turn 2 — at which point the single-turn
eval has already moved on and graded the prompt as failed.

This harness keeps the conversation alive: when the model calls a
non-storage tool (notably `check_script`), we synthesize a plausible
result, append it as a `tool` message, and re-prompt. The grading
then runs against the CONCATENATED output of every turn, mirroring
what `AIChatPanel.swift` does in production (multi-turn tool loop).

Storage tools (`set_*_script`, `set_part_property`, `create_*`,
`delete_part`, `move_part`, `rename_card`, etc.) terminate the loop
because that's the action the prompt was asking for.

Usage:
  python3 src/tournament_multiturn.py \\
    --prompts eval/comprehensive_prompts.jsonl \\
    --models qwen3.6:35b granite4.1:8b granite4.1:30b \\
    --report out/multiturn_tournament.json \\
    --report-md out/multiturn_tournament.md
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import (  # noqa: E402
    OUT_DIR,
    ROOT,
    hypetalk_guide_text,
    load_tools,
    normalize_chat_output,
    prompt_expects_tool_use,
    score_prompt,
    summarize,
    system_prompt_for,
)
from tournament import format_leaderboard, per_category  # noqa: E402
import yaml  # noqa: E402

# Tools whose call ENDS the conversation — the storage / mutation
# action the prompt was asking for. Once one of these fires, we
# stop re-prompting.
STORAGE_TOOLS = {
    "set_part_property",
    "set_card_script",
    "set_background_script",
    "set_stack_script",
    "set_scene_script",
    "create_button",
    "create_field",
    "create_shape",
    "create_image",
    "create_video",
    "create_chart",
    "create_calendar",
    "create_pdf",
    "create_map",
    "create_colorwell",
    "create_stepper",
    "create_slider",
    "create_segmented",
    "create_audiorecorder",
    "create_scene3d",
    "create_progressview",
    "create_gauge",
    "create_divider",
    "create_card",
    "create_background",
    "delete_part",
    "delete_card",
    "delete_background",
    "move_part",
    "resize_part",
    "rename_card",
    "set_card_property",
    "set_background_property",
    "set_stack_property",
    "add_sprite_to_scene",
    "add_camera_to_scene",
    "add_emitter_to_scene",
    "add_tilemap_to_scene",
    "add_label_to_scene",
    "add_shape_to_scene",
    "remove_sprite_from_scene",
    "set_scene_node_property",
    "set_scene_background",
    "go_to_card",
    "set_image_filter",
    "add_map_annotation",
}

# Tools whose call should be RESPONDED to with a synthesized result
# so the model can continue. Anything in this dict will get its
# canned reply appended as a `tool` message and the conversation
# continues for another turn.
SIMULATED_RESULTS = {
    "check_script": "OK: script parsed and validated",
    # Introspection tools that might fire as a "let me look first"
    # before the storage call. Return empty / minimal results so
    # the model continues to the storage step.
    "get_card_parts": "[]",
    "get_part_properties": "{}",
    "list_all_properties": "{}",
    "get_card_script": "",
    "get_background_script": "",
    "get_stack_script": "",
    "get_part_script": "",
    "get_scene_script": "",
    "get_scene_nodes": "[]",
    "list_cards": "[]",
    "list_backgrounds": "[]",
    "list_scenes": "[]",
    "get_stack_info": "{}",
}

# Hard cap on conversation turns. Production also has a small cap;
# any model that loops beyond this is misbehaving regardless of
# task content.
MAX_TURNS = 4

# Synthetic document state appended to every system prompt so the
# eval mirrors what `AIChatPanel.swift` injects in production
# (`CURRENT STATE: Stack ... Current card ... Card parts ...`).
#
# The eval prompts in `comprehensive_prompts.jsonl` reference
# specific named entities (button "play", image "logo",
# fields "score" + "shared_status", background "title_bg",
# sprite area "arena" with scene "main", card "intro"). Without
# this block, the model cannot tell those entities already exist
# and falls back to creating new ones — which is correct behavior
# under ambiguity but doesn't match the test's `must_contain`
# expectation of `set_part_property`. With the block, the model
# uses the right setter for the right existing part.
SYNTHETIC_STATE = """
CURRENT STATE:
Stack: "TestStack" (3 cards)
Current card: "first" | Background: "title_bg"
Card parts: button "play" (button) at 100,100 100x40; \
image "logo" (image) at 220,100 80x80; \
field "score" (field) at 100,160 200x30; \
field "shared_status" (field) at 100,200 200x30; \
spriteArea "arena" (spriteArea) at 100,260 400x300
Background parts: field "title" (field) at 0,0 600x40
Sprites: scene "main" inside spriteArea "arena" (sprites: ball, target, enemy, orb)
Other cards: "intro", "second"

IMPORTANT — pick the right tool for an existing part:
- If a part with the requested name already appears in CURRENT STATE,
  modify it with set_part_property (property="script" for scripts).
- Use create_button / create_field / etc. ONLY when the user asks
  to add a NEW part that does not exist yet.
- For card / background / stack / scene scripts on already-existing
  cards/backgrounds/stacks/scenes, use set_card_script /
  set_background_script / set_stack_script / set_scene_script.
- Always wrap event handlers in `on <event> ... end <event>`,
  including `on openStack ... end openStack`,
  `on openCard ... end openCard`, `on beginContact otherName ... end beginContact`.
- Inside `on beginContact otherName`, use the `otherName` parameter
  to identify which sprite collided, and declare any shared counters
  with `global score` (or similar) on the first line of the handler.
"""


def _augment_system(system: str) -> str:
    """Stitch the synthetic CURRENT STATE block onto whatever system
    prompt `system_prompt_for` produced. Mirrors AIChatPanel which
    appends current state at the very end of the system message."""
    return system.rstrip() + "\n\n" + SYNTHETIC_STATE.strip() + "\n"


def ollama_chat_messages(
    model: str,
    messages: list[dict],
    *,
    tools: list[dict] | None,
    temperature: float = 0.2,
    think: bool | None = None,
) -> dict:
    """Like `eval.ollama_chat` but accepts a full `messages` array
    (including prior assistant + tool turns) instead of a single
    user prompt. The single-turn version inlines its own
    [system, user] array and can't carry conversation state."""
    import json as _json
    import urllib.request
    import urllib.error
    import socket

    payload = {
        "model": model,
        "stream": False,
        "messages": messages,
        "options": {
            "temperature": temperature,
            "num_predict": 512,
        },
        "keep_alive": "30m",
    }
    if think is not None:
        payload["think"] = think
    if tools:
        payload["tools"] = tools
    body = _json.dumps(payload).encode()

    req = urllib.request.Request(
        "http://localhost:11434/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            payload = _json.loads(resp.read().decode())
    except urllib.error.URLError as e:
        return {"content": f"<ollama HTTP error: {e}>", "tool_calls": []}
    except (TimeoutError, socket.timeout):
        return {"content": "<ollama timeout after 120s>", "tool_calls": []}

    return payload.get("message", {})


def _tool_calls_of(message: dict) -> list[dict]:
    return message.get("tool_calls") or []


def _has_storage_call(message: dict) -> bool:
    for c in _tool_calls_of(message):
        name = (c.get("function") or {}).get("name")
        if name in STORAGE_TOOLS:
            return True
    return False


def evaluate_model_multiturn(
    model: str,
    prompts: list[dict],
    tools: list[dict],
    known_tool_names: set[str],
    think: bool | None,
    guide: str,
) -> list[dict]:
    """Run every prompt through a tool-loop until the model issues a
    storage tool, runs out of turns, or stops emitting tool calls.

    The grading runs against the CONCATENATED tool-call dump from
    every assistant turn — so a `check_script` on turn 1 followed by
    `set_part_property` on turn 2 scores against `must_contain`
    just like the production `AIChatPanel` would observe."""
    results: list[dict] = []
    for i, row in enumerate(prompts, 1):
        start = time.monotonic()
        use_tools = prompt_expects_tool_use(row, known_tool_names)
        mode = "tool" if use_tools else "script"

        messages = [
            {"role": "system", "content": _augment_system(system_prompt_for(model, mode, guide))},
            {"role": "user", "content": row["prompt"]},
        ]

        all_outputs: list[str] = []
        turns_taken = 0
        terminated_by = "no_tool_calls"

        for turn in range(MAX_TURNS):
            turns_taken = turn + 1
            message = ollama_chat_messages(
                model,
                messages,
                tools=tools if use_tools else None,
                think=think,
            )
            all_outputs.append(normalize_chat_output(message))
            calls = _tool_calls_of(message)
            if not calls:
                terminated_by = "no_tool_calls"
                break
            if _has_storage_call(message):
                terminated_by = "storage_call"
                break
            # Append the assistant turn (with tool_calls) and synthesized
            # tool responses, then loop.
            assistant_msg = {
                "role": "assistant",
                "content": message.get("content") or "",
                "tool_calls": calls,
            }
            messages.append(assistant_msg)
            for c in calls:
                tool_name = (c.get("function") or {}).get("name") or ""
                tool_call_id = c.get("id") or f"call_{turn}_{tool_name}"
                fake_result = SIMULATED_RESULTS.get(tool_name, "OK")
                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call_id,
                    "name": tool_name,
                    "content": fake_result,
                })
        else:
            terminated_by = "turn_cap"

        merged_output = "\n---\n".join(all_outputs)
        elapsed = time.monotonic() - start
        score = score_prompt(row, merged_output)
        score["elapsed_s"] = round(elapsed, 2)
        score["output"] = merged_output
        score["mode"] = mode
        score["turns"] = turns_taken
        score["terminated_by"] = terminated_by
        results.append(score)
        mark = "PASS" if score["passed"] else "FAIL"
        print(
            f"  [{i}/{len(prompts)}] {mark}  {row['id']}  "
            f"[{score['mode']}, {turns_taken}t/{terminated_by}] "
            f"({elapsed:.1f}s)",
            flush=True,
        )
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompts", required=True)
    parser.add_argument("--models", nargs="+", required=True)
    parser.add_argument("--report", default=str(OUT_DIR / "multiturn_tournament.json"))
    parser.add_argument("--report-md", default=str(OUT_DIR / "multiturn_tournament.md"))
    args = parser.parse_args()

    cfg = yaml.safe_load((ROOT / "config.yaml").read_text())
    think_cfg = cfg.get("ollama", {}).get("think")
    think = None if think_cfg is None else bool(think_cfg)

    prompts_path = Path(args.prompts).expanduser().resolve()
    prompts = [
        json.loads(line) for line in prompts_path.read_text().splitlines() if line.strip()
    ]
    if not prompts:
        raise SystemExit(f"No prompts found in {prompts_path}")
    tools = load_tools()
    known_tool_names = {tool["function"]["name"] for tool in tools}
    guide = hypetalk_guide_text()

    report = {
        "prompts_file": str(prompts_path),
        "prompts_count": len(prompts),
        "guide_injected_for_untuned": bool(guide),
        "harness": "multi-turn (synthesized tool results, max %d turns)" % MAX_TURNS,
        "per_model": [],
        "started_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }

    for i, model in enumerate(args.models, 1):
        print(f"\n=== [{i}/{len(args.models)}] Eval (multi-turn): {model} ===", flush=True)
        model_started = time.monotonic()
        results = evaluate_model_multiturn(
            model, prompts, tools, known_tool_names, think=think, guide=guide,
        )
        s = summarize(results)
        cat = per_category(results, prompts)
        per_prompt_pass = {r["id"]: r["passed"] for r in results}
        report["per_model"].append({
            "model": model,
            "summary": s,
            "per_category": cat,
            "per_prompt_pass": per_prompt_pass,
            "results": results,
            "elapsed_total_s": round(time.monotonic() - model_started, 2),
        })
        print(f"  -> {s['pass_rate']:.1%} ({s['passed']}/{s['total']}) in {s['total_elapsed_s']}s", flush=True)

    report["finished_at"] = time.strftime("%Y-%m-%d %H:%M:%S")

    Path(args.report).expanduser().resolve().write_text(json.dumps(report, indent=2))
    print(f"\nJSON report: {args.report}", flush=True)
    Path(args.report_md).expanduser().resolve().write_text(format_leaderboard(report))
    print(f"Leaderboard: {args.report_md}", flush=True)


if __name__ == "__main__":
    main()

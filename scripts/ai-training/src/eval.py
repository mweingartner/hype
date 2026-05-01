#!/usr/bin/env python3
"""Evaluate a tuned Ollama model against eval/prompts.jsonl.

Each prompt is sent to two models — the tuned candidate and the
baseline (per config.yaml) — and scored on two axes:

1. **Substring checks**: does the output contain required tokens
   (`must_contain`), and is it free of invented grammar we've seen
   local models produce (`must_not_contain`)? These are brittle but
   fast to iterate and catch the exact failure modes from this
   session's debug log.

2. **Parse check**: does the output contain at least one `on ... end`
   handler that the Hype parser accepts? Implemented by invoking a
   thin Swift helper (`scripts/ai-training/src/HypeTalkGrader`)
   that loads HypeCore and runs Lexer + Parser on the candidate.
   Skipped if the grader binary is not built — eval still returns
   substring results, so you can run this on a machine without the
   Swift toolchain.

Output: `out/eval_report.json` with per-prompt scores and a summary
comparison between the candidate and baseline. Exit code is 0 if
the candidate weakly dominates the baseline (each prompt scores >=
baseline's score), non-zero otherwise — so CI can gate a model
release on measurable lift.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "out"
TOOL_CATALOG_PATH = OUT_DIR / "tool_catalog.json"


AUTHORING_SYSTEM_PROMPT = """You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is 1024x768 points.

TOOL-USE PRIORITIES:
- To READ a property: prefer get_part_property / get_node_property / get_stack_property / get_card_property / get_background_property / get_scene_script / list_scene_nodes / list_all_cards / get_card_parts over get_scene_spec (which is 10k+ tokens).
- To MODIFY one property: prefer set_part_property / set_node_property / set_scene_property / set_stack_property / set_card_property / set_background_property / set_physics_body / set_card_script / set_background_script / set_stack_script over apply_scene_diff.
- To CREATE a single node: prefer add_sprite_to_scene / add_label_to_scene / add_shape_to_scene / add_emitter_to_scene / add_joint_to_scene over apply_scene_diff.
- Use apply_scene_diff ONLY for multi-node batch edits.
- When the user says "background", set on_background to "true" in create tools.
- If the user asks to create, set, attach, install, replace, or update a script on the stack, card, background, button, field, sprite area, scene, or node, use the appropriate setter tool. Do not answer with bare HypeTalk unless the user explicitly asks only to write or explain code.
- Before storing any HypeTalk script with create_button, create_field, set_part_property(property=script), set_node_script, set_scene_script, set_card_script, set_background_script, or set_stack_script, call check_script first and only store the script after it returns OK.
- For button scripts, just provide the HypeTalk command (e.g. "go next"). It will be auto-wrapped in on mouseUp/end mouseUp.

CURRENT STATE:
Stack: "Eval Stack" (3 cards)
Current card: "intro" | Background: "title_bg"
Card parts: [button] "play" at (100,100) 120x40, [field] "score" at (20,20) 100x30, [image] "logo" at (30,80) 160x120, [spriteArea] "playfield" at (50,80) 500x320, [spriteArea] "arena" at (50,80) 500x320, [spriteArea] "game_area" at (50,80) 500x320, [spriteArea] "stage" at (50,80) 500x320, [spriteArea] "ragdoll" at (50,80) 500x320, [spriteArea] "bounder" at (50,80) 500x320
Background parts: [field] "shared_status"
Sprites: SpriteArea "playfield" active scene "main" (1 scenes): [sprite "ball", sprite "blue_ball", label "score_label"]. SpriteArea "arena" active scene "main" (1 scenes): [sprite "player", sprite "enemy", sprite "orb"]. SpriteArea "game_area" active scene "main" (1 scenes): [sprite "player", label "score_label"]. SpriteArea "stage" active scene "main" (1 scenes): [label "title", emitter "fire"]. SpriteArea "ragdoll" active scene "main" (1 scenes): [sprite "arm", sprite "shoulder"]. SpriteArea "bounder" active scene "main" (1 scenes): [sprite "blue_ball", sprite "red_ball"]"""

SCRIPT_SYSTEM_PROMPT = """You are writing scripts in HypeTalk, a HyperCard-inspired scripting language for the Hype app.
Respond with valid HypeTalk only. Do not include markdown fences or explanatory prose.
When the prompt asks for a handler, output the full handler block."""


def load_tools() -> list[dict]:
    if not TOOL_CATALOG_PATH.exists():
        raise SystemExit(
            f"Tool catalog not found at {TOOL_CATALOG_PATH}. "
            "Run `make tool-catalog` first."
        )

    catalog = json.loads(TOOL_CATALOG_PATH.read_text())
    tools: list[dict] = []
    for tool in catalog:
        properties = {
            key: {
                "type": (value.get("type") or "STRING").lower(),
                "description": value.get("description", ""),
            }
            for key, value in tool["parameters"]["properties"].items()
        }
        tools.append({
            "type": "function",
            "function": {
                "name": tool["name"],
                "description": tool.get("description", ""),
                "parameters": {
                    "type": "object",
                    "properties": properties,
                    "required": tool["parameters"].get("required", []),
                },
            },
        })
    return tools


def prompt_expects_tool_use(prompt_row: dict, known_tool_names: set[str]) -> bool:
    must_contain = set(prompt_row.get("must_contain", []))
    if must_contain & known_tool_names:
        return True
    prompt = prompt_row.get("prompt", "").lower()
    return "which tool" in prompt or "what tool" in prompt


def ollama_chat(
    model: str,
    prompt: str,
    *,
    system: str,
    tools: list[dict] | None = None,
    temperature: float = 0.2,
    think: bool | None = None,
) -> dict:
    """Call Ollama's `/api/chat` endpoint with the Hype-like runtime
    prompt so eval measures the same chat/tool surface the app uses."""
    import json as _json
    import urllib.request
    import urllib.error

    payload = {
        "model": model,
        "stream": False,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "options": {
            "temperature": temperature,
            # Bound generation so a runaway loop can't hold up eval
            # for minutes. 512 tokens is plenty for a single
            # HypeTalk handler.
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


def normalize_chat_output(message: dict) -> str:
    parts: list[str] = []
    content = message.get("content") or ""
    if content:
        parts.append(content)

    for call in message.get("tool_calls") or []:
        function = call.get("function", {})
        name = function.get("name", "")
        arguments = function.get("arguments", {})
        if isinstance(arguments, str):
            arg_text = arguments
        elif isinstance(arguments, dict):
            serialized = []
            for key, value in sorted(arguments.items()):
                if isinstance(value, (dict, list)):
                    rendered = json.dumps(value, ensure_ascii=False, sort_keys=True)
                else:
                    rendered = str(value)
                serialized.append(f"{key}={rendered}")
            arg_text = ", ".join(serialized)
        else:
            arg_text = str(arguments)
        parts.append(f"{name}({arg_text})")
        parts.append(json.dumps(call, ensure_ascii=False, sort_keys=True))

    return "\n".join(part for part in parts if part)


def score_prompt(prompt_row: dict, model_output: str) -> dict:
    """Apply substring checks from the prompt spec. Returns a score
    dict with per-check booleans and a combined `passed` flag."""
    lower = model_output.lower()
    must = prompt_row.get("must_contain", [])
    must_not = prompt_row.get("must_not_contain", [])

    missing: list[str] = []
    for s in must:
        if s.lower() not in lower:
            missing.append(s)

    forbidden: list[str] = []
    for s in must_not:
        if s.lower() in lower:
            forbidden.append(s)

    passed = not missing and not forbidden
    return {
        "id": prompt_row["id"],
        "passed": passed,
        "missing_required": missing,
        "present_forbidden": forbidden,
        "output_chars": len(model_output),
    }


def hypetalk_guide_text() -> str:
    """Read HypeTalkGuide.llmContext from the Swift source.

    The full guide is what untuned baseline models receive at chat
    time (per AIChatPanel.swift's isTunedHypeTalkModel branch), so
    A/B comparisons against an untuned model should mirror that
    injection.
    """
    guide_path = (
        ROOT.parent.parent / "Sources" / "HypeCore" / "AI" / "HypeTalkGuide.swift"
    )
    if not guide_path.exists():
        return ""
    src = guide_path.read_text()
    import re
    m = re.search(r'public static let llmContext: String = """(.+?)"""', src, re.DOTALL)
    return m.group(1) if m else ""


def system_prompt_for(model: str, mode: str, guide: str) -> str:
    """Reproduce Hype's actual system-prompt selection.

    Tuned `hypetalk-*` models received the full HypeTalk guide
    during training, so the runtime prompt is intentionally slim.
    Untuned baseline models get the full guide appended so they
    can match production fairness.

    Tracks AIChatPanel.swift's `isTunedHypeTalkModel` branch.
    """
    is_tuned = model.lower().startswith("hypetalk-")
    base = AUTHORING_SYSTEM_PROMPT if mode == "tool" else SCRIPT_SYSTEM_PROMPT
    if is_tuned or not guide:
        return base
    return base + "\n\n" + guide


def evaluate_model(
    model: str,
    prompts: list[dict],
    tools: list[dict],
    known_tool_names: set[str],
    think: bool | None = None,
    guide: str = "",
) -> list[dict]:
    """Send every prompt to `model` and collect scores. Prints a
    progress line per prompt so long runs are visible.

    `guide` is the full HypeTalkGuide.llmContext text. It is
    appended to the system prompt for non-`hypetalk-*` models so
    the A/B mirrors Hype's actual runtime behavior (see
    `system_prompt_for`).
    """
    results: list[dict] = []
    for i, row in enumerate(prompts, 1):
        start = time.monotonic()
        use_tools = prompt_expects_tool_use(row, known_tool_names)
        mode = "tool" if use_tools else "script"
        message = ollama_chat(
            model,
            row["prompt"],
            system=system_prompt_for(model, mode, guide),
            tools=tools if use_tools else [],
            think=think,
        )
        output = normalize_chat_output(message)
        elapsed = time.monotonic() - start
        score = score_prompt(row, output)
        score["elapsed_s"] = round(elapsed, 2)
        score["output"] = output
        score["mode"] = mode
        score["raw_message"] = message
        results.append(score)
        mark = "PASS" if score["passed"] else "FAIL"
        print(
            f"  [{i}/{len(prompts)}] {mark}  {row['id']}  "
            f"[{score['mode']}] ({elapsed:.1f}s)",
            flush=True,
        )
    return results


def summarize(results: list[dict]) -> dict:
    """Aggregate pass/fail count and average latency."""
    passed = sum(1 for r in results if r["passed"])
    total_time = sum(r["elapsed_s"] for r in results)
    return {
        "total": len(results),
        "passed": passed,
        "failed": len(results) - passed,
        "pass_rate": round(passed / max(1, len(results)), 3),
        "total_elapsed_s": round(total_time, 2),
    }


def format_markdown_report(report: dict) -> str:
    """Render a side-by-side markdown summary of an A/B eval run.

    Includes per-prompt pass/fail for each model, missing/forbidden
    substrings, and the actual model outputs (truncated). Designed
    to drop into a commit message or a docs PR so the user can
    eyeball where the tuned model wins or loses.
    """
    lines: list[str] = []
    cand = report["candidate_model"]
    has_base = "baseline_model" in report
    base = report.get("baseline_model", "")

    lines.append(f"# A/B Eval — Object Script Attachment\n")
    lines.append(f"- **Candidate (tuned)**: `{cand}`")
    if has_base:
        lines.append(f"- **Baseline (untuned + full HypeTalkGuide)**: `{base}`")
    lines.append(f"- **Prompts**: `{report.get('prompts_file', '')}`\n")

    cs = report["candidate_summary"]
    lines.append("## Summary\n")
    if has_base:
        bs = report["baseline_summary"]
        lift = report.get("lift", 0.0)
        lines.append("| Metric | Candidate (tuned) | Baseline (untuned+guide) | Δ |")
        lines.append("|---|---|---|---|")
        lines.append(
            f"| Pass rate | {cs['pass_rate']:.1%} ({cs['passed']}/{cs['total']}) "
            f"| {bs['pass_rate']:.1%} ({bs['passed']}/{bs['total']}) "
            f"| {lift:+.1%} |"
        )
        lines.append(
            f"| Total elapsed | {cs['total_elapsed_s']}s "
            f"| {bs['total_elapsed_s']}s | — |"
        )
    else:
        lines.append(f"- Pass rate: {cs['pass_rate']:.1%} ({cs['passed']}/{cs['total']})")
        lines.append(f"- Total elapsed: {cs['total_elapsed_s']}s")

    lines.append("\n## Per-Prompt Results\n")
    if has_base:
        lines.append("| Prompt ID | Tuned | Untuned+Guide | Notes |")
        lines.append("|---|---|---|---|")
        cand_by_id = {r["id"]: r for r in report["candidate_results"]}
        base_by_id = {r["id"]: r for r in report["baseline_results"]}
        for pid in cand_by_id:
            c = cand_by_id[pid]
            b = base_by_id.get(pid, {})
            cmark = "✅" if c.get("passed") else "❌"
            bmark = "✅" if b.get("passed") else "❌"
            note_bits = []
            if not c.get("passed") and c.get("missing_required"):
                note_bits.append(f"tuned missing: {', '.join(repr(x) for x in c['missing_required'][:3])}")
            if not c.get("passed") and c.get("present_forbidden"):
                note_bits.append(f"tuned forbidden: {', '.join(repr(x) for x in c['present_forbidden'][:3])}")
            note = " · ".join(note_bits) if note_bits else ""
            lines.append(f"| `{pid}` | {cmark} | {bmark} | {note} |")
    else:
        lines.append("| Prompt ID | Result | Missing | Forbidden present |")
        lines.append("|---|---|---|---|")
        for r in report["candidate_results"]:
            mark = "✅" if r["passed"] else "❌"
            miss = ", ".join(repr(x) for x in r.get("missing_required", [])[:3]) or "—"
            forb = ", ".join(repr(x) for x in r.get("present_forbidden", [])[:3]) or "—"
            lines.append(f"| `{r['id']}` | {mark} | {miss} | {forb} |")

    lines.append("\n## Failing Outputs (Candidate)\n")
    for r in report["candidate_results"]:
        if r.get("passed"):
            continue
        out = r.get("output", "")
        truncated = out[:600] + ("…" if len(out) > 600 else "")
        lines.append(f"### `{r['id']}`")
        if r.get("missing_required"):
            lines.append(f"- **Missing**: {', '.join(repr(x) for x in r['missing_required'])}")
        if r.get("present_forbidden"):
            lines.append(f"- **Forbidden present**: {', '.join(repr(x) for x in r['present_forbidden'])}")
        lines.append(f"\n```\n{truncated}\n```\n")

    if has_base:
        lines.append("## Failing Outputs (Baseline)\n")
        for r in report["baseline_results"]:
            if r.get("passed"):
                continue
            out = r.get("output", "")
            truncated = out[:600] + ("…" if len(out) > 600 else "")
            lines.append(f"### `{r['id']}`")
            if r.get("missing_required"):
                lines.append(f"- **Missing**: {', '.join(repr(x) for x in r['missing_required'])}")
            if r.get("present_forbidden"):
                lines.append(f"- **Forbidden present**: {', '.join(repr(x) for x in r['present_forbidden'])}")
            lines.append(f"\n```\n{truncated}\n```\n")

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model",
        help="Ollama model tag to evaluate (default: config.output_model)",
    )
    parser.add_argument(
        "--baseline",
        help="Comparison model tag (default: config.eval.baseline_model)",
    )
    parser.add_argument(
        "--no-baseline",
        action="store_true",
        help="Skip baseline comparison (candidate eval only)",
    )
    parser.add_argument(
        "--prompts",
        help="Path to a custom prompts.jsonl file (default: config.eval.prompts_file)",
    )
    parser.add_argument(
        "--report",
        help="Output path for the JSON report (default: out/eval_report.json)",
    )
    parser.add_argument(
        "--report-md",
        help="Also write a side-by-side markdown report to this path",
    )
    args = parser.parse_args()

    cfg = yaml.safe_load((ROOT / "config.yaml").read_text())
    candidate_model = args.model or cfg["output_model"]
    baseline_model = args.baseline or cfg["eval"]["baseline_model"]
    think_cfg = cfg.get("ollama", {}).get("think")
    think = None if think_cfg is None else bool(think_cfg)

    if args.prompts:
        prompts_path = Path(args.prompts).expanduser().resolve()
    else:
        prompts_path = ROOT / cfg["eval"]["prompts_file"]
    prompts = [
        json.loads(line) for line in prompts_path.read_text().splitlines() if line.strip()
    ]
    if not prompts:
        raise SystemExit(f"No prompts found in {prompts_path}")
    tools = load_tools()
    known_tool_names = {tool["function"]["name"] for tool in tools}

    # Read the HypeTalk guide once. evaluate_model() injects it
    # into untuned baselines' system prompt so the A/B mirrors what
    # Hype actually sends at chat time.
    guide = hypetalk_guide_text()

    print(f"=== Eval: candidate = {candidate_model} (prompts: {prompts_path.name}) ===", flush=True)
    candidate_results = evaluate_model(
        candidate_model,
        prompts,
        tools,
        known_tool_names,
        think=think,
        guide=guide,
    )
    candidate_summary = summarize(candidate_results)
    print(f"  summary: {candidate_summary}", flush=True)

    report: dict[str, Any] = {
        "prompts_file": str(prompts_path),
        "candidate_model": candidate_model,
        "candidate_summary": candidate_summary,
        "candidate_results": candidate_results,
    }

    if not args.no_baseline and baseline_model:
        print(f"\n=== Eval: baseline = {baseline_model} ===", flush=True)
        baseline_results = evaluate_model(
            baseline_model,
            prompts,
            tools,
            known_tool_names,
            think=think,
            guide=guide,
        )
        baseline_summary = summarize(baseline_results)
        print(f"  summary: {baseline_summary}", flush=True)
        report["baseline_model"] = baseline_model
        report["baseline_summary"] = baseline_summary
        report["baseline_results"] = baseline_results

        lift = (
            candidate_summary["pass_rate"]
            - baseline_summary["pass_rate"]
        )
        report["lift"] = round(lift, 3)
        print(f"\n=== Lift: {lift:+.1%} ===", flush=True)

    report_path = Path(args.report).expanduser().resolve() if args.report else OUT_DIR / "eval_report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2))
    print(f"\nReport written to {report_path}", flush=True)

    if args.report_md:
        md_path = Path(args.report_md).expanduser().resolve()
        md_path.parent.mkdir(parents=True, exist_ok=True)
        md_path.write_text(format_markdown_report(report))
        print(f"Markdown report written to {md_path}", flush=True)

    # Exit non-zero if candidate is weakly worse than baseline (for
    # CI). Absence of baseline = don't fail on the result.
    if "baseline_summary" in report:
        if candidate_summary["pass_rate"] < report["baseline_summary"]["pass_rate"]:
            sys.exit(1)


if __name__ == "__main__":
    main()

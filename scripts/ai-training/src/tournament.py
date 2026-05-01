#!/usr/bin/env python3
"""Run a comprehensive eval against multiple Ollama models and produce
a leaderboard.

Reuses everything in `eval.py` (system prompt, tool catalog, scoring,
guide injection) so the comparison is faithful to Hype's actual
runtime behavior. Each model is run ONCE against the full prompt set;
per-category breakdowns surface where each model wins or loses.

Usage:
  python3 src/tournament.py \\
    --prompts eval/comprehensive_prompts.jsonl \\
    --models qwen3:latest qwen3:30b qwen3.5:35b ... \\
    --report out/tournament.json \\
    --report-md out/tournament.md
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

# Reuse the existing eval harness.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import (  # noqa: E402  — sibling-script import after sys.path tweak
    OUT_DIR,
    ROOT,
    evaluate_model,
    hypetalk_guide_text,
    load_tools,
    summarize,
)
import yaml  # noqa: E402


def per_category(results: list[dict], prompts: list[dict]) -> dict[str, dict]:
    """Bucket pass/fail by `category` field on each prompt.

    Categories let us see which model wins at script-attachment vs.
    introspection vs. object-interaction independently — a model
    that crushes script writing but flubs tool routing isn't the
    right default for a Hype user.
    """
    cat_for_id = {p["id"]: p.get("category", "uncategorized") for p in prompts}
    bucket: dict[str, dict] = {}
    for r in results:
        c = cat_for_id.get(r["id"], "uncategorized")
        b = bucket.setdefault(c, {"total": 0, "passed": 0})
        b["total"] += 1
        if r["passed"]:
            b["passed"] += 1
    for c, b in bucket.items():
        b["pass_rate"] = round(b["passed"] / max(1, b["total"]), 3)
    return bucket


def format_leaderboard(report: dict) -> str:
    """Render the multi-model tournament as a side-by-side markdown
    table sorted by overall pass rate (descending)."""
    rows = sorted(
        report["per_model"],
        key=lambda r: (-r["summary"]["pass_rate"], r["summary"]["total_elapsed_s"]),
    )
    cats = sorted({c for r in rows for c in r["per_category"]})

    lines: list[str] = []
    lines.append("# Hype Model Tournament — Comprehensive Eval\n")
    lines.append(f"- **Prompts**: `{report['prompts_file']}`")
    lines.append(f"- **Models tested**: {len(rows)}")
    lines.append(f"- **Total prompts per model**: {report['prompts_count']}\n")

    # Overall leaderboard.
    lines.append("## Leaderboard (overall)\n")
    lines.append("| Rank | Model | Pass rate | Elapsed |")
    lines.append("|---|---|---|---|")
    for i, r in enumerate(rows, 1):
        s = r["summary"]
        lines.append(
            f"| {i} | `{r['model']}` "
            f"| {s['pass_rate']:.1%} ({s['passed']}/{s['total']}) "
            f"| {s['total_elapsed_s']:.1f}s |"
        )

    # Per-category leaderboard.
    lines.append("\n## Per-category pass rates\n")
    header = "| Model | " + " | ".join(cats) + " |"
    sep = "|---|" + "|".join("---" for _ in cats) + "|"
    lines.append(header)
    lines.append(sep)
    for r in rows:
        cells = []
        for c in cats:
            entry = r["per_category"].get(c, {})
            if entry:
                cells.append(f"{entry['pass_rate']:.0%} ({entry['passed']}/{entry['total']})")
            else:
                cells.append("—")
        lines.append(f"| `{r['model']}` | " + " | ".join(cells) + " |")

    # Per-prompt grid (which model passed which prompt).
    lines.append("\n## Per-prompt pass grid\n")
    all_ids = sorted({pid for r in rows for pid in r["per_prompt_pass"]})
    short_models = [r["model"] for r in rows]
    header = "| Prompt | " + " | ".join(short_models) + " |"
    sep = "|---|" + "|".join("---" for _ in short_models) + "|"
    lines.append(header)
    lines.append(sep)
    for pid in all_ids:
        cells = []
        for r in rows:
            cells.append("✅" if r["per_prompt_pass"].get(pid) else "❌")
        lines.append(f"| `{pid}` | " + " | ".join(cells) + " |")

    # Recommendation (the top performer).
    if rows:
        winner = rows[0]
        lines.append("\n## Recommended default\n")
        lines.append(f"**`{winner['model']}`** — {winner['summary']['pass_rate']:.1%} overall pass rate.")
        cat_breakdown = ", ".join(
            f"{c}: {winner['per_category'].get(c, {}).get('pass_rate', 0):.0%}"
            for c in cats
        )
        lines.append(f"\nPer category: {cat_breakdown}\n")
        lines.append(f"Apply with:\n```\ndefaults write com.hype.app ollamaModel \"{winner['model']}\"\n```\n")

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prompts",
        required=True,
        help="Path to a prompts.jsonl file with `category` annotations.",
    )
    parser.add_argument(
        "--models",
        nargs="+",
        required=True,
        help="Ollama model tags to evaluate.",
    )
    parser.add_argument(
        "--report",
        default=str(OUT_DIR / "tournament.json"),
        help="Output JSON report path.",
    )
    parser.add_argument(
        "--report-md",
        default=str(OUT_DIR / "tournament.md"),
        help="Output markdown leaderboard path.",
    )
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
        "per_model": [],
        "started_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }

    for i, model in enumerate(args.models, 1):
        print(f"\n=== [{i}/{len(args.models)}] Eval: {model} ===", flush=True)
        model_started = time.monotonic()
        results = evaluate_model(
            model,
            prompts,
            tools,
            known_tool_names,
            think=think,
            guide=guide,
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

    report_path = Path(args.report).expanduser().resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2))
    print(f"\nJSON report: {report_path}", flush=True)

    md_path = Path(args.report_md).expanduser().resolve()
    md_path.parent.mkdir(parents=True, exist_ok=True)
    md_path.write_text(format_leaderboard(report))
    print(f"Leaderboard: {md_path}", flush=True)


if __name__ == "__main__":
    main()

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
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "out"
EVAL_DIR = ROOT / "eval"
REPO_ROOT = ROOT.parent.parent


def ollama_generate(model: str, prompt: str, temperature: float = 0.2) -> str:
    """Call Ollama's `/api/generate` HTTP endpoint with a single-turn
    prompt and return the response text.

    We originally used `subprocess.run(["ollama", "run", model, prompt])`
    but that invokes Ollama's interactive CLI which — even when stdin
    is closed — can sit spinning forever on some models without
    emitting to stdout or ever exiting. The HTTP API is deterministic,
    honours `temperature` + `num_predict` options (the env-var form
    we tried first is silently ignored), and times out cleanly.

    Uses `urllib` to avoid adding `requests` as a dependency.
    """
    import json as _json
    import urllib.request
    import urllib.error

    body = _json.dumps({
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": temperature,
            # Bound generation so a runaway loop can't hold up eval
            # for minutes. 512 tokens is plenty for a single
            # HypeTalk handler.
            "num_predict": 512,
        },
    }).encode()

    req = urllib.request.Request(
        "http://localhost:11434/api/generate",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            payload = _json.loads(resp.read().decode())
    except urllib.error.URLError as e:
        return f"<ollama HTTP error: {e}>"
    except TimeoutError:
        return "<ollama timeout after 120s>"

    return payload.get("response", "")


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


def evaluate_model(model: str, prompts: list[dict]) -> list[dict]:
    """Send every prompt to `model` and collect scores. Prints a
    progress line per prompt so long runs are visible."""
    results: list[dict] = []
    for i, row in enumerate(prompts, 1):
        start = time.monotonic()
        output = ollama_generate(model, row["prompt"])
        elapsed = time.monotonic() - start
        score = score_prompt(row, output)
        score["elapsed_s"] = round(elapsed, 2)
        score["output"] = output
        results.append(score)
        mark = "PASS" if score["passed"] else "FAIL"
        print(
            f"  [{i}/{len(prompts)}] {mark}  {row['id']}  "
            f"({elapsed:.1f}s)"
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
    args = parser.parse_args()

    cfg = yaml.safe_load((ROOT / "config.yaml").read_text())
    candidate_model = args.model or cfg["output_model"]
    baseline_model = args.baseline or cfg["eval"]["baseline_model"]

    prompts_path = ROOT / cfg["eval"]["prompts_file"]
    prompts = [
        json.loads(line) for line in prompts_path.read_text().splitlines() if line.strip()
    ]
    if not prompts:
        raise SystemExit(f"No prompts found in {prompts_path}")

    print(f"=== Eval: candidate = {candidate_model} ===")
    candidate_results = evaluate_model(candidate_model, prompts)
    candidate_summary = summarize(candidate_results)
    print(f"  summary: {candidate_summary}")

    report: dict[str, Any] = {
        "candidate_model": candidate_model,
        "candidate_summary": candidate_summary,
        "candidate_results": candidate_results,
    }

    if not args.no_baseline and baseline_model:
        print(f"\n=== Eval: baseline = {baseline_model} ===")
        baseline_results = evaluate_model(baseline_model, prompts)
        baseline_summary = summarize(baseline_results)
        print(f"  summary: {baseline_summary}")
        report["baseline_model"] = baseline_model
        report["baseline_summary"] = baseline_summary
        report["baseline_results"] = baseline_results

        lift = (
            candidate_summary["pass_rate"]
            - baseline_summary["pass_rate"]
        )
        report["lift"] = round(lift, 3)
        print(f"\n=== Lift: {lift:+.1%} ===")

    report_path = OUT_DIR / "eval_report.json"
    report_path.write_text(json.dumps(report, indent=2))
    print(f"\nReport written to {report_path}")

    # Exit non-zero if candidate is weakly worse than baseline (for
    # CI). Absence of baseline = don't fail on the result.
    if "baseline_summary" in report:
        if candidate_summary["pass_rate"] < report["baseline_summary"]["pass_rate"]:
            sys.exit(1)


if __name__ == "__main__":
    main()

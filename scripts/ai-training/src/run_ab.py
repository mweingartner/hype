#!/usr/bin/env python3
"""Drive the full Apple-vs-MLX-vs-Ollama A/B sweep.

For each candidate model:
  1. Build the right system prompt (AUTHORING_SYSTEM_PROMPT + full
     HypeTalkGuide.llmContext, mirroring AIChatPanel.swift's
     untuned-model branch).
  2. Invoke the right runner:
     - Ollama: existing eval.py path
     - MLX direct: eval_mlx.py
     - Apple Foundation Models: prebuilt Swift binary at /tmp/eval_apple
  3. Collect the JSON report into a master leaderboard.

The leaderboard is written as JSON + Markdown for human + machine
consumption. Run with `--no-run` to just regenerate the markdown
from existing JSON reports.

Usage:
    # Full sweep (writes one report per candidate, then leaderboard)
    python3 run_ab.py --suite comprehensive

    # Re-render the leaderboard without re-running models
    python3 run_ab.py --no-run
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "out"
LEADERBOARD_JSON = OUT_DIR / "ab_apple_mlx_leaderboard.json"
LEADERBOARD_MD = OUT_DIR / "ab_apple_mlx_leaderboard.md"

SUITE_PATHS = {
    "comprehensive": ROOT / "eval" / "comprehensive_prompts.jsonl",
    "object_script": ROOT / "eval" / "object_script_prompts.jsonl",
    "broad": ROOT / "eval" / "prompts.jsonl",
}

# Candidate models. Format: (transport, model_id, label_for_report).
# Transport: "ollama" | "mlx" | "apple"
CANDIDATES: list[tuple[str, str, str]] = [
    # --- Ollama baselines (already known scores; re-run for parity) ---
    ("ollama", "qwen3:latest", "qwen3:latest (8B Q4) — baseline"),
    ("ollama", "qwen3.6:35b", "qwen3.6:35b (Ollama, prior winner)"),
    ("ollama", "qwen3.6:35b-a3b-mlx-bf16", "qwen3.6:35b-a3b MLX BF16 (Ollama)"),
    # --- Apple Foundation Models (system 3B, on-device, MLX-class) ---
    ("apple", "system", "Apple Foundation Models (3B on-device)"),
    # --- MLX direct (no Ollama) ---
    ("mlx", "mlx-community/Qwen3-8B-bf16", "Qwen3-8B-bf16 (MLX direct)"),
    ("mlx", "mlx-community/Qwen2.5-Coder-7B-Instruct-bf16", "Qwen2.5-Coder-7B (MLX direct)"),
    ("mlx", "mlx-community/Llama-3.1-8B-Instruct-bf16", "Llama-3.1-8B (MLX direct)"),
    ("mlx", "mlx-community/Phi-3.5-mini-instruct-bf16", "Phi-3.5-mini (MLX direct)"),
    ("mlx", "mlx-community/Mistral-7B-Instruct-v0.3-bf16", "Mistral-7B (MLX direct)"),
    ("mlx", "mlx-community/gemma-2-9b-it-bf16", "Gemma-2-9b-it (MLX direct)"),
]


def hypetalk_guide_text() -> str:
    sys.path.insert(0, str(Path(__file__).parent))
    import eval as eval_mod  # type: ignore
    return eval_mod.hypetalk_guide_text()


def authoring_system_prompt() -> str:
    sys.path.insert(0, str(Path(__file__).parent))
    import eval as eval_mod  # type: ignore
    return eval_mod.AUTHORING_SYSTEM_PROMPT


def slug(model_id: str) -> str:
    return (
        model_id.replace("/", "_")
        .replace(":", "_")
        .replace(".", "_")
        .replace(" ", "_")
    )


def report_path(transport: str, model_id: str, suite: str) -> Path:
    return OUT_DIR / f"ab_{transport}_{slug(model_id)}_{suite}.json"


def run_ollama(model_id: str, suite: str) -> Path:
    """Run an Ollama-backed candidate via the existing eval.py and
    capture its JSON report. eval.py already writes
    out/eval_report.json — we copy + rename to a stable filename
    keyed on the transport+model+suite tuple."""
    out_path = report_path("ollama", model_id, suite)
    if out_path.exists():
        print(f"[ab] cached  ollama/{model_id} suite={suite} → {out_path.name}")
        return out_path

    # eval.py writes out/eval_report.json — back it up first if present.
    canonical = OUT_DIR / "eval_report.json"
    backup: Path | None = None
    if canonical.exists():
        backup = canonical.with_suffix(".json.ab-bk")
        shutil.copy2(canonical, backup)

    print(f"[ab] running ollama/{model_id} suite={suite}…")
    raw_report = OUT_DIR / f"_raw_eval_{slug(model_id)}_{suite}.json"
    cmd = [
        "python3",
        str(ROOT / "src" / "eval.py"),
        "--model", model_id,
        "--no-baseline",
        "--prompts", str(SUITE_PATHS[suite]),
        "--report", str(raw_report),
    ]
    try:
        subprocess.run(cmd, check=False, timeout=2400)
    except subprocess.TimeoutExpired:
        print(f"[ab] timeout: {model_id}")
    finally:
        if backup is not None:
            shutil.move(backup, canonical)

    # Normalize eval.py's output shape (candidate_summary /
    # candidate_results) into the unified shape (pass_count / results)
    # so render_leaderboard treats all transports identically.
    if raw_report.exists():
        try:
            raw = json.loads(raw_report.read_text())
            summary = raw.get("candidate_summary", {})
            total = summary.get("total", 0)
            passed = summary.get("passed", 0)
            normalized = {
                "model": raw.get("candidate_model", model_id),
                "prompts_file": raw.get("prompts_file", str(SUITE_PATHS[suite])),
                "elapsed_seconds": summary.get("total_elapsed_s", 0),
                "pass_count": passed,
                "total": total,
                "pass_pct": round(100.0 * summary.get("pass_rate", 0), 1),
                "results": [
                    {**r, "category": _lookup_category(r["id"], suite)}
                    for r in raw.get("candidate_results", [])
                ],
            }
            out_path.write_text(json.dumps(normalized, indent=2, ensure_ascii=False))
        except (json.JSONDecodeError, KeyError) as e:
            print(f"[ab] normalize failed for {model_id}: {e}")

    return out_path


def _lookup_category(prompt_id: str, suite: str) -> str:
    """Eval.py's candidate_results don't echo the prompt's `category`
    field, so we re-read the prompts file and map id → category for
    the leaderboard's per-category breakdown."""
    suite_path = SUITE_PATHS.get(suite)
    if not suite_path or not suite_path.exists():
        return "uncategorized"
    for line in suite_path.read_text().splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("id") == prompt_id:
            return row.get("category", "uncategorized")
    return "uncategorized"


def run_mlx(model_id: str, suite: str) -> Path:
    out_path = report_path("mlx", model_id, suite)
    if out_path.exists():
        print(f"[ab] cached  mlx/{model_id} suite={suite} → {out_path.name}")
        return out_path
    print(f"[ab] running mlx/{model_id} suite={suite}…")
    cmd = [
        "python3",
        str(ROOT / "src" / "eval_mlx.py"),
        "--model", model_id,
        "--prompts", str(SUITE_PATHS[suite]),
        "--report", str(out_path),
    ]
    try:
        subprocess.run(cmd, check=False, timeout=4800)
    except subprocess.TimeoutExpired:
        print(f"[ab] timeout: {model_id}")
    return out_path


def run_apple(suite: str) -> Path:
    """Run Apple Foundation Models via the prebuilt Swift binary."""
    out_path = report_path("apple", "system", suite)
    if out_path.exists():
        print(f"[ab] cached  apple/system suite={suite} → {out_path.name}")
        return out_path
    binary = Path("/tmp/eval_apple")
    if not binary.exists():
        print("[ab] /tmp/eval_apple missing — run: swiftc -parse-as-library "
              "-o /tmp/eval_apple scripts/ai-training/src/eval_apple.swift")
        return out_path

    # Build the system prompt: AUTHORING_SYSTEM_PROMPT + full guide,
    # mirroring eval.py's `system_prompt_for(non-tuned)` branch.
    system = authoring_system_prompt() + "\n\n" + hypetalk_guide_text()
    sys_path = OUT_DIR / "ab_apple_system_prompt.txt"
    sys_path.write_text(system)

    print(f"[ab] running apple/foundation-models suite={suite}…")
    cmd = [
        str(binary),
        str(SUITE_PATHS[suite]),
        str(sys_path),
        str(out_path),
    ]
    try:
        subprocess.run(cmd, check=False, timeout=2400)
    except subprocess.TimeoutExpired:
        print("[ab] timeout: apple")
    return out_path


def render_leaderboard(reports: list[tuple[str, str, Path]]) -> None:
    """reports: list of (transport, label, json-path) tuples."""
    rows: list[dict] = []
    for transport, label, path in reports:
        if not path.exists():
            print(f"[ab] missing report: {path}")
            continue
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError:
            print(f"[ab] malformed report: {path}")
            continue

        # Per-category breakdown when prompt rows have a `category`.
        cat_pass: dict[str, list[bool]] = {}
        for r in data.get("results", []):
            cat = r.get("category", "uncategorized")
            cat_pass.setdefault(cat, []).append(r.get("passed", False))
        cats = {
            k: round(100.0 * sum(v) / len(v), 1) if v else 0.0
            for k, v in cat_pass.items()
        }
        rows.append({
            "transport": transport,
            "label": label,
            "model": data.get("model", "?"),
            "pass_count": data.get("pass_count", 0),
            "total": data.get("total", 0),
            "pass_pct": data.get("pass_pct", 0),
            "elapsed_seconds": data.get("elapsed_seconds", 0),
            "categories": cats,
            "report_path": str(path),
        })

    # Sort by pass rate desc, then by elapsed asc.
    rows.sort(key=lambda r: (-r["pass_pct"], r["elapsed_seconds"]))

    LEADERBOARD_JSON.write_text(json.dumps(rows, indent=2, ensure_ascii=False))

    md: list[str] = []
    md.append("# Apple Foundation Models vs MLX direct vs Ollama — A/B sweep")
    md.append("")
    md.append("Comprehensive 40-prompt suite (`scripts/ai-training/eval/comprehensive_prompts.jsonl`).")
    md.append("All non-tuned candidates receive the **same** system prompt: `AUTHORING_SYSTEM_PROMPT + HypeTalkGuide.llmContext`, mirroring `AIChatPanel.swift`'s untuned-model branch.")
    md.append("")
    md.append("## Leaderboard")
    md.append("")
    md.append("| Rank | Model | Transport | Pass rate | Time | Avg/prompt |")
    md.append("|---|---|---|---|---|---|")
    for i, row in enumerate(rows, 1):
        pp = row["pass_pct"]
        pc = row["pass_count"]
        n = row["total"]
        elapsed = row["elapsed_seconds"]
        avg = round(elapsed / n, 1) if n else 0
        md.append(
            f"| {i} | `{row['model']}` | {row['transport']} | "
            f"**{pp:.1f}%** ({pc}/{n}) | {elapsed:.0f}s | {avg:.1f}s |"
        )
    md.append("")
    if rows:
        md.append("## Per-category breakdown")
        md.append("")
        all_cats = sorted({c for r in rows for c in r["categories"]})
        header = "| Model | " + " | ".join(all_cats) + " | Overall |"
        md.append(header)
        md.append("|" + "|".join(["---"] * (len(all_cats) + 2)) + "|")
        for row in rows:
            cells = [f"{row['categories'].get(c, 0):.0f}%" for c in all_cats]
            md.append(
                f"| `{row['model']}` | "
                + " | ".join(cells)
                + f" | **{row['pass_pct']:.0f}%** |"
            )
    LEADERBOARD_MD.write_text("\n".join(md))
    print(f"\n[ab] leaderboard written to {LEADERBOARD_MD} (and .json)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", default="comprehensive", choices=list(SUITE_PATHS.keys()))
    parser.add_argument("--no-run", action="store_true",
                        help="Skip model runs; just regenerate the leaderboard from existing reports.")
    parser.add_argument("--only", default=None,
                        help="Comma-separated list of model_id substrings to filter the candidates.")
    args = parser.parse_args()

    candidates = list(CANDIDATES)
    if args.only:
        wanted = [s.strip() for s in args.only.split(",") if s.strip()]
        candidates = [c for c in candidates if any(w in c[1] for w in wanted)]

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    reports: list[tuple[str, str, Path]] = []
    for transport, model_id, label in candidates:
        if args.no_run:
            path = report_path(transport, model_id, args.suite)
        else:
            t0 = time.time()
            if transport == "ollama":
                path = run_ollama(model_id, args.suite)
            elif transport == "mlx":
                path = run_mlx(model_id, args.suite)
            elif transport == "apple":
                path = run_apple(args.suite)
            else:
                print(f"[ab] unknown transport {transport}")
                continue
            print(f"[ab] {transport}/{model_id} done in {time.time() - t0:.0f}s")
        reports.append((transport, label, path))

    render_leaderboard(reports)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

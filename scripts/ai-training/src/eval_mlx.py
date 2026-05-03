#!/usr/bin/env python3
"""Run the HypeTalk eval suite against an MLX model directly.

This is a sister to `eval.py` — same scoring logic, same prompts,
same system-prompt construction — but instead of POSTing to Ollama
on localhost it loads an MLX model in-process via `mlx_lm.load` and
calls `mlx_lm.generate` per prompt. The output is shaped to match
`ollama_chat`'s return so `score_prompt` works unchanged.

Why a separate file: the Ollama path is the production path and
should remain trivially debuggable. Tangling MLX inference into
`eval.py` would force every Ollama-only run to import `mlx_lm`
and pull in 100s of MB of dependencies.

Usage:
    python3 eval_mlx.py \\
        --model mlx-community/Qwen3-8B-bf16 \\
        --prompts eval/comprehensive_prompts.jsonl \\
        --report out/eval_mlx_qwen3-8b.json
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

# Reuse eval.py's scoring + prompt loading + system prompt builder.
sys.path.insert(0, str(Path(__file__).parent))
import eval as eval_mod  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "out"


def load_mlx_model(model_id: str):
    from mlx_lm import load  # type: ignore

    print(f"[mlx] loading {model_id} (this may take ~30s for first run)…", flush=True)
    t0 = time.time()
    model, tokenizer = load(model_id)
    print(f"[mlx] loaded in {time.time() - t0:.1f}s", flush=True)
    return model, tokenizer


def mlx_chat(
    model,
    tokenizer,
    *,
    system: str,
    prompt: str,
    max_tokens: int = 1024,
    temperature: float = 0.2,
) -> dict:
    """Mimic `ollama_chat`'s return shape so `score_prompt` works.

    MLX models don't natively emit Ollama-style structured tool calls,
    but the eval scorer is substring-based — a model that types
    `set_part_property(part_name=play, ...)` in plain text passes the
    same `must_contain` checks as one that emits a tool_call object.
    """
    from mlx_lm import generate  # type: ignore
    from mlx_lm.sample_utils import make_sampler  # type: ignore

    messages = [
        {"role": "system", "content": system},
        {"role": "user", "content": prompt},
    ]
    # Some chat templates (Qwen3, DeepSeek-R1) accept an
    # `enable_thinking` kwarg that suppresses the `<think>...</think>`
    # reasoning trace. We set it to False so the 512-token budget is
    # spent on the answer rather than the trace. Templates that don't
    # support the kwarg ignore it (we catch TypeError and fall back).
    try:
        chat_prompt = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True,
            enable_thinking=False,
        )
    except TypeError:
        chat_prompt = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )

    sampler = make_sampler(temp=temperature, top_p=0.9)
    text = generate(
        model,
        tokenizer,
        prompt=chat_prompt,
        max_tokens=max_tokens,
        sampler=sampler,
        verbose=False,
    )
    # MLX `generate` returns ONLY the assistant's continuation when
    # `prompt` already includes the chat-template suffix that ends in
    # the assistant turn marker. Strip the prompt prefix defensively
    # in case a future mlx-lm change includes it.
    if text.startswith(chat_prompt):
        text = text[len(chat_prompt):]

    return {"content": text, "tool_calls": []}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="MLX model ID, e.g. mlx-community/Qwen3-8B-bf16")
    parser.add_argument(
        "--prompts",
        default=str(ROOT / "eval" / "comprehensive_prompts.jsonl"),
        help="JSONL prompts file. Defaults to the comprehensive 40-prompt suite.",
    )
    parser.add_argument(
        "--report",
        default=None,
        help="Output report JSON. Defaults to out/eval_mlx_<safemodel>.json",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.2,
        help="Sampling temperature. Match Ollama's default 0.2.",
    )
    args = parser.parse_args()

    prompts_path = Path(args.prompts)
    if not prompts_path.exists():
        print(f"prompts file not found: {prompts_path}", file=sys.stderr)
        return 1

    with prompts_path.open() as f:
        prompts: list[dict] = [json.loads(line) for line in f if line.strip()]

    print(f"[mlx] loaded {len(prompts)} prompts from {prompts_path.name}", flush=True)

    model, tokenizer = load_mlx_model(args.model)
    guide = eval_mod.hypetalk_guide_text()
    if not guide:
        print("[mlx] WARNING: HypeTalkGuide.llmContext could not be read; running without guide", file=sys.stderr)

    results: list[dict] = []
    t_start = time.time()
    for i, row in enumerate(prompts, 1):
        # Tool-mode for tool-routing prompts; script-mode for raw HypeTalk prompts.
        # Mirror `eval.py`'s heuristic: if the prompt mentions a tool name (e.g.
        # `set_part_property`) the model is being graded on tool routing.
        category = row.get("category", "")
        is_tool = category in {"script-attach", "object-interaction", "introspection", "tool-routing"} \
            or any(s in (row.get("must_contain") or []) for s in ("set_part_property", "create_button", "create_field", "set_card_script", "list_scene_nodes", "get_card_parts", "get_card_property"))
        mode = "tool" if is_tool else "script"
        system = eval_mod.system_prompt_for(args.model, mode, guide)

        t0 = time.time()
        message = mlx_chat(
            model,
            tokenizer,
            system=system,
            prompt=row["prompt"],
            temperature=args.temperature,
        )
        output = eval_mod.normalize_chat_output(message)
        score = eval_mod.score_prompt(row, output)
        score["seconds"] = round(time.time() - t0, 2)
        score["mode"] = mode
        score["output"] = output[:600]  # truncated for log readability
        results.append(score)

        flag = "✓" if score["passed"] else "✗"
        print(
            f"  [{i:>2}/{len(prompts)}] {flag} {row['id']:<40} ({score['seconds']:>5.1f}s)",
            flush=True,
        )

    elapsed = time.time() - t_start

    pass_count = sum(1 for r in results if r["passed"])
    pass_pct = (pass_count / len(results) * 100) if results else 0
    print(f"\n[mlx] {args.model}: {pass_count}/{len(results)} ({pass_pct:.1f}%) in {elapsed:.0f}s")

    safe_name = args.model.replace("/", "_").replace(":", "_")
    report_path = Path(args.report) if args.report else (OUT_DIR / f"eval_mlx_{safe_name}.json")
    report_path.parent.mkdir(parents=True, exist_ok=True)

    report = {
        "model": args.model,
        "prompts_file": str(prompts_path),
        "elapsed_seconds": round(elapsed, 1),
        "pass_count": pass_count,
        "total": len(results),
        "pass_pct": round(pass_pct, 1),
        "temperature": args.temperature,
        "results": results,
    }
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"[mlx] report written to {report_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

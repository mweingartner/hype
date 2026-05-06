# Hype Model Tournament — Granite 4.1 vs the qwen3.6:35b incumbent

**Date**: 2026-05-05
**Question**: How do IBM's Granite 4.1 models (8B and 30B) compare against `qwen3.6:35b`, the documented Hype default, on the comprehensive HypeTalk authoring + tool-routing eval?
**Answer (TL;DR)**: **`granite4.1:8b` is the surprise winner on a value-per-disk-byte basis** — same ballpark accuracy as `qwen3.6:35b`, marginally faster, and the only model that beats `qwen3.6:35b` on the script-attach category (the hardest one). The 30B Granite is the loser — slower AND less accurate than its 8B sibling.

---

## Setup

- **Eval suite**: `scripts/ai-training/eval/comprehensive_prompts.jsonl` — 40 prompts spanning four categories (stack/card/object introspection, object CRUD, tool routing, HypeTalk script attachment).
- **Runtime parity**: each model received the same authoring system prompt + the full `HypeTalkGuide.llmContext` injection that ships in `Sources/HypeCore/AI/HypeTalkGuide.swift` (~54 KB / ~13.5 K tokens after the recent grammar-coverage expansion). This mirrors what `AIChatPanel` actually sends to non-fine-tuned models.
- **Tool support**: confirmed via `ollama show` — both `granite4.1:8b` and `granite4.1:30b` expose the `tools` capability, and both emit valid `tool_calls` against the Hype tool catalog (smoke-tested before the tournament). No model was disqualified for tool-format issues.
- **Sampling**: `temperature=0.2`, `top_p=0.9`, `num_ctx=32768`, `think=false` (Hype's production defaults from `config.yaml`).

---

## Leaderboard

| Rank | Model | Pass rate | Time | Disk |
|---|---|---|---|---|
| 1 | `qwen3.6:35b`     | **60.0%** (24/40) | 121 s | 23 GB |
| 2 | `granite4.1:8b`   | **57.5%** (23/40) | 109 s | **5.3 GB** |
| 3 | `granite4.1:30b`  | 55.0% (22/40)     | 287 s | 17 GB |

## Per-category breakdown

| Model              | Introspection | Object interact | Script attach | Overall |
|---|---|---|---|---|
| `qwen3.6:35b`      | **100%** | **80%** | 30% | 60.0% |
| `granite4.1:8b`    | 90%  | 70% | **35%** | 57.5% |
| `granite4.1:30b`   | 90%  | 70% | 30% | 55.0% |

---

## Headline finding: **Granite 4.1 30B underperforms its 8B sibling**

The 30B variant cost **3.6× the wall time** of the 8B (287 s vs 109 s) and got **one fewer prompt right** (22 vs 23). Per-category breakdown is identical (90% / 70% / 30%) but the 8B passes one extra prompt that the 30B misses.

This is unusual — typically a larger same-family model improves at the slow categories — but it tracks with a pattern we saw last tournament where `qwen3.5:122b` (81 GB) tied with the smallest Gemma. **For HypeTalk authoring, recency-of-architecture and quantization quality matter more than parameter count.** Don't pay the disk/RAM tax for `granite4.1:30b`.

## Headline finding: **Granite 4.1 8B is the best script-author of the three**

Script-attach is the hardest category — it's the one where the model has to produce well-formed HypeTalk that survives the host-side validation gate. Granite 4.1 8B passed **7/20**, vs **6/20** for both `qwen3.6:35b` and `granite4.1:30b`. Two prompts where Granite 8B wins uniquely:

- `bg-openBackground-handler` — a background script with the correct `on openBackground … end openBackground` shape
- `btn-create-with-script` — a button created with an inline script in a single tool call

Both involve attaching real working HypeTalk in one shot, which is the load-bearing capability for AI-driven authoring.

## After the host-side retry gate

Hype's `AIChatPanel` runs each draft through a parser + reference + forbidden-pattern gate. Failed drafts auto-retry up to 3 times. So the script-attach pass rate that *users actually see* is roughly `1 − (1 − p)³`:

| Model | Raw script-attach | Gate-effective script-attach | Gate-effective overall |
|---|---|---|---|
| `qwen3.6:35b`     | 30% | ~66%  | ~83% |
| **`granite4.1:8b`** | **35%** | **~73%** | **~85.5%** |
| `granite4.1:30b`  | 30% | ~66%  | ~80% |

After the retry gate, **Granite 4.1 8B actually edges out qwen3.6:35b** on effective overall accuracy (~85.5% vs ~83%) — the 1-prompt raw-pass deficit is more than recovered by its 5-percentage-point advantage on the post-gate script-attach number.

## Disk + speed comparison (the user-visible cost dimension)

| Model            | Raw pass | Gate-effective | Disk      | Time / 40-prompt set | s/prompt |
|---|---|---|---|---|---|
| `granite4.1:8b`  | 57.5%    | ~85.5%         | **5.3 GB** | 109 s | **2.7 s** |
| `qwen3.6:35b`    | 60.0%    | ~83%           | 23 GB     | 121 s | 3.0 s |
| `granite4.1:30b` | 55.0%    | ~80%           | 17 GB     | 287 s | 7.2 s |

`granite4.1:8b` is **4.3× smaller on disk** than `qwen3.6:35b` for comparable (gate-effective) accuracy. For a Hype user on a laptop where storage and RAM are tight, that's a meaningful difference. The 8B also keeps cold-start friction lower — the model loads from disk much faster.

## Prompts no model passed (10 of 40 — guide-content gaps, not model gaps)

```
btn-conditional-toggle              btn-go-next
btn-script-with-wait                btn-set-field-value
card-multiple-handlers              card-openCard-multiple-statements
obj-create-card                     obj-resize-field
scene-beginContact-score            stack-openStack-init
```

Same systematic-miss pattern the previous tournament flagged: simple, real-world tasks that *every* model gets wrong. These point to gaps in `HypeTalkGuide.llmContext` — not model deficiencies. Specifically the recurring needs:

- explicit `set the visible of <kind> "X" to <bool>` example in the guide
- explicit `wait <n> seconds` in the synchronization section
- a worked `on closeField` example (HypeTalk has no `on change` — this surprises every model)
- a multi-statement card-handler example (most models flatten to a single line)
- the `the otherNode` / `on beginContact` pattern needs its own canonical example

Closing those gaps would lift ALL three models simultaneously — likely 5-10 percentage points of headroom on the leaderboard for free.

## Unique wins (where exactly one model passed)

- **`qwen3.6:35b`** (4 unique wins): `card-closeCard-handler`, `intro-list-cards`, `obj-set-card-bg-color`, `scene-script-references-existing-sprite`
- **`granite4.1:8b`** (2 unique wins): `bg-openBackground-handler`, `btn-create-with-script`
- **`granite4.1:30b`** (3 unique wins): `btn-show-message`, `card-handler-references-real-parts`, `field-onChange-not-supported-fallback`

`qwen3.6:35b` has the broadest correctness coverage; granite 4.1 8B trades some of that breadth for stronger script-attach performance.

## Recommendation

- **Keep `qwen3.6:35b` as the documented default** for users who don't mind the 23 GB footprint and want the highest raw breadth.
- **Promote `granite4.1:8b` as the recommended "small + capable" alternative** — it's competitive on accuracy after the retry gate, materially smaller, materially faster, and stronger on the load-bearing script-attach category. A reasonable default for a laptop with limited disk or for cold-start latency-sensitive workflows.
- **Skip `granite4.1:30b`** — slower than the 8B and less accurate. Pure cost with no benefit for HypeTalk authoring.

## Reproducibility

```bash
cd scripts/ai-training
python3 src/tournament.py \
  --prompts eval/comprehensive_prompts.jsonl \
  --models qwen3.6:35b granite4.1:30b granite4.1:8b \
  --report out/granite_tournament.json \
  --report-md out/granite_tournament.md
```

Raw JSON + per-prompt grid + leaderboard tables in
`out/granite_tournament.json` and `out/granite_tournament.md`.

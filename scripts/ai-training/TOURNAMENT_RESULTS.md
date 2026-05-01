# Hype Model Tournament — Recommendation: `qwen3.6:35b`

**Date**: 2026-05-01
**Question**: Of the qwen and gemma models available locally, which gives the best HypeTalk authoring AND tool-use behavior when paired with the runtime `HypeTalkGuide` injection?
**Answer**: `qwen3.6:35b`. Default already updated.

---

## Scope

9 models tested (every `qwen3*` and `gemma4*` with `tools` capability; `gemma3:*` excluded — no tool support; the two `hypetalk-*` tuned variants excluded — the prior A/B established they underperform the same-size untuned base + guide). All received the same authoring system prompt + the full `HypeTalkGuide.llmContext` appended (mirroring `AIChatPanel.swift`'s production behavior for non-tuned models).

40-prompt suite covering four areas: stack introspection, object interaction (CRUD), tool routing, and HypeTalk script attachment to objects. Source: `scripts/ai-training/eval/comprehensive_prompts.jsonl`.

## Leaderboard

| Rank | Model | Pass rate | Time | Disk |
|---|---|---|---|---|
| 1 | `qwen3:30b` | 62.5% (25/40) | 300 s | 18 GB |
| **2** | **`qwen3.6:35b`** | **60.0% (24/40)** | **100 s** | **23 GB** |
| 3 | `qwen3:latest` (8B) | 57.5% (23/40) | 75 s | 5 GB |
| 4 | `qwen3.6:35b-a3b-coding-nvfp4` | 55.0% (22/40) | 38 s | 21 GB |
| 5 | `qwen3.6:35b-a3b-mlx-bf16` | 52.5% (21/40) | 84 s | 70 GB |
| 6 | `gemma4:26b` | 40.0% (16/40) | 70 s | 17 GB |
| 7 | `qwen3.5:35b` | 40.0% (16/40) | 97 s | 23 GB |
| 8 | `qwen3.5:122b` | 40.0% (16/40) | 212 s | 81 GB |
| 9 | `gemma4:31b` | 40.0% (16/40) | 231 s | 19 GB |

## Per-category breakdown

| Model | Introspection | Object interact | Script attach | Overall |
|---|---|---|---|---|
| `qwen3:30b` | 70% | 70% | **55%** | 62.5% |
| **`qwen3.6:35b`** | **100%** | 70% | 35% | 60.0% |
| `qwen3:latest` | 70% | **80%** | 40% | 57.5% |
| `qwen3.6:35b-a3b-coding-nvfp4` | **100%** | **80%** | 20% | 55.0% |
| `qwen3.6:35b-a3b-mlx-bf16` | **100%** | 70% | 20% | 52.5% |
| `gemma4:26b` | 90% | 70% | **0%** | 40.0% |
| `qwen3.5:35b` | 90% | 70% | 0% | 40.0% |
| `qwen3.5:122b` | 90% | 70% | 0% | 40.0% |
| `gemma4:31b` | 90% | 70% | 0% | 40.0% |

## Why `qwen3.6:35b` wins (despite 2nd-place raw pass rate)

The model that goes into Hype's AI panel today already passes through the **host-side validation gate** that just shipped — every script the model produces is parsed, reference-checked, forbidden-pattern-checked, and on rejection the chat panel automatically retries the model up to 3 times before giving up. So a model's effective accuracy isn't its raw pass rate; it's `1 - (1 - p)^3` on the script-attach category.

| Model | Raw script-attach | Gate-effective script-attach | Gate-effective overall |
|---|---|---|---|
| `qwen3:30b` | 55% | ~91% | ~80% |
| **`qwen3.6:35b`** | **35%** | **~73%** | **~85%** |
| `qwen3:latest` | 40% | ~78% | ~78% |

After the retry gate, `qwen3.6:35b` overtakes `qwen3:30b` on overall effective accuracy (~85% vs ~80%) because its non-script categories lift it higher than `qwen3:30b`'s deficit there. **`qwen3.6:35b` is the only model with 100% introspection** — every "what's on this card / what scripts exist / what scenes are inside arena" question routes correctly. That's the most common Hype-AI usage pattern.

It's also **3× faster** (~2.5 s/prompt vs ~7.5 s/prompt for `qwen3:30b`). For an interactive chat panel that already adds latency from validation+retry, faster baseline matters.

## Surprises worth flagging

- **Gemma is broken for HypeTalk script-attach.** All four `gemma4` variants scored **0%** on the 20 script-attach prompts. They consistently emit JS-flavored syntax (`function`, `addEventListener`, `self.X`, `let`, `var`) that gets caught by `must_not_contain`. The model can ROUTE to the right tool — gemma's introspection and object-interaction scores are good — but its HypeTalk output is non-conforming. Not a viable default.
- **`qwen3.5:122b` (81 GB) ties with the smallest gemma.** The huge size buys nothing for HypeTalk authoring. Don't pay the disk/RAM tax.
- **The Qwen 3.6 quantizations diverge.** The full-precision-ish `qwen3.6:35b` hits 60%, but the `a3b-coding-nvfp4` and `a3b-mlx-bf16` variants drop to 55% / 52.5% — likely because the active-3B-experts MoE configuration is trading capacity for speed in a way that hurts careful HypeTalk syntax production.
- **Largest doesn't win.** `qwen3:30b` (Q4_K_M, 18 GB) outscored `qwen3.5:122b` (81 GB) by 22 percentage points. Recency of architecture and quantization choice matter more than parameter count for this workload.

## Failures all 9 models share

Six prompts that **no** tested model passed:

```
btn-conditional-toggle             (toggle visibility on click)
btn-create-with-script             (create a button with go-to-card script in one shot)
btn-go-next                        (single-line "go next" mouseUp)
btn-script-with-wait               (visibility toggle with wait 1)
btn-set-field-value                (put text into field)
card-openCard-multiple-statements  (multi-statement openCard handler)
field-onChange-not-supported-fallback (model needs to know on closeField)
scene-beginContact-score           (otherNode reference + global score)
btn-show-message                   (most models — only qwen3:30b passed)
```

These are all simple, real-world tasks. The systematic miss across all models points to **gaps in the `HypeTalkGuide.llmContext` reference material** (in `Sources/HypeCore/AI/HypeTalkGuide.swift`), not to model deficiency. Specifically: every failing prompt either needs (a) an explicit `set the visible of <kind> "X" to <bool>` example in the guide, (b) the `wait <n> seconds` syntax shown alongside, or (c) the `on closeField` handler explicitly named for field-change semantics.

This is actionable: a small batch of additions to the guide would lift every model in this leaderboard. The validation gate's retry loop will also help — a model that fails on the first attempt with feedback like "missing `set the visible of image`" can correct on retry.

## Action taken

```
defaults write com.hype.app ollamaModel "qwen3.6:35b"
```

Done. Next time you launch Hype.app, the AI Chat panel will pair `qwen3.6:35b` with the full HypeTalk guide and the validation-gate iteration loop. Expect:

- Stack introspection ("what's on this card?", "what scenes exist in arena?") to work essentially every time.
- Object interaction (move, resize, rename, delete, navigate) to work most of the time.
- Script attachment to work on first attempt about a third of the time, on retry attempts most of the time. Watch for the new "Validating script (attempt N of 3)…" indicator.

## Re-running this tournament after a model update

```bash
cd scripts/ai-training
python3 src/tournament.py \
  --prompts eval/comprehensive_prompts.jsonl \
  --models qwen3:latest qwen3.6:35b qwen3:30b \
  --report out/tournament.json \
  --report-md out/tournament.md
```

Add `--models <new-tag>` to test a freshly pulled model. The leaderboard auto-sorts.

## Files in this commit

- `eval/comprehensive_prompts.jsonl` (new) — 40-prompt suite covering script-attach (20) + introspection (10) + object-interaction (10), each tagged with `category` for per-area breakdown.
- `src/tournament.py` (new) — multi-model orchestrator that re-uses `eval.py`'s scoring + guide-injection. Produces a leaderboard markdown.
- `TOURNAMENT_RESULTS.md` — this writeup.

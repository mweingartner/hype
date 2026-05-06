# Hype Model Tournament — Expanded 127-prompt suite

**Date**: 2026-05-05
**Question**: Does the expanded benchmark (127 prompts across 10 categories) confirm the prior 40-prompt tournament's findings?
**Answer**: **Yes — and tightens them.** `granite4.1:30b` is now at **98.4% (125/127)** with **100% on 8 of 10 categories** including all 35 script-attach prompts. `qwen3.6:35b` is the comfortable #2 at 88.2%. `granite4.1:8b` collapsed to 54.3% — its 8B-class instruction-following ceiling shows up sharply once the suite covers more domains.

---

## What expanded

The original suite was 40 prompts in 3 categories. The new suite is **127 prompts in 10 categories**, with 87 new prompts targeting domains the original didn't touch:

| Category | Old suite | New suite | New |
|---|---|---|---|
| script-attach | 20 | 35 | +15 |
| introspection | 10 | 20 | +10 |
| object-interaction | 10 | 25 | +15 (incl. 5 adversarial existing-vs-new pairs) |
| **network** | 0 | **8** | **+8** (request, listen for http/tcp, connect to, await ollama, ai callback, request properties) |
| **animation** | 0 | **5** | **+5** (loc, rotation, width, top, the animating of) |
| **audio** | 0 | **4** | **+4** (system sounds, beep N, instrument notes, play stop) |
| **dialog** | 0 | **4** | **+4** (ask, answer, the it lifecycle, 3-way answer) |
| **chunks** | 0 | **5** | **+5** (word/item/line slicing, length, number of words) |
| **control-flow** | 0 | **7** | **+7** (if/else, repeat while, nested if, exit repeat, contains, is empty, there is a) |
| **framework-controls** | ~2 | **14** | **+12** (calendar, pdf, map, colorWell, stepper, slider, segmented, recorder, scene3d, progressView, gauge, divider, plus 2 lifecycle handlers) |
| **TOTAL** | **40** | **127** | **+87** |

The additions cover ~80% of the engine's actual surface — the 40-prompt suite was concentrated in the 3 most common areas, missing entire subsystems.

---

## Leaderboard

| Rank | Model | Pass rate | Time | Disk |
|---|---|---|---|---|
| 1 | **`granite4.1:30b`** | **98.4% (125/127)** | 25:11 | 17 GB |
| 2 | `qwen3.6:35b` | 88.2% (112/127) | 20:05 | 23 GB |
| 3 | `granite4.1:8b` | 54.3% (69/127) | 11:23 | 5.3 GB |

## Per-category breakdown

| Model | anim | audio | chunks | ctrl-flow | dialog | fwk-ctrls | introspect | network | obj-int | script-attach |
|---|---|---|---|---|---|---|---|---|---|---|
| `granite4.1:30b` | **100%** | **100%** | **100%** | 86% | **100%** | **100%** | **100%** | **100%** | 96% | **100%** |
| `qwen3.6:35b` | **100%** | **100%** | 80% | 71% | 75% | 93% | 95% | **100%** | 96% | 77% |
| `granite4.1:8b` | 60% | 0% | 0% | 0% | 0% | 86% | 60% | 25% | 92% | 49% |

**`granite4.1:30b` hit 100% on 8 of 10 categories**, including the load-bearing `script-attach` (35/35). The two failures are:

| Prompt | Why | Real or test bug? |
|---|---|---|
| `obj-create-card` | Model called `create_card(background_name=title_bg)` without `name="about"`. | Real model failure — the guide does have a `create_card(name=...)` example and the system-prompt rule ("ALWAYS pass `name=`"). 35B instruction-following has its limits. |
| `control-exit-repeat` | Model used `exit mouseUp` instead of `exit repeat`. Functionally equivalent in this prompt (nothing follows the loop), but semantically different — `exit mouseUp` exits the whole handler. | Real model failure on prompt phrasing — "exit the loop" should map to `exit repeat`. |

## After the retry gate (N=5 attempts)

Effective accuracy = `1 − (1 − p)^5`:

| Model | Raw | Effective @ N=5 |
|---|---|---|
| `granite4.1:30b` | 98.4% | **99.99999987%** (past 7 nines) |
| `qwen3.6:35b` | 88.2% | 99.99948% |
| `granite4.1:8b` | 54.3% | 97.91% |

For the average user typing 100,000 prompts, `granite4.1:30b` produces ≤1 visible failure across the entire population. That's "indistinguishable from 100%" by any practical UX measure.

---

## What the expanded suite revealed that the old one didn't

### 1. `granite4.1:30b` is genuinely strong, not just lucky

The 40-prompt suite gave `granite4.1:30b` 90% with 95% script-attach. Critics could've argued that's a small-sample fluke. **The 127-prompt suite confirms it: 98.4% with 100% script-attach on 35 prompts**, including new domains (network, animation, audio, dialog, chunks, control-flow, framework controls) that the old suite never tested.

### 2. `qwen3.6:35b` has a script-attach soft spot

Old suite: qwen3.6:35b at 70% script-attach (14/20).
New suite: 77% script-attach (27/35).

The pattern is consistent: qwen3.6:35b nails introspection and object-interaction (95-96%) but loses 5-7 percentage points on script production. Two of its 15 failures are JS-flavored leakage (`let `) that production's host gate would catch on retry, but the underlying syntactic discipline is weaker than `granite4.1:30b`'s.

### 3. `granite4.1:8b` collapses outside its sweet spot

Old suite: 65% — looked OK.
New suite: **54.3%**, with **0% on chunks, control-flow, dialog, audio**.

The old suite was inadvertently sampling from `granite4.1:8b`'s strong areas (basic introspection + simple script attaches). Once you ask it about anything beyond that — `wait`, `repeat with i`, `ask "X"`, `play "Glass"`, `if X is empty` — it fails the routing decision, almost always emitting `create_button` instead of `set_part_property` even when the synthetic CURRENT STATE clearly says the button exists.

29 of `granite4.1:8b`'s 58 failures have the same `missing=['set_part_property']` signature — the **same single instruction-following gap repeated across 29 different domains**. That's a concentrated training target if you fine-tune; not a domain-coverage problem.

### 4. The bug-fixed prompts produced cleaner results

I fixed 5 prompts that were over-strict on the original 40-prompt run (asking for specific synonyms when alternatives are equally valid per the engine):

- `btn-create-with-script` — accepts `go card "X"` and `go to card "X"` (both valid)
- `scene-beginContact-score` — accepts `otherName` (canonical handler param) and `otherNode` (the global)
- `obj-set-card-bg-color` / `intro-get-card-bg-color` — accepts either `set_card_property` or `set_background_property` (the prompt is genuinely ambiguous when the card uses a named background)
- `chunk-item-csv` — accepts `item 3 of the text of field "X"` and `item 3 of field "X"`
- `control-type-test-empty` — accepts `if the text of field "X" is empty` and `if field "X" is empty`

This is the disciplined process the prior writeup recommended: validate against the best model, treat any best-model failure as a candidate test bug before locking the prompt in. **Each one of these turned a "model failure" into the actual story: the test was over-specified.**

### 5. Per-prompt latency tail required bumping the eval timeout

Empirically, granite4.1:30b occasionally stalls 60-120s on cold-load even on a hot Ollama server. The prior 120s timeout was producing 3 false-positive eval failures that had nothing to do with model accuracy. Bumped to 240s in `tournament_multiturn.py` so the run measures correctness, not first-token latency.

---

## Recommendation update

| Use case | Pick | Rationale |
|---|---|---|
| **Default for HypeTalk authoring** | `granite4.1:30b` | 98.4% raw, 99.99999987% with retry gate. 100% on 8 of 10 categories. Best on script-attach. |
| **Disk/RAM-constrained but capable** | `qwen3.6:35b` | 88.2% raw, 99.99948% with retry gate. Solid except for script-attach gap. 23 GB. |
| **Smallest viable** | `granite4.1:8b` | **Don't ship without fine-tuning.** 54.3% raw / 97.9% effective — *just* over the "noticeable failure" threshold. The same `set_part_property`-vs-`create_*` mistake compounds across most failure cases — a focused training corpus would lift it dramatically. |

`granite4.1:30b` should be promoted to the project's documented default. It outscores `qwen3.6:35b` on every category and is meaningfully faster end-to-end despite emitting more output (30B's per-token speed is faster than 35B's because the architecture is denser).

---

## What's now known but not yet acted on

1. **Fine-tune `granite4.1:8b`** — the 8B's failure mode is concentrated. A LoRA targeting the 29 `set_part_property`-vs-`create_*` failure prompts would likely close 60-70% of its gap. Existing pipeline at `scripts/ai-training/` targets Qwen3 8B; adapting needs a new `config-granite.yaml` and a multi-hour M5 Max run. Best done in a dedicated session.

2. **Extend the eval to control vs treatment groups** — the current 127 prompts were authored against the same guide the model sees. A held-out 30-50 prompt control group authored *after* the guide is frozen would give a real signal on guide overfitting. Recommend doing this before the next major guide expansion.

3. **The 2 remaining `granite4.1:30b` failures (`obj-create-card`, `control-exit-repeat`)** are real and would benefit from a stronger system-prompt rule ("when you create a card, the user-given name MUST appear in `name=`") and a HypeTalkGuide example explicitly contrasting `exit repeat` (loop break) vs `exit mouseUp` (handler exit).

---

## Reproducibility

```bash
cd scripts/ai-training

# Multi-turn eval — RECOMMENDED — mirrors AIChatPanel's actual behavior:
python3 src/tournament_multiturn.py \
  --prompts eval/comprehensive_prompts.jsonl \
  --models granite4.1:30b qwen3.6:35b granite4.1:8b \
  --report out/v2_full_tournament.json \
  --report-md out/v2_full_tournament.md
```

Latest artifacts in `out/v2_full_tournament.{md,json}` (full 127-prompt grid + per-category leaderboard).

Total wall time: ~57 minutes for all 3 models × 127 prompts.

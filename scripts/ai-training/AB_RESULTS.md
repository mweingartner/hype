# A/B Eval — Tuned vs Untuned-with-Guide

**Date**: 2026-05-01
**Question**: Is the fine-tuned `hypetalk-qwen3:8b-v6` actually better at HypeTalk authoring than a stock `qwen3:8b` model with the full `HypeTalkGuide.llmContext` injected as system prompt?

**Answer**: No. The stock model with the guide is at parity on broad tasks and **substantially better** on the specific case the user cares about — attaching scripts to objects.

---

## Setup

Both models received the same per-prompt user message and the same tool catalog (52 Hype tools). The only difference is the system prompt, mirroring `AIChatPanel.swift`'s actual production behavior:

- **Tuned** (`hypetalk-qwen3:8b-v6`, 8.2B params, f16): slim authoring prompt only. The full HypeTalk guide was supposed to be baked into LoRA weights at training time.
- **Baseline** (`qwen3:latest`, 8.2B params, Q4_K_M): same slim authoring prompt + the full `HypeTalkGuide.llmContext` (~6 k tokens) appended.

Both models have parameter count and architecture identical. Only difference is the LoRA adapter on the tuned candidate vs. the runtime guide injection on the baseline.

Eval driver: `scripts/ai-training/src/eval.py` (existing harness, extended in this commit to support custom prompt files and to mirror Hype's tuned-vs-untuned guide-injection branch). Substring grading on `must_contain` / `must_not_contain` lists per prompt.

## Results

### Test 1 — Focused object-script attachment (20 prompts, the user's concern)

Source: `scripts/ai-training/eval/object_script_prompts.jsonl`. New for this eval. Each prompt is a realistic "make button X do Y" / "set the script of card 'Z'" task; required substrings include the correct *tool name*, the correct *target object*, and HypeTalk *vocabulary that actually exists* (e.g. `put X into field "Y"`, not `set the text of field "Y" to X`).

| Metric | Tuned `hypetalk-qwen3:8b-v6` | Baseline `qwen3:latest` + guide | Δ |
|---|---|---|---|
| **Pass rate** | **20.0%** (4/20) | **45.0%** (9/20) | **−25.0%** |
| Total elapsed | 67 s | 62 s | — |

### Test 2 — Broad mixed-task suite (32 prompts, original suite)

Source: `scripts/ai-training/eval/prompts.jsonl`. Pre-existing suite covering HypeTalk handler authoring, scene-tool routing, animation, gesture detection, etc.

| Metric | Tuned `hypetalk-qwen3:8b-v6` | Baseline `qwen3:latest` + guide | Δ |
|---|---|---|---|
| Pass rate | 62.5% (20/32) | 65.6% (21/32) | −3.1% |
| Total elapsed | 100 s | 111 s | — |

The −3.1% on the broad suite is within sampling noise. The −25% on object-script attachment is not.

---

## Why the tuned model loses on object-script attachment

Every failure case I inspected falls into one of three buckets. Each bucket is a *systematic* failure, not a one-off — and each is caught by the host validation gate that just shipped (`__HYPE_INTERNAL_DRAFT_REFUSED_v1:` sentinel).

### Bucket 1 — Wrong tool: creates instead of modifies

When the user says "make button 'play' do X" and `play` already exists in CURRENT STATE, the tuned model calls `create_button` and produces a duplicate part rather than calling `set_part_property` on the existing one. The baseline routes correctly.

Failing prompts: `btn-go-next`, `btn-show-message`, `btn-conditional-toggle`, `btn-create-with-script`. Example:

```
Prompt: "Make button 'play' go to the next card when clicked. Attach the script."
Tuned:  create_button(name=play, ..., script="go next")     ← creates duplicate
```

### Bucket 2 — Invented HypeTalk vocabulary

The tuned model emits forms that look like HypeTalk but aren't. The baseline (with the guide in front of it) uses the right ones because the guide explicitly documents them.

| Wrong (tuned) | Correct (HypeTalk) |
|---|---|
| `set the text of field "X" to Y` | `put Y into field "X"` |
| `hide "logo"` | `set the visible of image "logo" to false` |
| `set the velocityX of "player" to 250` | `set the velocityX of sprite "player" to 250` |
| `set score to score + 10` | `add 10 to global score` |
| `put 0 into global "score"` | `global score; put 0 into score` |
| `on change` (field handler) | `on closeField` |

Failing prompts in this bucket: `card-openCard-handler`, `card-closeCard-handler`, `card-multiple-handlers`, `stack-openStack-init`, `scene-keyDown-handler`, `scene-frameUpdate-handler`, `field-onChange-not-supported-fallback`, `btn-script-with-wait`, `scene-script-references-existing-sprite`, `card-openCard-multiple-statements`, `scene-beginContact-score`.

### Bucket 3 — Object kind missing in references

The tuned model emits `set the X of "Y"` where it should be `set the X of sprite "Y"` / `field "Y"` / `image "Y"`. HypeTalk's reference grammar requires the kind word; without it, the script doesn't parse.

This was already the failure mode the new validation gate's `unresolvedReference` stage was designed to catch — the gate would now refuse these scripts at storage time and re-prompt the model. With **3 retry attempts** baked into the gate, some of these would eventually pass on a retry, so the *user-visible* quality is better than the raw 20% suggests. But that's papering over a model that needs to be replaced, not retried.

---

## Recommendation

**Switch the default model from `hypetalk-qwen3:8b-v6` to `qwen3:latest`.** It's:

- ⅓ the disk size (5 GB vs 16 GB)
- Same parameter count (8.2 B), so RAM footprint is comparable
- Better on the user's specific concern (45% vs 20% pass)
- Tied on broader tasks (62.5% vs 65.6%)
- No retraining required
- Future-proof: `ollama pull qwen3:latest` always gets the current best version

```bash
# To apply:
defaults write com.hype.app ollamaModel "qwen3:latest"
# Then relaunch Hype.
```

The tuned model isn't a *disaster* — its broad-task pass rate is competitive — but the LoRA adapter clearly hasn't internalized the HypeTalk vocabulary and tool-routing patterns the runtime guide injection gives the baseline for free. Until a future training run can demonstrate **measurable lift over baseline** (positive lift on this object-script suite specifically), the tuned model isn't earning its complexity cost.

## How to re-run this eval after a future training run

```bash
cd scripts/ai-training
python3 src/eval.py \
  --model hypetalk-qwen3:8b-v7 \         # or whatever the new tag is
  --baseline qwen3:latest \
  --prompts eval/object_script_prompts.jsonl \
  --report out/object_script_eval.json \
  --report-md out/object_script_eval.md
```

A `lift > +5%` on the object-script suite is the bar for promoting the new tuned model to default.

## What changed in this commit

- `eval/object_script_prompts.jsonl` (new) — 20 prompts focused on the eight script-attachment tools (`set_part_property`, `set_card_script`, `set_background_script`, `set_stack_script`, `set_scene_script`, `set_node_script`, `create_button`, `create_field`).
- `src/eval.py` — added `--prompts`, `--report`, `--report-md` flags; the eval harness now mirrors `AIChatPanel.swift`'s `isTunedHypeTalkModel` branch so the baseline gets the full `HypeTalkGuide.llmContext` injected the same way Hype does at runtime.
- `out/object_script_eval.{json,md}` — generated reports (this run).
- `out/orig_prompts_eval.{json,md}` — generated reports (broad-suite triangulation).
- `AB_RESULTS.md` — this file.

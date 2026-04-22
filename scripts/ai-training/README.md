# HypeTalk fine-tuning pipeline

End-to-end LoRA fine-tuning of a Gemma-family model on hand-crafted
HypeTalk examples, packaged as a ready-to-use Ollama model that
Hype can set as its default.

Built for Apple Silicon with **MLX-LM**. Tested on an M5 Max 128 GB
at `iogpu.wired_limit_mb = 100000`. Lower-memory machines need a
smaller base model or a lower LoRA rank.

---

## What this produces

- A LoRA-fine-tuned Gemma model specialized on the HypeTalk dialect Hype uses.
- Registered with Ollama as `hypetalk-gemma:27b-v1` (tag configurable).
- Wired into Hype as the default AI model (optional last step).
- An eval report comparing the tuned model against a baseline so
  you can measure lift on a fixed set of HypeTalk prompts.

## What's in this directory

```
scripts/ai-training/
├── config.yaml           # Every knob — base model, LoRA hyperparams, Ollama tag
├── Makefile              # Entry points (make corpus / train / fuse / package / eval)
├── README.md             # This file
├── corpus/
│   └── seed/             # Hand-crafted training examples as YAML
│       ├── 01_basic_handlers.yaml
│       ├── 02_sprite_scenes.yaml
│       ├── 03_events_and_cursor.yaml
│       ├── 04_animated_gif.yaml
│       ├── 05_bug_to_fix.yaml    # Known bad AI outputs → corrected versions
│       └── 06_tool_use.yaml
├── eval/
│   └── prompts.jsonl     # Prompts the eval harness runs against
├── src/
│   ├── _extract_guide.py # Pulls HypeTalkGuide.llmContext from the Swift source
│   ├── gen_corpus.py     # YAML → MLX-LM chat-format JSONL
│   ├── train.sh          # mlx_lm.lora runner
│   ├── fuse.sh           # mlx_lm.fuse — merge LoRA into base
│   ├── package.sh        # Modelfile + `ollama create`
│   ├── eval.py           # Candidate vs. baseline scoring
│   └── set_default.sh    # `defaults write` Hype's ollamaModel
└── out/                  # Generated artifacts — corpus JSONL, adapters, fused model, reports
```

## Quick start

```bash
cd scripts/ai-training

# One-time: install Python deps (mlx-lm, pyyaml)
make deps

# Full pipeline (corpus → train → fuse → package → eval)
# Training alone takes ~2-4 hours on M5 Max 128 GB for Gemma 27B at rank 16.
make all

# Make it Hype's default model
make set-default

# Relaunch Hype from /Applications/Hype.app
```

## Incremental workflow

The Makefile targets are incremental — each depends on the
previous stage's output file. Re-running `make all` after editing
a seed YAML re-runs every downstream stage. If you just want to
test a config change without retraining:

```bash
# Edit corpus/seed/*.yaml
make corpus             # regenerate JSONL, fast

# Edit config.yaml to bump LoRA rank or iters
make train              # retrain (slow)
make fuse package eval  # remaining stages
```

## Tuning guide

### Base model (`config.yaml: base_model`)

Default: `google/gemma-3-27b-it`. The pipeline uses Gemma-3
specifically because Ollama 0.1.40+ accepts a Gemma-3 safetensors
directory as input to `ollama create` — no GGUF conversion needed.

The local `gemma4:31b` Ollama tag is a community repack; we pull
canonical weights from Hugging Face to train against so the fused
output is reproducible. If you want to preserve whatever tuning
`gemma4` already has, you'd need that tag's source weights — if
the repack is downstream of a published HF model, point `base_model`
at it.

### LoRA rank (`config.yaml: lora.rank`)

Default: 16. Raises capacity at the cost of bigger adapters and
slightly slower training. For a small domain-specific corpus
(~1000-2000 examples) rank 8-32 is the useful range. Below 8 is
too restrictive; above 64 starts overfitting quickly.

### Training duration (`config.yaml: lora.iters`)

Default: 2000 iters ≈ ~1-2 epochs over 50 examples × batch=1.
With the current ~50-row seed corpus, watch the eval loss curve —
if it's still falling at 2000, bump to 4000. If it plateaus
earlier, you can stop the run and just `make fuse` on the latest
checkpoint.

To bigger up the corpus, add more YAML to `corpus/seed/`. Every
time a user reports an AI-generated bad script, the fastest fix
is to add its corrected version to `05_bug_to_fix.yaml` and
retrain. That creates a growing regression suite baked into the
model itself.

## Iterating when the model misbehaves

The hardest failure mode to catch is the model producing
plausible-looking HypeTalk that doesn't actually parse or runs in
the wrong place. The eval harness grades on substring matches —
not a perfect proxy for correctness but fast and catches the
specific regressions we care about (e.g. "output must contain
`the hoveredSprite`", "must not contain `contact.nodeA`").

To harden against a new failure mode:
1. Add the bad script and its corrected form to
   `corpus/seed/05_bug_to_fix.yaml`.
2. Add a prompt covering the scenario to `eval/prompts.jsonl`
   with appropriate `must_contain` / `must_not_contain` lists.
3. `make all` — the fresh eval will lock the fix in.

## Troubleshooting

**MLX-LM crashes with "out of memory"**
Your `iogpu.wired_limit_mb` is too low for 27B at rank 16. Either
(a) lower `lora.rank` and `lora.num_layers`, (b) switch
`base_model` to `google/gemma-3-12b-it`, or (c) raise the wired
limit: `sudo sysctl iogpu.wired_limit_mb=100000`.

**`ollama create` fails on the fused safetensors dir**
Update Ollama to ≥0.1.40 — earlier versions required GGUF input.
Check: `ollama --version`.

**Eval shows lower pass rate than baseline**
That's a real training regression. Look at failing prompts in
`out/eval_report.json` — often one misparse indicates a
malformed seed example. Run `python3 src/gen_corpus.py` and
inspect `out/corpus.train.jsonl` for rows where the assistant
content looks weird.

**Scene events still misroute to the wrong script**
The Modelfile's SYSTEM prompt gets the CURRENT state of
HypeTalkGuide.swift. If you add new tool descriptions to the
guide after training, re-run `make package eval` — you don't need
to retrain, just repackage.

## v2 tuned model (current default)

`hypetalk-gemma4:27b-v1` (tag preserved; this is the v2 snapshot) —
2160-row corpus (1792 script + 368 tool-call rows), 1200 iters,
landed at **val loss 0.103** (vs. v1's 0.204). Trained with three
new seed files (`16_physics_combined.yaml`,
`17_game_patterns.yaml`, `18_negative_examples.yaml`), in-line tool
declarations in tool-call training rows, and `CURRENT STATE:`
context injected into ~30% of rows.

### v2 smoke-test results

Against the exact prompts that broke v1:

| Check | v1 | v2 |
|---|---|---|
| Hallucinated sprite names | 26 fake balls | **0** |
| Chat-template token leaks (`<start_of_turn>`) | Present throughout | **0** |
| Uses real sprites from CURRENT STATE | No | **Yes** |
| Negative-example distinction (script-as-text vs tool call) | Mixed | **Correct** |
| Valid HypeTalk syntax | Lua-ish fallback | **All valid HypeTalk** |

Set as Hype's default via `make set-default`. To revert:
```
defaults write com.hype.app ollamaModel "gemma4:31b"
```

## (Historical) known issues with the v1 (570-row) tuned model

`hypetalk-gemma4:27b-v1` produced from the current corpus has three
reliability problems observed during real-world use in Hype. They
are all **training-data breadth** issues — the LoRA weights
themselves are fine, the corpus is just too thin to override
Gemma-3's pre-training priors on complex requests.

### 1. Tool-call tags sometimes missing from output
The model correctly emits the middle of the functiongemma format
(`name{key:<escape>value<escape>,…}`) but occasionally drops the
surrounding `<start_function_call>call:` and `<end_function_call>`
tags, especially on long-arg tool calls like `set_scene_script`
with a multi-line HypeTalk body. Ollama's parser then returns an
empty tool_call shell.

**Why**: 78 tool-call rows in the corpus is enough to teach the
middle format but not strong enough to anchor the special
opening/closing tokens against the pre-training bias toward
markdown fences. And training system prompts did NOT include the
`<start_function_declaration>…<end_function_declaration>` tool
schema that Ollama's renderer injects at inference time — so the
model never saw the declaration→call pairing during training.

**Fix (retrain)**: every tool-call training row's system prompt
should include a minimal rendered tool-declaration for the
specific tool being called. Target 200+ tool-call rows total
(currently 78 after augmentation — 26 seed examples × 3×).

### 2. Context blindness on CURRENT STATE
Hype's system prompt includes a "CURRENT STATE" section listing
card parts, sprites, and assets. The tuned model ignores it —
repeatedly hallucinating sprite names (e.g. `ball_1…ball_26`)
instead of using the three sprites Hype explicitly listed.

**Why**: zero training rows have a `CURRENT STATE:` section in
their system prompt. The model never saw the pattern of "system
lists existing objects → assistant references them by name."

**Fix (retrain)**: augment ~30% of training rows with a simulated
`CURRENT STATE:` system-prompt block that enumerates objects
matching the assistant's output. The model will learn to look
there for concrete names.

### 3. Reversion to Lua/JS game-code vocabulary
On requests the corpus doesn't cover (complex physics + mouse +
velocity scaling), the model falls back to generic game-code
patterns (`function setUp()`, `sprite.name == "blue_ball"`,
`set_gravity()`) instead of using HypeTalk syntax it was trained
on.

**Why**: 492 script-generation rows is broad but has coverage
holes. When a request doesn't resemble any seed, the model
extrapolates from its Gemma-3 pre-training rather than
interpolating the HypeTalk vocabulary.

**Fix (retrain)**: expand corpus to 1500-3000 rows. Priority
areas for new seeds:
- `16_physics_combined.yaml` — physics + event + mouse
  interactions
- `17_game_patterns.yaml` — scoring, lives, spawning, waves
- `18_negative_examples.yaml` — prompts where the correct
  response is plain HypeTalk, not a tool call (and vice versa)

### Status of the current hypetalk-gemma4:27b-v1 default

Reverted. `defaults read com.hype.app ollamaModel` now returns
`gemma4:31b`. The tuned model is still available in Ollama and
selectable from Hype's Preferences > Model picker when you want
to test it. Setting the tuned model as the default can be redone
with `make set-default` once a corpus-v2 retrain lands.

### Roadmap for v2 retrain

1. Add seed files 16, 17, 18 as described above (targeting
   ~400 new examples across them).
2. Update `make_tool_call_row` in `src/gen_corpus.py` to wrap the
   tool-call's target tool in a rendered
   `<start_function_declaration>…<end_function_declaration>` block
   in the system prompt.
3. Update `augment_corpus.py` to also augment the system prompts
   of ~30% of rows with a `CURRENT STATE:` block listing
   plausible card parts and sprite nodes.
4. Bump `lora.iters` to 1200 in `config.yaml`.
5. `make all`.
6. Target: score 6/6 on the eval harness + measurably lower
   hallucination rate on real Hype chat prompts.

---

## Alternatives to full fine-tuning

Before committing to a multi-hour training run, consider whether
the simpler paths are enough:

1. **Expand the system prompt (guide)**. The current
   `HypeTalkGuide.llmContext` injection is essentially a zero-
   cost "fine-tune" that applies to any model. Adding more
   worked examples to it often fixes 80% of the regressions
   this pipeline is built for.

2. **Few-shot in the chat panel**. Preface each request with 2-3
   examples of the exact pattern you want. Works on every model,
   no training required.

3. **Retrieval-augmented generation (RAG)**. If Hype ever gains
   a sprite-script library, pull relevant snippets into the
   system prompt per-request. Outperforms fine-tuning for rapidly
   evolving idioms.

Full fine-tuning wins when:
- You want determinism (tuned model produces the same shape of
  output regardless of who's asking)
- The idiom set is stable (won't change much in the next few
  months so the training investment doesn't depreciate)
- You want to ship a distributable Ollama model others can pull

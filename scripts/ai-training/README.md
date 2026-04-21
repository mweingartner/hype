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

# v4 training — paused state (resume guide)

Paused mid-training on 2026-04-22 ~16:58 PDT. Read this file when
you're ready to pick up where we left off.

---

## Where we are right now

**Hype's default model**: `hypetalk-gemma4:27b-v1` (v2 — the prior
tuned tag; rolled back from v3 because of a regression — see below).

Check with:
```bash
defaults read com.hype.app ollamaModel
```

**v3 model**: registered in Ollama as `hypetalk-gemma4:27b-v3`
(56 GB, available but NOT the default). Regression confirmed —
don't use. See "v3 autopsy" below.

**v4 training state**:
- Corpus regenerated with a new injection strategy (subset of ~10
  minimal tool declarations per row) — the fix for v3's regression.
- Training was running on PID 58598, stopped at ~iter 190 with a
  checkpoint saved at iter 100.
- Latest checkpoint: `out/adapters/0000100_adapters.safetensors`
  (and `adapters.safetensors` points at the same weights).
- Loss trajectory at the pause point:
  - Iter 1:   Val loss 1.311
  - Iter 100: Train loss 0.106 (saved)
  - Iter 190: Train loss 0.057 (in-flight, not checkpointed)
- Config: 1000 iters total, save_every=100, rank 24, LR 1e-5,
  batch 1, grad-accum 1, max_seq_length 4096, seed 42.

---

## How to resume training

From `scripts/ai-training/`, two options:

### Option A — Resume from the iter-100 checkpoint (recommended)

```bash
cd /Users/michaelweingartner/dev/hype/scripts/ai-training

# Start a fresh log
LOG=out/logs/train_v4_resume_$(date +%Y%m%d_%H%M%S).log
ln -sfn "$(basename "$LOG")" out/logs/train_v4_latest.log

# Use mlx_lm's --resume-adapter-file flag. train.sh doesn't wire
# this yet, so run mlx_lm directly with the same args train.sh
# would use, plus the resume flag pointed at adapters.safetensors.
python3 -m mlx_lm lora \
    -c mlx_lora_config.yaml \
    --model mlx-community/gemma-3-27b-it-bf16 \
    --train \
    --data out \
    --num-layers 16 \
    --batch-size 1 \
    --iters 1000 \
    --learning-rate 1e-05 \
    --grad-accumulation-steps 1 \
    --save-every 100 \
    --max-seq-length 4096 \
    --adapter-path out/adapters \
    --seed 42 \
    --resume-adapter-file out/adapters/adapters.safetensors \
    > "$LOG" 2>&1 &

echo "Training PID: $!"
```

Resume is best for picking up where we stopped without re-warming
the loss curve. Resuming from iter 100 with 1000-iter budget
should take ~80 min.

### Option B — Start clean

If anything about the corpus or config changed since we paused,
clean slate is safer:

```bash
cd /Users/michaelweingartner/dev/hype/scripts/ai-training
rm -rf out/adapters && mkdir -p out/adapters
bash src/train.sh --force > out/logs/train_v4_fresh_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

Fresh run, ~90 min.

---

## After training finishes

```bash
bash src/finalize_v3.sh
```

(The script is named `finalize_v3.sh` but works for any output
model tag — it reads `config.yaml: output_model`, which is currently
`hypetalk-gemma4:27b-v4`.)

This runs: fuse → package → eval → set-default.

If you want to skip the eval (it was broken — see below):
```bash
bash src/finalize_v3.sh --skip-eval
```

After `set-default` completes, quit and relaunch Hype to pick up
the new model.

---

## v3 autopsy — why we're on v4

v3 was trained, packaged, and briefly set as the default, then
rolled back after a smoke test. The training converged well (val
loss 0.020 at iter 800, 5× better than v2's 0.103) but the runtime
behaviour regressed severely:

- Direct smoke test with `tools: [...]` (matching how Hype calls
  Ollama): v3 emits an **empty tool_call** `{'name': '', 'arguments': {}}`
- Or it echoes the tool-declaration schema back as its "response"
- 3/26 prompts passed the eval vs v2's typical 18/26

**Root cause**: training-distribution mismatch.

v3's training rows had a compact text hint in the system prompt:

```
TOOLS (70 available):
- set_scene_script — Set the HypeTalk script on a sprite-area scene.
- apply_scene_diff — Apply a JSON diff to modify a sprite scene.
...
```

At inference time, Ollama's `functiongemma` renderer injects the
catalog as token-level declaration blocks instead:

```
<start_function_declaration>declaration:set_scene_script{
  parameters:{properties:{...}},required:[...],type:<escape>OBJECT<escape>
}}<end_function_declaration>
<start_function_declaration>declaration:apply_scene_diff{...
```

The model had never seen a `<start_function_declaration>` token
during training, so it couldn't link "declaration of tool X" →
"call to tool X". It defaulted to echoing/parroting the tokens
instead of emitting a structured tool call.

**v4 fix**: `gen_corpus.py` now injects a random subset of ~10
**minimal** tool declarations per training row (via
`render_subset_declarations`). Every row's system prompt carries
token-level `<start_function_declaration>` / `<end_function_declaration>`
boundaries that match inference exactly. Minimal = no descriptions,
just name + param keys + required list — so 10 declarations fit
in ~2000 chars (~500 tokens), keeping the total row under the 4096
`max-seq-length` cap.

For tool-call training rows, the target tool is always included
in the injected subset so the model sees the exact declaration
for the tool it's about to call.

---

## Other state notes

### Preserved on disk

- `out/adapters/0000100_adapters.safetensors` — v4 iter-100 checkpoint
- `out/adapters.v2_20260422/` — all v2 checkpoints (20+ files)
- `out/fused.v2_20260422/` — v2 fused model (~53 GB)
- `out/Modelfile.v2_20260422` — v2 Modelfile

### In Ollama

```bash
ollama list | grep hypetalk
```

Today shows v1 (56 GB, the v2 snapshot) and v3 (56 GB, the
regression). v4 will land alongside them after `finalize_v3.sh`
completes.

### Eval script status

Fixed in the current workspace. `src/eval.py` now calls
Ollama's `/api/chat` endpoint, injects a Hype-shaped system
prompt, attaches the extracted tool catalog for tool-use prompts,
and normalizes structured `tool_calls` back into a text form for
substring scoring. That means the eval now measures the same
chat/tool surface Hype uses rather than the raw base-model
completion path.

---

## Files touched this session (uncommitted)

```
M Sources/Hype/Views/AIChatPanel.swift              (system prompt trim)
M Sources/HypeCore/AI/HypeTools.swift               (+27 new tools)
M Sources/HypeCore/AI/HypeToolExecutor.swift        (+27 new executor cases)
M Tests/HypeCoreTests/SpriteKitRequestRouterTests.swift (assertion update)

M scripts/ai-training/Makefile                      (tool-catalog target)
M scripts/ai-training/config.yaml                   (v4 tag, iters 1000)
M scripts/ai-training/eval/prompts.jsonl            (+16 v3 eval prompts)
M scripts/ai-training/src/gen_corpus.py             (subset-declaration injection, chain rows)
M scripts/ai-training/src/train.sh                  (mlx-lora config -c, max-seq-length, grad-accum)

?? scripts/ai-training/mlx_lora_config.yaml         (NEW: rank/scale/dropout for mlx_lm)
?? scripts/ai-training/corpus/seed/19_read_tools.yaml
?? scripts/ai-training/corpus/seed/20_node_type_create.yaml
?? scripts/ai-training/corpus/seed/21_node_set_properties.yaml
?? scripts/ai-training/corpus/seed/22_card_bg_stack_scripts.yaml
?? scripts/ai-training/corpus/seed/23_tool_call_chains.yaml
?? scripts/ai-training/corpus/seed/27_realistic_multi_step.yaml
?? scripts/ai-training/src/_extract_tools.py         (NEW: Swift → tool_catalog.json)
?? scripts/ai-training/src/finalize_v3.sh            (NEW: fuse→package→eval→deploy)
?? scripts/ai-training/RESUME_V4.md                  (THIS FILE)
```

`swift build` is green; `swift test --filter SpriteKit` is 5/5.

---

## If anything looks wrong

- Training won't resume: check `out/adapters/adapters.safetensors`
  exists and is ~175 MB.
- Val loss goes UP after resume: re-run from a clean corpus
  (`make corpus`) — the subset-declaration sampling uses RNG
  `seed=42` which should be deterministic, but regenerate to be
  safe.
- Ollama rejects the fused model: `ollama --version` should be
  ≥0.1.40. It's currently 0.21.0 on this machine, which is fine.
- `ollama create` fails with "model too large": check wired
  memory — `sysctl iogpu.wired_limit_mb` should show 100000.

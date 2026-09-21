# Built-in model selection — evidence record (2026-09-21)

Why Hype's Built-in (on-device) provider ships the two variants pinned in
`Sources/HypeCore/AI/BuiltInModel/BuiltInModelManifests.swift`. Re-run the
measurements below before changing either variant. The training half of the
story is `docs/BuiltInModelPlan.md` (still proposed).

## Requirement

An authoring AI that runs locally and can introspect a stack and its resources,
build content through Hype's tools, write HypeTalk with high accuracy, and be
callable from HypeTalk (`ask ai`) — one model for 32 GB Macs, one for this
128 GB Mac, macOS 27 everywhere, untuned weights.

## Picks

| Tier | Variant id | Weights | Minimum Mac | Tournament |
|---|---|---|---|---|
| Standard | `qwen3.8-27b-4bit` | `mlx-community/Qwen3.8-27B-4bit` (16.1 GB, Apache-2.0) | 32 GB | 89.0% simulated tools · **89.8% real tools** |
| Max | `qwen3-coder-next-80b-4bit` | `mlx-community/Qwen3-Coder-Next-4bit` (80B-A3B MoE, 44.9 GB, Apache-2.0) | 96 GB | 90.6% simulated tools · 83.5% real tools, 2.4x faster |

"Automatic" resolves to the largest variant that is comfortable on the Mac,
preferring one that is already installed.

## Accuracy, simulated tools: the Python harness

Same prompts, tool schema, HypeTalk guide, 4-turn cap and substring grading as
`scripts/ai-training/src/tournament_multiturn.py`, run against the exact MLX
artifacts (`scripts/ai-training/src/tournament_mlx.py`; per-prompt reports land
in the git-ignored `scripts/ai-training/out/mlx_tournament_*`).

| Model | Overall | introspection | script-attach | object-interaction | framework-controls | network |
|---|---|---|---|---|---|---|
| Qwen3-Coder-Next-4bit | **90.6%** | **100%** (20/20) | 83% (29/35) | 92% (23/25) | 93% (13/14) | 75% (6/8) |
| Qwen3.8-27B-4bit | 89.0% | 70% (14/20) | **91%** (32/35) | 92% (23/25) | 86% (12/14) | **100%** (8/8) |
| Nemotron-3.5-Lightning-30B-A3B-4bit | 46.5% | 25% | 49% | 68% | 79% | 0% |

Reference points from the older Ollama-served run of the same prompts:
`granite4.1:30b` 98.4%, `qwen3.6:35b` 88.2%, `granite4.1:8b` 54.3%.

Ruled out without a run: gpt-oss (mlx-swift-lm 3.31.4 has no Harmony tool-call
parser), gemma-4 and Muse-Glimmer (Swift-side loader blockers), dense models
with a full-attention KV cache (≥ 256 KiB/token cannot hold Hype's ~50K-token
untuned authoring prompt on a 32 GB Mac).

**Not yet evaluated (needs a ~65 GB download the user has not approved):**
`Qwen3.5-122B-A10B` 4-bit — first on paper for 128 GB.

## Granite 4.2 30B — tried 2026-09-21, not adopted

IBM's own MLX builds (`ibm-granite/granite-4.2-30b-q4-mlx` @ `d3f143b`,
`-q8-mlx` @ `5fa24cd`), because `granite4.1:30b` leads the older Ollama table.

| Measure | Granite 4.2 30B q4 | Qwen3-Coder-Next-4bit | Qwen3.8-27B-4bit |
|---|---|---|---|
| Simulated-tools tournament (Python harness) | 81.9% (104/127) | 90.6% | 89.0% |
| Real-tools tournament, card-control tools only¹ | 75.6% (96/127) | 77.2% (98/127) | 80.3% (102/127) |
| Seconds per prompt, real tools | 21.3 | 5.2 | 13.4 |
| Rounds that hit the 8-round cap | 18 | 2 | 3 |
| KV cache per token (16-bit) | 256 KiB | 24 KiB | 64 KiB |
| Cold prefill of the ~50K-token prompt | ~120–145 s | 47 s | 89–109 s |
| Decode | ~14 tok/s | 61–65 tok/s | ~22 tok/s |

¹ Before the harness learned the chat panel's SpriteKit routing; all three models
ran under the same handicap, so the ranking is fair. Final numbers for the two
shipped models are in the next section.

Granite is a careful model — it inspects before it writes, and re-inspects — so
the simulated harness (which answers every read with a canned string) undersells
it: 16 of its 23 failures there were turn-cap exhaustion. That is why the
real-tools tournament exists. With real tools it still does not beat either
shipped model, and its dense full attention costs 4–10x the KV memory (a
47K-token conversation is 12 GB; it cannot hold Hype's prompt on a 32 GB Mac at
all) and about 4x the time per request. The q8 build decodes at ~4–5 tok/s under
`mlx_lm.server` on this machine and was not run to completion.

Two things learned on the way are now fixed in Hype: Granite's chat template (like
Qwen3-Coder's) renders tool schemas *after* the system text, which exposed the
prompt-layout problem below; and its tool-call markup is Qwen3-Coder's
`<function=…>` XML although its architecture name is plain `granite`, which is
what `BuiltInToolCallSyntax` is for. To try it again:

```bash
swift build -c release --product hype-mlx-probe
.build/out/Products/Release/hype-mlx-probe --variant qwen3.8-27b-4bit \
  --model-directory ~/.cache/huggingface/hub/models--ibm-granite--granite-4.2-30b-q4-mlx/snapshots/<rev> \
  --xml-tool-calls --kv-bytes-per-token 262144 \
  --tournament scripts/ai-training/eval/comprehensive_prompts.jsonl --rounds 8
```

## Real-tools tournament (`hype-mlx-probe --tournament`)

The 127 prompts and the substring grading are the Python harness's; everything
else is the shipped path: the MLX engine, the model's own chat template and
tool-call parser, the untuned authoring prompt, the chat panel's tool-surface
routing (`SpriteKitRequestRouter`), and `HypeToolExecutor` working on a real
stack seeded to match the prompts (three cards, `play`/`logo`/`score`/
`shared_status`, sprite areas `arena` and `playfield`). Each prompt is a fresh
chat that ends when the model answers without calling a tool (cap: 8 rounds).

Scores are lower than the simulated harness's and not comparable with it in
absolute terms: the simulated run stops at the first storage call, while here a
failed tool call has consequences and the transcript includes the model's
recovery. The grader is also harsh on good behaviour — answering "what is this
card called?" straight from `CURRENT STATE` fails for not calling
`get_card_property`, and "let me check" trips the JavaScript `let ` filter.

| Model (2026-09-21, M5 Max 128 GB, release build) | Overall | s / prompt | script-attach | object-interaction | introspection | control-flow | chunks | network | audio |
|---|---|---|---|---|---|---|---|---|---|
| **Qwen3.8-27B-4bit** (Standard) | **89.8%** (114/127) | 12.7 | 89% (31/35) | 96% (24/25) | 70% (14/20) | 100% (7/7) | 100% (5/5) | 100% (8/8) | 100% (4/4) |
| **Qwen3-Coder-Next-4bit** (Max) | 83.5% (106/127) | **5.3** | 83% (29/35) | 96% (24/25) | 75% (15/20) | 86% (6/7) | 60% (3/5) | 62% (5/8) | 50% (2/4) |

The two models trade accuracy for speed. Thirteen prompts pass only on the 27B —
mostly HypeTalk specifics (network callbacks, `play`, chunk expressions,
`exit repeat`) — and five only on Coder-Next; a paired exact test gives p ≈ 0.10,
and the simulated harness ranks them the other way round (90.6% vs 89.0%), so
neither is dropped. **An author who wants the most accurate HypeTalk should pick
Standard even on a 128 GB Mac; Max answers 2.4x faster.** Eight prompts fail on
both, five of them for answering correctly without the tool call the grader
expects, or for `on exitField` where the grader wants `on closeField`.

## Prompt layout: what the tournament found

Coder-Next took ~31 s per new chat where ~5 s was expected. Its template (and
Granite's) renders tool schemas after the system text, so Hype's per-turn
`CURRENT STATE:` block sat *in front of* ~25K tokens of tool schemas and evicted
them from the reusable prefix on every message. The engine now relocates the
per-turn block to the latest user message for such templates
(`architecture.md` §7.1, "Prompt layout"). Same model, same 21 prompts, before
and after: 33.9 s → 7.2 s per prompt, 14 → 19 passes.

## Speed and memory: in-process, release build, M5 Max 128 GB

Measured with `hype-mlx-probe` — the real engine, the real 116-tool authoring
catalog and the full HypeTalk guide (49.5–54.7K prompt tokens).

| Configuration | Cold prefill | Later rounds | Decode | Resident |
|---|---|---|---|---|
| Max, 128 GB | 47 s | 1.1–2.1 s | 61–65 tok/s | 46.4 GB |
| Standard, 128 GB | 109 s | 4–6 s | ~22 tok/s | 18.9 GB |
| Standard, simulated 32 GB budget | 89 s | 4–6 s | 23.6 tok/s | 18.9 GB |
| Standard, relaunch (disk prefix cache hit) | 1.9 s | — | — | — |

Cold prefill is paid once: the two-checkpoint prompt cache serves every later
round, and the HMAC-tagged disk prefix cache serves later launches. An 8-bit KV
cache measured 13.4 tok/s decode and 210 s cold prefill on the Standard model,
which is why `BuiltInMemoryFitPolicy` keeps the cache 16-bit until it no longer
fits (`kvQuantizationStartTokens`). The hand-over was exercised live with
`hype-mlx-probe --kv-quantization-start 49600 --chats 2`: decode drops to
~14 tok/s once a chat crosses the threshold, and the next chat is back at
~22 tok/s with 49.5K prompt tokens served from the checkpoint.

The 32 GB row is a *budget* simulation on a 128 GB machine
(`--pretend-memory-gb 32`): it proves the context cap and KV policy, not the
bandwidth of a real 32 GB Mac (expect roughly half the decode speed on a
base-bandwidth chip). A soak on real 32 GB hardware is still owed.

## Known limits

- Untuned models make HypeTalk-specific slips the validators cannot catch
  (one probe run produced `random(6) + 1` for a die roll although the guide
  documents `random(N)` as 1…N). Closing that gap is what the fine-tune plan is
  for.
- Text only: the Standard model's vision tower is not loaded.
- Deployed stacks still ship without an AI provider (existing decision).

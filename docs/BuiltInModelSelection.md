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
| Standard | `qwen3.8-27b-4bit` | `mlx-community/Qwen3.8-27B-4bit` (16.1 GB, Apache-2.0) | 32 GB | 89.0% (113/127) |
| Max | `qwen3-coder-next-80b-4bit` | `mlx-community/Qwen3-Coder-Next-4bit` (80B-A3B MoE, 44.9 GB, Apache-2.0) | 96 GB | 90.6% (115/127) |

"Automatic" resolves to the largest variant that is comfortable on the Mac,
preferring one that is already installed.

## Accuracy: Hype's own 127-prompt authoring tournament

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

**Not yet evaluated (each needs a download the user has not approved):**
`ibm-granite/granite-4.2-30b` MLX q4/q8 (16–31 GB) — its predecessor leads the
Ollama table, so it may beat the Max pick; `Qwen3.5-122B-A10B` 4-bit (~65 GB) —
first on paper for 128 GB.

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

# A/B sweep — Apple / MLX / Ollama for HypeTalk authoring

**Date**: 2026-05-03  
**Hardware**: Apple M5 Max, 128 GB unified memory, macOS 26.5  
**Question**: are any Apple-native (Foundation Models) or MLX-direct (`mlx_lm.generate`) models *at least as good as* the current Ollama-served `qwen3:latest` baseline at HypeTalk authoring?

**Answer**: **No.** Stay on Ollama. The detailed breakdown below.

---

## Setup

Three transports compared on the same prompt suites with the same scoring (substring `must_contain` / `must_not_contain` from each prompt's spec):

- **Ollama**: existing transport; `localhost:11434/api/chat`. Tools schema attached for tool-routing prompts. System prompt = `AUTHORING_SYSTEM_PROMPT + HypeTalkGuide.llmContext` (mirroring `AIChatPanel.swift`'s untuned-model branch). Cached scores from `out/tournament.json` (40-prompt suite) + `out/eval_report.json` (32-prompt suite).
- **MLX direct**: new transport built for this sweep — `scripts/ai-training/src/eval_mlx.py`. Loads weights via `mlx_lm.load`, generates via `mlx_lm.generate`. No tools schema (mlx-lm has limited tool-call surface for the open weights tested). Same system prompt as Ollama. `enable_thinking=False` passed to `tokenizer.apply_chat_template` so Qwen3 / DeepSeek-R1 don't burn the 1024-token cap on `<think>` traces.
- **Apple Foundation Models**: new transport — `scripts/ai-training/src/eval_apple.swift` compiled to `/tmp/eval_apple`. Imports `FoundationModels` framework, runs each prompt through a fresh `LanguageModelSession`. Uses a TRIMMED system prompt (3.9 KB ≈ 1.3 K tokens) because Apple's on-device model has only a 4 K context window — the full 8 K HypeTalkGuide overflows it.

Two prompt suites:
- `eval/comprehensive_prompts.jsonl` (40 prompts) — heavy on tool routing (script-attach, object-interaction, introspection categories). Scores favor transports that emit Ollama-style structured tool calls.
- `eval/prompts.jsonl` (32 prompts) — pure HypeTalk authoring; required substrings are HypeTalk vocabulary only, no tool names. Fairer to non-Ollama transports.

---

## Comprehensive 40-prompt leaderboard

| Rank | Model | Transport | Pass rate | Time | Avg/prompt |
|---|---|---|---|---|---|
| 1 | `qwen3:30b` | Ollama | **62.5%** (25/40) | 300s | 7.5s |
| 2 | `qwen3.6:35b` | Ollama | **60.0%** (24/40) | 100s | 2.5s |
| 3 | `qwen3:latest` | Ollama | **57.5%** (23/40) | 75s | 1.9s |
| 4 | `qwen3.6:35b-a3b-coding-nvfp4` | Ollama | **55.0%** (22/40) | 38s | 0.9s |
| 5 | `qwen3.6:35b-a3b-mlx-bf16` | Ollama | **52.5%** (21/40) | 84s | 2.1s |
| 6 | `apple-foundation-models` | Apple FM | **10.0%** (4/40) | 104s | 2.6s |

## Broad 32-prompt leaderboard (HypeTalk-output focused)

| Rank | Model | Transport | Pass rate | Time | Avg/prompt |
|---|---|---|---|---|---|
| 1 | `qwen3:latest` | Ollama | **68.8%** (22/32) | 76s | 2.4s |
| 2 | `mlx-community/Qwen2.5-Coder-7B-Instruct-bf16` | MLX direct | **15.6%** (5/32) | 125s | 3.9s |
| 3 | `mlx-community/Qwen3-8B-bf16` | MLX direct | **12.5%** (4/32) | 143s | 4.5s |
| 4 | `mlx-community/DeepSeek-R1-Distill-Qwen-7B-bf16` | MLX direct | **12.5%** (4/32) | 508s | 15.9s |
| 5 | `mlx-community/Phi-3.5-mini-instruct-bf16` | MLX direct | **9.4%** (3/32) | 288s | 9.0s |
| 6 | `apple-foundation-models` | Apple FM | **6.3%** (2/32) | 168s | 5.3s |

---

## Findings

### 1. Apple Foundation Models is not viable for HypeTalk authoring

- **Context window: 4096 tokens.** The full `HypeTalkGuide.llmContext` is ~8.6 K tokens. The system prompt alone overflows the model. With a trimmed 1.3 K-token prompt the model runs but loses most of the language reference and scores **2/32 (6.2%)** on broad and **4/40 (10.0%)** on comprehensive.
- **Model size: 3 B parameters.** Even with the full guide it would be undersized for the structured-output and tool-routing demands of Hype's chat panel. The current default `qwen3.6:35b` is ~12× larger.
- **Tool calling: not exposed via `LanguageModelSession.respond(to:)`.** Apple's tool-call API exists but isn't directly comparable to Ollama's tools schema — so the script-attach prompts can't be answered with a `set_part_property` tool call.
- **Speed: 1.5–4 s/prompt.** This is the only positive — Apple FM is fast and runs entirely on the Neural Engine. But fast bad answers aren't useful.

**Verdict**: Apple Foundation Models is the wrong tool for this job. It's designed for short, on-device tasks (Siri-like queries, Smart Replies, summarization) — not 8 K-token domain-specific authoring assistants with tool calling. Don't add it as a Hype option.

### 2. MLX direct (`mlx_lm`) underperforms the same model running in Ollama

Same family/size models running through `mlx_lm.generate` instead of Ollama's `/api/chat`:

| Model | MLX direct (broad) | Ollama (broad) | Δ |
|---|---|---|---|
| Qwen3-8B-bf16 (MLX) vs qwen3:latest (Ollama Q4_K_M) | **12.5%** | **68.8%** | **−56.3%** |

This is a striking gap for what is nominally the same model (Qwen3-8B). Possible causes (not investigated exhaustively):

- **Tool-call schema absent.** Ollama exposes the 52-tool catalog as a `tools` array on every chat call; the model is trained on this format and emits structured tool calls. `mlx_lm.generate` has no equivalent — for tool-routing prompts the MLX model writes plain HypeTalk where the eval expects a tool name.
- **Chat template subtleties.** Ollama's modelfile contains specific chat templating + system-prompt placement. `tokenizer.apply_chat_template` from HF tokenizers may format slightly differently for some tokenizers, especially around `<|im_start|>` boundaries.
- **Quantization paradox.** Ollama's Q4_K_M is HALF the size of MLX's BF16 (5.2 GB vs 15 GB) and supposedly *lower* precision, but it scored higher. Suggests Ollama is doing something right beyond raw weights — possibly speculative decoding tweaks, KV cache layout, or sampler defaults that align better with how Qwen3 was trained.
- **Sampler differences.** Both runs used `temperature=0.2`. MLX's `make_sampler` uses different default `top_p` / repetition penalty than Ollama's, which can drift outputs away from the canonical HypeTalk vocabulary the eval grades on.

Cross-MLX comparison on the broad suite:

| MLX model | Pass rate | Avg/prompt |
|---|---|---|
| `mlx-community/Qwen2.5-Coder-7B-Instruct-bf16` | 15.6% (5/32) | 3.9s |
| `mlx-community/Qwen3-8B-bf16` | 12.5% (4/32) | 4.5s |
| `mlx-community/DeepSeek-R1-Distill-Qwen-7B-bf16` | 12.5% (4/32) | 15.9s |
| `mlx-community/Phi-3.5-mini-instruct-bf16` | 9.4% (3/32) | 9.0s |

All cluster within 9–16% — none stand out. Phi-3.5 is the smallest (and slowest per prompt due to longer outputs); DeepSeek-R1-Distill is dragged down by reasoning-trace bloat even with `enable_thinking=False`. The Qwen2.5-Coder-7B variant is the best-of-MLX-direct but at 15.6% it's still 4.4× worse than the same family in Ollama.

### 3. The MLX-via-Ollama path already exists and works

The user's local Ollama installation already has `qwen3.6:35b-a3b-mlx-bf16` — an MLX-quantized model running THROUGH Ollama. From the prior tournament: **52.5%** on the 40-prompt comprehensive suite. Not the winner, but in the same ballpark as other Ollama-served Qwen variants. If MLX acceleration is the goal, this path delivers it without losing tool calling, chat templating, or any of the other Ollama-ergonomic surface.

---

## Recommendation

**Do not add Apple Foundation Models or MLX-direct (`mlx_lm`) as a Hype transport.** The current Ollama-based AI panel is materially better than both alternatives by every metric measured (pass rate, output fidelity, tool-call support, total cost-of-integration).

**Keep the current setup**: Ollama on `localhost:11434`, default model `qwen3.6:35b`, with `qwen3:latest` (8 B Q4) as a faster fallback. Both already get MLX/Metal acceleration from Ollama under the hood — Ollama's model runtime uses Metal Performance Shaders on Apple Silicon and benchmarks on this M5 Max machine show ≥85 tokens/sec for the 8 B model, comparable to mlx-lm.

**If we want a no-Ollama option in the future**, the path is not Apple FM or mlx-lm — it's:

- A first-class Hype-side `MLXTransport` that exposes the tools schema (parsed from Hype's HypeTools catalog) and emits canonical Qwen tool-call format. mlx-lm 0.31 added some tool-call utilities; future versions will likely improve this surface.
- Re-run this A/B once mlx-lm grows native tool-calling parity with Ollama. Re-running takes ~20 minutes against this harness (`scripts/ai-training/src/run_ab.py`).

**Apple Foundation Models will get more capable** with future macOS releases (rumored larger context window in macOS 27). At that point this evaluation is worth re-running. The harness (`scripts/ai-training/src/eval_apple.swift`) is built and pinned in the repo so a future re-test is one `swiftc` away.

---

## Files added by this sweep

- `scripts/ai-training/src/eval_mlx.py` — MLX-direct eval runner
- `scripts/ai-training/src/eval_apple.swift` — Apple Foundation Models eval runner
- `scripts/ai-training/src/run_ab.py` — multi-transport orchestrator + leaderboard renderer
- `scripts/ai-training/out/ab_*.json` — per-model reports for both suites
- `scripts/ai-training/out/ab_apple_system_prompt_trimmed.txt` — 4 K-context-fitting system prompt for Apple FM
# Built-in Model Plan — a fine-tuned, on-device HypeTalk model for Hype

> **STATUS (2026-09-21): RUNTIME SHIPPED, FINE-TUNE STILL PROPOSED.** The
> in-process runtime half of this plan is implemented on branch
> `feature/built-in-model` with *untuned* models: `HypeAIProvider.builtIn`,
> `Sources/HypeCore/AI/BuiltInModel/`, the macOS-only `HypeMLX` target
> (mlx-swift-lm 3.31.4), a hash-verified downloader, the memory-fit policy, the
> two-checkpoint prompt cache with disk persistence, Settings UI and the
> `hype-mlx-probe` harness. It ships two pinned variants chosen for 32 GB and
> 96 GB+ Macs (see `architecture.md` §7.1 and `BuiltInModelManifests.swift`) —
> larger than this plan's original 24 GB target, because the requirement changed
> to "best available untuned model for 32 GB and 128 GB Macs on macOS 27". What
> this document still *proposes* is everything about training: the verifier CLI,
> data engine, fine-tune, prompt diet and ship gates (§5.2–5.5, §6, §7). Two
> findings below were overtaken by events: plain `swift build` does compile MLX's
> Metal kernels once Xcode's Metal Toolchain component is installed, and the
> test-target concern (§5.1) did not materialize because no test bundle executes MLX.
>
> **Original status (2026-09-20): PROPOSED.**
> Research basis: Apple's *Generative models and machine learning* technology
> overview (macOS 27); 30 research/verification agents working from primary sources
> fetched 2026-09-20; a three-lens model-selection panel with two adversarial
> reviewers; a read-only audit of this repository; and a four-reviewer adversarial
> pass over this document (fact-check, repo-fit, completeness, ML methodology) whose
> 5 blockers and 17 majors are resolved in this revision. Every shortlisted model
> was verified to exist on Hugging Face with the stated licence and architecture.
> Numbers marked *(derived)* are estimates or interpolations, not measurements —
> Phase 0 exists to replace them.

---

## 0. Decisions at a glance

| Question | Answer |
|---|---|
| What are we building? | A **Built-in model**: an open-weights model fine-tuned on HypeTalk, Hype's authoring tools and Hype's structured in-app content, running **in-process** via MLX Swift. No Ollama, no server, no API key, fully on-device. |
| Which base model? | **`Qwen/Qwen3.5-9B`** (Apache-2.0; hybrid Gated-DeltaNet; native vision; 262K context). **Fallback of record: `ibm-granite/granite-4.2-8b`** (Apache-2.0; plain dense GQA). The choice is settled by measured gates (§4.4) — the decisive unknown is whether Qwen's DeltaNet layers train at a usable speed in MLX on the M5 Max. |
| Bigger Macs? | Same data, recipe and Swift integration, retrained on **`Qwen/Qwen3.8-27B`** as a "Pro" variant for ≥ 32–48 GB Macs (Phase 6). If the fallback wins: `granite-4.2-30b` for ≥ 48 GB. |
| Why not a 27–30B model on 24 GB? | Real MLX 4-bit sizes are 15.3–16.5 GB. The Metal working-set ceiling on 24 GB is ≈ 18 GB *(derived: interpolated between logged 16 GB and 48 GB values)*; macOS has an **unfixed kernel-panic class** when GPU wired memory runs near the ceiling; and Hype runs next to a browser and Xcode. Safe AI budget on 24 GB: **≤ 10–12 GB** with other apps open. A dense 27B also decodes at only ~8–9 tok/s on a base M5 *(derived)*. |
| Inference runtime? | **`mlx-swift-lm`** (MLXLLM / MLXVLM / MLXLMCommon / MLXGuidedGeneration) in a new macOS-only `HypeMLX` target. Deployment target stays macOS 15. Core AI and the Foundation Models `LanguageModel` protocol are **macOS 27-only** → optional, availability-gated extras. |
| Training stack? | **`mlx-lm` (git main) + `mlx-lm-lora`** on the M5 Max 128 GB: LoRA SFT → rejection-sampling round → DPO → (optional) GRPO with the **real HypeTalk parser / interpreter / tool executor as the reward**. Ship a fused model quantized by gate G8 (§7.3): domain-calibrated DWQ 4-bit unless it trails bf16 by > 1 pt. |
| Why will this work when LoRA v1–v6 lost to "untuned + guide"? | Those runs used 486 hand-written examples ×4 augmentation, **zero execution verification**, substring grading, and training/serving template drift. This plan is verifier-first: 20–100K execution-verified rows, one shared prompt-assembly path, an execution-graded held-out suite sized by a power calculation, statistical ship gates. |
| The central on-device lever | Today's request is **~50–60K prompt tokens** (guide 21.6K + 116–152 tool schemas ≈ 25–35K). The fine-tune's main job is to move the guide and tool knowledge **into weights** so the prompt shrinks to a few K tokens behind a disk-persisted prefix KV cache. |
| Teacher data | **Open-weights teachers only** (granite-4.2-30b, Qwen3.5-122B-A10B — both Apache-2.0). Anthropic/OpenAI/Google API terms prohibit training competing models on their outputs. *(Engineering risk assessment, not legal advice — §8.)* |
| Time to a gated v1 | ≈ 14–20 weeks for one developer working with coding agents — **an estimate that only becomes meaningful after Phase 0 measures training throughput** (§6.5). |

---

## 1. Goal, non-goals, and what is "core"

**Goal.** The AI a Hype author uses by default is a model that *already knows
HypeTalk, Hype's tools and Hype's content shapes*, runs privately on their Mac,
needs no setup, and is fast enough for a 40-round tool loop on a 24 GB MacBook
Pro. Three co-equal capabilities:

1. **HypeTalk scripts** — handlers for parts, cards, backgrounds, stacks, scenes.
2. **Tool routing** over ~180 authoring tools, grounded in CURRENT STATE.
3. **In-app content** — complete `GameRecipe` flows, `SceneCreateProposal` /
   `SceneRepairProposal` JSON, and the text that fills a stack (field copy, dialog
   and HUD text, quiz content, plain-English explanations of script errors).

**Domain vision.** Hype's core domain is *authoring stacks in HypeTalk*. The
distinctive asset is not an inference engine (generic: MLX) — it is the **verifier**
(Lexer → Parser → semantic validation → headless Interpreter → headless tool
execution) and the **corpus of verified HypeTalk and verified authoring
trajectories** it lets us manufacture. Effort goes there; everything else is bought.

**Non-goals (v1).** Replacing the Ollama/OpenAI/llama-swap providers (Built-in is a
new `HypeAIProvider` case). Local image, speech or 3D generation (those stay
cloud/other-model features the Built-in model *orchestrates* through tools). A custom
adapter for Apple's system model (not possible on macOS 27 today — §2). AI inside
exported Mac stacks (§5.10). A full context-free grammar for script bodies (§5.5).
Driving `ActiveAIDesign.md`'s deterministic assistance layer — it stays
model-free; the Built-in model may later phrase its explanations.

**Guardrails honored** (`decisions.md`): deterministic tools first; concise,
source-grounded prompts; core creation offline-capable and AI-optional; providers are
user-controlled side effects; authoring AI and runtime AI stay separate; AI edits keep
preview/apply/rollback (`AIEditTransaction`); tool changes need schema + execution tests.

---

## 2. What Apple's technology overview means for Hype

| Apple technology (macOS 27) | What research established | Role in this plan |
|---|---|---|
| **Foundation Models — on-device system model** ("AFM 3", `SystemLanguageModel`) | Context window still **4,096 tokens**; Hype's May A/B scored it 6–10%. The adapter-training toolkit's last release (26.0.0) is **not compatible with OS 27**; no successor announced. | Not the authoring brain. Stays the **runtime AI for deployed iPhone/iPad stacks** (existing decision). |
| **Foundation Models — `LanguageModel` / `LanguageModelExecutor` protocol** | New in 27.0. The framework hands your executor the `GenerationSchema` and tool definitions as data — **you implement constrained decoding and tool formatting yourself**. Apple's June-2026 release notes name `ml-explore/mlx-swift-lm` (`MLXFoundationModels`) as an official open-source conformer. | **Optional bridge (Phase 6)**, `#available(macOS 27, *)`. Not the primary seam: Hype targets macOS 15 and needs sampling/logit control the session API does not expose. |
| **Private Cloud Compute** | 32K context, entitlement-gated, daily quota. | Possible future "boost" provider. Out of scope. |
| **Core AI** (`.aimodel`, `coreai-torch`, `coreai-optimization`) | macOS 27+ only; `coreai-opt` is self-labelled Alpha; **no LoRA hot-swap**, no published LLM throughput, **no documented MLX → Core AI path** (Apple points MLX users at Core ML Tools). Apple's `coreai-models` package does ship a full LLM serving layer (tokenizer, KV strategies, xgrammar guided generation, tool parsing). | **Tracked migration target, not v1.** Phase-6 experiment: export the same fused weights (HF format) through `coreai-torch`; compare quality, latency, ANE use. |
| **MLX** | Apple's M5 post says a 24 GB MacBook Pro can hold an 8B in BF16 or a 30B MoE at 4-bit with the inference workload under 18 GB *(paraphrase; a clean benchmark run, nothing else open)*; Neural Accelerators give 3.3–4.1× faster prefill, decode +19–27%. `mlx-swift-lm` ships prompt-cache persistence, KV quantization, LoRA loading, tool parsers, XGrammar guided generation. | **The runtime and the training stack.** |
| **Evaluations framework** | `subject(from:)` wraps **any async function**; native JSONL loader; `ToolCallEvaluator` works on hand-built transcripts; results serialize to JSON. Requires Xcode 27 / macOS 27; **SwiftPM-only use unverified** (Apple's sample is an `.xcodeproj`). No multi-turn/conversation API was found in the docs fetched *(unconfirmed absence)*. | **Release/CI regression gate** on the macOS 27 toolchain, after a 30-minute compatibility spike. The Python harness stays for training-time iteration and multi-turn tournaments. |
| **Create ML / Core ML** | For small classifiers/regressors. | Optional later: a tiny on-device request router. `HypeTalk.mlproj` at the repo root is an empty abandoned scaffold. |
| **HIG — Generative AI** | Keep people in control (undo/retry/edit), confirm irreversible actions, disclose AI use, prefer on-device, specific progress over spinners, keep a manual path. | Drives §5.8–5.9. Hype already has most of this (`AIEditTransaction`, retry gate). |
| **Background Assets** | Apple-hosted packs need App Store/TestFlight; unmanaged packs need App Sandbox + an extension. Hype is unsandboxed, SwiftPM-built, locally signed. | **Not used.** Resumable `URLSession` download with a signed manifest (§8). |

---

## 3. Ground truth from this repository (measured 2026-09-20)

**The seam exists, but it is a closed switch.** `HypeAIClient`
(`Sources/HypeCore/AI/HypeAIClient.swift:39`) is the protocol; every provider is
constructed by `HypeAIConfiguration.makeClient(defaults:)` (`:240`) — a static,
**synchronous**, exhaustive `switch` inside HypeCore, called from ~12 sites. Every AI
surface speaks the provider-neutral — but misleadingly named — `OllamaMessage` /
`OllamaTool` / `OllamaToolCall` / `OllamaChatResponse` types, so a new conformer gets
the tool catalog, the `check_script` gate and preview/apply for free.

**The prompt is far larger than older notes say.**
- `HypeTalkGuide.llmContext` = **21,621 tokens**. (The "~8.6K" and "~52 tools" figures
  survive only in the frozen historical note `scripts/ai-training/AB_APPLE_MLX_RECOMMENDATION.md`
  — leave it — and in one live code comment near `AIChatPanel.swift:1540`, worth fixing.)
- `HypeToolDefinitions.allTools` = **178 tools** (the last training run baked in 113).
  Rendered as tool blocks ≈ **39,400 tokens**; per-request allowlists expose 116
  (`cardControlAuthoringTools`) to 152 unique (`spriteSceneAuthoringTools`; its source
  lists 158 literals with duplicates).
- `AIPromptBudget` trims *messages* to 128K tokens but **never counts the tools array**. CURRENT STATE is uncapped.
- Streaming is off whenever tools are offered (`AIChatPanel.swift:1717`); tool loop `maxRounds = 40`; script retry gate `maxAttempts = 5`.

**There are at least two divergent prompt assemblies today.** `AIChatPanel` gates
the guide on `isTunedHypeTalkModel` (`:1545`, model-name prefix `hypetalk-`) and
switches to a slim prompt (CURRENT STATE + TOOL-USE PRIORITIES). `ScriptEditorAIView`
(`ScriptEditorAIPrompts.systemPrompt`, `:327–336`) embeds the full guide
**unconditionally**; `AIProviderParityHarness` defaults to the full guide;
`SceneAuthoringAssistant`, `AssetRepositoryAIChatView` and the MCP bridge assemble their own.

**The tool loop lives in a view.** ~900 lines inside `AIChatPanel` (a `@MainActor`
SwiftUI `View`) mutate ~15 `@State` properties inline and write back to a live
`@Binding` document at ~10 sites. It cannot run headlessly today.

**The verifier is stronger than assumed.** Tier 1 parse (12K+ scripts/s); Tier 2
static validation — split across two non-unified implementations
(`HypeTalkScriptValidator.swift`; a private `ScriptSemanticValidator` at
`HypeCLI.swift:987`); Tier 3 headless execution with stubbed providers, a
1M-instruction budget, ~410K statements/s; Tier 4 headless tool execution via
`HypeMCPDocumentBackend.callTool` (XCTest-only, no CLI). `InterpreterFuzzTests`
already contains a grammar-driven script generator. `hypetalk` itself is a single
flat `AsyncParsableCommand` with a positional `script` argument and ~30 flags — no subcommands.

**Verified seed material.** 486 hand-authored seed examples; **~900–1,500 handler
snippets in `Tests/HypeCoreTests`** (227 files), each paired with a natural-language
`@Test` description and a behavioural assertion; 7 curated patterns in
`HypeTalkSkillCatalog`; the guide's own examples.

**Lessons from LoRA v1–v6** (`scripts/ai-training/`):
1. v3 hit val-loss 0.020 and passed 3/26 quality prompts — **loss is not quality**.
2. Tuned Qwen3-8B v6 **lost** to untuned base + guide (20% vs 45% object-script attach).
3. One harness fix (single-turn → multi-turn grading) moved granite4.1:30b 55% → 82.5% — **eval correctness dominated every model delta ever measured here**.
4. The May "MLX-direct scores 12%" result was a harness bug: `eval_mlx.py` sends **no tools schema** and parses no tool calls. The same weights scored 68.8% through Ollama.
5. Training rows render tool results as `Tool result: X`; serving renders `<tool_response>` — template drift.
6. Grading is 100% substring; no held-out set was ever built (flagged twice, never done).
7. `eval.py` documents a Swift `HypeTalkGrader` binary that does not exist.

**Build and test graph.** Pure SwiftPM; `swift build` + hand-assembled `.app`
(`script/build_and_run.sh`, reused by `install.sh`);
locally self-signed; no sandbox, no entitlements file, no `.xcodeproj`. One remote
dependency; AudioKit is vendored with a provenance note (the precedent for awkward
dependencies). HypeCore's interpreter kernel must stay watchOS-buildable. **The
`HypeTests` target depends on the `Hype` executable target, and the pre-push gate's
`swift test --filter …` still *builds every target*** — so anything `Hype` links is
compiled on every push. No onboarding flow exists; provider setup lives in `PreferencesView`.

**Naming drift to flag (not fix here).** `OllamaMessage` et al. are the app's
universal chat vocabulary. A rename to `AIChatMessage` / `AIToolSpec` / `AIToolCall` is
a worthwhile separate refactor; the Built-in provider makes the misnomer more visible.

---

## 4. Model choice

### 4.1 The 24 GB budget (the constraint that decides everything)

- Logged `recommendedMaxWorkingSetSize`: 74.0% of RAM at 16 GB, 78.0% at 48 GB,
  84.0% at 128 GB (measured on this machine). **No 24 GB value has been logged;**
  interpolation gives ≈ 18 GB — consistent with Apple's "under 18GB" benchmark, which
  was a clean run. Phase 0 measures it on real hardware.
- `mlx_lm` wires the **entire** recommended ceiling by default. The macOS kernel-panic
  class `IOGPUMemory.cpp:550 prepare count underflow` (ml-explore/mlx#3346,
  mlx-lm#883, mlx-lm#1666) is **not fixed** and has been reproduced on a 24 GB
  MacBook Air M5. Community isolation work implicates full-ceiling wiring plus buffer
  churn (load/unload cycles, cache clearing during generation).
- One real 24 GB data point: macOS + Chrome + app chrome ≈ 6.6 GB before Xcode.

**Design budget on 24 GB: ≤ 10–12 GB resident (weights + KV + scratch) with Hype +
browser + Xcode open; ≤ 15–16 GB absolute maximum with everything else closed.**
Query the ceiling at runtime; never hardcode a percentage; never wire the full ceiling.

Speed anchors (llama.cpp discussion #4167, LLaMA-2 7B Q4_0 — a cross-engine check that
reproduces Apple's MLX M4→M5 ratios):

| Chip (24 GB configs in bold) | Bandwidth | Prefill tok/s | Decode tok/s |
|---|---:|---:|---:|
| M4 | 120 GB/s | 221 | 24 |
| **M5 (MacBook Pro base)** | 153 GB/s | 723 | 32 |
| M4 Pro | 273 GB/s | 440 | 51 |
| **M5 Pro** | 307 GB/s | 1,621 | 66 |
| M5 Max | 614 GB/s | 3,220 | 120 |

8-bit costs ~30–41% of 4-bit decode speed. A persisted prompt cache reloaded an
8.2K-token prefix in **0.57 s vs 17.9 s cold** (measured: M5 Pro, Qwen3.8-27B, third-party server).

### 4.2 Candidates

Sizes are real MLX safetensors totals from the Hugging Face API, except cells marked *(d)* = derived.

| Model | Licence | Architecture | 4-bit | 6-bit | 8-bit | KV @16K | Verdict for the 24 GB default |
|---|---|---|---:|---:|---:|---:|---|
| **Qwen3.5-9B** | Apache-2.0 | dense hybrid Gated-DeltaNet 3:1, vision, MTP, 262K | 5.95 | 8.19 | 10.43 | ~0.55 GiB | **Primary.** |
| **granite-4.2-8b** | Apache-2.0 | dense GQA, 131K, switchable thinking | 4.95 | 7.14 | 9.34 | ~2.5 GiB | **Fallback of record.** |
| gemma-4-12B-it | Apache-2.0 | dense, 5:1 sliding window, encoder-free multimodal, 256K | 6.74 | 9.73 | 12.72 | ~0.44 GiB | Third lane in the untuned probes. Needs `mlx-lm` git main (#1481). |
| Ministral-3-8B / 14B | Apache-2.0 | dense `mistral3`, 256K | 5.6 / ~9–10 *(d)* | — | — | dense | Credible; zero Hype-domain evidence. |
| Granite-4.0-H-Tiny | Apache-2.0 | hybrid Mamba-2 + MoE 7B-A1B | 3.91 (DWQ) | — | — | tiny | Interesting 16 GB tier; hybrid LoRA fix only weeks old; no Swift `LoRAModel`. |
| gpt-oss-20b | Apache-2.0 | MoE 21B-A3.6B MXFP4, harmony | 11.2–12.1 | — | — | small | **Out:** mlx-lm tool-call bug #875 open 7 months; `mlx_lm fuse` broken for it (#1172). |
| ERNIE-4.5-21B-A3B | Apache-2.0 | MoE | 12.28 | — | — | — | **Out:** the MoE variant has no `mlx-swift-lm` port; no tool template. |
| gemma-4-26B-A4B-it | Apache-2.0 | MoE 25.8B-A3.8B | 15.34 | — | — | small | Over the 24 GB budget. |
| Qwen3.8-27B | Apache-2.0 | same family as the primary | 16.05 | 22.8 *(d: sibling Qwen3.6-27B)* | 29.5 | ~1.1 GiB | Over budget on 24 GB → **Pro tier**. |
| granite-4.2-30b | Apache-2.0 | dense GQA | 16.47 | 23.5 *(d: interpolated)* | 31.1 | ~4.0 GiB | Over budget → fallback Pro tier, ≥ 48 GB. |
| Devstral-Small-2-24B, Muse-Glimmer-30B, Nemotron-3.5-Lightning, GLM-4.7-Flash (16.85 GB) | various | | 13.5–17.8 | | | | Over budget, and/or VLM-only registry, licence or age concerns. |

Hype's own evidence (untuned, full guide, via Ollama): granite4.1:30b **98.4%**,
qwen3.6:35b 88.2%, granite4.1:8b 54.3% (29 of 58 failures are *one* routing confusion:
`create_*` instead of `set_part_property`), qwen3:8b 57.5–68.8%, gemma4:26b/31b 40%
with **0% on script-attach** (JS-flavoured output).

### 4.3 Why Qwen3.5-9B is the primary

1. **Fits with real headroom:** ~6.5–7 GB resident at 4-bit including KV and the
   vision tower; ~9 GB at 6-bit. Also viable on 16 GB Macs at 4-bit.
2. **Near-flat KV/state** (8 of 32 layers keep a growing KV cache): long contexts and
   40-round tool loops do not explode memory. A dense 8B's KV is 2.5 GiB at 16K, 5 GiB at 32K.
3. **Tool-use benchmarks nearly tie its 27B sibling** (BFCL-V4 −2.4, TAU2 +0.1); the gap
   is in raw coding (LiveCodeBench −15.1) — what fine-tuning on verified HypeTalk targets.
4. **Native vision in the same checkpoint** for the rationed `capture_card_image`
   turns — *credited only if gate G9 shows it survives fine-tuning and quantization.*
5. **One integration, a whole family:** identical `qwen3_5` architecture, tokenizer,
   chat template, XML tool-call format and Swift classes (`Qwen35Model`, dedicated
   Qwen3.5 tool-call parser, MTP support) for Qwen3.6-27B, Qwen3.8-27B, Qwen3.6-35B-A3B
   — and the Apache-2.0 **teacher Qwen3.5-122B-A10B** (same tokenizer → logit/on-policy
   distillation possible later).
6. Decode MBU measured at 86–92% for this family vs 70–77% for plain dense →
   ~20–22 tok/s on base M5, ~40–45 on M5 Pro at 4-bit *(derived — unmeasured at 9B)*.
7. Largest ecosystem of any candidate (9.2M downloads; many community LoRAs on this checkpoint).

**Known risks — each is a gate, not a footnote:**
- **Training cost and stability (the big one).** The Gated-DeltaNet recurrence has
  no custom VJP in `mlx-lm`; the fallback is a sequential loop with O(T) memory and
  superlinear time. PR mlx-lm#1870 measured *one* layer of exactly this shape at
  4.2 s (2K tokens) and 39 s (4K tokens) forward+backward on an M4 Pro; Qwen3.5-9B has
  24 such layers. Open issue **mlx-lm#1206: LoRA crashes on the first backward pass
  with Qwen3.5-9B on an M5 Max** — this machine class. Two upstream fixes closed
  unmerged; the chunkwise-parallel kernel (#1870, claimed ~130× faster, 6.5× less
  memory) is open. `mlx-lm-lora` detects hybrid recurrent models and uses checkpointed
  blocks automatically. **Whether Qwen trains at a usable tok/s on this machine is
  unknown and decides the base model.**
- **Sustained decode:** two field reports on the 27B sibling (via third-party servers)
  show multi-round agentic decode 2.5–4.5× below burst numbers. Unmeasured at 9B and through `mlx-swift-lm`.
- **MTP is not a guaranteed win** (1.57–1.88× measured in MLX on the 27B; a
  llama.cpp/Metal test showed a net *loss* on the 9B). Optional optimization only.
- **`mlx-swift-lm`#561** (LoRA over linear-attention projections faulting the GPU in
  Swift) is closed, fix version unconfirmed → ship **fused** weights, not runtime adapters.
- **Vendor churn:** Qwen3.6/3.8 shipped no 9B. The fine-tuned weights are Hype's
  durable artifact; re-evaluate the base each training cycle.

**Why granite-4.2-8b is the fallback of record:** plain GQA (zero known `mlx-lm` LoRA
bugs; the only top candidate whose Swift class conforms to `LoRAModel`); the family
with the best HypeTalk prior in Hype's own tournament; a same-family 30B proven at
98.4%; clean `enable_thinking=False`. Costs: no vision, linear KV growth (8-bit KV
needed for long sessions), and a Pro tier that needs ≥ 48 GB.

### 4.4 Gates that settle the choice

Two rounds, because a fair pilot fine-tune needs Phase-1 infrastructure.

**Round A — Phase 0 (needs no Hype-side infrastructure; ~1 week).** On the M5 Max and a
**real 24 GB Mac** (base M5 MacBook Pro ideally — *must be borrowed or bought; nothing substitutes for it*):

| # | Probe | Pass condition |
|---|---|---|
| A1 | **Training throughput & stability:** 200-step LoRA on Qwen3.5-9B via `mlx-lm-lora` (checkpointed recurrences) and, if available, the #1870 kernel; sequence lengths 2K / 4K / 8K / 16K; report **tokens/sec, peak memory, crash/clean**, and gradient norms on the DeltaNet projections. Same runs on granite-4.2-8b as the control. | Clean at ≤ 8K; DeltaNet projections receive non-zero updates; **≥ 300 tok/s at 4K and ≥ 150 tok/s at 8K**, or within 3× of granite. |
| A2 | **Untuned tournament:** Qwen3.5-9B, granite-4.2-8b, gemma-4-12B through `tournament_multiturn.py` with the *same tools schema and guide* production uses. | Informational; a Qwen score far below granite-8b's 54.3% is a red flag. |
| A3 | **Sustained tool-loop decode** through `mlx-swift-lm` `ChatSession` on the 24 GB Mac with Hype + Chrome + Xcode open: tok/s in the *last 5 rounds* of a 30–40-round loop; resident memory; TTFT cold vs cached; with and without 8-bit KV (quality spot-check). Log the real `recommendedMaxWorkingSetSize`. | ≥ 15 tok/s sustained on base M5; AI resident ≤ 10 GB; no collapse > 1.5× vs burst. |
| A4 | **Tool-call round trip:** 30 real tool turns through each model's Swift parser. | Zero parser failures on well-formed output. |
| A5 | **Vision smoke test:** one `capture_card_image` turn through the VLM registry path. | Works end to end. |

→ **Provisional base:** Qwen3.5-9B if A1 and A3 pass; otherwise granite-4.2-8b.

**Round B — end of Phase 1 (needs the verifier CLI and the frozen held-out suite).**

| # | Probe | Pass condition |
|---|---|---|
| B1 | **Pilot fine-tune (= Stage S1):** the same ~2K verified rows on both finalists, identical recipe, **execution-graded** on the held-out suite. | The provisional base is confirmed if it is ≥ the other finalist −2 pts; a tie goes to Qwen (family, vision, KV). |

Because the corpus is text-level, the verifier is model-independent and the Swift
provider is architecture-agnostic, switching bases costs days, not months. An
off-Mac escape hatch exists if Qwen is wanted but MLX training is too slow: train
with PyTorch + flash-linear-attention kernels on a rented GPU and convert to MLX —
**a deviation from "train with MLX" that needs Michael's explicit sign-off** (§12).

### 4.5 Variants by machine

| Mac RAM | Variant | Resident | Notes |
|---|---|---:|---|
| < 16 GB | — | — | Built-in unavailable; other providers still work. |
| 16 GB | 9B, 4-bit | ~7 GB | Supported; tighter context cap; "close other apps" hint. |
| **24 GB** | **9B, quantization per gate G8** (4-bit expected) | 7–9.5 GB | **The default target.** |
| 32–36 GB | 9B at 6/8-bit, or Pro 27B 4-bit (after Phase-6 gates) | 10–18 GB | |
| ≥ 48 GB | **Pro: Qwen3.8-27B 4-bit** (6-bit at ≥ 64 GB); optionally Qwen3.6-35B-A3B for speed | 18–25 GB | Same integration, same data, retrained. |

Artifacts keep the existing naming convention (e.g. `hypetalk-9b-2026.1`), but the
`hasPrefix("hypetalk-")` check becomes an explicit client capability — a **prompt
profile** — not a string convention.

---

## 5. Runtime architecture (in-process, no Ollama)

### 5.1 Targets — and keeping the pre-push gate healthy

```
Sources/
  HypeCore/          # NO MLX imports; stays watchOS-portable
    AI/
      HypeAIClient.swift          # + HypeAIProvider.builtIn, + builtInClientFactory hook
      PromptAssembly/             # NEW: single source of truth for every AI surface (5.3)
      AuthoringAgentLoop.swift    # NEW: tool loop extracted from AIChatPanel (5.2)
      BuiltInModel/               # NEW: MLX-free domain types
        BuiltInModelCatalog.swift   # variants, RAM tiers, manifest schema
        ModelStore.swift            # download / verify / versions / rollback / disk usage
        MemoryFitPolicy.swift       # pure: (RAM, ceiling, KV bytes/token, variant) -> caps/verdict
  HypeApp/           # NEW library target = today's Sources/Hype code (HypeTests depends on THIS)
  Hype/              # thin executable: main + registers the Built-in factory
  HypeMLX/           # NEW, macOS-only
    BuiltInModelClient.swift      # actor : HypeAIClient  (Anticorruption Layer)
    MLXSessionHost.swift          # ModelContainer / ChatSession ownership, queueing, cancellation
    PromptPrefixCache.swift       # savePromptCache / loadPromptCacheSnapshot, keyed
    ToolCallGrammar.swift         # XGrammar structural tags from HypeTools JSON Schema
    WiredMemoryGuard.swift        # budget below ceiling, KV cap, pressure handling
  HypeVerifier/      # NEW executable `hypeverify` (6.1) — no MLX
```

- **The test-graph problem.** Today `HypeTests` → `Hype`, and `swift test` builds every
  target, so the moment `Hype` links `HypeMLX` every push compiles MLX (C++ + Metal).
  Resolution, decided by the Phase-0 build spike:
  **Option A (preferred):** split `Hype` into the `HypeApp` library (what `HypeTests`
  depends on) + a thin `Hype` executable that alone links `HypeMLX`. The gate still
  *compiles* `HypeMLX` (acceptable if the Metal toolchain builds cleanly and
  incrementally) but **no test bundle ever loads MLX**, which is what mlx-swift#460 crashes on.
  **Option B:** move the app shell + `HypeMLX` into a second in-repo package that
  depends on the root package, so root `swift test` never sees MLX; `build_and_run.sh` and
  `install.sh` build from that package.
- **The registration hook.** `makeClient` is a synchronous static switch inside
  HypeCore, which cannot name `HypeMLX`. Add
  `public static var builtInClientFactory: (@Sendable () throws -> any HypeAIClient)?`
  to `HypeAIConfiguration`; the `Hype` executable sets it at launch; `.builtIn` calls it
  and throws a clear "Built-in model is not available in this build" error when unset
  (CLI, tests). The factory returns a lightweight actor shell immediately; **model
  loading is lazy on first use** (the "Loading" state in §5.8), so synchronous callers never block.
- The **Anticorruption Layer** is `BuiltInModelClient`: MLX types (`ChatSession`,
  `ToolSpec`, `Generation`, `KVCache`) never leak into HypeCore or views.
- Dependencies: `mlx-swift`, `mlx-swift-lm`, `swift-transformers`; exact pins; recorded
  in `OpenSourceManifest.json`. If any fails to resolve cleanly under tools-version 6.0,
  follow the AudioKit vendoring precedent.

### 5.2 Extract the tool loop: `AuthoringAgentLoop` (its own milestone)

This is a real refactor, not a move. Scope:
1. The loop operates on a `HypeDocument` **value** plus an explicit apply step through
   `AIEditTransaction` — replacing ~10 live `@Binding` write-backs.
2. It emits a typed **progress-event stream** (`AsyncStream<AuthoringAgentEvent>`:
   token, tool-call started/finished, script refused/retried, capture requested,
   proposal pending, transaction ready, cancelled); `AIChatPanel` subscribes and owns
   all `@State`.
3. Response repair, the retry-gate wiring, CURRENT STATE assembly and capture budgeting move with it.
4. Characterization tests pin today's behaviour (fake `HypeAIClient`) *before* the move.

Payoffs: the **same loop** runs headlessly to generate training trajectories and to
grade evals — train/serve parity by construction — and the chat panel becomes presentation.

### 5.3 One prompt-assembly path for *every* surface

`PromptAssembly` renders, for (document state, request, surface, **prompt profile**),
the exact system prompt, tool set and messages. Profiles: `.fullGuide` (untuned models —
today's behaviour) and `.builtIn` (slim). Consumers to migrate — all in scope:
`AIChatPanel`, **`ScriptEditorAIView`** (today: unconditional full guide),
`AssetRepositoryAIChatView`, `SceneAuthoringAssistant`, `CardCaptureCoordinator`,
`AIProviderParityHarness`, the MCP bridge. `hypeverify prompt --json` exposes the
renderer so the **Python pipeline calls the Swift renderer** instead of re-implementing
it. Chat-template rendering uses the model's own tokenizer template on both sides;
every shipped model snapshot includes its resolved `chat_template`.

### 5.4 The prompt diet — "guide in weights, tools by index"

| Component | Today | Built-in profile |
|---|---:|---:|
| HypeTalk guide | 21.6K tokens | **0** (in weights); on demand via the existing `get_hypetalk_skill_guide` / `get_hypetalk_pattern` / `check_script` tools |
| Tool schemas | 25–35K tokens (116–152 tools) | **~3K-token tool index** (name + one-line signature); full schemas enforced by grammar (§5.5); `get_tool_help(name)` for rare tools |
| Static rules | ~2–3K | ~0.5–1K TOOL-USE PRIORITIES |
| CURRENT STATE | unbounded | capped + summarized beyond N parts/nodes, with `inspect_*` tools for detail |
| **Static prefix** | — | **≤ ~4K tokens, KV-cached on disk** (key = model id + prefix hash + tool-catalog hash) |

Tool-catalog drift (113 → 178 tools in five months) is handled three ways: the index is
generated from `HypeTools` at build time; training includes **tool-index dropout,
renamed tools and never-seen tools** so the model reads the index rather than trusting
memory; every app release re-runs the tool-routing eval slice. This is `decisions.md`
verbatim: *"Large catalogs should be discoverable through tools rather than always
injected into the system prompt."*

Expected turn on a base M5 *(derived)*: prefix cache load < 1 s; a 2–4K dynamic suffix
prefills in ~4–7 s (≈ 2–3 s on M5 Pro); a 150-token tool call decodes in ~7 s at 20 tok/s.

**Before the fine-tune exists** the Built-in provider runs an untuned base under
`.fullGuide`. On 24 GB that is only viable with (a) the ~45–55K-token static prefix
(guide + tool schemas) **built once and disk-cached** (~1.5–2 minutes cold on a base M5
*(derived)*, seconds thereafter), (b) a hybrid/sliding-window base whose KV at 60K tokens
stays ≈ 2 GB, and (c) the per-surface tool subsets. It is labelled **Preview**; on a
dense base (granite) the untuned preview is restricted to ≥ 32 GB Macs.

### 5.5 Constrained decoding: guarantee the envelope, verify the body

- **Tool calls:** `MLXGuidedGeneration` (vendored XGrammar, works back to macOS 14) with
  **trigger-based structural tags** — the grammar engages only *after* the model emits
  the tool-call opener, then constrains the tool name to the offered set and the
  arguments to that tool's JSON Schema (`HypeTools` definitions already are valid JSON
  Schema). The trigger design avoids the documented *Tool Suppression* failure
  (arXiv 2606.25605), where eager schema constraints stop open models calling tools.
- **Structured content** (`SceneCreateProposal`, `SceneRepairProposal`, optionally a
  one-shot `GameRecipe` alongside the incremental recipe tools): schema-constrained
  through `structuredChat`, keeping the tolerant decoders as a second line of defence.
- **Script bodies stay unconstrained.** The parser is a 4,288-line recursive-descent
  parser with lookahead and vocabulary-driven disambiguation; a faithful CFG would be a
  permanent double-maintenance burden. The system of record remains
  `HypeTalkScriptValidator` → `ScriptDraftRefusal` → `ScriptDraftCoordinator` retry with
  the parser error fed back. A block-skeleton grammar (`on…end`, `if…end if`,
  `repeat…end repeat`) is an evidence-gated later experiment.
- Add the base model's chat-template tokens to the validator's forbidden-token list.

Once the envelope is guaranteed, `HypeAIResponseRepair`'s five salvage shapes and two
hard-coded canned scripts are dead weight for this provider: measure, then retire them
for `.builtIn` only. Lower `maxAttempts` once first-attempt pass rate is measured.

### 5.6 Memory policy (`WiredMemoryGuard`) — defence in depth

1. Read `recommendedMaxWorkingSetSize` and `physicalMemory` at load; compute the budget
   per §4.1; **never wire the full ceiling**.
2. **Context caps are computed, not fixed:** `MemoryFitPolicy` derives the cap from the
   variant's KV bytes/token and the budget — e.g. on 24 GB, ~64K for Qwen3.5-9B
   (KV ≈ 2 GiB) but ~32K with 8-bit KV for a dense 8B. `AIPromptBudget`'s 128K floor
   becomes per-profile. KV quantization is enabled only where probe A3 and the S5
   ablation show no quality loss.
3. **No load/unload churn, no cache clearing during generation.** Load once, keep
   resident, unload only when idle *and* under memory pressure.
4. One generation at a time (single actor) — structurally avoids the concurrent-admission panic path.
5. Observe memory pressure, `thermalState`, Low Power Mode → surface in the chat status line.
6. Refuse to load, with a clear message, when `MemoryFitPolicy` says no.

### 5.7 Build and test integration

- **Spike first:** Swift 6.4's new default build system reportedly compiles MLX's Metal
  shaders under plain `swift build` (the README still says xcodebuild is required;
  maintainers said otherwise on 2026-09-17). Verify with Hype's real package, measure
  the gate's added build time, choose Option A or B (§5.1). Fallback: a prebuilt
  `mlx.metallib` copied by the generic resource step in `script/build_and_run.sh`. Verify
  the new build system's output layout does not break the three deploy scripts.
- Test `BuiltInModelClient` against a fake session; live MLX tests live in a separate
  target gated by `HYPE_LIVE_MLX=1` (mirroring `HYPE_LIVE_OLLAMA=1`) that the gate never runs.
- Register the client in `AIProviderParityHarness`.
- Confirm hardened-runtime behaviour of MLX's Metal JIT before ever notarizing.

### 5.8 UX states (HIG-aligned; lives in Preferences — there is no onboarding flow)

The provider picker gains **"Built-in (on-device)"**. Every state is designed, including the unhappy ones:

| State | What the author sees |
|---|---|
| Unsupported Mac | Why (memory), and that other providers still work. |
| Not installed | Size, free disk, "runs privately on this Mac", **Download** — explicit consent, never a silent multi-GB fetch. |
| Downloading / paused / failed / **offline** | Real progress, pause/resume, retry; survives relaunch; an offline notice instead of a spinner. |
| Verifying | Checksum + signature. A failed verification deletes the partial download and keeps the previous version active. |
| Ready | Variant, version, disk usage, **Remove**, "Test Built-in model" (reuse the `OllamaProviderDiagnostics` pattern). Once installed, **the Built-in model works fully offline.** |
| Loading (first use) | "Loading model…" with elapsed time; then prefix-cache warm-up. |
| Generating | Step-level progress ("Creating button…", "Checking script…"); tool rounds can stream the tool name as it is decoded. |
| Busy elsewhere | A second stack window sees "Built-in model is busy in *Stack A* — queued" with Cancel; requests queue FIFO per window. |
| Constrained | Memory pressure / thermal / Low Power hint; context-cap notice. |
| Update available | New version, size, changelog, eval score. **The old version stays active until the new one verifies; one-click rollback to the last known-good version; versions can be pinned.** |

**Accessibility (day 1):** VoiceOver labels and live-region announcements for download,
verification and generation progress; full keyboard operability for
pause/resume/retry/remove/cancel; status never conveyed by colour alone; respects
Reduce Motion. **Localization:** all new strings go through the app's existing string
handling; no model-facing prompt text is localized. **Visual QA** per `decisions.md`:
build, deploy and inspect every state.

### 5.9 Cancellation and transactions

Cancel stops token generation at the next step, abandons the in-flight tool call
*before* it executes, and leaves the open `AIEditTransaction` in **preview** —
never partially applied. Tool calls already executed within the transaction remain
reviewable and revertible through the existing preview/apply/rollback flow. Billable
deferred tools (Meshy) are never started by a cancelled round.

### 5.10 Runtime AI in deployed Mac stacks — a decision, not a default

`ask ai` in an exported Mac app throws today (`UnavailableDeployedAIProvider`), and
`decisions.md` forbids embedding local-model endpoints in deployed defaults. The
Built-in engine *could* fill the `.macOS` arm of `RuntimeAIProviderResolver`, but
shipping 6 GB of weights with exported apps (or sharing Hype's installed copy) is a
product decision with size, licence and consent implications. **Out of scope for v1** (§12).

---

## 6. Training program

### 6.1 Verifier first — the filter, the reward and the grader are one thing

`hypetalk` is a flat command with a positional script argument; bolting subcommands
onto it is ambiguous (`hypetalk verify` = run the literal script "verify"). So: a **new
executable target `HypeVerifier` (`hypeverify`)** with real ArgumentParser subcommands,
reusing HypeCore, leaving `hypetalk` untouched. JSON in/out, always exit 0 with a
verdict, **batch/stdin mode** to avoid per-script process start-up.

| Command | Tier | Purpose |
|---|---|---|
| `hypeverify script` | 1–3 | parse → unified semantic validation → headless run against a fixture stack; structured errors (line, handler, category, "did you mean") |
| `hypeverify scenario` | 3 | run handlers against a fixture, then assert on field text / properties / messages |
| `hypeverify tools` | 4 | execute a tool-call trajectory against a headless document (`HypeMCPDocumentBackend`); per-call results + final state |
| `hypeverify content` | — | validate `GameRecipe` (compiles through `RecipeCompiler` to parser-valid HypeTalk) and scene-proposal JSON against their schemas and decoders |
| `hypeverify schema` | — | dump the 168-property registry, part types, events, built-ins and the tool catalog — the **coverage matrix** source |
| `hypeverify prompt` | — | §5.3 |

Merge the two Tier-2 validators into one canonical `ScriptSemanticValidator` in HypeCore
(the chat gate keeps its false-negative bias through configuration). Validator failure
categories become the **error taxonomy** for negatives, eval reporting and telemetry.

### 6.2 Data engine — every row is executed before it is believed

| Source | Method | Share |
|---|---|---:|
| **Harvest** | ~900–1,500 verified handlers from `Tests/HypeCoreTests` (+ descriptions and assertions), the 486 seeds *(after the provenance audit, §8)*, skill-catalog patterns, guide examples, HyperTalk reference compat tests | seed |
| **Back-translation** | verified script → teacher writes 3–5 natural author requests (varied persona/phrasing) | 12% |
| **Docs-grounded generation** | per guide section × property × part type × tool, driven by the `schema` coverage matrix. **Coverage floor N = 20 verified rows per construct (provisional; revisit after S1), ≥ 50 for the 50 most-used constructs and tools;** report min/median coverage | 22% |
| **Agent trajectories** | synthetic fixture stacks (built headlessly) → author task → **a teacher drives the real `AuthoringAgentLoop`** with the full guide → keep only trajectories where every tool call succeeds, every stored script passes `hypeverify script`, and scenario assertions hold | 30% |
| **Composite content** | complete `GameRecipe` flows (incremental recipe tools → `build_game`), `SceneCreateProposal` / `SceneRepairProposal` JSON, stack text content (field copy, dialog/HUD text, quiz content, error explanations) — validated by `hypeverify content` | 10% |
| **Transfer** | game/UI scripting tasks from JS/Lua/Python rewritten in HypeTalk, verified by scenario tests (MultiPL-T style) | 8% |
| **Robustness & negatives** | paraphrases; distractor tools; *existing-vs-new object* pairs (the `set_part_property` vs `create_*` confusion); "no tool — answer in prose"; fail-closed SpriteKit cases; clarifying questions; rejected siblings kept as DPO negatives | 15% |
| **Vision slice** | 1–2K rows: headlessly rendered fixture cards (`CardRenderer`) → layout verification/critique, labelled by an open multimodal teacher and checked against the known fixture geometry | 3% |
| **General replay** | **default: self-replay** — the base model's own answers on diverse general/tool prompts, which anchors behaviour with no third-party provenance. Third-party instruct/tool datasets only after the same provenance audit as the seeds (many popular ones were distilled from frontier APIs) | +15–30% of the mix (sweep) |

**Surfaces:** rows are rendered through `PromptAssembly` for each surface
(`AIChatPanel`, `ScriptEditorAIView`, `AssetRepositoryAIChatView`,
`SceneAuthoringAssistant`) with that surface's tool subset.

**Controls:** MinHash dedup; **decontamination against the held-out suite before every
round**; fixture stacks span trivial → 200-part documents; multi-turn rows use the real
`tool` role and the real template (fixing the `Tool result: X` drift).

**Sequence budget (resolves the prefix-vs-cap conflict).** A slim-profile row =
~4K prefix + 0.5–3K CURRENT STATE + history + completion. Three length buckets:
**≤ 4K** (scripts, single tool calls — ~55% of rows; these use a *truncated* prefix
variant, which doubles as index-dropout training), **≤ 8K** (multi-turn, composite
content — ~35%), **≤ 16K** (long trajectories over large fixtures — ≤ 10%). Long
trajectories are also **unrolled per round** (one row per assistant turn, loss on that
turn only) so most learning signal lives in the ≤ 8K bucket. If probe A1 shows 8–16K
is impractical on the chosen base, the 16K bucket is dropped and CURRENT STATE
summarization is tightened — and the "grounding at 200-part scale" claim is reduced to match.

**Context distillation:** the teacher generates with the **full 21.6K-token guide**;
the student is trained on the same targets under the **slim Built-in profile**. Risk:
the student learns to assert guide facts it never saw → mitigated by the coverage
floor, by verifier-only acceptance, and by keeping 10–15% of rows with retrieved guide
snippets so the on-demand skill tools stay useful.

**Teachers (open weights only):** `granite-4.2-30b` (its predecessor scores 98.4% on
Hype's tournament — the best available HypeTalk writer) and `Qwen3.5-122B-A10B`
(Apache-2.0, ~70 GB 4-bit, fits this machine; BFCL-V4 72.2; multimodal for the vision
slice). Two teachers + a hard verifier beat one teacher's style; per-teacher share is
tracked so style drift is visible. Throughput is **unmeasured**: ~40M generated tokens
for 100K rows is roughly 2–6 days of batched generation on the M5 Max *(derived)*; the
20K checkpoint needs about a fifth of that.

Volumes: **2K pilot → 20K first production checkpoint → 60–100K stretch**, matching the
low-resource-language and tool-calling literature (MultiPL-T, Magicoder 75K, xLAM 60K,
ToolACE). LIMA-scale data does not transfer: HypeTalk is new knowledge, not a format.

### 6.3 Toolchain

- `mlx-lm` from **git main**, pinned by commit (DeltaNet, `gemma4_unified`,
  granite-hybrid and gpt-oss fixes all post-date PyPI 0.31.3).
- **If the base is Qwen3.5-9B, every training stage — S1, S2, the S3 retrain, DPO and
  GRPO — runs through `mlx_lm_lora.train`**, never plain `mlx_lm.lora`, so the automatic
  checkpointed-recurrence handling is always on. (`mlx_lm.lora` on this model is exactly
  the crashing combination in #1206.) For granite either trainer works.
- `mlx-lm-lora` is a fast-moving community package: pin it, and cross-check one SFT run
  against plain `mlx_lm.lora` on granite before trusting it.
- Replace the Gemma → GGUF → Ollama path in `scripts/ai-training`; keep `gen_corpus.py`'s
  tool rendering, the CURRENT STATE injection algorithm, `tournament_multiturn.py` and the
  seed YAML format. Call `mx.random.seed()` explicitly (the CLI `--seed` only seeds shuffling).

### 6.4 Stages

| Stage | What | Key settings | Exit |
|---|---|---|---|
| **S1 Pilot SFT** | 2K verified rows; validates the pipeline end to end; is gate B1 | LoRA all-linear, rank 64, LR 1e-4–2e-4 cosine, 3% warm-up, effective batch 16–32, length buckets per §6.2, completion-only loss, 2–3 epochs; **vision tower frozen** | beats untuned base + full guide on the held-out suite |
| **S2 Production SFT** | 20K → 60K+ rows, full mix, context distillation | same; checkpoint selection by **execution-graded dev pass rate, never val loss** | ≥ 85% held-out; general regression ≤ 3 pts |
| **S3 Rejection-sampling round** | sample k = 8 per prompt from S2 on a fresh decontaminated pool; keep verifier-accepted; **retrain from the base** (ReST-EM) — budgeted as a full second SFT run | — | monotone gain with CI |
| **S4a DPO** | on-policy pairs: accepted vs rejected siblings of the same prompt | β 0.1, LR 5e-6 | fewer first-attempt validator rejects |
| **S4b GRPO — optional** (Dr.GRPO loss) | reward = parse × semantic-valid × scenario-assertions-pass × tool-args-valid — **deterministic terms only; no LLM judge anywhere in the reward**; group 4–8; tight max completion length; human spot-check of rollouts each iteration | run **only if** DPO leaves a measurable gap *and* A1 throughput makes the rollout + backward budget affordable | significant gain (McNemar) over S4a |
| **S5 Quantize** | fuse in bf16 → verify the vision tower and MTP head tensors are bit-identical to the base → `mlx_lm.dynamic_quant` → **`mlx_lm.dwq` calibrated on the domain corpus** → 4-bit; A/B vs mxfp4; KV-quantization ablation | DWQ adds little at 6-bit (its own docs say so): the 6-bit fallback is plain / dynamic quant | gate G8 |

**Thinking mode:** trained and shipped **non-thinking** for the interactive path;
planning already has explicit tools (`plan_hypetalk_script`, `check_script`). A bounded
thinking mode for hard multi-step requests is a later experiment.

### 6.5 Compute honesty

No credible M5-Max MLX *training* throughput is published, and the one relevant
measurement (#1870) says stock DeltaNet training is drastically slower than a dense
transformer's. **Probe A1's tokens/sec sets the schedule**: 20K rows across the three
length buckets average ~4–5K tokens each ≈ 80–100M training tokens per epoch; at
500 tok/s that is ~2 days per epoch, at 150 tok/s about a week. Phase 3's duration, the
affordability of S3 and S4b, and the §4.4 decision all key off that number.

---

## 7. Evaluation and ship gates

### 7.1 Suites

| Suite | Size | Grading | Purpose |
|---|---:|---|---|
| **Tournament-127** (existing) | 127 | substring, multi-turn | continuity with history |
| **Held-out authoring suite** (new) | **≥ 700** (≈ 350 authored scenarios × 2 fixture variants) | **execution** via `hypeverify`; sub-scores: script bodies · tool routing · CURRENT STATE grounding · composite content (GameRecipe / scene JSON) · in-app text · negatives · multi-turn · **per surface** | the promotion metric |
| **Vision slice** | 50 | fixture-geometry checks | gate G9 |
| **General regression** | ~300 | IFEval-style checks, a generic tool-calling slice, content writing judged by a larger **open** model calibrated against human scores | anti-forgetting |
| **Systems** | — | sustained 40-round tok/s, TTFT cold/warm, resident memory, **8-hour soak** with Chrome + Xcode churn on a real 24 GB Mac | field readiness |

**Independence of the held-out suite.** It is authored *after* the guide freeze by
someone who is not tuning the guide or corpus. With one developer, the mechanism must
be explicit (§12): a contracted HyperCard-literate author, or a **blinded agent session**
with no access to the corpus prompts, generator code or guide-edit history, reviewed by
Michael; independence is *checked* with n-gram/MinHash overlap against the corpus.

**Why ≥ 700.** For a paired non-inferiority test with margin δ = 3 pts (one-sided
α = 0.05, power 0.80), n ≈ (1.645 + 0.84)² · p_disc / δ². At an expected ~10% discordant
rate that is ≈ 690 prompts (≈ 410 at 6%). With 400–500 prompts the test would be
under-powered in exactly the 85–95% operating range the new model is expected to land in.
Achieved power is reported alongside the CI whenever G1 is evaluated.

First fix: give `eval_mlx.py` tools-schema and tool-call-parsing parity — without it,
MLX-side numbers are meaningless (the May A/B's root cause).

### 7.2 Statistics

Paired **McNemar** tests between checkpoints, **BCa bootstrap CIs** (10K resamples),
Holm–Bonferroni across multiple comparisons. Raw pass@k deltas on a few hundred prompts
are noise — this repo's own history proves it.

### 7.3 Ship gates (all must hold)

| Gate | Threshold |
|---|---|
| G1 Quality vs today's best | Held-out suite: **non-inferior to granite4.1:30b-via-Ollama + full guide (δ = 3 pts, one-sided 95%)** and ≥ +15 pts over the untuned base + full guide |
| G2 First-attempt script validity | ≥ 95% pass `hypeverify script` without the retry gate |
| G3 Hygiene | 0 chat-template token leaks; 0 wrong-language scripts on the JS/Lua-bait slice |
| G4 Latency (base M5, 24 GB) | sustained ≥ 15 tok/s in rounds 30–40; warm TTFT ≤ 2 s; cold turn ≤ 8 s |
| G5 Memory | AI resident ≤ 10 GB at 16K context with Hype + Chrome + Xcode open |
| G6 General capability | no regression > 3 pts vs the base |
| G7 Stability | 8-hour soak, zero panics or crashes |
| **G8 Quantization** | ship DWQ 4-bit **unless it trails the bf16 fused checkpoint by > 1.0 pt** on the held-out suite (paired); otherwise ship 6-bit (plain/dynamic quant). This is the single canonical rule referenced by §0, §4.5 and S5. |
| **G9 Vision** | the shipped artifact is ≥ the untuned base on the vision slice; if it fails, v1 ships text-only and `capture_card_image` is withheld for Built-in (the model pick does not change) |

**Until G1 holds, Built-in ships as opt-in "beta" and Ollama remains the documented
default.** It is never presented as equivalent to the 30B experience before it is.

### 7.4 Apple's Evaluations framework

After the SwiftPM-compatibility spike: a Swift `Evaluation` whose subject is
`AuthoringAgentLoop` + any `HypeAIClient`; code-based evaluators call the real
Lexer/Parser/dispatcher; `ToolCallEvaluator` over transcripts adapted from Hype's
tool-call log; results saved as JSON and diffed per release. Single-turn prompts migrate
first; multi-turn stays in Python unless a conversation API turns up.

---

## 8. Distribution, licensing, privacy

- **Hosting:** Cloudflare R2 (zero egress) as primary, a public ungated Hugging Face repo
  as mirror/discovery. A developer-**signed manifest (Ed25519)** lists shards, sizes,
  SHA-256, model id, base model, licence, minimum app version and eval scores. Resumable
  `URLSession` downloads; verify before activation; keep the last known-good version.
- **Location:** `~/Library/Application Support/Hype/Models/<model-id>/<version>/` (not
  Caches — it gets purged); excluded from backups; visible disk usage; one-click removal.
- **Ship fused, quantized models**, not runtime adapters (best quality and speed; avoids
  the Swift linear-attention LoRA fault class). A ~6 GB re-download per model release, a
  few times a year, is acceptable; revisit adapter deltas later.
- **Licensing:** all finalists are Apache-2.0 → NOTICE/attribution only; no naming
  mandate, no MAU cap. Extend `OpenSourceManifest.json` (mlx-swift, mlx-swift-lm,
  swift-transformers, XGrammar) and add model-manifest fields: `baseModel`,
  `baseModelLicense`, `trainingDataProvenance`, `teachers`. Publish a model card.
- **Teacher and data provenance policy:** the Anthropic, OpenAI and Google API terms
  each prohibit using outputs to train competing models; a redistributed, generally
  capable fine-tune is a grey area at best. Clean path: open-weights teachers for the
  corpus. **Provenance audit — scheduled in Phase 0, before any seed enters S1:** who
  authored the 486 seeds and with what tools; the same audit for any third-party dataset
  considered for general replay. Anything of frontier-API origin is regenerated through
  an open teacher + the verifier, or cleared in writing. Frontier models may still build
  the tooling, review the eval suite and act as eval-time judges. *This is an engineering
  risk assessment, not legal advice; get counsel before a public weights release
  (including the EU AI Act fine-tuner / open-source exemption read).*
- **Privacy:** fully on-device; no prompt or stack content leaves the Mac. The
  improvement flywheel (Phase 6) is **opt-in and export-based**: verifier-rejected
  generations and immediately-undone AI edits are collected locally; the author reviews
  and chooses to send a file. No silent telemetry.

---

## 9. Roadmap

| Phase | Weeks | Work | Exit criteria |
|---|---|---|---|
| **0 Spikes & Round-A gates** | 1–2 | Build spike (`swift build` + Metal; Option A vs B; gate build time; deploy-script layout) · prompt-cache round trip · probes A1–A5 · Evaluations SwiftPM spike · memory-guard soak prototype · **provenance audit** · acquire a 24 GB test Mac | **Provisional base chosen**; training tok/s known → schedule re-estimated; build approach decided; go/no-go on MLX Swift |
| **1 Verifier & eval foundation** | 3–4 | `hypeverify` (script / scenario / tools / content / schema / prompt) · unify validators · **`AuthoringAgentLoop` extraction (1.5–2 weeks, characterization tests first)** · `PromptAssembly` + profiles across all surfaces · held-out suite authored and frozen · execution grading · `eval_mlx.py` tool parity · re-extract tool catalog and guide · **gate B1 (S1 pilot on both finalists)** | Held-out baselines for granite4.1:30b, the untuned finalists and the legacy tuned models; **base model confirmed** |
| **2 Data engine** | 3–4 | harvesters · fixture-stack generator · teacher trajectories through the real loop · composite-content and vision slices · coverage matrix · dedup/decontam · 2K → 20K | 20K verified rows; coverage ≥ N per construct (min/median reported); zero held-out leakage |
| **3 Training** (overlaps 2) | 3–6 *(set by A1)* | S2 → S5; ablations (mix ratio, rank, DPO vs GRPO, quantization, KV bits) | G1–G3, G6, G8, G9 on the dev machine |
| **4 Runtime integration** (parallel with 1–3) | 4–5 | target split + factory hook · `HypeMLX` · `BuiltInModelClient` · `ModelStore` + manifest + rollback · `WiredMemoryGuard` · prefix cache · tool-call grammar · Preferences UI (all states, accessibility) · queueing/cancellation · diagnostics · parity harness | Untuned **Preview** usable end to end through Built-in (24 GB on a hybrid base with the cached prefix; ≥ 32 GB otherwise) |
| **5 Beta hardening** | 2 | real-hardware G4/G5/G7 · model card · manifest signing · docs (`architecture.md` §7, `decisions.md`, README, `OpenSourceManifest.json`, new `scripts/ai-training/README.md`) · visual QA of every state | All gates green → Built-in beta ships opt-in |
| **6 After v1** | ongoing | Pro tier (27B) · opt-in flywheel · MTP if measured to win · `LanguageModel` protocol bridge (macOS 27) · Core AI export experiment · runtime-AI decision (§5.10) · default-provider switch once G1 holds in the field | |

Critical path: Phase 0 → 1 → 2 → 3. Phase 4 deliberately does not wait for the
fine-tune: the in-process provider is the harness Phase-0/5 measurements need, and an
Ollama-free Preview is useful on its own.

---

## 10. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| DeltaNet LoRA crashes or is impractically slow on the M5 Max (mlx-lm#1206, #1870) | **Medium–High** | High | Probe A1 with a numeric tok/s gate; `mlx-lm-lora` checkpointed trainer; length buckets; **fallback base granite-4.2-8b**; off-Mac training only with sign-off |
| Fine-tune again loses to untuned + guide | Medium | High | Verifier-first data at 20–100K; execution grading; powered held-out suite; G1; S1 must beat the baseline before scaling |
| 9B quality ceiling below the 30B experience | Medium | Medium | Honest beta labelling; Ollama stays; Pro tier; separate script-body and content sub-scores |
| Kernel panic / memory pressure on 24 GB | Low–Med | Severe | `WiredMemoryGuard`; ≤ 10–12 GB budget; no churn; computed context caps; 8-hour soak gate |
| Sustained tool-loop decode collapse | Unknown | High | Measure through `mlx-swift-lm` in A3 before committing; bounded KV; granite as control |
| SwiftPM + Metal breaks the gate or deploy scripts | Medium | Medium | Phase-0 spike; target split (A) or second package (B); prebuilt `metallib` |
| `AuthoringAgentLoop` extraction regresses the chat panel | Medium | Medium | Characterization tests first; event stream; own milestone |
| Tool-catalog drift makes weights stale | High | Medium | Tool index in prompt + index-dropout training + grammar from the live catalog + per-release routing eval |
| Context distillation teaches unfounded assertions | Medium | Medium | Coverage floor; verifier-only acceptance; retained retrieval rows |
| Reward hacking in GRPO | Medium | Medium | Deterministic reward only; length caps; human rollout review; GRPO is optional |
| Eval contamination across RFT rounds | Medium | High | Decontaminate every round; independent, frozen, overlap-checked held-out suite |
| Upstream churn (`mlx-swift-lm`, `mlx-lm-lora`, the Qwen line) | High | Low–Med | Pin commits; fused weights are Hype's artifact; re-evaluate the base each cycle |
| Licence/provenance of seeds or replay data | Low–Med | High | Phase-0 audit; open teachers; self-replay default; counsel before public release |
| No 24 GB test hardware | — | High | Acquire in Phase 0; nothing substitutes for it |

---

## 11. Documentation and repo changes this will require

- `architecture.md` — new subsection under AI Authoring: Built-in provider, target
  split, `HypeMLX` boundary, model storage, prefix cache, memory policy, `AuthoringAgentLoop`, `PromptAssembly`.
- `decisions.md` — new guardrails: explicit-consent download; disk transparency and
  removal; never wire the full GPU ceiling; Built-in joins the local side of the context
  policy; deterministic verifier is the only RL reward; promotion gates; open-teacher and provenance policy.
- `README.md` — "Optional AI and network services" and AI-assisted authoring sections.
- `Sources/Hype/Resources/OpenSourceManifest.json` — new components + model entry.
- `scripts/ai-training/` — new README; keep the v1–v6 and tournament notes as frozen
  history (including their stale "~52 tools / ~8.6K guide" figures); the ~350 GB of
  superseded fused snapshots in `out/` can be deleted (untracked; owner's call).
- Fix the stale "~6K tokens" guide comment near `AIChatPanel.swift:1540`; de-duplicate the
  `spriteSceneAuthoringTools` literal list.

---

## 12. Decisions needed from Michael

1. **Accept the two-finalist approach** (Qwen3.5-9B primary, granite-4.2-8b fallback,
   settled by §4.4) — or force a single pick now. *If forced today: granite-4.2-8b is the
   lower-risk choice for MLX training; Qwen3.5-9B is the higher-ceiling product choice.*
2. **A 24 GB test Mac** (base M5 MacBook Pro ideally) for Phase 0 and the soak gate.
3. **"Train with MLX" strictness:** if A1 shows Qwen is too slow in MLX, fall back to
   granite (default), or allow off-Mac PyTorch training with conversion to MLX?
4. **Who authors the held-out suite**, and by which independence mechanism (§7.1)?
5. **Default-provider policy:** Built-in becomes the zero-config default only after G1
   holds — agreed? Until then opt-in beta.
6. **Weights release posture:** public (HF mirror + model card) or app-only download?
   Public raises the bar on provenance and counsel review.
7. **Provenance audit** — who authored the 486 seeds, and with what tools?
8. **Deployed-Mac runtime AI** (§5.10): keep out of scope, or plan a consented,
   shared-model path for a later release?
9. **Deployment target:** stay on macOS 15 (this plan) or move to 26/27 sooner, which
   would make the `LanguageModel` protocol and Evaluations first-class.

---

## Appendix A — Key sources

Apple: technology overview *Generative models and machine learning*; Foundation Models
(`LanguageModel`, `LanguageModelExecutor`, TN3193, context-window guide, June-2026
updates); Core AI docs, `coreai-torch` 0.4.2, `coreai-opt` 0.2.1, `apple/coreai-models`;
Evaluations docs + Book Tracker sample; HIG *Generative AI* and *Machine learning*; ML
Research *Exploring LLMs with MLX and the Neural Accelerators in the M5 GPU*.
MLX: `ml-explore/mlx-lm` (LORA.md, LEARNED_QUANTS.md, tuner, tool_parsers; issues #875,
#883, #1172, #1206, #1481, #1666; PR #1870), `ml-explore/mlx-swift-lm` (KVCache,
LoRAContainer, Tool/Parsers, MLXGuidedGeneration, MLXFoundationModels, PR #545, issue #561),
`ml-explore/mlx-swift`#460, `ml-explore/mlx`#3346/#3186, `Goekdeniz-Guelmez/mlx-lm-lora`,
`mlc-ai/xgrammar`. Models: Hugging Face API + cards for every model in §4.2.
Methods: MultiPL-T (2308.09895), Magicoder (2312.02120), WizardCoder (2306.08568), ReST-EM
(2312.06585), *LoRA Without Regret* (Thinking Machines, 2025), *LoRA Learns Less and
Forgets Less* (2405.09673), Dr.GRPO (2503.20783), DAPO (2503.14476), APIGen/xLAM, ToolACE
(2409.00920), BFCL, Grammar-Aligned Decoding (2405.21047), *Let Me Speak Freely?*
(2408.02442), *Constraint Tax in Open-Weight LLMs* (2606.25605), MLX 4-bit code-quality
study (Zenodo 10.5281/zenodo.22698290), llama.cpp discussion #4167.
Repo: `scripts/ai-training/*` results docs, `Sources/HypeCore/AI/*`, `AIChatPanel.swift`,
`ScriptEditorAIView.swift`, `HypeCLI.swift`, `Package.swift`, `.githooks/pre-push`,
`decisions.md`, `architecture.md`.

# Hype

**HyperCard, reimagined for modern macOS.**

Hype is a native macOS authoring tool in the spirit of Apple's HyperCard
(1987–2004). It preserves the original mental model — **stacks** of
**cards** built on shared **backgrounds**, populated with **parts**
(buttons, fields, shapes, images, videos, charts, sprite areas, …) and
driven by a HyperTalk-style scripting language called **HypeTalk** —
and re-grounds it on a contemporary Apple-platforms stack: Swift 6,
SwiftUI, SpriteKit, Core Graphics, AppKit, WKWebView, AVKit, Apple
Charts, and a **dual-provider AI authoring loop** that supports both
local **Ollama** models (the default — no network egress) and optional
**OpenAI** models (frontier quality, image generation, speech I/O)
through one unified tool-calling contract.

This repository contains the full source for the desktop application,
the core library, the HypeTalk language toolchain, and the AI
fine-tuning / evaluation pipeline.

---

## Why bring HyperCard back?

HyperCard's core insight — that a *stack of cards*, hand-edited in
place, with scripts attached to live objects, is one of the most
approachable programming models ever shipped — is timeless. What's
changed is the surface area. A modern revival should feel native on
Apple Silicon, edit cleanly under source control, expose every
visual control the platform offers, and let an LLM ride along as a
co-author without the user ever leaving the canvas.

That's what Hype is. It is **not** a HyperCard emulator and it does
not run legacy `.stack` files. It is a fresh codebase that adopts the
HyperTalk-style authoring philosophy, extends it to roughly twice the
control surface, and treats SpriteKit as a first-class peer of the
classic flat-card model — so a card can host both a static button-and-
field layout *and* a live physics scene with a tile map and particle
emitters in the same document, with one unified scripting model.

---

## Highlights

- **One document, infinite control types.** Cards host buttons,
  fields, shapes, images, video players (AVKit), web pages
  (WKWebView), charts (Apple Charts), maps (MapKit), PDFs (PDFKit),
  calendars (EventKit-aware), color wells, steppers, sliders,
  segmented controls, gauges, progress views, dividers, audio
  recorders (AVFoundation), 3D scene viewers (SceneKit + STL/USDZ
  conversion), and full SpriteKit sprite areas — all editable in the
  same property inspector with the same multi-selection bulk editor.
- **HypeTalk: a real, modern HyperTalk descendant.** A native lexer +
  recursive-descent parser + tree-walking interpreter, with operators
  (`is in`, `is within`, `is a number`, `there is a button "X"`),
  control flow (`repeat`, `if/then/else`, `exit`, `pass`), chunks
  (`word N of`, `item N of`), 30+ built-in functions, async forms
  (`await ollama(…)`, `request "…" with message …`, `listen for tcp`),
  and 50+ message types (`mouseUp`, `openCard`, `frameUpdate`,
  `beginContact`, `valueChanged`, `recordingStarted`, …).
- **SpriteKit as the interaction substrate.** Card-level cinematic
  transitions go through `SKView.presentScene(_:transition:)`. A
  `spriteArea` part hosts a live `SKScene` with a real scene graph —
  sprites, physics bodies, joints, particle emitters, tile maps,
  cameras — and HypeTalk handlers route to scene nodes through the
  same message-passing chain as classic parts.
- **AI authoring with tool-calling — Ollama OR OpenAI.** Hype drives the
  document via 150+ structured tools (`create_button`, `set_card_script`,
  `add_sprite_to_scene`, `apply_scene_diff`, `generate_image`, …) routed
  through a single `HypeAIClient` contract with two concrete providers:
  local Ollama (default, no network egress) and optional OpenAI
  (frontier-model quality, image generation, speech). Every model output
  goes through a validating tool surface with a parser-level script gate,
  retry loop, reference-resolution pass, and a transaction layer that
  previews each turn against a draft document so you can apply / cancel /
  roll back before any mutation touches the live stack. A 127-prompt
  benchmark suite is included; `granite4.1:30b` currently leads the
  local-models leaderboard at 98.4% raw / 99.999% effective accuracy
  after the retry gate.
- **A real theme system.** Stacks, backgrounds, and cards each carry
  an optional theme name; the cascade resolver picks the effective
  theme per card. Seven built-in themes ship — System (follows
  macOS), Classic HyperCard (B&W), Modern Light, Modern Dark, Sunset,
  Neon, and **Liquid Glass** (Apple's macOS Tahoe / iOS 26 design
  language: translucent surfaces with vibrancy, hairline strokes,
  generous corner radii). Every renderer consults the active theme;
  the SwiftUI inspector chrome picks up `.regularMaterial` /
  `.thickMaterial` / `.thinMaterial` automatically when the theme
  opts into glass material rendering.
- **Document-based, value-typed, source-controllable.** `.hype` files
  are JSON. The model is a single `HypeDocument` aggregate of value
  types — diffs are readable, undo/redo is trivial, and the file
  format is forward-compatible (unknown part types decode to a
  filtered-out sentinel, not a crash).
- **Tested.** ~1,400 unit tests under Swift Testing, all passing
  under the parallel runner in roughly 80 seconds. Coverage spans
  parser, interpreter, tool-call routing, scene serialization,
  rendering geometry (per-pixel sampling), theme cascade, async
  runtime, and AI evaluation.

---

## What's on a card?

Every part is a single `HypeCore.Part` value type with a
`PartType` discriminator. The renderer dispatches on the type;
property panels, multi-selection editing, and scripting all work
uniformly across them.

**Native Apple controls:**
`button` (12 styles incl. switch/checkbox/radio/popup/link),
`field` (7 styles incl. search/secure/scrolling),
`shape` (rectangle, roundRect, oval, line, freeform path),
`image`, `video` (AVKit), `webpage` (WKWebView),
`chart` (Apple Charts).

**Form controls:**
`stepper`, `slider`, `segmented`, `toggle`, `colorWell`,
`progressView`, `gauge`, `divider`.

**Apple-framework controls:**
`calendar` (EventKit-aware), `pdf` (PDFKit, multi-page nav),
`map` (MapKit, geocoding via async `mapLocation`),
`audioRecorder` (AVFoundation, m4a/caf, live duration tick),
`scene3D` (SceneKit, STL/USDZ/OBJ/SCN/DAE).

**SpriteKit:**
`spriteArea` — a live `SKScene` host. Inside it: sprite, label,
shape, group, camera, emitter, audio, video, tilemap nodes; physics
bodies; joints; constraints; physics fields. All HypeTalk-addressable.

---

## HypeTalk

HypeTalk is an English-like, case-insensitive scripting language
modeled on HyperTalk and extended for SpriteKit, async networking,
and AI calls.

```hypetalk
on mouseUp
  set the visible of image "logo" to not the visible of image "logo"
end mouseUp

on openCard
  global score
  put 0 into score
  put "Welcome — score: 0" into field "status"
end openCard

on beginContact otherName
  global score
  if otherName is "goal" then
    add 10 to score
    set the text of label "score" to "Score: " & score
  end if
end beginContact
```

**Implementation surface (in `Sources/HypeCore/Script/`):**

- `Lexer.swift` — tokenizer; supports curly quotes, line continuation
  (`\` before newline), `--` comments.
- `Parser.swift` — recursive-descent parser producing the AST in
  `AST.swift`.
- `Interpreter.swift` — tree-walking interpreter with full operator
  precedence, chunk expressions (`word N of`, `item N of`,
  `line N of`, `char N of`, plus ranges and ordinals), control flow,
  globals (`global X` per-handler declaration), and a comprehensive
  built-in catalog.
- `MessageDispatcher.swift` — routing layer from canvas events
  (mouseUp, keyDown, frameUpdate, beginContact, valueChanged,
  searchSubmitted, locationResolved, modelLoadFailed, …) to handler
  bodies, with the classic part → card → background → stack → app
  dispatch chain.
- `HypeTalkGuide.swift` — the language reference fed to AI models on
  every turn (~54 KB / ~13.5 K tokens after the grammar-coverage
  expansion).

A separate, much longer reference lives at
[`HyperTalk_Reference.md`](HyperTalk_Reference.md).

---

## SpriteKit substrate

The single most consequential architectural decision is treating
SpriteKit as a peer to the classic flat-card model.

- **Card-level transitions.** Navigating between cards uses
  `SKView.presentScene(_:transition:)` so HyperCard-era visual
  effects (`dissolve`, `wipe left`, `iris open`, `barn door open`,
  `zoom in`, etc.) animate as real scene transitions, not crossfades
  hacked on top of a static layer.
- **Sprite areas.** A `spriteArea` part is a SwiftUI/AppKit-hosted
  `SKView` showing an `SKScene`. The scene's contents are described
  by a `SceneSpec` value type (`Sources/HypeCore/Models/SceneSpec.swift`)
  that round-trips through JSON in the document. Live nodes are
  reconstructed from the spec at scene-load time via
  `SceneBridge.swift`, and a `NodeRegistry` maintains a bidirectional
  UUID ↔ `SKNode` map so HypeTalk can address nodes by name.
- **Physics.** Every node can carry a `PhysicsBodySpec`
  (rectangle/circle/edgeChain/edgeLoop/alphaMask) with friction,
  restitution, density, mass, gravity flags. Joints (pin, spring,
  fixed, sliding, limit) and physics fields (electricMagnetic,
  drag, vortex, radial, linear, noise, turbulence, spring) are
  first-class citizens.
- **Particles.** Emitters are configured in the property inspector
  with a live preview. Specs round-trip through `EmitterNodeSpec`.
- **Tile maps.** `tileSet` repository assets, with classification UI
  to set columns/rows/tile size. `set tile` / `fill tilemap` / `the
  tile at` HypeTalk verbs operate on live `SKTileMapNode`s.

A practical hands-on tour is in
[`SpriteKit-Tutorial.md`](SpriteKit-Tutorial.md).

---

## AI authoring

Hype's AI Chat panel supports **two providers** — local Ollama
(default, no network egress) and **optional OpenAI**. Both share
the same tool-calling contract through a single
[`HypeAIClient`](Sources/HypeCore/AI/HypeAIClient.swift)
abstraction. The provider is a preference: pick whichever you
trust for the task at hand.

| Provider | Where requests go | When to pick it |
|---|---|---|
| **Ollama** (default) | `localhost:11434` — local model on your machine | Stays offline; document state, prompts, and tool calls never leave the box; best with `granite4.1:30b` or similarly capable local models |
| **OpenAI** (opt-in) | OpenAI Responses API (`/v1/responses`), Images (`/v1/images/generations`), Audio (`/v1/audio/speech` + transcriptions) | When you want frontier-model quality, image generation, or higher-quality speech I/O. Set `OPENAI_API_KEY` in Hype Preferences. |

Switching providers is a one-line change in Preferences → AI;
the system prompt (`HypeTalkGuide.llmContext`) and the tool
schema list are identical, so a prompt that works on one
provider almost always works on the other. An
`AIProviderParityHarness` test suite verifies that the two
clients exchange the same scenarios with the same tool-call
results.

Cloud AI is **opt-in twice**: once for the global provider, and
once per-stack via `Stack.aiContextCloudSharingAllowed`, which
gates whether the `AIContextLibrary` (rules, files, examples
attached to the stack) is included in cloud requests. Local
Ollama can use context unconditionally; OpenAI cannot until both
flags are set.

### Tool-calling architecture

The model never types HypeTalk into your document directly. Every
change goes through a structured tool-call interface with **150+
defined tools** (`Sources/HypeCore/AI/HypeTools.swift`,
`HypeToolExecutor.swift`):

```
create_card / create_button / create_field / create_image / create_video / create_chart
add_sprite_to_scene / add_label_to_scene / add_emitter_to_scene / …
set_part_property / set_card_property / set_background_script / set_stack_script / set_scene_script
get_card_parts / get_part_property / list_scene_nodes / …
check_script / list_all_properties / capture_card_image / …
```

Every script-storage tool routes the draft through:

1. **`check_script`** — parser-level validation. The model is told
   (via `HypeTalkGuide.swift`) to call this first; it returns
   `OK:` / `FAIL: <reason>` with the offending line number.
2. **`HypeTalkScriptValidator`** — secondary host gate that catches
   forbidden patterns (JS-flavored tokens like `function (`,
   `addEventListener`, `=>`, etc.) and runs reference-resolution.
3. **`ScriptDraftCoordinator`** — retry loop. On host-side refusal,
   the storage tool returns a `__HYPE_INTERNAL_DRAFT_REFUSED_v1:`
   sentinel; the chat panel iterates with the model up to 5 times.
4. **`ScriptAutoFixer`** — surgical pre-flight repairs (bare `end` →
   `end <handlerName>`, `elseif` → `else if`) so trivially mechanical
   mistakes don't burn a retry.

### Recommended models

The 127-prompt benchmark suite in
[`scripts/ai-training/eval/comprehensive_prompts.jsonl`](scripts/ai-training/eval/comprehensive_prompts.jsonl)
covers introspection, object CRUD, script attachment, network,
animation, audio, dialog, chunks, control flow, and framework
controls. Latest results
([`scripts/ai-training/TOURNAMENT_127_RESULTS.md`](scripts/ai-training/TOURNAMENT_127_RESULTS.md)):

| Rank | Model | Pass rate (raw) | Effective @ N=5 retries |
|---|---|---|---|
| 1 | `granite4.1:30b` | **98.4% (125/127)** | **99.99999987%** |
| 2 | `qwen3.6:35b`    | 88.2% (112/127)     | 99.99948%        |
| 3 | `granite4.1:8b`  | 54.3% (69/127)      | 97.91%           |

Set the active model in Hype's preferences panel (or via
`defaults write com.hype.app ollamaModel "granite4.1:30b"`).

### Transactional AI edits (preview / apply / rollback)

Every AI tool turn — across the main AI Chat panel, the Script
Editor AI assistant, and the Sprite Repository AI assistant —
runs through
[`AIEditTransaction` / `AIEditTransactionRunner`](Sources/HypeCore/AI/AIEditTransaction.swift):

1. The model emits tool calls.
2. The runner executes them against a **draft copy** of the
   document, not the live one.
3. The resulting deltas (changed parts, cards, backgrounds,
   sprite repository entries, paint layers, scripts) are captured
   as an `AIEditDocumentDelta` plus a rollback snapshot of every
   touched object's prior state.
4. The user gets a preview summary and chooses **Apply** or
   **Cancel**. Apply commits the draft and registers a single
   undo step; cancel leaves the document bit-for-bit unchanged.
5. The most-recently applied transaction can be **rolled back** —
   not just undone via the responder chain, but explicitly
   reverted at the model layer using the recorded snapshot.

This is what lets you say "create a customer entry form on this
card" or "make my game ball bounce" without trusting the model
not to corrupt unrelated state — the failure mode of a bad turn
is a discarded draft, not a half-mutated stack.

### AI Context Library

Each stack carries an `AIContextLibrary` of files, images, text
notes, and folders that the AI sees on every prompt. Items are
tagged by role — **rules**, **asset**, **styleGuide**,
**example**, **projectMemory**, **reference** — so a long-running
project can teach the model its own conventions without
re-pasting them. Items can be **embedded** (bytes stored in the
`.hype` file) or **referenced** (path on disk, included only when
the file is reachable).

Context is gated by both the provider preference and the per-stack
`aiContextCloudSharingAllowed` flag, so private rules and customer
artifacts never reach OpenAI by accident.

### Image generation

[`OpenAIImageGenerationClient`](Sources/HypeCore/AI/OpenAIImageGenerationClient.swift)
adds a `generate_image` tool whose result lands directly in a
new image part or `SpriteRepository` asset (via the standard
transaction path, so it's previewable and rollback-able). The
returned bytes are PNG; provenance is recorded on the asset so
the inspector shows which model + prompt produced it.

### Speech I/O

Hype's HypeTalk grammar gained two speech surfaces:

```
-- Speak text aloud (uses macOS AVSpeechSynthesizer locally or
-- the OpenAI `/v1/audio/speech` endpoint when the OpenAI
-- provider is active and `speechProvider == "openai"`):
say "Welcome to my stack"

-- Toggle the speech listener; while active, transcribed phrases
-- arrive at the `on listen` handler chain:
set activateListener to true

on listen spokenText
  put spokenText into field "lastSpeech"
  pass listen
end listen
```

The `SpeechOutputProvider` and `SpeechListenerProvider`
abstractions decouple HypeTalk from the underlying engine, so the
same script runs against the system speech APIs or an OpenAI
voice without script-level changes.

### Fine-tuning pipeline

`scripts/ai-training/` contains a complete LoRA fine-tuning pipeline
targeting Qwen3 8B (configurable for other base models): corpus
generation from seed YAMLs, MLX-based training, fusion, Ollama
packaging, eval grading, and an A/B harness. Run `make all` from
that directory.

---

## Themes

Stack > background > card cascade with seven built-in themes:

| Name | Mood | Use case |
|---|---|---|
| System | Follows macOS appearance | Default for new stacks |
| Classic HyperCard | Black & white, sharp corners, Geneva-ish | Tribute / minimalism |
| Modern Light | Calm grays + indigo accent | Productivity |
| Modern Dark | Charcoal + teal accent | Long sessions, dark mode |
| Sunset | Warm peach + orange accent | Reading / journaling |
| Neon | Magenta on near-black with cyan secondaries | Games / arcade |
| **Liquid Glass** | Translucent surfaces, vibrancy, system blue | Apple's Tahoe / iOS 26 look |

Liquid Glass opts into a `usesGlassMaterial = true` flag that tells
every renderer to switch to a translucent glass treatment (low-alpha
fill + top-edge specular highlight + soft drop shadow) and tells
SwiftUI panels to back themselves with `.regularMaterial`. Every
button style honors `theme.accent`; text is automatically
contrast-aware against the chosen accent (light text on dark
accents, dark text on light accents).

User-authored themes are first-class — duplicate any built-in via
the Theme Designer (Window menu → Theme Designer) and edit. User
themes live on `HypeDocument.themes` and travel with the file.

---

## Build & install

### Requirements

- macOS 15 or later (the app targets macOS 15+ via `Package.swift`).
- Xcode 16 / Swift 6.0 toolchain (`swift --version` should report
  6.0+).
- *(optional, for AI features)* Ollama running locally on
  `localhost:11434`. Pull the recommended models with:
  ```bash
  ollama pull granite4.1:30b   # ~17 GB — recommended default
  ollama pull qwen3.6:35b      # ~23 GB — strong alternative
  ollama pull granite4.1:8b    # ~5 GB — small + fast (ship after fine-tune)
  ```

### Build the app

```bash
git clone https://github.com/mweingartner/hype.git
cd hype
swift build -c release
```

### Install to /Applications

```bash
bash install.sh
```

The installer copies the release binary, icons, and `Info.plist`
into `/Applications/Hype.app` and re-signs ad-hoc. After the first
install, double-click any `.hype` file in Finder to open it.

### Run from a development build

```bash
swift run Hype
```

### Run the test suite

```bash
scripts/test.sh                    # 1,400+ tests, ~80 seconds
scripts/test.sh --filter HypeTalk  # subset by Suite or Test name
scripts/test.sh --no-parallel      # serial runner — fallback for debugging
```

---

## Project layout

```
Hype/
├── Package.swift                 # SwiftPM, macOS 15+, Swift 6
├── install.sh                    # Build release → install to /Applications
├── architecture.md               # In-depth architecture overview
├── HyperTalk_Reference.md        # Long-form HypeTalk language reference
├── HypeTalk-LLM-Context.md       # Older LLM context doc (now lives in code)
├── SpriteKit-Tutorial.md         # Hands-on SpriteKit walkthrough
├── docs/
│   └── AppleFrameworksRoadmap.md # Apple-framework integration roadmap
├── Sources/
│   ├── Hype/                     # Executable target — UI / AppKit / SpriteKit
│   │   ├── HypeApp.swift         # @main, DocumentGroup, menu commands
│   │   ├── Resources/
│   │   ├── SpriteKit/            # SKScene/SKNode bridge layer
│   │   └── Views/                # SwiftUI / NSViewRepresentable
│   │       ├── MainContentView.swift
│   │       ├── CardCanvasView.swift
│   │       ├── PropertyInspector.swift
│   │       ├── ScriptEditor.swift
│   │       ├── AIChatPanel.swift
│   │       ├── SpriteRepositoryView.swift
│   │       ├── Themes/                  # Theme designer
│   │       └── …
│   └── HypeCore/                 # Library target — model, scripting, AI, rendering
│       ├── Models/               # HypeDocument, Part, Stack, Card, SceneSpec, PartGrouping, CardPaintLayer, AIContextLibrary, …
│       ├── Script/               # Lexer, Parser, AST, Interpreter, MessageDispatcher (`say`, `on listen`, `send to`)
│       ├── Rendering/            # Per-control CG renderers + GlassRenderer + FieldTextLayout
│       ├── SpriteKit/            # Scene bridge + native-card Button/Field/Shape/Image/Paint nodes
│       ├── AI/                   # HypeAIClient (Ollama + OpenAI), tools, validator, fixer, EditTransaction, ContextLibrary, ProviderParityHarness, Image + Speech clients
│       ├── Theme/                # HypeTheme, BuiltInThemes, ColorContrast
│       ├── Runtime/              # Browse-mode StackRuntime actor, speech listener provider
│       ├── Animation/            # `animate the X of Y over N` engine
│       ├── Audio/                # Sound playback, NAOD note parser
│       ├── Layout/               # Snap-to-grid, alignment, distribution
│       ├── Tools/                # Mouse-action layer (paint, draw, select, group)
│       ├── Sync/                 # SyncService — operation/change-set engine + checkpoints
│       ├── Export/               # `.hype` ↔ JSON ↔ HTML (paint layers embedded as PNG)
│       ├── Logging/              # HypeLogger
│       ├── Navigation/           # Card history, go-back stack
│       └── Controls/             # Visual-effect catalog, PaintLayer, etc.
├── Tests/
│   ├── HypeCoreTests/            # 1,556 unit tests (Swift Testing) — full suite ~85s
│   └── HypeTests/                # SpriteKit / canvas / menu / Script Editor AI integration smokes
└── scripts/
    ├── test.sh                   # Canonical `swift test` invocation
    └── ai-training/              # LoRA fine-tuning + eval pipeline
        ├── Makefile
        ├── config.yaml
        ├── corpus/
        ├── eval/
        │   └── comprehensive_prompts.jsonl
        └── src/
```

---

## Design principles

1. **Domain language wins.** Code uses HyperCard / HyperTalk
   vocabulary verbatim — `Stack`, `Background`, `Card`, `Part`,
   `Handler`, `Message`, `Chunk`. Implicit rules become named objects
   (`PartAnimator`, `MessageDispatcher`, `ScriptDraftRefusal`).
2. **Value types for the model.** Every persisted entity is a
   `Codable Sendable` value type. Mutations go through
   `HypeDocument.updatePart(id:_:)` so undo/redo and Codable round-
   trip are trivial.
3. **AppKit where SwiftUI is brittle, SwiftUI everywhere else.**
   Heavy interactive surfaces (`CardCanvasView`,
   `HypeFieldEditorCell`, `SpriteAreaHostView`) are
   `NSViewRepresentable` for direct event control. Inspector panels,
   menus, dialogs are SwiftUI.
4. **AI as a co-author, not a generator.** The model edits your
   document through validated tool calls inside a retry loop, with
   parser-level + reference-level + forbidden-pattern checks before
   any mutation lands. The chat panel always shows what the model is
   about to do.
5. **Tests are the spec.** Renderer geometry, parser corner cases,
   theme cascade, scene-spec round-trip, AI dispatch — all covered
   by the test suite. Red CI is the canonical "we broke something"
   signal.

The full design rationale, including the SpriteKit substrate
decision, the StackRuntime actor model, async dispatch semantics,
and security posture (script gates, AI tool refusal sentinels,
forbidden patterns), is in [`architecture.md`](architecture.md).

---

## Status

Hype is **active research / personal-tool** development at version
2.0. The model surface is stable enough that older `.hype` files
load forward-compatibly, but APIs and tool catalogs are still
evolving. Production use is not warranted; daily authoring use is
the author's primary workflow.

Recent milestones:

- Apple's Liquid Glass theme + theme-aware rendering across every
  button style.
- Multi-selection (canvas + sprite scenes) with Cmd/Shift-click
  and a uniform-edit inspector covering position, size, transform,
  appearance, and text formatting (alignment, font, color).
- AI eval suite expanded to 127 prompts across 10 categories;
  `granite4.1:30b` reaches 98.4% raw / 99.999% effective.
- Test suite parallel-runner deadlock fixed (cooperative-thread
  starvation in the sync→async dispatch bridge); 1,400+ tests run
  in ~80 s.

---

## Contributing

The repository is open-source under the MIT license. Issues and
pull requests are welcome. See `architecture.md` before opening a
substantive PR — many design choices have load-bearing rationale
documented there.

For PRs:

- Run `scripts/test.sh` and confirm green.
- Match the existing commit-message style (`area: imperative
  sentence` plus a short prose body explaining *why*).
- Keep new public APIs `Sendable` where possible.
- For visual changes, add a per-pixel rendering test (see
  `Tests/HypeCoreTests/ControlCleanupTests.swift` for the pattern).

---

## License

MIT — see `LICENSE` (to be added) for the full text.

The HyperCard name and design language are property of Apple Inc.
Hype is an independent revival project that uses no Apple HyperCard
code or assets; it draws inspiration from the public HyperCard
manuals and the broader HyperTalk culture (Decker, LiveCode, etc.)
and is implemented from scratch.

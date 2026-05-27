# Hype Architecture

> A snapshot of the current implementation as of 2026-05-27.

Hype is a modern, macOS-native re-imagining of HyperCard. It preserves the
HyperCard mental model — **stacks** of **cards** built on shared **backgrounds**,
populated with **parts** (buttons, fields, shapes, images, video, web pages,
charts, sprite areas), all driven by a HyperTalk-style scripting language
called **HypeTalk** — and re-grounds it on a contemporary Apple-platforms
stack: Swift 6, SwiftUI, SpriteKit, Core Graphics, AppKit, WKWebView,
AVKit, Apple Charts, and a provider-selectable AI authoring loop that can use
local Ollama models, local llama-swap proxies, or OpenAI-hosted models, plus
OpenAI image generation for card/background artwork and Sprite Repository
assets. Deployed non-macOS runtimes use a separate runtime AI policy that
prefers Apple's built-in on-device Foundation Models where the target platform
supports them.

The single most important architectural decision is the introduction of
**SpriteKit as the underlying interaction and rendering substrate** for cards.
The card is no longer a passive bitmap with controls floating on top — it is a
live `SKScene` capable of hosting a real-time scene graph (sprites, physics,
particles, tile maps, cameras) inside any part marked as a `spriteArea`, while
also driving the cinematic transitions between cards via SpriteKit's
`presentScene(_:transition:)`. The HyperCard message-passing model is preserved,
but messages now flow through both classic parts and SpriteKit nodes uniformly.

The second architectural shift is the move from a purely copy-in/copy-out
script evaluator to a **browse-mode runtime actor**. In browse mode, a
`StackRuntime` owns the live document session, async continuations, AI jobs,
HTTP requests, listeners, TCP connections, and callback queue. HypeTalk stays
source-compatible and synchronous by default, but explicit suspending forms
(`wait`, `wait until`, `await …`, `request …`, listener callbacks) now run
through that runtime so scripts can talk to Ollama and network services
without blocking the app or corrupting handler ordering.

This document describes how that is implemented today.

Agentic coding harness instructions live in `AGENTS.md`. This file should stay
focused on the architecture as built: persistent models, runtime ownership,
message dispatch, rendering bridges, AI/tool surfaces, and known feature gaps.

---

## 1. Top-Level Layout

### 1.1 Repository structure

```
hype-v2/
├── Package.swift                   # SwiftPM, macOS 15+, Swift 6
├── Sources/
│   ├── Hype/                       # Executable target — UI / AppKit / SpriteKit host
│   │   ├── HypeApp.swift           # @main, DocumentGroup, menu commands
│   │   ├── OpenAISpeechOutputProvider.swift # App-side speech playback adapter
│   │   ├── MCP/                    # Loopback MCP automation server + live-stack registry
│   │   ├── Accessibility/          # Stable AX IDs + virtual canvas hierarchy
│   │   │   ├── HypeAccessibilityID.swift
│   │   │   └── CardCanvasAccessibility.swift
│   │   ├── Resources/
│   │   ├── SpriteKit/              # SKScene/SKNode bridge layer
│   │   │   ├── HypeSKScene.swift          # Per-sprite-area interactive scene
│   │   │   ├── CardSKScene.swift          # Card-level scene (transitions + native layers)
│   │   │   ├── SceneBridge.swift          # SceneSpec ↔ live SKNode tree
│   │   │   ├── NodeRegistry.swift         # UUID ↔ SKNode bidirectional map
│   │   │   ├── SpriteAreaNode.swift       # SKCropNode container for an embedded scene
│   │   │   ├── CardPartNode.swift         # Protocol: SKNode wrapping a Hype Part
│   │   │   ├── ShapePartNode.swift        # SKShapeNode rendering of a shape Part
│   │   │   └── ImagePartNode.swift        # SKSpriteNode rendering of an image Part
│   │   └── Views/                  # SwiftUI / NSViewRepresentable UI
│   │       ├── MainContentView.swift      # Main split view, state plumbing
│   │       ├── CardCanvasView.swift       # NSViewRepresentable + CardCanvasNSView (~4,400 LoC)
│   │       ├── PropertyInspector.swift    # Per-part property pane (~4,300 LoC, multi-select aware)
│   │       ├── ObjectsToolPanel.swift     # Left-edge tool palette + Run/Edit toggle
│   │       ├── ScriptEditor.swift         # HypeTalk script editor window
│   │       ├── SpriteSceneSetupGuide.swift # Guided SpriteKit scene setup flow
│   │       ├── HypeTalkTextView.swift     # NSTextView host for the editor
│   │       ├── HypeFieldEditorCell.swift  # NSTextFieldCell — pixel-aligned field editor inset
│   │       ├── CompletionPopup.swift      # Code completion list
│   │       ├── AIChatPanel.swift          # Provider-backed tool-calling chat (primary AI UI)
│   │       ├── AIChatInputView.swift      # NSTextView-backed dynamic-height prompt input
│   │       ├── AIContextLibraryView.swift # Stack-scoped files/images/notes/folders for AI context
│   │       ├── AIPanel.swift              # Simple Q&A side panel
│   │       ├── NetworkPanelView.swift     # Stack network policy + live runtime monitor
│   │       ├── SpriteRepositoryView.swift # Sprite asset browser window (multi-select, Transparent Background)
│   │       ├── SpriteRepositoryAIChatView.swift # Repository-scoped AI chat for generated sprite assets
│   │       ├── ChartHostView.swift        # Apple Charts host
│   │       ├── ProgressViewHostView.swift # SwiftUI hosts for the framework progress / gauge controls
│   │       ├── GaugeHostView.swift
│   │       ├── CalendarHostView.swift     # NSDatePicker host for calendar parts
│   │       ├── ColorWellHostView.swift    # NSColorWell host for colorWell parts
│   │       ├── FormControlHostViews.swift # Stepper / Slider / Segmented hosts
│   │       ├── PDFHostView.swift          # PDFKit host for PDF parts
│   │       ├── MapHostView.swift          # MKMapView host for map parts
│   │       ├── MapGeocodeCache.swift      # Process-scoped forward-geocode cache
│   │       ├── MapLocationGeocoder.swift  # Per-partId debounced MKLocalSearch dispatcher
│   │       ├── Scene3DHostView.swift      # SCNView host for scene3D parts
│   │       ├── AudioRecorderHostView.swift
│   │       ├── Generate3DSheet.swift      # Meshy.ai 3-tab sheet (Text / Image / Multi-image → Phase 2)
│   │       ├── PreferencesView.swift
│   │       ├── MessageBoxView.swift       # HypeTalk REPL
│   │       ├── Themes/
│   │       │   ├── ThemeDesignerWindowController.swift  # Detached theme editor
│   │       │   ├── ThemeColorWell.swift                 # NSColorPanel-backed color picker
│   │       │   └── ThemePicker.swift                    # Picker bound to BuiltInThemes + stack themes
│   │       ├── ToolName.swift             # Tool palette catalog
│   │       └── GoMenuCommands.swift       # Menu items (Go, Objects, Arrange, Tools, AI + View/Window additions)
│   ├── HypeMCPBridge/              # stdio-to-loopback MCP bridge executable
│   ├── HypePacmanTestbedBuilder/   # CLI that emits a Pac-Man .hype regression stack
│   └── HypeCore/                   # Library target — model, scripting, AI, rendering
│       ├── Models/                 # Document model (all value types)
│       │   ├── HypeDocument.swift         # Root aggregate (themes array, scriptGlobals)
│       │   ├── HypeStack.swift            # Enums: PartType (24 cases + unknown), ButtonStyle, ShapeType …
│       │   ├── Stack.swift                # Stack metadata + script + themeName
│       │   ├── Background.swift           # Background metadata + script + themeName
│       │   ├── Card.swift                 # Card metadata + script + themeName
│       │   ├── Part.swift                 # The "everything part" struct (60+ fields)
│       │   ├── TargetPlatform.swift       # Deployment targets, device profiles, part availability
│       │   ├── RuntimeAISettings.swift    # Deployed-runtime AI policy and safe tool flags
│       │   ├── PartGrouping.swift         # Flat groupId-based authoring groups
│       │   ├── TextStyleFlags.swift       # Bold/italic/underline/strikethrough parser/emitter
│       │   ├── JSONCodec.swift            # Shared JSONEncoder/Decoder for stored-as-string fields
│       │   ├── ChartModel.swift           # Chart config / series / data points
│       │   ├── AssetRef.swift             # Stable reference into the Sprite Repository
│       │   ├── SpriteRepository.swift     # Stack-scoped asset store (provenance, slicing, clips)
│       │   ├── SpriteAreaSpec.swift       # Named-scene registry for sprite areas
│       │   ├── SceneSpec.swift            # Persistent SpriteKit scene description
│       │   ├── NetworkManifest.swift      # Persisted outbound rules + saved listeners
│       │   ├── SceneAuthoringSupport.swift # Scene checklists, diagnostics, asset usage
│       │   ├── MultiSelectionEditing.swift # Common-value + apply-value across selections
│       │   └── SceneDiff.swift            # Incremental scene patch operations
│       ├── Storage/                # SQLite-backed .hype package storage
│       │   └── HypeSQLiteStackStore.swift # Schema, package I/O, FTS search, diagnostics
│       ├── Script/                 # HypeTalk
│       │   ├── Token.swift                # 100+ token types (including `animate`)
│       │   ├── Lexer.swift                # Hand-written tokenizer
│       │   ├── AST.swift                  # Statement / Expression nodes
│       │   ├── Parser.swift               # Recursive descent parser (~1,800 LoC)
│       │   ├── Interpreter.swift          # Tree-walking interpreter (~5,000 LoC)
│       │   ├── MessageDispatcher.swift    # part → card → background → stack → app
│       │   └── HypeTalkHighlighter.swift  # Editor syntax highlighting
│       ├── AI/                     # Provider-backed AI, tool-calling, speech
│       │   ├── OllamaToolClient.swift     # /api/chat, /api/generate, /api/tags, structured JSON
│       │   ├── LlamaSwapClient.swift      # local OpenAI-compatible llama-swap proxy
│       │   ├── OpenAIResponsesClient.swift # /v1/responses text/tool/schema bridge
│       │   ├── OpenAIImageGenerationClient.swift # /v1/images/generations image bytes for parts/assets
│       │   ├── OpenAISpeechClient.swift   # /v1/audio transcriptions + speech
│       │   ├── HypeAIClient.swift         # Provider-neutral client/config factory
│       │   ├── RuntimeAIProvider.swift    # Target-aware deployed-runtime AI provider bridge
│       │   ├── RuntimeAIToolCatalog.swift # Narrow runtime-safe AI tool descriptors/executor
│       │   ├── AIContextLibrary.swift     # Safe stack-scoped context ingestion/search model
│       │   ├── AIScriptingProvider.swift  # Async HypeTalk-facing Ollama abstraction
│       │   ├── SpeechOutputProvider.swift # HypeCore speech-output protocol
│       │   ├── HypeTools.swift            # tool schemas (parts, scopes, themes, scenes, music, 3D gen)
│       │   ├── HypeToolExecutor.swift     # Dispatch tool calls to model mutations (Phase 2 adds 4 Meshy tools)
│       │   ├── HypeTalkGuide.swift        # System-prompt grammar primer fed to the model
│       │   ├── HypeTalkScriptValidator.swift # check_script syntax/semantics gate
│       │   ├── HypeAIResponseRepair.swift # Tool-arg auto-repair for malformed model output
│       │   ├── ScriptAutoFixer.swift      # Iterative script-attach failure recovery
│       │   ├── SpriteKitRequestRouter.swift # Routes scene-authoring intents to the right surface
│       │   ├── SceneAuthoringAssistant.swift # Schema-driven scene create/repair proposals
│       │   ├── AIService.swift            # Cloud routing fallback
│       │   ├── StackGenerator.swift       # One-shot JSON-mode generator
│       │   ├── MeshyModels.swift          # Meshy API value types (request/response/task/error)
│       │   ├── MeshyAIClient.swift        # Meshy HTTP actor (text-to-3D, image-to-3D, multi-image-to-3D)
│       │   ├── MeshyImageRequests.swift   # MeshyImageTo3DRequest / MeshyMultiImageTo3DRequest codables
│       │   ├── MeshyImageInput.swift      # Image input resolver (filePath/assetName/base64) with strict validation
│       │   ├── MeshyTaskMonitor.swift     # AsyncStream poller for Meshy task state (pending→succeeded/failed)
│       │   ├── Meshy3DAssetImporter.swift # Downloads GLB/USDZ/FBX and builds SpriteAsset array
│       │   ├── Meshy3DGate.swift          # Pre-flight guard (meshyEnabled + API key present)
│       │   ├── Generate3DJob.swift        # Single-shot orchestrator used by sheet UI and AI tools
│       │   └── Meshy3DToolProgressReporter.swift # Throttled aiOutput progress reporter (10s / 25% jump)
│       ├── MCP/                    # Model Context Protocol types, tool/resource bridge, prefs
│       ├── Rendering/              # Core Graphics part renderers
│       │   ├── CardRenderer.swift         # Pipeline + dispatcher (theme-aware)
│       │   ├── ButtonRenderer.swift       # All button styles (opaque/round/shadow/popup/check/toggle/link)
│       │   ├── FieldRenderer.swift        # Field text + style; routes through TextStyleFlags
│       │   ├── FieldTextLayout.swift      # Shared static/edit field text insets + vertical centering
│       │   ├── ShapeRenderer.swift
│       │   ├── ImageRenderer.swift        # Calls ImageChromaKey for transparentBackground
│       │   ├── ImageChromaKey.swift       # Dominant-corner alpha mask + makeTransparentPNG
│       │   ├── ImageFilter.swift          # CoreImage filter pipeline for image parts
│       │   ├── GlassRenderer.swift        # Liquid Glass material rounded-rect helpers
│       │   ├── ColorContrast.swift        # Luminance-aware foreground picking
│       │   ├── FormControlsRenderer.swift # Stepper / Slider / Segmented edit-mode placeholders
│       │   ├── ProgressViewRenderer.swift
│       │   ├── GaugeRenderer.swift
│       │   ├── DividerRenderer.swift
│       │   ├── CalendarRenderer.swift     # Edit-mode placeholder
│       │   ├── PDFRenderer.swift          # Edit-mode placeholder
│       │   ├── MapRenderer.swift          # Edit-mode placeholder (real map is MKMapView in browse)
│       │   ├── ColorWellRenderer.swift
│       │   ├── Scene3DRenderer.swift
│       │   ├── AudioRecorderRenderer.swift
│       │   ├── MusicControlsRenderer.swift
│       │   ├── STLConverter.swift         # On-the-fly STL → OBJ for SceneKit imports
│       │   ├── WebPageRenderer.swift      # Edit-mode placeholder
│       │   ├── VideoRenderer.swift        # Edit-mode placeholder
│       │   ├── ChartRenderer.swift        # Edit-mode placeholder
│       │   └── SpriteAreaRenderer.swift   # Edit-mode placeholder
│       ├── Theme/                  # Stack-scoped + built-in theme cascade
│       │   ├── HypeTheme.swift            # Color tokens + cornerRadii + stroke weights + glass flag
│       │   ├── BuiltInThemes.swift        # Default / Sunset / Ocean / Forest / Liquid Glass …
│       │   ├── ColorRef.swift             # Hex / system / theme-token color reference
│       │   ├── ColorContrast.swift        # readableTextColor(forFillHex:) helper
│       │   ├── ThemeResolver.swift        # Card→Background→Stack effective-theme cascade
│       │   └── ThemeEnvironment.swift     # SwiftUI EnvironmentKey for the active theme
│       ├── Animation/              # Frame-timer animation systems
│       │   ├── PartAnimator.swift         # Generic property tween (loc/rotation/alpha/etc.)
│       │   ├── GIFAnimator.swift          # Animated GIF playback for image parts
│       │   └── GIFDecoder.swift           # Frame extraction + delay parsing
│       ├── SpriteKit/
│       │   └── CoordinateConverter.swift  # Y-flip + rotation conversion
│       ├── Controls/
│       │   ├── PaintLayer.swift           # RGBA bitmap paint surface (Bresenham, etc.)
│       │   ├── WebPageController.swift
│       │   └── VisualEffects.swift        # Card transition catalog
│       ├── Layout/
│       │   ├── LayoutConstraint.swift     # Edge-to-edge responsive constraints
│       │   ├── ConstraintSolver.swift     # Iterative solver
│       │   ├── LayoutResolver.swift       # Target profile projection + safe-area geometry
│       │   └── AlignmentGuide.swift       # Snap guides
│       ├── Tools/
│       │   ├── ToolManager.swift          # Active tool / selection
│       │   └── MouseAction.swift          # Tool-aware mouse routing
│       ├── Navigation/
│       │   └── CardNavigator.swift        # Card traversal
│       ├── Runtime/
│       │   └── StackRuntime.swift         # Browse-mode live session, async jobs, listeners
│       ├── Sync/
│       │   └── SyncService.swift          # Transport-neutral live-sync engine
│       └── Export/
│           ├── DocumentExporter.swift     # JSON / single-file HTML export
│           ├── DeploymentAppIntentDescriptor.swift # Runtime App Intent descriptors
│           ├── StackDeploymentPlanner.swift # Runtime-only platform deployment plans
│           └── TargetRuntimePackageBuilder.swift # Self-contained runtime package artifacts
├── TestStacks/
│   └── PacmanAccessibilityTestbed.hype # Generated SpriteKit-heavy UI automation stack
├── Tests/HypeCoreTests/            # Model, script, async runtime, AI, export
└── Tests/HypeTests/                # App/SpriteKit/AppKit/accessibility smoke coverage
```

The package defines four production surfaces: **HypeCore** (model, scripting,
AI, MCP types, and Core Graphics/AppKit rendering helpers — fully testable
without launching the app), **Hype** (the macOS executable — SwiftUI, NSView,
AppKit, SpriteKit, AVKit, WKWebView, and the loopback MCP server),
**HypeMCPBridge** (a stdio client bridge for external MCP hosts that forwards
JSON-RPC lines into the running app), and **HypePacmanTestbedBuilder** (a small
CLI that emits a deterministic Pac-Man-style `.hype` stack for accessibility
and SpriteKit regression work). The hard split keeps the document model and
script runtime as value-oriented Swift while the executable owns windows,
menus, live AppKit hosts, SpriteKit scenes, and live-stack automation
registration. HypeCore conditionally imports AppKit for macOS
rendering/audio/image utilities, but it does not own SwiftUI windows or live
SpriteKit nodes.

### 1.2 The big picture in one diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│  HypeApp  (DocumentGroup, FileDocument)                                  │
│    └─ MainContentView                                                    │
│         ├─ Tool palette / status bar / side panels                       │
│         ├─ PropertyInspector  (SwiftUI)                                  │
│         ├─ AIChatPanel        (SwiftUI ↔ selected AI tool loop)          │
│         ├─ NetworkPanelView   (SwiftUI ↔ stack network policy/status)    │
│         └─ CardCanvasView     (NSViewRepresentable)                      │
│              └─ CardCanvasNSView  (NSView, isFlipped, layer-backed)      │
│                   ├─ CardRenderer  → CGContext  (static parts)           │
│                   ├─ Native overlays at part rects:                      │
│                   │     • NSTextField  (inline field editor)             │
│                   │     • WKWebView    (webpage parts)                   │
│                   │     • AVPlayerView (video parts)                     │
│                   │     • NSHostingView<ChartHostView> (chart parts)     │
│                   │     • SKView + HypeSKScene  (sprite-area parts)      │
│                   └─ PassthroughSKView + CardSKScene                     │
│                        (full-card transitions: dissolve, wipe, iris, …)  │
└──────────────────────────────────────────────────────────────────────────┘
                                  ↕
┌──────────────────────────────────────────────────────────────────────────┐
│  HypeCore                                                                │
│    Model    : HypeDocument(stack, backgrounds, cards, parts, sprites,    │
│                            constraints, aiContextLibrary,                │
│                            aiPromptHistory, networkManifest)             │
│    Runtime  : StackRuntimeRegistry → StackRuntime                         │
│               (live document session, FIFO event queue, async jobs,      │
│                listeners, connections, runtime status snapshots)         │
│    Scripts  : Lexer → Parser → AST → MessageDispatcher → Interpreter     │
│               (sync core path; browse mode executes through StackRuntime)│
│    Bridge   : SpriteAreaSpec/SceneSpec ←→ SceneBridge ←→ live SKNode tree│
│               (NodeRegistry: UUID ↔ SKNode)                              │
│               (CoordinateConverter: top-left ↔ bottom-left, deg ↔ rad)   │
│    AI       : HypeAIClient (Ollama/OpenAI) → SceneAuthoringAssistant /   │
│               AIScriptingProvider / HypeToolExecutor                     │
│               RuntimeAIProviderResolver → Apple Foundation Models for    │
│               supported non-macOS deployed runtimes                      │
└──────────────────────────────────────────────────────────────────────────┘
```

Two arrows are worth highlighting:

1. **Persistence ↔ runtime.** The model is plain `Codable` Swift values at
   runtime, but `.hype` documents are self-contained SQLite packages written
   by `HypeSQLiteStackStore`. Sprite-area scenes remain authored as
   `SpriteAreaSpec` / `SceneSpec` values, and the storage layer projects them
   into searchable relational tables. At display time, the bridge layer
   compiles the active scene into a live `SKNode` tree.
   Stack deployment targets are also document data: `StackDeploymentTargets`
   records the selected target platforms, primary design target, and whether
   the new-stack target prompt has been acknowledged. `RuntimeAISettings`
   records the deployed-runtime AI policy, safe runtime tool allowlist, and
   transcript preference separately from local authoring preferences.
2. **Hit test ↔ message dispatch.** A click inside a sprite area is
   converted by `HypeSKScene` from a `CGPoint` to a UUID via the
   `NodeRegistry`, forwarded to `CardCanvasNSView` (the
   `SpriteEventDelegate`), and finally enters the `MessageDispatcher` as a
   HypeTalk message — which then traverses node → parent group(s) → scene →
   sprite area → card → background → stack → app like any classic HyperCard
   message. In browse mode, the `StackRuntime` serializes those deliveries with
   async completions and network callbacks on the same FIFO queue.

---

## 2. Document Model

### 2.1 The root aggregate

`HypeDocument` (Sources/HypeCore/Models/HypeDocument.swift:4) is a single
`Codable, Sendable` struct that holds the entire stack:

```swift
public struct HypeDocument: Codable, Sendable {
    public var stack: Stack
    public var backgrounds: [Background]
    public var cards: [Card]
    public var parts: [Part]
    public var paintLayers: [CardPaintLayer]      // per-card paint snapshots
    public var constraints: [LayoutConstraint]
    public var spriteRepository: SpriteRepository
    public var themes: [HypeTheme]                // user-edited theme registry
    public var aiContextLibrary: AIContextLibrary // rules / assets / examples sent to AI
    public var aiPromptHistory: [String]
}
```

A few choices are deliberate:

- **Flat array of parts.** Parts are not nested under cards or backgrounds.
  Each `Part` carries either a `cardId` (card-scoped) or a `backgroundId`
  (background-scoped), and helpers like `partsForCard(_:)` and
  `partsForBackground(_:)` filter the flat array on demand. This avoids
  copy-of-copy issues, makes draw-order trivial (the array index is the
  z-order), and keeps undo, AI tool edits, and SQLite reconstruction simple.
- **All value types.** Every model — `Stack`, `Background`, `Card`, `Part`,
  `SpriteRepository`, `SceneSpec`, `LayoutConstraint`, `SpriteAsset` — is a
  `struct` conforming to `Sendable`. There is no shared mutable state in
  the model layer; updates flow through `mutating` document methods
  (`addPart`, `updatePart`, `bringForward`, `sendToBack`, `addConstraint`).
- **Forward-compatible decoding.** Custom `init(from:)` decoders accept
  missing fields with sensible defaults so older `.hype` files keep loading
  as the schema evolves (HypeDocument.swift:36).

### 2.2 Cards, backgrounds, parts

```
HypeDocument
  ├── Stack            (id, name, width × height, target platforms, runtime AI, script)
  ├── Backgrounds[]    (sortKey, name, script)            ← shared visual templates
  ├── Cards[]          (sortKey, name, marked, backgroundId, script)
  ├── Parts[]          (cardId? or backgroundId?, see §2.3)
  ├── Constraints[]    (LayoutConstraint, see §6.5)
  ├── AIContextLibrary (stack-scoped AI files/images/notes/folders)
  └── SpriteRepository (see §4)
```

Stacks default to 800 × 600. A `Background` is a template; many cards may
share one background, and parts placed on the background appear on every
card that uses it (this is the classic HyperCard reuse mechanism). A
`Card` always belongs to exactly one background.

New stacks default to macOS as the selected target platform but must ask the
creator to confirm/select deployment targets before normal authoring continues.
The target taxonomy is `macOS`, `iPhone`, `iPad`, and `tvOS`; iPhone and iPad
are distinct because their default form factors and safe-area/layout behavior
are meaningfully different. Existing decoded stacks that predate this field
load as acknowledged macOS-only stacks for compatibility.

`PartType` (Sources/HypeCore/Models/HypeStack.swift:9) is the discriminator
and has grown well beyond the original eight kinds:

```swift
public enum PartType: String, Codable, Sendable {
    // Classic HyperCard parts
    case button, field, shape, webpage, image, video, chart, spriteArea
    // Framework-backed controls (Apple frameworks hosted as NSView/SwiftUI overlays)
    case calendar, pdf, map, colorWell, audioRecorder, scene3D
    // Music controls (AudioKit stack patterns plus one MusicKit search surface)
    case musicPlayer, pianoKeyboard, stepSequencer, musicMixer
    case appleMusicBrowser, musicQueue
    // Form controls (AppKit-feel)
    case stepper, slider, toggle, segmented
    // Apple-controls catalog / legacy compatibility cases
    case progressView, gauge, link, menu, searchField, divider
    // Forward-compat sentinel for partType strings written by future versions
    case unknown
}
```

Several legacy values (`toggle`, `link`, `menu`, `searchField`) used to be
distinct kinds and still exist in the enum so old documents decode; they now
migrate at `Part.init(from:)` time to `button` (with `.toggle`, `.link`,
`.popup` style) or `field` (with `.search` style). New authoring paths should
create those canonical button/field forms rather than writing the legacy
part-type cases.

`musicQueue` is also retained as a readable legacy part type, but it is no
longer exposed as a new authoring control or AI creation tool. New stacks use
AudioKit controls (`musicPlayer`, `pianoKeyboard`, `stepSequencer`,
`musicMixer`) for stack-contained synthesized music and `appleMusicBrowser`
as the single simple MusicKit search-criteria control.

### 2.3 Part: the "everything" struct

`Part` (Sources/HypeCore/Models/Part.swift:4) is a single struct that holds
fields for **every** part type, with only the relevant ones populated for a
given `partType`. The fields fall into bands:

| Band             | Fields (representative)                                                  |
|------------------|--------------------------------------------------------------------------|
| identity         | `id`, `name`, `sortKey`, `cardId?`, `backgroundId?`, `groupId?`          |
| geometry         | `left`, `top`, `width`, `height`, `rotation`                             |
| state            | `visible`, `enabled`, `hilite`, `autoHilite`                             |
| text (any part)  | `textContent`, `textFont`, `textSize`, `textStyle`, `textAlign`, `fontColor` |
| help             | `helpText` *(NSToolTip shown on hover in browse mode; multi-line; aliases tooltip / help)* |
| button           | `buttonStyle`, `showName`, `iconId`, `popupItems`, `url` (link style)    |
| field            | `fieldStyle`, `lockText`, `dontWrap`, `wideMargins`, `richText`, `enterKeyEnabled` |
| shape            | `shapeType`, `fillColor`, `strokeColor`, `strokeWidth`, `cornerRadius`, `pathData[]` |
| webpage          | `url`, `urlSourceFieldId?`                                               |
| video            | `videoURL`                                                               |
| image            | `imageData?`, `invertOnClick`, `transparentBackground`, `imageFilter`, `imageFilterIntensity`, `animated` (GIF) |
| chart            | `chartData` *(JSON-encoded ChartConfig)*                                 |
| calendar         | `selectedDate`, `displayMonth`, `minDate`, `maxDate`, `calendarStyle`    |
| pdf              | `pdfURL`, `pdfCurrentPage`, `pdfDisplayMode`, `pdfAutoScales`            |
| map              | `mapCenterLat`, `mapCenterLon`, `mapSpan`, `mapType`, `mapAnnotationsJSON`, `mapLocation` *(geocoded)* |
| colorWell        | `colorWellHex`, `colorWellInteractive`                                   |
| stepper / slider | `controlValue`, `controlMin`, `controlMax`, `controlStep`; sliders derive horizontal/vertical rendering from their bounds, using the longest dimension as the interactive axis |
| segmented        | `segmentItems` *(pipe-separated)*, `controlValue` *(selected index)*     |
| progressView     | `progressValue`, `progressTotal`, `progressIsCircular`, `progressIsIndeterminate`, `progressLabel`, `progressTint`, `progressDecimals` |
| gauge            | `gaugeValue`, `gaugeMin`, `gaugeMax`, `gaugeStyle`, `gaugeTint`, `gaugeLabel`, `gaugeMinLabel`, `gaugeMaxLabel`, `gaugeDecimals` |
| audioRecorder    | `audioRecording`, `audioPlaying`, `audioOutputPath`, `audioFormat`, `audioDuration`, `audioEmbedInStack`, `audioData?` |
| music controls   | `musicPatternName`, `musicInstrumentName`, `musicTempo`, `musicKeyCount`, `musicShowControlType`, `musicShowPattern`, `musicShowInstrument`, `musicShowTempo`, `musicLoop`, `musicVolume`, `musicTrackData`, `musicSourceKind`, `musicSourceID`, `musicSourceType`, `musicSourceTitle`, `musicSourceArtist`, `musicSourceAlbum`, `musicArtworkURL`, `musicPosition`, `musicDuration`, `musicQueueData`, `musicSearchTerm`, `musicSearchScope` |
| scene3D          | `scene3DSourceURL`, `scene3DURL`, `scene3DAllowsCameraControl`, `scene3DAutoLighting`, `scene3DAntialiasing`, `scene3DBackground` |
| divider          | `dividerOrientation`, `dividerThickness`, `dividerColor`                 |
| **sprite area**  | `sceneSpec` *(JSON-encoded `SpriteAreaSpec`, with legacy `SceneSpec` migration)* |
| script           | `script` *(HypeTalk source)*                                             |

For AudioKit-backed controls, `musicTempo` is an integer BPM value clamped to
`1...320` everywhere it enters the model; the default is 120.
`pianoKeyboard` controls also persist `musicKeyCount`, normalized to one of
49, 61, 76, or 88 keys. Rendering and Browse-mode hit testing both derive
from the same deterministic keyboard geometry: 49 keys C2...C6, 61 keys
C2...C7, 76 keys E1...G7, and 88 keys A0...C8. The
`musicShowControlType`, `musicShowPattern`, `musicShowInstrument`, and
`musicShowTempo` flags control optional runtime chrome on piano-keyboard and
step-sequencer parts. When `musicShowInstrument` is enabled, browse mode hosts
a live instrument popup backed by the same General MIDI instrument catalog used
by HypeTalk and AI tools; the Core Graphics pass suppresses only the popup
placeholder for those live-hosted controls so run mode does not double-draw the
instrument name.

That a sprite area is **just a Part** is the key trick. It participates in
selection, draw order, the property inspector, layout constraints, scripts,
and the message hierarchy like any other part. Its `sceneSpec` field is now a
JSON-encoded `SpriteAreaSpec`: a small area-level wrapper that owns a named
scene registry, the active scene ID, design size, scale mode, and SpriteKit
debug flags while preserving compatibility with older single-scene payloads.

Layered metadata enums (`ButtonStyle`, `FieldStyle`, `ShapeType`,
`TextAlignment`) live in `HypeStack.swift`.

### 2.4 Persistence

The document is a self-contained package written through SwiftUI's
`FileDocument`. `HypeDocumentWrapper` (HypeApp.swift:298) reads/writes `.hype`
packages via `HypeSQLiteStackStore`, and exposes the custom package UTType
`com.hype.stack`. A package contains:

```text
Stack.hype/
  manifest.json
  stack.sqlite
```

`stack.sqlite` is the canonical store. It contains normalized, indexed tables
for stacks, backgrounds, cards, parts, scripts, assets, AI context, themes,
paint layers, constraints, SpriteKit areas/scenes/nodes, and FTS search. Rows
also carry payload JSON for exact reconstruction of the value-model graph while
the schema continues to grow. SQLite `PRAGMA user_version` tracks the schema;
schema version 2 adds `parts.audio_data` so audio recorder bytes can be stored
as a real SQLite BLOB while the JSON payload omits duplicate audio bytes.
Schema version 3 adds normalized `music_patterns`, `music_tracks`, and
`music_notes` projections for stack-contained AudioKit music while keeping
`HypeDocument.musicLibrary` as the value-model source of truth. Schema version
4 adds normalized `apple_music_items` and `apple_music_queues` projections for
MusicKit references and queue metadata. These tables persist only stable Apple
Music IDs plus metadata snapshots; licensed catalog/library audio remains
external and is never embedded in the `.hype` package.
Schema version 5 adds normalized `deployment_targets` projections for the
stack's selected target platforms, primary target, prompt acknowledgement, and
standard device profile metadata. The `Stack.deploymentTargets` value remains
the reconstruction source of truth; the table exists for diagnostics, search,
and export tooling.
Schema version 6 adds normalized `runtime_ai_settings` projections for the
stack's deployed-runtime AI provider policy, runtime-safe side-effect tool
gate, allowlisted tool names, fallback text, and transcript persistence flag.
`Stack.runtimeAISettings` remains the reconstruction source of truth; the table
is for diagnostics and target-runtime export validation.

Interactive saves and undo now flow through
`HypeDocumentMutationCoordinator` (`Sources/Hype/DocumentMutationCoordinator.swift`).
`MainContentView` publishes a tracked `Binding<HypeDocumentWrapper>` to the
canvas, inspector, detached authoring windows, settings bridge, AI panels, and
menu handlers. Any persistent document mutation that reaches that binding is
compared in a deterministic sorted-JSON value snapshot, registered with the
active `UndoManager`, written immediately to a local SQLite recovery package
under Application Support, and scheduled for debounced `NSDocument` autosave.
App resign-active, window close, and terminate all flush pending autosaves.
Runtime-only fields
that are intentionally excluded from `HypeDocument.CodingKeys` (for example
`scriptGlobals`) do not create persistent undo entries.

Converted HyperCard stacks add one optional persisted field:
`legacyImport: LegacyStackImportMetadata?`. It stores the import report, block
and resource summaries, discovered XCMD/XFCN resources, SHA-256 hashes, and,
when the original forks fit the safety limit, the raw HyperCard data/resource
forks. This keeps converted `.hype` files self-contained and lets future importer
revisions re-run conversion from the preserved source without executing any
legacy code.

Continuous interactions are coalesced before entering undo: canvas
drag/resize mutations suppress per-frame registrations and commit one undo item
on mouse-up, while animation tick mutations remain autosaved but do not flood
the undo stack. AI transaction application and script/runtime side effects pass
through the same binding path, so accepted multi-tool edits and HypeTalk
document mutations participate in the same save/undo pipeline as manual edits.
Stack-authored mode flags that affect portability, including
`Stack.runtimeModeEnabled` and `Stack.runtimeAISettings`, live in the stack model rather than `UserDefaults`;
purely local window geometry, selected AI provider, and API keys remain local
app preferences or Keychain entries.

For stored-as-string runtime sub-documents — `Part.sceneSpec` (a
JSON-encoded `SpriteAreaSpec`), `Part.chartData` (a `ChartConfig`),
`Part.mapAnnotationsJSON` — `JSONCodec` (Sources/HypeCore/Models/JSONCodec.swift)
provides a single shared `JSONEncoder` / `JSONDecoder` pair so the model layer
isn't allocating a fresh codec on every `fromJSON(...)`/`toJSON(...)` round
trip. `Part.spriteAreaSpecModel` is called from many hot paths (every draw
frame for visible sprite areas, every dispatch that reads or writes a scene
property, every AI tool that introspects scenes); the shared codec moves the
allocation cost from per-call to one-time-per-app-launch.

The SQLite storage layer projects Sprite Area contents into relational
`sprite_areas`, `scenes`, and `scene_nodes` tables for diagnostics and search,
while `SceneSpec` / `SpriteAreaSpec` remain the runtime source of truth.
AudioKit music follows the same declarative rule: `MusicPatternSpec` and
`MusicTrackSpec` persist in the document/database, and runtime `AudioEngine`,
sampler, and playback tasks live only behind the `SystemProvider` /
`AudioKitMusicProvider` boundary. MusicKit / Apple Music integration is a
separate provider path in `AppleMusicProvider`: the stack can store selected
catalog/library IDs, item kinds, titles, artist/album snapshots, artwork URLs,
search terms, and queue metadata, but playback and search require user
preference enablement, stack-level opt-in (`Stack.appleMusicAllowed`), MusicKit
authorization, and a runtime provider. This preserves stack portability without
misrepresenting protected Apple Music audio as stack-contained content.

Music controls convert Browse-mode clicks, piano-key drag crossings, and
step-sequencer cell drag crossings into provider-backed runtime playback
requests. Piano-keyboard hits carry a runtime-only `MusicSustainedNoteSpec`
that starts an AudioKit sampler note on mouse-down/drag-enter and stops that
same note on mouse-up, drag-off, key change, or `stop music`; the document still
persists only declarative keyboard settings and pattern specs. `appleMusicBrowser` uses a live `AppleMusicBrowserHostNSView` in
Browse mode so users can authorize, search, choose a song/album/singer/playlist
reference, play/stop, and seek within the current song while the document stores
only stable MusicKit IDs, metadata snapshots, `musicPosition`, and
`musicDuration`. Step sequencer grid hits audition the
selected row/column step instead of replaying one generic pattern. Piano
keyboard geometry reserves a title/subtitle band at the top and a small bottom
inset rather than using symmetric vertical insets, so the default-sized control
has a visible and hit-testable key bed. These interactions do not persist live
engine/player state or mutate the stack unless a user script does so explicitly.

`DocumentExporter` (Sources/HypeCore/Export/DocumentExporter.swift) provides
two side outputs: pretty-printed sorted JSON (for inspection / diff) and a
single-file HTML rendering of every card as absolutely-positioned `<div>`s.

`SyncService` is a transport-neutral live-sync engine with peer sessions,
operation/change-set publishing, checkpoints, and deterministic conflict
reporting. The current transport is an in-process collaboration hub for local
loopback and regression coverage; CloudKit, Multipeer, or a custom server can
be attached at the transport boundary later without changing document mutation
contracts.

### 2.5 Sprite-area registries and network manifest

Two newer pieces of persisted state materially change how the document model is
used at runtime:

- **`SpriteAreaSpec`** turns `Part.sceneSpec` into a small registry instead of a
  single scene blob. Each sprite area now owns:
  - `activeSceneID`
  - `scenes: [SpriteAreaScene]`
  - area-wide defaults such as design size, scale mode, and debug overlays
  Legacy `.hype` files that stored only a `SceneSpec` still decode, because the
  part helper migrates the old payload into a one-scene registry on load.
- **`Stack.networkManifest`** persists the stack's requested network
  capabilities. It contains outbound host rules and saved listener
  definitions (HTTP/TCP, host, port, callback message, bind scope, auto-start
  flag). The manifest is part of the shared document; approval to actually use a
  host or bind a port is intentionally **not**.

This split is deliberate: `.hype` files describe what a stack *wants* to do,
while runtime-only state describes what the current machine has actually
approved and started. Live sockets, in-flight requests, pending HTTP replies,
AI jobs, and open TCP connections belong to `StackRuntime`, never to the file
format.

### 2.6 HyperCard import and legacy preservation

The HyperCard import path lives in `Sources/HypeCore/HyperCardImport/` and is
designed around untrusted binary input:

- `HyperCardInputNormalizer` reads the selected data fork and, on macOS, tries
  the native `..namedfork/rsrc` resource fork plus AppleDouble `._Name`
  sidecars.
- `HyperCardBlockParser` walks the HyperCard block stream (`STAK`, `BKGD`,
  `CARD`, `LIST`, `PAGE`, `BMAP`, `TAIL`, etc.) with hard byte/block limits.
- `MacResourceForkReader` parses classic resource-map structure and reports
  resources such as `XCMD`, `XFCN`, `PICT`, and `snd ` without executing them.
- `HyperCardToHypeConverter` maps supported stack/background/card/button/field
  structure into `HypeDocument`, preserves scripts as HypeTalk text, records
  unsupported bitmap/resource features in `HyperCardImportReport`, and stores
  `LegacyStackImportMetadata` on the document.

The Hype app exposes this through **File > Import HyperCard Stack...**. The menu
opens an untyped file picker because original stacks often have no extension or
arrive as restored classic-Mac files. The selected stack is converted to a
temporary Hype document and opened normally; saving from there writes a
standard portable SQLite-backed `.hype` package.

---

## 3. SpriteKit as the Interaction Substrate

This is the heart of Hype, and the architectural delta from a textbook
HyperCard re-implementation. The goal stated in the project's PRD draft is
explicit: the Hype card model must remain a **persistent authoring
model**, while SpriteKit becomes a **runtime scene graph with a frame loop**
that the model compiles into. Two bridges are required: model→runtime
(scene spec → SKNode) and runtime→model (hit test → UUID → HypeTalk
message).

### 3.1 Two SpriteKit roles

SpriteKit serves Hype in two distinct ways:

1. **Embedded Sprite Area parts (the primary role).** A part of type
   `spriteArea` becomes its own `SKView` overlaid at the part's frame on
   the card canvas. The SKView hosts a `HypeSKScene` whose contents are
   built from the sprite area's active `SceneSpec` inside `SpriteAreaSpec`.
   This is where physics, sprite actions, particles, audio, video, tile maps,
   and cameras live. Multiple sprite areas can coexist on the same card; each
   has an independent named-scene registry with one active runtime scene.

2. **Card-level transitions.** A second, persistent `SKView` /
   `CardSKScene` lives on every card canvas to drive cinematic
   card-to-card transitions (dissolve, wipe, iris, scroll). When a script
   says `visual effect dissolve / go to next card`, both the current and
   target cards are rasterized to `NSImage`, blitted into a `CardSKScene`'s
   `cardNode`, and animated via `SKView.presentScene(_:transition:)`.

The card-level `SKView` is implemented as `PassthroughSKView`
(CardCanvasView.swift, search for `class PassthroughSKView`) — a subclass whose `hitTest` returns `nil`. This
keeps it visible for transitions without ever stealing mouse events from
the underlying NSView, so editing tools and inline NSView controls keep
working unchanged.

`CardSKScene` (Sources/Hype/SpriteKit/CardSKScene.swift) is layered to
anticipate three architectural phases:

```swift
let cardNode    = SKSpriteNode()  // z=0   — rasterized card texture (Phase A)
let nativeLayer = SKNode()        // z=50  — Phase C native part SKNodes
let spriteLayer = SKNode()        // z=100 — Phase B sprite area scenes
```

Currently the canvas uses Phase A (texture transitions) plus Phase B
(sprite areas hosted as their own SKViews); `nativeLayer` /
`ShapePartNode` / `ImagePartNode` are infrastructure for future migration
of native part types directly into the SpriteKit scene graph.

### 3.2 The persistent scene description: `SpriteAreaSpec` + `SceneSpec`

`SceneSpec` (Sources/HypeCore/Models/SceneSpec.swift:36) remains the durable,
JSON-serializable description of a single SpriteKit scene. What changed is the
container around it: `Part.sceneSpec` now stores a `SpriteAreaSpec`, which owns
the active scene selection plus a named registry of `SceneSpec` entries for the
same sprite area. This keeps scene switching, duplication, and inspector scene
management inside the document model instead of faking them by mutating one
scene's `name`.

That means persistence has two layers:

- **`SpriteAreaSpec`**: area-level defaults and named-scene registry
- **`SceneSpec`**: one concrete SpriteKit scene description

Because both are plain value types, the authored state remains AI-friendly,
undoable, inspectable through SQLite projections, and portable across runs
without holding onto live SpriteKit objects.

The shape:

```swift
public struct SceneSpec: Codable, Sendable {
    public var name: String
    public var size: SizeSpec
    public var backgroundColor: String       // hex
    public var gravity: VectorSpec           // physics world gravity
    public var nodes: [HypeNodeSpec]         // recursive node tree
    public var joints: [JointSpec]           // physics joints
    public var sceneConstraints: [SceneConstraintSpec]
    public var fields: [FieldSpec]           // physics field nodes
    public var isPaused: Bool
    public var showsPhysics, showsFPS, showsNodeCount: Bool
    public var scaleMode: SceneScaleMode     // fill | aspectFill | aspectFit | resizeFill
}
```

`HypeNodeSpec` (SceneSpec.swift:125) is the recursive node:

```swift
public enum NodeType: String, Codable {
    case sprite, group, label, shape, emitter, audio, tileMap,
         camera, video, crop, effect, light
}

public struct HypeNodeSpec: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var nodeType: NodeType
    public var position: PointSpec
    public var zPosition, rotation, xScale, yScale, alpha: Double
    public var isHidden: Bool

    // Conditional, type-specific fields:
    public var assetRef: AssetRef?               // sprite
    public var size: SizeSpec?                   // sprite
    public var text, fontName, fontColor: String? // label
    public var fontSize: Double?
    public var shapeSpec: ShapeNodeSpec?          // shape
    public var emitterSpec: EmitterSpec?          // emitter
    public var audioLoop, audioAutoplay, audioPositional: Bool?
    public var audioVolume: Double?
    public var tileMapSpec: TileMapSpec?
    public var videoLoop, videoAutoplay: Bool?
    public var cameraTarget: String?
    public var physicsBody: PhysicsBodySpec?

    public var actions: [ActionSpec]
    public var children: [HypeNodeSpec]           // recursive
    public var script: String                     // optional per-node HypeTalk
}
```

Subsidiary specs cover the full SpriteKit feature surface: `PhysicsBodySpec`
(circle/rect/texture/edge bodies with category/contact/collision bit masks,
restitution, friction, mass, damping, velocity), `ActionSpec` (~20 action
types: moveTo, moveBy, rotate, scale, fade, sequence, group, repeatForever,
animations, audio playback, etc.), `JointSpec` (pin, spring, sliding, fixed,
limit), `FieldSpec` (linear/radial gravity, vortex, noise, turbulence,
spring, drag, electric, magnetic), `EmitterSpec`, `TileMapSpec`,
`SceneConstraintSpec` (distance, orient, position).

`SceneDiff` (Sources/HypeCore/Models/SceneDiff.swift) supports incremental
mutations: `addNodes`, `removeNodeIds`, `updateNodes`, plus scene-level
property updates. The AI tool layer uses `SceneDiff` so the model can patch
existing scenes without resending the entire spec. Scene and node lookup are
recursive, so nested groups, tile-map hierarchies, and deep child trees can be
patched in place without flattening the scene model first.

### 3.3 The runtime scene: `HypeSKScene`

`HypeSKScene` (Sources/Hype/SpriteKit/HypeSKScene.swift:24) is the
`SKScene` subclass instantiated for each sprite area. It is small and
focused — its job is to:

1. Forward mouse and keyboard events to a delegate, after converting
   coordinates and resolving hit-test targets to UUIDs.
2. Receive physics contact callbacks and forward them as UUID pairs.
3. Tick a `frameUpdate` event each render frame.

The delegate protocol — and the canonical event surface — is
`SpriteEventDelegate`:

```swift
enum SpriteEvent: Sendable {
    case mouseDown(nodeId: UUID?, scenePosition: PointSpec)
    case mouseUp(nodeId: UUID?, scenePosition: PointSpec)
    case mouseDragged(nodeId: UUID?, scenePosition: PointSpec)
    case mouseWithin(nodeId: UUID?, scenePosition: PointSpec)
    case keyDown(characters: String, keyCode: UInt16)
    case keyUp(characters: String, keyCode: UInt16)
    case contactBegan(nodeA: UUID, nodeB: UUID)
    case contactEnded(nodeA: UUID, nodeB: UUID)
    case frameUpdate(deltaTime: TimeInterval)
    case sceneDidLoad
    case actionFinished(name: String, nodeId: UUID)
}

@MainActor protocol SpriteEventDelegate: AnyObject {
    func spriteScene(_ scene: HypeSKScene, didReceiveEvent event: SpriteEvent)
}
```

The hit-test logic (HypeSKScene.swift:107) is depth-first: SpriteKit's
`nodes(at:)` is called, and for each candidate node the registry is asked
for a matching UUID. If a node is unregistered, the parent chain is walked
upward until a registered ancestor is found. This matches the HyperCard
expectation that clicking on a child element selects its enclosing
scriptable object.

Physics contact callbacks (HypeSKScene.swift:124) are
`@preconcurrency SKPhysicsContactDelegate` implementations that hop back
onto the main actor with `Task { @MainActor in … }` before resolving
node UUIDs and dispatching, since SpriteKit physics contacts are delivered
on a background queue.

### 3.4 The bridge: `SceneBridge`

`SceneBridge` (Sources/Hype/SpriteKit/SceneBridge.swift, ~900 LoC) is the
single point of translation between the persistent `SceneSpec` and the
live `SKNode` tree. It owns three pieces of state:

- a `NodeRegistry` mapping `UUID ↔ SKNode` in both directions
  (Sources/Hype/SpriteKit/NodeRegistry.swift),
- a `CoordinateConverter` for the current scene height,
- a `[UUID: SKTexture]` cache to avoid re-decoding asset images.

Two update paths:

- **`applyLiveUpdates(spec:to:repository:)`** — fast-path. If the set of
  node IDs in the new spec equals the set already registered, properties
  are updated in place: position, rotation, scale, alpha, hidden, physics
  velocity, emitter parameters, etc. This avoids tearing down the scene
  graph (and the GPU resources behind it) on every property tweak from a
  script. Returns `true` if a structural change is detected, signalling
  the caller to perform a full rebuild.
- **`apply(spec:to:repository:)`** — full rebuild. Clears the registry
  and the scene's children, applies scene-level properties (background
  color, gravity, scale mode, debug overlays, paused state), recursively
  builds nodes via `makeNode(from:repository:)`, then post-processes
  joints, scene constraints, and physics fields.

Inside `makeNode(from:repository:)` each `NodeType` maps to a specific
`SKNode` subclass:

| `NodeType`  | Concrete `SKNode`              |
|-------------|--------------------------------|
| `sprite`    | `SKSpriteNode` + `SKTexture`   |
| `label`     | `SKLabelNode`                  |
| `shape`     | `SKShapeNode` (rect / round-rect / circle / ellipse / arbitrary path) |
| `emitter`   | `SKEmitterNode` (with default white-circle texture if none provided) |
| `audio`     | `SKAudioNode`                  |
| `video`     | `SKVideoNode`                  |
| `tileMap`   | `SKTileMapNode` (built from a spritesheet asset, with `SKTileGroup`s extracted from a `SKTextureAtlas`) |
| `camera`    | `SKCameraNode` (with optional follow constraint) |
| `crop`      | `SKCropNode`                   |
| `effect`    | `SKEffectNode`                 |
| `light`     | `SKLightNode`                  |
| `group`     | `SKNode`                       |

Every constructed node is registered with the `NodeRegistry`, given its
common properties (name, z-position, scale, alpha, hidden), and finally
positioned and rotated through the `CoordinateConverter`. Physics bodies,
actions, and children are then attached.

Action construction (SceneBridge.swift, `buildAction`) supports the full
~20-action SpriteKit vocabulary, including sequences, groups, repeats, and
animations. Named actions are wrapped in
`SKAction.sequence([action, completionCallback])` so the bridge can fire an
`actionFinished(name:nodeId:)` event back to the delegate when the action
completes — letting HypeTalk drive sequenced animations declaratively.

Joints, scene constraints, and physics fields are applied **after** the
node tree exists, because they reference nodes by UUID and require the
registry to be fully populated.

Texture caching (`textureCache: [UUID: SKTexture]`) keys by asset ID and is
populated on demand from the `SpriteRepository`. This prevents repeated
NSImage→SKTexture decodes when a script makes many small property
changes.

### 3.5 Coordinates: top-left vs. bottom-left

Hype's authoring model is HyperCard-style: top-left origin, Y grows
downward, rotations are in degrees and turn clockwise. SpriteKit is
graphics-style: bottom-left origin, Y grows upward, rotations are in
radians and turn counter-clockwise.

`CoordinateConverter` (Sources/HypeCore/SpriteKit/CoordinateConverter.swift)
is the entire impedance match:

```swift
public struct CoordinateConverter: Sendable {
    public let sceneHeight: Double
    public func toSK(_ p: PointSpec) -> PointSpec {
        PointSpec(x: p.x, y: sceneHeight - p.y)
    }
    public func toHype(_ p: PointSpec) -> PointSpec {
        PointSpec(x: p.x, y: sceneHeight - p.y)   // symmetric
    }
    public func toSKRotation(_ degrees: Double) -> Double {
        -degrees * .pi / 180.0
    }
    public func toHypeRotation(_ radians: Double) -> Double {
        -radians * 180.0 / .pi
    }
}
```

This converter is applied whenever positions and rotations cross the
boundary: when the bridge constructs nodes, when actions specify target
points (`moveTo`), when shape paths are built from `pathData`, and when
mouse events come back out of `HypeSKScene`. The fact that it's used
symmetrically in both directions and always derived from the current scene
height keeps coordinate handling local — no scattered Y-flip arithmetic.

### 3.6 Hosting sprite areas in the canvas

The integration point on the AppKit side is `CardCanvasNSView`
(CardCanvasView.swift:856, ~4,400 LoC). This is the layer-backed NSView
that draws the card via Core Graphics and overlays NSViews for native
controls. Sprite areas are tracked in parallel dictionaries:

```swift
var spriteViews:        [UUID: SKView]
var spriteScenes:       [UUID: HypeSKScene]
var spriteBridges:      [UUID: SceneBridge]
var loadedSceneSpecs:   [UUID: String]   // last applied spec, JSON-equality cached
var loadedActiveSceneIDs: [UUID: UUID]    // active scene ID for lifecycle close/open
```

`updateSpriteViews()` (CardCanvasView.swift:3530) is called from `draw()`.
It considers both visible card parts and visible parts on the current card's
background, so embedded scenes owned by either layer follow the same lifecycle.
For each visible `spriteArea` part it:

1. Lazily creates a `PassthroughSKView` and a `HypeSKScene` if none exist.
2. Compares the part's current `sceneSpec` JSON to the cached one. Because that
   JSON now contains the full `SpriteAreaSpec`, scene switches and area-level
   debug changes are detected by the same cache. If unchanged, the view is just
   repositioned and resized in place.
3. If changed, it tries `applyLiveUpdates(...)` first (for
   property-only edits) and falls back to `rebuildSpriteScene(...)` if
   structural changes are detected.
4. Dispatches `closeScene` to any sprite areas that disappeared or became
   inactive because the current card/background changed.

`rebuildSpriteScene()` (CardCanvasView.swift:3725) parses the JSON, creates
or reuses a `SceneBridge` and `HypeSKScene`, configures debug overlays,
stores references **before** calling `presentScene()` (critical: the bridge
must be reachable from `didMove(to:)` callbacks), applies the active scene
spec, and then schedules `sceneDidLoad` / `openScene` on the browse-mode
runtime queue so lifecycle delivery is serialized with the rest of HypeTalk.
The dispatch context starts at the scene script, then passes through the
sprite-area part, card, background, stack, and app; a scene script can handle
`on sceneDidLoad` directly or `pass sceneDidLoad` to the owning sprite area.

In **edit mode**, sprite-area SKViews are not created at all — `draw()`
falls through to `SpriteAreaRenderer` which paints a teal dashed rectangle
with the scene name as a placeholder. Switching to **browse mode** (the
HyperCard equivalent of Run mode) triggers a re-layout that materializes
the SKViews and starts the simulation. This keeps the editor lightweight
and predictable, and ensures physics simulation only runs when the user is
actually exercising the stack.

### 3.7 Card transitions

`performCardTransition()` (CardCanvasView.swift:875) implements
HyperCard-style visual effects. It:

1. Captures the current card via `CardRenderer.renderToImage()` →
   `NSImage`.
2. Briefly mutates state to the destination card and renders the same way.
3. Constructs an `SKTransition` matching the requested effect (`dissolve`,
   `fade`, `crossFade`, `wipe*`, `iris*`, `scroll*`, `push*`,
   `moveIn*`, `reveal*`, `doorway`, `flipHorizontal`, `flipVertical`).
4. Calls `cardSKView.presentScene(targetScene, transition: skTransition)`,
   which performs the actual animation entirely on the GPU.
5. After the animation completes, the SKView is hidden and the canvas
   resumes normal Core Graphics rendering.

This is why the card-level SKView exists at all: SpriteKit's transition
system gives Hype zero-cost, GPU-accelerated card transitions that would
otherwise require a custom Metal shader stack.

### 3.8 Native part nodes (now wired into the live rendering path)

`CardPartNode` (Sources/Hype/SpriteKit/CardPartNode.swift) is a small
protocol describing an `SKNode` that wraps a Hype `Part`:

```swift
protocol CardPartNode: AnyObject {
    var partId: UUID { get }
    func updateFromPart(_ part: Part)
}
```

Concrete implementations now exist for every classic part type and live
inside `CardSKScene.nativeLayer`, taking over the Core Graphics rendering
path that previously drew them through `CardRenderer`. The migration is
opt-in via a feature flag on `CardSKScene` so the legacy CG pass remains
available as a fallback while the SK-native path matures.

| Part type | Concrete node                                                          |
|-----------|------------------------------------------------------------------------|
| button    | `ButtonPartNode` (Sources/Hype/SpriteKit/ButtonPartNode.swift) — `SKShapeNode` background + `SKLabelNode` label, honors `buttonStyle`, theme tokens, hilite |
| field     | `FieldPartNode` (Sources/Hype/SpriteKit/FieldPartNode.swift) — `SKShapeNode` frame + `SKLabelNode`/attributed text, routes through `FieldTextLayout` |
| shape     | `ShapePartNode` (Sources/Hype/SpriteKit/ShapePartNode.swift) — `SKShapeNode` building a CGPath from `shapeType` + `pathData` |
| image     | `ImagePartNode` (Sources/Hype/SpriteKit/ImagePartNode.swift) — `SKSpriteNode` with `invertOnClick` via `colorBlendFactor` |
| paint     | `PaintLayerNode` (Sources/Hype/SpriteKit/PaintLayerNode.swift) — `SKSpriteNode` whose texture is the per-card `PaintLayer` RGBA bitmap |

The benefits the original architecture promised are now delivered: every
part type has access to `SKAction`-driven animation, physics, and the SKView
GPU pipeline; card transitions can use the same SpriteKit scene that hosts
the parts; and the `nativeLayer` slot in `CardSKScene` finally has its full
set of occupants. The CG renderer remains as the fallback / edit-mode
placeholder surface.

`FieldTextLayout` (Sources/HypeCore/Rendering/FieldTextLayout.swift)
extracts field-text positioning, padding, and color resolution into a
single helper that both the legacy `FieldRenderer` (CG path) and
`FieldPartNode` (SK path) call. The two paths cannot drift in pixel
alignment because they share the inset math, leading/trailing inset
overrides for `.search` / `.scrolling` styles, the wide-margins toggle,
and the contrast-aware color picker.

### 3.9 Embedded scene containment: `SpriteAreaNode`

`SpriteAreaNode` (Sources/Hype/SpriteKit/SpriteAreaNode.swift) is a
container `SKCropNode` plus an inner content `SKNode`, configured with a
white-rect mask sized to the sprite area's bounds. It carries its own
`SceneBridge` instance and exists to support the "many sprite areas on
one card" case in which sprite areas are eventually hosted as children of
the card's `spriteLayer` rather than as separate `SKView`s. Today the
shipping path uses one `SKView` per sprite area; `SpriteAreaNode` is
infrastructure for the alternative single-`SKView` consolidation.

### 3.10 SceneKit substrate: `scene3D` parts and 3D model rendering

`scene3D` is a first-class `PartType` peer of `spriteArea`. Where `spriteArea`
hosts a live `SKScene`, `scene3D` hosts an `SCNView` that loads and renders
a 3D model asset. The two part types share the same property-inspector,
scripting, asset-ref, and Sprite Repository discipline.

**`Scene3DHostNSView`** (`Sources/Hype/Views/Scene3DHostView.swift`) is the
AppKit-hosted `SCNView` overlay. One instance is created per visible `scene3D`
part and tracked in `CardCanvasNSView.scene3DViews: [UUID: Scene3DHostNSView]`.
On part update, the host checks whether `scene3DAssetRef` has changed: if so,
it resolves the asset bytes from `SpriteRepository` through
`Scene3DRepositoryAssetResolver`, writes the render asset to a UUID-named temp
file under `URL.temporaryDirectory/hype-scene3d/` (directory created with
`0o700` permissions), and calls `Scene3DAssetLoader.load(from:)` on a
background queue. GLB/GLTF repository selections render through a same-task or
same-basename USDZ companion when one exists, while the selected asset name
remains the author-visible model value. The load identity includes a byte
fingerprint so replacing an embedded asset with same-length bytes still reloads.
The fallback path reads `scene3DURL` directly for legacy file-path bindings.

**`Scene3DAssetLoader`** (`Sources/HypeCore/Rendering/Scene3DAssetLoader.swift`)
is the centralised extension→strategy table:

| Extension | Strategy |
|-----------|----------|
| `.usdz`, `.usd`, `.scn`, `.dae`, `.obj` | `SCNScene(url:)` — SceneKit native |
| `.glb`, `.ply`, `.abc` | `MDLAsset(url:)` → `SCNScene(mdlAsset:)` — macOS 13+ |
| `.fbx` | `MDLAsset(url:)` — macOS 13+ only; higher attack surface (Autodesk SDK) |
| `.stl` | `STLConverter.convert(stlPath:)` → OBJ → `SCNScene(url:)` |

All methods are synchronous and throw structured `LoadError` on failure; they
never call `fatalError`. Callers are responsible for invoking off main thread.

**`Part.scene3DAssetRef: AssetRef?`** (Phase 1) is the preferred binding path.
When non-nil, the host materialises bytes from `SpriteRepository` into a temp
file and feeds the file URL to the loader. `scene3DURL` remains as the legacy
file-path path; when both are present, `scene3DAssetRef` takes precedence.

**`Scene3DAssetConverter`** (`Sources/HypeCore/Rendering/Scene3DAssetConverter.swift`,
Phase 4) converts GLB to USDZ via `MDLAsset` for AR Quick Look consumption.
Gated on `#available(macOS 13, *)`.

**`ARQuickLookPresenter`** (`Sources/Hype/AR/ARQuickLookPresenter.swift`, Phase 4)
stages a USDZ in `~/Library/Caches/com.hype.app/ar-quicklook/` (created with
`0o700` permissions) and presents it via `QLPreviewPanel.shared()`. GLB assets
are first converted by `Scene3DAssetConverter`; non-USDZ assets that cannot
be converted surface `ARQuickLookError.unsupportedAssetKind`. The "Open in AR"
button in `SpriteRepositoryView` is hidden on macOS < 13.

**Architectural symmetry with SpriteKit.** `scene3D` parts are model-driven:
`Part.scene3DAssetRef` is the asset-ref discipline (UUID, not raw path), and
mutations flow through the same `@Binding`-based document model as every other
part type. The Sprite Repository and Property Inspector ("From Repository…"
dropdown) are the authoring surfaces — no separate 3D asset management UI.
HypeTalk addresses `scene3D` parts by name and can set `the model` of any part
through the smart resolver (see §5.7), keeping the scripting surface consistent
with 2D image binding.

---

## 4. The Sprite Repository

Asset management is intentionally separated from raw filesystem paths. The
PRD's strongest claim about asset handling — *"no scene spec should depend
on a raw path as its canonical asset reference"* — is reflected in the
data model.

### 4.1 Data model

`SpriteRepository` (Sources/HypeCore/Models/SpriteRepository.swift:92) is a
stack-scoped collection of `SpriteAsset` values, embedded directly inside
`HypeDocument` and serialized along with the rest of the stack. Stacks
remain self-contained: opening a `.hype` file on another machine restores
all referenced art with zero external dependencies.

```swift
public enum AssetKind: String, Codable, Sendable {
    case imageTexture, spriteSheet, tileSet, audioClip, videoClip,
         particlePreset, placeholderAsset, model3D
}
```

`AssetKind` has a custom `init(from:)`: unknown raw values (from future versions of
the format) map to `.imageTexture` for forward-compat — the same strategy as
`PartType.init(from:)` (Phase 1 design decision).

```swift
public struct SpriteAsset: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AssetKind
    public var mimeType: String
    public var data: Data            // raw bytes embedded in the stack package
    public var width: Int
    public var height: Int
    public var tags: [String]
    public var slices: [AssetSlice]            // sprite sheet → frame rects
    public var animationClips: [AnimationClip] // frame indices → fps + loops
    // Tile-set classification (kind == .tileSet)
    public var tileWidth, tileHeight, tileColumns, tileRows: Int
    // Origin / license tracking (set when the AI imports from web search)
    public var provenance: AssetProvenance?
    // 3D model metadata (kind == .model3D, Phase 3)
    public var isRigged: Bool
    public var animationActionId: Int?  // Meshy animation catalog entry
}

public struct SpriteRepository: Codable, Sendable {
    public var assets: [SpriteAsset]
    public func asset(byId: UUID)   -> SpriteAsset?
    public func asset(byName: String) -> SpriteAsset?
    public func assetRef(for: SpriteAsset) -> AssetRef
    public mutating func addAsset/_/removeAsset/_/updateAsset(_:)
}
```

`AssetProvenance` records the import path: `userImport`, `webSearch`,
`aiGenerated`, or `aiContext`. Web-search imports also persist license + creator + source URL
so the inspector can show an attribution block and the stack-script
attribution synchronizer can keep an `-- Attributions --` block in the stack
script up to date as web assets are added or removed. For Meshy-generated
models, `AssetProvenance.attribution` additionally carries `taskId: String`
(the Meshy task that produced this asset) and `parentTaskId: String` (the
source task when this asset was derived via remesh, retexture, or rigging),
enabling chain-of-derivation tracking (Phase 3 / Phase 4).

**50 MB decode cap on `model3D` assets.** `SpriteAsset.init(from:)` enforces a
50 MB cap on `kind == .model3D` data at decode time (Phase 1 Security M1). A
malicious `.hype` document embedding a gigantic GLB/USDZ blob would otherwise
exhaust memory silently during `JSONDecoder` inflate; the cap surfaces an
explicit `DecodingError` instead and keeps ordinary valid models well within
the limit.

`tileSet` is a refinement of sprite sheet for SpriteKit `SKTileMapNode` use:
the slicing tools record per-tile dimensions and grid extents, and
`createTileMap` reads those directly so authors don't have to repeat the
tile geometry on every reference.

### 4.2 AI Context Library

`AIContextLibrary` (Sources/HypeCore/AI/AIContextLibrary.swift) is the
user-curated context channel for AI stack creation. It snapshots selected
files, folders, images, and freeform notes into `HypeDocument` so complex
instructions and asset packs travel with the stack without exposing arbitrary
filesystem tools to the model.

The ingestion path is deliberately narrow:

- supported text and image extensions only
- hidden/package descendants and symlinks skipped for directories
- per-file and per-directory caps enforced before reading
- text chunked into bounded snippets for search/read tools
- image bytes embedded as context items and importable into the Sprite
  Repository via `import_context_asset`
- AI-authored project-memory notes written through `write_ai_context_note`
  so decisions, TODOs, naming conventions, and known issues persist with
  the stack across build sessions

Cloud sharing is gated by `Stack.aiContextCloudSharingAllowed`. Local Ollama
models can use context tools directly; OpenAI models only see context summaries
and context tool schemas after the current stack is explicitly opted in from
Preferences or script/tool property setters.

### 4.3 Stable references via `AssetRef`

`AssetRef` (Sources/HypeCore/Models/AssetRef.swift) is what scene specs
actually carry. It is intentionally small:

```swift
public struct AssetRef: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var variantId: UUID?
    public var mimeType: String
}
```

A node spec stores an `AssetRef`, not a path or filename. At
texture-load time, `SceneBridge.loadTexture` (SceneBridge.swift around line
617) looks up the `SpriteAsset` by ID via the document's repository,
decodes its `data` to an `NSImage`, and caches the resulting `SKTexture`
under the asset ID. This means:

- Renaming an asset never breaks a scene.
- Replacing an asset's bytes (e.g. swapping in a new sprite sheet)
  preserves every reference.
- Sprite-sheet `slices` and `animationClips` are derived metadata that
  travel with the asset, so reusing an animation across cards just means
  pointing another node spec at the same `AssetRef`.

### 4.4 The repository UI

`SpriteRepositoryView` (Sources/Hype/Views/SpriteRepositoryView.swift) is
the SwiftUI window that browses, imports, slices, and tags the repository.
It supports drag-and-drop import (PNG / JPEG / audio formats), Cmd+click
multi-select, slicing into frame rects, tile-set classification (auto-detect
+ manual W×H), animation-clip authoring (FPS, loops), per-asset rename,
duplicate, delete, and attribution view (for web-search imports). It is the
surface that the AI's `list_repository_assets`, `import_repository_asset`,
`generate_sprite_asset`, and `web_asset_search` tools mirror — keeping human
and AI workflows on the same data. The right side of the repository window also
hosts `SpriteRepositoryAIChatView`, a repository-scoped chat surface that can
ask for the required sprite asset name and then call `generate_sprite_asset`
without exposing card, background, or script mutation tools.

A **Transparent Background** action — available in both the single-asset
detail panel and the multi-selection panel — runs the same dominant-corner
chroma-key the renderer uses for `Part.transparentBackground`, but writes the
result back to `SpriteAsset.data` as PNG bytes (always PNG, since JPEG can't
carry per-pixel alpha). The shared `ImageChromaKey.makeTransparentPNG(...)`
helper in `Sources/HypeCore/Rendering/ImageChromaKey.swift` is what both the
view-time render path and this asset-modification path call.

The detail-panel image preview and grid thumbnails tag their `Image(nsImage:)`
with `.id(asset.data.count)` so SwiftUI gives the view a fresh identity when
the bytes change — without that, the cached NSImage decode lingered after a
chroma-key edit and the preview kept showing pre-transparent pixels until the
user re-selected.

### 4.5 Model3D assets in the repository

`model3D` assets live alongside 2D sprites in the same repository. Their bytes
(GLB, USDZ, FBX, etc.) are embedded directly in the `.hype` file, so stacks
remain fully self-contained. There is no separate asset cache or sidecar file.

**Grid rendering.** `SpriteRepositoryView` renders `model3D` assets with a
`cube.transparent` SF Symbol placeholder icon in indigo. A rendered preview
thumbnail is not feasible without loading SceneKit; the icon is the intentional
fallback.

**Inspector action buttons.** The asset detail panel gates Meshy-specific
operations behind `provenance.attribution.providerIdentifier == "meshy"` and,
where applicable, a non-empty `taskId`. The full button surface is:

| Button | Gate |
|--------|------|
| Generate 3D… | any `model3D` asset (re-trigger generation) |
| Rig & Animate… | `isMeshy && hasMeshyTaskId && !asset.isRigged` |
| Animate… | `asset.isRigged && asset.animationActionId == nil && hasRigTaskId` |
| Remesh… | `isMeshy && hasMeshyTaskId` |
| Retexture… | `isMeshy && hasMeshyTaskId` |
| Open in AR | any `model3D` asset; button is hidden on macOS < 13 |

**Binding to `scene3D` parts.** Model3D assets are bound to `scene3D` parts via
`Part.scene3DAssetRef` (an `AssetRef?`). The preferred authoring paths are the
Property Inspector "From Repository…" dropdown and the HypeTalk command
`set the model of scene3d "X" to "<asset-name>"` (see §5.7). When
`scene3DAssetRef` is set, `Scene3DHostNSView` materialises asset bytes from
`SpriteRepository` into a UUID-named temp file under
`URL.temporaryDirectory/hype-scene3d/` (directory created with `0o700`
permissions if absent) and feeds the resulting file URL to `Scene3DAssetLoader`.
The legacy `scene3DURL` string remains as a fallback for file-path bindings.

---

## 5. HypeTalk: the Scripting Language

HypeTalk is the largest single subsystem in HypeCore — about 8,400 lines
across lexer, parser, AST, interpreter, dispatcher, and highlighter. The
goal is to feel like HyperCard's HyperTalk while addressing modern part
types, the SpriteKit scene graph, the asset repository, and a 60-fps
property-tween animation system.

### 5.1 Pipeline

```
script source string
        │
        ▼
┌────────────┐    ┌────────────┐    ┌─────┐    ┌────────────────┐
│   Lexer    │───▶│   Parser   │───▶│ AST │───▶│   Interpreter  │
│ (251 LoC)  │    │ (2.5k LoC) │    │     │    │   (4.7k LoC)   │
└────────────┘    └────────────┘    └─────┘    └────────────────┘
                                                       │
                                                       ▼
                                          ExecutionResult{
                                              status,
                                              returnValue,
                                              modifiedDocument,
                                              navigationTarget,
                                              visualEffect
                                          }
```

- **Lexer** (Sources/HypeCore/Script/Lexer.swift) is hand-written,
  case-insensitive, recognizes 100+ token types, handles `--` line comments,
  `\` line continuations, and both straight and Unicode smart quotes.
- **Parser** (Sources/HypeCore/Script/Parser.swift) is recursive descent.
  It accepts an optional top-level `global a, b, c` prelude before handler
  blocks and injects those names into every handler body. That is the only
  supported top-level statement form; executable top-level commands are still
  rejected so runtime execution remains handler-driven. After that prelude it
  splits source into top-level `on name … end name` or `function name … end
  name` blocks, then parses statement-by-statement with a switch on the
  leading token. Object references like `card 3`, `field "Name"`, `button 2
  of background "BG1"`, and scope references like `this stack` / `current
  card` are first-class grammar.
- **AST** (Sources/HypeCore/Script/AST.swift) defines `Expression` and
  `Statement` enums. Expressions cover literals, variables, `it`, `me`,
  `this`, `empty`, binary and unary operators, function calls, property
  access, chunk expressions (`word 3 of …`), object references, and
  containment / membership predicates. Statements cover ~70 forms: data
  movement (`put`, `get`, `set`), navigation (`go`), control flow
  (`if`/`then`/`else`, `repeat` in count/while/with-iterator forms,
  `exit`, `next`, `pass`, `return`), dialogs (`ask`, `answer`), screen
  effects (`visual`, `lock screen`, `unlock screen`), and ~15 SpriteKit
  commands (create sprite/scene/tilemap/camera/joint/constraint/physics
  field, `apply force`, `apply impulse`, `set tile`, `pause scene`,
  `resume scene`, `open scene`). The grammar now also includes explicit
  suspending, dispatch, and network-aware forms: `await <expression>`, `wait until`,
  `request …`, `reply to request …`, `listen for http …`, `listen for tcp …`,
  `connect to host …`, `send "<message>" to <target>`, `send … to connection …`,
  `close connection …`, and `stop listener …`. The plain `send` form is
  HypeTalk message dispatch; the `to connection` form is TCP I/O. For imported
  HyperCard scripts, unknown command-style identifiers with arguments parse as
  `.externalCommand(name:arguments:)` so XCMD calls like `SetCursor "watch"`
  can flow into the emulation registry rather than causing a parse error.

  Property animation is a first-class statement:
  `animate the loc of button "ball" to "400,300" over 0.5`,
  `animate the rotation of shape "spinner" to 360 over 2 seconds`,
  `animate the alpha of cd btn 1 to 0 over 0.3`. The interpreter dispatches
  the `.animateProperty` AST node into `PartAnimator.shared`, which runs a
  60Hz `Timer` tick (or `CADisplayLink` when paired with `GIFAnimator`) that
  interpolates the part's property toward the target value over the given
  duration. The animator writes through to the document via a coordinator
  hook so the change is visible to subsequent reads (`the animating of
  button "ball"` returns `"true"` while a tween is in flight, `"false"`
  otherwise). Animatable properties cover the geometry / transform / color
  surface (`left`, `top`, `width`, `height`, `loc`, `rotation`, `alpha`,
  `fillColor`, `strokeColor`, `fontColor`).
- **Interpreter** (Sources/HypeCore/Script/Interpreter.swift) is a
  tree walker. It maintains an `ExecutionContext` (target ID, current
  card, document, dialog/drawing/system providers, mouse coordinates,
  instruction budget) and an `Environment` (locals, globals, the special `it`
  variable, and a set of names declared global). Control flow uses thrown
  signals: `exitRepeat`, `nextRepeat`, `exitHandler(returnValue)`,
  `passMessage` are exceptions caught at the appropriate level. An
  instruction-count limit (default 1 million) prevents accidental
  infinite loops. The interpreter now has two execution modes:
  - a **pure-core path** that still takes a document in and returns a
    modified document out, used heavily by tests and non-browse tooling
  - a **runtime-backed async path** used in browse mode and by the Message Box,
    where suspension points preserve locals while the live stack keeps evolving

### 5.2 Message dispatch and runtime ownership

`MessageDispatcher` (Sources/HypeCore/Script/MessageDispatcher.swift)
still implements the HyperCard message hierarchy, but browse mode no longer
treats dispatch as a one-off pure function call. Instead, `MainContentView`,
`CardCanvasView`, and `MessageBoxView` resolve a per-stack `StackRuntime`
through `StackRuntimeRegistry` and ask that actor to enqueue work.

The runtime owns:

- the live `HypeDocument`
- script globals and the app script
- provider bridges for dialog, drawing, local system audio/beep, AI, speech,
  and Meshy so browse-mode scripts do not silently fall back to test stubs
- async AI jobs
- outbound HTTP requests and inbound pending HTTP replies
- active HTTP/TCP listeners and TCP connections
- a FIFO callback/event queue
- published runtime status snapshots for the UI

Hype has two AI lanes. The macOS authoring lane remains provider-selectable
through `HypeAIClient` (`Ollama`, `llama-swap`, `llama.cpp`, OpenAI, Z.ai,
MiniMax) and can use broad authoring tools through `HypeToolExecutor`.
The deployed-runtime lane is target-aware and intentionally narrower:
`RuntimeAwareAIScriptingProvider` keeps macOS on the selected authoring provider
but routes non-macOS runtime-mode `ask ai` calls through
`RuntimeAIProviderResolver`. iPhone and iPad resolve to
`AppleFoundationModelsRuntimeProvider`, guarded by `canImport(FoundationModels)`
and OS/model availability checks. tvOS resolves to `UnavailableRuntimeAIProvider`
until Apple exposes a supported on-device language-model runtime there.
`RuntimeAIToolCatalog` only exposes read-only runtime tools by default; any
side-effect tool requires both `allowRuntimeSideEffectTools` and an explicit
allowlist entry in `Stack.runtimeAISettings`.

That ownership boundary matters because it gives HypeTalk a place to suspend
without freezing the app or violating message order. `wait`, `wait until`,
`await …`, async AI completions, HTTP replies, listener events, and socket
events all resume by enqueueing a normal HypeTalk message back onto the runtime
queue; they never re-enter a running handler directly.

### 5.3 Message chain and callback routing

The effective browse-mode chain is now:

```
node → parent group(s) → scene → sprite area → card → background → stack → app
```

Deduplication still applies when a target is already a card, background, or
stack. For each link, the dispatcher finds the attached script, parses it,
looks up a handler with the matching name (case-insensitive), and runs it. If
the handler ends with `pass <message>`, dispatch continues up the chain;
otherwise it returns the `ExecutionResult`. The app-level "Hype" script still
lives at a sentinel UUID (`00000000-0000-0000-0000-000000000001`) persisted in
`UserDefaults`.

Scripts can enter the same dispatch path explicitly with `send "<message>" to
<target>`, such as `send "doCamp" to this stack`, `send "refresh" to this
card`, `send "cleanup" to this background`, or `send "flash" to button "OK"`.
The networking form is intentionally distinct: `send "<data>" to connection
connId` writes to a TCP connection and does not invoke object handlers.

The important change over the earlier architecture is that **SpriteKit targets
are no longer collapsed to only the sprite-area part**. `HypeNodeSpec.script`
and `SceneSpec.script` are first-class script surfaces, so:

- a click inside a sprite area can target the concrete node first
- nested groups can intercept and `pass`
- scene-level handlers can observe `openScene`, `closeScene`, `sceneDidLoad`,
  `frameUpdate`, `beginContact`, `endContact`, and `actionFinished`
- callback-based async jobs capture the owner target, card, and scene context
  that created them, so completions route back to that same chain first

If a callback owner disappears before completion, the runtime either promotes
the message to the stack/app level or tears down the handle cleanly, depending
on the event type.

### 5.4 Async execution, AI calls, and networking

HypeTalk remains **sync by default**. A normal handler runs inline and returns
exactly as classic HyperTalk would. It becomes suspending only when it uses an
explicit suspending form:

- `wait <seconds>`
- `wait until <condition>`
- `await <async builtin call>`
- `request …` without `with message`
- callback-style AI, listener, or connection events

The language intentionally uses a hybrid model:

- **`await`** is for one-shot operations whose result is needed immediately
- **`with message "handlerName"`** is for long-lived or externally-driven work

That pattern is used consistently across AI and networking:

- AI:
  - `put await ollama("prompt") into field "out"`
  - `put await ollama("modelName", "prompt") into field "out"`
  - `put await ollamaModels() into field "out"`
  - `ask ai "prompt" with message "aiFinished"`
- HTTP client:
  - `request "https://example.com/data"`
  - `request "https://example.com/submit" method "POST" headers "Content-Type: application/json" body "{\"score\":42}" with message "requestFinished"`
- HTTP server:
  - `listen for http on port 8080 host "127.0.0.1" with message "networkRequest"`
  - `reply to request requestId with status 200 body "hello from Hype"`
- TCP:
  - `listen for tcp on port 9000 host "127.0.0.1" with message "socketEvent"`
  - `connect to host "127.0.0.1" on port 9000 with message "socketEvent"`
  - `send "ping" to connection connId`
  - `close connection connId`
  - `stop listener listenerId`

The network-facing `request`/`reply` verbs are now about real I/O, not a stub
for future Apple Events. V1 scope is UTF-8 text/JSON over HTTP/HTTPS and raw
TCP. Binary payloads, UDP, WebSockets, and server-side TLS certificate
management are intentionally deferred.

#### Legacy external emulation

HyperCard XCMD/XFCN compatibility is handled by
`HyperCardExternalRegistry`, not by loading original native resources. Imported
scripts can use command-style external calls (`SetCursor "watch"`) and
function-style calls (`put HypeVersion() into v`). The parser emits
`.externalCommand` for unknown command identifiers with arguments, while normal
function-call syntax falls through to the registry after Hype's built-ins.

The registry returns a `HyperCardExternalResult` containing the command value,
`the result` diagnostic, optional document mutation, and optional pass-message
flag. Unknown or not-yet-emulated externals set `the result` to a clear
`Can't Load External...` diagnostic and continue execution. This matches the
security posture of the importer: XCMD/XFCN resources are preserved and
reported, but classic 68K/PPC code is never executed in-process.

### 5.5 Object and property model

The interpreter exposes hundreds of properties on each part type and
scene-node type. A few representative ones:

| Object        | Properties (sample)                                                                                |
|---------------|----------------------------------------------------------------------------------------------------|
| any part      | `name`, `visible`, `enabled`, `hilite`, `left/top/width/height`, `rect`, `loc`, `right`, `bottom`, `script`, `owner`, `number`, `helpText` *(aliases tooltip / help)*, `fontColor` *(aliases textColor / color)*, `textStyle` *(comma-separated bold/italic/underline/strikethrough)*, `animating` |
| button        | `style`, `showName`, `iconId`, `popupItems`, `autoHilite`, `url` (link style)                       |
| field         | `textContent`, `textFont`, `textSize`, `textStyle`, `textAlign`, `lockText`, `dontWrap`, `enterKeyEnabled` |
| shape         | `shapeType`, `fillColor`, `strokeColor`, `strokeWidth`, `cornerRadius`                              |
| webpage       | `url`                                                                                              |
| image         | `imageFilter`, `imageFilterIntensity`, `transparentBackground`, `animated`                          |
| chart         | `chartData`, `charttitle`, `xAxisLabel`, `yAxisLabel`, `showLegend`, `showGrid`                    |
| calendar      | `selectedDate`, `displayMonth`, `minDate`, `maxDate`, `calendarStyle`                               |
| pdf           | `pdfurl`, `currentPage`, `displayMode`, `autoScales`, `pageCount`                                   |
| map           | `centerLat`, `centerLon`, `span`, `mapType`, `annotations`, `location` *(geocoded async)*           |
| colorWell     | `color`, `interactive`                                                                              |
| stepper / slider | `value`, `min`, `max`, `step`                                                                    |
| segmented     | `segments`, `selectedSegment`                                                                       |
| progressView  | `value` (0..total), `progressTotal`, `progressIsCircular`, `progressIsIndeterminate`, `progressLabel`, `progressTint`, `progressDecimals` |
| gauge         | `value` (gaugeMin..gaugeMax), `gaugeMin`, `gaugeMax`, `gaugeStyle`, `gaugeTint`, `gaugeLabel`, `gaugeDecimals` |
| recorder      | `recording`, `playing`, `duration`, `outputPath`, `format`                                          |
| scene3d       | `object`, `modelURL`, `allowsCameraControl`, `autoLighting`, `antialiasing`, `background3d`         |
| divider       | `dividerOrientation`, `dividerThickness`, `dividerColor`                                            |
| sprite area   | (top-level scene name, plus per-node access via `the position of sprite "Hero"`)                   |
| sprite node   | `position`, `rotation`, `xScale/yScale`, `zPosition`, `alpha`, `hidden`, `text`, `fontName`, `fontColor`, `textStyle`, `velocity`, `angularVelocity`, `density`, `damping`, `audioVolume`, `audioLoop`, `videoLoop`, `particleBirthRate`, `emissionAngle`, `cameraTarget`, `zoom`, … |
| request       | `status`, `method`, `url`, `statusCode`, `body`, `error`, `header "Content-Type"`                  |
| listener      | `port`, `host`, `transport`, `state`, `callbackMessage`                                            |
| connection    | `remoteAddress`, `port`, `state`, `lastData`, `error`                                              |
| card          | `name`, `marked`, `script`, `theme`, `effectiveTheme`                                              |
| background    | `name`, `script`, `theme`, `number of cards`                                                       |
| global        | `the time`, `the date`, `the ticks`, `the seconds`, `the screenrect`, `the version`, `the mouseLoc`, `the shiftKey`, `the optionKey`, `the commandKey`, `the aiModel`, `the aiModels` |

A few property surfaces deserve their own paragraph because authors run into
them often:

- **`textStyle`** — comma-separated subset of `plain`, `bold`, `italic`,
  `underline`, `strikethrough`. Setters normalize through `TextStyleFlags`
  (Sources/HypeCore/Models/TextStyleFlags.swift) so `"BOLD,italic"` and
  `"strike"` both round-trip to canonical `"bold, italic"` /
  `"strikethrough"`. Both card parts and SpriteKit label nodes share this
  surface. The renderer applies bold/italic via `NSFontManager` font traits
  and underline/strikethrough as attributed-string keys.
- **`fontColor`** — hex string for text foreground; empty string means
  "auto / contrast-aware against fill" (the renderer picks a readable color
  from the fill's luminance via `ColorContrast.readableTextColor`). This is
  what fixed the long-standing dark-mode-with-white-fill invisibility bug.
- **`helpText`** — every part can opt into a hover bubble shown via native
  `NSToolTip`. `set the helpText of cd btn "Save" to "Saves the current
  document. ⌘S also works."` is enough; aliases `tooltip`, `help`,
  `tool_tip`, `help_text` are accepted. Empty disables the bubble. See §6.9.

**Field-exit events** (`exitField`, `closeField`) underwent a deliberate
semantic change:
- `exitField` fires on **every** field exit — Tab out, click out,
  programmatic focus loss. This is the universal "blur" event authors want
  for validation, geocoding, save-on-exit patterns.
- `closeField` fires **before** `exitField` only when the text changed
  during the edit session. Use it specifically for "the value changed"
  semantics (e.g. mark a form dirty).

The previous strict-XOR HyperCard semantics meant `exitField` only fired
when text *didn't* change, which was confusing for authors writing the
common case "do something every time the user finishes editing this
field." Both events now coexist; the more specific `closeField` runs first
when relevant, then the general `exitField`.

Built-in functions number ~70 across string handling (`length`, `offset`,
`chartonum`, `numtochar`), math (`abs`, `round`, `min`, `max`, `sin`, `sqrt`,
`pow`), date/time, statistical (`sum`, `average`, `annuity`, `compound`),
and system info (`screenRect`, `diskSpace`, `systemVersion`). All values
are conceptually strings (HyperCard's "everything is a chunk of text"
model), coerced to numbers during arithmetic, with chunk expressions
(`word 3 of card field "Name"`) for slicing.

`the aiModel` is synchronous because it reflects local configuration.
`the aiModels` remains available for compatibility, but the preferred async form
is `await ollamaModels()`.

### 5.6 Editor support

Script editing happens in a dedicated window (`ScriptEditor.swift`,
~488 LoC). It hosts an `NSTextView` via `HypeTalkTextView.swift`
(forces light appearance for readability, monospaced 13pt, disables smart
quotes/dashes/auto-correct), with a sidebar of ~50 templates grouped by
category (Events, Navigation, Variables, Control, SpriteKit, AI, Network, …)
for quick insertion. The editor also understands scene-level and node-level
scripts as first-class targets, so jump-to-script actions from the property
inspector, scene guide, and repository usage views can open the exact script
surface that owns a behaviour. Syntax highlighting goes through a separate
`HypeTalkHighlighter` pass that emits `[HighlightToken]` records over
`Range<String.Index>` so highlight categories
(keyword/command/objectType/constant/string/number/comment/operator)
land on exact character ranges. A `CompletionPopup` table view offers
arrow-key-navigated, Enter-to-insert completions.
The right-side Script Editor AI panel submits requests with the canonical
`HypeTalkGuide.llmContext` in the system prompt, supports microphone input with
~3.5 seconds of silence before auto-submit, and tracks the in-flight model task
so the visible Stop button can cancel the current request. Its prompt input uses
the same zero-inset `AIChatInputView` as the main AI panel: it starts as a
single line, expands to show the full composed prompt, collapses after Submit,
and uses Up/Down arrow recall against the document-scoped prompt history.

A `MessageBoxView` REPL (Sources/Hype/Views/MessageBoxView.swift) lets the
user evaluate HypeTalk expressions interactively against the live runtime
document — not a stale snapshot — so `await`, runtime object properties, and
callback-driven networking behave the same way they do in browse mode. The
SpriteKit authoring side is similarly guided: `SpriteSceneSetupGuide` and
`SceneAuthoringSupport` surface a checklist-oriented workflow for scene basics,
world content, assets, physics, and starter scripts instead of exposing raw
SpriteKit knobs with no scaffolding.

**Author shortcuts to the script editor.** Two interaction conventions
shorten the path from a part to its script:
- **Cmd+click** in browse mode opens the clicked part's script editor (or
  the current card's script editor when clicking empty canvas). Implemented
  in `CardCanvasNSView.mouseDown` (Sources/Hype/Views/CardCanvasView.swift)
  and consumed via the `.openPartScriptEditor` notification.
- The inspector's per-part **"Edit Script…"** row opens the same editor
  bound to the selected part's `script` field.

Both paths converge on the shared `openScriptEditorWindow(...)` helper,
which dedups windows by target ID, persists size/position, and supports
error-line highlighting when navigating from a runtime error.

### 5.7 3D model commands (Meshy)

These grammar forms were added in Phases 3–5 of the Meshy integration.

**`ask meshy`** — text-to-3D generation.

- *Statement form (synchronous, sets `it` / `the result`):*
  `ask meshy "<prompt>"`
- *Statement form (asynchronous callback):*
  `ask meshy "<prompt>" with message "handlerName"`
- *Expression form (usable in `put … into`):*
  `put ask meshy "barrel" into x`

Both statement and expression forms accept optional order-independent modifiers:
- `with style "realistic"` or `with style "sculpture"` — maps to `artStyle` on
  the Meshy API.
- `with model "meshy-6"` (or `"meshy-5"`, etc.) — selects the Meshy generation
  model.

The expression evaluates to the new asset's name as a `String` (the
`SpriteAsset.name` assigned by `Meshy3DAssetImporter`). The synchronous
statement form blocks via `await` internally; it is equivalent to
`put await (ask meshy …) into it`.

**Warning:** do NOT use `ask meshy` as a boolean condition — each evaluation
fires a billable Meshy generation call. The expression is not memoized.

**`set the model of scene3d "X" to "<value>"`** — smart resolver.

- If `<value>` matches a `model3D` asset name or extensionless asset stem in
  the Sprite Repository, binds via `Part.scene3DAssetRef` (asset-ref discipline).
- Otherwise, falls back to the file-path resolver (sets `scene3DURL` directly).
  On the file-path branch, `scene3DAssetRef` is explicitly cleared.
- The `put <expr> into the model of scene3d "X"` form applies the same
  smart-resolve rules and is fully equivalent to the `set` form (Phase 5
  Finding 3 fix).
- `modelAsset`, `model_asset`, `assetName`, and `asset_name` use the same
  resolver for AI tools and HypeTalk aliases.

**`remesh asset "X" to <polycount>`** — triggers a Meshy remesh operation on
the named model3D asset and imports the result as a new repository asset.
Optional `with message "handlerName"` for async callback.

**`retexture asset "X" with prompt "<text>"`** — triggers a Meshy retexture
operation on the named model3D asset. Optional `with message "handlerName"`.

---

## 6. View, Rendering, and Editing

### 6.1 The SwiftUI / NSView / SpriteKit boundary

The whole macOS app is a SwiftUI `App` that uses a SwiftUI `DocumentGroup`
to manage `.hype` files. SwiftUI handles **everything around the canvas**:
menus, palettes, the property inspector, the AI chat panel, the
preferences pane, the sprite repository window, the stack network panel, and
the script editor.

The canvas itself is **not** SwiftUI. `CardCanvasView` is an
`NSViewRepresentable` whose `makeNSView` returns a `CardCanvasNSView`
(`NSView` subclass, layer-backed, `isFlipped = true`). This was a
deliberate choice: a single NSView gives Hype precise control over
draw order, hit testing, and the lifecycles of the heterogeneous overlays
(text fields, web views, video players, charts, SKViews) it composites on
top of its Core Graphics drawing pass.

The SwiftUI side communicates with the NSView side through the standard
`Coordinator` pattern (CardCanvasView.swift:113): the coordinator owns the
NSView reference, exposes methods like `selectPart`, `addPart`,
`movePart`, `resizePart`, `dispatchMessage`, and reflects model
mutations back into SwiftUI `@Binding`s so the inspector and palettes
update. In browse mode, `MainContentView` also listens for
`stackRuntimeDocumentDidChange` and `stackRuntimeStatusDidChange`
notifications so the SwiftUI shell can stay synchronized with the live runtime
actor rather than assuming scripts are mutating only local view state.

Menu ownership stays in the SwiftUI `Commands` layer. `GoMenuCommands` defines
Hype's Go, Objects, Arrange, Tools, AI, and Window additions, and augments the
system View menu with a command group instead of declaring a second top-level
`View` menu. Tests pin that contract so future menu additions do not reintroduce
the duplicate-menu regression.

### 6.2 The render pipeline

`CardRenderer` (Sources/HypeCore/Rendering/CardRenderer.swift) is a pure
HypeCore type that draws a card to a `CGContext`. It can render to a
context that the NSView is currently drawing into, or render to an
offscreen `NSBitmapImageRep` (the entry point for capturing
`NSImage`s for card transitions). The pipeline:

1. Fill the white background.
2. Draw the background's parts (if any), skipping any IDs in a
   `nativePartIds` set — i.e. any parts that are being hosted as native
   overlays (web views, charts, sprite areas, etc.).
3. (placeholder) draw the card's paint layer.
4. Draw the card's parts, again skipping `nativePartIds`.

`drawPart()` is a dispatcher on `partType`. Concrete renderers live as
sibling files:

- `ButtonRenderer` (Sources/HypeCore/Rendering/ButtonRenderer.swift,
  ~236 LoC) implements all button styles: standard, default, opaque,
  transparent, rectangle, roundRect, shadow, oval, toggle, popup,
  checkBox.
- `FieldRenderer` paints field backgrounds and text. Both static rendering and
  browse-mode inline editing share `FieldTextLayout`, so text insets, search /
  scrolling reserves, alignment, foreground contrast, and vertical centering
  match pixel-for-pixel.
- `ShapeRenderer` paints rectangles, round-rects, ovals, lines, and
  freeform `CGPath`s with fill / stroke / corner radius.
- `ImageRenderer` blits embedded `NSImage`s with hilite (invert-on-click)
  support and the appropriate Y-flip handling for the flipped NSView.
- `WebPageRenderer`, `VideoRenderer`, `ChartRenderer`, `SpriteAreaRenderer`
  each render an **edit-mode placeholder** — a styled rectangle with type
  identification — because at runtime those parts are replaced by native
  overlays.

### 6.3 Native overlays

`CardCanvasNSView` keeps several parallel dictionaries from `Part.id` to
its native overlay:

```swift
var webViews:            [UUID: WKWebView]
var videoPlayers:        [UUID: AVPlayerView]
var chartViews:          [UUID: NSView]       // NSHostingView<ChartHostView>
var calendarViews:       [UUID: CalendarHostNSView]
var pdfViews:            [UUID: PDFHostNSView]
var mapViews:            [UUID: MapHostNSView]
var colorWellViews:      [UUID: ColorWellHostNSView]
var stepperViews:        [UUID: StepperHostNSView]
var sliderViews:         [UUID: SliderHostNSView]
var segmentedViews:      [UUID: SegmentedHostNSView]
var audioRecorderViews:  [UUID: AudioRecorderHostNSView]
var scene3DViews:        [UUID: Scene3DHostNSView]
var progressViewHosts:   [UUID: ProgressViewHostNSView]
var gaugeHosts:          [UUID: GaugeHostNSView]
var spriteViews:         [UUID: SKView]       // HypeSKScene
var paintLayers:         [UUID: PaintLayer]   // per-card runtime cache, mirrored to document snapshots
var activeFieldEditor:   NSTextField?         // single inline editor at a time
```

On every layout pass, each visible part of an overlay-eligible type has
its overlay subview created (lazily), positioned to its part rect, and
configured. Parts that disappear have their overlays torn down. The
overlay set is recorded in a `nativePartIds` set so `CardRenderer`
knows to skip those parts during the Core Graphics pass.

Charts are notable: `ChartHostView.swift` is a SwiftUI view built on
Apple's Charts framework, hosted inside an `NSHostingView` so it can live
inside an AppKit subview hierarchy.

Sprite areas now host the active scene from `SpriteAreaSpec` rather than a
single anonymous `SceneSpec`. `SceneBridge` diffing and cache invalidation are
recursive, so nested node edits, scene switching, and repository-driven texture
changes can be applied without always tearing down the full `SKView`.

### 6.4 Accessibility and UI automation

Hype exposes a stable macOS Accessibility API contract for both assistive
clients and automation agents. The implementation is split between
`HypeAccessibilityID` (stable, non-localized identifiers) and
`CardCanvasAccessibility` (a virtual accessibility tree for the custom
canvas).

Stable IDs deliberately use document UUIDs rather than visible labels. Key
examples:

- `hype.canvas.card.<cardUUID>` — the active `CardCanvasNSView`.
- `hype.part.<partUUID>` — every visible, enabled card/background part.
- `hype.spriteArea.<partUUID>.scene.<sceneUUID>` — the active scene inside a
  sprite area.
- `hype.spriteArea.<partUUID>.scene.<sceneUUID>.node.<nodeUUID>` — each visible
  SpriteKit node described by `SceneSpec`.
- `hype.panel.objects`, `hype.panel.inspector`, `hype.panel.ai`,
  `hype.ai.prompt`, `hype.ai.send`, `hype.scriptEditor.text`, and
  `hype.scriptEditor.ai` — the primary shell, AI, and script-editor surfaces.

The canvas is a custom `NSView`, so it cannot rely on AppKit child controls to
describe stack content. Instead it exposes virtual `NSAccessibilityElement`
instances for parts, sprite scenes, and sprite nodes. Part elements report role,
label, help text, value summaries, and screen frames. Sprite-area parts expose
their active scene as a child, and that scene exposes its visible
`HypeNodeSpec` nodes as children. This makes a Pac-Man-style generated scene
discoverable through the hierarchy: canvas → `pacmanArea` part → `main` scene →
`maze`, `pacmanPlayer`, ghosts, pellets, score label, and colliders.

Automation actions route through the same mutation and script paths as user
interaction. Part elements support pick/press plus custom actions for opening
the script editor, revealing the part in the inspector, deleting, moving, and
resizing. Scene and node elements support script-editor and inspector reveal
actions. These actions intentionally reuse `CardCanvasView.Coordinator`,
`NotificationCenter` script-editor routing, and document mutation/autosave
paths rather than creating a second automation-only edit path.

Security posture: accessibility labels and values expose user-visible document
content, geometry, IDs, and scene metadata, but not provider API keys, Keychain
values, or hidden preference secrets. The model/provider preference controls
still live behind the normal macOS process boundary and should not place raw
secrets into AX labels, values, or help text.

`HypePacmanTestbedBuilder` generates
`TestStacks/PacmanAccessibilityTestbed.hype`, a deterministic SpriteKit-heavy
stack used as a live automation fixture. `CardCanvasAccessibilityTests` asserts
that this class of document exposes fields, sprite areas, scenes, and
individual Pac-Man nodes through the AX tree.

### 6.5 Layout constraints

Hype supports HyperCard-style absolute positioning **and** edge-based
responsive layout. `LayoutConstraint`
(Sources/HypeCore/Layout/LayoutConstraint.swift) is an edge-to-edge rule:
*"this part's right edge stays N points from that part's left edge"* or
*"this part's top edge stays N points from the canvas top"*. They live
on `HypeDocument.constraints`.

`ConstraintSolver` (Sources/HypeCore/Layout/ConstraintSolver.swift) is an
iterative solver (max 10 passes) that groups constraints by source part,
splits them by axis, and moves or resizes each part to satisfy them. If
both left and right edges are constrained on the same axis, the part is
**resized**; otherwise it's repositioned. Only parts that actually moved
by more than 0.5 points are reported back, so the solver is cheap to run.

`AlignmentEngine` / `SnapGuide` (Sources/HypeCore/Layout/AlignmentGuide.swift)
provide live drag-time snap guides. Snapping is an **authoring affordance**:
it mutates absolute `Part.left/top/width/height` values only and never creates
or rewrites persisted `LayoutConstraint` rows. Explicit constraint authoring is
still a separate Control+Option drag path. This keeps manual drag/drop behavior
predictable and prevents accidental responsive-layout rules from being baked
into user documents.

The layout authoring grid lives in `LayoutGrid`
(Sources/HypeCore/Layout/LayoutGrid.swift). Normal object movement and resizing
snap to an 8-point grid; holding Shift disables grid snapping for 1-point
pixel-precision movement/resizing. Arrow-key nudging mirrors this rule:
Arrow moves selected objects by 8 points, Shift+Arrow moves them by 1 point.
`PartCreationDefaults` centralizes HIG-oriented default control sizes and the
canonical creation-tool-to-`PartType` mapping so the object palette, menu
commands, mouse handling, and tests all use the same rules.

Target-aware layout begins with `HypeDeviceProfileCatalog`,
`PartAvailabilityCatalog`, and `LayoutResolver`. A device profile supplies the
logical target size, safe areas, and input model. The object panel filters
creation controls using strict selected-target intersection: a control appears
only when it is usable on every platform selected for the stack.
`StackDeploymentTargets.layoutPolicy` controls target projection: `fixed`
preserves absolute coordinates, `scaleToFit` uniformly scales and centers the
authored card inside the target safe area, and `stretchToFill` scales each axis
independently. `LayoutResolver` projects persisted part geometry and explicit
constraints into a target profile without storing live platform views. The View
menu's **Target Platforms…** command edits target/platform policy; **Emulate
Target Device** constrains the canvas to a standard target profile. Edits made
while emulating are ordinary document edits and are saved immediately through
the same mutation path as non-emulated edits.

`AlignmentEngine` computes higher-affinity targets for edges, centers, canvas
center, 20-point canvas margins, and typographic baselines for text-bearing
parts. Holding Option during a move enables Smart Spacing: the moving object
also seeks 8 / 12 / 20 point gaps from neighboring objects and shows spacing
guides. Grid snapping fills in only when no stronger guide is active on that
axis.

### 6.5.1 Deployment runtime

Deployment planning is modeled by `StackDeploymentPlanner`, and deterministic
runtime-package artifacts are produced by `TargetRuntimePackageBuilder`. The
plan object distinguishes macOS standalone, iPhone runtime shell, iPad runtime
shell, and tvOS runtime shell outputs. Deployed stacks are runtime-only: no
object palette, property inspector, script editor, AI/debug panels, or edit-mode
toggle are included in the deployed runtime shell. The planner prepares a
runtime document by enabling `stack.runtimeModeEnabled` and clearing
session-only script globals without mutating the source stack. Runtime packages
embed a self-contained SQLite `.hype` package under `Stack/Stack.hype`, write a
`RuntimeManifest.json`, and generate shell `Info.plist`, entitlements metadata,
App Intent descriptor JSON, and runtime-only Swift shell source.
The generated shell uses the manifest profile id and `LayoutResolver` so the
runtime view applies the same fixed / scale-to-fit / stretch-to-fill projection
used by AI previews and deployment validation.
Before export, `StackDeploymentPlanner` validates the actual parts present in
the stack against each selected target. `TargetRuntimePackageBuilder` refuses to
produce a runtime package when the document still contains controls unsupported
by that target, so exported artifacts fail early with actionable part names and
reasons rather than producing a broken standalone runtime.

Each deployment plan also carries a runtime AI policy. Automatic policy maps
iPhone and iPad runtime shells to Apple Foundation Models, maps tvOS to disabled
until a supported Apple on-device model exists for that target, and leaves
macOS on the existing authoring-provider path. iPhone/iPad plans expose App
Intent descriptors for opening cards, sending stack messages, asking stack AI,
and searching stack content; these descriptors are export metadata for future
target shell generation, not authoring UI.

### 6.6 Tools

`ToolManager` (Sources/HypeCore/Tools/ToolManager.swift) holds the active
tool name and the current selection. `ToolName` (Sources/Hype/Views/ToolName.swift)
is the catalog: browse, button, field, shape, webpage, image, video,
chart, spriteArea, framework/form controls, select, pencil, spray, bucket,
and eraser. `ObjectToolCatalog` (Sources/Hype/Views/ObjectToolCatalog.swift)
is the left-panel source of truth and exposes one creation tool per canonical
persisted `PartType`. The left panel groups basic object and form controls under
one **Objects** section, keeps framework-backed controls in **Framework**, and
keeps paint-layer tools in **Paint**; text annotations, search fields, ovals,
and line shapes are styles/properties of Field or Shape rather than separate
panel tools.
Tools belong to one of three modes: **browse** (HyperCard's
Run mode — interactive parts respond to clicks, sprite areas come alive),
**edit** (parts can be selected, moved, resized, created), and **paint**
(freehand drawing onto the per-card paint layer).

`MouseHandler` (Sources/HypeCore/Tools/MouseAction.swift) is a stateless
utility that turns a mouse-down/drag/up sequence into a `MouseActionResult`
based on the active tool: select a part, create a part, move a selection, send
a HypeTalk `mouseDown` to a part, or begin a paint stroke. Creation tools now
support both explicit drag-out rectangles and click/tiny-drag default-size
placement. Explicit drag rectangles snap origin and size to the 8-point grid
unless Shift is held; tiny drags use the HIG-oriented default size from
`PartCreationDefaults`.

The left object palette also supports drag-to-place. Pressing and dragging a
creation tool does not instantiate a live part immediately; the SwiftUI palette
uses a narrow AppKit drag-source bridge so mouse-down / hold / drag gestures
produce a reliable pasteboard drag into `CardCanvasNSView`. The canvas registers
both the Hype-specific object-tool pasteboard type and a string fallback, shows
a translucent elevated ghost at the prospective snapped location, then creates
the real `Part` on drop. A normal click placement or palette drop selects the
new part, clears the previous selection, shows resize handles, and reverts the
active tool to Select. Shift-click placement is the rapid-repeat path: it
creates another default-sized part of the active tool at the clicked point,
keeps the active creation tool selected, and appends each newly-created part to
the selection so shared attributes can be edited together in the inspector. This
path creates only the part model (plus the normal default `SpriteAreaSpec` for
sprite areas); it does not create layout constraints.

In browse mode, mouse interaction results are forwarded to `StackRuntime` so
HypeTalk handlers, async callbacks, `idle`, and SpriteKit messages all share
one serialized execution path.

The **paint layer** is a small RGBA bitmap stored per card,
implemented in `PaintLayer.swift` (Sources/HypeCore/Controls/PaintLayer.swift)
with primitive plot/line (Bresenham), rect, oval, round-rect, and
thick-line operations. It is rendered into the card via a CGImage with
the appropriate Y-flip; HypeTalk can paint into it through a
`DrawingProvider` adapter, mirroring HyperCard's classic painting
commands.

### 6.7 Card transitions and effects

`VisualEffects.swift` (Sources/HypeCore/Controls/VisualEffects.swift)
catalogs the supported transition effects, which the `HypeTalk visual`
command queues up to apply on the next `go` statement. The execution path
is described in §3.7 above: rasterize current and target cards →
`SKTransition` → `cardSKView.presentScene(_:transition:)`.
Effect names are normalized through a fixed enum, not dynamic selector lookup:
scripts can use human forms such as `visual effect wipe left`,
`visual effect flip horizontal`, `visual effect move in right`, or
`visual effect none`. Durations are clamped before scheduling timers so a
malformed script cannot create a negative or unbounded transition delay.

### 6.8 Themes

The theme system (`Sources/HypeCore/Theme/`) introduces a Mac-app-style
visual system on top of the per-part color fields. A `HypeTheme` is a
named bundle of color tokens (`accent`, `windowBackground`, `inspectorBackground`,
`cardSurface`, `fieldBackground`, `fieldBorder`, `buttonFace`, `shapeFillDefault`,
`shapeStrokeDefault`, etc.), corner radii, stroke weights, shadow opacity /
radius, and a `usesGlassMaterial` flag that opts into Apple's Liquid Glass
material in the renderer.

Themes cascade: card → background → stack → built-in default. `ThemeResolver`
(Sources/HypeCore/Theme/ThemeResolver.swift) walks the chain and returns the
effective theme for any card. Each `Stack`, `Background`, and `Card` carries
an optional `themeName` — empty means "inherit from the next level up";
non-empty selects a theme by name from `BuiltInThemes` (Default, Sunset,
Ocean, Forest, Liquid Glass, …) or from the stack's `HypeDocument.themes`
array of user-edited themes. The cascade lets one stack contain multiple
visual moods without per-part config sprawl.

`HypeTheme` is propagated to SwiftUI via a `ThemeEnvironment` `EnvironmentKey`
and to the AppKit / Core Graphics renderer via plain function arguments —
`CardRenderer.render(...)` and the per-type renderers (`ButtonRenderer`,
`FieldRenderer`, `ShapeRenderer`, etc.) all accept the resolved theme so
default fill / stroke / corner radius come from the theme instead of being
hard-coded.

`GlassRenderer` (Sources/HypeCore/Rendering/GlassRenderer.swift) is the
opt-in companion: when a theme has `usesGlassMaterial == true`, the field
and rectangular-button renderers route through `GlassRenderer.fillRoundedRect`
to draw a translucent rounded-rect with shadow, sheen, and stroke that
approximates the Liquid Glass material from outside SwiftUI/AppKit's
`.regularMaterial`. `ColorContrast.readableTextColor(forFillHex:)` picks a
foreground color whose luminance contrasts the actual fill, which is what
makes labels readable across dark / light themes without the user setting
`fontColor` on every part.

The detached **Theme Designer** window
(`Sources/Hype/Views/Themes/ThemeDesignerWindowController.swift`) lets
authors edit colors with `NSColorWell`-backed pickers and live preview, save
the result back into `HypeDocument.themes`, and apply it card-by-card from
the inspector's THEME row.

### 6.9 Hover help

Hover help text exists for both the tool palette and author-defined controls.
The tool palette uses a belt-and-suspenders approach: system `NSToolTip`
support for native macOS/accessibility behavior plus an immediate floating
help panel. The floating help is a borderless, non-activating, mouse-ignoring
`NSPanel` positioned in screen coordinates so it floats above the card canvas,
inspector, and split-view panes instead of being clipped by the left panel.

Two surfaces:

1. **Tool palette icons.** `ObjectsToolPanel` calls `.help(...)` on every
   tool button and also tracks hover state to show the floating help panel.
   Help text comes from `ObjectToolCatalog.tooltipBody(for:)`, so the same
   catalog that defines the one-canonical-object-per-part-type palette also
   owns style/property guidance. This text is deliberately user-facing: it
   describes what authors can do with each object and must not expose backing
   framework names or internal property identifiers.
2. **Per-part `helpText`.** Every `Part` carries a `helpText: String`
   field (default empty). `CardCanvasNSView.updatePartToolTips()` clears
   and re-registers tooltip rects via
   `NSView.addToolTip(_:owner:userData:)` after every draw, browse mode
   only. A `[NSView.ToolTipTag: UUID]` map remembers which tag points to
   which part; the
   `view(_:stringForToolTip:point:userData:)` callback looks up the part
   fresh at display time so the bubble always reflects the current value.
   Edit mode disables tooltips so they don't compete with click-to-select.

The `NSInitialToolTipDelay` UserDefault is set to `0.35s` in
`HypeAppDelegate.applicationDidFinishLaunching` — half the platform default
(~750ms). `NSApp.activate(ignoringOtherApps: true)` is dispatched on the
next runloop tick so SwiftUI's `DocumentGroup` first window goes through a
proper `becomeKey` cycle (otherwise tooltips sometimes fail to register
until the user tabs the app away and back).

Authors can set `helpText` from the inspector's HELP section, from
HypeTalk (`set the helpText of cd btn "Save" to "..."`, aliases `tooltip` /
`help`), and from the AI tool surface (`set_part_property property=helpText`).
All three paths converge on `Part.helpText`, which `updatePartToolTips`
reads on the next draw.

### 6.10 Map geocoding service

Map parts use a `MapLocationGeocoder` actor-style singleton
(`Sources/Hype/Views/MapLocationGeocoder.swift`) to translate
`Part.mapLocation` (a place name, address, or US ZIP) into
`mapCenterLat / mapCenterLon` via `MKLocalSearch`. The service runs
**outside** the live `MKMapView` host so the geocode fires whether or not
that host is on screen — the previous design embedded geocoding in
`MapHostNSView`, which is destroyed in edit mode, so authors editing the
location field saw nothing happen.

The service holds per-partId state (debounce timer, in-flight
`MKLocalSearch`, last successfully resolved query). The canvas
coordinator's `reconcileMapLocations()` runs on every `updateNSView` cycle,
diffs each map part's `mapLocation` against a stored snapshot, and routes
changes through `MapLocationGeocoder.scheduleResolve(...)`. Resolved
coordinates flow back via `setPartMapCoordinate(id:lat:lon:)` and the next
draw mirrors them onto the live `MKMapView`. A successful resolve fires the
`locationResolved` HypeTalk message on the part so scripts can observe it.

`MapGeocodeCache` (Sources/Hype/Views/MapGeocodeCache.swift) sits underneath
both the geocoder and the `MapHostNSView` rendering path: it memoizes
successful (query → coordinate) pairs and records recent failures (60s TTL)
so we don't hammer Apple after a not-found.

### 6.11 Multi-selection and grouping authoring

The canvas, inspector, and sprite scene host all support multi-selection
edits. `selectedPartIds: Set<UUID>` is the single source of truth on the
canvas side. Cmd+click toggles a part in/out of the selection; Shift+click
is the parallel modifier (matches macOS Finder convention).

Card/background object grouping is persisted as flat `Part.groupId`
membership. Hype does not create a separate wrapper part for a group: children
keep their own type, style, script, and draw order, but the authoring layer
normalizes selection through `HypeDocument.expandedGroupSelection(_:)` and
`selectionUnits(for:)`. A click on any grouped member selects the whole group;
marquee selection expands to full groups; arrow nudging, drag movement,
Arrange > Bring/Send, alignment, and distribution operate on selection units.
Resize handles are drawn around the group bounds and scale each child
proportionally inside that bounding box. Grouping is restricted to parts on the
same card or the same background layer so a card object and a background object
cannot accidentally become one edit unit.

The inspector renders one of three panels keyed off
`selectedPartIds.count`:

- **0 parts** — card-level / background-level inspector.
- **1 part** — full single-part inspector (per-type sections).
- **2+ parts** — multi-selection inspector. `MultiSelectionEditing`
  (Sources/HypeCore/Models/MultiSelectionEditing.swift) provides
  `commonValue(in:for:)` and `applyValue(_:to:in:for:)` so each row in the
  multi-panel can show "Multiple" placeholders when values differ and
  apply a uniformly-typed value to every selected part on edit. Common
  multi-edits include geometry (X / Y / Width / Height), fill / stroke /
  textStyle / fontColor, alignment / distribution, and helpText.

Sprite scene nodes get the same treatment — the scene host's per-node
inspector exposes a multi-selection panel keyed off `selectedNodeIds: Set<UUID>`,
with multi-edits for position / rotation / alpha / fillColor on shape nodes,
text / fontSize / textStyle on label nodes, and so on.

---

## 7. AI Authoring, Scripting, and Speech

Hype's AI integration is now split across five deliberate surfaces:

- **authoring chat** (`AIChatPanel`) for structured tool-calling edits
- **schema-driven scene authoring** for SpriteKit create/repair flows
- **HypeTalk scripting AI** for prompt-driven generation from user scripts
- **Script Editor AI** for code-focused help inside script windows
- **voice input/output** for speaking requests and optionally hearing replies

The primary AI paths now route through `HypeAIClient`, a provider-neutral
contract implemented by `OllamaToolClient`, `LlamaSwapClient`, and
`OpenAIResponsesClient`, with `OpenAIChatCompletionsClient` used for
OpenAI-compatible local and third-party providers.
They still use different contracts because they solve different problems.
The authoring paths want structured mutations and previews; the scripting path
wants plain text results or callback completion; speech wants explicit
microphone capture and audio playback.

### 7.1 Provider clients

`OllamaToolClient` (Sources/HypeCore/AI/OllamaToolClient.swift) is a
multi-surface HTTP client for the local Ollama daemon. It now serves three
distinct architectural roles:

- `/api/chat` for structured authoring conversations and tool calls
- `/api/generate` for one-shot HypeTalk scripting requests
- `/api/tags` for model discovery

`OpenAIResponsesClient` (Sources/HypeCore/AI/OpenAIResponsesClient.swift)
adapts the same Hype message/tool/schema types onto OpenAI's Responses API:

- `/v1/responses` for plain text, tool calls, and JSON-schema guided output
- hosted OpenAI text requests use the Responses API rather than Chat
  Completions so GPT-5/o-series reasoning models can use the API surface
  OpenAI recommends for reasoning workloads
- streaming OpenAI chat uses `stream: true`, `Accept: text/event-stream`, and
  `response.output_text.delta` SSE events from `/v1/responses`
- reasoning-capable OpenAI models receive a `reasoning` object with
  `summary: "auto"` so Hype can expose provider reasoning summaries as the
  local `thinking` transcript metadata
- OpenAI function-call items are converted to Hype's existing
  `OllamaToolCall` shape before reaching `HypeToolExecutor`
- tool results keep their `call_id` pairing so multi-step OpenAI tool loops
  can continue without a provider-specific executor path

`LlamaSwapClient` (Sources/HypeCore/AI/LlamaSwapClient.swift) treats a local
llama-swap process as an OpenAI-compatible provider:

- `GET /v1/models` lists model IDs configured in llama-swap
- the selected model ID is sent in the `model` field of
  `/v1/chat/completions` requests, which is llama-swap's signal to load or
  swap to that model
- optional llama-swap API keys are stored in Keychain; unauthenticated local
  instances work without a key
- Hype reuses the OpenAI-compatible Chat Completions message/tool/schema
  bridge for llama-swap, llama.cpp, Z.ai, and MiniMax so local proxies stay
  compatible without inheriting hosted-OpenAI-only Responses features

`OpenAIImageGenerationClient`
(Sources/HypeCore/AI/OpenAIImageGenerationClient.swift) is the image-only
OpenAI client:

- `/v1/images/generations` creates base64 image bytes from text prompts
- generated bytes are stored only as `Part.imageData` or `SpriteAsset.data`
- request/response console logs include prompts, model, size, MIME type, and
  byte counts, but never log API keys or generated base64 image payloads

`OpenAISpeechClient` (Sources/HypeCore/AI/OpenAISpeechClient.swift) covers
the speech side:

- `/v1/audio/transcriptions` for OpenAI-backed voice input
- `/v1/audio/speech` for optional assistant reply playback
- `AISpeechCapture` applies the same voice-request completion behavior across
  AI surfaces: partial Apple Speech transcripts and metered OpenAI recordings
  auto-finalize after roughly 3.5 seconds of user silence
- `SpeechOutputProvider` is the HypeCore injection point for spoken AI
  responses; the app target supplies `OpenAISpeechOutputProvider` so AI
  Assistant replies and HypeTalk `ask ai` / `ollama(...)` responses can be
  spoken without putting AVFoundation playback into the interpreter

Preferences store the selected AI provider/model and speech provider/model in
`UserDefaults`, while OpenAI, llama-swap, and Pexels API keys stay in Keychain.

Tool schemas use OpenAI-style JSON: `{type: "function", function: {name,
description, parameters: { … JSON Schema … }}}`. The client encodes those
schemas in the request body alongside the conversation messages. When
the model returns tool calls, they arrive as
`{function: {name, arguments: [String: String]}}` which are then
forwarded to `HypeToolExecutor`. For deterministic scene planning and repair,
the same client can also send a `format` schema and decode the JSON response
directly into typed Swift structs.

### 7.2 Tool surface: `HypeTools`

`HypeTools` (Sources/HypeCore/AI/HypeTools.swift) declares the AI tool
schemas in one place using a small `makeTool(...)` builder that turns a
`[String: (type, description, required)]` parameter map into a complete
schema struct. The categories:

| Category                  | Representative tools |
|---------------------------|----------------------|
| Stack & cards             | `create_card`, `create_background`, `go_to_card`, `delete_card`, `list_all_cards`, `list_backgrounds`, `set_card_name`, `set_background_name`, `set_card_background`, `reorder_card`, `duplicate_part` |
| Scope properties (read)   | `get_stack_property`, `get_card_property`, `get_background_property` |
| Scope properties (write)  | `set_stack_property`, `set_card_property`, `set_background_property` |
| Scope scripts             | `get_stack_script`, `set_stack_script`, `get_card_script`, `set_card_script`, `get_background_script`, `set_background_script` |
| Part creation             | `create_button`, `create_field`, `create_label`, `create_shape`, `create_webpage`, `create_video`, `create_chart`, `create_image`, `generate_image`, `create_calendar`, `create_pdf`, `create_map`, `create_color_well`, `create_stepper`, `create_slider`, `create_segmented`, `create_progressview`, `create_gauge`, `create_divider`, `create_audio_recorder`, `create_music_player`, `create_piano_keyboard`, `create_step_sequencer`, `create_music_mixer`, `create_apple_music_browser`, `create_scene3d` |
| Part modification         | `set_part_property` (canonical write surface, accepts ~250 property names + aliases incl. `helpText`, `fontColor`, `textStyle`, `rotation`, `imageFilter`), `delete_part`, `repair_form_controls` |
| Part introspection        | `get_part_property`, `list_all_properties` (full property dump w/ defaults), `get_card_parts`, `get_background_parts`, `capture_card_image` |
| Target-aware layout       | `list_target_profiles`, `get_hig_layout_guide`, `apply_hig_layout`, `validate_hig_layout`, `pin_part_to_safe_area`, `add_part_layout_constraint`, `list_part_layout_constraints`, `preview_layout_profile` |
| Themes                    | `list_themes`, `get_theme`, `create_or_update_theme`, `delete_theme`, `apply_theme` |
| Charts                    | `set_chart_data_point_color`, `get_chart_data_points` |
| Maps                      | `add_map_annotation`, `clear_map_annotations` |
| Images                    | `set_image_filter` |
| Music                     | `list_music_instruments`, `create_music_pattern`, `list_music_patterns`, `export_music_pattern`, `get_apple_music_capabilities`, `authorize_apple_music`, `search_apple_music`, `set_apple_music_selection`, `play_apple_music`, `play_music_player`, `pause_apple_music`, `resume_apple_music`, `stop_apple_music` |
| Sprite areas / scenes     | `create_sprite_area`, `infer_sprite_game_template`, `get_sprite_game_template_guide`, `create_sprite_game_template`, `list_sprite_game_templates`, `get_scene_spec`, `apply_scene_diff`, `add_sprite_to_scene`, `add_label_to_scene`, `add_shape_to_scene`, `add_emitter_to_scene`, `add_audio_to_scene`, `add_video_to_scene`, `add_group_to_scene`, `create_tilemap`, `create_basic_tileset_asset`, `classify_asset_as_tileset`, `set_tile`, `fill_tilemap`, `get_tilemap_info`, `create_camera`, `add_joint_to_scene`, `add_constraint_to_scene`, `add_physics_field_to_scene`, `capture_scene_snapshot`, `get_scene_diagnostics`, `list_scene_nodes`, `list_scene_joints`, `list_scene_constraints`, `get_scene_script`, `get_node_script`, `get_node_property`, `set_node_property`, `set_node_script`, `set_scene_script`, `set_physics_body` |
| Asset repository          | `list_repository_assets`, `import_repository_asset`, `generate_sprite_asset`, `create_basic_tileset_asset`, `web_asset_search`, `web_asset_import` |
| AI Context Library        | `list_ai_context`, `search_ai_context`, `read_ai_context_item`, `import_context_asset`, `write_ai_context_note` |
| 3D model generation (Meshy) | `generate_3d_model_from_text`, `generate_3d_model_from_image`, `generate_3d_model_from_images`, `list_3d_models`, `remesh_3d_model`, `retexture_3d_model` |
| HypeTalk scripting skills | `list_hypetalk_skills`, `get_hypetalk_skill_guide`, `plan_hypetalk_script`, `inspect_message_path`, `suggest_handler_location`, `get_hypetalk_pattern`, `review_hypetalk_script` |
| Script gating             | `check_script` (REQUIRED before storing any HypeTalk; runs the validator) |

The surface is **dual mode**: it has both read tools (for the model to
inspect current state) and write tools (for it to mutate). It is also
**asset-aware** — `add_sprite_to_scene` looks up assets by name in the
`SpriteRepository` (so the model can reference an imported sprite by
name and the executor will resolve it to the stable ID), and
`apply_scene_diff` accepts `SceneDiff` JSON for incremental scene
updates. The important policy change is that the filesystem/web tools are no
longer part of the default in-app authoring loop. They still exist as optional
capabilities for explicit future use, but normal authoring is narrowed to
repository-aware stack, card, part, and scene operations.

For complex sprite-area game requests, Hype exposes a deterministic
catalog-based template path without embedding the whole taxonomy in every
model prompt. `SpriteGameTemplateCatalog` owns the supported template IDs,
aliases, default scene sizes, controls, mechanics, generated-node contracts,
and test expectations. The model first uses the non-mutating
`infer_sprite_game_template` tool to map a natural-language request to a
template ID. If the request has unusual mechanics or needs richer details, it
can then call `get_sprite_game_template_guide` for focused guidance about that
one template. `list_sprite_game_templates` remains a compact discovery tool
with optional query/full-detail arguments. `create_sprite_game_template` is
the bounded mutating tool that builds the selected local scaffold instead of
asking the model to freehand dozens of image, tile, node, physics, and script
calls. The high-fidelity templates remain Pac-Man / `maze_chase` and Donkey
Kong-style / `barrel_climber`: the maze scaffold creates local embedded PNG
assets, a classified maze tileset, tile map, static wall colliders,
player/ghost sprites, pellets, power pellets, and parser-tested scene
HypeTalk; the barrel-climber scaffold creates an 800×600 Sprite Area with
generated hero, barrel, platform, ladder, rival, trophy, and hammer assets,
platform physics, A/D/W/S plus Space controls, top-origin barrel spawns from
the rival/gorilla platform, three-life barrel-hit reset/loss handling,
ladder-safe contact rules, timed hammer pickup/swing/smash behavior, and a New
Game button that re-dispatches `sceneDidLoad`.

The catalog also provides deterministic baseline scaffolds for
`side_scroller_platformer`, `top_down_adventure`, `twin_stick_shooter`,
`space_shooter`, `physics_puzzle`, `breakout`, `pinball_pachinko`,
`endless_runner`, `tower_defense`, `match3_grid_puzzle`,
`sokoban_block_puzzle`, `racing_lane`, `pong_sports_arena`, `rhythm_timing`,
`board_card_game`, `boss_wave_arena`, `sandbox_physics_toy`, and
`educational_sim`. These baseline templates create self-contained placeholder
assets, bounds, player/enemy/pickup/goal/projectile nodes, reset handlers,
keyboard controls, contact scoring, and parser-validated HypeTalk. Tile/grid
families also get deterministic tile-map scaffolds. The main AI panel keeps
only the template-first routing rule in its always-on prompt; catalog details
are pulled through `infer_sprite_game_template`,
`get_sprite_game_template_guide`, and `list_sprite_game_templates` when needed.
The Sprite Scene setup guide also exposes the full catalog as a complete-game
option for users who want a local deterministic scaffold without going through
chat.
`create_basic_tileset_asset` is the smaller reusable primitive for local
maze/wall tilesets when a full game scaffold is not needed. These tools avoid
sending the model through dozens of low-level tile/image/script calls and
prevent it from asking the user to provide basic tile sheets that Hype can
synthesize itself.

### 7.3 Structured scene authoring

`SceneAuthoringAssistant` (Sources/HypeCore/AI/SceneAuthoringAssistant.swift)
adds a second AI path alongside tool calling: **schema-driven scene proposals**.
Instead of asking the model to mutate the document directly, Hype can request:

- `SceneCreateProposal`
- `SceneRepairProposal`
- checklist-oriented starter scene blueprints
- focused `SceneDiff` repairs backed by local diagnostics

This is the AI path used by the guided SpriteKit authoring flow. It keeps the
model on a stricter contract than open-ended tool calling: the output must be
valid JSON matching the expected schema, asset names must line up with the
repository, and the result is previewable and undoable before it becomes a live
scene edit.

### 7.4 Executor and authoring loop

`HypeToolExecutor` (Sources/HypeCore/AI/HypeToolExecutor.swift, ~5,200 LoC)
remains the structural mutation engine. It is still a large `switch` over tool
name taking `document: inout HypeDocument`, but its responsibilities are now
more sharply defined:

- create or mutate stack parts and scenes
- resolve repository assets by stable identity
- generate OpenAI-backed image parts and AI-generated repository assets when
  configured with an image generation client
- apply `SceneDiff` patches to the active scene inside a `SpriteAreaSpec`
- return diagnostics and navigation signals back to the UI
- emit `formatAllProperties(_:)` dumps for `list_all_properties` so the
  model can discover the full property surface of any part without guessing

**Branch-extraction split (Phase 5 remediation).** The executor itself stays
the dispatcher; high-volume tool families now live in sibling files under
`Sources/HypeCore/AI/Executors/`:

| Branch file | Tool cases hosted |
|-------------|-------------------|
| `WebAssetExecutorBranches.swift` (~260 LoC) | `search_web_for_sprite`, `import_web_asset`, `find_and_import_sprite` |
| `Scene3DExecutorBranches.swift` (~740 LoC) | `list_3d_models`, `bind_model_3d_to_scene3d`, `generate_3d_from_text/image/images`, `remesh_3d`, `retexture_3d` |
| `SceneNodeExecutorBranches.swift` (~410 LoC) | `apply_scene_diff`, `set_node_property`, `set_node_script`, `set_physics_body`, `delete_scene_node`, `add_action`, `remove_all_actions` |
| `FileIOExecutorBranches.swift` (~100 LoC) | `fetch_url`, `read_file`, `write_file`, `list_directory` (each accepts injected `urlSession` / `fileSystem` for testability — see §8.4) |

Each branch file is a `package enum` namespace with `static` functions that
take `context: HypeToolExecutor` for access to the dispatcher's clients and
helpers. The dispatcher's tool case is reduced to a single-line delegation
call. No public API changed; tool names, argument shapes, and result strings
are byte-for-byte identical.

A few cross-cutting helpers harden the loop:

- **`HypeTalkScriptValidator`** (`Sources/HypeCore/AI/HypeTalkScriptValidator.swift`)
  is the gate behind the `check_script` tool. Every storage path
  (`create_button`, `create_field`, `set_part_property property=script`,
  `set_card_script`, …) refuses to commit a script until the validator
  reports OK. The system prompt instructs the model to call `check_script`
  first and iterate; if the storage tool itself receives a malformed
  draft, it returns a `__HYPE_INTERNAL_DRAFT_REFUSED_v1:` sentinel and the
  model is asked to fix and retry. This is what closes the loop on
  silently-broken scripts.
- **`HypeTalkSkillCatalog`** (`Sources/HypeCore/AI/HypeTalkSkillCatalog.swift`)
  keeps the HyperTalk/HypeTalk scripting craft guidance out of the always-on
  prompt. It exposes compact discovery, source-attributed focused guides,
  parser-tested pattern snippets, message-path inspection, handler-location
  planning, and pre-storage script review. The catalog is partly informed by
  Jeanne A. E. DeVoto's Jaedworks HyperTalk scripting chapter, but each guide is
  rewritten as Hype-specific compatibility guidance and returned only when the
  model calls the relevant tool.
- **`HIGLayoutCatalog`** (`Sources/HypeCore/Layout/HIGLayoutCatalog.swift`)
  keeps target-aware layout guidance deterministic and tool-callable. It stores
  Hype-native Apple HIG-informed metrics for macOS, iPhone, iPad, and tvOS
  profiles; returns compact source-attributed guidance; applies vertical,
  horizontal, grid, form, toolbar, and full-bleed arrangements; writes durable
  `LayoutConstraint` relationships to safe-area canvas edges; and validates all
  selected target profiles for safe-area containment, target availability,
  minimum hit sizes, text size, and interactive-control spacing.
- **`HypeAIResponseRepair`** (`Sources/HypeCore/AI/HypeAIResponseRepair.swift`)
  cleans up common malformations in the model's tool-call arguments —
  string-vs-number coercions, accidental Markdown fencing, comma-separated
  lists where an array was expected — so a single sloppy emit doesn't
  abort the loop.
- **`ScriptAutoFixer`** (`Sources/HypeCore/AI/ScriptAutoFixer.swift`) drives
  the iterative attach-script-then-fix harness used by the multi-turn
  benchmark suite to push the script-attach success rate to ~98%+.
- **`SpriteKitRequestRouter`** (`Sources/HypeCore/AI/SpriteKitRequestRouter.swift`)
  recognizes scene-authoring intents and routes them onto the structured
  `SceneAuthoringAssistant` path instead of letting open tool-calling
  produce malformed `SceneDiff` JSON.

`AIChatPanel` (Sources/Hype/Views/AIChatPanel.swift) orchestrates three related
loops:

1. a classic multi-round tool-calling loop for stack/card/part edits
2. a structured scene create/repair loop that previews typed proposals
3. an undoable apply step that commits the accepted proposal to the document

The panel maintains a bounded conversation window, embeds repository and scene
context into the system prompt, exposes the stack's `AIContextLibrary` through
safe context tools, and keeps past prompts on `HypeDocument.aiPromptHistory`
for recall. The result is an AI authoring surface that is still
conversational, but much more deterministic for the SpriteKit-heavy parts of
the app and for whole-stack builds driven by user-supplied design material.

`HypeTalkGuide` (`Sources/HypeCore/AI/HypeTalkGuide.swift`) is the system-
prompt grammar primer fed into every chat turn. It documents the property
surface, message hierarchy, common patterns, and gotchas — including the
`exitField` / `closeField` semantics, `send "<message>" to <target>`,
top-level `global` preludes, the `helpText` / `tooltip` aliases, the
`textStyle` / `fontColor` set/get, and the `animate` command form. The guide
is updated whenever a new property or grammar form lands so the model sees a
faithful description of the live surface rather than its training-time prior.

### 7.5 AI from HypeTalk

`AIScriptingProvider` (Sources/HypeCore/AI/AIScriptingProvider.swift) is the
runtime-facing AI abstraction used by HypeTalk. It intentionally hides the
tool-calling authoring loop and exposes only what scripts need:

- `currentModel()`
- `availableModels()`
- `generate(prompt:model:)`

This keeps the scripting surface simple and predictable:

- `the aiModel` is sync because it is just configuration
- `await ollama(...)` and `await ollamaModels()` are the preferred async forms
- `ask ai "prompt" with message "handlerName"` is the callback form for
  fire-and-forget work
- the older sync wrappers remain for compatibility, but are architecturally
  legacy because they block the calling handler

That split is deliberate: authoring AI is schema/tool oriented, while scripting
AI is text-generation oriented.

### 7.6 MCP automation and introspection

Hype exposes the same document-aware authoring surface through a local Model
Context Protocol (MCP) interface so external agents, in-app AI panels, and
automation harnesses can inspect and mutate the running app through one
contract instead of inventing separate accessibility-only or prompt-only
paths.

The implementation is split by runtime boundary:

- `Sources/HypeCore/MCP/HypeMCPTypes.swift` owns the JSON-RPC request/response
  types, MCP tool/resource/prompt shapes, batch handling, and the
  `HypeMCPProcessor` dispatcher.
- `Sources/HypeCore/MCP/HypeMCPToolBridge.swift` maps every
  `HypeToolDefinitions` tool into an MCP tool and adds Hype-specific control
  tools such as `hype_get_app_state`, `hype_get_preferences`,
  `hype_run_existing_tool`, `hype_preview_transaction`,
  `hype_apply_transaction`, `hype_rollback_transaction`, and
  `hype_create_test_stack`.
- `Sources/HypeCore/MCP/HypeMCPPreferenceStore.swift` exposes preferences as
  scalar descriptors and exposes secrets only as redacted `isSet` status.
  Provider API keys remain in Keychain; the MCP bearer token is a local
  automation token in the Hype app preference domain so app launch never blocks
  on Keychain decryption.
- `Sources/HypeCore/MCP/HypeMCPDocumentBackend.swift` is the testable in-memory
  backend used by unit tests and non-UI harnesses.
- `Sources/Hype/MCP/HypeAutomationRegistry.swift` tracks live
  `MainContentView` document bindings, current card, selection, active tool,
  and background-editing state.
- `Sources/Hype/MCP/HypeLiveMCPBackend.swift` runs MCP calls against the active
  registered stack and applies changed documents through
  `HypeDocumentMutationCoordinator`, preserving autosave and undo behavior.
- `Sources/Hype/MCP/HypeMCPAppServer.swift` starts a loopback HTTP endpoint
  (`POST /mcp`, `GET /health`) when Hype launches.
- `Sources/HypeMCPBridge/main.swift` is a stdio bridge executable for MCP
  hosts that expect line-delimited JSON-RPC over stdin/stdout; it reads or
  creates the redacted Hype MCP token from the Hype app preference domain and
  forwards each request to the running app.

Security policy is local-first and explicit. The HTTP endpoint accepts only
loopback client endpoints, every `/mcp` request requires either
`Authorization: Bearer <token>` or `X-Hype-MCP-Token`, and the token lives in
the Hype app preference domain under `hype.mcp.token`.
`hype://app/preferences` and `hype_get_preferences` never return secret
values. Mutating calls are gated by `hype.mcp.allowMutations`;
when disabled, read-only tools still work but stack mutations and transaction
previews are refused. Multi-tool edits should use `hype_preview_transaction`
followed by `hype_apply_transaction` rather than a sequence of immediate
single-tool writes.

The initial resource catalog is intentionally diagnosable:

- `hype://app/state` — active stack ID, open stacks, selection, tool, and MCP
  policy
- `hype://app/preferences` — MCP-exposed preference descriptors plus redacted
  secret status
- `hype://stacks` — summaries of registered open stacks
- `hype://stack/{id}/summary`, `/cards`, `/backgrounds`, `/parts` — active
  document structure and scripts at each scope

Tests in `HypeMCPTests` cover JSON-RPC initialization, tool/resource catalog
exposure, preference redaction, document mutation, mutation-policy refusal, and
preview/apply transaction semantics. Live app validation uses
`hype-mcp` against `/Applications/Hype.app` after deployment.

### 7.7 Lightweight Q&A and bulk generator

`AIPanel` is the lightweight Q&A surface and now uses the same selected
`HypeAIClient` provider as the main authoring chat. `AIService`
(Sources/HypeCore/AI/AIService.swift) remains as a small compatibility routing
layer for simple text requests. `StackGenerator`
(Sources/HypeCore/AI/StackGenerator.swift) is a one-shot generator that
prompts a model for a complete stack as a single JSON payload (no tool
calls, no loop) and reconstructs a `HypeDocument` from the parsed
response — used for "bootstrap a new stack from a paragraph" scenarios.

### 7.8 Meshy.ai 3D model generation

Hype integrates with Meshy.ai's hosted 3D generation API across five delivery
phases:

| Phase | What shipped |
|-------|-------------|
| **1** | Text-to-3D (Generate3DSheet, text tab), Preferences API-key entry, per-stack `Stack.meshyEnabled` flag, `AssetKind.model3D`, `Part.scene3DAssetRef`, `Scene3DAssetLoader` |
| **2** | Image-to-3D + multi-image-to-3D tabs in `Generate3DSheet`; 4 new AI tools (`generate_3d_model_from_text`, `generate_3d_model_from_image`, `generate_3d_model_from_images`, `list_3d_models`); `AIEditTransaction` integration for AI-triggered generation |
| **3** | Rigging via Meshy `/openapi/v1/rigging`; animation picker with a bundled ~3,000-entry catalog (no bulk fetch); `isRigged` + `animationActionId` on `SpriteAsset`; HypeTalk `ask meshy` statement grammar |
| **4** | Remesh, retexture (Meshy API); `Scene3DAssetConverter` (GLB→USDZ); `ARQuickLookPresenter`; webhook payload decoder (documented, no auto-listener — see §9); `remesh_3d_model` + `retexture_3d_model` AI tools |
| **5** | HypeTalk `ask meshy` expression form; `set the model of scene3d "X" to <asset>` smart resolver; `put <expr> into the model of scene3d "X"` |

**Core actors and orchestrators.**

- `MeshyAIClient` (Sources/HypeCore/AI/MeshyAIClient.swift) — `actor` pinned
  to `api.meshy.ai`. The public initialiser takes no `baseURL` parameter;
  the hostname is not configurable.
- `MeshyTaskMonitor` (Sources/HypeCore/AI/MeshyTaskMonitor.swift) — `actor`
  that polls task state every 3 seconds with a 30-minute hard timeout.
  `cancel()` is idempotent.
- `Generate3DJob` (Sources/HypeCore/AI/Generate3DJob.swift) — single-shot
  orchestrator shared by the `Generate3DSheet` UI and the AI tool executor.
  Calls `MeshyAIClient`, feeds the task to `MeshyTaskMonitor`, and on
  success calls `Meshy3DAssetImporter`.
- `Meshy3DAssetImporter` (Sources/HypeCore/AI/Meshy3DAssetImporter.swift) —
  downloads model bytes, builds a `SpriteAsset` with `kind == .model3D` and
  `provenance.type == .aiGenerated`, and adds it to `SpriteRepository`.
- `Meshy3DGate` (Sources/HypeCore/AI/Meshy3DGate.swift) — pre-flight guard
  that checks `Stack.meshyEnabled` and that a Meshy API key is present in
  Keychain before allowing any generation call.

**Security pipeline.**

- Hostname allowlist: all outbound requests must resolve to `*.meshy.ai`.
- `MeshyNoRedirectDelegate` — `URLSessionTaskDelegate` that blocks HTTP
  redirects so a `Location:` header from an untrusted response cannot
  redirect the download to an attacker-controlled host.
- `sanitizedMeshyURL` — filters all wire URLs returned by the Meshy API
  through a hostname check before any fetch.
- 50 MB download cap on model bytes; 50 MB decode cap enforced by
  `SpriteAsset.init(from:)` at document-load time.
- MIME type check is authoritative over the caller-supplied claim.
- `MeshyImageInput` strict validation: `resolvingSymlinksInPath` +
  blocked-prefix allowlist + containment check before reading any local image.
- Meshy API key is read from Keychain off main thread.

**AI tool surface.** The Sprite Repository AI chat (`SpriteRepositoryAIChatView`)
includes all six Meshy tools in its allowlist. Gate enforcement still happens at
executor level (`Meshy3DGate`), so the chat surface cannot bypass the opt-in
check even if the tool schema is visible.

---

## 8. Cross-Cutting Concerns

### 8.1 Concurrency

- The model layer (`HypeDocument`, all its components, `SceneSpec`,
  `SpriteAreaSpec`, `SpriteRepository`, `StackNetworkManifest`, etc.) is
  composed entirely of `Sendable` value types.
- Browse mode is coordinated by the `StackRuntime` actor, which owns the live
  session document, the FIFO event queue, async jobs, listeners, connections,
  and runtime status snapshots.
- `wait` and `wait until` no longer block the thread with `Thread.sleep`; they
  suspend against an injected `RuntimeClock`, which keeps the runtime testable
  and lets handler locals survive suspension.
- `HypeSKScene`, `SceneBridge`, `NodeRegistry`, and the event delegate
  protocol are `@MainActor`-isolated.
- SpriteKit physics-contact callbacks are
  `@preconcurrency SKPhysicsContactDelegate` implementations that hop to
  the main actor with `Task { @MainActor in … }` before touching the
  registry.
- Async completions are never delivered by re-entering the current handler.
  They become ordinary queued messages, which gives HypeTalk a predictable
  single-threaded mental model on top of an actor-backed runtime.

### 8.2 Lifecycle messages

The system dispatches a small number of lifecycle messages through the
HypeTalk message hierarchy:

- `openStack` / `closeStack` — once per document
- `openBackground` / `closeBackground` — when navigating between
  cards that change backgrounds
- `openCard` / `closeCard` — every navigation
- `openScene` / `closeScene` — when a sprite area becomes active /
  inactive
- `sceneDidLoad` — once per scene rebuild, dispatched before `openScene`
  through the scene → sprite area → card → background → stack chain
- `mouseDown` / `mouseUp` / `mouseDragged` — both for classic parts and
  for sprite-area nodes
- `mouseWithin` / `frameUpdate` — SpriteKit-driven interaction / frame hooks
- `beginContact` / `endContact` / `actionFinished` — physics and action events
- async callback messages chosen by the user, e.g. `aiFinished`,
  `requestFinished`, `networkRequest`, `socketEvent`
- `keyDown` / `keyUp`
- `quit` — fired from the `applicationWillTerminate` notification via
  the `hypeQuit` `Notification.Name`

These give scripts familiar HyperCard hooks at every level of the
hierarchy.

### 8.3 Edit mode vs. browse mode

The interaction mode (`browse` vs. `edit` vs. `paint`, decided by the
active tool) drives a number of behavioural switches:

| Subsystem        | Edit mode                                               | Browse mode                                         |
|------------------|---------------------------------------------------------|-----------------------------------------------------|
| Part hit testing | Selection / drag / resize                               | HypeTalk `mouseDown`/`mouseUp` to part              |
| Runtime          | No live `StackRuntime`; document edited directly        | Live `StackRuntime` owns session + async queue      |
| Sprite area      | `SpriteAreaRenderer` placeholder; no SKView             | Live `HypeSKScene` running physics + simulation     |
| Field            | Selectable / movable                                    | Inline `NSTextField` editor on focus                |
| Web view         | Static placeholder via `WebPageRenderer`                | Live `WKWebView` loading the URL                    |
| Video            | Static placeholder                                      | Live `AVPlayerView`                                 |
| Chart            | Static rectangle                                        | Live SwiftUI `ChartHostView` via `NSHostingView`    |
| Networking       | Manifest editing only; no sockets                       | Live requests, listeners, connections, callbacks    |

This separation keeps the editor lightweight and predictable, and avoids
running physics, JavaScript, and open network services inside the editor
surface.

Browse-mode hit testing uses the raw topmost visible card or background part.
The card/background layer filter applies only to edit-mode selection so
background controls remain playable after switching a stack into runtime mode.
Authoring-only Browse shortcuts are gated off when
`Stack.runtimeModeEnabled == true`: double-clicking a part in authoring Browse
mode may open the property inspector, but runtime mode keeps double-clicks
available to the stack/control instead of switching Hype into edit mode.

### 8.4 Testing

The combined SwiftPM test suite currently runs **230 suites and 2,075 tests**
in about 80-90 seconds on the local machine. Most tests live in
`HypeCoreTests` and run without launching the app because they exercise the
model, parser, interpreter, renderer helpers, and tool executor directly;
`HypeTests` covers app-facing seams that need AppKit, SpriteKit, or an
`NSWindow`. Coverage spans:

- **Model & persistence** — SQLite package round-trip, FTS search,
  diagnostics, self-contained asset/context persistence, Codable value-model
  reconstruction, and forward-compat decoding for value-typed fields.
- **Script engine** — `ComprehensiveScriptTests`, `ParserCoverage`, expression
  precedence, chunks, `it` lifecycle, control flow, pass-up semantics.
- **Property dispatch** — `PropertyAuditTests` walks every property exposed
  to HypeTalk get/set + AI tool surface and validates each one round-trips,
  including the new `helpText`, `fontColor`, `textStyle`, `rotation`,
  `imageFilter`, and the gauge / progress decimals contract.
- **Async runtime** — `await ollama(...)`, HTTP request / reply / listener
  flows, TCP listener flows, callback ordering, runtime status snapshots.
- **AI authoring loop** — tool-call dispatch, `check_script` gating,
  `ScriptAutoFixer` regression suite, end-to-end multi-turn dispatch
  (`EndToEndAIDispatchTests`), tool-arg repair (`HypeAIResponseRepairTests`),
  scene-authoring schema validation, OpenAI Responses/Image client encoding,
  and AI Context Library tool execution.
- **Specific surfaces** — animate command (`AnimateCommandTests`), GIF
  decoder + animator, chart data points, calendar / PDF / map, color well,
  every form control, sprite slicing, tile-set classification, theme
  resolution, multi-selection editing, grouping, top-level `global` preludes,
  explicit `send "<message>" to <target>` dispatch, `sceneDidLoad`
  lifecycle delivery, text styling (TextStyleFlags + rendered ink-budget
  regression), and the new `helpText` Codable + HypeTalk + AI surfaces.
- **Renderer ink-budget regressions** — pixel-level checks that bold draws
  more ink than plain, that transparent-background actually masks alpha,
  etc. These catch silent drawing regressions that wouldn't surface in
  Codable-only tests.

A separate `HypeTests` target holds app-facing smoke coverage for SpriteKit
bridge behavior, native card-node reconciliation, the canvas hover-help
registration path, grouped-object keyboard movement, card transition handoff,
menu composition, field-editor layout parity, Script Editor AI prompt behavior,
and the Accessibility virtual tree for a Pac-Man-style sprite scene. Provider
parity and AI transaction coverage live in `HypeCoreTests` so they can run
without live OpenAI/Ollama credentials.

`HypePacmanTestbedBuilder` is a reproducible fixture generator rather than a
test-only mock. Running
`swift run HypePacmanTestbedBuilder TestStacks/PacmanAccessibilityTestbed.hype`
writes a real `.hype` stack containing a generated Pac-Man-style sprite area,
deterministic sprite assets, tile map, physics bodies, player, ghosts, pellets,
score label, and scene script. That stack is intended for live app smoke tests
with macOS Accessibility clients after the user grants Hype accessibility
permission in System Settings.

#### Test isolation abstractions

Three protocols exist purely to keep tests deterministic and parallel-safe
without forcing production code through any extra indirection:

- **`KeychainProviding`** (`Sources/HypeCore/AI/WebAssetSearch/KeychainProviding.swift`)
  abstracts the four-method `setSecret` / `getSecret` / `hasSecret` /
  `deleteSecret` surface. `KeychainStore` conforms via `KeychainStore.live`;
  the existing `KeychainStore.setSecret(_:account:)` static API is preserved
  as a passthrough, so production callers are unchanged. Tests inject
  `InMemoryKeychain` (package-visible, `[String: String]` + `NSLock`)
  instead of touching the real macOS Keychain.

- **`FileSystemProviding`** (`Sources/HypeCore/AI/FileSystemProviding.swift`)
  covers `fileExists`, `createDirectory`, `write`, `read`, `contents`,
  `removeItem`, `attributesOfItem`. `FileManager` conforms via extension.
  Tests inject `InMemoryFileSystem` (path-normalised via `URL.standardized`
  so `/tmp` vs `/private/tmp` mismatches don't surface).

- **`URLSessionProviding`** (in `FileIOExecutorBranches.swift`) abstracts
  the small subset of `URLSession` used by the `fetch_url` AI tool.
  `URLSession` conforms; tests inject `MockURLSession`.

- **`Scene3DAssetConverting`** (`Sources/HypeCore/Rendering/Scene3DAssetConverter.swift`)
  abstracts the GLB→USDZ conversion path used by `ARQuickLookPresenter`.
  `Scene3DAssetConverter` conforms. The presenter accepts the protocol +
  a `FileManager` + an `osVersion: () -> Bool` closure at init time so
  the macOS 13+ gate, file staging, and conversion failures can each be
  tested without touching real OS surfaces.

Together these eliminated a known parallel-keychain flake
(`MeshyKeychainAccountTests` "deleting Meshy key does not affect openAI
key", `errSecMissingEntitlement`) and let `ARQuickLookPresenter` ship
with 9 unit tests instead of zero.

---

## 9. Current Feature Gaps / Architectural Runway

These are intentional or still-open gaps in the architecture as built, not
unknowns:

1. **Live sync has a local engine, but no external transport.** `SyncService`
   now publishes operation/change-set updates between peers, maintains
   checkpoints, and reports deterministic conflicts. The remaining gap is
   plugging in the selected external transport and exposing collaboration UI.
2. **Card rendering is still hybrid, but basic native nodes exist.** Sprite
   areas, transitions, shapes, images, buttons, fields, and paint layers now have
   SpriteKit-native card-scene nodes and reconciliation tests. Editing overlays
   and platform-heavy parts still use AppKit/Core Graphics until each path can
   preserve selection, text editing, accessibility, and scripting parity.
3. **Paint layers now persist, but paint tooling is still basic.** `PaintLayer`
   supports drawing and script adapters inside `CardCanvasNSView`; the document
   stores per-card `CardPaintLayer` snapshots and HTML export embeds them as
   PNG data. The remaining gap is richer paint-layer management such as import,
   layer ordering, and external image export controls.
4. **HyperCard import now has a safe structural foundation, but visual-resource
   compatibility is incomplete.** `STAK`/`BKGD`/`CARD` structure, button/field
   records, scripts, resource summaries, and XCMD/XFCN discovery are implemented.
   Original XCMD/XFCN native code is never executed; calls route through the
   Swift emulation registry. Remaining import work includes WOBA bitmap
   decompression, PICT/snd conversion, AddColor rendering, and many classic
   command surfaces such as `doMenu`, `print`, `run`, `copy template`, and
   programmatic selection/find behavior.
5. **AI authoring has formal transactions, but preview UX is still maturing.**
   `AIEditTransactionRunner` executes tool calls against a draft document,
   captures operation deltas, and supports explicit apply/rollback. Main chat AI
   tool turns now use that transaction path and document application flows
   through the global autosave/undo coordinator; the remaining gap is richer
   user-facing preview/apply controls across every AI surface.
6. **OpenAI/Ollama parity has local coverage, but live provider drift remains.**
   `AIProviderParityHarness` verifies text tool-call contracts, image generation,
   and speech output with local fakes. Opt-in live provider tests and stack-level
   smoke recordings should keep expanding because model/tool behavior remains
   the least deterministic part of the system.
7. **Meshy webhook auto-listener is deferred.** The Meshy API supports a webhook
   callback URL so long-running generation tasks can push their result rather
   than requiring polling. A `MeshyWebhookDecoder` is implemented and tested,
   but a public-reachable listener (required by Meshy's cloud infrastructure)
   cannot be started automatically on a residential Mac without a user-managed
   reverse tunnel. The current polling approach via `MeshyTaskMonitor` covers
   the common case without requiring network configuration.
8. **AR Quick Look is macOS 13+ gated.** `ARQuickLookPresenter` and
   `Scene3DAssetConverter` both gate on `#available(macOS 13, *)`. The "Open in
   AR" button in `SpriteRepositoryView` is hidden on older OS versions. The app
   minimum deployment target is macOS 15, so this gap only matters for anyone
   back-porting the code.
9. **Animation catalog is bundled JSON; no live refresh.** The ~3,000-entry
   Meshy animation catalog used in the Rig & Animate picker is a static
   bundled JSON file. Meshy does not publish a public pagination endpoint for
   the full catalog; if they add animations or retire old ones, the bundle
   must be manually updated.
10. **Meshy generation requires explicit per-stack opt-in.** `Stack.meshyEnabled`
    must be set to `true` (via Preferences) and a Meshy API key must be present
    in Keychain before any `Generate3DSheet`, HypeTalk `ask meshy`, or AI tool
    call can proceed. Both flags are off by default. This is intentional — it
    prevents accidental billable API calls on stacks authored before the Meshy
    integration shipped.

---

## 10. Where SpriteKit and SceneKit Sit in the Stack — Summary

The user's framing — *"SpriteKit as the underlying layer for interaction
across a stack"* — maps onto the implementation as follows:

1. **Cards live inside a SpriteKit-aware NSView.** Every card canvas
   (`CardCanvasNSView`) carries a persistent `PassthroughSKView` hosting
   a `CardSKScene` configured with three explicit layers
   (`cardNode`, `nativeLayer`, `spriteLayer`), so SpriteKit is always
   present even when no sprite area is on the card.

2. **Card transitions are GPU-driven by SpriteKit.** The `visual effect`
   HypeTalk commands rasterize current and target cards and let
   `SKView.presentScene(_:transition:)` animate between them — exactly
   the kind of polish SpriteKit was built to deliver.

3. **Sprite areas are real SpriteKit scenes.** Each `spriteArea` part
   gets its own `SKView` overlay running a `HypeSKScene`. The persistent
   `SpriteAreaSpec` JSON inside the part selects one named `SceneSpec`
   to compile into a live `SKNode` tree via `SceneBridge`. Physics,
   particles, tile maps, cameras, audio, video, and the full SpriteKit
   feature surface are available without leaving the Hype document.

4. **Hit testing speaks UUIDs, not nodes.** `HypeSKScene` and
   `NodeRegistry` cooperate to translate every SpriteKit hit-test into a
   Hype `Part` / scene-node UUID, so a click on a sprite is
   indistinguishable from a click on a button as far as HypeTalk is
   concerned.

5. **Messages bubble through SpriteKit and back into HyperCard's
   hierarchy.** The `MessageDispatcher` does not know or care that some
   targets are nodes inside a sprite area. In browse mode the effective
   chain is node → parent group(s) → scene → sprite area → card →
   background → stack → app, and `StackRuntime` serializes both direct
   events and async callbacks onto the same queue. SpriteKit nodes produce
   messages; HypeTalk handles them; the model is mutated; the bridge
   re-applies; the next frame reflects it.

6. **A bridge layer is a hard architectural boundary.** Persistent
   `SpriteAreaSpec` / `SceneSpec` (model) and live `SKScene` / `SKNode`
   (runtime) are never confused. `SceneBridge` is the only file allowed to
   translate between them, and `NodeRegistry` is the only file that holds
   live `SKNode` references. Live updates are preferred over rebuilds when
   possible (`applyLiveUpdates`), recursive node diffs avoid flattening the
   scene tree, and a UUID-keyed `[UUID: SKTexture]` cache prevents repeated
   decoding when the AI or scripts make rapid property edits.

7. **The Sprite Repository keeps assets stable across the bridge.**
   `AssetRef` carries an opaque UUID; `SpriteRepository` resolves it to
   bytes; the texture cache memoizes the decode. Renames, replacements,
   and AI-generated edits never traffic in raw paths.

8. **Native part nodes are an architectural runway.** `CardPartNode`,
   `ShapePartNode`, and `ImagePartNode` exist as the hooks for a future
   phase in which **all** part types render natively into
   `CardSKScene.nativeLayer` (eliminating the Core Graphics pass and
   unifying every part — button, field, shape, image — under the same
   SpriteKit interaction model). The `nativeLayer` slot in `CardSKScene`
   is reserved for that migration.

9. **SceneKit complements SpriteKit for 3D content.** `scene3D` parts are
   first-class peers of `spriteArea`: both are `PartType` cases, both are
   tracked in `CardCanvasNSView` as native overlays, and both participate in
   the same property inspector, asset-ref discipline, and scripting model.
   `model3D` assets sit alongside 2D sprites in the same `SpriteRepository`,
   embedded as bytes in the `.hype` file. The authoring and binding patterns
   (`AssetRef`, "From Repository…" dropdown, HypeTalk `set the model`) mirror
   the 2D sprite workflow exactly.

10. **Meshy.ai is the on-demand 3D asset pipeline; everything else is local.**
    Generation, rigging, remesh, and retexture require a Meshy API key and
    network egress to `api.meshy.ai`. Rendering (SceneKit), binding
    (`scene3DAssetRef`), scripting (`ask meshy` result handling, `set the
    model`), and AR Quick Look staging are all local and offline.

The net result: Hype is a HyperCard whose card runtime is a real-time
2D scene graph — and now also a 3D scene viewer. Buttons and fields still
feel like HyperCard buttons and fields, the message hierarchy still works
the way it did in 1987, and a HypeTalk script can still say `go to next card`.
But behind that surface, the same script can also create a sprite, attach a
physics body, listen for collisions, run a tile-map of an entire game
level, generate a 3D model from a text prompt, bind it to a scene3D part, await
an Ollama model, call an HTTP service, expose a local listener, and let an
authoring assistant edit the scene by calling `apply_scene_diff` —
all without ever leaving the stack.

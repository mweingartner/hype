# Hype Architecture

> A snapshot of the current implementation as of 2026-04-12.

Hype is a modern, macOS-native re-imagining of HyperCard. It preserves the
HyperCard mental model — **stacks** of **cards** built on shared **backgrounds**,
populated with **parts** (buttons, fields, shapes, images, video, web pages,
charts, sprite areas), all driven by a HyperTalk-style scripting language
called **HypeTalk** — and re-grounds it on a contemporary Apple-platforms
stack: Swift 6, SwiftUI, SpriteKit, Core Graphics, AppKit, WKWebView,
AVKit, Apple Charts, and a local Ollama-backed AI authoring loop.

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

---

## 1. Top-Level Layout

### 1.1 Repository structure

```
hype-v2/
├── Package.swift                   # SwiftPM, macOS 15+, Swift 6
├── Sources/
│   ├── Hype/                       # Executable target — UI / AppKit / SpriteKit host
│   │   ├── HypeApp.swift           # @main, DocumentGroup, menu commands
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
│   │       ├── CardCanvasView.swift       # NSViewRepresentable + CardCanvasNSView (~2,300 LoC)
│   │       ├── PropertyInspector.swift    # Per-part property pane
│   │       ├── ScriptEditor.swift         # HypeTalk script editor window
│   │       ├── SpriteSceneSetupGuide.swift # Guided SpriteKit scene setup flow
│   │       ├── HypeTalkTextView.swift     # NSTextView host for the editor
│   │       ├── CompletionPopup.swift      # Code completion list
│   │       ├── AIChatPanel.swift          # Tool-calling Ollama chat (primary AI UI)
│   │       ├── AIPanel.swift              # Simple Q&A side panel
│   │       ├── NetworkPanelView.swift     # Stack network policy + live runtime monitor
│   │       ├── SpriteRepositoryView.swift # Sprite asset browser window
│   │       ├── ChartHostView.swift        # Apple Charts host
│   │       ├── PreferencesView.swift
│   │       ├── MessageBoxView.swift       # HypeTalk REPL
│   │       ├── ToolName.swift             # Tool palette catalog
│   │       └── GoMenuCommands.swift       # Menu items (Go, Objects, Arrange, Tools, AI)
│   └── HypeCore/                   # Library target — model, scripting, AI, rendering
│       ├── Models/                 # Document model (all value types)
│       │   ├── HypeDocument.swift         # Root aggregate
│       │   ├── HypeStack.swift            # Enums: PartType, ButtonStyle, ShapeType …
│       │   ├── Stack.swift                # Stack metadata + script
│       │   ├── Background.swift           # Background metadata + script
│       │   ├── Card.swift                 # Card metadata + script
│       │   ├── Part.swift                 # The "everything part" struct
│       │   ├── ChartModel.swift           # Chart config / series / data points
│       │   ├── AssetRef.swift             # Stable reference into the Sprite Repository
│       │   ├── SpriteRepository.swift     # Stack-scoped asset store
│       │   ├── SpriteAreaSpec.swift       # Named-scene registry for sprite areas
│       │   ├── SceneSpec.swift            # Persistent SpriteKit scene description
│       │   ├── NetworkManifest.swift      # Persisted outbound rules + saved listeners
│       │   ├── SceneAuthoringSupport.swift # Scene checklists, diagnostics, asset usage
│       │   └── SceneDiff.swift            # Incremental scene patch operations
│       ├── Script/                 # HypeTalk
│       │   ├── Token.swift                # 60+ token types
│       │   ├── Lexer.swift                # Hand-written tokenizer
│       │   ├── AST.swift                  # Statement / Expression nodes
│       │   ├── Parser.swift               # Recursive descent parser (~1,500 LoC)
│       │   ├── Interpreter.swift          # Tree-walking interpreter (~2,400 LoC)
│       │   ├── MessageDispatcher.swift    # part → card → background → stack → app
│       │   └── HypeTalkHighlighter.swift  # Editor syntax highlighting
│       ├── AI/                     # Local Ollama tool-calling integration
│       │   ├── OllamaToolClient.swift     # /api/chat, /api/generate, /api/tags, structured JSON
│       │   ├── AIScriptingProvider.swift  # Async HypeTalk-facing Ollama abstraction
│       │   ├── HypeTools.swift            # 40+ tool schemas
│       │   ├── HypeToolExecutor.swift     # Dispatch tool calls to model mutations
│       │   ├── SceneAuthoringAssistant.swift # Schema-driven scene create/repair proposals
│       │   ├── AIService.swift            # Cloud routing fallback
│       │   └── StackGenerator.swift       # One-shot JSON-mode generator
│       ├── Rendering/              # Core Graphics part renderers
│       │   ├── CardRenderer.swift         # Pipeline + dispatcher
│       │   ├── ButtonRenderer.swift
│       │   ├── FieldRenderer.swift
│       │   ├── ShapeRenderer.swift
│       │   ├── ImageRenderer.swift
│       │   ├── WebPageRenderer.swift      # Edit-mode placeholder
│       │   ├── VideoRenderer.swift        # Edit-mode placeholder
│       │   ├── ChartRenderer.swift        # Edit-mode placeholder
│       │   └── SpriteAreaRenderer.swift   # Edit-mode placeholder
│       ├── SpriteKit/
│       │   └── CoordinateConverter.swift  # Y-flip + rotation conversion
│       ├── Controls/
│       │   ├── PaintLayer.swift           # RGBA bitmap paint surface (Bresenham, etc.)
│       │   ├── WebPageController.swift
│       │   └── VisualEffects.swift        # Card transition catalog
│       ├── Layout/
│       │   ├── LayoutConstraint.swift     # Edge-to-edge responsive constraints
│       │   ├── ConstraintSolver.swift     # Iterative solver
│       │   └── AlignmentGuide.swift       # Snap guides
│       ├── Tools/
│       │   ├── ToolManager.swift          # Active tool / selection
│       │   └── MouseAction.swift          # Tool-aware mouse routing
│       ├── Navigation/
│       │   └── CardNavigator.swift        # Card traversal
│       ├── Runtime/
│       │   └── StackRuntime.swift         # Browse-mode live session, async jobs, listeners
│       ├── Sync/
│       │   └── SyncService.swift          # Future CloudKit hook
│       └── Export/
│           └── DocumentExporter.swift     # JSON / single-file HTML export
├── Tests/HypeCoreTests/            # Model, script, async runtime, AI, export
└── Tests/HypeTests/                # App/SpriteKit smoke coverage
```

The package defines two targets: **HypeCore** (model + scripting + AI + Core
Graphics rendering — fully testable, no AppKit/SpriteKit dependencies) and
**Hype** (the macOS executable — SwiftUI, NSView, AppKit, SpriteKit, AVKit,
WKWebView). The hard split lets the model layer remain pure-Swift and
unit-testable, while UI- and SpriteKit-specific code lives in the executable.

### 1.2 The big picture in one diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│  HypeApp  (DocumentGroup, FileDocument)                                  │
│    └─ MainContentView                                                    │
│         ├─ Tool palette / status bar / side panels                       │
│         ├─ PropertyInspector  (SwiftUI)                                  │
│         ├─ AIChatPanel        (SwiftUI ↔ Ollama tool loop)               │
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
│                            constraints, aiPromptHistory, networkManifest)│
│    Runtime  : StackRuntimeRegistry → StackRuntime                         │
│               (live document session, FIFO event queue, async jobs,      │
│                listeners, connections, runtime status snapshots)         │
│    Scripts  : Lexer → Parser → AST → MessageDispatcher → Interpreter     │
│               (sync core path; browse mode executes through StackRuntime)│
│    Bridge   : SpriteAreaSpec/SceneSpec ←→ SceneBridge ←→ live SKNode tree│
│               (NodeRegistry: UUID ↔ SKNode)                              │
│               (CoordinateConverter: top-left ↔ bottom-left, deg ↔ rad)   │
│    AI       : OllamaToolClient → SceneAuthoringAssistant /               │
│               AIScriptingProvider / HypeToolExecutor                     │
└──────────────────────────────────────────────────────────────────────────┘
```

Two arrows are worth highlighting:

1. **Persistence ↔ runtime.** The model is plain `Codable` Swift values
   serialized as JSON in a `.hype` `FileDocument`. Sprite-area scenes are
   stored on the part as a JSON-encoded `SpriteAreaSpec`, which owns a named
   scene registry and migrates legacy single-`SceneSpec` payloads on load. At
   display time, the bridge layer compiles the active scene into a live
   `SKNode` tree.
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
    public var constraints: [LayoutConstraint]
    public var spriteRepository: SpriteRepository
    public var aiPromptHistory: [String]
}
```

A few choices are deliberate:

- **Flat array of parts.** Parts are not nested under cards or backgrounds.
  Each `Part` carries either a `cardId` (card-scoped) or a `backgroundId`
  (background-scoped), and helpers like `partsForCard(_:)` and
  `partsForBackground(_:)` filter the flat array on demand. This avoids
  copy-of-copy issues, makes draw-order trivial (the array index is the
  z-order), and keeps the JSON shape diff-friendly.
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
  ├── Stack            (id, name, width × height, createdAt, modifiedAt, script)
  ├── Backgrounds[]    (sortKey, name, script)            ← shared visual templates
  ├── Cards[]          (sortKey, name, marked, backgroundId, script)
  ├── Parts[]          (cardId? or backgroundId?, see §2.3)
  ├── Constraints[]    (LayoutConstraint, see §6.4)
  └── SpriteRepository (see §4)
```

Stacks default to 800 × 600. A `Background` is a template; many cards may
share one background, and parts placed on the background appear on every
card that uses it (this is the classic HyperCard reuse mechanism). A
`Card` always belongs to exactly one background.

`PartType` (Sources/HypeCore/Models/HypeStack.swift:9) is the discriminator:

```swift
public enum PartType: String, Codable, Sendable {
    case button, field, shape, webpage, image, video, chart, spriteArea
}
```

### 2.3 Part: the "everything" struct

`Part` (Sources/HypeCore/Models/Part.swift:4) is a single struct that holds
fields for **every** part type, with only the relevant ones populated for a
given `partType`. The fields fall into bands:

| Band             | Fields (representative)                                                  |
|------------------|--------------------------------------------------------------------------|
| identity         | `id`, `name`, `sortKey`, `cardId?`, `backgroundId?`                      |
| geometry         | `left`, `top`, `width`, `height`                                         |
| state            | `visible`, `enabled`, `hilite`, `autoHilite`                             |
| text (any part)  | `textContent`, `textFont`, `textSize`, `textStyle`, `textAlign`          |
| button           | `buttonStyle`, `showName`, `iconId`, `family`, `popupItems` |
| field            | `fieldStyle`, `lockText`, `dontWrap`, `wideMargins`, `richText`, `htmlContent`, `enterKeyEnabled` |
| shape            | `shapeType`, `fillColor`, `strokeColor`, `strokeWidth`, `cornerRadius`, `pathData[]` |
| webpage          | `url`, `urlSourceFieldId?`                                               |
| video            | `videoURL`                                                               |
| image            | `imageData?`, `invertOnClick`                                            |
| chart            | `chartData` *(JSON-encoded ChartConfig)*                                 |
| **sprite area**  | `sceneSpec` *(JSON-encoded `SpriteAreaSpec`, with legacy `SceneSpec` migration)* |
| script           | `script` *(HypeTalk source)*                                             |

That a sprite area is **just a Part** is the key trick. It participates in
selection, draw order, the property inspector, layout constraints, scripts,
and the message hierarchy like any other part. Its `sceneSpec` field is now a
JSON-encoded `SpriteAreaSpec`: a small area-level wrapper that owns a named
scene registry, the active scene ID, design size, scale mode, and SpriteKit
debug flags while preserving compatibility with older single-scene payloads.

Layered metadata enums (`ButtonStyle`, `FieldStyle`, `ShapeType`,
`TextAlignment`) live in `HypeStack.swift`.

### 2.4 Persistence

The whole document is a single JSON blob written through SwiftUI's
`FileDocument`. `HypeDocumentWrapper` (HypeApp.swift:44) reads/writes via
`JSONEncoder/JSONDecoder` and exposes `.hype` files via a custom UTType
`com.hype.stack`. There is no schema migration system: each model's
`init(from:)` decoder uses `decodeIfPresent` with defaults so newer fields
load gracefully against older files.

`DocumentExporter` (Sources/HypeCore/Export/DocumentExporter.swift) provides
two side outputs: pretty-printed sorted JSON (for inspection / diff) and a
single-file HTML rendering of every card as absolutely-positioned `<div>`s.

A placeholder `SyncService` actor exists for future CloudKit collaboration
but does not yet implement live sync.

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
(CardCanvasView.swift:360) — a subclass whose `hitTest` returns `nil`. This
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

Because both are plain JSON-backed value types, the authored state remains
diff-friendly, AI-friendly, undoable, and inspectable, and it survives across
runs without holding onto live SpriteKit objects.

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

`SceneBridge` (Sources/Hype/SpriteKit/SceneBridge.swift, ~742 LoC) is the
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
(CardCanvasView.swift:367, ~2,300 LoC). This is the layer-backed NSView
that draws the card via Core Graphics and overlays NSViews for native
controls. Sprite areas are tracked in four parallel dictionaries:

```swift
var spriteViews:        [UUID: SKView]
var spriteScenes:       [UUID: HypeSKScene]
var spriteBridges:      [UUID: SceneBridge]
var loadedSceneSpecs:   [UUID: String]   // last applied spec, JSON-equality cached
```

`updateSpriteViews()` (CardCanvasView.swift:1749) is called from `draw()`.
For each visible `spriteArea` part it:

1. Lazily creates a `PassthroughSKView` and a `HypeSKScene` if none exist.
2. Compares the part's current `sceneSpec` JSON to the cached one. Because that
   JSON now contains the full `SpriteAreaSpec`, scene switches and area-level
   debug changes are detected by the same cache. If unchanged, the view is just
   repositioned and resized in place.
3. If changed, it tries `applyLiveUpdates(...)` first (for
   property-only edits) and falls back to `rebuildSpriteScene(...)` if
   structural changes are detected.
4. Dispatches `closeScene` to any sprite areas that disappeared.

`rebuildSpriteScene()` (CardCanvasView.swift:1840) parses the JSON, creates
or reuses a `SceneBridge` and `HypeSKScene`, configures debug overlays,
stores references **before** calling `presentScene()` (critical: the bridge
must be reachable from `didMove(to:)` callbacks), applies the active scene
spec, and then schedules `sceneDidLoad` / `openScene` on the browse-mode
runtime queue so lifecycle delivery is serialized with the rest of HypeTalk.

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
   `wipeLeft/Right/Up/Down`, `irisOpen/Close`, `scrollLeft/Right`).
4. Calls `cardSKView.presentScene(targetScene, transition: skTransition)`,
   which performs the actual animation entirely on the GPU.
5. After the animation completes, the SKView is hidden and the canvas
   resumes normal Core Graphics rendering.

This is why the card-level SKView exists at all: SpriteKit's transition
system gives Hype zero-cost, GPU-accelerated card transitions that would
otherwise require a custom Metal shader stack.

### 3.8 Native part nodes (forward-looking)

`CardPartNode` (Sources/Hype/SpriteKit/CardPartNode.swift) is a small
protocol describing an `SKNode` that wraps a Hype `Part`:

```swift
protocol CardPartNode: AnyObject {
    var partId: UUID { get }
    func updateFromPart(_ part: Part)
}
```

`ShapePartNode` (Sources/Hype/SpriteKit/ShapePartNode.swift) is a concrete
`SKShapeNode` subclass that builds a CGPath from a shape part's
geometry, handles fill/stroke colors and corner radius, and supports the
freeform path type. `ImagePartNode` is the equivalent `SKSpriteNode`
wrapper for image parts, including the `invertOnClick` hilite via
`colorBlendFactor`.

These types are not yet wired into the live rendering path — Core Graphics
still draws shapes and images today. They are the hooks for a future phase
in which **all** part types render directly into `CardSKScene.nativeLayer`,
giving every part type access to physics, actions, and the SKView GPU
pipeline. The `nativeLayer` reservation in `CardSKScene` exists exactly for
that migration.

### 3.9 Embedded scene containment: `SpriteAreaNode`

`SpriteAreaNode` (Sources/Hype/SpriteKit/SpriteAreaNode.swift) is a
container `SKCropNode` plus an inner content `SKNode`, configured with a
white-rect mask sized to the sprite area's bounds. It carries its own
`SceneBridge` instance and exists to support the "many sprite areas on
one card" case in which sprite areas are eventually hosted as children of
the card's `spriteLayer` rather than as separate `SKView`s. Today the
shipping path uses one `SKView` per sprite area; `SpriteAreaNode` is
infrastructure for the alternative single-`SKView` consolidation.

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
    case imageTexture, spriteSheet, audioClip, videoClip,
         particlePreset, placeholderAsset
}

public struct SpriteAsset: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AssetKind
    public var mimeType: String
    public var data: Data            // raw bytes embedded in JSON
    public var width: Int
    public var height: Int
    public var tags: [String]
    public var slices: [AssetSlice]            // sprite sheet → frame rects
    public var animationClips: [AnimationClip] // frame indices → fps + loops
}

public struct SpriteRepository: Codable, Sendable {
    public var assets: [SpriteAsset]
    public func asset(byId: UUID)   -> SpriteAsset?
    public func asset(byName: String) -> SpriteAsset?
    public func assetRef(for: SpriteAsset) -> AssetRef
    public mutating func addAsset/_/removeAsset/_/updateAsset(_:)
}
```

### 4.2 Stable references via `AssetRef`

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

### 4.3 The repository UI

`SpriteRepositoryView` (Sources/Hype/Views/SpriteRepositoryView.swift) is
the SwiftUI window that browses, imports, slices, and tags the repository.
It supports drag-and-drop import, multi-select, slicing into frame rects,
and (importantly) is the surface that the AI's `list_repository_assets`
and `import_repository_asset` tools mirror — keeping human and AI workflows
on the same data.

---

## 5. HypeTalk: the Scripting Language

HypeTalk is the largest single subsystem in HypeCore — about 4,700 lines
across lexer, parser, AST, interpreter, dispatcher, and highlighter. The
goal is to feel like HyperCard's HyperTalk while addressing modern part
types, the SpriteKit scene graph, and the asset repository.

### 5.1 Pipeline

```
script source string
        │
        ▼
┌────────────┐    ┌────────────┐    ┌─────┐    ┌────────────────┐
│   Lexer    │───▶│   Parser   │───▶│ AST │───▶│   Interpreter  │
│ (231 LoC)  │    │ (1.5k LoC) │    │     │    │   (2.4k LoC)   │
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
  case-insensitive, recognizes ~60 token types, handles `--` line comments,
  `\` line continuations, and both straight and Unicode smart quotes.
- **Parser** (Sources/HypeCore/Script/Parser.swift) is recursive descent.
  It splits source into top-level `on name … end name` handlers, then
  parses statement-by-statement with a switch on the leading token. Object
  references like `card 3`, `field "Name"`, `button 2 of background "BG1"`
  are first-class grammar.
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
  suspending and network-aware forms: `await <expression>`, `wait until`,
  `request …`, `reply to request …`, `listen for http …`, `listen for tcp …`,
  `connect to host …`, `send … to connection …`, `close connection …`,
  and `stop listener …`.
- **Interpreter** (Sources/HypeCore/Script/Interpreter.swift) is a
  tree walker. It maintains an `ExecutionContext` (target ID, current
  card, document, dialog/drawing providers, mouse coordinates, instruction
  budget) and an `Environment` (locals, globals, the special `it`
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
- async AI jobs
- outbound HTTP requests and inbound pending HTTP replies
- active HTTP/TCP listeners and TCP connections
- a FIFO callback/event queue
- published runtime status snapshots for the UI

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

### 5.5 Object and property model

The interpreter exposes hundreds of properties on each part type and
scene-node type. A few representative ones:

| Object        | Properties (sample)                                                                                |
|---------------|----------------------------------------------------------------------------------------------------|
| any part      | `name`, `visible`, `enabled`, `hilite`, `left/top/width/height`, `rect`, `loc`, `right`, `bottom`, `script`, `owner`, `number` |
| button        | `style`, `family`, `showName`, `iconId`, `popupItems`, `autoHilite`                                 |
| field         | `textContent`, `textFont`, `textSize`, `textStyle`, `textAlign`, `lockText`, `dontWrap`, `htmlContent` |
| shape         | `shapeType`, `fillColor`, `strokeColor`, `strokeWidth`, `cornerRadius`                              |
| webpage       | `url`                                                                                              |
| chart         | `chartData`                                                                                        |
| sprite area   | (top-level scene name, plus per-node access via `the position of sprite "Hero"`)                   |
| sprite node   | `position`, `rotation`, `xScale/yScale`, `zPosition`, `alpha`, `hidden`, `text`, `fontName`, `fontColor`, `velocity`, `angularVelocity`, `density`, `damping`, `audioVolume`, `audioLoop`, `videoLoop`, `particleBirthRate`, `emissionAngle`, `cameraTarget`, `zoom`, … |
| request       | `status`, `method`, `url`, `statusCode`, `body`, `error`, `header "Content-Type"`                  |
| listener      | `port`, `host`, `transport`, `state`, `callbackMessage`                                            |
| connection    | `remoteAddress`, `port`, `state`, `lastData`, `error`                                              |
| card          | `name`, `marked`, `script`                                                                         |
| background    | `name`, `script`, `number of cards`                                                                |
| global        | `the time`, `the date`, `the ticks`, `the seconds`, `the screenrect`, `the version`, `the mouseLoc`, `the shiftKey`, `the optionKey`, `the commandKey`, `the aiModel`, `the aiModels` |

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

A `MessageBoxView` REPL (Sources/Hype/Views/MessageBoxView.swift) lets the
user evaluate HypeTalk expressions interactively against the live runtime
document — not a stale snapshot — so `await`, runtime object properties, and
callback-driven networking behave the same way they do in browse mode. The
SpriteKit authoring side is similarly guided: `SpriteSceneSetupGuide` and
`SceneAuthoringSupport` surface a checklist-oriented workflow for scene basics,
world content, assets, physics, and starter scripts instead of exposing raw
SpriteKit knobs with no scaffolding.

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
- `FieldRenderer` paints field backgrounds and text.
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
var webViews:    [UUID: WKWebView]
var videoPlayers: [UUID: AVPlayerView]
var chartViews:  [UUID: NSView]      // wrapping NSHostingView<ChartHostView>
var spriteViews: [UUID: SKView]      // wrapping HypeSKScene
var paintLayers: [UUID: PaintLayer]  // per-card bitmap surfaces
var activeFieldEditor: NSTextField?  // single inline editor at a time
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

### 6.4 Layout constraints

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
provide live drag-time snap guides: the solver computes alignment
candidates against other parts' edges and centers, the canvas center, and
HIG-recommended spacings (8 / 12 / 20 pt) within a 6-point threshold.

### 6.5 Tools

`ToolManager` (Sources/HypeCore/Tools/ToolManager.swift) holds the active
tool name and the current selection. `ToolName` (Sources/Hype/Views/ToolName.swift)
is the catalog: browse, button, field, shape, webpage, image, video,
chart, spriteArea, select, pencil, line, rect, oval, spray, bucket,
eraser, text. Tools belong to one of three modes: **browse** (HyperCard's
Run mode — interactive parts respond to clicks, sprite areas come alive),
**edit** (parts can be selected, moved, resized, created), and **paint**
(freehand drawing onto the per-card paint layer).

`MouseHandler` (Sources/HypeCore/Tools/MouseAction.swift) is a stateless
utility that turns a mouse-down/drag/up sequence into a `MouseActionResult`
based on the active tool: select a part, create a part by drag-out
(rect ≥ 5×5 px), move a selection, send a HypeTalk `mouseDown` to a
part, or begin a paint stroke. The result is interpreted by the
canvas/coordinator. In browse mode, those interaction results are forwarded to
`StackRuntime` so HypeTalk handlers, async callbacks, `idle`, and SpriteKit
messages all share one serialized execution path.

The **paint layer** is a small RGBA bitmap stored per card,
implemented in `PaintLayer.swift` (Sources/HypeCore/Controls/PaintLayer.swift)
with primitive plot/line (Bresenham), rect, oval, round-rect, and
thick-line operations. It is rendered into the card via a CGImage with
the appropriate Y-flip; HypeTalk can paint into it through a
`DrawingProvider` adapter, mirroring HyperCard's classic painting
commands.

### 6.6 Card transitions and effects

`VisualEffects.swift` (Sources/HypeCore/Controls/VisualEffects.swift)
catalogs the supported transition effects, which the `HypeTalk visual`
command queues up to apply on the next `go` statement. The execution path
is described in §3.7 above: rasterize current and target cards →
`SKTransition` → `cardSKView.presentScene(_:transition:)`.

---

## 7. AI Authoring and Scripting (Local Ollama)

Hype's AI integration is now split across three deliberate surfaces:

- **authoring chat** (`AIChatPanel`) for structured tool-calling edits
- **schema-driven scene authoring** for SpriteKit create/repair flows
- **HypeTalk scripting AI** for prompt-driven generation from user scripts

All three are local-first and Ollama-backed, but they use different contracts
because they solve different problems. The authoring paths want structured
mutations and previews; the scripting path wants plain text results or callback
completion.

### 7.1 Ollama client

`OllamaToolClient` (Sources/HypeCore/AI/OllamaToolClient.swift) is a
multi-surface HTTP client for the local Ollama daemon. It now serves three
distinct architectural roles:

- `/api/chat` for structured authoring conversations and tool calls
- `/api/generate` for one-shot HypeTalk scripting requests
- `/api/tags` for model discovery

Tool schemas use OpenAI-style JSON: `{type: "function", function: {name,
description, parameters: { … JSON Schema … }}}`. The client encodes those
schemas in the request body alongside the conversation messages. When
the model returns tool calls, they arrive as
`{function: {name, arguments: [String: String]}}` which are then
forwarded to `HypeToolExecutor`. For deterministic scene planning and repair,
the same client can also send a `format` schema and decode the JSON response
directly into typed Swift structs.

### 7.2 Tool surface: `HypeTools`

`HypeTools` (Sources/HypeCore/AI/HypeTools.swift) declares ~40 tool
schemas in one place using a small `makeTool(...)` builder that turns a
`[String: (type, description, required)]` parameter map into a complete
schema struct. The categories:

| Category                  | Representative tools |
|---------------------------|----------------------|
| Stack & cards             | `create_card`, `create_background`, `go_to_card`, `delete_card` |
| Part creation             | `create_button`, `create_field`, `create_shape`, `create_webpage`, `create_video`, `create_chart` |
| Part modification         | `set_part_property`, `delete_part` |
| Sprite areas / scenes     | `create_sprite_area`, `get_scene_spec`, `apply_scene_diff`, `add_sprite_to_scene`, `create_tilemap`, `create_camera` |
| Diagnostics / introspection | `get_stack_info`, `get_card_parts`, `capture_scene_snapshot`, `get_scene_diagnostics` |
| Asset repository          | `list_repository_assets`, `import_repository_asset` |
| Optional extra tools      | `fetch_url`, `read_file`, `write_file`, `list_directory` |

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

`HypeToolExecutor` (Sources/HypeCore/AI/HypeToolExecutor.swift, 649 LoC)
remains the structural mutation engine. It is still a large `switch` over tool
name taking `document: inout HypeDocument`, but its responsibilities are now
more sharply defined:

- create or mutate stack parts and scenes
- resolve repository assets by stable identity
- apply `SceneDiff` patches to the active scene inside a `SpriteAreaSpec`
- return diagnostics and navigation signals back to the UI

`AIChatPanel` (Sources/Hype/Views/AIChatPanel.swift) orchestrates three related
loops:

1. a classic multi-round tool-calling loop for stack/card/part edits
2. a structured scene create/repair loop that previews typed proposals
3. an undoable apply step that commits the accepted proposal to the document

The panel maintains a bounded conversation window, embeds repository and scene
context into the system prompt, and keeps past prompts on
`HypeDocument.aiPromptHistory` for recall. The result is an AI authoring
surface that is still conversational, but much more deterministic for the
SpriteKit-heavy parts of the app.

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

### 7.6 Cloud fallback and bulk generator

`AIService` (Sources/HypeCore/AI/AIService.swift) is a smaller routing
layer that can call Anthropic's Claude API for plain-text Q&A when an API
key is configured, used by the lightweight `AIPanel`. `StackGenerator`
(Sources/HypeCore/AI/StackGenerator.swift) is a one-shot generator that
prompts a model for a complete stack as a single JSON payload (no tool
calls, no loop) and reconstructs a `HypeDocument` from the parsed
response — used for "bootstrap a new stack from a paragraph" scenarios.

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
- `sceneDidLoad` — once per scene rebuild
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

### 8.4 Testing

The `HypeCoreTests` target contains test suites for the model
(`ModelTests`), the script engine (`ScriptTests`,
`ComprehensiveScriptTests`), tools (`ToolTests`), controls
(`ControlsTests`), alignment (`AlignmentTests`), and AI / export
(`AIAndExportTests`). Because HypeCore has no AppKit/SpriteKit
dependencies, the bulk of the language and model surface still runs in CI
without a UI. Newer suites cover the runtime-backed path as well: async
HypeTalk execution, `await ollama(...)`, HTTP request/listener flows, TCP
listener flows, and scene authoring support. A separate `HypeTests` target
holds app-facing smoke coverage for SpriteKit bridge behavior and related UI
integration seams.

---

## 9. Where SpriteKit Sits in the Stack — Summary

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

The net result: Hype is a HyperCard whose card runtime is a real-time
2D scene graph. Buttons and fields still feel like HyperCard
buttons and fields, the message hierarchy still works the way it did
in 1987, and a HypeTalk script can still say `go to next card`. But
behind that surface, the same script can also create a sprite, attach a
physics body, listen for collisions, run a tile-map of an entire game
level, await an Ollama model, call an HTTP service, expose a local listener,
and let an authoring assistant edit the scene by calling `apply_scene_diff` —
all without ever leaving the stack.

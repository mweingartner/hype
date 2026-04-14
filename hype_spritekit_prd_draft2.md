# Hype SpriteKit Integration

## PRD Draft 2 — revised to add a stack-scoped Sprite Repository

Prepared for Michael  
Date: April 8, 2026



> **Purpose**  
> This draft is meant to do two jobs at once: (1) serve as a first serious PRD for adding SpriteKit support to Hype, and (2) act as prompt context for code generation and implementation planning.  
>  
> **Assumptions from the prompt**  
> Hype is a macOS app written in Swift with a HyperCard-inspired document model (stacks, backgrounds, cards), a HyperTalk-like scripting language called HypeTalk, embedded modern content types (browser, PNG, MP4, graphs), and a local AI integration built on Ollama.  
>  
> **Revision focus in Draft 2**  
> This revision adds a recommended **Sprite Repository** concept: a stack-scoped, database-backed repository of reusable named assets exposed in a separate repository window and deeply integrated into Sprite Areas, HypeTalk, and the local Ollama workflow.


## 1. Executive recommendation


Hype should add SpriteKit as a **first-class embedded “Sprite Area” part** that can live on a card or background, and it should add a **stack-scoped Sprite Repository** as the canonical home for reusable game assets used anywhere in that stack. The Sprite Area should host an `SKView` and one active `SKScene`, while Hype persists a **declarative scene specification** as part of the stack document. The Sprite Repository should persist **named assets, derived variants, and import metadata** in the stack database, so scenes and scripts reference stable asset identities instead of raw file paths. HypeTalk should treat scenes, nodes, repository assets, and asset-derived objects as first-class scriptable objects, extending the familiar HyperCard message path into the real-time scene graph. AI creation and control should use **schema-validated scene specs, asset refs, and transactional scene diffs plus tool calling**, not unconstrained free-form mutation. Simulation, rendering, physics, and texture loading should remain native in Swift/SpriteKit; HypeTalk and the local model should orchestrate behavior at the object and event layer. [S1][S2][S3][S4][S7][S10][S11][S14][S15][S16]


### Key decisions


| Decision | Recommendation | Why |
|---|---|---|
| Integration surface | Add a new Hype part type called **Sprite Area** | Preserves the card/background mental model and lets creators mix UI, media, and game content on one card |
| Asset management | Add a **Sprite Repository** window scoped to the stack | Gives creators one reusable asset source across cards, backgrounds, and scenes |
| Storage model | Store repository metadata and asset blobs in the **stack database** with stable IDs | Makes stacks portable, rename-safe, AI-friendly, and less path-fragile |
| Runtime architecture | Persist **SceneSpec** and **AssetRef**; generate runtime `SKScene` / `SKNode` tree from them | SpriteKit’s scene graph is ideal at runtime, but Hype needs a durable authoring model and AI-friendly serialization |
| Scripting model | Extend HypeTalk with scene, node, repository, and asset commands/messages | Preserves the HyperTalk feel instead of forcing raw SpriteKit API thinking |
| Message routing | Bubble events from node → parent groups → scene → Sprite Area → card → background → stack | Keeps the strongest HyperCard design pattern: modular scripts and inheritance-like message passing |
| AI control | Use structured JSON schemas + scene diffs + asset refs + tool calling | Reliable, testable, undoable, safer than letting an LLM invent arbitrary runtime state |
| Performance boundary | Keep frame-critical behavior native; use HypeTalk for orchestration and discrete logic | HyperCard historically relied on native compiled extensions for speed-sensitive capabilities; the same principle applies here |


## 2. Research synthesis


### 2.1 What SpriteKit gives Hype


SpriteKit is explicitly a 2D framework for shapes, particles, text, images, and video. A scene is represented by `SKScene`, and that scene is the root of a tree of `SKNode` objects. `SKView` presents the scene and alternates between simulation and rendering. SpriteKit also exposes major game-building primitives that matter for Hype: actions, physics bodies and contacts, tile maps, cameras, constraints, video nodes, audio nodes, and texture atlases. [S1][S2][S3][S5][S6][S7][S8][S9]


That matters because Hype already supports media-rich cards. SpriteKit fits unusually well with Hype’s existing direction: it can coexist with PNG and MP4 assets, it can render inside a view, and it already has the primitives needed for small games, animated diagrams, simulations, interactive toys, and dynamic media components. `SKView` also exposes knobs that are ideal for an authoring environment: frame-rate selection, transparency, and debug overlays such as FPS, physics, node count, and draw count. [S3][S8][S9]


### 2.2 What HyperCard/HypeTalk should preserve


HyperCard’s lasting design value was not just “cards.” It was the combination of:

- modular scripts attached to many object types,
- English-like event handling,
- a message-passing order that let behavior live at the most natural level, and
- a background/card structure that balanced reuse with per-card specialization. [S10][S11][S12][S13]


The historical message path is especially important. If an object does not handle a message, HyperCard passes it onward through the current card, then background, then stack, then Home stack, then HyperCard itself. HyperCard also allowed scripts on buttons, fields, cards, backgrounds, and stacks, which made behavior highly composable. Background objects could be shared visually and behaviorally, while properties such as `sharedText` controlled whether some data was shared across cards or card-specific. [S10][S11][S12][S13]


This suggests a strong rule for Hype: **do not expose SpriteKit as a raw API wrapper first. Expose it as a new family of Hype objects that participate in HypeTalk’s message system.**


### 2.3 Why a bridge layer is mandatory


HyperCard/Hype is fundamentally a **persistent authoring model**; SpriteKit is fundamentally a **runtime scene graph with a frame loop**. Those are compatible, but they are not the same thing. The product needs a bridge that preserves Hype’s source-of-truth object model while compiling it into SpriteKit’s runtime model.


The first-principles requirement is this:


1. The document model must be durable, inspectable, diffable, AI-friendly, and safe to version.
2. The runtime model must be fast, renderable, hit-testable, and physics-capable.
3. The scripting model must feel like HypeTalk, not like a direct Swift API binding.
4. The AI model must operate on constrained, validated structures, not ad hoc mutation. [S2][S3][S4][S14][S15][S16]


### 2.4 Why a Sprite Repository layer is also mandatory


A second bridge is needed between **runtime nodes** and **art/media assets**. Raw file paths are a weak authoring boundary for a HyperCard-like system because they are brittle under rename, move, export, duplicate, and AI-generated edits. SpriteKit can load textures efficiently and supports atlases and preloading, but Hype still needs a stable, user-visible asset system above that runtime layer. [S7]


The first-principles requirement for assets is:


1. Assets must be easy to import once and reuse everywhere in a stack.
2. Scenes and scripts must reference stable asset identities, not transient filesystem locations.
3. The stack must remain portable and self-contained when shared.
4. The AI model must be able to inspect a bounded catalog of available assets and select from it deterministically.
5. Asset replacement should preserve references whenever possible.
6. Derived data such as sliced frames, animation clips, tile sets, previews, and default collision metadata should live near the source asset, not be rediscovered every time.


That leads directly to a **Sprite Repository** as a stack-level subsystem.


## 3. Product goals, non-goals, and success criteria


### 3.1 Goals


1. Let Hype creators build simple to moderately sophisticated 2D games and animated interactive experiences without leaving Hype.
2. Keep the mental model recognizably HyperCard-like: cards, backgrounds, parts, scripts, message passing.
3. Let HypeTalk create, inspect, and control SpriteKit content without requiring creators to think in raw Swift.
4. Make the local Ollama integration a first-class authoring and control surface for Sprite content.
5. Preserve Hype’s mixed-media advantage: game content should coexist cleanly with fields, buttons, browsers, graphs, and media.
6. Add a stack-scoped Sprite Repository so creators can import, name, organize, and reuse Sprite assets across the whole stack.
7. Make asset references durable enough that AI, HypeTalk, and user-driven edits can all operate on the same stable identities.


### 3.2 Non-goals for the first release


1. Not a 3D engine.
2. Not a replacement for Xcode game development.
3. Not a networked multiplayer stack.
4. Not frame-by-frame LLM control of the render loop.
5. Not arbitrary native-code execution generated by AI.
6. Not full parity with every SpriteKit class on day one.
7. Not a general-purpose cloud asset service.
8. Not a promise that every existing Hype media workflow immediately migrates into the repository on day one.


### 3.3 Success criteria


1. A creator can insert a Sprite Area, add sprites, and make a simple game with HypeTalk alone.
2. A creator can import a sprite sheet once into the Sprite Repository, slice it, name it, and reuse it across multiple scenes.
3. A creator can ask Hype’s local model to generate a working playable prototype, inspect the proposed changes, and apply them.
4. Sprite-specific messages feel native in HypeTalk and participate in familiar message routing.
5. Simple scenes can hot reload after script/property edits without reopening the stack.
6. Scenes save and reopen reliably inside a stack with asset references intact.
7. Renaming or replacing a repository asset does not silently break scene references.
8. Hype exposes enough diagnostics that authors and the local model can repair common scene and asset errors without manual Swift changes.


## 4. Users and top user stories


### 4.1 Primary users


- **HyperCard-style creators** who want approachable scripting and visual authoring.
- **Educators and hobbyists** who want small games, simulations, or interactive lessons.
- **AI-assisted creators** who prefer to prompt for working prototypes and then tune them.
- **Power users** who want reusable backgrounds, shared assets, and more advanced scene behavior.


### 4.2 Top user stories


1. As a creator, I can drop a Sprite Area on a card and make a Pong-like game without opening Xcode.
2. As a creator, I can script a sprite, a scene, or the card itself and decide where logic belongs.
3. As a creator, I can combine a Sprite Area with ordinary card UI such as fields and buttons.
4. As a creator, I can import art into a Sprite Repository once and reuse it throughout the stack.
5. As a creator, I can replace the underlying art for a named asset without manually repairing every scene that uses it.
6. As a creator, I can ask the local model to generate a game scene, its HypeTalk handlers, and the required object hierarchy using assets already in the repository.
7. As a creator, I can preview, pause, step, inspect, and debug the scene from inside Hype.
8. As a creator, I can keep a HUD or reusable layout on a background while card-specific game content changes.
9. As a creator, I can see where a repository asset is used before I rename, replace, or delete it.


## 5. Product design


### 5.1 Proposed object model


**New first-class objects**


- `spriteArea` (a Hype part that hosts SpriteKit)
- `scene`
- `group` (logical container backed by `SKNode`)
- `sprite`
- `label`
- `shape`
- `emitter`
- `tileMap`
- `camera`
- `videoSprite`
- `audioNode`
- `physicsWorld` (scene-level scriptable object)
- `spriteRepository`
- `spriteAsset`
- `assetVariant`
- `animationClip`
- `tileSet`
- `particlePreset`


**Hierarchy**


`stack -> spriteRepository`  
`stack -> background -> card -> part -> spriteArea -> scene -> node/group -> leaf nodes`  
`scene/node -> assetRef -> spriteRepository asset or variant`


This preserves the stack/card/background foundation while giving scenes their own internal scene graph and a stable stack-wide asset layer.


### 5.2 User-facing part concept: Sprite Area


The right product abstraction is an embedded part, not a separate file type.


A Sprite Area should:

- be placeable on a card or background,
- have a frame/bounds like other Hype parts,
- optionally fill the entire card,
- optionally be transparent over the card,
- host one active scene at a time,
- support play/pause/step/preview modes,
- participate in selection, inspector editing, undo/redo, and z-ordering inside Hype.


**Why this is the right abstraction:** `SKView` is a view-based renderer, and Hype already thinks in embedded content regions. SpriteKit’s ability to render in a view, convert coordinates, support transparency, and expose scene scaling modes makes it a natural fit for a part-based authoring tool. [S3][S9]


### 5.3 Stack-scoped Sprite Repository


#### 5.3.1 Product abstraction


The repository should be a **stack-scoped asset subsystem** dedicated to SpriteKit-facing reusable assets. It should appear as a separate window or detachable panel so creators can manage assets without consuming scene-canvas space. The repository is not just a file browser. It is a durable asset graph stored in the stack database.


The repository should solve four product problems at once:


1. **Reuse** — one import can be used anywhere in the stack.
2. **Stability** — scene specs and HypeTalk refer to stable IDs, not paths.
3. **Authoring ergonomics** — creators need visual browsing, drag/drop, slicing, tagging, and usage inspection.
4. **AI grounding** — the local model needs a bounded inventory of available assets it can inspect and reference deterministically.


**Recommendation:** ship it as a dedicated window called **Sprite Repository** in v1, with a future option to dock it into the main editor.


#### 5.3.2 Repository window UX


The Sprite Repository window should support:


| Capability | v1 recommendation | Why |
|---|---|---|
| Grid and list views | Yes | Creators need both visual browsing and metadata inspection |
| Drag/drop import | Yes | Fastest on-ramp for art-heavy workflows |
| Folder import | Yes | Common for sprite-sheet and animation packs |
| Search + tags | Yes | Essential as stacks accumulate assets |
| Named assets | Yes | Critical for HypeTalk and AI prompting |
| Preview pane | Yes | Needed for slicing, animation, and safe replacement |
| Usage inspector | Yes | Prevents accidental breakage |
| Drag asset into scene | Yes | Makes repository feel native to authoring |
| Replace asset while preserving refs | Yes | Common iteration workflow |
| Sprite-sheet slicing | Yes | Foundational for games |
| Animation clip creation | Yes | Lets creators reuse derived animations |
| Tile-set derivation | Should | Important for game maps but can follow the core flow |
| AI-aware command bar | Should | Useful, but the underlying tools matter more than a bespoke UI in v1 |


#### 5.3.3 Asset kinds and scope


The repository schema should support these kinds even if the UI reaches them in phases:


- `imageTexture`
- `spriteSheet`
- `animationClip` (derived)
- `tileSet` (derived)
- `atlasGroup` (optimization artifact or logical grouping)
- `audioClip` (phase 1.5 candidate)
- `videoClip` (phase 2 candidate)
- `particlePreset` (phase 2 candidate)
- `placeholderAsset`


**V1 authoring center of gravity:** image textures, sprite sheets, animation clips, and asset variants.


#### 5.3.4 Recommended data model and database storage


The user requested database-backed reusable named assets. That is the correct default.


**Canonical rule:** the Sprite Repository should store both **asset metadata** and **binary content references** in the stack database, so a stack remains self-contained and portable.


Recommended logical schema:


| Entity | Purpose | Notes |
|---|---|---|
| `sprite_assets` | One row per user-visible asset | Stable `assetID`, unique human name, type, dimensions, tags, timestamps |
| `asset_blobs` | Binary content store | Content-hash dedupe, compression metadata, byte length, preview blob |
| `asset_variants` | Derived forms of assets | Frame slices, trimmed textures, tile sets, collision masks, animation definitions |
| `asset_aliases` | Optional friendly names or renames | Helpful if HypeTalk wants soft naming compatibility |
| `asset_usage` | Materialized or computed usage index | Scene, node, and script references for rename/delete safety |
| `asset_metadata` | Extensible JSON metadata | Pivot points, default scale, frame timing, import hints, AI description |


Recommended identity rules:

- `assetID` is the canonical durable reference.
- `name` is the primary human-facing handle and should be unique within the stack repository scope.
- `variantID` identifies a derived asset representation.
- `contentHash` enables dedupe and replace detection.
- Scenes and nodes should store `assetID` and optional `variantID`; scripts may also accept names for convenience.


Recommended default storage rule:

- **Embed repository blobs in the stack database by default.**
- Warn when the stack grows large.
- Reserve “externalized large asset” support for a later phase if needed, but do not make external paths the default model.


#### 5.3.5 Import and derivation workflow


The repository should support these flows:


1. import a single image as a named asset,
2. import a folder as multiple named assets,
3. import a sprite sheet and slice it into frames,
4. derive an animation clip from frame slices,
5. derive a tile set from a sheet,
6. promote an existing card/media asset into the repository,
7. replace an asset’s underlying blob while preserving IDs and references,
8. duplicate an asset intentionally when a creator wants a fork rather than a shared update.


Recommended import pipeline:

- ingest file(s),
- compute hash,
- identify kind and metadata,
- generate preview/thumbnail,
- optionally auto-suggest a unique name,
- optionally detect sprite-sheet grid,
- let user define tags, pivot, frame bounds, default collision outline, and notes,
- commit into repository as an undoable transaction.


#### 5.3.6 Reference model


This is the most important repository rule: **no scene spec should depend on a raw path as its canonical asset reference.**


Recommended `AssetRef` shape:


- `assetID`
- `variantID` (optional)
- `name` (cached human hint)
- `expectedKind`
- `role` (for example `texture`, `normalMap`, `video`, `tileSet`)
- `fallbackAssetID` (optional)
- `revision` or `updatedAt` hint for stale-cache detection


This yields:

- rename safety,
- replace safety,
- stack portability,
- AI determinism,
- better diagnostics when an asset is missing or incompatible.


#### 5.3.7 HypeTalk surface for the repository


The repository should be scriptable, but the scripting surface should stay declarative and English-like.


**Example commands (proposed)**


```hypertalk
open spriteRepository

import file "/Users/me/Art/ship.png" into spriteRepository as asset "ship"
import file "/Users/me/Art/shipSheet.png" into spriteRepository as asset "shipSheet"

slice asset "shipSheet" into grid 6 by 1
create animationClip "shipIdle" from asset "shipSheet" frames 1 to 6 fps 12 loop true

create spriteArea "game" at rect 20,20,780,580 on this card
create scene "main" in spriteArea "game"

create sprite "player" in scene "main" with asset "ship"
set the animationClip of sprite "player" to "shipIdle"
set the loc of sprite "player" to 160,40
```


**Example inspection commands (proposed)**


```hypertalk
put the assetNames of spriteRepository into field "assets"
answer the usage of asset "ship"
replace asset "ship" with file "/Users/me/Art/ship_v2.png"
```


Design rule:

- HypeTalk may allow referencing assets by name for ergonomics.
- Internally, Hype should resolve names to IDs and persist IDs.


#### 5.3.8 Repository behavior with the local AI model


The local model should not hallucinate asset names. It should receive a bounded repository inventory and select from it.


Recommended AI-facing repository fields:

- `assetID`
- `name`
- `kind`
- `size`
- `frameCount`
- `tags`
- `shortDescription`
- `previewAvailable`
- `usageCount`


Recommended model behaviors:

- prefer existing assets before asking for placeholders,
- generate scenes against repository names or IDs already present,
- create placeholders only when assets are missing,
- propose asset replacements or derived clips as structured operations,
- never import arbitrary filesystem assets without an explicit user-granted file handle or selection.


### 5.4 Recommended runtime behavior


#### Canonical source of truth


The **persisted SceneSpec** and **repository AssetRefs** must be canonical. Runtime `SKScene` / `SKNode` / `SKTexture` objects are generated projections.


That means:

- the editor edits SceneSpec and repository metadata,
- HypeTalk mutates logical objects and the bridge updates runtime nodes,
- AI emits `SceneSpec`, `SceneDiff`, `AssetOp`, and `ScriptPatch` JSON,
- save/load operates on versioned document data, not archived SpriteKit runtime instances.


This is the single most important architectural choice.


#### Active scene lifecycle


Each Sprite Area owns:

- one **scene registry** (all named scenes defined for that part),
- one **active scene instance**,
- one **node registry** mapping Hype IDs ↔ SpriteKit nodes,
- one **event bridge**,
- one **asset resolver/cache** backed by the Sprite Repository,
- one **diagnostics channel**.


Default scene lifecycle:

1. load SceneSpec,
2. resolve repository AssetRefs,
3. build runtime scene,
4. present in `SKView`,
5. dispatch `sceneDidLoad` / `openScene`,
6. run frame loop,
7. teardown on card close or scene change unless explicitly retained later.


For v1, scene instances should be recreated predictably rather than retained invisibly across card navigation. That keeps behavior deterministic. Persistent state should live in Hype data, repository metadata, or HypeTalk variables, not hidden runtime state.


### 5.5 Message routing model


This is where Hype can become distinctly better than a thin SpriteKit wrapper.


**Recommended message path**


1. target node (sprite, label, shape, etc.)
2. parent group(s), nearest outward first
3. scene
4. spriteArea
5. card
6. background
7. stack
8. Hype runtime or system


This is the natural extension of HyperCard’s message-passing idea into a scene graph. [S10][S11]


**Rule:** when a SpriteKit-originated event occurs, the bridge should synthesize a HypeTalk message and dispatch it through this path.


Examples:

- a click on a sprite → `mouseDown`, `mouseUp`, `mouseEnter`, etc.
- a physics contact → `beginContact`, `endContact`
- a frame update → `frameUpdate deltaTime`
- scene lifecycle → `sceneDidLoad`, `openScene`, `closeScene`
- action completion → `actionFinished actionName`
- asset resolution issue → `assetMissing assetName`


### 5.6 Recommended object properties and messages


#### Core properties by object type


| Object | Key properties |
|---|---|
| `spriteArea` | frame, visible, activeScene, designSize, scaleMode, transparent, paused, preferredFPS, debugFlags |
| `scene` | size, backgroundColor, gravity, camera, paused, physicsEnabled |
| `group`, `sprite`, `label`, `shape` | name, id, loc, x, y, z, rotation, xScale, yScale, alpha, hidden, parent, children, tags |
| renderable nodes | blendMode, color, texture, assetRef, size |
| physics-enabled nodes | physicsBody, dynamic, affectedByGravity, velocity, angularVelocity, mass, friction, restitution, linearDamping, angularDamping, category, collisionCategories, contactCategories |
| `camera` | loc, xScale, yScale, constraints |
| `tileMap` | columns, rows, tileSize, tileSet |
| `videoSprite` | videoAsset, playbackState, loop, muted |
| `audioNode` | asset, loop, positional, volume |
| `spriteRepository` | name, assetCount, collections, tags, lastImportedAt |
| `spriteAsset` | id, name, kind, width, height, frameCount, tags, usageCount, pivot, checksum |


#### Recommended messages


| Message | Target(s) | Notes |
|---|---|---|
| `sceneDidLoad` | scene | Setup after scene materialization |
| `openScene` / `closeScene` | scene, spriteArea | Mirrors card lifecycle concepts |
| `frameUpdate dt` | scene, optionally bubbling upward | Keep heavy work off this path |
| `keyDown keyName` / `keyUp keyName` | focused node, scene, spriteArea | Requires clear focus rules |
| `mouseDown x,y` / `mouseUp x,y` / `mouseDragged x,y` | hit node upward | Use Hype logical coordinates |
| `beginContact otherNode` / `endContact otherNode` | contacted nodes, scene | Physics delegate bridge |
| `actionFinished actionName` | node | Good fit for action chaining |
| `assetImported assetName` | spriteRepository | Repository lifecycle hook |
| `assetReplaced assetName` | spriteRepository, interested scenes | Allows cache refresh and diagnostics |
| `assetMissing assetName` | spriteArea, card, stack | Recoverable asset diagnostics |
| `repositoryDidChange` | spriteRepository, stack | Useful for editor refresh |


### 5.7 Scale and coordinate model


A creator-friendly model matters more than raw SpriteKit fidelity.


Recommended coordinate rules for v1:

- every Sprite Area has a `designSize`,
- HypeTalk uses **top-left origin coordinates inside the Sprite Area**, matching card authoring expectations,
- `x` increases to the right, `y` increases downward,
- the bridge converts Hype logical coordinates into SpriteKit’s scene coordinates,
- `loc` refers to the visual center of a node in HypeTalk,
- default `scaleMode` is a fixed logical scene with aspect fit,
- alternate scale modes can arrive later.


This deliberately favors Hype ergonomics over raw SpriteKit convention. Advanced “native SpriteKit coordinates” can be a later option if needed.


### 5.8 Scene transitions


SpriteKit has scene transitions, but Hype should initially expose them conservatively. [S2]


Recommended v1 support:

- open scene instantly,
- fade transition,
- push transition,
- move-in transition,
- optional custom duration,
- HypeTalk message `open scene "name" with transition ...`


Do not make animated transitions the core of the architecture. The hard part is stable scene and asset semantics.


## 6. AI/Ollama integration


### 6.1 Core principle


The local model should be treated as a **scene author, repository-aware editor, and repair assistant**, not as the frame loop. Ollama’s structured outputs and tool calling are the key enabling pieces because they let Hype ask for constrained JSON and perform deterministic local operations. [S14][S15][S16]


### 6.2 Recommended AI modes


**Mode A — Generate new scene content**

Prompt → repository inventory + current card context → `SceneSpec` + `ScriptPatch` + optional `AssetOp[]`


**Mode B — Edit current scene**

Prompt + current `SceneSpec` + selected nodes + repository inventory → `SceneDiff` + `ScriptPatch`


**Mode C — Explain or repair**

Current scene state + diagnostics + repository inventory → explanation, probable root cause, and proposed diff or script fix


**Mode D — Repository assistance**

Prompt + repository metadata + selected asset(s) → slice proposal, animation clip definition, naming or tagging suggestion, asset replacement plan, or placeholder-asset plan


### 6.3 Why structured JSON matters


Free-form code generation is not enough for this feature. Hype needs transaction boundaries.


Recommended AI return types:

- `SceneSpec`
- `SceneDiff`
- `AssetOp`
- `ScriptPatch`
- `DiagnosticExplanation`


Each should validate against a known schema before any apply step. [S14][S15]


### 6.4 Repository-aware tool catalog


The local model should get explicit tools rather than a vague command surface.


| Tool | Purpose | Must for v1 |
|---|---|---|
| `getCurrentCardContext()` | Card, background, selected part, current stack context | Yes |
| `listSpriteAreas()` | Enumerate Sprite Areas in scope | Yes |
| `getSceneSpec(spriteAreaID)` | Retrieve canonical scene spec | Yes |
| `getRuntimeSceneSummary(spriteAreaID)` | Read node tree, positions, states, diagnostics | Yes |
| `listRepositoryAssets(filter?)` | Inventory assets, variants, tags, sizes, usage | Yes |
| `getAssetDetails(assetID)` | Detailed metadata, variants, preview availability | Yes |
| `proposeAssetSlice(assetID)` | Return a structured slicing plan | Yes |
| `applySceneDiff(spriteAreaID, diff)` | Validated transactional change | Yes |
| `applyScriptPatch(targetID, patch)` | Validated script update | Yes |
| `applyAssetOp(op)` | Import, rename, replace, derive clip, retag, duplicate | Yes |
| `capturePreview(spriteAreaID)` | Image snapshot for repair or explanation | Should |
| `findAssetUsage(assetID)` | Where an asset is used | Should |
| `createPlaceholderAsset(spec)` | Generate simple procedural placeholder content | Should |


### 6.5 AI contracts for assets and scenes


Recommended contracts:

- `SceneSpec` creates or fully replaces a scene definition.
- `SceneDiff` applies narrow edits to nodes, properties, order, handlers, and scene settings.
- `AssetOp` covers repository operations such as import, rename, replace, slice, derive animation, duplicate, and retag.
- `ScriptPatch` creates or updates HypeTalk handlers.


All contracts should:

- include stable object IDs where possible,
- allow human-readable names as hints,
- validate before apply,
- generate undo checkpoints,
- emit diagnostics on partial failure,
- avoid mutating live frame-critical state blindly.


### 6.6 AI operational rules


1. The model should always inspect the repository before inventing asset names.
2. If suitable assets exist, the model should prefer binding them over generating placeholders.
3. Asset imports from the filesystem require explicit user-approved file handles.
4. Asset replacement should preserve IDs unless the user requested a fork.
5. AI-generated scripts should prefer declarative commands (`run action`, `open scene`, `set asset`) over ad hoc per-frame logic.
6. Long-running local inference must never execute inline with the render loop.
7. Every AI apply path must be previewable and undoable.


### 6.7 AI and visual context


If the local model supports multimodal inspection, Hype should provide preview images for repository assets and scene snapshots. That is especially useful for repair loops, tile-map layout checks, and animation verification. But preview images should supplement—not replace—the structured scene and repository schema.


### 6.8 Context-budget recommendation


For large stacks, do not dump the entire scene or full repository blob metadata into the model context. Provide:

- the current Sprite Area,
- selected nodes,
- nearby handlers,
- a compact repository inventory,
- only the asset details relevant to the task,
- the active diagnostics.


That keeps local-model latency and hallucination risk under better control.


## 7. Technical architecture


### 7.1 High-level component model


| Component | Responsibility |
|---|---|
| `HypeSpritePartModel` | Persistent model for the Sprite Area part |
| `HypeSpritePartView` | Editor/runtime host view embedding `SKView` |
| `HypeSceneSpec` | Canonical scene document model |
| `HypeNodeSpec` | Canonical node model |
| `HypeAssetRef` | Stable reference from node to repository asset or variant |
| `HypeSpriteRepositoryStore` | Stack-scoped repository metadata and queries |
| `HypeAssetBlobStore` | Blob persistence, hashing, preview generation, dedupe |
| `HypeAssetResolver` | Converts `AssetRef` into runtime textures, videos, or tile assets |
| `HypeSpriteSheetSlicer` | Creates frame variants and animation definitions |
| `HypeSceneBridge` | Translates between persistent model and SpriteKit runtime |
| `HypeSKScene` | Generic reusable runtime `SKScene` subclass |
| `HypeNodeRegistry` | Maps Hype object IDs ↔ runtime nodes |
| `HypeSceneDiffApplier` | Transactionally applies validated diffs |
| `HypeSpriteRepositoryWindowController` | Repository UI, drag/drop, usage inspection |
| `HypeAIBridge` | Structured outputs, tool calling, permissions, previews |
| `HypeDiagnosticsChannel` | Collects human-readable and AI-readable diagnostics |


### 7.2 Generic scene subclass rationale


Do **not** generate a native Swift subclass for every user scene. Use one generic reusable `HypeSKScene` plus bridge objects.


Why:

- Hype scenes are document-authored, not compile-authored.
- AI editing is dramatically easier against data than source-generated Swift subclasses.
- save/load and undo/redo are simpler when runtime behavior is driven by specs.
- hot reload is much easier.


Per-scene user code belongs in HypeTalk handlers attached to logical scene and node objects, not in generated Swift files.


### 7.3 Node identity and script targeting


Recommended runtime identity convention:

- `SKNode.name` = human script name if present
- `SKNode.userData["hypeID"]` = stable UUID
- `SKNode.userData["hypeType"]` = node type
- `SKNode.userData["assetID"]` = canonical repository asset ID when relevant
- `SKNode.userData["scriptTarget"]` = lookup metadata


This gives:

- direct hit-test → Hype object mapping,
- stable AI diffs,
- debuggable runtime inspection,
- script references that remain readable.


### 7.4 Asset identity and resolution


The repository should be the only canonical place where Sprite-facing asset identity lives.


Recommended runtime flow:

1. node spec contains `AssetRef`,
2. bridge asks `HypeAssetResolver` for a runtime asset,
3. resolver fetches repository metadata and blob,
4. resolver produces `SKTexture`, `SKTileSet`, `AVAsset`-backed node config, or a placeholder diagnostic asset,
5. runtime caches are keyed by `assetID`, `variantID`, and relevant scale parameters.


Important rules:

- a renamed asset keeps the same `assetID`,
- a replaced asset usually keeps the same `assetID` but increments metadata revision,
- cache invalidation runs when `assetReplaced` occurs,
- a missing asset degrades to diagnostics, not crashes.


### 7.5 Input routing


SpriteKit on macOS can participate in responder-style interaction, and SpriteKit docs distinguish mouse, touch, keyboard handling, and hit-testing concerns. [S3][S9]


For Hype, input should be centralized:

- SpriteKit input arrives at the scene or bridge,
- the bridge resolves the hit node,
- HypeTalk messages are synthesized,
- messages are dispatched through the Hype path.


Do **not** require each node type to own bespoke native event code in v1.


### 7.6 Frame loop integration


SpriteKit offers frame-cycle callbacks and scene delegate callbacks. [S4]


Recommendation:

- use the frame cycle to drive runtime updates,
- expose a single HypeTalk `frameUpdate dt` surface,
- never let HypeTalk block the render loop for long,
- budget heavy work away from frame-critical execution,
- guard re-entrant mutations during frame dispatch.


Important product rule:

- HypeTalk can observe and direct frame behavior,
- but large AI requests must never run inline with the frame loop.


### 7.7 Actions


SpriteKit actions are a very good fit for HypeTalk because they encode animation and timing without forcing the script engine to manually update every frame. [S5]


Recommendation:

- support named actions,
- expose sequence, group, repeat, follow-path, move, rotate, scale, fade, wait,
- allow HypeTalk to start, stop, and query actions by name,
- surface completion as `actionFinished actionName`.


### 7.8 Physics


SpriteKit provides a scene-level physics world and contact delegate infrastructure. [S6]


Recommended v1 physics scope:

- circle, rectangle, and texture-based physics bodies,
- categories by symbolic names mapped to bit masks,
- collision masks and contact masks,
- gravity control at scene level,
- impulses, forces, and velocity,
- contact begin and end events.


Recommended later scope:

- joints,
- fields,
- compound bodies,
- editor polygon tools.


### 7.9 Asset pipeline and repository implementation


SpriteKit supports texture atlases and preloading. Xcode’s build-time atlas workflow is useful in app development, but Hype is a runtime authoring environment. [S7]


Therefore Hype should put the **Sprite Repository in front of SpriteKit’s raw asset APIs**.


Recommended implementation rules:

- ordinary image assets resolve directly from repository blobs,
- repository entries can produce derived variants such as frame slices and trimmed textures,
- runtime atlases and caches may be built as an optimization layer,
- required textures should preload before scene presentation when possible,
- missing assets should produce diagnostics instead of crashes,
- replacing an asset should invalidate caches and refresh interested scenes predictably.


Do not make `.sks` files or Xcode atlas folders the authoring center of gravity for Hype. They are useful references, not the core persistence model.


### 7.10 Transparency and mixed-media composition


Because `SKView` exposes transparency behavior, Hype can support Sprite Areas as overlays or mixed-media regions. [S9]


That creates several good product modes:

- opaque game panel,
- transparent particle overlay above a card,
- game scene beneath ordinary Hype controls,
- animated diagram inside a traditional card layout.


### 7.11 Threading model


Recommended rule set:

- all SpriteKit view, scene, and node mutations occur on the main actor,
- AI calls run off the render path,
- asset decoding, hashing, preview generation, and preparation may run in background tasks,
- diff application marshals back to the main actor,
- diagnostics capture should be lightweight and non-blocking,
- repository blob writes should be transactional.


## 8. Editor and UX requirements


### 8.1 Core authoring UI


The editor should provide:

- insert Sprite Area command,
- resize and move handles,
- scene tree inspector,
- node property inspector,
- script editor integration,
- play, pause, step, and reload controls,
- scene preview canvas,
- debug overlay toggles,
- scene snapshot capture for AI repair loops.


### 8.2 Sprite Repository window


The repository window should provide:

- import files or folders,
- drag-drop and paste support,
- grid and list browsing,
- search by name, tag, or kind,
- preview pane,
- sprite-sheet slicing UI,
- animation-clip editor,
- usage panel,
- rename, duplicate, replace, and delete actions,
- drag asset to Sprite Area or inspector target,
- “promote to repository” action from selected Hype media,
- repository diagnostics such as duplicate names, incompatible replacements, and missing variants.


### 8.3 Selection model


A creator should be able to:

- select the Sprite Area as a part,
- drill into the active scene,
- select nodes visually or from the tree,
- select a repository asset from the repository window,
- jump from selected node to its asset,
- jump from selected asset to its usages,
- jump from selected node to script,
- jump from script references back to node or asset.


### 8.4 Diagnostics


Must-have diagnostics:

- missing asset references,
- incompatible asset kind for a node role,
- invalid sprite-sheet slice definitions,
- invalid physics category names,
- duplicate node names in same scope,
- duplicate repository asset names,
- circular parent relationships,
- invalid property values,
- script errors bound to scene or node handlers,
- AI schema validation failures,
- scene load or presentation failures.


Diagnostics should be human-readable and AI-readable.


### 8.5 Undo and redo


Every editor and AI change to SceneSpec, node hierarchy, repository assets, asset metadata, and scripts must participate in Hype’s undo and redo stack. This is non-negotiable if AI is allowed to edit scenes and repository content.


## 9. Requirements matrix


### 9.1 Functional requirements


| ID | Requirement | Priority |
|---|---|---|
| FR-001 | User can insert a Sprite Area on a card or background | Must |
| FR-002 | Each stack has a Sprite Repository and a dedicated repository window | Must |
| FR-003 | User can import image and sprite-sheet assets into the repository as named assets | Must |
| FR-004 | Repository assets persist in the stack database with stable IDs | Must |
| FR-005 | Scene specs reference repository assets by `assetID` and optional `variantID`, not raw file paths | Must |
| FR-006 | User can drag a repository asset into a scene to create a node or bind it to a selected node | Must |
| FR-007 | User can slice sprite sheets into frames | Must |
| FR-008 | User can create derived animation clips from repository assets | Must |
| FR-009 | User can view usage of any repository asset across the stack | Must |
| FR-010 | User can rename or replace a repository asset while preserving references | Must |
| FR-011 | Sprite Area can host one active scene and store multiple named scene definitions | Must |
| FR-012 | Scene definitions persist inside the stack in a versioned declarative schema | Must |
| FR-013 | HypeTalk can create, update, delete, and query scenes and nodes | Must |
| FR-014 | HypeTalk can query repository assets and bind them to nodes | Must |
| FR-015 | Scene and node events dispatch through the extended HypeTalk message path | Must |
| FR-016 | Runtime supports sprites, labels, shapes, groups, and scene-level physics | Must |
| FR-017 | Runtime supports named actions and action-completion notifications | Must |
| FR-018 | Runtime supports keyboard and mouse input on macOS | Must |
| FR-019 | Editor exposes play, pause, step, reload, and debug overlay controls | Must |
| FR-020 | Local AI can generate a valid `SceneSpec`, `AssetRef` set, and HypeTalk scripts | Must |
| FR-021 | Local AI can inspect repository assets and current scene state through tools | Must |
| FR-022 | Local AI changes apply through validated diffs and asset ops with preview plus undo | Must |
| FR-023 | Runtime and repository diagnostics are available to both the human user and the local AI model | Must |
| FR-024 | Runtime supports camera nodes | Should |
| FR-025 | Runtime supports emitter nodes | Should |
| FR-026 | Runtime supports tile maps and tile-set assets | Should |
| FR-027 | Runtime supports audio nodes | Should |
| FR-028 | Runtime supports video sprite nodes | Could |
| FR-029 | Runtime supports shader-backed nodes and constraints | Could |
| FR-030 | Selected existing Hype media can be promoted into the repository as reusable sprite assets | Should |


### 9.2 Non-functional requirements


| ID | Requirement | Priority |
|---|---|---|
| NFR-001 | Scene edits hot reload without reopening the stack where feasible | Must |
| NFR-002 | Runtime mutations are main-actor safe and do not corrupt scene state | Must |
| NFR-003 | AI mutation paths are deterministic enough to validate and test | Must |
| NFR-004 | Missing or incompatible assets fail gracefully with diagnostics | Must |
| NFR-005 | Reference scenes maintain the selected target frame rate consistently | Must |
| NFR-006 | Texture preloading and caching are available for scenes that need them | Should |
| NFR-007 | Scene and repository serialization are forward-versioned and migration-friendly | Must |
| NFR-008 | Local AI operation works without cloud dependency | Must |
| NFR-009 | AI permission boundaries prevent arbitrary file or system mutation | Must |
| NFR-010 | Repository blobs are deduplicated by content hash where practical | Should |
| NFR-011 | Asset replacement invalidates relevant runtime caches safely | Must |
| NFR-012 | The stack remains portable and self-contained when shared | Must |
| NFR-013 | Large repository operations remain responsive through background preparation and lazy previews | Should |
| NFR-014 | Usage indexing is accurate enough to support safe rename, replace, and delete operations | Must |
| NFR-015 | The repository window remains usable with hundreds of assets in a stack | Should |
| NFR-016 | Hype warns the user before repository changes cause significant stack-size growth | Should |


## 10. Phased delivery plan


### Phase 0 — architecture spike

- confirm Sprite Area part integration with the existing Hype part and view system,
- define `SceneSpec`, `SceneDiff`, `AssetRef`, and `AssetOp` schemas,
- prototype `SKView` embedding and message routing,
- prototype Sprite Repository storage in the stack database,
- validate coordinate conversion and hot reload,
- validate repository-driven asset resolution and safe replacement.


### Phase 1 — shippable foundation

- Sprite Area part
- SceneSpec persistence
- Sprite Repository window
- database-backed named image and sprite-sheet assets
- sprite-sheet slicing and animation-clip derivation
- generic `HypeSKScene`
- sprite, group, label, and shape support
- actions
- basic physics
- keyboard and mouse input
- debug overlays
- local AI structured generation plus diff application
- editor inspector and preview basics


### Phase 1.5 — creator-quality upgrade

- usage inspector and safe asset replacement UX
- camera nodes
- emitters
- tile sets and tile maps
- texture preloading and atlas optimization
- richer diagnostics and AI repair loop
- promote existing Hype media into repository


### Phase 2 — richer multimedia and repository breadth

- audio nodes
- video nodes
- constraints
- scene transitions UI
- particle presets
- placeholder asset generation workflow
- repository smart collections and tags refinement


### Phase 3 — advanced AI runtime behavior

- event-triggered runtime director mode
- agent-loop repair and balancing workflows
- repository curation suggestions
- adaptive content generation from current stack context


## 11. Risks and open questions


### Risks


1. **Conceptual mismatch risk**  
   If SpriteKit is exposed too literally, HypeTalk becomes awkward and the feature feels bolted on.

2. **Frame-loop risk**  
   If HypeTalk or AI is allowed to run expensive work inline with frame updates, performance will degrade unpredictably.

3. **Serialization risk**  
   If runtime `SKNode` state becomes the de facto source of truth, save, load, asset repair, and AI editing will become fragile.

4. **Repository bloat risk**  
   If every imported asset is duplicated or stored without dedupe and preview policy, stack databases may become much larger than expected.

5. **Input-focus risk**  
   Mixed card UI and Sprite Area interaction may cause confusion unless focus and routing rules are explicit.

6. **AI trust risk**  
   Without structured outputs, validation, repository-aware tools, and undoable diffs, local-model edits will be too brittle.


### Open questions


1. Should the Sprite Repository remain sprite-specific, or should it later become the first step toward a unified Hype Asset Library?
2. Should one Sprite Area eventually support multiple simultaneously layered scenes, or is one active scene enough long term?
3. Should background-level Sprite Areas ever retain live runtime state across card navigation, or should shared state remain data-driven only?
4. Should repository asset names be globally unique within a stack, or should collections provide optional namespacing?
5. How much of the scene graph should be directly editable on-canvas versus tree and inspector only in v1?
6. Should audio and video assets enter the repository in v1, or should image-centric assets remain the focus until phase 2?
7. Should Hype later expose an advanced “native SpriteKit coordinate mode,” or is a top-left Hype coordinate model sufficient?


## 12. Recommendation summary


The strongest path is:


1. **Add SpriteKit as a first-class Sprite Area part**
2. **Add a stack-scoped Sprite Repository backed by the stack database**
3. **Persist declarative scene data and stable asset references, not SpriteKit runtime archives**
4. **Extend HypeTalk object and message semantics into both the scene graph and repository**
5. **Keep frame-critical work native in Swift and SpriteKit**
6. **Use structured AI outputs, repository-aware tools, and transactional diffs**
7. **Design for mixed-media cards and reusable stack-wide assets from day one**


That gives Hype something genuinely differentiated: a modern HyperCard-style authoring environment where conventional UI, media, reusable game assets, real-time 2D scenes, and local AI all coexist in the same stack.


## Appendix A — Proposed implementation prompt context for code generation


Use the following assumptions when generating code for the first implementation pass:


- Target platform: macOS app in Swift
- Existing product model: stack → background → card → part
- New part type: `HypeSpritePartModel` / `HypeSpritePartView`
- New stack subsystem: `HypeSpriteRepositoryStore`
- Repository UI: `HypeSpriteRepositoryWindowController`
- Rendering host: `SKView` embedded in Hype’s existing part and view system
- Runtime scene class: one generic reusable `HypeSKScene` subclass, not generated subclasses per user scene
- Canonical persistence model: `HypeSceneSpec`, `HypeNodeSpec`, `HypeAssetRef`, `HypeSceneDiff`, `HypeAssetOp`
- Repository persistence model: database-backed metadata plus blob store inside the stack document
- Message routing: node → parent group(s) → scene → spriteArea → card → background → stack → runtime
- Required node types for initial pass: sprite, group, label, shape
- Required repository asset kinds for initial pass: image texture, sprite sheet, animation clip
- Required v1 extras: actions, scene gravity, physics categories and contact events, keyboard and mouse input, debug toggles
- Recommended later node types: emitter, tileMap, camera, audio, video
- Recommended later repository kinds: audio clip, video clip, tile set, particle preset
- Use `SKNode.name` plus `userData` to map runtime nodes back to Hype IDs, names, and asset IDs
- Scene edits should be hot-reloadable when possible
- All runtime SpriteKit mutations must be on the main actor
- All repository blob writes should be transactional and undoable
- Asset references should persist by `assetID` and optional `variantID`, never by raw file path
- Asset replacement should preserve `assetID` when semantically replacing content
- Default coordinate model for HypeTalk inside a Sprite Area: top-left origin, `y` increases downward, bridge converts to SpriteKit coordinates
- Sprite Area has `designSize`; default `scaleMode` is a fixed logical scene with aspect fit
- Minimum editor controls: play, pause, step, reload, show FPS, show node count, show draw count, show physics
- Minimum repository controls: import, search, preview, slice sprite sheet, create animation clip, usage view, rename, replace, drag into scene
- Minimum HypeTalk surface:
  - create scene
  - create sprite
  - set loc, x, y, z, rotation, scale, alpha, hidden
  - set texture or asset
  - set size
  - set physics body, category, contact categories, collision categories
  - run action, stop action
  - import asset, slice asset, replace asset, create animationClip, query asset usage
  - `openScene`, `closeScene`, `frameUpdate`, `beginContact`, `endContact`, `keyDown`, `keyUp`, `mouseDown`, `mouseUp`, `assetMissing`
- AI integration contract:
  - full-create path returns `SceneSpec`
  - edit path returns `SceneDiff`
  - repository edit path returns `AssetOp[]`
  - script path returns `ScriptPatch`
  - all AI changes must validate before apply
  - all AI changes must be undoable
- Do not make `.sks` files the canonical authoring format
- Do not generate per-scene Swift subclasses
- Do not rely on the LLM for per-frame control
- Prefer a bridge or delegate architecture over direct scripting logic inside SpriteKit subclasses


## Appendix B — Suggested schema sketch for code generation


These are not final API contracts, but they are good draft shapes for initial implementation.


```swift
struct HypeSceneSpec: Codable, Identifiable {
    var id: UUID
    var name: String
    var designSize: CGSizeCodable
    var backgroundColor: ColorCodable?
    var gravity: VectorCodable?
    var nodes: [HypeNodeSpec]
    var scripts: [HypeScriptBinding]
    var version: Int
}

struct HypeNodeSpec: Codable, Identifiable {
    var id: UUID
    var name: String?
    var kind: HypeNodeKind
    var parentID: UUID?
    var position: PointCodable
    var zPosition: Double?
    var rotation: Double?
    var scaleX: Double?
    var scaleY: Double?
    var alpha: Double?
    var isHidden: Bool?
    var size: CGSizeCodable?
    var assetRef: HypeAssetRef?
    var physics: HypePhysicsSpec?
    var text: String?
    var color: ColorCodable?
    var scripts: [HypeScriptBinding]?
    var custom: [String: JSONValue]?
}

struct HypeAssetRef: Codable {
    var assetID: UUID
    var variantID: UUID?
    var nameHint: String?
    var expectedKind: HypeAssetKind
    var role: String?
}

struct HypeSpriteAsset: Codable, Identifiable {
    var id: UUID
    var name: String
    var kind: HypeAssetKind
    var blobID: UUID
    var width: Int?
    var height: Int?
    var frameCount: Int?
    var tags: [String]
    var metadata: [String: JSONValue]
}

struct HypeAssetVariant: Codable, Identifiable {
    var id: UUID
    var assetID: UUID
    var kind: HypeAssetVariantKind
    var metadata: [String: JSONValue]
}

struct HypeAnimationClip: Codable, Identifiable {
    var id: UUID
    var name: String
    var assetID: UUID
    var frameVariantIDs: [UUID]
    var fps: Double
    var loop: Bool
}

struct HypeSceneDiff: Codable {
    var operations: [HypeSceneDiffOp]
}

struct HypeAssetOp: Codable {
    var operation: HypeAssetOperationKind
    var targetAssetID: UUID?
    var payload: [String: JSONValue]
}
```


Recommended repository-oriented enums:

- `HypeAssetKind = imageTexture, spriteSheet, animationClip, tileSet, audioClip, videoClip, placeholderAsset`
- `HypeAssetVariantKind = frameSlice, trimmedTexture, tileSet, collisionMask, previewImage`
- `HypeNodeKind = sprite, group, label, shape, emitter, tileMap, camera, videoSprite, audioNode`


## Appendix C — Research basis


### Research conclusions used in this draft


1. SpriteKit is a 2D framework centered on `SKScene` and a node tree, rendered by `SKView`, with built-in actions, physics, cameras, constraints, tile maps, video, and related scene-building nodes. [S1][S2][S3][S5][S6][S8]

2. SpriteKit has an explicit frame-cycle model and debug and performance controls suitable for an integrated authoring tool. [S3][S4][S7][S9]

3. HyperCard’s durable strengths are object-attached scripts, message-passing order, and stack, background, card composition. [S10][S11][S12]

4. HyperCard used native compiled extensions (XCMD and XFCN) for speed-sensitive and system-level capabilities, which is a strong analogy for keeping SpriteKit native while exposing HypeTalk-friendly surfaces. [S11]

5. Ollama’s structured outputs, tool calling, agent-loop pattern, and OpenAI-compatible API make it practical to drive scene creation and editing locally with schema validation. [S14][S15][S16]

6. First-principles product conclusion: Hype needs both a scene bridge and an asset bridge. The scene bridge reconciles Hype’s persistent authoring model with SpriteKit’s runtime scene graph; the asset bridge is the Sprite Repository, which reconciles stack portability, AI grounding, and runtime texture loading.


### Source list


- **S1** — Apple Developer Documentation — [SpriteKit overview](https://developer.apple.com/documentation/spritekit/)
- **S2** — Apple Developer Documentation — [SKScene](https://developer.apple.com/documentation/spritekit/skscene)
- **S3** — Apple Developer Documentation — [SKView](https://developer.apple.com/documentation/spritekit/skview)
- **S4** — Apple Developer Documentation — [Responding to Frame-Cycle Events](https://developer.apple.com/documentation/spritekit/responding-to-frame-cycle-events)
- **S5** — Apple Developer Documentation — [Getting Started with Actions / SKAction](https://developer.apple.com/documentation/spritekit/getting-started-with-actions)
- **S6** — Apple Developer Documentation — [Getting Started with Physics / SKPhysicsContactDelegate](https://developer.apple.com/documentation/spritekit/getting-started-with-physics)
- **S7** — Apple Developer Documentation — [About Texture Atlases / Maximizing Texture Performance](https://developer.apple.com/documentation/spritekit/about-texture-atlases)
- **S8** — Apple Developer Documentation — [Nodes for Scene Building](https://developer.apple.com/documentation/spritekit/nodes-for-scene-building)
- **S9** — Apple Developer Documentation — [SKView properties including transparency, scale mode, preferred FPS, and debug toggles](https://developer.apple.com/documentation/spritekit/skview)
- **S10** — The HyperCard Center — [The message-passing order](https://www.hypercard.center/HyperTalkReference/hypertalkbasics/The-message-passing-order)
- **S11** — Dr. Dobb's Journal — [An Introduction to HyperCard Programming](https://jacobfilipp.com/DrDobbs/articles/DDJ/1988/8814/8814d/8814d.htm)
- **S12** — Internet Archive text — [The Complete HyperCard Handbook](https://archive.org/stream/The_Complete_HyperCard_Handbook/The_Complete_HyperCard_Handbook_djvu.txt)
- **S13** — The HyperCard Center — [sharedText property](https://www.hypercard.center/HyperTalkReference/properties/sharedText)
- **S14** — Ollama Docs — [Structured Outputs](https://docs.ollama.com/capabilities/structured-outputs)
- **S15** — Ollama Docs — [Tool Calling](https://docs.ollama.com/capabilities/tool-calling)
- **S16** — Ollama Docs — [API Introduction / OpenAI Compatibility](https://docs.ollama.com/api/introduction)

# Meshy.ai Integration Plan for Hype

> Status: design proposal — not yet implemented. Date: 2026-05-10.
>
> This plan is the proposed staged-delivery path for adding Meshy.ai
> 3D asset generation into Hype. It follows the same control gates the
> Hype Feature Gap plan uses (architect → security → build → security
> → outcome tests) and is sized so each phase ships independently.

---

## 1. Goal

Let Hype authors generate 3D assets — single models, multi-view
reconstructions, rigged characters, animated characters — directly
inside the app and use them in stacks without leaving the
authoring loop. Concretely:

- **Sprite Repository** can hold 3D models (`AssetKind.model3D`) the
  same way it holds image textures, sprite sheets, and audio clips.
- **`scene3D` part** can be filled from any repository model in one
  click; provenance (model name, prompt, license, credits consumed)
  travels with the asset.
- **AI tools** can call Meshy.ai during a tool-call turn, so a
  prompt like "make a low-poly tree and put it in the scene"
  resolves through the existing `AIEditTransaction` preview/apply
  flow.
- **Preferences** gains a Meshy.ai section: API key entry stored in
  the macOS Keychain, balance readout, default model / format
  toggles.

The goal is to make 3D feel like a first-class media type next to
images and audio — not a side feature behind a separate window.

---

## 2. What Meshy.ai gives us

Confirmed by docs at `https://docs.meshy.ai/en` on 2026-05-10:

| Endpoint                              | Method | Notes |
|---------------------------------------|--------|-------|
| `/openapi/v2/text-to-3d`              | POST/GET/DELETE | `mode: "preview"` builds geometry; `mode: "refine"` adds textures. Polling via GET; SSE stream at `/:id/stream`. |
| `/openapi/v1/image-to-3d`             | POST/GET/DELETE | Single PNG/JPEG (URL or base64 data URI). |
| `/openapi/v1/multi-image-to-3d`       | POST   | 1–4 images of the same object from different angles. |
| `/openapi/v1/remesh`                  | POST   | Refine geometry / change polycount on an existing model. (5 credits) |
| `/openapi/v1/retexture`               | POST   | New textures on an existing model. (10 credits) |
| `/openapi/v1/rigging`                 | POST   | Auto-rig a humanoid GLB; produces FBX+GLB with bones + basic walking/running clips. (5 credits) |
| `/openapi/v1/animations`              | POST   | Apply a library animation (`action_id`) to a rigged model. (3 credits per call) |
| `/openapi/v1/balance`                 | GET    | Returns `{ "balance": <int> }` — remaining credit. |
| Webhooks                              | n/a    | Account-level, configured in the Meshy dashboard, max 5 active. POST JSON of the task object on status change. **No HMAC verification** — webhook URL secret is your defence. |

**Auth.** `Authorization: Bearer msy_…`. RFC 6750. Key is created
once in the Meshy dashboard, shown one time, revocable any time.
No scopes, no rotation.

**Workflow.** Async. POST returns `{"result": "<task_id>"}` (or
just an `id` for v1 endpoints). Poll the GET endpoint until
`status` is `SUCCEEDED`, `FAILED`, or `CANCELED`. Success carries
a `model_urls` object with download URLs for every requested
format (`glb`, `fbx`, `usdz`, `obj`, `mtl`, `stl`, `3mf`) and a
`texture_urls` array of PBR maps. Downloads of those URLs are
direct (no bearer required per the quickstart Python sample).

**Rate limits.** Pro tier: 20 RPS, 10 queued tasks max.
Enterprise: 100 RPS, 50+ queued. Per-account, not per-key.

**Credits.** 3–30 per call depending on model and operation; user
buys credit packs in the Meshy dashboard. We never pay; we just
spend the user's credit on their behalf.

**Output formats Hype already understands.**

| Meshy format | Hype handler |
|---|---|
| `glb`  | `scene3D` part loads directly via SceneKit (preferred — single-file with embedded textures) |
| `usdz` | `scene3D` part loads directly via SceneKit |
| `obj` + `mtl` | `scene3D` part loads directly via SceneKit |
| `stl` | `STLConverter` (already in HypeCore) auto-converts to OBJ on import |
| `fbx` | Not currently supported — out of scope for Phase 1 |
| `3mf` | Not currently supported — out of scope for Phase 1 |

GLB is the canonical target. We request GLB always, plus USDZ
when the user opts into "AR-ready" output (USDZ is what Quick
Look on macOS / iOS prefers).

---

## 3. Where it slots into Hype

Five existing surfaces are the right joins; we should not
reinvent any of them.

### 3.1 `SpriteRepository` gains a `model3D` asset kind

Today `AssetKind` covers `imageTexture`, `spriteSheet`, `tileSet`,
`audioClip`, `videoClip`, `particlePreset`, `placeholderAsset`. We
add **`model3D`**. The repository row stores the GLB bytes inline
(same pattern as audio clips today — bytes embedded in the `.hype`
file so stacks stay self-contained), with optional sidecars in
`tags` for prompt, source images, format variants downloaded.

A typical 3D model from Meshy is 1–5 MB at default polycount; a
hi-def 60k-triangle GLB is 8–15 MB. Embedding is consistent with
how Hype stores audio (`mp3`, `m4a`) inline already. The 50 MB-
per-asset soft cap stays where it is; Meshy's hi-detail output
will land well below it.

### 3.2 `scene3D` part is the consumer

`scene3D` already supports `.usdz`, `.scn`, `.dae`, `.obj`, `.stl`,
and `.glb`. We add a small change so a scene3D part can name an
`AssetRef` directly (just like sprite nodes name asset refs)
instead of carrying a path:

```swift
public var scene3DAssetRef: AssetRef?   // NEW — preferred reference
public var scene3DSourceURL: String     // existing — file:// or http path (still supported)
public var scene3DURL: String           // existing — resolved path after format conversion
```

When `scene3DAssetRef` is set, the renderer / SceneKit host resolves
the bytes through `SpriteRepository.asset(byId:)`, writes them to a
short-lived cache file under
`~/Library/Caches/com.hype.app/scene3d-cache/<assetId>.<ext>`, and
loads them. Same lifecycle and same security boundary as
`STLConverter` already uses, just keyed by asset ID instead of by
source-file SHA. The path stays self-contained — a `.hype` file
that uses Meshy-generated assets is portable to another machine.

### 3.3 Sprite Repository window gains a "Generate 3D…" affordance

The repository window already has Import (`+`), Tileset Import,
and the recently-added Transparent Background action. We add a
**Generate 3D** menu under the Plus button (or as a dedicated
button) opening a sheet with three tabs:

- **Text → 3D** — prompt textbox, ai_model picker (meshy-5 /
  meshy-6 / latest), art-style toggle, target polycount slider
  (1k–300k), symmetry / pose-mode / decimation knobs, "Refine
  with textures" checkbox.
- **Image → 3D** — drag-target or "from library" picker (picks
  an `imageTexture` asset), same texture / pose / symmetry
  options.
- **Multi-image → 3D** — 1–4 image slots (drag-target each), with
  a hint that all images should be the same object from different
  angles.

Each tab has a single **Generate** button at the bottom. The button
queues the call, watches it via `MeshyTaskMonitor` (see §5.1), and
on success drops the resulting GLB into the repository as a
`model3D` asset with `AssetProvenance.aiGenerated` and a sidecar
record (prompt, model, polycount, credits consumed, source image
asset IDs if any).

### 3.4 `scene3D` part inspector gains "From Repository…"

Replace today's free-form path entry on the inspector's scene3D
section with two controls:

- **From Repository** popup of available `model3D` assets — pick
  one and the part's `scene3DAssetRef` is set.
- **Import File** (existing path entry) — falls back to the legacy
  file-URL path for users who have a model on disk.

A small **Generate from prompt…** button next to the popup opens
the same sheet from §3.3 with the result auto-bound to this part.

### 3.5 AI tool surface

We add three tools to `HypeTools.swift`, mirroring the existing
`generate_image` tool:

- `generate_3d_model_from_text` — `prompt`, `ai_model?`,
  `polycount?`, `pose_mode?`, `symmetry_mode?`, `art_style?`.
- `generate_3d_model_from_image` — `image_asset_name` (looked up
  in the repository) or `image_url`.
- `generate_3d_model_from_images` — `image_asset_names: [String]`
  (1–4).

All three return the new asset's name (and ID) so a follow-up
`create_scene3d` tool call can reference it. Because these are
long-running, they live inside the existing
`AIEditTransactionRunner`: the model previews the change, the
user clicks Apply, the asset is committed.

Optionally:

- `list_3d_models` — read-side, lists the `model3D` assets so the
  model can reference an existing one.
- `meshy_balance` — read-side, returns the credit balance for
  contexts where the model should warn the user before spending.

---

## 4. New files / changes by directory

### New
```
Sources/HypeCore/AI/MeshyAIClient.swift                # Core HTTP client (HypeAIClient-style contract)
Sources/HypeCore/AI/MeshyTaskMonitor.swift             # Async polling + SSE streaming
Sources/HypeCore/AI/MeshyModels.swift                  # Codable structs for request/response
Sources/HypeCore/AI/MeshyError.swift                   # Typed errors (rate-limited, insufficient credit, etc.)
Sources/HypeCore/AI/Meshy3DAssetImporter.swift         # task_id → SpriteAsset (writes bytes to repository)
Sources/Hype/Views/Generate3DSheet.swift               # The three-tab generation UI
Sources/Hype/Views/PreferencesView+Meshy.swift         # Preferences section additions
Tests/HypeCoreTests/MeshyAIClientTests.swift           # Encoding/decoding, retry, status polling
Tests/HypeCoreTests/MeshyTaskMonitorTests.swift        # Long-running task progress
Tests/HypeCoreTests/Meshy3DAssetImporterTests.swift    # Asset materialization
Tests/HypeTests/Generate3DSheetTests.swift             # SwiftUI sheet input validation
```

### Modified
```
Sources/HypeCore/Models/SpriteRepository.swift         # Add AssetKind.model3D + provenance fields
Sources/HypeCore/Models/Part.swift                     # Add scene3DAssetRef: AssetRef?
Sources/HypeCore/Models/AssetRef.swift                 # No change expected
Sources/HypeCore/AI/HypeTools.swift                    # Three new tool schemas
Sources/HypeCore/AI/HypeToolExecutor.swift             # Dispatch the new tools through Meshy3DAssetImporter
Sources/HypeCore/AI/AIEditTransaction.swift            # Delta tracking already covers spriteRepository — confirm
Sources/Hype/Views/PreferencesView.swift               # Inline the new Meshy section
Sources/Hype/Views/SpriteRepositoryView.swift          # "Generate 3D…" button + sheet host
Sources/Hype/Views/PropertyInspector.swift             # scene3D section: From Repository popup
Sources/HypeCore/AI/WebAssetSearch/KeychainStore.swift # Add a meshyAPIKeyAccount constant
Sources/HypeCore/AI/HypeTalkGuide.swift                # Document new tool surface
Sources/Hype/Views/MainContentView.swift               # Wire Generate3DSheet presentation state
architecture.md                                        # §7 add the Meshy integration narrative
README.md                                              # AI authoring section mentions 3D generation
```

### Net size
~1,400 LOC across new files + ~400 LOC of targeted edits to existing
files. Comparable to the OpenAI provider integration in size.

---

## 5. Runtime architecture

### 5.1 Async task lifecycle

```
┌───────────────────────────┐
│  Generate3DSheet (UI)     │
│  or AI tool call          │
└──────────────┬────────────┘
               │ MeshyGenerationRequest
               ▼
┌──────────────────────────────────────┐
│  MeshyAIClient                       │
│   • POST /openapi/v2/text-to-3d      │
│   • returns task_id                  │
└──────────────┬───────────────────────┘
               │ task_id
               ▼
┌──────────────────────────────────────┐
│  MeshyTaskMonitor (actor)            │
│   • SSE stream when available        │
│   • fallback polling at 3s intervals │
│   • publishes progress + status      │
└──────────────┬───────────────────────┘
               │ MeshyTaskResult (model_urls, credits_consumed)
               ▼
┌──────────────────────────────────────┐
│  Meshy3DAssetImporter                │
│   • download GLB bytes               │
│   • optionally download USDZ bytes   │
│   • create SpriteAsset               │
│     (kind=.model3D, provenance=.aiGenerated) │
│   • return AssetRef                  │
└──────────────┬───────────────────────┘
               │ AssetRef
               ▼
┌──────────────────────────────────────┐
│  AIEditTransactionRunner             │
│   (preview / apply / rollback)       │
└──────────────────────────────────────┘
```

`MeshyTaskMonitor` is an `actor` that owns a single in-flight
task ID and exposes:

```swift
actor MeshyTaskMonitor {
    enum State { case pending, inProgress(percent: Int), succeeded(MeshyTaskResult), failed(MeshyError), canceled }
    func progress() -> AsyncStream<State>
    func cancel() async
}
```

- **SSE first.** If the Meshy SSE endpoint is reachable
  (`GET /:id/stream`), use it. Lowest-latency progress updates,
  no client-side polling.
- **Poll fallback.** If SSE returns 4xx (older API plan / regional
  restriction) we fall back to polling `GET /:id` every 3 s with
  exponential backoff if the task is `PENDING` for >60 s.
- **Cancellation.** UI cancel → `DELETE /:id` + monitor returns
  `.canceled` to subscribers.
- **Timeout.** Hard ceiling: 10 minutes per task. After that we
  return `.failed(.timedOut)` and the user can retry or report.

### 5.2 Webhook strategy: **deferred**

Meshy webhooks are account-level (not per-task) and have no HMAC
verification. Receiving them requires a public HTTP listener
running in Hype — feasible (we have `listen for http` infra) but
unnecessary for the first cut and a real security surface. We
ship polling-only in Phase 1. Webhooks become Phase 4
(opt-in, off by default, listener in `StackRuntime`, callback
fires the `meshyTaskFinished` HypeTalk message).

### 5.3 Concurrency & cancellation

`MeshyAIClient` is `Sendable` and `actor`-isolated. Tasks
generated from the SwiftUI Generate3DSheet bind their progress
stream to a `@State` model so the cancel button works. AI-driven
generation lives inside `AIEditTransactionRunner`'s task tree, so
canceling the whole transaction cancels the Meshy task too.

### 5.4 Disk I/O

- GLB bytes are downloaded to a temp file in
  `~/Library/Caches/com.hype.app/meshy-staging/<taskId>.glb`,
  read into `Data`, written into `SpriteAsset.data`, and the temp
  file is deleted.
- The cache directory has a 200 MB ceiling enforced via
  size-based eviction (oldest first).
- `STLConverter`'s existing cache pattern is the model; we reuse
  its directory scaffolding.

---

## 6. UI design

### 6.1 Sprite Repository — Generate 3D button

A small **3D Cube + Sparkle** icon goes next to the existing
"+ Import" / "Import Tileset" buttons in the repository toolbar.
Click opens the **Generate 3D** sheet (modal, dismissable).

### 6.2 Generate 3D sheet

Three-tab `SwiftUI` sheet, 540 × 480 fixed:

```
┌─────────────────────────────────────────────────────┐
│  Generate 3D                          [×]           │
├─────────────────────────────────────────────────────┤
│ [ Text ]  [ Image ]  [ Multi-image ]                │  ← tab bar
├─────────────────────────────────────────────────────┤
│ Prompt:                                             │
│  ┌─────────────────────────────────────────────┐    │
│  │ A medieval wooden barrel, weathered, with   │    │
│  │ iron bands                                  │    │
│  └─────────────────────────────────────────────┘    │
│  Model:    [meshy-6 ▾]   Polycount: 30,000  [─●─]   │
│  Style:    [Realistic ▾]                            │
│  Symmetry: [Auto ▾]      Pose: [None ▾]             │
│  ☑ Generate textures (refine pass, +20 credits)     │
│  ☐ Also export USDZ (for AR / Quick Look)           │
├─────────────────────────────────────────────────────┤
│  Cost: ≈ 40 credits   |   Balance: 380 credits      │
│  [Cancel]                              [ Generate ] │
└─────────────────────────────────────────────────────┘
```

After clicking **Generate** the sheet swaps to a progress view:

```
┌─────────────────────────────────────────────────────┐
│  Generating 3D model…                               │
├─────────────────────────────────────────────────────┤
│  Status:   Refining textures                        │
│  Progress: ███████████░░░░░░░  62%                  │
│  Elapsed:  1:24 / est. ~2:30                        │
│                                                     │
│  [Cancel]                                           │
└─────────────────────────────────────────────────────┘
```

On success the sheet dismisses, the asset appears in the
repository grid pre-selected, and the inspector right pane
auto-focuses its detail view.

### 6.3 Scene3D inspector — From Repository popup

Replaces the current single text path entry with:

```
3D MODEL
┌────────────────────────────────────────┐
│ From Repository: [ barrel.glb     ▾ ] │
│  – or –                                │
│ Import File:     [ Choose…           ] │
│                                        │
│ [ Generate from prompt… ]              │
└────────────────────────────────────────┘
```

The popup lists every `model3D` asset in the repository, sorted
by most-recently-added. Picking one sets `scene3DAssetRef` on
the selected part.

### 6.4 Preferences — Meshy.ai section

A new section in the AI tab of the Preferences window, sitting
between OpenAI and the Ollama controls:

```
┌─ Meshy.ai (3D model generation) ──────────────────┐
│                                                   │
│  API key:                                         │
│  [ msy_•••••••••••••••••••••••••••••• ] [Save]    │
│  ☑ API key stored (tap to replace)                │
│                                                   │
│  Balance:  380 credits                  [Refresh] │
│                                                   │
│  Default model:    [ meshy-6 ▾ ]                  │
│  Default formats:  ☑ GLB    ☐ USDZ    ☐ FBX       │
│                                                   │
│  Privacy: prompts and source images are sent to   │
│  api.meshy.ai. Generated models are downloaded    │
│  to ~/Library/Caches/com.hype.app and embedded    │
│  into the .hype file you're working in.           │
│                                                   │
│  [ Test connection ]  [ Open Meshy dashboard ]    │
│                                                   │
└───────────────────────────────────────────────────┘
```

### 6.5 HypeTalk surface

Even though Phase 1 is GUI-driven, we expose a minimal
script-callable form so the AI's `generate_3d_model_from_text`
tool has a HypeTalk-visible analog and authors can script
generation in long-running game logic:

```
-- Async form (preferred): result lands in `it` as the asset name
ask meshy "a medieval wooden barrel" with style "realistic"
-- ↳ `it` will be e.g. "barrel-018a2…glb"
set the object of scene3d "barrel" to it

-- Or via with-message:
ask meshy "a low-poly tree" with message "treeReady"

on treeReady assetName
  set the object of scene3d "tree" to assetName
end treeReady
```

This is sugar over `MeshyAIClient`; the grammar additions are a
small lexer/parser delta. The user-facing tooltip on the
`scene3D` part's "Generate from prompt…" button names this form
in the help text.

---

## 7. Key storage & security

### 7.1 Keychain

Add a new account constant to `KeychainStore` (the same module
that stores `openAIAPIKeyAccount`):

```swift
extension KeychainStore {
    public static let meshyAPIKeyAccount = "com.hype.app.meshyAPIKey"
}
```

The Preferences view writes the key with
`KeychainStore.setSecret(account:, secret:)` exactly the way the
OpenAI key is stored today. `MeshyAIClient` reads it on demand;
no plaintext copy is ever held in process memory longer than the
single HTTP request that consumes it.

### 7.2 Network egress policy

`MeshyAIClient` only ever talks to `https://api.meshy.ai`, hard-
coded in the client (no user-configurable base URL, no
substitution). This is the same defence the OpenAI client uses
against accidental token exfiltration via a swapped base URL.

### 7.3 Asset bytes

Downloads happen over HTTPS to URLs returned by the Meshy task.
Per the docs, those download URLs are **direct** (no bearer
required); we still validate that they're `https://` and that
the response `Content-Type` matches what we asked for.

### 7.4 Privacy disclosure

The Preferences section has an explicit "what gets sent to
Meshy" note (see §6.4). When the user generates from an image,
the source image is uploaded to Meshy as a data URI inside the
JSON payload — no separate file upload required, but the user
should know. If we add a future feature to upload large source
images via signed URL, that's an additional consent surface.

### 7.5 Credit awareness

The "Generate" button always shows the **estimated cost** for the
selected settings (computed from the public pricing table in
Meshy's docs) AND the **current balance** (fetched from
`GET /balance` once when the sheet opens, refreshed after each
task). If the cost exceeds the balance, the button disables and
a "Add credits in Meshy dashboard" link replaces it.

### 7.6 Moderation

We pass `moderation: true` on every preview task by default. The
user can flip it off in Preferences for adult / mature content
work, but the default is the conservative path.

---

## 8. AI tool surface & HypeTalk integration

### 8.1 New tools

Three new entries in `HypeTools.allTools`:

```swift
makeTool(name: "generate_3d_model_from_text", description: """
    Generate a 3D model from a text prompt using Meshy.ai. Returns the new asset's
    name in the Sprite Repository. Always runs inside an AIEditTransaction so the
    user can preview before applying. Default formats: GLB only. PBR textures are
    on by default (refine pass). Requires the user's Meshy API key to be set in
    Preferences; tool will return an error otherwise.
    """, params: [
    "prompt":      ("string", "Plain-English description of the model", true),
    "ai_model":    ("string", "meshy-5 | meshy-6 | latest (default)", false),
    "polycount":   ("string", "Target polygon count (100–300,000, default 30,000)", false),
    "art_style":   ("string", "realistic | sculpture (default realistic)", false),
    "pose_mode":   ("string", "a-pose | t-pose | empty (humanoids only)", false),
    "with_usdz":   ("string", "true to also download USDZ for AR/Quick Look", false),
]),

makeTool(name: "generate_3d_model_from_image", description: """
    Generate a 3D model from a single image. The image is either an existing
    Sprite Repository asset (pass image_asset_name) or a URL (pass image_url).
    Returns the new asset's name. Same Meshy.ai prerequisites as
    generate_3d_model_from_text.
    """, params: [
    "image_asset_name": ("string", "Name of an existing imageTexture asset", false),
    "image_url":        ("string", "Public https URL to an image (alternative to image_asset_name)", false),
    "ai_model":         ("string", "meshy-5 | meshy-6 | latest", false),
    "polycount":        ("string", "100–300,000", false),
]),

makeTool(name: "generate_3d_model_from_images", description: """
    Generate a 3D model from 1–4 images of the same object from different angles.
    Higher fidelity than single-image when multiple views are available. Names
    are looked up in the Sprite Repository. Returns the new asset's name.
    """, params: [
    "image_asset_names": ("array",  "1–4 image asset names", true),
    "ai_model":          ("string", "meshy-5 | meshy-6 | latest", false),
]),
```

Plus one read-side tool:

```swift
makeTool(name: "list_3d_models", description: """
    Lists every model3D asset in the Sprite Repository, including provenance
    (which prompt or images created it, when, and how many credits it cost).
    Use before generate_3d_model_from_text to avoid regenerating something the
    user already has.
    """, params: [:]),
```

### 8.2 HypeTalkGuide additions

A new section in `HypeTalkGuide.llmContext`:

```markdown
## 3D model generation (Meshy.ai)

The user can attach a Meshy.ai API key in Preferences → AI → Meshy.
When set, you can generate 3D assets directly:

- `generate_3d_model_from_text(prompt: "…")` → asset name
- `generate_3d_model_from_image(image_asset_name: "…")` → asset name
- `generate_3d_model_from_images(image_asset_names: ["front","side","back"])`

Always wire the returned asset name into a scene3D part:

    create_scene3d(name: "tree", left: 100, top: 100, width: 300, height: 300)
    set_part_property(part_name: "tree", property: "object", value: <asset_name>)

Generation costs Meshy.ai credits; budget 10–30 credits per text-to-3D and
about 20 credits extra for the textured refine pass. Use list_3d_models
first if the user might already have what they need.
```

### 8.3 HypeTalk grammar (Phase 3)

A `ask meshy "<prompt>"` form lands in Phase 3. Lexer keyword,
parser branch in the existing `ask` statement, interpreter
dispatch routes through `MeshyAIClient`. Async — same pattern as
`ask ai`.

---

## 9. Phased delivery

Following the same control gates used by the existing
`HypeFeatureGapImplementationPlan`:

### Phase 1 — Foundations (text-to-3D, sync via polling, no AI)
- `MeshyAIClient` + `MeshyTaskMonitor` + `MeshyModels` + `MeshyError`
- `AssetKind.model3D` in `SpriteRepository`
- `Meshy3DAssetImporter`
- Preferences: API key entry, Keychain storage, balance display
- `scene3DAssetRef` on `Part`
- Sprite Repository: "Generate 3D…" button, text-to-3D tab only
- `scene3D` inspector: "From Repository…" popup
- Acceptance: a stack saved with a generated GLB reopens with the
  same model visible; key persists across launches.

### Phase 2 — Image inputs and AI tools
- Image-to-3D and Multi-image-to-3D tabs
- Three new AI tools (`generate_3d_model_from_text`,
  `generate_3d_model_from_image`, `generate_3d_model_from_images`)
- `list_3d_models` read-side tool
- AIEditTransaction wraps tool outputs (preview → apply → rollback)
- Acceptance: a multi-turn AI session can say "generate a barrel and
  put it on the card" and end with a placed scene3D part that
  references a new repository asset.

### Phase 3 — Rigging, animation, HypeTalk
- `MeshyAIClient.rig(modelTaskId:)` + `MeshyAIClient.animate(rigTaskId:, actionId:)`
- New `AssetKind.rigged3D` (or a flag on `model3D`)
- New `AssetKind.animation3D` for the FBX/GLB action clips
- HypeTalk `ask meshy …` grammar
- Scene3D inspector: per-asset animation picker
- Acceptance: a humanoid generated by text → rig → walk animation
  plays in the scene3D part in browse mode.

### Phase 4 — Webhooks + remesh + retexture
- HTTP listener registers a Meshy webhook on startup if enabled
- `meshyTaskFinished` HypeTalk message dispatch
- `remesh` and `retexture` tools (for "make this lower-poly" and
  "re-skin this with a new texture")
- Acceptance: a generation triggered from HypeTalk via webhook
  callback fires its handler within seconds of completion
  regardless of whether the canvas is visible.

Each phase ships independently. Phases 2–4 are not blockers for
the first user-visible feature in Phase 1.

---

## 10. Test plan

### Unit (HypeCoreTests)
- `MeshyAIClientTests` — request encoding for every endpoint
  (text-to-3D preview/refine, image-to-3D, multi-image-to-3D,
  rigging, animations, balance), response decoding for success +
  every error shape, retry behavior on 429, 5xx, and SSE
  reconnect.
- `MeshyTaskMonitorTests` — state machine: pending → in-progress
  → succeeded; cancel from each state; timeout after 10 min;
  polling fallback when SSE returns 404.
- `Meshy3DAssetImporterTests` — task result → `SpriteAsset` with
  the right kind, mimeType, provenance, data bytes; rollback path
  deletes the asset.
- `KeychainStoreTests` — extended with `meshyAPIKeyAccount` set /
  get / delete.
- `HypeToolsTests` — three new tool schemas validate; tool-arg
  repair handles missing fields gracefully.
- `HypeToolExecutorTests` — dispatching each tool with a mocked
  `MeshyAIClient` writes the right asset.

### Integration (HypeTests)
- `Generate3DSheetTests` — input validation, balance gating, the
  "insufficient credit" disabled state, cancel-mid-generation.
- `PreferencesView+MeshyTests` — key save/replace/test-connection
  + balance refresh paths.
- `SceneInspectorScene3DRepositoryPopupTests` — picking an asset
  from the popup sets `scene3DAssetRef` and the rendered SceneKit
  view updates.

### Live smoke (manual, opt-in via `MESHY_API_KEY` env var)
- Generate a text-to-3D, watch progress reach 100%, confirm
  the GLB renders correctly in the scene3D part.
- Image-to-3D from a transparent-background PNG in the repository.
- Cancel a generation in progress, confirm credits not charged
  (per Meshy docs, canceled tasks don't consume).
- Use the AI chat panel to drive a generation through
  `generate_3d_model_from_text` — confirm the preview/apply/
  rollback path works as it does for OpenAI image generation.

---

## 11. Decisions (resolved with user — 2026-05-11)

The plan previously left these for user resolution. They are now
locked in. Subsequent sections override earlier recommendations
where they conflict.

1. **Embed GLB/USDZ/FBX bytes in `.hype`.** Stacks remain
   all-encompassing and self-sufficient. Audio precedent applies:
   model bytes live in `SpriteRepository` keyed by content hash.

2. **Per-stack model cache only.** No global
   `~/Library/Application Support/Hype/MeshyCache`. Reinforces (1)
   — every stack is portable as a single document.

3. **`should_remesh` defaults match Meshy's per-`ai_model`
   default.** Meshy 6 defaults `false`; earlier models default
   `true`. `Meshy3DGenerateSheet` initializes the toggle from the
   selected model's default but lets the user override.

4. **Animations are user-chosen on demand, not bulk-imported.**
   Phase 3 ships an in-app animation picker (browse, search, pick
   one or more, apply); no implicit catalog fetch on app launch.
   The picker calls a Meshy endpoint at the moment of browsing —
   we cache responses for the session but don't pre-populate.

5. **`stack.meshyEnabled` per-stack flag, separate from
   `aiContextCloudSharingAllowed`.** Lives in the
   `StackPreferences` block, surfaces in the Preferences pane and
   the Generate 3D sheet's first-run gate.

6. **FBX is in for Phase 1.** Hype's `scene3D` part needs FBX
   loadable as a runtime asset. Decision below; investigation
   results in `13.A FBX support strategy`.

7. **AR Quick Look "Open in AR" action on `model3D` assets:
   yes.** Adds a contextual-menu / inspector button on any
   `model3D` asset; uses macOS Quick Look for USDZ, and falls back
   to converting GLB → USDZ on demand if the source isn't USDZ.
   Implemented in Phase 4.

### 11.A FBX support strategy (resolves #6)

`scene3D` today loads what `SceneKit` natively accepts: DAE,
USDZ, OBJ (via SCNScene/MDLAsset). GLB is loaded via a one-shot
MDLAsset round-trip. FBX is **not** in SceneKit's native list.

Three implementation options were considered:

- **(a) Assimp framework dependency** — adds a 6+ MB shared lib
  and another build-system seam. Rejected: too much weight for
  one optional format.
- **(b) Server-side conversion** — Meshy returns GLB and FBX
  natively, so we don't need to *convert* FBX, we just need to
  *load* it. Doesn't apply if the user drops a third-party FBX
  in the repository.
- **(c) Embed `MDLAsset` FBX path + USDZ-conversion fallback** —
  Apple's `MDLAsset` initializer supports FBX through ModelIO on
  macOS 13+ when the file extension is `.fbx`. We add a
  `Scene3DAssetLoader` that maps file extensions to loaders and
  falls back to a one-shot ModelIO → SCNScene roundtrip.
  **Chosen.**

For Phase 1, FBX support means:
- `SpriteRepository.AssetKind.model3D` accepts FBX file extension
  and content type.
- `scene3D` part loads FBX through `Scene3DAssetLoader.load(_:)`
  (new file) which centralises the format → SCN-graph mapping.
- The Meshy generation flow continues to prefer GLB (smaller,
  textured, ubiquitous); users can opt-in to FBX in the Generate
  3D sheet under "Format" if Meshy returns it.

---

## 12. Out of scope (explicitly)

- Multi-color print, analyze-printability, repair-printability
  endpoints. Hype is an authoring tool for interactive content,
  not a 3D-print preprocessor.
- The text-to-image / image-to-image Meshy endpoints — we
  already have `OpenAIImageGenerationClient` covering that use
  case, and the parity harness will keep them aligned.
- Per-stack Meshy API keys. The key is per-user (machine-local
  Keychain), not per-document.
- Real-time mesh streaming. We always download the final GLB; we
  don't try to preview intermediate vertex data.

---

## 13. Summary

Meshy.ai slots cleanly into Hype's existing seams:
`SpriteRepository` already stores arbitrary bytes; `scene3D`
already loads GLB / USDZ / OBJ; `KeychainStore` already keeps API
keys; `AIEditTransaction` already gates preview-then-apply; the
AI tool surface already has a `generate_image` precedent. The
delivery is four phases, each independently shippable, with the
visible win — Generate-3D-from-text inside the Sprite Repository
— landing in Phase 1.

The biggest implementation risk is the long-running async lifecycle
on flaky networks. `MeshyTaskMonitor` is designed to handle that
explicitly (SSE first, poll fallback, hard timeout, cancel
propagation) and is the single chokepoint we test exhaustively
before unblocking the UI layer.

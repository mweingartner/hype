# Code Review and Gaps Plan

> Snapshot: 2026-05-13
> Scope: full audit of the Hype codebase (~81k LOC Swift across `HypeCore` and
> `Hype`) plus the three design documents at `docs/MeshyAIIntegrationPlan.md`,
> `docs/HypeFeatureGapImplementationPlan.md`, and `docs/AppleFrameworksRoadmap.md`.
> Audits cross-checked against the latest pushed commit (`d4cb9c5`).
>
> **Outcome of the audit:** the codebase is in good architectural shape. No
> critical vulnerabilities, no behavioral drift between docs and code, no dead
> features. The actionable gaps are concentrated in **(1) staleness in two
> design docs**, **(2) test coverage for AR Quick Look + several AI-tool error
> branches**, and **(3) one monolithic file** that's a maintenance risk rather
> than a bug.
>
> Below is a phased remediation plan, ranked by severity and ordered for
> efficient execution.

---

## 0. TL;DR — what to do, in what order

| # | Phase | Effort | Risk if skipped | Notes |
|---|-------|--------|-----------------|-------|
| 1 | **Doc staleness pass** | ~1 hr | Misleads new contributors / future-self | One-shot edit |
| 2 | **AR Quick Look test suite** | ~3 hr | Crashy on macOS 12; file I/O perms blind spot | Highest-risk untested surface |
| 3 | **AI tool error-branch tests** | ~4 hr | Production AI tool surface fails opaquely | Sampled ~10 high-traffic branches |
| 4 | **Coordinator UI lifecycle tests** | ~3 hr | Sheet-dismiss races; orphan Tasks | Rig/Animate, Remesh/Retexture, Generate3D |
| 5 | **HypeToolExecutor split** | ~6 hr | Maintenance / merge-conflict risk only | No bug fix; pure refactor |
| 6 | **Test-isolation hardening** | ~3 hr | Flaky parallel test runs; real Keychain pollution | Mock FileManager + KeychainStore + URLSession |
| 7 | **Polish: line-number drift, logging gaps, NonisolateCache wrapper** | ~2 hr | Cosmetic / observability | Batch cleanup |

**Total estimated effort to close everything: ~22 hours of focused work.**
Phases can run in any order after Phase 1; Phases 2–6 are independent.

---

## 1. Doc staleness pass — Phase 1 (1 hour)

### Findings (from `docs-audit`)

The three planning docs in `docs/` predate the Meshy implementation. The audit
extracted 44 promised features; 8 are recorded as "shipped" in the docs, 24 as
"future/deferred," and 7 as open questions. **Many of the "future" items have
actually shipped** in commits `d50dd58` through `d4cb9c5` but the docs still
read as forward-looking.

### Concrete fixes

1. **`docs/MeshyAIIntegrationPlan.md`** — add a status header at the top:
   ```markdown
   > **STATUS (2026-05-13):** Phases 1–5 shipped. See commits d50dd58
   > (Phase 1 — text-to-3D), 9f38778 (Phase 2 — image-to-3D + AI tools),
   > 7ec9c75 (Phase 3 — rigging + animation + HypeTalk), 7ed3347 (Phase 4
   > — remesh + retexture + AR Quick Look + webhook decoder), 11f1040
   > (Phase 5 — HypeTalk model binding + Sprite Repo AI), and d4cb9c5
   > (scene3D resolvers + bind_3d_model_to_scene3d AI tool). The document
   > below is preserved as the historical design narrative.
   ```
   Then add a one-line annotation to each §11 decision noting how it was
   ultimately resolved in code (e.g., "§11.6 FBX → resolved per §11.A;
   MDLAsset path shipped in Phase 1").

2. **`docs/HypeFeatureGapImplementationPlan.md`** — audit each phase and
   update the status. AIEditTransactionRunner, AIProviderParityHarness,
   SyncService (local engine), CardSKScene migration, transactional AI
   in the main chat are all shipped. Add a "STATUS" line per phase header.

3. **`docs/AppleFrameworksRoadmap.md`** — verify each numbered item:
   - Phase 1 §1–3 (Calendar, PDF Viewer, Map): shipped — confirm with
     `grep -n "calendar\|pdf\|map" Sources/HypeCore/Models/Part.swift`.
   - Phase 2 §5–8 (Scene3D, Audio Recorder, Color Well, Stepper/Slider/Toggle/
     SegmentedControl): shipped.
   - Phase 3 §11 (CoreImage filters): shipped.
   - Items still genuinely future: ContactsUI, EventKit, WebAuthenticationServices,
     UserNotifications, AVKit PiP, CoreLocation map overlay.

4. **`architecture.md`** — two small drift fixes from the `arch-audit`:
   - §3 SpriteKit substrate cites `PassthroughSKView` at
     `CardCanvasView.swift:360` — actual line is **963**. Update.
   - §3.4 says `SceneBridge` is "~742 LoC"; actual is **923**. Update or
     change to "~900 LoC" with a leading "~" so it weathers small growth.

### Owner / sequencing
Single editor pass. Can be done before or after the test work; doesn't block
anything.

---

## 2. AR Quick Look test suite — Phase 2 (3 hours)

### Findings (from `test-audit`)

`Sources/Hype/AR/ARQuickLookPresenter.swift` (272 lines) has **zero tests**.
This is the highest-risk untested surface in the project because it:

- Conditionally gates on `#available(macOS 13, *)` — older OS path is
  completely unexercised.
- Creates a real directory at `~/Library/Caches/com.hype.app/ar-quicklook`
  with `0o700` POSIX permissions (security-relevant; addendum C10).
- Converts GLB → USDZ via `MDLAsset` (separate Phase-4 invariant C12).
- Evicts cache entries on a 30-day / 200 MB policy that has no regression
  test, so a bug here could fill disk silently.
- Singleton state could race if `present()` is called concurrently.

### Concrete tests to add

Create `Tests/HypeTests/ARQuickLookPresenterTests.swift` with:

1. `present` on a `.imageTexture` asset throws `.unsupportedAssetKind`.
2. `present` on a `.model3D` USDZ asset writes the bytes to a temp file
   with `0o700` permissions and returns its URL (or hands off to
   `QLPreviewPanel`; if not testable headlessly, isolate the staging
   helper into a private static function that IS testable).
3. `present` on a `.model3D` GLB asset triggers `Scene3DAssetConverter`
   and stages the resulting USDZ. Mock the converter to return canned
   USDZ bytes; verify the file is written, not the input GLB.
4. `present` on a `.model3D` FBX asset triggers conversion (FBX-via-
   MDLAsset, macOS 13+).
5. On macOS 12 (mock via injectable `osVersion: OperatingSystemVersion`),
   any `.model3D` `present` throws `.unsupportedOS`.
6. Cache eviction: pre-populate the cache directory with 5 fake USDZ
   files dated 31 days ago; call `evictOldStagedFiles()`; assert the
   directory is empty afterward. Same for the 200 MB size cap with 3
   large fake files.
7. Conversion failure: stub `Scene3DAssetConverter.convertToUSDZ` to
   throw; assert `present` re-throws `.conversionFailed` with a clean
   error description (no raw exception leak).

### Refactor note
The presenter is currently a singleton with hardcoded `FileManager.default`.
Add an `init(fileManager: FileManager = .default, converter:
Scene3DAssetConverting = Scene3DAssetConverter())` for dependency injection
so the tests above are actually possible. This is ~10 minutes of mechanical
refactor.

### Risk if skipped
Medium-high. The bundle is shipping, real-user macOS 12 sessions silently fail
"Open in AR," and the 200 MB cap could leak slowly.

---

## 3. AI tool error-branch tests — Phase 3 (4 hours)

### Findings (from `test-audit`)

`HypeToolExecutor` has ~130 tool case branches and ~71 are not exercised by
explicit tests. The ones with the highest risk are the new Meshy 3D tools
because they expose network and credit-spending failure modes to the AI.

### Priority order (Critical → Medium)

**Critical:**
1. `generate_3d_model_from_images` (lines 6091–6219):
   - 0 images → validation error
   - 1 image → validation error
   - exactly 2 images → success
   - exactly 4 images → success
   - 5 images → validation error
   - One image fails resolve, others succeed → partial-success behavior
     (whatever it is — currently undocumented; pick: fail-fast OR
     continue-with-warning)

2. `remesh_3d_model` + `retexture_3d_model` (lines 6220+):
   - Source asset has no `attribution.taskId` (cannot rig non-Meshy
     assets) → clean error message
   - Polycount below/above documented range (100…300,000) → validation
     error
   - Stub `MeshyClient` returns `.taskFailed` mid-poll → error surfaces
     to AI without leaking internals
   - Stub returns `.timedOut` → AI sees the 5-min cap message

**High:**
3. `create_image` (lines 3875–3906):
   - Fetch returns 404 → clean error
   - Fetch returns oversized payload (>50 MB) → cap fires
   - Corrupted base64 input → validation error
   - MIME mismatch (file claims PNG but is GIF) → validation error

4. `MeshyWebhookPayload` parser (lines 92–119):
   - `taskError.error` set but no `message` → fallback to `error` field
   - Three competing GLB sources (`model_urls.glb`, `rigged_character_glb_url`,
     `result.animation_glb_url`) → priority order test
   - Oversized error message (>200 chars) → truncation actually fires
   - Already covered: CSV injection (Phase 4 F1), attacker URL sanitization
     (C4) — leave as-is

**Medium:**
5. `Generate3DJob.validate` boundary cases:
   - `targetPolycount` exactly 100 and exactly 300,000 → both valid
   - `topology` and `symmetryMode` with mixed case → lowercased validation

### Test substrate
A `StubMeshyClient` already exists in `Tests/HypeCoreTests/`. Reuse it. The
new tests are mostly "construct stub with scripted response, drive tool case,
assert result string." No new infrastructure needed.

### Risk if skipped
Medium-high. The AI surface is the most user-facing, most-spending-money
path, and the error messages it returns to the AI become parts of the
LLM's reasoning. Bad error strings → confused LLM → bad retries → wasted
credits.

---

## 4. Coordinator UI lifecycle tests — Phase 4 (3 hours)

### Findings (from `test-audit`)

Three sheet coordinators have NO state-machine tests:

- `RigAndAnimateCoordinator.swift` (481 lines) — preflight → rigging → picking
  → animating → done phases
- `RemeshAndRetextureCoordinator.swift` (442 lines) — preflight → working
  → done
- `Generate3DSheet.swift` (856 lines) — form → submitting → progress →
  importing → done, plus three tab states

Flow-layer tests exist (`RigAndAnimateFlowTests`, `Generate3DJobTests`) but
they exercise the **data logic**, not the **sheet UI lifecycle**. The
sheet's responsibilities — Task cancellation on dismiss, error display,
phase transitions, tab switching mid-generation — are unexercised.

### Concrete tests to add

Create `Tests/HypeTests/RigAndAnimateCoordinatorLifecycleTests.swift`,
`Tests/HypeTests/RemeshAndRetextureCoordinatorLifecycleTests.swift`, and
`Tests/HypeTests/Generate3DSheetLifecycleTests.swift`. Each covers:

1. **Cancel during in-flight phase** cancels the underlying `flowTask`
   AND the underlying `MeshyTaskMonitor`. (Security addendum C19-equivalent;
   without this, a dismiss leaks a polling Task that keeps spending credits.)

2. **Early dismiss via window close** — same as cancel; verify cleanup
   runs in `.onDisappear` whether or not the explicit Cancel button was
   used.

3. **Phase transitions in order** — feed the underlying Flow scripted
   states and assert the sheet renders the matching view.

4. **Error phase displays sanitized message** — assert error text does
   NOT contain API keys, file paths, or raw response bodies (extends
   the Phase 1 H1 + Phase 2 H1 invariants to the UI layer).

5. **Generate3DSheet specifically:**
   - Tab switch mid-generation cancels the in-flight Task (this is
     non-obvious; tests catch the race).
   - Multi-image tab requires 2–4 filled slots; clicking Generate with
     1 or 0 doesn't submit.
   - Asset name conflict (repo already has same name) → Generate3DJob
     dedup runs; sheet's success state displays the dedup'd name.

### Refactor note
Several `@State` private fields in these coordinators need to be
test-visible. Add `#if DEBUG`-gated test hooks, or use the existing
`_testHooks` pattern from `Generate3DSheetTests.swift` (search for
`_testHooks` in the test suite — it's already established).

### Risk if skipped
Medium. Each coordinator currently relies on user testing for cancellation
correctness. A user closing the sheet mid-rigging leaves a Task polling
Meshy for up to 30 minutes, consuming credits.

---

## 5. HypeToolExecutor split — Phase 5 (6 hours)

### Findings (from `quality-audit`)

`Sources/HypeCore/AI/HypeToolExecutor.swift` is **6,497 lines** with 15+
MARK sections covering web assets, scene setters, 3D generation, image
generation, asset I/O, file I/O, and dozens of helpers. The file compiles,
all tests pass, and there's no bug — but it's a maintenance hazard:

- Adding new tools requires scrolling thousands of lines.
- Merge conflicts in this file are guaranteed on parallel branches.
- New contributors can't form a mental model from one file.

### Proposed split

Keep `HypeToolExecutor` as the dispatcher (the public `execute(...)`
function with the giant `switch` over tool name). Extract these
helper struct-with-static-functions modules:

| New file | Lines roughly covered | Tool cases moved |
|----------|----------------------|------------------|
| `Sources/HypeCore/AI/Executors/WebAssetExecutorBranches.swift` | ~2878–3026 | `search_web_for_sprite`, `import_web_asset` |
| `Sources/HypeCore/AI/Executors/SceneNodeExecutorBranches.swift` | ~3551–4170 | `set_node_property`, `set_physics_body`, etc. |
| `Sources/HypeCore/AI/Executors/Scene3DExecutorBranches.swift` | ~5086–6470 | `generate_3d_model_from_*`, `remesh_3d_model`, `retexture_3d_model`, `bind_3d_model_to_scene3d`, `list_3d_models` |
| `Sources/HypeCore/AI/Executors/FileIOExecutorBranches.swift` | (existing scattered) | `read_file`, `write_file`, `list_directory`, `fetch_url` |
| Stays in `HypeToolExecutor.swift` | dispatcher + small/medium-traffic cases | All other tools |

Each branch module is a `package` `enum` with `static` functions taking
`(arguments: [String: String], document: inout HypeDocument, currentCardId: UUID,
context: HypeToolExecutor.Context) async -> String`. The dispatcher just
calls them.

### Process
- Do this AFTER Phase 3 (AI tool error-branch tests). Tests written in
  Phase 3 will catch any regression introduced by the refactor.
- Run `swift test` after EACH branch extraction; the 1943-test suite
  is the regression net.
- No public API change. Tool names and arguments are unchanged.

### Risk if skipped
Low-Medium. No user-visible defect. Pure maintainability win. Defer if
schedule pressure exists; tackle when the file gets to ~8,000 lines.

---

## 6. Test isolation hardening — Phase 6 (3 hours)

### Findings (from `test-audit`)

Several tests hit real OS resources:

- **Keychain**: `KeychainStoreTests`, plus indirectly via `Meshy3DGateTests`,
  the coordinator `.onAppear` paths, etc.
- **Filesystem**: `read_file` / `write_file` / `list_directory` tool tests;
  `ARQuickLookPresenter` (if Phase 2 adds tests for it).
- **Network**: `fetch_url` tool tests use real URLs (slow, flaky, can be
  rate-limited).

This causes:
- Slow test runs (timeouts add ~30s when offline).
- Parallel test races on `/tmp` or `~/Library/Caches`.
- Real Keychain entries left around if a test fails mid-run.

### Concrete fixes

1. **Keychain abstraction** — introduce a `protocol KeychainProviding` with
   `setSecret`, `getSecret`, `hasSecret`, `deleteSecret`. Make
   `KeychainStore` conform. Inject into coordinators and clients
   (default: `KeychainStore.default`). Tests use an in-memory stub.

2. **FileManager abstraction** — `protocol FileSystemProviding` for the
   read/write/list/exists/createDirectory surface. `FileManager.default`
   conforms via extension. Tests use an in-memory FS or a per-test temp
   directory under `URL.temporaryDirectory.appendingPathComponent(testName)`.

3. **URLSession abstraction** — already exists for `MeshyAIClient` (mock
   URLProtocol pattern). Extend to `fetch_url` and any other tool that
   hits the network.

4. **`nonisolated(unsafe)` in tests** — the test-audit flagged
   `Generate3DJobTests` line 245 using `nonisolated(unsafe)` to capture
   progress. Replace with `AsyncStream` or a `MainActor`-isolated wrapper.

### Risk if skipped
Low-Medium. Tests work today on a clean machine. They become flaky in CI
and on developer machines that have keychain conflicts.

---

## 7. Polish — Phase 7 (2 hours)

Misc cleanups from the audits:

1. **Web asset search success logging** — `WebAssetSearchClient` logs on
   error but not on success. Add an `aiOutput` log line: `"search query
   "<q>" returned N candidates from <provider>"`.

2. **NonisolateMutableCache wrapper** — `ImageFilter.swift` and a few
   other places use `nonisolated(unsafe) static var cache` with paired
   `NSLock`. Extract a generic `package final class
   NonisolateMutableCache<K: Hashable, V>` with `withLock { ... }` that
   makes the pattern foolproof.

3. **Architecture.md line citations** — already covered in Phase 1.

4. **NSCoder stub repetition** — 15+ `init(coder:) fatalError("not used")`
   stubs across SpriteKit nodes and host views. Acceptable AppKit pattern,
   but a documented `// Required by NSView superclass; never invoked
   because views are created in code, not storyboards.` block once at the
   top of the SpriteKit folder's README (or as a single shared comment)
   would help new contributors.

5. **Mid-file MARK reorganization in HypeToolExecutor** — if Phase 5
   (split) is deferred, at least reorganize the top-of-file MARK index
   so navigation is faster (Xcode minimap).

---

## What we are NOT going to do

Documented so the next code-review pass doesn't re-raise these:

1. **Multiple error enums for AI providers (AIError, OpenAIClientError,
   OllamaError, MeshyError, WebAssetSearchError).** They mirror distinct
   external APIs. Unifying them would create a leaky abstraction. Keep
   them.

2. **`HypeToolExecutor.swift` is 6,500 lines.** Pure cosmetic if Phase 5
   is deferred. No bug; no security risk.

3. **`Parser.swift` 70-case switch.** Recursive descent parsers are this
   way for a reason. No refactor.

4. **`@unchecked Sendable` annotations.** All ~20 instances have paired
   locking and a justifying comment. No action.

5. **NSCoder stubs `fatalError("not used")`.** Standard AppKit pattern.
   No action beyond Phase 7 #4.

6. **Soft-deprecated decode aliases** (`style="switch"` → `toggle`,
   `style="opaque"` → `rectangle`, etc.). Backward-compat code; correct
   to keep.

7. **`Stack.runtimeModeEnabled`-style flags growing.** They're additive,
   backward-compat decoded, and reflect real design intent. Keep adding
   them on demand.

---

## Execution timeline (suggested)

A focused engineer can complete this in **one week** of work:

| Day | Phases | Output |
|-----|--------|--------|
| Mon AM | Phase 1 | Doc staleness pass committed |
| Mon PM | Phase 2 (1/2) | ARQuickLookPresenter test suite drafted |
| Tue | Phase 2 (2/2) + Phase 3 (1/3) | AR tests green; Meshy 3D error-branch tests started |
| Wed | Phase 3 (2/3) | All AI tool error tests green |
| Thu | Phase 3 (3/3) + Phase 4 (1/2) | Coordinator lifecycle tests started |
| Fri AM | Phase 4 (2/2) | Coordinator tests green |
| Fri PM | Phase 6 + Phase 7 | Abstractions in place; polish committed |

Phase 5 (HypeToolExecutor split) is parked unless schedule allows; it's
the largest single unit of work and has no bug-fixing component.

---

## Closing assessment

The codebase is healthier than the audit's number-of-findings suggests.
Out of 44 promised features, only doc staleness blocks a "shipped"
verdict on the ones already in code. Architecture documentation is
accurate. There are no critical security gaps, no behavioral drift,
no dead features. The remediation work above is **risk reduction and
maintainability**, not crisis management.

The single highest-impact item is **adding tests to
`ARQuickLookPresenter`** — it's the largest untested surface, gates on
a macOS version we can't easily integration-test against, and touches
real filesystem permissions. Everything else is straightforward
incremental improvement.

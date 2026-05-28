# Hype Feature Gap Implementation Plan

> **STATUS (2026-05-13): All 7 phases SHIPPED.** This plan was executed in
> commit `07475ca` ("execute the 7-phase HypeFeatureGapImplementationPlan").
> AIEditTransactionRunner, AIProviderParityHarness, SyncService (local
> engine), CardSKScene SpriteKit migration of every classic part type,
> per-card paint snapshots, transactional AI in the main chat — all in the
> shipping build. The document below is preserved as the historical
> delivery contract.

This plan is the staged delivery path for closing the current high-risk feature
gaps without destabilizing the stack model, HypeTalk runtime, AI authoring, or
renderer. Every workstream uses the same control gates:

1. Architect plan: define model contracts, migration strategy, API boundaries,
   UI touchpoints, and acceptance tests before code changes.
2. Security review of plan: check file access, network boundaries, prompt/tool
   boundaries, undo/rollback behavior, persistence privacy, and denial-of-service
   limits.
3. Build: land the smallest shippable slice behind the documented model/API.
4. Security review of build: inspect implementation for unsafe paths, stale
   permissions, unbounded input, data loss risks, and tool/provider leakage.
5. Outcome tests: run focused unit tests, integration tests, and live app smoke
   tests against a real stack where UI behavior matters.

## Phase 1: Durable Foundations

Scope:

- Persist per-card paint snapshots in `HypeDocument`.
- Export paint layers in HTML as embedded PNG assets.
- Remove the legacy parameter-access stubs for `the paramCount`, `the params`,
  and `param N`.
- Record this plan as the canonical staged roadmap.

Security review:

- Paint snapshots are document-contained RGBA data; no arbitrary filesystem path
  is introduced.
- HTML export embeds generated PNG data URLs only from document data.
- Handler parameter access exposes only current in-process dispatch values.

Acceptance:

- A painted card saves, reloads, and still renders its paint layer.
- HTML export includes visible paint content.
- `param 1`, `param(1)`, `the paramCount`, and `the params` return real handler
  parameters.

## Phase 2: Formal AI Transactions

Implementation status:

- `AIEditTransactionRunner` now previews tool calls against a draft document,
  computes deltas, and supports explicit apply/rollback.
- Main AI chat tool turns use the transaction path and expose a rollback control
  for the last applied AI edit.
- Focused tests cover preview isolation, apply/rollback state transitions, and
  merged multi-tool deltas.

Architecture:

- Introduce `AIEditTransaction` with transaction id, initiating prompt, provider,
  ordered tool calls, preflight diagnostics, document diff, changed object ids,
  created asset ids, rollback snapshot, and user-visible summary.
- Make `HypeToolExecutor` produce `AIEditOperation` values first, then apply them
  through a single transaction runner.
- Add preview/apply/cancel UI in the main AI panel, Script Editor AI panel, and
  Sprite Library AI panel.
- Attach each transaction to the undo stack as one unit.

Security review:

- Tool calls must not mutate the live document during preview.
- Asset writes must be scoped to the current document/package or approved import
  locations.
- Prompt context must not include API keys or unrestricted file contents.
- Rollback must remove created assets and restore modified object properties.

Acceptance:

- Multi-tool edits preview changed cards/backgrounds/parts/scripts/assets before
  apply.
- Cancel leaves the document bit-for-bit unchanged.
- Apply creates exactly one undo step.
- A failed tool call rolls back all prior operations in the same transaction.

## Phase 3: Provider Parity Regression Harness

Implementation status:

- `AIProviderParityHarness` now exercises provider-independent text tool-call,
  image generation, and speech-output contracts without requiring live
  credentials.
- Focused tests cover matching Ollama/OpenAI-style tool calls, missing required
  tools, generated-image metadata, and speech-output invocation.

Architecture:

- Define provider-independent contracts for chat, tool calling, image generation,
  speech-to-text, text-to-speech, cancellation, streaming, and error surfaces.
- Build a local regression harness with provider fixtures for OpenAI, Ollama, and
  local-model dispatch where network/API availability is optional.
- Add live opt-in tests guarded by environment variables for real provider calls.
- Store provider transcripts in debug logs with secrets redacted.

Security review:

- API keys remain in preferences/keychain paths and never enter transcripts.
- Live tests are opt-in and budget-limited.
- Speech and image payloads are retained only when explicitly requested for test
  artifacts.

Acceptance:

- Same prompt/tool scenario passes through OpenAI and Ollama adapters.
- Cancellation stops in-flight model work and leaves UI state recoverable.
- Image creation can target card/background insertion and asset repository
  insertion with required sprite naming.
- Speech query auto-submit and spoken AI responses work through the selected
  provider path.

## Phase 4: Live Sync

Implementation status:

- `SyncService` now provides a transport-neutral local collaboration engine with
  peer sessions, operation/change-set publishing, checkpoints, and deterministic
  conflict reporting.
- Focused tests cover independent peer convergence and stale same-entity edit
  conflict detection.

Architecture:

- Replace placeholder `SyncService` with a transport-neutral sync engine:
  `SyncSession`, `SyncPeer`, `SyncOperation`, `SyncChangeSet`, `SyncConflict`,
  and `SyncCheckpoint`.
- Start with local loopback and file-backed sync tests, then add the chosen
  transport: CloudKit for Apple ecosystem sync, Multipeer for local sessions, or
  a custom server for cross-platform collaboration.
- Make document edits operation-based rather than whole-document pushes.
- Add conflict policy for stack/card/background/part/script/asset changes.

Security review:

- Authentication and authorization belong at the transport boundary.
- Sync payloads must be schema-validated before applying.
- Remote script changes must enter the same transaction/preview path when the
  local user has not opted into automatic collaboration apply.
- Large asset sync must be chunked and bounded.

Acceptance:

- Two app instances converge after independent edits.
- Conflicting property/script edits surface a deterministic conflict result.
- Undo of local sync-applied work behaves predictably.
- Offline edits replay after reconnect without document corruption.

## Phase 5: Full SpriteKit-Native Cards

Implementation status:

- `CardSKScene` now reconciles native card nodes for shapes, images, buttons,
  fields, sprite areas, and paint layers.
- Card transitions exclude native-renderable parts from fallback snapshots and
  update the SpriteKit scene content before presentation.
- Focused tests cover native-renderable id selection and node reconciliation.

Architecture:

- Move card rendering from Core Graphics plus AppKit overlays toward
  `CardSKScene.nativeLayer` for native SpriteKit card parts.
- Implement SpriteKit nodes for buttons, fields, shapes, images, text, and paint
  layers while preserving AppKit overlays only for controls that require native
  editors or platform services.
- Keep hit-testing, selection, grouping, resize handles, transitions, and script
  dispatch behavior identical during migration.
- Use per-part feature flags so each part type can migrate independently.

Security review:

- Ensure script-driven node changes cannot escape document-owned state.
- Keep web/PDF/map/media views sandboxed as overlays until native equivalents are
  safe and complete.
- Validate generated scene content before loading into SpriteKit nodes.

Acceptance:

- Every migrated part type renders identically in browse and edit mode.
- Text static/edit rendering preserves alignment and theme behavior.
- Card transitions operate on the full card scene rather than a mixed snapshot.
- Existing stacks load with no visual or scripting regression.

## Phase 6: Legacy HypeTalk Compatibility Expansion

Architecture:

- Maintain a compatibility matrix from `HyperTalk_Reference.md` to parser,
  interpreter, UI/runtime support, and AI guide status.
- Implement high-value classics in priority order: selection/found text surfaces,
  `do` evaluation where safe, printing/export routing, menu dispatch, card
  history stack, and remaining classic system properties.
- Prefer real behavior or explicit errors over silent no-ops.

Security review:

- `do`/`run` must be sandboxed to HypeTalk only; no shell execution.
- Printing/export commands require normal user-facing file/privacy controls.
- Selection APIs must not expose hidden text from locked/private parts unless
  normal scripting access already permits it.

Acceptance:

- The compatibility matrix has automated tests for every implemented classic.
- Unsupported classics produce documented, non-destructive behavior.
- AI guidance is updated whenever a stub becomes real behavior.

## Phase 7: Paint Import/Export Completion

Architecture:

- Extend the Phase 1 persistence work with explicit import/export commands and
  UI: export paint layer as PNG, import image as paint layer, clear paint layer,
  duplicate paint layer to another card, and optionally convert paint to image
  part.
- Add HypeTalk commands/properties for paint-layer metadata and export.

Security review:

- File export/import uses user-selected URLs only.
- Imported images are decoded with size limits and converted to bounded RGBA.

Acceptance:

- Paint can round-trip through `.hype`, HTML export, direct PNG export, and PNG
  import without coordinate flips or alpha loss.

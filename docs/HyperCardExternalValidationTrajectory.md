# HyperCard External Validation Trajectory

This document defines the tracking system and validation loop for ported
HyperCard XCMD/XFCN emulators. It complements `docs/HyperCardExternalMapping.md`
by describing how each emulator becomes independently testable, how evidence is
captured, and what gate must pass before we treat the behavior as understood.

## Scope

The trajectory applies to Swift emulators registered in
`HyperCardExternalRegistry`. It does not execute original 68K/PPC resources.
The goal is to validate function contracts with explicit inputs and outputs
without requiring a full imported stack, then connect those isolated contracts to
runtime and visible evidence where needed.

## Validation Loop

Every external moves through the same loop:

| Step | Requirement | Artifact | Gate |
| ---: | --- | --- | --- |
| 1 | Inventory | Name, kind, aliases, resource id, call count, source stacks, disassembly path. | External appears in `docs/HyperCardExternalMapping.md` and generated Myst inventory when applicable. |
| 2 | Contract | Define accepted arguments, normalized inputs, return value, `the result`, runtime globals, document mutations, visual effect metadata, diagnostics, and intentional deviations. | Contract row exists in `docs/HyperCardExternalMapping.md`. |
| 3 | Isolated invocation | Call the emulator directly through `HyperCardExternalRegistry.invokeIsolated(...)` with explicit arguments and optional synthetic document/assets. | Focused unit test asserts `HyperCardExternalResult` fields directly. |
| 4 | Fixture matrix | Add representative cases for normal input, missing input, malformed input, missing resources, aliases/casing, and stateful follow-up calls. | Unit tests assert content, not just existence. |
| 5 | Runtime integration | Exercise parser/dispatcher path only after isolated behavior is proven. | Existing script/runtime tests still pass and match isolated expectations. |
| 6 | Evidence capture | For visual/media externals, capture operation traces, resolved assets, before/after snapshots, and comparison references. | Evidence artifacts exist and are referenced from the function tracking row. |
| 7 | Promotion gate | Mark the function validation status. | Status is one of `isolated`, `runtimeIntegrated`, `visualEvidenceCaptured`, or `blocked:<reason>`. |

## Artifact System

Use these artifact layers rather than mixing all evidence into one report:

| Layer | Location | Contents |
| --- | --- | --- |
| Canonical contract | `docs/HyperCardExternalMapping.md` | Human-readable support status and behavior contract. |
| Isolated tests | `Tests/HypeCoreTests/HyperCardExternalIsolationTests.swift` | Direct emulator calls that do not parse scripts or load imported stacks. |
| Runtime tests | Existing `ScriptTests.swift`, `HyperCardImportTests.swift`, and focused runtime suites | Parser/dispatcher/import integration checks. |
| Generated Myst inventory | `/Users/jrepp/d/myst-export/docs/external-emulation-plan.md` | Resource/call-count tracking across exported Myst stacks. |
| Disassembly evidence | `/Users/jrepp/d/myst-export/docs/external-disassembly-audit.md` and recipe docs | Reverse-engineering evidence for contracts and rendering plans. |
| Visible evidence | `docs/MystVisibleEvidencePlan.md` plus generated probe artifacts | Operation traces, screenshots/bitmaps, resolved asset links, comparison results. |

## Per-Function Tracking Matrix

Initial status below reflects the current consolidation point. `Isolated gate`
means a direct `invokeIsolated` test should exist or be added before relying on
the emulator for deeper Myst visual claims.

| External | Kind | Primary output class | Isolated gate | Runtime gate | Visible/evidence gate |
| --- | --- | --- | --- | --- | --- |
| `Picture` | XCMD | image window/document mutation | covered by isolated tests for resolved, missing, and empty-name assets | existing runtime coverage | needed for exact scroll/crop/window placement screenshots |
| `Movie` | XCMD | video part/window state | covered by isolated test for resolved and missing assets | existing runtime coverage | needed for first-frame/bounds/lifecycle screenshots |
| `playQT` | XCMD | video/audio playback part | covered by isolated tests for looped video, audio-only hidden playback, and missing assets | existing runtime coverage | needed for hidden-vs-visible media proof screenshots/traces |
| `xCIcon3` | XCMD | icon overlay/document mutation | covered by isolated tests for centered overlay, missing icon, uppercase `ICON` resources, and malformed locations | existing runtime coverage | needed for placement/reuse/removal screenshots |
| `xMemory` | XCMD/XFCN | value/runtime globals | covered by isolated test | existing runtime coverage | not visual; trace only when branch-gating |
| `xSetSoundVol` | XCMD/XFCN | value/runtime globals/document mutation | covered by isolated test | existing runtime coverage | media-volume trace only |
| `xGetSoundVol` | XFCN | value/runtime globals | covered by isolated default/stored-state test | existing runtime coverage | media-volume trace only |
| `xAbout` | XCMD | runtime globals/empty result | covered by isolated no-modal intent test | existing runtime coverage | not visual unless scripts require UI |
| `SetMode` | XCMD | runtime globals/empty result | covered by isolated mode/depth normalization test | existing runtime coverage | palette/depth trace only |
| `GetMode` | XFCN | value/runtime globals | covered by isolated stored-state test | existing runtime coverage | palette/depth trace only |
| `xVirtual` | XFCN | value/runtime globals | covered by isolated deterministic disabled-VM test | existing runtime coverage | not visual |
| `xDepth` | XFCN | value/runtime globals | covered by isolated stored-depth test | existing runtime coverage | palette/depth trace only |
| `variant` | XFCN | value/runtime globals | covered by isolated compatibility-version test | existing runtime coverage | not visual |
| `xClip` | XCMD | runtime globals | covered by isolated clip-rect test | existing runtime coverage | needed with `xLine` visual probes |
| `xLine` | XCMD | paint-layer mutation | covered by isolated clipped-pixel and palette-indexed color tests | existing runtime coverage | needed for broader pixel probes |
| `HyperTint` | XCMD | runtime globals/options | covered by isolated timing/delay/options test | existing runtime coverage | needed for render-operation trace |
| `HTChangePict` | XCMD | image replacement/card viewport paint mutation | covered by isolated test, including direct `cardPaintLayer` draw | existing runtime coverage | needed for full-card replacement snapshots |
| `HTVisual` | XCMD | visual-effect metadata/runtime globals | covered by isolated test | existing runtime coverage | needed for transition frame probes |
| `HTRemove` | XCMD | document mutation/runtime globals | covered by isolated compatibility-part cleanup test | existing runtime coverage | needed for lifecycle cleanup traces |
| `HTLock` | XCMD | runtime globals | covered by isolated lock-mode normalization test | existing runtime coverage | needed in lifecycle traces |
| `HTAddPict` | XCMD | image overlay/document mutation | covered by isolated asset overlay test | existing runtime coverage | needed for overlay/crop/clipboard snapshots |
| `HTSavePict` | XCMD | clipboard asset/document mutation | covered by isolated paint-layer clipboard capture test | existing runtime coverage | needed for capture/restore evidence |
| `HTUDefPal` | XCMD | palette runtime globals | covered by isolated imported-palette payload test | existing runtime coverage | needed for palette-aware visual probes |
| `HTTB1TS` | XCMD | temp-buffer copy runtime globals | covered by isolated temp-buffer copy intent and malformed-rect default tests | existing runtime coverage | needed for dropped-page/temp-buffer evidence |
| `moveCursor` | XCMD | cursor runtime globals | covered by isolated cursor-position intent test | existing runtime coverage | visual only if gameplay requires cursor state |
| `DeCurse` | XCMD | cursor runtime globals | covered by isolated cursor-resource intent test | existing runtime coverage | visual only if gameplay requires cursor state |

## Isolated Invocation Rules

- Use `HyperCardExternalRegistry.default.invokeIsolated(...)` for new direct
  contract tests.
- Prefer no `document` argument for pure value/state externals.
- Pass a synthetic `HypeDocument.newDocument(...)` only when the contract needs
  assets, paint layers, globals, existing parts, or card dimensions.
- Assert raw `HyperCardExternalResult` fields directly: `value`, `result`,
  `diagnostic`, `runtimeGlobals`, `modifiedDocument`, `visualEffect`,
  `visualEffectDuration`, and navigation targets.
- Do not rely on `Interpreter`-merged `scriptGlobals` in isolated tests; that is
  a runtime integration concern.
- Include missing-resource and malformed-input cases before a function graduates
  from `isolated` to `runtimeIntegrated`.

## Function Gate Template

Use this template when adding or updating a function row:

```text
External: HTChangePict
Kind: XCMD
Contract source: docs/HyperCardExternalMapping.md
Inputs: classic picture name, optional destination rect, transfer mode, srcRect
Outputs: value/result asset name, runtime globals, modified document image part
Isolated tests: normal asset, missing asset, srcRect crop, replacement cleanup
Runtime tests: parser command form, field-driven call, interpreter globals merge
Visible evidence: before/after full-card replacement snapshot, resolved PICT asset
Gate status: isolated -> runtimeIntegrated -> visualEvidenceCaptured
```

## Next Gates

1. Expand runtime-integration fixture matrices for stateful follow-up behavior
   that only appears after interpreter/global merging, especially window property
   setters, `close window`, `closemoovs`, and repeated overlay/media lifecycle
   calls.
2. Add deeper palette/compositing fixture cases for `HTUDefPal`, `HyperTint`,
   and `HTTB1TS` beyond runtime-global intent once temp-buffer or palette-tint
   surfaces are modeled.
3. Feed the visual producers into `docs/MystVisibleEvidencePlan.md` probes so
   each visible claim has a matching isolated contract, runtime trace, and
   screenshot or bitmap artifact.

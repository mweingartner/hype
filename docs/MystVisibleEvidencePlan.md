# Myst Visible Evidence Consolidation Plan

This document consolidates the current Myst planning, porting, and runtime
evidence into one visible-evidence capture plan. It is a coordination index: the
source of truth for implemented HyperCard external behavior remains
`docs/HyperCardExternalMapping.md`, and generated Myst evidence remains under
`/Users/jrepp/d/myst-export/docs/`.

## Goal

Build enough evidence to explain and verify what should be visible on screen for
Myst cards, especially the launcher/startup path where card records are mostly
structural and visible graphics are produced by imported PICT resources,
QuickTime windows, HyperTint-family XCMDs, and runtime overlays.

The immediate focus is not new emulation behavior. The focus is collecting and
connecting evidence so future rendering changes can be judged against concrete
screenshots, operation traces, imported resources, and script call sites.

## Existing Evidence Sources

| Area | Source | Use |
| --- | --- | --- |
| Hype external contracts | `docs/HyperCardExternalMapping.md` | Canonical status and current Hype behavior for each XCMD/XFCN emulator. |
| External validation trajectory | `docs/HyperCardExternalValidationTrajectory.md` | Stack-free validation loop, artifacts, and per-function gates before runtime or visual claims. |
| Import resource behavior | `docs/StackImportResourceMapping.md` | How PICT, palette, cursor, icon, media, and native resources become Hype assets or metadata. |
| Myst stack map | `/Users/jrepp/d/myst-export/docs/game-data-map.md` | Stack list, startup flow, external pressure, and first-path routing. |
| External inventory | `/Users/jrepp/d/myst-export/docs/external-emulation-plan.md` | Resource IDs, call counts, staged implementation history, sample call sites. |
| Disassembly audit | `/Users/jrepp/d/myst-export/docs/external-disassembly-audit.md` | Toolbox trap evidence and reverse-engineering notes for each Myst external. |
| HyperTint corpus | `/Users/jrepp/d/myst-export/docs/hypertint-runtime-corpus.md` | Generated call-site corpus for HyperTint-family commands across Myst stacks. |
| HyperTint coverage | `/Users/jrepp/d/myst-export/docs/hypertint-port-coverage-audit.md` | Coverage counts and feature classifications for HyperTint-family calls. |
| HyperTint recipes | `/Users/jrepp/d/myst-export/docs/hypertint-disassembly-recipes.md` | QuickDraw-oriented recipe classes from HyperTint disassembly. |
| Pixel-fidelity trajectory | `/Users/jrepp/d/myst-export/docs/hypertint-pixel-perfect-trajectory.md` | Long-session path from safe emulation to QuickDraw-style pixel evidence. |
| Post-acceptance probes | `/Users/jrepp/d/myst-export/docs/myst-post-acceptance-probe-plan.md` | Staged probe backlog for runtime, visual, font, external, and final artifact validation. |
| Gap ledger | `/Users/jrepp/d/myst-export/docs/myst-playable-gap-ledger.md` | Owner-facing remaining gaps and post-acceptance probe backlog. |
| Golden references | `/Users/jrepp/d/myst-export/docs/golden-images/mobygames-myst-macintosh/` | External screenshot corpus for broad scene-level visual comparison. |

## Visible Graphics Pipeline To Explain

For any target card, visible output may come from these layers and operations:

| Layer or operation | Primary evidence | Current Hype behavior | Evidence still needed |
| --- | --- | --- | --- |
| Card/background geometry | `card_*.json`, `background_*.json`, `stack_-1.json` in exported `.xstk` packages | Structural import creates cards, backgrounds, fields, buttons, and base card dimensions. | Per-card layer inventory that states whether the visible base is actual card paint, an all-black PBM, or external PICT replacement. |
| Background field `pict name` | Stack/card scripts plus content records | `HTChangePict field "pict name", "srccopy"` can resolve imported image assets and create replacement image parts. | Deterministic mapping from each card's `pict name` value to the concrete PICT/PNG asset and rendered bounds. |
| `HTChangePict` | `HyperCardExternalMapping.md`, HyperTint corpus, disassembly audit | Replaces prior `HTChangePict` compatibility image parts and draws decoded replacement pixels into the current card paint layer/card viewport surface when possible. | Before/after capture for representative full-card replacements; operation trace containing source asset, destination rect, transfer mode, and paint/overlay target. |
| `HTAddPict` | HyperTint corpus, external mapping, isolated synthetic-asset test | Adds compatibility image overlays, supports `srcRect`, clipboard restore, and recognized transfer-mode compositing. | Probe cases for partial overlays, door/drawer/button state changes, and clipboard restore paths. |
| `HTSavePict` | HyperTint corpus, external mapping, isolated paint-layer capture test | Records save intent and captures current-card paint-layer pixels for clipboard destinations when available. | Evidence showing whether captured pixels match the intended composite source, not just the current paint layer. |
| `HTTB1TS` | HyperTint recipes, corpus, isolated temp-buffer-intent test | Records HyperTint temp-buffer tile-copy intent. | Concrete dropped-page/temp-buffer visual probe and expected source/destination rect behavior. |
| `HTUDefPal`/`HyperTint` | Palette assets, HyperTint recipes, coverage audit, isolated palette/timing tests | Records palette/tint timing and resolves palette assets into runtime globals; `xLine` can consume active palette colors. | Palette-aware compositor evidence showing PICT/overlay output under active palettes, beyond line primitives. |
| `HTVisual` | External mapping and corpus | Records transition intent and maps effect name/duration into Hype visual-effect result state. | Transition frame-capture plan for named effects where visible timing matters. |
| `HTLock`/`HTRemove` | External mapping, corpus, isolated state/cleanup tests | Records lock mode; removes transient compatibility parts. | Trace showing lock/remove lifecycle around visible overlay creation and cleanup. |
| `Picture` | External mapping, disassembly audit, PICT assets | Disassembly shows classic window/port drawing (`SetPort`, `SetRect`, `OffsetRect`, `DrawPicture`, `CopyBits`) plus scroll-control reads and picture mouse messages; Hype models this as an image-backed compatibility window part with script-visible window state. | Exact scroll/crop/floating-window visual captures for launcher and gameplay usages. |
| `Movie`/`playQT` | External mapping, QuickTime replacement docs, modern media assets | `Movie` disassembly is QuickTime/window-heavy (`QuickTimeDispatch`, `ComponentDispatch`, `SetPort`, `FrameRect`, region/window lifecycle strings); Hype creates repository-backed video/audio parts, with audio-only media using hidden playback parts. | First-frame and placement captures for visible movies; lifecycle trace for `set the ... of window ...` changes. |
| `xCIcon3` | External mapping, icon assets | Disassembly shows color-icon lookup and QuickDraw port work (`GetCIcon`, `SetPort`, `SetRect`, `EraseRect`, `OpenPort`/`ClosePort`); Hype creates transparent icon overlays centered on classic point arguments. | Button/icon state capture showing overlay placement, reuse/removal behavior, and exact asset chosen. |
| `xClip`/`xLine` | External mapping and palette tests | Disassembly maps directly to QuickDraw region/line primitives: `xClip` uses region setup (`NewRgn`, `OpenRgn`, `FrameRect`, `CopyRgn`) while `xLine` uses `PenSize`, `ForeColor`, `MoveTo`, and `LineTo`; Hype records clip rects and renders clipped line primitives into current card paint layer. | Visual probes for tower/rotation paths and palette-indexed lines against expected pixels. |
| `moveCursor`/`DeCurse` | External mapping, cursor resources, isolated cursor-intent tests | Records cursor intent without moving the host pointer. | Cursor-state capture only if gameplay evidence shows visible cursor changes are required for understanding. |
| `xMemory`/`xSetSoundVol`/`xAbout` | External mapping and runtime tests | Script-visible/environment compatibility; not direct graphics producers. | Include in traces as context only when they gate a visible branch. |

## First Evidence Target: Myst Application Startup

The launcher stack is the right first target because the first four cards are
small and expose the core problem: card records alone do not explain the visible
graphics.

Current exported order from `Myst-Application.xstk/stack_-1.json`:

| Order | Card ID | Name | Visible evidence question |
| ---: | ---: | --- | --- |
| 1 | `2953` | empty | Startup dispatcher with all-black bitmap; visible result depends on `idle`, `NewGame`, `FullIntro`, and background/media calls. |
| 2 | `3656` | `black` | Black transition card with marker hotspots; used by quit/intro/credits flows. |
| 3 | `2269` | `bookDown` | Book-down state has a hotspot but no card bitmap in the export record; likely relies on background `pict name`/PICT replacement. |
| 4 | `2517` | `bookClosed` | Closed-book state has no parts and no card-local script; visible image likely comes from external picture state. |

Startup evidence to collect:

| Step | Capture |
| --- | --- |
| Static package inventory | Card/background parts, contents, PBM density, `pict name` values, and referenced asset names. |
| Script trace | `startup`, `Paths`, `stackInit`, `Environment`, first-card `idle`, `NewGame`, `FullIntro`, and each external call reached before book interaction. |
| External operation trace | Ordered `HTChangePict`, `HTLock`, `HTUDefPal`, `HyperTint`, `HTRemove`, `Movie`, `playQT`, `Picture`, and `HTVisual` calls with normalized arguments and resolved assets. |
| Render snapshots | Before/after card bitmap or screenshot for each graphics-producing operation, plus final steady-state frame for each card. |
| Media snapshots | First frame, bounds, hidden/visible flag, loop/autoplay state, and asset path for each `Movie`/`playQT` call. |
| Comparison references | MobyGames screenshots where correlated, and later a classic-Mac oracle capture if available. |

`Tests/HypeCoreTests/HyperCardExternalIsolationTests.swift` includes a
deterministic visible-evidence probe for `HTChangePict`, `HyperTint`, `Movie`,
and the current card paint layer using synthetic assets. By default it only
asserts the trace and surface state in memory. To materialize local artifacts,
run the isolated suite with `HYPE_VISIBLE_EVIDENCE_OUTPUT=/path/to/output`; the
test writes `myst-visible-evidence-probe.json` and
`myst-visible-evidence-paint-layer.png`.

## Evidence Artifact Shape

Each visible probe should produce both machine-readable JSON and a short Markdown
summary so humans can review failures quickly.

Suggested JSON shape:

```json
{
  "probeId": "myst-app-startup-card-2953",
  "sourcePackage": "Myst-Application.xstk",
  "target": { "stack": " Myst", "cardId": 2953, "cardName": "" },
  "sourceFingerprint": "<package or manifest fingerprint>",
  "staticLayers": [],
  "scriptTrace": [],
  "externalOperations": [],
  "resolvedAssets": [],
  "renderSnapshots": [],
  "mediaSnapshots": [],
  "comparisons": [],
  "openQuestions": []
}
```

Minimum fields for a graphics-producing external operation:

| Field | Purpose |
| --- | --- |
| `sequence` | Stable order in the script/runtime trace. |
| `owner` | Stack/card/background/part that issued the call. |
| `sourceLine` | Script line and raw source when available. |
| `name` | External command/function name with canonical casing. |
| `arguments` | Evaluated and raw argument forms when available. |
| `resolvedAsset` | Asset id/name/resource type/resource id/path. |
| `sourceRect` | Classic source rect or inferred full source bounds. |
| `destinationRect` | Classic destination rect or inferred card/window bounds. |
| `transferMode` | `srcCopy`, `transparent`, `srcXor`, or unresolved mode. |
| `paletteState` | Active palette id and resolved color table reference. |
| `outputSurface` | Card paint layer, transient overlay, temp buffer, window, video part, or state-only. |
| `snapshotBefore` / `snapshotAfter` | Paths to deterministic bitmap/screenshot artifacts. |
| `confidence` | `observed`, `inferred`, or `unknown`. |

## Consolidated Backlog

| Priority | Work item | Inputs | Output |
| ---: | --- | --- | --- |
| 1 | Generate per-card visible layer inventory for `Myst-Application.xstk` first four cards. | `.xstk` card/background/stack JSON, PBM files, asset manifests. | Markdown/JSON inventory listing base layers, fields/buttons, scripts, and unresolved visual dependencies. |
| 1 | Link `pict name` values and `HTChangePict` calls to concrete imported PICT assets. | Stack scripts, card contents, asset metadata, `HTChangePict` emulator lookup rules. | Lookup table from card/state name to asset id/resource metadata and expected bounds. |
| 1 | Capture first-path external operation trace from app startup through final book open. | Hype debug import/runtime probe, script-index, external registry diagnostics. | Ordered trace with resolved assets and media parts. |
| 1 | Capture deterministic render snapshots for graphics-producing operations. | Runtime probe harness or headless renderer, disposable package copy. | Before/after PNGs plus operation JSON. |
| 2 | Normalize all Myst external names case-insensitively in generated reports. | Existing script indexes and corpus generator. | Corpus without split names such as `htchangePict`/`HTChangePict`. |
| 2 | Expand HyperTint operation trace beyond state globals. | HyperTint recipes, runtime corpus, emulator hooks. | `HyperTintRenderOperation`-style trace with no-op reasons. |
| 2 | Add QuickTime visible-window evidence for `Movie` and `playQT`. | Modern QuickTime replacements, media metadata, runtime video parts. | First-frame/bounds/lifecycle captures. |
| 3 | Add transition frame probes for `HTVisual`. | Runtime visual-effect state and card snapshots. | Frame sequence or deterministic metadata for representative effects. |
| 3 | Add cursor/icon visible probes for `xCIcon3`, `DeCurse`, and `moveCursor`. | Cursor/icon resources and runtime state. | Placement/state captures only where gameplay requires visible cursor evidence. |

## Verification Rules

- Use disposable package copies for live probes unless the task explicitly needs
  to update tracked generated evidence.
- Do not execute original 68K/PPC resources; all behavior must remain Swift
  emulation or offline disassembly analysis.
- Do not treat passing acceptance tests as visual proof. A visible claim needs a
  static resource link, operation trace, screenshot/bitmap artifact, or pixel
  comparison.
- Keep `.hype` packages and generated `.xstk` exports out of Hype repo commits
  unless the task explicitly requires them.
- When generated Myst docs are refreshed, preserve the exact command used and
  the source/export fingerprint in the resulting report.

## Next Concrete Step

Build `myst-app-startup-card-inventory` as the first visible-evidence artifact.
It should read the regenerated `Myst-Application.xstk`, summarize cards `2953`,
`3656`, `2269`, and `2517`, and emit unresolved visual dependencies such as
`pict name` fields, `HTChangePict` calls, and QuickTime/Picture calls that must
be resolved before the visible output can be claimed.

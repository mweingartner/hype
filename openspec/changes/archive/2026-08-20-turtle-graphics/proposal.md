# Turtle Graphics for HypeTalk

## Why

Hype has no way to script vector drawings onto a card: the raster `drag` paint
path is pixels-only, and shape parts can only be placed one at a time. The
classic Logo turtle is the missing, audience-right vocabulary — an imperative
pen whose trail becomes real, editable shape parts — and the AI assistant needs
the identical vocabulary through one tool so both surfaces stay equivalent by
construction.

## What Changes

- New HypeTalk turtle vocabulary (`forward`/`fd`, `back`/`bk`, `right`/`rt`,
  `left`/`lt`, `setHeading`/`setH`, `setPos`/`setXY`, `home`, `penUp`/`pu`,
  `penDown`/`pd`, `setPenColor`, `setPenWidth`/`setPenSize`, `setFillColor`,
  `beginFill`/`endFill`, `circle`, `arc`, `dot`, `clean`, `clearScreen`/`cs`,
  `reset turtle`) plus the `the <prop> of the turtle` property surface —
  parsed without new reserved lexer keywords via the external-command path.
- A single pure `TurtleEngine` in HypeCore owns turtle state, geometry, the
  stroke/fill flush lifecycle, per-run limits, and every error string; the
  interpreter and the AI tool are thin front-ends over it.
- Turtle output is ordinary `.freeform`/`.oval` shape parts named
  `turtle path N` / `turtle fill N` / `turtle dot N` on the current card. No
  document-format change, no version bump.
- New AI tool `draw_with_turtle` (authoring catalogs only; absent from the
  runtime catalog) that parses a turtle-only program with the real HypeTalk
  parser, refuses non-turtle statements all-or-nothing (E9), and executes
  through the same interpreter/engine path.
- `.freeform` renderer alignment across **all three** render sites —
  `ShapeRenderer` (CG), `ShapePartNode` (SK), and the deployed/exported
  `TargetRuntimeShapeView` — through a shared
  `RenderGeometry.freeformIsOpenStroke` helper: `fillColor == ""` renders
  as an open, stroked, round-capped polyline; non-empty renders closed +
  filled (+ stroked when `strokeWidth > 0`). In the two editor renderers
  path geometry anchors to the part frame so moved freeform parts carry
  their drawing; the export runtime keeps its existing stretch-to-fit
  geometry (only its open/closed + fill decision is unified). This closes
  a latent defect where the export runtime rendered a `fillColor ""`
  freeform as a solid **black** polygon.
- `HexColor.normalized` gains a fixed 16-name classic color table
  (system-wide, additive) — **modifies the `part-properties` capability**.
- HypeTalk guide + skill catalog gain a Turtle graphics section/skill;
  `InterpreterFuzzTests` gains the turtle statement family and turtle
  metamorphic relations.

No breaking changes. Two visible legacy corrections are recorded as notes:
CG-rendered legacy freeform parts gain the stroke SK already showed (and stop
rendering vertically mirrored), and bare `home` becomes the turtle command
(user handlers named `home` still take precedence; `go home` is unchanged).

## Capabilities

### New Capabilities

- `turtle-graphics` — the turtle vocabulary, vector output contract, session
  state, engine-owned errors, renderer alignment, AI tool + allowlist, and
  cross-surface equivalence.

### Modified Capabilities

- `part-properties` — the shared `HexColor` validator additionally accepts a
  fixed, case-insensitive 16-name classic color table (hex behavior,
  empty-string sentinel, and chart carve-out unchanged).

## Impact

- `Sources/HypeCore/Script/`: new `TurtleEngine.swift`,
  `TurtlePartApplier.swift`, `TurtleProgramValidator.swift`,
  `HypeTalkFormat.swift`; surgical edits to `Parser.swift` and
  `Interpreter.swift`. `AST.swift` is declared but expected untouched.
- `Sources/HypeCore/Rendering/`: `ShapeRenderer.swift`, `RenderGeometry.swift`.
- `Sources/Hype/SpriteKit/ShapePartNode.swift`.
- `Sources/HypeCore/Export/TargetRuntimeControlViews.swift` — the third
  freeform render site (deployed/exported runtime); honors the same
  `fillColor==""` open/no-fill contract via the shared `RenderGeometry`
  helper (keeps its own stretch-to-fit geometry).
- `Sources/HypeCore/AI/`: `HypeTools.swift`, `HypeToolExecutor.swift`,
  `HypeTalkGuide.swift`, `HypeTalkSkillCatalog.swift`.
- Shared: `Sources/HypeCore/Models/HexColor.swift` (name table),
  `Sources/HypeCore/Models/PartDuplication.swift` (`nextPartSortOrdinal`
  visibility `private` → `internal`).
- Tests: `TurtleEngineTests`, `TurtleScriptingTests`,
  `TurtleCrossSurfaceEquivalenceTests`, `ShapeRendererFreeformTests`,
  `TargetRuntimeFreeformTests`, `ShapePartNodeFreeformTests` (app target),
  extensions to `InterpreterFuzzTests`, `HypeTalkGuideTests`,
  `PartPropertyDispatchTests`.
- Docs: `HypeTalk-LLM-Context.md` (Documentation phase).

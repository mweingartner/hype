# turtle-graphics

## ADDED Requirements

### Requirement: One turtle engine behind every surface

A single pure, `Sendable` `TurtleEngine` in HypeCore SHALL own turtle state,
all geometry (movement, circle/arc approximation, dot), the stroke/fill
accumulators and flush lifecycle, the per-run limits, and every turtle error
string (E1–E9). The HypeTalk interpreter and the `draw_with_turtle` AI tool
SHALL be thin callers of this engine; no second geometry implementation may
exist on any surface. The engine SHALL NOT import the interpreter, parser, or
AI executor.

#### Scenario: Error strings are byte-identical across surfaces

- **WHEN** `setPenColor "blurple"` runs in a HypeTalk handler and the same
  line runs inside a `draw_with_turtle` program
- **THEN** the HypeTalk `ScriptError` message and the tool result string are
  byte-identical:
  `turtle: "blurple" isn't a color — use #RRGGBB, #RRGGBBAA, or a name like red, blue, orange.`

### Requirement: Turtle vocabulary

HypeTalk SHALL execute the turtle commands `forward`/`fd`, `back`/`bk`,
`right`/`rt`, `left`/`lt`, `setHeading`/`setH`, `setPos`/`setXY`, `home`,
`penUp`/`pu`, `penDown`/`pd`, `setPenColor`, `setPenWidth`/`setPenSize`,
`setFillColor`, `beginFill`, `endFill`, `circle`, `arc`, `dot`, `clean`,
`clearScreen`/`cs`, and `reset turtle`, case-insensitively, with no new
reserved lexer keywords. Numeric arguments are full HypeTalk expressions
coerced via the `Double(_:) ?? 0` rule; non-finite values coerce to 0;
positions clamp to ±1,000,000. Heading uses degrees, 0 = up, clockwise
positive, normalized to [0, 360). Home is the card center
(`stack.width/2`, `stack.height/2`); coordinates are card coordinates
(top-left origin, y-down). Pen defaults: down, `#000000`, width 2; fill color
default `#000000`. `setPenWidth` clamps to [0.5, 100]. User-defined handlers
with a turtle verb's name SHALL keep message-dispatch precedence over the
built-in on both surfaces.

#### Scenario: First line from defaults

- **WHEN** on an 800×600 stack a handler runs `forward 100` and the run ends
- **THEN** the turtle moved from (400,300) to (400,200) and exactly one
  `.freeform` part exists with `pathData == [(400,300),(400,200)]`,
  `strokeColor "#000000"`, `strokeWidth 2`, `fillColor ""`

#### Scenario: Rotation and absolute forms

- **WHEN** from home a script runs `right 90` then `forward 100`
- **THEN** the turtle is at (500,300); `left 90` inverts the rotation;
  `setHeading 270` then `forward 100` from home reaches (300,300); after
  `right 450` `the heading of the turtle` is `90`

#### Scenario: Abbreviations behave identically

- **WHEN** a script uses `fd`, `bk`, `rt`, `lt`, `setH`, `setXY`, `pu`, `pd`,
  or `cs`
- **THEN** each behaves identically to its long form

#### Scenario: Tolerant numerics, strict colors

- **WHEN** a script runs `forward "banana"`, `setPenWidth 500`, and
  `setPenColor "blurple"`
- **THEN** `forward` coerces to 0 and is a quiet no-op, the width clamps to
  100 silently, and the color raises E1 leaving pen state unchanged

### Requirement: Turtle property surface

`the position of the turtle` (aliases `loc`, `location`; format `"x,y"`),
`xcor`, `ycor`, `heading`, `penDown`, `penColor`, `penWidth`, `fillColor`,
and `filling` SHALL be readable via `the <prop> of the turtle`; `position`,
`heading`, `penDown`, `penColor`, `penWidth`, and `fillColor` SHALL be
settable with semantics identical to the corresponding commands; `xcor`,
`ycor`, and `filling` SHALL error as read-only on SET. Aliases SHALL be
symmetric between GET and SET. Error copy SHALL follow the registry style
(lowercase start, quoted user input, em-dash guidance).

#### Scenario: Property round-trip

- **WHEN** a script runs `set the heading of the turtle to 45`
- **THEN** `the heading of the turtle` returns `45`, identically to having
  run `setHeading 45`

### Requirement: Vector output contract

Every flush SHALL emit one Part with `partType .shape` and `shapeType
.freeform` (strokes, fills) or `.oval` (dots); absolute card-coordinate
`pathData` in draw order (unrounded doubles); stroke parts with
`fillColor ""`, `strokeColor` = pen color, `strokeWidth` = pen width; fill
parts with `fillColor` = turtle fill color and outline from pen state at
`endFill` (pen up → `strokeWidth 0`); frame = tight `pathData` bounds padded
by `strokeWidth/2` per side (minimum 1×1); name `turtle path N` /
`turtle fill N` / `turtle dot N` where N is the smallest positive integer not
already used with that prefix on the target card; `cardId` = current card at
flush time; sortKey via the existing next-part-sort-ordinal path; rotation 0,
visible true, empty script. The document format SHALL NOT change and no
document-version bump is required.

#### Scenario: Trail splits on pen change

- **WHEN** a run executes `forward 50` / `setPenColor "red"` / `forward 50`
- **THEN** exactly two stroke parts exist with the respective colors

#### Scenario: Square is one part

- **WHEN** a pen-down turtle runs `repeat 4 times / forward 120 / right 90 /
  end repeat` and the run ends
- **THEN** exactly one part exists with exactly 5 vertices, first == last,
  forming a 120-pt square

#### Scenario: Fill emits one part

- **WHEN** a pen-down turtle runs `beginFill`, three `forward 130 / right
  120` steps, then `endFill`
- **THEN** exactly one `.freeform` part exists with 4 vertices,
  `fillColor` = turtle fill color and `strokeColor`/`strokeWidth` from the
  pen, and no separate stroke part was created by the movement; the same
  sequence with pen up emits `strokeWidth 0`

#### Scenario: Curve approximation is exact

- **WHEN** `circle 50` and `arc 90, 50` run
- **THEN** the circle part has 61 vertices whose first and last are
  identical and all within 0.07 pt of the radius; the arc part has
  max(8, ceil(90/6)) = 15 segments (16 vertices); neither moves the turtle;
  `dot 10` emits a 10×10 `.oval` centered on the turtle with `fillColor` =
  pen color and `strokeWidth 0`

#### Scenario: Flush lifecycle

- **WHEN** an active stroke exists
- **THEN** it flushes (emitting a part when it has ≥ 2 vertices and non-zero
  length) on `penUp`, on a pen color/width change, on `beginFill`, on card
  navigation, and at end of the top-level run; `clean`, `clearScreen`, and
  `reset turtle` discard open buffers instead of emitting; an unclosed
  `beginFill` at end of run emits nothing and sets `the result` to E7

#### Scenario: Limits are enforced with honest partial state

- **WHEN** a single run attempts to emit more than 200 parts or 50,000 total
  path points
- **THEN** the engine raises E8, the run stops, and parts already emitted in
  that run remain

### Requirement: Session-scoped turtle state

One turtle SHALL exist per open-stack session. Scalar state (position,
heading, pen up/down, pen color, pen width, fill color) SHALL persist across
runs within a session via the session-only script-globals channel, reset to
defaults on stack open, and never be written into the `.hype` document.
Buffers SHALL NOT survive a run. `reset turtle` SHALL restore defaults
without deleting parts; `clean` SHALL delete exactly the parts on the current
card whose names start with `turtle path`, `turtle fill`, or `turtle dot`;
`clearScreen` SHALL additionally home without drawing.

#### Scenario: Message-box REPL

- **WHEN** `forward 100`, then `rt 90`, then `forward 100` run as three
  separate message-box commands
- **THEN** the walk continues across runs and each drawing run flushes its
  own part (two parts total)

#### Scenario: Renamed drawings are adopted

- **WHEN** a turtle-drawn part is renamed and `clean` runs
- **THEN** the renamed part survives

### Requirement: Freeform renderer alignment

All three freeform render sites — `ShapeRenderer` (CG),
`ShapePartNode` (SK), and `TargetRuntimeShapeView` (the deployed/exported
runtime, `TargetRuntimeControlViews.swift`) — SHALL render `.freeform`
parts with one open/closed contract, gated through the shared
`RenderGeometry.freeformIsOpenStroke(_:)` helper: `fillColor == ""` → an
open polyline (no close, no fill) stroked with `strokeColor` at
`strokeWidth` when > 0, with round line caps and joins; `fillColor`
non-empty → closed subpath, filled, and stroked when `strokeWidth > 0`.
The two editor renderers (CG, SK) SHALL additionally anchor the path's
tight bounding box (expanded by `strokeWidth/2`) to the part frame origin
so that moving the frame moves the visible drawing; the export runtime
SHALL keep its existing stretch-to-fit `normalizedPathPoints` geometry
unchanged (only its open/closed + fill/no-fill decision is unified).

#### Scenario: Renderer parity

- **WHEN** a stroke part (`fillColor ""`) and a fill part render in CG, SK,
  and the deployed/exported runtime
- **THEN** the stroke part is open, stroked, and unfilled in all three; the
  fill part is closed, filled, and outlined in all three; an existing
  freeform part with `fillColor "#FFFFFF"` still renders closed and filled
  in all three (in particular the export runtime no longer renders a
  `fillColor ""` part as a solid black polygon)

#### Scenario: Dragging moves the drawing

- **WHEN** a turtle-drawn part's frame is moved in edit mode
- **THEN** the visible drawing translates rigidly with the frame

### Requirement: AI tool draw_with_turtle

`draw_with_turtle` SHALL exist in `HypeToolDefinitions.allTools` (and the
card-control and sprite-scene authoring allowlists) with one required string
parameter `program`, and SHALL NOT exist in `RuntimeAIToolCatalog`. The tool
SHALL cap `program` at 64 KB, parse it with the real HypeTalk parser, and
validate an allowlist — turtle commands, turtle property sets, `reset
turtle`, `--` comments, and `repeat N times` / `repeat with i = a to b`
loops with arithmetic-only expressions — before any mutation; any other
statement SHALL refuse with E9 naming the first offending line, creating
zero parts. The allowed-expression validator SHALL be applied to **every**
expression position in every allowed statement — external-command
arguments, the `set` value expression, and the `repeatCount` count and
`repeatWith` from/to bound expressions; a `functionCall` (or any
non-arithmetic / non-turtle-property expression) in **any** position SHALL
refuse with E9 and create zero parts. Valid programs SHALL execute through
the same interpreter, engine, and part-emission path as HypeTalk, on an
`ExecutionContext` built with deny-by-default stub providers only (no real
file/host/runtime provider), mutating the document through the executor's
standard `inout HypeDocument` path, and return a compact summary naming
each created part and the final turtle state. Engine errors SHALL return
the engine string verbatim. Loop iterations SHALL be bounded and
cancellable by `context.instructionLimit` regardless of body (so an
empty-body counted loop cannot spin unbounded).

#### Scenario: Function call in any position refuses (sandbox boundary)

- **WHEN** a program contains `repeat foo() times`, `repeat with i = 1 to
  foo()`, or `set the heading of the turtle to foo()`
- **THEN** the tool refuses with E9 and creates zero parts — no user
  function is invoked

#### Scenario: Empty-body counted loop is bounded, not a hang

- **WHEN** a program is `repeat 1000000000 times` / `end repeat`
- **THEN** execution terminates with an "Instruction limit exceeded" error
  (not an unbounded spin) and, on the tool surface, mutates nothing

#### Scenario: Non-turtle statement refuses all-or-nothing

- **WHEN** a program's line 4 is `go next card`
- **THEN** the tool returns
  `turtle: line 4 isn't a turtle command ("go next card") — draw_with_turtle accepts only turtle commands and repeat loops.`
  and zero parts were created

#### Scenario: Success summary

- **WHEN** a valid program draws three shapes on card "Garden"
- **THEN** the result names each part and the turtle state, e.g.
  `Drew 3 shapes on card "Garden": turtle path 1 (5 points), turtle fill 1 (4 points), turtle dot 1. Turtle at 400,180 heading 90, pen down.`

### Requirement: Cross-surface equivalence

The identical program executed (a) as a HypeTalk handler and (b) via
`draw_with_turtle` from the same starting document SHALL produce parts with
byte-identical `pathData`, `shapeType`, `fillColor`, `strokeColor`,
`strokeWidth`, frames, and names (ids and sortKeys excepted), and identical
invalid input SHALL produce the identical error string on both surfaces.

#### Scenario: Garden program equivalence

- **WHEN** the canonical Turtle Garden program body runs on both surfaces
  against copies of the same document
- **THEN** the emitted part lists are field-identical per the above

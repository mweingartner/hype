# Design Spec — Turtle Graphics for HypeTalk (`turtle-graphics`)

Phase: Design Mock (Phase A). Designer: Fable. Date: 2026-08-19.
Scope: HypeTalk turtle vocabulary + vector output on the card + AI tool surface, one engine behind both.

## 1. Design-language audit (what this change must reuse)

Grounded in:

- `Sources/HypeCore/Models/HypeStack.swift` — `ShapeType.freeform`, `PathPoint {x, y}` (polyline-only; no control points).
- `Sources/HypeCore/Models/Part.swift` — shape parts carry `pathData: [PathPoint]`, `fillColor`/`strokeColor`/`strokeWidth` (hex strings, `""` as an app-wide "auto/none" sentinel per `fontColor`), frame `left/top/width/height`, `sortKey`, `name`.
- `Sources/HypeCore/Rendering/ShapeRenderer.swift` + `Sources/Hype/SpriteKit/ShapePartNode.swift` — freeform renders as a CG/SK polyline; **today CG closes+fills and never strokes, SK closes+fills+strokes**. They already disagree; this change aligns them (§5.2).
- `Sources/HypeCore/Script/Interpreter.swift` — the raster `DrawingProvider` (`drag from x,y to x,y` + `pencilsize`/`pencilcolor` globals, defaults `2` / `#000000`), card coordinates top-left origin y-down, the global-property `the <name>` switch, `reset <target>` verb, tolerant numeric coercion (`toNumber` → garbage becomes 0), clamp-on-write numeric convention (`musicTempo`, `setGaugeValue`).
- `Sources/HypeCore/Models/PartPropertyRegistry.swift` + `HexColor.swift` — the **one-vocabulary, two-surfaces** pattern: shared resolution, byte-identical error copy (lowercase-start, quoted user input, em-dash suggestion), `HexColor.normalized` as the single color gate.
- `Sources/HypeCore/AI/HypeTools.swift`, `HypeToolExecutor.swift`, `RuntimeAIToolCatalog.swift` — snake_case verb_noun tools, string params, text results, script-draft refusal gate; the runtime catalog is a separate consent-gated surface that does **not** mutate the document.
- `AGENTS.md` — interpreter changes must extend `InterpreterFuzzTests`; document-shape changes need versioned migration (this design **avoids any document-shape change**: no new PartType, no PathPoint change).

## 2. Intent (in the product's language)

Give stack authors the classic Logo turtle inside HypeTalk: an imperative pen you steer with `forward` and `right`, whose trail becomes **real shape parts on the card** — editable, inspectable, scriptable, saved in the `.hype` document like anything drawn by hand. The AI speaks the identical vocabulary through one tool. The turtle should feel like it always belonged in a HyperCard: tolerant, English-like, immediate.

## 3. Rulings (one canonical answer each)

| # | Question | Ruling | Why |
|---|---|---|---|
| R1 | Output model | **Vector `.freeform` shape parts (default and only mode in v1)** | Editable/scalable/persistent; the raster `DrawingProvider` already exists as `drag` for paint — offering a turtle "paint mode" would duplicate that surface. Deferred, seam noted (§5.6). |
| R2 | Curves | **Polyline approximation, fixed 6°-per-segment rule** (§5.4). No `PathPoint` change | Smallest correct approach; avoids a document-format migration entirely. |
| R3 | Coordinates | **Card coordinates** (top-left origin, y-down, points), same as `the loc`, `drag`, `the mouseLoc` | One coordinate vocabulary per scripting surface; a second, centered system would be a false cognate inside HypeTalk. |
| R4 | Angles | **Degrees; heading 0 = up (toward card top); clockwise positive; normalized [0, 360)** | Logo compass convention; `fd`/`rt 90` squares behave exactly as in Logo. |
| R5 | Home | **Card center: `(stack.width/2, stack.height/2)`**; `home` also sets heading 0, drawing if pen down | Logo `HOME` semantics mapped onto card space. |
| R6 | Turtle identity | **One turtle, `the turtle`, per open-stack session.** Scalar state persists across runs (message-box REPL works); buffers flush at end of each run; nothing turtle-state is saved to `.hype` | Drawn parts are the durable artifact; the turtle itself is a session tool, like the selection. |
| R7 | Visible cursor | **Deferred from v1.** No `showTurtle`/`hideTurtle` verbs ship (a verb that silently does nothing is a design defect). Seam: a Phase-2 SpriteKit overlay node in the card scene's native layer | Keeps v1 tight; drawing is near-instant so the cursor's value is mostly in future step-animation. |
| R8 | Position command | **`setPos x, y`** (alias `setXY`). **No `goto`** | `goto` collides with `go` navigation — a false cognate rejected by name. |
| R9 | Named colors | **Extend `HexColor.normalized` with a 16-name classic table** (§5.7) so *every* color property gains names uniformly | `setPenColor "red"` is essential for the audience; a turtle-only name table would fork the color vocabulary. System-wide improvement, one owner. |
| R10 | Error philosophy | **Colors and impossible geometry error; out-of-range numerics clamp; garbage numerics coerce to 0** | Matches the codebase's existing split (HexColor nil→error; tempo/gauge clamp; `toNumber` coercion). |
| R11 | AI surface | **One tool, `draw_with_turtle`, taking a turtle-only program string**, parsed by the real HypeTalk parser, executed by the same engine (§7) | Same expressive power as HypeTalk without tool explosion or arbitrary script execution. Equivalence by construction. |
| R12 | Pen vs pencil | The raster paint tool's `pencilsize`/`pencilcolor` and the turtle's **pen** are deliberately distinct concepts; turtle state is always read via `of the turtle` | Prevents one-letter naming drift (`penColor` vs `pencilcolor`); documented in the guide. |

## 4. HypeTalk vocabulary

All commands case-insensitive (canonical camelCase in docs). Numeric arguments are full HypeTalk expressions coerced via `toNumber` (garbage → 0). Color arguments accept `#RRGGBB`, `#RRGGBBAA`, or a classic name (§5.7).

### 4.1 Movement

| Command | Semantics |
|---|---|
| `forward n` / `fd n` | Move n points along heading: `dx = n·sin(h°)`, `dy = −n·cos(h°)`. Pen down → appends vertex to active stroke (opens one if needed). Negative n moves backward. |
| `back n` / `bk n` | Exactly `forward -n`. |
| `right deg` / `rt deg` | heading ← (heading + deg) mod 360. Negative allowed. |
| `left deg` / `lt deg` | heading ← (heading − deg) mod 360. |
| `setHeading deg` / `setH deg` | heading ← deg mod 360 (absolute). Never draws. |
| `setPos x, y` / `setXY x, y` | Move to absolute card point. Pen down → draws a straight segment there. Comma-joined args like `drag from x,y`. |
| `home` | `setPos` to card center **then** heading ← 0. Draws if pen down (Logo semantics). |

Positions are unbounded — the turtle may leave the card and return; coordinates clamp defensively to ±1,000,000.

### 4.2 Pen

| Command | Semantics |
|---|---|
| `penUp` / `pu` | Stop drawing. **Flushes** the active stroke into a part (§5.3). Idempotent. |
| `penDown` / `pd` | Resume drawing from the current position. Idempotent. Default state: **down**. |
| `setPenColor c` | Pen color ← normalized c. Invalid → error E1, state unchanged. If an active stroke exists and the value changed, flush first (a part has one strokeColor). |
| `setPenWidth w` / `setPenSize w` | Pen width ← w clamped to [0.5, 100] (clamp-on-write convention). Changed value flushes the active stroke first. Default 2 (matches the paint pencil's default). |

### 4.3 Fill

| Command | Semantics |
|---|---|
| `setFillColor c` | Fill color state ← normalized c. Default `#000000`. Invalid → error E1. |
| `beginFill` | Flush any active stroke; start recording fill vertices from the current position. While filling, movement feeds **only** the fill polygon (no separate stroke part). Already filling → error E4. |
| `endFill` | Close the polygon (last→first implicit) and emit **one** `.freeform` part: `fillColor` = turtle fill color; outline = pen state at `endFill` (pen down → `strokeColor`/`strokeWidth` from pen; pen up → `strokeWidth` 0). Fewer than 3 distinct vertices → no part, `the result` ← E6. No `beginFill` → error E5. |

### 4.4 Drawing primitives (turtle does not move)

| Command | Semantics |
|---|---|
| `circle r` | Polyline circle of radius r **centered on the turtle** (UCB-Logo `arc 360 r`): 60 segments, 61 vertices, first = last, starting at the point at the turtle's heading. Emitted immediately as its own stroke part (fill `""`), or as vertices of the fill polygon when filling. r ≤ 0 → error E2. |
| `arc deg, r` | Arc of that circle, from the turtle's heading, clockwise `deg` degrees (negative → counterclockwise). deg clamps to [−360, 360]. Segments n = max(8, ceil(\|deg\|/6)), n+1 vertices. r ≤ 0 → error E2; deg coercing to 0 → no-op. Emitted immediately as its own stroke part. |
| `dot` / `dot d` | Filled circle of diameter d (default max(2×penWidth, 4)) centered on the turtle: an **`.oval` shape part**, `fillColor` = pen color, `strokeWidth` 0 (reuses the existing oval shape — no new geometry). d ≤ 0 → error E2. Draws even with pen up (Logo `dot` semantics). |

### 4.5 Canvas and reset

| Command | Semantics |
|---|---|
| `clean` | Delete every part on the **current card** whose name starts with `turtle path`, `turtle fill`, or `turtle dot`. Discards open buffers. Turtle stays put. Renamed parts survive — renaming a drawing is adopting it. |
| `clearScreen` / `cs` | `clean` then `home` (without drawing). |
| `reset turtle` | Extends the existing `reset` verb: state ← defaults (home position, heading 0, pen down, `#000000`, width 2, fill `#000000`, not filling; buffers discarded). Drawings untouched. |

### 4.6 Turtle state — property form

Read/written exactly like part properties, object `the turtle`:

| Property | Read | Set |
|---|---|---|
| `the position of the turtle` (aliases `loc`, `location`) | `"x,y"` (formatNumber) | yes — like `setPos` (draws if pen down) |
| `the xcor of the turtle` / `the ycor of the turtle` | number | read-only (use `setPos`) |
| `the heading of the turtle` | 0–359.999… | yes ≡ `setHeading` |
| `the penDown of the turtle` | `true`/`false` | yes ≡ `penDown`/`penUp` |
| `the penColor of the turtle` | `#RRGGBB[AA]` | yes ≡ `setPenColor` |
| `the penWidth of the turtle` | number | yes ≡ `setPenWidth` |
| `the fillColor of the turtle` | `#RRGGBB[AA]` | yes ≡ `setFillColor` |
| `the filling of the turtle` | `true`/`false` | read-only |

Property aliases obey the registry's alias-symmetry law (same alias set for GET and SET).

## 5. Output model — how the trail becomes parts

### 5.1 Part contract

Every flush emits one `Part`:

- `partType: .shape`, `shapeType: .freeform` (strokes and fills) or `.oval` (dots).
- `pathData`: absolute card-coordinate vertices (y-down), in draw order. Doubles, unrounded.
- Stroke part: `fillColor = ""` (the app-wide "none" sentinel, per `fontColor`/`HexColor` docs), `strokeColor` = pen color, `strokeWidth` = pen width.
- Fill part: `fillColor` = turtle fill color; outline per §4.3.
- Frame: `left/top` = tight bounding box of `pathData` minus `strokeWidth/2` padding on each side; `width/height` = bounds + padding both sides (min 1×1).
- `name`: `turtle path N` / `turtle fill N` / `turtle dot N` — N = smallest positive integer not already used with that prefix on the target card. `cardId` = current card at flush time. `sortKey` via the existing next-part-sortKey path; `rotation` 0, `visible` true, `script` empty.

### 5.2 Renderer contract change (Architect owns; this is the one rendering change)

`.freeform` in **both** `ShapeRenderer.draw` and `ShapePartNode.updateFromPart`:

- `fillColor == ""` → **open** polyline: no close, no fill; stroke with `strokeColor` at `strokeWidth` (when > 0), round line caps and joins (a pen trail must not have miter spikes).
- `fillColor` non-empty → close subpath, fill, and stroke when `strokeWidth > 0` (also closed).

Backward compatibility: existing freeform parts default `fillColor "#FFFFFF"` → still closed+filled. This **aligns** the two renderers (today CG never strokes freeform and SK always does); CG-rendered legacy freeforms gain the stroke SK already showed — record as a note, not a regression.

### 5.3 Flush lifecycle

The active stroke accumulator opens at the first pen-down movement and flushes (emits a part, if ≥ 2 vertices and non-zero length) on: `penUp` · pen color/width **change** · `beginFill` · `clean`/`clearScreen`/`reset turtle` · any card navigation (`go`) · **end of the top-level run**. End-of-run flush is what makes the message box a live REPL: type `forward 100`, see the line.

An unclosed `beginFill` at end of run emits nothing and sets `the result` to E7.

### 5.4 Curve approximation (exact, testable)

Segments n = max(8, ceil(|deg| / 6)); full circle = 60 segments. Chord error = r·(1 − cos(3°)) ≈ 0.00137·r — under 0.14 pt at r = 100, invisible at any stroke width. Vertices are computed from the turtle's position, radius, and start angle = heading; circle's last vertex equals its first exactly.

### 5.5 Limits (shared by both surfaces, enforced in the engine)

One run may emit at most **200 parts** and **50,000 total path points**. Exceeding → error E8, run stops, already-emitted parts remain (visible, honest partial state).

### 5.6 Deferred raster mode (seam)

If a "paint mode" is ever wanted, it is a turtle setting that routes segments through the existing `DrawingProvider.drawLine` instead of the accumulator. Not in v1; do not build the switch.

### 5.7 Named colors (system-wide, owner: Architect, in this change)

Extend `HexColor.normalized(_:)` with a fixed case-insensitive table resolving to hex: `black, white, red, green, blue, yellow, orange, purple, pink, brown, gray (grey), cyan, magenta, lime, navy, teal`. Every color-kind property on every surface gains them uniformly (additive: previously-invalid input becomes valid; nothing renderable changes meaning). If the Architect finds a `decisions.md` guardrail forbidding this, fallback is name resolution at the turtle seam only — but the shared table is the right home.

## 6. States

- **First run / empty**: pen-up movement, `arc 0, r`, `clean` on a clean card — all quiet no-ops. No part, no error, `the result` empty. Success is silent (HyperCard voice).
- **Off-canvas**: allowed; parts may lie partly or fully outside card bounds like any part. Frame math unchanged.
- **Errors** — engine-owned strings, byte-identical on both surfaces (registry copy style: lowercase start, quoted input, em-dash guidance):
  - E1 `turtle: "blurple" isn't a color — use #RRGGBB, #RRGGBBAA, or a name like red, blue, orange.`
  - E2 `turtle: circle needs a radius greater than 0 (got -5).` (same shape for `arc`, `dot`)
  - E4 `turtle: already filling — call endFill before starting another fill.`
  - E5 `turtle: endFill without beginFill — nothing to fill.`
  - E6 `turtle: fill needs at least 3 points — nothing drawn.` (via `the result`, not a script error)
  - E7 `turtle: beginFill was never closed — no fill drawn.` (via `the result`)
  - E8 `turtle: drawing limit reached — a single run may draw at most 200 shapes and 50000 points.`
  - E9 (AI tool only) `turtle: line 4 isn't a turtle command ("go next card") — draw_with_turtle accepts only turtle commands and repeat loops.`
  - E1–E5, E8 are script errors (`ScriptError`) in HypeTalk and the same text as the tool result string in the AI surface.

## 7. AI tool surface — one vocabulary, two front-ends

### 7.1 Tool

`draw_with_turtle` in `HypeToolDefinitions.allTools` (authoring catalog), executed in `HypeToolExecutor`:

- `program` (string, **required**): newline-separated turtle commands in the exact HypeTalk vocabulary of §4 (including abbreviations, property sets on `the turtle`, and `--` comments), plus `repeat N times … end repeat` / `repeat with i = a to b … end repeat` loops (nestable; total iterations capped by the §5.5 point/part limits). Nothing else — any other statement refuses with E9 naming the first offending line, and **no parts are created** (all-or-nothing validation before execution, mirroring the script-draft refusal gate).

Description text (discovery): "Draw vector graphics on the current card with the classic Logo turtle. Pass a program of turtle commands, one per line — forward/back, right/left, setHeading, setPos, home, penUp/penDown, setPenColor, setPenWidth, setFillColor, beginFill/endFill, circle, arc, dot, clean, clearScreen — plus repeat loops. Same commands and semantics as HypeTalk's turtle; heading 0 points up, degrees clockwise, card coordinates. Output becomes editable freeform shape parts named 'turtle path N' / 'turtle fill N'."

Result (success): a compact text summary in the executor idiom —
`Drew 3 shapes on card "Garden": turtle path 1 (5 points), turtle fill 1 (4 points), turtle dot 1. Turtle at 400,180 heading 90, pen down.`

Result (error): the engine's error string verbatim (E1–E9).

### 7.2 Mechanism (unification requirement)

The tool **parses `program` with the real HypeTalk parser**, validates the statement allowlist, and executes against the **same TurtleEngine and part-emission code** the interpreter uses. One engine, two thin front-ends — no parallel geometry implementation anywhere. The tool mutates `document` through the same `inout HypeDocument` path as every other mutating tool, so the existing preview/apply/undo behavior of AI mutations applies unchanged.

### 7.3 Catalog placement and safety boundary

- **Authoring catalog: yes.** Gated like all authoring AI mutation (userLevel gates the AI authoring surface per `decisions.md`).
- **RuntimeAIToolCatalog (deployed runtime): no, v1.** Runtime tools mutate runtime state only; the turtle mutates the document. Adding it later means a `documentMutation` side-effect tier — out of scope, seam noted.
- Bounded verbs: the allowlist means the AI gets no file, network, navigation, or script-attachment access through this tool. Program capped at 64 KB (the `menuItems` cap precedent).

### 7.4 Discovery parity

- `HypeTalkGuide.swift` gains a "Turtle graphics" section documenting §4 verbatim (same tables, same defaults, same error copy).
- `list_hypetalk_skills` gains skill id `turtle-graphics`; `get_hypetalk_skill_guide` returns the focused guide.
- `HypeTalk-LLM-Context.md` updated in the Documentation phase.

## 8. Onboarding example — "Turtle Garden" (Tester/Docs artifact)

One card, one button `Draw Garden`, script:

```
on mouseUp
  reset turtle
  clearScreen

  -- 1. a blue square, drawn the classic way
  setPenColor "blue"
  setPenWidth 3
  penUp
  setPos 200, 380
  penDown
  repeat 4 times
    forward 120
    right 90
  end repeat

  -- 2. a filled triangle (fill + outline from one beginFill/endFill)
  penUp
  setPos 420, 380
  setPenColor "black"
  setFillColor "orange"
  penDown
  beginFill
  repeat 3 times
    forward 130
    right 120
  end repeat
  endFill

  -- 3. a twelve-circle flower
  penUp
  home
  setPenColor "purple"
  setPenWidth 2
  repeat 12 times
    forward 45
    penDown
    circle 22
    penUp
    back 45
    right 30
  end repeat

  -- 4. a square spiral
  penUp
  setPos 620, 200
  setHeading 0
  setPenColor "teal"
  penDown
  repeat with i = 1 to 40
    forward i * 3
    right 91
  end repeat
  penUp
end mouseUp
```

The same program body (inside `on mouseUp`… stripped) is the canonical `draw_with_turtle` test payload. Message-box REPL demo: type `forward 100` then `rt 90` then `forward 100` — two parts appear, one per run, proving end-of-run flush and cross-run state.

## 9. Accessibility and existing-language reuse

- Turtle output is **ordinary shape parts** — it inherits selection, inspector, `get_card_parts`, HypeTalk property access, persistence, export, and the shape parts' existing accessibility representation. No new widget, no new part type, no animation (hence no reduce-motion path needed in v1).
- Part names (`turtle path 1`) are the parts' accessible identity — never emit unnamed parts.
- The example stack uses no color-alone meaning; error copy is text, surfaced through the existing script-error channel.

## 10. Acceptance criteria (Architect plans to these; Tester verifies these)

**Semantics**
1. From defaults on an 800×600 stack: `forward 100` moves the turtle from (400,300) to (400,200); with pen down, end of run emits one `.freeform` part with `pathData == [(400,300),(400,200)]`, `strokeColor "#000000"`, `strokeWidth 2`, `fillColor ""`.
2. `right 90` then `forward 100` from home moves to (500,300); `left 90` inverts; `setHeading 270; forward 100` moves to (300,300). `the heading of the turtle` after `right 450` is `90`.
3. `back n` ≡ `forward -n`; `home` with pen down draws a segment to (400,300) and sets heading 0; `setPos 10, 20` with pen up draws nothing and `the position of the turtle` returns `"10,20"`.
4. `penUp`/`pu`, `penDown`/`pd`, and all §4 abbreviations parse and behave identically to their long forms.
5. `repeat 4 times / forward 120 / right 90 / end repeat` from a pen-down start yields ONE part with exactly 5 vertices, first == last, forming a 120-pt square.

**Output contract**
6. A pen-color or pen-width change mid-trail splits the trail: `forward 50 / setPenColor "red" / forward 50` emits two parts with the respective colors.
7. Part frames: for every emitted part, `left/top/width/height` equal the tight `pathData` bounds padded by `strokeWidth/2` per side; parts land on the current card with unique names per §5.1's smallest-free-N rule.
8. `beginFill / repeat 3 [forward 130, right 120] / endFill` with pen down emits exactly ONE `.freeform` part: `fillColor` = turtle fill color, `strokeColor`/`strokeWidth` = pen state, 4 vertices; the same with pen up emits `strokeWidth 0`. Movement inside a fill span adds **no** separate stroke part.
9. `circle 50` emits one 61-vertex part whose first and last vertices are identical and whose vertices all lie within 0.07 pt of the radius; `arc 90, 50` emits max(8, ceil(90/6)) = 15 segments (16 vertices); neither moves the turtle. `dot 10` emits an `.oval` part 10×10 centered on the turtle with `fillColor` = pen color.
10. Renderer parity: a stroke part (`fillColor ""`) renders as an **open, stroked, unfilled** polyline in both `ShapeRenderer` (CG) and `ShapePartNode` (SK); a fill part renders closed+filled+outlined in both. Existing freeform parts (`fillColor "#FFFFFF"`) still render closed+filled.

**State, persistence, round-trip**
11. Scalar turtle state survives across separate runs in one session (two message-box commands continue one walk; each run flushes its own part), and resets to defaults on stack open. `reset turtle` restores defaults without deleting parts; `clean` deletes exactly the `turtle path`/`turtle fill`/`turtle dot`-prefixed parts on the current card; `clearScreen` additionally homes without drawing.
12. All eight properties in §4.6 read correctly after any command sequence, and every settable one round-trips (`set the heading of the turtle to 45` ≡ `setHeading 45`, etc.).
13. Save → reload `.hype`: turtle-drawn parts re-render identically (same `pathData`, colors, frames) with **no document-version bump required**.
14. Dragging a turtle-drawn part in edit mode moves the visible drawing with the frame (the freeform `pathData`/frame translation contract — Architect resolves the latent offset behavior in `ShapePartNode.updateFromPart` for moved freeform parts).

**Errors**
15. `setPenColor "blurple"` raises E1 verbatim and leaves pen state unchanged; `circle 0`, `arc 90, -1`, `dot 0` raise E2; `beginFill` twice raises E4; bare `endFill` raises E5; a 2-point fill sets `the result` to E6 and emits nothing; exceeding §5.5 limits raises E8 with already-emitted parts intact. `setPenWidth 500` clamps to 100 silently; `forward "banana"` coerces to 0 and is a quiet no-op.

**AI surface + equivalence**
16. `draw_with_turtle` with the §8 program creates the same parts on the current card and returns a summary naming each part; the tool appears in `HypeToolDefinitions.allTools` with the §7.1 description; it is absent from `RuntimeAIToolCatalog`.
17. A program containing any non-turtle statement (e.g. `go next card`) refuses with E9 naming the line, and creates **zero** parts.
18. **Cross-surface equivalence (key invariant):** the identical program executed (a) as a HypeTalk handler and (b) via `draw_with_turtle` produces parts with byte-identical `pathData`, `shapeType`, `fillColor`, `strokeColor`, `strokeWidth`, frames, and names (ids/sortKeys excepted); and the identical invalid input (`setPenColor "blurple"`) produces the identical error string on both surfaces. One named test: `TurtleCrossSurfaceEquivalenceTests`.
19. Named colors resolve identically everywhere: `setPenColor "red"`, `set the fillColor of shape "x" to "red"`, and `set_part_property fill_color=red` all store `#FF0000` (the `HexColor` table is the single source).
20. `InterpreterFuzzTests` grammar is extended with the turtle statement family (all verbs, abbreviations, property sets) and stays green; the metamorphic suite gains at least one turtle relation (e.g. `right d` then `left d` restores heading; `fd n / bk n` restores position).

## 11. Notes and conditions for the Architect

- **No document-format change**: no new `PartType`, no `PathPoint` extension, no version bump. The only model-adjacent changes are the `.freeform` render contract (§5.2, both renderers, identical) and the `HexColor` name table (§5.7).
- **One engine**: a `TurtleEngine` (pure, `Sendable`, in HypeCore) owns state, geometry, flushing, limits, and every error string. Interpreter statements and `draw_with_turtle` are thin callers. Any second geometry implementation is a design-review FAIL.
- Parser: turtle verbs should parse without new reserved lexer keywords where feasible (the external-command/identifier path shows the pattern); `reset turtle` extends the existing `resetCmd`. Architect owns the mechanism; the surface in §4 is the contract.
- The `turtle` object joins `the <prop> of the turtle` resolution; keep alias symmetry and, where sensible, register through `PartPropertyRegistry`'s conventions for copy consistency (the turtle is not a Part; a small parallel resolver with the same error-copy style is acceptable — flag in design review if copy diverges).
- Files this design expects to touch (manifest seed): `AST.swift`, `Parser.swift`, `Interpreter.swift`, new `TurtleEngine.swift`, `ShapeRenderer.swift`, `ShapePartNode.swift`, `HexColor.swift`, `HypeTools.swift`, `HypeToolExecutor.swift`, `HypeTalkGuide.swift`, plus tests (`TurtleEngineTests`, `TurtleCrossSurfaceEquivalenceTests`, fuzz-grammar extension).

**Design Mock: complete.** This spec is the contract for Architecture; criteria 1–20 are the Design Sign-off checklist.

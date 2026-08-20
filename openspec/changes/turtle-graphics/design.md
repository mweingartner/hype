# Design: Turtle Graphics for HypeTalk

## Actor

Architect — Fable (`claude-fable-5`), delegated subagent in the mpd pipeline.

## Context

This file is the canonical current-state contract. It plans against the
Designer's decisive spec `design-mock.md` (rulings R1–R12, acceptance
criteria 1–20) and the code as read on 2026-08-19. Line numbers cite the
current files and will drift; the cited anchors (case labels, function
names) are the contract.

Grounding facts verified in code:

- Turtle-like verbs already parse: an identifier followed by an argument
  token parses as `.externalCommand` (`shouldParseExternalCommandStatement`,
  `Parser.swift:438–459`); execution order in the interpreter is
  user-handler dispatch → classic builtins → external registry
  (`Interpreter.swift:2356–2426`). Bare zero-argument identifiers only parse
  as commands when listed in `isKnownZeroArgumentExternalCommand`
  (`Parser.swift:461`).
- Session persistence across runs exists via `document.scriptGlobals`
  (seeded into `Environment` per run, written back after every statement and
  at run end; `Interpreter.swift:616, 881, 740`). It is deliberately
  excluded from document coding (`HypeDocument.swift:60–64, 109, 139`) and
  keys must be all-lowercase (`Interpreter.messageBoxKey` precedent,
  `Interpreter.swift:576–581`).
- `the <prop> of the turtle` arrives as target expression
  `.propertyAccess("turtle", nil)` on both the GET path
  (`evaluateProperty`, `Interpreter.swift:5263`) and the SET path
  (`case .set`, `Interpreter.swift:1380`). There is no `turtle` case in the
  global-property switch — no collision.
- `reset` parses any trailing expression (`Parser.swift:2358`); evaluating
  the bare word `turtle` yields `""`, so the exec-side match must use the
  variable-name fallback idiom (`evaluateNavigationExpression`,
  `Interpreter.swift:6834`).
- Number/truthiness canon: `toNumber = Double(v) ?? 0`
  (`Interpreter.swift:8735`), `formatNumber` drops `.0`
  (`Interpreter.swift:8755`), `isTruthy` = "true" or non-zero number
  (`Interpreter.swift:8769`), `clampedInt` (`Interpreter.swift:8743`).
- Part creation canon: `Part` defaults `fillColor "#FFFFFF"`, `sortKey "a0"`
  (`Part.swift:442–494`); the next-part-sortKey path is
  `nextPartSortOrdinal()` → `String(format: "a%06d", n)`
  (`PartDuplication.swift:106`, currently `private`).
- Renderer discord confirmed and worse than the mock states: the CG
  freeform path fills-never-strokes AND renders `pathData` vertically
  mirrored with absolute x (`ShapeRenderer.swift:100–109`, the
  "approximate" `canvasHeight`); the SK path strokes+fills and re-derives
  its local path from absolute `pathData` on every update so a moved frame
  cancels out (`ShapePartNode.swift:54–74`) — the criterion-14 latent
  offset. A third freeform renderer exists in the export runtime
  (`TargetRuntimeControlViews.swift:1291`, closed+filled+scaled).
- `HexColor.normalized` is the single color gate with two error-copy call
  sites (`Interpreter.swift:7493`, `HypeToolExecutor.swift:2121`). There is
  no `decisions.md` guardrail against a name table; the standing constraint
  is `openspec/specs/part-properties/spec.md:86`, modified by this change's
  part-properties delta. The chart carve-out (`ChartConfig.normalizedHex`)
  stays.
- Executor idiom: `HypeToolExecutor.execute(toolName:arguments:document:
  currentCardId:) async -> String`; mutating tools mutate `inout` and
  return plain text; refusals return without mutating
  (`HypeToolExecutor.swift:1103–1266`). Curated catalogs that include
  `create_shape`: `cardControlAuthoringTools` (`HypeTools.swift:2102`) and
  `spriteSceneAuthoringTools` (`HypeTools.swift:2235`);
  `RuntimeAIToolCatalog.defaultTools` is a separate list — absence is the
  default.
- `ScriptError` results carry no `modifiedDocument`
  (`Interpreter.swift:724–725`); in the app, partial mutations survive an
  error only through the per-statement `publishDocument` channel
  (`Interpreter.swift:891–894`). Small test doubles for
  `ScriptRuntimeProviding` are an established pattern
  (`InterpreterPublishGatingTests.swift:9`).

## Goals / Non-Goals

**Goals:** everything in design-mock §§4–7 and criteria 1–20; one engine;
no document-format change; no new lexer keywords; fuzz + metamorphic
coverage per AGENTS.md.

**Non-Goals:** visible turtle cursor (R7), raster paint mode (§5.6),
`goto` (R8), runtime-catalog exposure (§7.3), export-runtime freeform
alignment (deferred, see Deviations), `HypeTalk-LLM-Context.md` prose
(Documentation phase), chart-color named-color support (standing carve-out).

## Decisions

### D1. TurtleEngine — pure value engine, return-based emission

New file `Sources/HypeCore/Script/TurtleEngine.swift`. Imports Foundation
only (uses the `PathPoint` model from the same module). No document
knowledge, no providers, no actors.

```swift
public struct TurtleEngine: Sendable {
    public struct Canvas: Sendable, Equatable {
        public var width: Double
        public var height: Double
        public init(width: Double, height: Double)
    }

    /// Scalar state — the only thing that survives a run (R6).
    public struct ScalarState: Sendable, Equatable {
        public var x: Double, y: Double, heading: Double
        public var penDown: Bool
        public var penColor: String     // normalized "#RRGGBB[AA]"
        public var penWidth: Double     // clamped [0.5, 100]
        public var fillColor: String
        public static func defaults(canvas: Canvas) -> ScalarState
        /// "v1|x|y|heading|penDownFlag|penWidth|penColor|fillColor";
        /// numbers via String(Double) (full precision), flag "1"/"0".
        public var encoded: String { get }
        public init?(encoded: String)   // nil on malformed → caller uses defaults
    }

    public enum Command: Sendable, Equatable {
        case forward(Double), back(Double), right(Double), left(Double)
        case setHeading(Double), setPos(x: Double, y: Double), home
        case penUp, penDown
        case setPenColor(String), setPenWidth(Double), setFillColor(String)
        case beginFill, endFill
        case circle(radius: Double), arc(degrees: Double, radius: Double)
        case dot(diameter: Double?)     // nil → default max(2*penWidth, 4)
        case clean, clearScreen, resetTurtle
    }

    public struct FrameRect: Sendable, Equatable {
        public var left, top, width, height: Double
    }

    public struct Emission: Sendable, Equatable {
        public enum Kind: String, Sendable { case path, fill, dot }
        public var kind: Kind
        public var pathData: [PathPoint]      // absolute card coords; empty for .dot
        public var frame: FrameRect           // §5.1 math, computed by the engine
        public var fillColor: String          // "" for stroke parts
        public var strokeColor: String
        public var strokeWidth: Double
    }

    public struct Outcome: Sendable {
        public var emissions: [Emission]
        public var deletesTurtleParts: Bool   // clean / clearScreen
        public var resultNote: String?        // E6 / E7 → `the result`
        public static let empty: Outcome
    }

    /// LocalizedError with errorDescription == message (PartPropertyError
    /// precedent, PartPropertyRegistry.swift:811) so the message survives
    /// any generic catch byte-identically.
    public struct TurtleError: Error, LocalizedError, Sendable, Equatable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static let sessionGlobalKey = "__turtle"   // MUST stay lowercase
    public static let maxPartsPerRun = 200
    public static let maxPathPointsPerRun = 50_000
    public static let positionLimit: Double = 1_000_000

    public init(canvas: Canvas, restoring: ScalarState?)  // nil → defaults
    public var scalarState: ScalarState { get }
    public var isFilling: Bool { get }
    public var hasOpenStroke: Bool { get }

    /// Throws TurtleError for E1, E2, E4, E5, E8. A command either fully
    /// emits or throws with state unchanged (atomic per command).
    public mutating func perform(_ command: Command) throws -> Outcome
    /// End-of-run / navigation flush: emits the open stroke (≥2 vertices,
    /// non-zero length), discards an open fill with resultNote E7. Never
    /// throws; the final flush may emit even at the part cap (bounded +1).
    public mutating func endRun() -> Outcome
    /// §4.6 property surface. GET: unknown name → TurtleError.
    public func propertyValue(_ name: String) throws -> String
    /// SET: read-only / unknown / invalid value → TurtleError; position and
    /// pen sets reuse the corresponding Command paths.
    public mutating func setProperty(_ name: String, to value: String) throws -> Outcome
}
```

**Error copy — single owner.** `TurtleEngine.ErrorCopy` (internal enum of
static formatters) holds every string; nothing else may compose turtle error
text. Exact strings (raw user input capped at 200 chars, registry
precedent):

- E1 `turtle: "<input>" isn't a color — use #RRGGBB, #RRGGBBAA, or a name like red, blue, orange.`
- E2 `turtle: circle needs a radius greater than 0 (got <n>).` /
  `turtle: arc needs a radius greater than 0 (got <n>).` /
  `turtle: dot needs a diameter greater than 0 (got <n>).` (`<n>` via
  `HypeTalkFormat.number`)
- E4 `turtle: already filling — call endFill before starting another fill.`
- E5 `turtle: endFill without beginFill — nothing to fill.`
- E6 `turtle: fill needs at least 3 points — nothing drawn.` (resultNote)
- E7 `turtle: beginFill was never closed — no fill drawn.` (resultNote)
- E8 `turtle: drawing limit reached — a single run may draw at most 200 shapes and 50000 points.`
- E9 `turtle: line <N> isn't a turtle command ("<line text>") — draw_with_turtle accepts only turtle commands and repeat loops.`
- Property copy (registry style, new — Deviations d14):
  `"<name>" of the turtle is read-only — set the position instead.` (xcor,
  ycor), `"filling" of the turtle is read-only — use beginFill and endFill.`,
  `no such property "<name>" for the turtle — the turtle has position, xcor,
  ycor, heading, penDown, penColor, penWidth, fillColor, and filling.`
- Tool-only size cap (not an E-number):
  `turtle: program is too large — the limit is 65536 bytes.`

**Geometry (exact, testable):**

- Input hygiene: every numeric argument passes `toFinite` (non-finite → 0)
  then command-specific rules; positions clamp to ±1,000,000.
- Heading: `normalize(h) = ((h mod 360) + 360) mod 360` via
  `truncatingRemainder`.
- Movement: `dx = n·sinDeg(h)`, `dy = −n·cosDeg(h)` with **exact-cardinal
  snapping**: when `normalize(h)` is exactly 0/90/180/270, `sinDeg/cosDeg`
  return table values {0, ±1}. This makes criterion 5's `first == last`
  square exact and criterion 1's (400,300)→(400,200) exact; all other
  headings use `sin/cos` of `h·π/180`.
- Buffering: pen down & not filling → open the stroke buffer with the
  pre-move position if empty, append the post-move point when it differs
  from the last buffered point. Filling → append to the fill polygon
  (regardless of pen state — Deviations d6). Pen up & not filling → move
  only.
- `circle r`: r ≤ 0 → E2. 60 segments, 61 vertices centered on the turtle;
  vertex i at angle `heading + i·6°`:
  `(x + r·sinDeg(a), y − r·cosDeg(a))`; vertex 60 is copied from vertex 0
  (exact closure). Emitted immediately as a stroke emission (fill "" ), or
  appended to the fill polygon when filling. Turtle does not move.
- `arc deg, r`: r ≤ 0 → E2; deg clamps to [−360, 360]; deg == 0 → quiet
  no-op. `n = max(8, Int(ceil(|deg|/6)))`, vertices i in 0...n at
  `heading + sign(deg)·|deg|·i/n`. Same emission rule as circle
  (fills feed the polygon — Deviations d4). Turtle does not move.
- `dot d?`: omitted d → `max(2·penWidth, 4)` (never errors); explicit
  d ≤ 0 → E2. Emission kind `.dot`: empty pathData, frame
  `(x−d/2, y−d/2, d, d)`, `fillColor` = pen color, `strokeColor` = pen
  color, `strokeWidth 0`. Emits even with pen up and even mid-fill
  (Deviations d5).
- Pen/fill state: `setPenColor`/`setFillColor` route through
  `HexColor.normalized`; nil **or empty** → E1 (the "" auto sentinel is not
  a pen color — Deviations d7); an actual value change of pen color/width
  flushes the open stroke first. `setPenWidth` clamps [0.5, 100].
- `beginFill`: filling → E4; else flush open stroke, start polygon at the
  current position. `endFill`: not filling → E5; fewer than 3 *distinct*
  vertices → no emission, resultNote E6; else one `.fill` emission
  (vertices as buffered — no synthetic closing vertex; renderers close).
- `clean`: `deletesTurtleParts = true`, discard both buffers (emit-then-
  delete ≡ discard — Deviations d3). `clearScreen`: clean + home without
  drawing (position = center, heading = 0). `resetTurtle`: discard buffers,
  scalar state = defaults; no deletion.
- Limits: counters per engine instance (= per run). Every vertex appended
  to any buffer or emission counts toward 50,000; every emission counts
  toward 200. A command that would exceed either throws E8 atomically.
- Frame math (stroke/fill): `pad = strokeWidth/2`;
  `left = minX − pad`, `top = minY − pad`,
  `width = max(1, (maxX − minX) + 2·pad)`, `height = max(1, …)`.

### D2. HypeTalkFormat — one number/truth canon

New file `Sources/HypeCore/Script/HypeTalkFormat.swift`:

```swift
public enum HypeTalkFormat {
    public static func number(_ n: Double) -> String      // body moved from Interpreter.formatNumber
    public static func number(from value: String) -> Double  // Double(value) ?? 0
    public static func isTruthy(_ value: String) -> Bool  // body moved from Interpreter.isTruthy
}
```

`Interpreter.formatNumber`, `Interpreter.toNumber`, and
`Interpreter.isTruthy` become one-line delegations (byte-identical
behavior); the engine and executor summary use `HypeTalkFormat` so
formatting can never fork. `HypeToolExecutor`'s existing private
`formatNumber` is out of scope.

### D3. TurtleVocabulary — shared verb recognition

In `TurtleEngine.swift`:

```swift
public enum TurtleVocabulary {
    /// verb must be lowercased. Accepts ≥ required arg count (extras
    /// ignored, HyperCard tolerance); missing numeric args coerce to 0.
    public static func command(verb: String, args: [String]) -> TurtleEngine.Command?
    public static func isTurtleVerb(_ lowercasedVerb: String) -> Bool
    public static let zeroArgumentVerbs: Set<String>
        // ["penup","pendown","pu","pd","home","beginfill","endfill",
        //  "clean","clearscreen","cs","dot"]
}
```

Verb map: forward/fd, back/bk, right/rt, left/lt, setheading/seth,
setpos/setxy (2 numeric args), home, penup/pu, pendown/pd, setpencolor,
setpenwidth/setpensize, setfillcolor, beginfill, endfill, circle, arc
(2 args), dot (0 or 1), clean, clearscreen/cs. (`reset turtle` is not here —
it rides the existing `resetCmd`.)

### D4. TurtlePartApplier — the one document mutation path

New file `Sources/HypeCore/Script/TurtlePartApplier.swift`:

```swift
public enum TurtlePartApplier {
    public static let namePrefixes = ["turtle path", "turtle fill", "turtle dot"]
    /// Deletions first (when outcome.deletesTurtleParts): every part on
    /// `cardId` whose name has one of the prefixes, removed via
    /// document.deletePart(id:) (constraint cleanup). Then each emission
    /// becomes a Part: partType .shape; shapeType .freeform (path/fill) or
    /// .oval (dot); name "<prefix> N" with N = smallest positive integer
    /// whose exact name "<prefix> N" is unused on that card (recomputed per
    /// emission); sortKey = String(format: "a%06d", document.nextPartSortOrdinal());
    /// cardId; frame/pathData/colors/width from the emission; other fields
    /// Part-init defaults. Returns the appended parts in order.
    @discardableResult
    public static func apply(_ outcome: TurtleEngine.Outcome,
                             to document: inout HypeDocument,
                             cardId: UUID) -> [Part]
}
```

Supporting one-word change: `nextPartSortOrdinal()` in
`Sources/HypeCore/Models/PartDuplication.swift:106` goes `private` →
`internal` (same module; no API surface change).

### D5. Parser — three vocabulary-gated extensions, no new tokens

`Sources/HypeCore/Script/Parser.swift`:

1. `isKnownZeroArgumentExternalCommand` (line 461): also return true when
   `TurtleVocabulary.zeroArgumentVerbs.contains(normalizedExternalCommandName(rawName))`.
2. `isKnownExternalCommand` (line 472): also true for
   `TurtleVocabulary.isTurtleVerb(...)` (covers `forward(100)`).
3. `shouldParseExternalCommandStatement` (line 438): add one case — when
   `next.type == .minus`, return `TurtleVocabulary.isTurtleVerb(current.value.lowercased())`
   — so `forward -50` / `arc -90, 50` parse as commands while every other
   `identifier - expr` line keeps its existing expression parse.

`parseResetStatement` and `AST.swift` are untouched.

### D6. Interpreter integration (all inside Interpreter.swift; leaf helpers)

Because `executeStatement`'s frame size is a known hazard (see the
chart-data-point comment at `Interpreter.swift:1384–1392`), all turtle work
lives in private leaf helpers; the switch cases gain only thin calls.

1. `Environment` (~line 360): add `var turtle: TurtleEngine? = nil`.
2. New helpers (`// MARK: - Turtle graphics`):
   - `private func turtleEngine(env: inout Environment, document: HypeDocument) -> TurtleEngine`
     — returns `env.turtle` or creates one from
     `ScalarState(encoded: env.globals[TurtleEngine.sessionGlobalKey] ?? "")`
     (malformed/absent → defaults) with
     `Canvas(width: Double(document.stack.width), height: Double(document.stack.height))`.
   - `private func syncTurtle(_ engine: TurtleEngine, env: inout Environment)`
     — `env.turtle = engine; env.globals[key] = engine.scalarState.encoded`
     (the existing per-statement `document.scriptGlobals = env.globals`
     at line 881 persists it).
   - `private func applyTurtleOutcome(_ outcome:, env: inout Environment,
     document: inout HypeDocument, context:) `— applies via
     `TurtlePartApplier.apply` on
     `env.currentCardId(fallback: context.currentCardId)`; sets
     `env.result` when `resultNote` present; calls
     `env.invalidatePartLookupCache()` when parts were added or deleted.
   - `private func executeTurtleCommand(_ cmd:, env:, document:, context:,
     handler:) throws` — `perform` → apply → sync; wraps `TurtleError` into
     `ScriptError(message: e.message, line: handler.line, handler: handler.name)`
     (message byte-identical).
   - `private func flushTurtleAtRunEnd(env:, document:, context:)` and
     `private func flushTurtleForNavigation(...)` — guard
     `env.turtle != nil` (zero cost otherwise) → `endRun()` → apply → sync.
3. `.externalCommand` (line 2356): after the `dispatchHandlerCommandIfAvailable`
   block (user handlers keep precedence) and before
   `handleClassicBuiltInCommand` (line 2381):
   `if let cmd = TurtleVocabulary.command(verb: normalizedName, args: args)
   { try executeTurtleCommand(...); break }`. (`args` are already evaluated
   with the bare-identifier→name fallback, so `setPenColor red` works.)
4. `.resetCmd` (line 3592): compute the target word with the
   empty-variable→name fallback; if it lowercases to `"turtle"` →
   `perform(.resetTurtle)` path; existing `ai session` branch unchanged.
5. `.set` (line 1380, top of the `if let targetExpr = target` block):
   `if case .propertyAccess(let obj, nil) = targetExpr, obj.lowercased() ==
   "turtle" { … engine.setProperty(property, to: value) … break }` —
   strictly the canonical `of the turtle` form (R12).
6. `evaluateProperty` (immediately after `let targetExpr = target!`,
   line 5263): same match → `engine.propertyValue(property)`; `TurtleError`
   propagates (LocalizedError carries the message into the generic
   ScriptError catch).
7. Run-end flush in `executeAsyncImpl`: call `flushTurtleAtRunEnd` in the
   `passMessage` (line ~704), `exitHandler` (~712), `showAllCards` (~721),
   and `CancellationError` (~727) catches and on normal completion
   (~739) — always before `document.scriptGlobals = env.globals`. The
   `ScriptError` catch is untouched (no document is returned there; parts
   already applied survive through the live `publishDocument` channel,
   matching app behavior).
8. Navigation flush: first line of `.go` (line 1656), `.goInStack`
   (line 1709), and `.pop` (line 3617) — flush to the departing card
   (Deviations d8).

Nested dispatches (`send`, implicit command handlers) are their own runs:
their flush emits their own part; scalar state round-trips through
scriptGlobals (Deviations d12).

### D7. AI front-end

**Validator** — new file
`Sources/HypeCore/Script/TurtleProgramValidator.swift`:

```swift
public enum TurtleProgramValidator {
    public static let maxProgramBytes = 64 * 1024
    public enum Verdict: Sendable {
        case ok([Statement])
        case refused(String)     // E9 text or the size-cap text
    }
    public static func validate(program: String) -> Verdict
}
```

Mechanism: byte-cap check → real `Lexer` (tokens carry line numbers) → real
`Parser.parseStatements()`. A `ParseError` refuses as E9 using the error
token's line and that source line's trimmed text. The parsed AST is then
walked against the structural allowlist **in lockstep with a token-segment
line cursor** (segments = token runs between `.newline` tokens; every
allowed construct is single-line-headed: simple statement = 1 segment,
`repeat …` header = 1, `end repeat` = 1), so the first offending statement
maps to an exact line. Allowlist:

- `.externalCommand(name:arguments:)` with `TurtleVocabulary.isTurtleVerb`
  and argument expressions from the allowed expression set;
- `.set(property:of:to:)` where `of` is the turtle form;
- `.resetCmd(expr)` where expr is the bare word / literal `turtle`;
- `.repeatCount` and `.repeatWith` (bodies validated recursively);
- allowed expressions (recursive): `.literal`, `.variable`,
  `.unary(.negate, _)`, `.binary` with arithmetic ops
  (+ − * / mod div ^), and `.propertyAccess(_, turtle-target)`.
  **`functionCall` is expressly disallowed** (a user function could smuggle
  arbitrary script into an argument); everything else refuses.

**Tool schema** — `HypeTools.swift`: `makeTool(name: "draw_with_turtle",
description: <§7.1 text verbatim>, params: ["program": ("string",
"Newline-separated turtle commands and repeat loops. Required.", true)])`
placed after `create_shape` in `allTools`; add `"draw_with_turtle"` to the
`cardControlAuthoringTools` and `spriteSceneAuthoringTools` allowlists
(both already include `create_shape`). `RuntimeAIToolCatalog` untouched.

**Executor** — `HypeToolExecutor.swift`, new
`case "draw_with_turtle":` delegating to a private helper:

```swift
private func executeDrawWithTurtle(program: String,
                                   document: inout HypeDocument,
                                   currentCardId: UUID) async -> String
```

Flow: validate (refusal returns the E9/cap string, zero mutation) →
snapshot existing part IDs → `Handler(name: "drawWithTurtle", handlerType:
.message, params: [], body: statements, line: 1)` →
`ExecutionContext(targetId: currentCardId, currentCardId: currentCardId,
document: document)` (stub providers, no runtime) →
`await Interpreter().executeAsync(...)`. On `.error` → return
`result.error!.message` verbatim, document untouched (all-or-nothing on
this surface — Deviations d2). On `.cancelled` → `"Turtle drawing was
cancelled."`. On `.completed` → `document = result.modifiedDocument ??
document`; new parts = parts on the current card whose id was not
snapshotted, in array order; summary:
`Drew <N> shapes on card "<name>": <part name> (<pathData.count> points),
…, <dot name>. Turtle at <x>,<y> heading <h>, pen <down|up>.` — dots listed
without a point count, numbers via `HypeTalkFormat.number`, state decoded
from `document.scriptGlobals[TurtleEngine.sessionGlobalKey]`, `N == 0`
phrased `Drew no shapes on card "<name>".`, a `resultNote` appended as a
final sentence, and an unnamed card rendered as `card <number>`
(Deviations d13). Handler shadowing (`on forward` in stack scripts)
applies identically on both surfaces — equivalence-preserving; noted for
Security.

### D8. Renderer alignment (§5.2 + criterion 14)

`Sources/HypeCore/Rendering/RenderGeometry.swift` gains the shared contract
(public, both modules use it):

```swift
public static func freeformIsOpenStroke(_ part: Part) -> Bool   // part.fillColor.isEmpty
/// pathData translated so its tight bbox, expanded by strokeWidth/2, sits
/// at (0,0) — y-down local coordinates. NaN-safe like safeRect.
public static func freeformLocalPoints(_ part: Part) -> [CGPoint]
```

`ShapeRenderer.draw` `.freeform` (lines 100–109, flipped CG context, frame
rect at `(part.left, part.top)`): draw local points at
`(rect.minX + p.x, rect.minY + p.y)` — no y-flip (fixes the mirroring);
open branch: no close, no fill, stroke when `strokeWidth > 0` with
`.round` cap/join; closed branch: `closePath`, fill, then stroke when
width > 0 (round join). `ShapePartNode.updateFromPart` `.freeform`
(lines 54–65): build the path from local points as `(p.x, −p.y)` (node
position stays `(left, −top)`); open branch sets `fillColor = .clear`, no
`closeSubpath`; closed branch closes and fills; both set
`lineCap = .round`, `lineJoin = .round`; `lineWidth = strokeWidth`
(stroke color `.clear` when width == 0 on the open branch to avoid SK's
default hairline). Because the applier writes frame = tight bounds + pad,
un-moved turtle parts render at exactly their absolute `pathData`; moved
parts translate rigidly with the frame in both renderers (criterion 14),
covering every move path (drag, arrows, inspector, HypeTalk) at once.
Anchor-to-frame is a one-time visual correction for legacy freeforms whose
frame had drifted from their path bounds — recorded as a note. 8-digit
`#RRGGBBAA` strokes keep the existing 6-digit `NSColor(hexString:)`
limitation shared by all shape types (pre-existing; not widened here).

### D9. HexColor name table (§5.7, R9)

`HexColor.normalized` (HexColor.swift:34): after the empty-string
passthrough, look up `trimmed.lowercased()` in a fixed table before the hex
path: black `#000000`, white `#FFFFFF`, red `#FF0000`, green `#008000`,
blue `#0000FF`, yellow `#FFFF00`, orange `#FFA500`, purple `#800080`,
pink `#FFC0CB`, brown `#A52A2A`, gray/grey `#808080`, cyan `#00FFFF`,
magenta `#FF00FF`, lime `#00FF00`, navy `#000080`, teal `#008080`.
Additive only; hex behavior and "" byte-identical; the two existing
error-copy call sites keep their current strings (Deviations d11); chart
paths untouched. The part-properties spec delta in this change records the
capability modification.

### D10. Discovery parity

`HypeTalkGuide.llmContext`: new `## Turtle graphics` section — vocabulary
tables condensed from §4, defaults, coordinate/heading rules, the part
contract and naming, the error copy, and the R12 pen-vs-pencil note.
`HypeTalkSkillCatalog`: new `case turtleGraphics = "turtle_graphics"`
(snake_case per catalog convention — Deviations d1), descriptor (triggers:
"turtle", "logo", "draw", "forward", "pen", "vector drawing"; related
tools: `draw_with_turtle`, `get_card_parts`, `check_script`), guidance
bullets, and one pattern (`turtle-square-flower`) using the §8 snippets.
`HypeTalk-LLM-Context.md`: Documentation phase.

## Risks / Trade-offs

- [Swift 6 concurrency] → engine is a `Sendable` value type; per-run
  instance lives in the interpreter's private `Environment`; cross-run
  state is a string inside the document value (`scriptGlobals`); no new
  shared mutable state, no locks, no `@MainActor`.
- [Interpreter hot path] → zero work when no turtle statement runs (one
  `env.turtle == nil` check per run end / navigation); all logic in leaf
  helpers to protect `executeStatement`'s frame (known recursion hazard).
- [Shared renderer change] → contract keyed on `fillColor == ""`, which no
  existing freeform-creation path produces (defaults `#FFFFFF`); no test
  asserts freeform pixels today; legacy CG mirroring fix and frame
  anchoring are one-time visual corrections, recorded as notes; new
  renderer tests pin both branches.
- [-Osize release config] → trivial trig per vertex, no generics/protocol
  fan-out; nothing measurable.
- [Parser grammar safety] → all three parser extensions are gated on the
  turtle vocabulary; the seeded fuzz suite must stay green and gains the
  turtle family.
- [Handler shadowing reaches the AI tool] → `on forward` in a stack script
  shadows the built-in on both surfaces (dispatch precedence,
  Interpreter.swift:2369). Equivalence-preserving; grants no authority
  beyond existing authoring tools; documented for the Security phase.
- [E8 partial state depends on the publish channel] → tests use a small
  capturing `ScriptRuntimeProviding` double (existing pattern); the AI
  surface is all-or-nothing (Deviations d2).

## Test plan (criteria 1–20 → files)

- `Tests/HypeCoreTests/TurtleEngineTests.swift` — criteria 1–3 (geometry),
  5 (square: one emission, 5 vertices, first == last via cardinal
  snapping), 6 (split on pen change), 7 (frame math), 8 (fill contract,
  pen-up → width 0, no stroke part mid-fill), 9 (61/16 vertices, radius
  tolerance 0.07, dot oval), 15 engine half (E1–E5 verbatim, clamps,
  coercions, E8 atomicity), state encoding round-trip, limits.
- `Tests/HypeCoreTests/TurtleScriptingTests.swift` — interpreter surface:
  criteria 1, 3, 4 (abbreviations), 11 (cross-run persistence via
  scriptGlobals; `reset turtle`; `clean` exactness incl. renamed-part
  survival; `clearScreen`), 12 (all eight property reads + settable
  round-trips + read-only errors), 13 (encode → decode `.hype`,
  re-render fields identical, `documentVersion` unchanged), 15 (E-strings
  through `ScriptError.message`; E6/E7 via `the result`; E8 partial parts
  via a capturing runtime double), navigation flush, REPL two-run walk,
  `on forward` shadowing.
- `Tests/HypeCoreTests/TurtleCrossSurfaceEquivalenceTests.swift`
  (criterion 18, mandatory) — §8 garden body on both surfaces from equal
  documents: part-by-part field equality (pathData, shapeType, colors,
  width, frames, names; ids/sortKeys excepted); identical E1 string both
  surfaces; plus criterion 16 (tool creates the parts, returns the naming
  summary, present in `allTools` with the §7.1 description, absent from
  `RuntimeAIToolCatalog`) and criterion 17 (E9 verbatim, zero
  parts, including `set the name of button 1 …` and `repeat while` shapes
  and the 64 KB cap).
- `Tests/HypeCoreTests/ShapeRendererFreeformTests.swift` +
  `Tests/HypeTests/ShapePartNodeFreeformTests.swift` — criterion 10 parity
  (open/unfilled vs closed/filled, round caps/joins, `#FFFFFF` legacy
  regression) and criterion 14 (frame moved +Δ → rendered geometry moves
  +Δ in both renderers).
- `Tests/HypeCoreTests/PartPropertyDispatchTests.swift` — criterion 19:
  `red` → `#FF0000` via `HexColor.normalized`, HypeTalk `set the
  fillColor`, and `set_part_property`; `grey` ≡ `gray`; garbage still
  errors; chart paths unchanged.
- `Tests/HypeCoreTests/InterpreterFuzzTests.swift` (criterion 20,
  mandatory) — grammar extension: turtle statement family (every verb and
  abbreviation, garbage/negative/huge arguments, unbalanced
  beginFill/endFill, property gets/sets, `clean`/`reset turtle`,
  repeat-wrapped) asserting **never crashes** and **deterministic** on
  fresh documents (compare part names + pathData + colors, not UUIDs).
  Metamorphic relations: `right d; left d` restores heading (exact);
  `fd n; bk n` restores position (≤ 1e−9); `right (d+360k)` ≡ `right d`;
  4×(fd L, rt 90) returns home with first == last; `clean` twice ≡ once.
  Standing invariants for the harness: heading ∈ [0,360); every emitted
  part carries a reserved-prefix name; all pathData finite and within
  ±1,000,000.
- `Tests/HypeCoreTests/HypeTalkGuideTests.swift` — guide contains the
  Turtle graphics section and every §4 verb; skill `turtle_graphics`
  listed; pattern resolves.

## Phasing for the Builder (each package ends `swift test` green)

- **P1 — engine + canon + colors:** `HypeTalkFormat.swift`;
  `TurtleEngine.swift` (+ `TurtleVocabulary`); `TurtlePartApplier.swift`
  (+ `nextPartSortOrdinal` visibility); `HexColor` name table;
  `TurtleEngineTests`; `PartPropertyDispatchTests` color additions.
  *Why first:* pure code, no integration risk; pins the engine contract
  and the color table the §8 program needs downstream.
- **P2 — HypeTalk surface:** Parser gates; all Interpreter integration
  (D6); `TurtleScriptingTests`; `InterpreterFuzzTests` extension.
  *Why second:* completes and hard-gates the language surface (AGENTS.md
  fuzz rule) before a second front-end exists.
- **P3 — AI surface:** `TurtleProgramValidator.swift`; tool schema +
  catalog allowlists; executor case; `TurtleCrossSurfaceEquivalenceTests`.
  *Why third:* thin caller over P2's proven path; equivalence test locks
  the two surfaces together.
- **P4 — renderers + discovery:** `RenderGeometry` helper; `ShapeRenderer`;
  `ShapePartNode`; renderer tests; `HypeTalkGuide` section;
  `HypeTalkSkillCatalog` skill; `HypeTalkGuideTests`.
  *Why last:* independent of the engine; isolates the one shared-surface
  rendering risk. (`HypeTalk-LLM-Context.md` remains for the Documentation
  phase.)

## Deviations and open rulings flagged for Design Review

- d1 Skill id `turtle_graphics` (catalog snake_case) instead of the mock's
  `turtle-graphics` literal.
- d2 AI surface is all-or-nothing for mid-run engine errors (E1–E8): a
  `ScriptError` result carries no document, so the tool mutates nothing on
  failure. §5.5's "already-emitted parts remain" holds on the HypeTalk
  surface via the live publish channel.
- d3 `clean`/`clearScreen`/`reset turtle` discard open buffers
  (reconciling §4.5 "discards" with §5.3's trigger list — emit-then-delete
  is indistinguishable from discard).
- d4 `arc` feeds the fill polygon while filling (parity with `circle`).
- d5 `dot` mid-fill emits its own part immediately.
- d6 While filling, movement feeds the polygon regardless of pen state;
  pen state at `endFill` decides the outline.
- d7 `setPenColor`/`setFillColor` reject `""` with E1 (the app-wide auto
  sentinel is not a pen color).
- d8 Navigation (`go`/`go … in stack`/`pop`) flushes the open stroke to
  the departing card and discards an open fill with resultNote E7.
- d9 The export-runtime freeform renderer
  (`TargetRuntimeControlViews.swift:1291`) still closes+fills+scales —
  outside §5.2's two-renderer ruling; deferred with the seam noted, or
  pulled in at review.
- d10 Bare `home` becomes the turtle command (user handlers still shadow;
  `go home` unchanged).
- d11 The two existing shared color error strings keep their current copy
  (no name mention); only the turtle's E1 mentions names.
- d12 A custom handler invoked mid-run is its own run boundary — its trail
  flushes as its own part.
- d13 Tool summary copy details (zero-shape phrasing, unnamed-card
  fallback, resultNote sentence) are Architect-authored, not in the mock.
- d14 Turtle property read-only/unknown error copy is new (registry
  style).

## Conditions for Builder

1. **One engine only.** All turtle geometry, state transitions, flush
   decisions, limits, and frame math live in `TurtleEngine`; the
   interpreter, executor, validator, and applier contain no coordinate
   math and no duplicated rules. Any second geometry implementation is a
   FAIL.
2. **No document-format change.** No new `PartType`, no `PathPoint`
   change, no coding-key additions (including `scriptGlobals`), no
   `documentVersion` bump.
3. **Error strings are engine-owned and byte-identical across surfaces.**
   Only `TurtleEngine.ErrorCopy` composes turtle error text; the
   interpreter wraps messages into `ScriptError` unaltered; the executor
   returns them verbatim. Tests assert full-string equality.
4. **AI allowlist is all-or-nothing before any mutation.** The 64 KB cap
   and `TurtleProgramValidator` run before any document access; a refusal
   or parse failure creates zero parts and performs zero mutation; E9
   names the first offending line. `functionCall` expressions never pass
   validation.
5. **`HexColor` change is strictly additive.** Existing hex acceptance,
   normalization, and the `""` sentinel are byte-identical; the two
   existing error-copy strings are unchanged; chart color paths
   (`ChartConfig.normalizedHex`, chart create/series colors) are
   untouched.
6. **Freeform render change keeps existing filled freeforms filled.**
   `fillColor` non-empty (including the `#FFFFFF` default) renders
   closed+filled in both renderers; only `""` renders open; caps/joins
   round; contract identical CG/SK via the shared `RenderGeometry` helper.
7. **Masking and script-gate surfaces untouched.** No changes to the
   script-draft refusal gate, MCP masking, secure-field handling, or
   `RuntimeAIToolCatalog`.
8. **Every emitted part is named per §5.1** (`turtle path N` /
   `turtle fill N` / `turtle dot N`, smallest free N per prefix per card)
   and lands on the current card at flush time with a
   `nextPartSortOrdinal` sortKey. Never emit an unnamed part.
9. **Session state lives only in
   `document.scriptGlobals["__turtle"]`** (all-lowercase key); buffers
   never survive a run; nothing turtle-related is ever encoded into the
   `.hype` file.
10. **Module boundaries:** `TurtleEngine.swift` imports Foundation (+
    same-module models) only — never the parser, interpreter, or
    executor; the validator may use Lexer/Parser; the applier may use
    HypeDocument/Part.
11. **Fuzz gate:** `InterpreterFuzzTests` stays green and gains the turtle
    grammar family plus at least the two mock-named metamorphic relations
    before P2 closes (AGENTS.md hard rule).
12. **Hot-path neutrality:** scripts that never touch the turtle incur at
    most one nil check per run end/navigation — no engine allocation, no
    extra scriptGlobals writes, no per-statement cost.

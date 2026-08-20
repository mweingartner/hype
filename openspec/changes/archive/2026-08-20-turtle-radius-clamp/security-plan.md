# Security review: turtle-radius-clamp (plan)

## Actor

Security (sonnet) — delegated persona, plan-review phase.

## Threat model

The credible trust boundary is not "engine vs. hostile network peer" —
it is "engine vs. two upstream producers of `Command` values that can
each emit an arbitrarily large finite `Double`": (1) a local HypeTalk
stack author, and (2) the `draw_with_turtle` AI tool, whose LLM-authored
program is only lexed/parsed/allowlist-walked
(`TurtleProgramValidator.swift`), never bounds-checked on literal
magnitude. Both are inside the app's existing local-trusted-user
perimeter — nothing here crosses a privilege, tenancy, or process
boundary; the failure mode this closes is a *robustness/consistency*
one (astronomically large finite geometry, not a crash, not code
execution, not data exposure).

I independently confirmed reachability rather than taking the design's
claim on faith: `TurtleProgramValidator.isAllowedExpression`
(`TurtleProgramValidator.swift:266-285`) accepts `.literal`
unconditionally (line 268-269) and — one notch beyond what design.md's
Context states — also accepts arbitrary `.binary` arithmetic
combinations of literals (`allowedArithmeticOps`, line 264: add,
subtract, multiply, divide, modulo, intDiv, power), recursively, at
every expression position the walk visits (external-command args, `set`
values, `repeatCount`/`repeatWith` bounds). So the reachable input isn't
just "a huge literal," it's "any huge value an allowed arithmetic
expression over literals can produce" (e.g. a literal raised to a
power). This doesn't weaken the fix: `clampRadius`/`clampDiameter`
clamp the resulting `Double` regardless of how it was constructed
upstream, so the wider reachability surface is still fully closed by a
single clamp at the shared engine. I also traced the call chain
confirming the program actually reaches `TurtleEngine.perform`:
`HypeToolExecutor.executeDrawWithTurtle` (`HypeToolExecutor.swift:5778`)
calls `TurtleProgramValidator.validate` (line 5784) and, on `.ok`, runs
the validated statements through the real `Interpreter`, which drives
`TurtleVocabulary.command`/`TurtleEngine.perform` — the same path
HypeTalk itself uses. `circle`/`arc`/`dot` are allowlisted verbs
(`TurtleEngine.swift:779`, `:786`).

Placing the clamp in the shared engine (not in the validator or either
front end) is the right layer: it is the one place both producers
funnel through, so one fix closes the gap for both without adding a
second copy of the rule (consistent with the engine's existing
single-owner discipline for `clampCoordinate`/`sanitizedNumber`/error
copy). The change is additive-only — two new `min()`-based upper
bounds — and introduces no new attack surface; confirmed by reading the
diff's shape in the design (no new inputs, no new outputs, no new
control paths, no I/O, no secrets/credentials anywhere in this file).

## Per-condition soundness (C1-C8)

**C1 — radius upper-bound-only, byte-identical error path.** Sound.
`clampRadius(r) = min(sanitizedNumber(r), positionLimit)` with
`positionLimit = 1_000_000 > 0`. For any `r ≤ 0`, `sanitizedNumber(r) =
r` (already finite input) and `min(r, 1_000_000) = r` since `r ≤ 0 <
1_000_000`. So the guard sees the identical raw value it sees today;
`min()` cannot alter which branch throws or the echoed `got:` value for
any non-positive input. Verified against the actual guard at
`TurtleEngine.swift:414`/`:420` and `ErrorCopy.needsPositiveRadius`
(`:226-228`).

**C2 — single owners, no forked logic.** Sound as specified: one
`clampRadius` call site for `.circle` (`:412-416`) and `.arc`
(`:418-424`), one `clampDiameter` call site for `.dot`'s explicit branch
(`:426-438`). Matches the existing single-owner pattern already used by
`clampCoordinate`/`ErrorCopy.needsPositiveRadius`/`needsPositiveDiameter`.

**C3 — finite-coercion precedes clamping; `min()` never sees NaN.**
Sound, and this is the condition that actually matters most. Swift's
generic `min<T: Comparable>(_:_:)` is `y < x ? y : x` — it has **no**
IEEE-754 minNum NaN-handling; `min(Double.nan, positionLimit)` returns
`Double.nan` (since `positionLimit < .nan` is `false`, so it falls
through to `x`). If a NaN radius/diameter ever reached `min()` directly,
the clamp would silently pass NaN through instead of bounding it. The
design avoids this entirely: `sanitizedNumber` runs as the *inner* call
(`min(sanitizedNumber(r), positionLimit)`), so NaN/±Infinity are
coerced to `0` before `min()` ever executes — `min()` only ever
receives already-finite arguments. A NaN/Inf radius still lands on
`r = 0`, still fails `r > 0`, still throws E2 with `got 0` exactly as
today. Confirmed by reading `sanitizedNumber` (`:656-658`,
`n.isFinite ? n : 0`) and the helper shape in design.md's Decision 2.

**C4 — no regression for in-range values.** Sound, and I checked it
against the actual test corpus rather than assuming: `min(x, limit) =
x` exactly (no rounding) whenever `x ≤ limit`, so every existing
circle/arc/dot test is byte-identical post-fix. Grepped
`TurtleEngineTests.swift` for every radius/diameter argument in use —
the property-test suite goes up to `r = 1000`
(`circleVerticesWithinTolerance`, `:708-726`) and `r = 400`
(`arc360EqualsCircle`, `:728-741`); nothing anywhere in the corpus
approaches `positionLimit` (1e6) or `2·positionLimit` (2e6). No existing
test exercises the boundary the clamp introduces, so C4 is safe but
also confirms the plan is right to require *new* tests for the clamped
region (covered by the manifest's test file).

**C5 — clamped-curve emission bound.** Sound on the pathData claim,
slightly loose on the frame claim. Center is always `≤ positionLimit`
in magnitude (enforced by `move`'s `clampPosition`/`clampCoordinate`,
`:557`, `:660`, `:664`, which run *before* any vertex is buffered or
state mutated — verified by reading `move`, `:556-582`); radius is now
`≤ positionLimit`. `vertexOnCircle` (`:707-710`) computes `center ±
radius·trig` with `|trig| ≤ 1`, so every pathData coordinate is bounded
by `2·positionLimit` — the arithmetic in the design is correct. The
condition's second clause, "the emission's frame is finite," is true
but weaker than what the Goals section actually promises ("frame ...
within ±2·positionLimit... + ≤ 50 stroke pad on path frames" — the pad
comes from `frame(for:strokeWidth:)`'s `strokeWidth/2` term at
`:759`/`:763-764`, and `strokeWidth` is itself capped at 100 by the
existing penWidth clamp, `:368`). This is a **documentation-precision
gap, not a soundness gap** — the tighter numeric bound is real and
derivable from already-verified facts, it's just not what C5 literally
says to assert. Recommend the Tester assert the frame bound explicitly
(`|frame edge| ≤ 2·positionLimit + 50`) rather than settling for
"finite," so the stronger guarantee in Goals is actually pinned by a
test, not merely implied.

**C6 — fill-mode curves covered.** Sound. `.circle`/`.arc` compute `r`
via `clampRadius` *before* calling `circlePoints`/`arcPoints`
(`:415`/`:423`), so the vertices passed into `emitCurve` (`:588`) are
already clamped whether or not a fill is open; `emitCurve`'s
fill-buffer branch (`:589-593`) appends those same (already-clamped)
points verbatim. No separate/duplicate geometry path exists for the
filling case, so C5's per-vertex bound transfers directly.

**C7 — E2 copy unchanged.** Sound — the plan does not propose editing
`ErrorCopy.needsPositiveRadius` (`:226-228`) or
`needsPositiveDiameter` (`:231-233`); only the value flowing into the
existing guards changes shape (via the new helpers), and C1/C3 already
establish that value is unchanged for every input that actually throws.

**C8 — dot upper-bound-only, default branch untouched, bounded frame.**
Sound by the same `min(x, cap) = x for x ≤ cap` argument as C1, applied
to `clampDiameter(d) = min(sanitizedNumber(d), 2·positionLimit)`: any
`d ≤ 0` is untouched, so `ErrorCopy.needsPositiveDiameter` still echoes
the raw value (`:231-233`, guard at `:430`). The no-argument default
(`max(2·penWidth, 4)`, `:433`) is not routed through `clampDiameter` at
all per the plan, and is already bounded (`penWidth ≤ 100` ⇒ default `≤
200`), so it's correctly left alone. For the explicit-diameter path,
`FrameRect(left: x - d/2, top: y - d/2, width: d, height: d)`
(`:436`) with `x, y` position-clamped and `d ≤ 2·positionLimit` gives
every edge `≤ 2·positionLimit` exactly — no stroke pad applies here
since the dot's `FrameRect` is built directly, not via
`frame(for:strokeWidth:)`, and `Emission.strokeWidth` is hardcoded to
`0` for `.dot` (`:437`). This condition's frame-bound wording is
already precise (unlike C5) — no gap.

## Independent completeness survey

I walked the full `Command` enum (`TurtleEngine.swift:113-134`) myself
rather than trusting design.md's Context table:

- `forward`/`back` (distance): unbounded *input*, but `move` clamps the
  destination (`clampPosition`, inside `move` at `:557`) **before**
  appending any stroke/fill vertex (`:561-577`) or mutating
  `state.x`/`state.y` (`:579-580`) — verified by reading the full
  function body, not just the design's line citation. Output is bounded
  regardless of input magnitude. No clamp needed.
- `right`/`left`/`setHeading` (degrees): `normalizeHeading`
  (`:670-673`) uses `truncatingRemainder(dividingBy: 360)` twice, which
  is well-defined and bounded for any finite input magnitude — confirmed
  no overflow/precision escape path exists here.
- `setPos`: routes through `move`, same as forward/back.
- `setPenWidth`: explicitly clamped to `[0.5, 100]` at `:368`.
- `arc` degrees: explicitly clamped to `[-360, 360]` at `:421`.
- `setPenColor`/`setFillColor`: string inputs, validated by
  `HexColor.normalized`, no numeric-magnitude concern.
- `home`/`penUp`/`penDown`/`beginFill`/`endFill`/`clean`/
  `clearScreen`/`resetTurtle`: no numeric arguments.
- `circle`/`arc` radius and `dot` explicit diameter: the two gaps this
  change closes.

I found no additional unbounded numeric input beyond the two the plan
already targets. The survey in design.md's Context is accurate and
complete.

**Interaction with the existing per-run caps** (`maxPartsPerRun = 200`,
`maxPathPointsPerRun = 50_000`, `:288-289`, enforced via
`reserveCapacity`, `:642-649`): none, and this is worth stating
explicitly since it wasn't asked for by name in the plan. Clamping the
*radius* changes the magnitude of each vertex, not the *count* of
vertices — `circlePoints` always emits exactly 61 points regardless of
`r` (`:715-723`), and `arcPoints`'s vertex count is a function of
`degrees` only, never `radius` (`n = max(8, ceil(|degrees|/6))`,
`:729`). So the clamp cannot interact with, weaken, or be weakened by
the point/part caps in either direction. No credential, secret, or I/O
surface exists anywhere in this file — confirmed by inspection; this is
pure in-memory geometry math.

## No-spec-delta decision

Defensible. The live spec's only radius/diameter-relevant promise is
positional clamping to ±1,000,000; it doesn't enumerate size inputs
today, and this fix doesn't change what the spec describes — it
completes an already-stated input-hygiene philosophy the spec's prose
already covers in spirit. Enumerating radius/diameter now would be
scope creep on a `--fix`. My only soft disagreement: since this gap was
specifically reachable from the AI-tool surface (not just a
theoretical HypeTalk footgun), a future spec revision for
`turtle-graphics` would be a reasonable place to fold "every numeric
size input clamps to the coordinate world" into the documented
philosophy — but that's a documentation nice-to-have for a later
change, not a blocker here.

## Conditions for Builder

The design's **C1–C8** (design.md) are sound and complete, and are the
binding security/correctness conditions the Build must honor and the
Security (code) gate will verify. Security adds emphasis on the
load-bearing ones:

- **C3 is the critical invariant.** `sanitizedNumber` MUST remain the
  *inner* call inside each helper — `min(sanitizedNumber(x), cap)`.
  Swift's generic `min` has no NaN-safe minNum semantics
  (`min(.nan, cap) == .nan`), so reordering to `sanitizedNumber(min(x,
  cap))`, or dropping the coercion, would silently pass a NaN radius/
  diameter straight through. Keep coercion strictly before `min()`.
- **C1/C7/C8 error-path byte-identity.** `min(x, cap) == x` for every
  non-positive `x`, so the `> 0` guards and both `ErrorCopy` owners stay
  untouched; do not edit the error copy or reorder the guards.
- **C2/C6 single owner.** Exactly one `clampRadius` used by both
  `.circle` and `.arc`, one `clampDiameter` used by `.dot`'s explicit
  branch; the fill-mode path must inherit the same clamped vertices (no
  forked geometry).
- **C4/C8 no-regression.** In-range values (radius ≤ positionLimit,
  diameter ≤ 2·positionLimit, and the default `dot` branch) must be
  byte-identical; existing geometry/property/E2 tests stay green
  unmodified.
- **Tester note (non-blocking, tightens C5):** assert the frame bound at
  its real magnitude (`|frame edge| ≤ 2·positionLimit + strokeWidth/2`,
  strokeWidth ≤ 100) rather than mere finiteness, so the stronger
  guarantee stated in design.md Goals is pinned by an actual assertion.

No additional security condition is required: the change is
additive-only (two upper bounds), introduces no new input, output, I/O,
control path, or secret handling, and the completeness survey found no
other unbounded numeric input.

## Verdict: PASS

No unsound or missing Condition; the reachability, layering, and
byte-identical-error-path claims all check out against the real code
(line numbers above were read from the file, not taken from the
design). One non-blocking note for the Tester: assert the C5 frame
bound at its actual tighter magnitude (`≤ 2·positionLimit + 50`, from
the `strokeWidth/2` pad in `frame(for:strokeWidth:)`) rather than only
finiteness, so the stronger guarantee already stated in the Goals
section is pinned by a real assertion, not left implicit. This does not
block Build.

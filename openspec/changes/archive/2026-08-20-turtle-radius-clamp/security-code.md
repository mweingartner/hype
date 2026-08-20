# Security review: turtle-radius-clamp (code)

## Actor

Security (sonnet) — delegated persona, code-review phase.

## Scope of the actual diff

```
git diff -- Sources/HypeCore/Script/TurtleEngine.swift Tests/HypeCoreTests/TurtleEngineTests.swift
```

confirms the change is exactly what design.md's Decision 2 specified, and
nothing more:

- `.circle` (`TurtleEngine.swift:413`) and `.arc` (`:419`): the size
  computation's callee changed from `TurtleEngine.sanitizedNumber(radius)`
  to `TurtleEngine.clampRadius(radius)`. No other line in either case
  changed.
- `.dot`'s explicit-diameter branch (`:429`): `TurtleEngine.sanitizedNumber(diameter)`
  → `TurtleEngine.clampDiameter(diameter)`. No other line in the case
  changed; the default branch (`:433`, `max(2 * state.penWidth, 4)`) is
  untouched.
- Two new private static helpers added at `:669-684`, next to
  `clampCoordinate`.
- `git status --porcelain` confirms only these two tracked files changed
  (plus new/untracked openspec change artifacts and `.mpd/state/…json`,
  which are process artifacts, not code) — the manifest is honored, no
  undeclared tracked edit.

## Findings

No security or correctness defects found. The code on disk is additive-only
(two private `min()`-based upper-bound helpers plus three one-line call-site
swaps), matches design.md Decision 2 verbatim, honors all of C1–C8, and
introduces no new input, output, control path, I/O, or secret handling. Both
E2 error paths are byte-identical, each helper has exactly one caller (no
bypass/forked geometry), and the full pre-existing regression suite passes
unmodified. Detailed per-condition evidence follows.

## Conditions verified (per condition, against the code actually on disk)

**C3 — finite-coercion precedes clamping (load-bearing).** CONFIRMED by
direct read of the helper bodies, `TurtleEngine.swift:675-684`:

```swift
private static func clampRadius(_ r: Double) -> Double {
    min(sanitizedNumber(r), positionLimit)
}
private static func clampDiameter(_ d: Double) -> Double {
    min(sanitizedNumber(d), 2 * positionLimit)
}
```

`sanitizedNumber` is literally the inner call in both — not reordered,
not dropped. `sanitizedNumber` itself (`:656-658`) is
`n.isFinite ? n : 0`. Since Swift's generic `min<T: Comparable>` has no
IEEE minNum NaN-handling (`min(.nan, x)` returns `.nan`), this ordering
is exactly the one that matters: a NaN/Inf radius or diameter is coerced
to `0` before `min()` ever runs, so `min()` never receives a non-finite
argument. Verified `positionLimit = 1_000_000` at `:290`, matching the
cap used in `clampRadius`, and `2 * positionLimit` in `clampDiameter`
matching the radius↔diameter conversion documented in design.md
Decision 2.

**C1/C7/C8 — error-path byte-identity.** CONFIRMED. The diff's `-`/`+`
lines are only the size-computation call (`sanitizedNumber` →
`clampRadius`/`clampDiameter`); the `guard r > 0 else { throw
TurtleError(ErrorCopy.needsPositiveRadius(...)) }` line at `:414` and
`:420`, and `guard sanitized > 0 else { throw
TurtleError(ErrorCopy.needsPositiveDiameter(...)) }` at `:430`, are
unchanged context lines in the diff — not touched. `ErrorCopy.needsPositiveRadius`
(`:226-228`) and `ErrorCopy.needsPositiveDiameter` (`:231-233`) string
bodies are unmodified (no diff hunk touches lines 200-239). Since
`min(x, cap) == x` for every `x ≤ cap` and both caps are positive
(`positionLimit`, `2·positionLimit`), every non-positive input passes
through the clamp unchanged, so the guard sees the identical raw value
and throws the identical string. Confirmed empirically, not just by
argument: ran the new `clampDoesNotAffectRadiusErrorPath` and
`clampDoesNotAffectDotDiameterErrorPath` tests (below) — both assert the
exact byte string (`"turtle: circle needs a radius greater than 0 (got
-5)."`, etc.) and pass.

**C2/C6 — single owner, no forked/duplicated clamp path.** CONFIRMED by
grep. `grep -n "sanitizedNumber(\|clampRadius(\|clampDiameter("` across
the whole file shows:
- `clampRadius(` called at exactly two sites: `:413` (`.circle`) and
  `:419` (`.arc`).
- `clampDiameter(` called at exactly one site: `:429` (`.dot`'s explicit
  branch).
- No `.circle`/`.arc`/`.dot` size computation still calls
  `sanitizedNumber(` directly — the only remaining `sanitizedNumber(`
  call sites are for unrelated inputs (`forward`/`back` distance `:322/:326`,
  heading deltas `:330/:334/:338`, `setPos` coordinates `:342`,
  `setPenWidth` `:368`, `arc` degrees `:421` — none of these are the
  radius/diameter size input this change targets).
- Fill-mode inheritance: `emitCurve` (`:588-605`) receives `points`
  already built from the clamped `r` (computed at `:413`/`:419` *before*
  `circlePoints`/`arcPoints` is called at `:415`/`:423`); its fill branch
  (`:589-593`) appends that same `points` array verbatim into
  `fillBuffer` — no separate geometry is computed for the filling case.
  Verified by reading `emitCurve` in full: there is exactly one call to
  `circlePoints`/`arcPoints` per case, and its result feeds both the
  fill and non-fill outcomes.

**C4/C8 — no regression, default dot untouched.** CONFIRMED. The `.dot`
default branch (`:433`, `d = max(2 * state.penWidth, 4)`) is a separate
`else` arm from the `clampDiameter` call at `:429` — never routed
through the new helper. `min(x, cap) = x` exactly for `x ≤ cap` (no
rounding, IEEE-754 comparison is exact here), so every existing
circle/arc/dot test is byte-identical post-fix. Ran `swift test --filter
TurtleCurveTests` and `swift test --filter TurtleEngineTests`: both
suites pass, including "circle 50 has 61 vertices…", "arc 90,50 has
… 16 vertices…", "dot 10 emits a 10×10 oval…", "an omitted dot diameter
defaults to max(2·penWidth,4)…", and "circle/arc with radius ≤ 0 raise
E2 with the exact copy" — none of these needed modification and all
pass unmodified.

**Completeness — no other unclamped numeric size input.** CONFIRMED by
reading the full `Command` enum (`:113-134`) and every case in `perform`
(`:317-458`) myself:
- `forward`/`back` (`:322`/`:326`) and `setPos` (`:342`) route through
  `move` (`:556-582`), which calls `TurtleEngine.clampPosition` at
  `:557` and mutates `state.x`/`state.y` only at `:579-580` — strictly
  after the clamp and after any buffer append (`:561-577`). Output is
  bounded regardless of input magnitude; no separate clamp needed here,
  and none was added.
- `right`/`left`/`setHeading` (`:330/:334/:338`) go through
  `normalizeHeading` (`:687-690`), `truncatingRemainder(dividingBy: 360)`
  twice — bounded for any finite input.
  `setPenWidth` (`:368`) is explicitly clamped `[0.5, 100]`. `arc`
  degrees (`:421`) explicitly clamped `[-360, 360]`.
- `setPenColor`/`setFillColor` are strings, not numeric magnitude
  inputs.
- No other case in the enum (`home`, `penUp`, `penDown`, `beginFill`,
  `endFill`, `clean`, `clearScreen`, `resetTurtle`) takes a numeric
  argument.
- Radius (`circle`/`arc`) and explicit diameter (`dot`) were therefore
  the complete set of unclamped size inputs, and both are now clamped.
  No gap found.

**Tests actually assert the conditions, not something weaker.**
Skimmed and ran `TurtleRadiusClampTests`
(`Tests/HypeCoreTests/TurtleEngineTests.swift:347-509`), all 9 pass:
- The two E2 tests (`clampDoesNotAffectRadiusErrorPath`,
  `clampDoesNotAffectDotDiameterErrorPath`) assert the *exact* strings
  via `#expect(throws: TurtleEngine.TurtleError("turtle: circle needs a
  radius greater than 0 (got -5)."))` etc. — byte-identical copy, not a
  weaker "throws some error" check.
- The bound tests assert real magnitude, not just finiteness: e.g.
  `hugeRadiusCircleClampsToPositionLimit` asserts
  `abs(radius - TurtleEngine.positionLimit) <= 1e-6` (a genuine
  radius-1,000,000 circle) and the frame bound at
  `2 * positionLimit + strokeHalf` — the tighter bound Security's
  plan-phase review recommended for C5, now actually pinned by
  assertion rather than left as "finite."
- C6 (fill-mode) is covered by
  `hugeRadiusCircleInsideFillIsBounded`, which drives `beginFill` →
  `circle(hugeRadius)` → `endFill` and asserts the resulting fill
  polygon's 62 points and frame are all finite and bounded.
- C8 (dot) is covered by `hugeDiameterDotClampsToPositionLimit`,
  asserting `frame.width == 2 * positionLimit` exactly (not merely
  bounded) and every edge within `position ± positionLimit`.
- C4 (identity boundary) is covered by `inRangeSizesAreClampIdentity`,
  asserting radius exactly at `positionLimit` draws a true circle of
  that radius, and diameter exactly at `2·positionLimit` is untouched.
- No test found that asserts something weaker than its Condition.

**New attack surface / secrets / I/O.** CONFIRMED none. The diff is
additive-only: two new `min()`-based upper bounds in pure, private,
static geometry helpers. No new inputs, outputs, control paths, I/O, or
credential/secret handling anywhere in the diff. This matches the
plan-phase Security review's threat model (local-trusted-user
perimeter; the fix is a robustness hardening, not a privilege/tenancy
boundary).

## Verification performed (not just read — executed)

- `swift test --filter TurtleRadiusClampTests` — 9/9 new tests pass.
- `swift test --filter TurtleEngineTests` — pre-existing E2/limits tests
  pass unmodified.
- `swift test --filter TurtleCurveTests` — pre-existing circle/arc/dot
  geometry tests pass unmodified (no regression, confirming C4/C8
  empirically, not just by `min(x,cap)=x` argument).
- `git status --porcelain` — confirms only the two manifest-declared
  tracked files changed.

## Conditions for Builder

All of design.md's C1-C8 are honored by the code on disk, verified
directly (not assumed from the plan):

- **C3 is confirmed load-bearing and correctly implemented as-is.** Any
  future edit to `clampRadius`/`clampDiameter` MUST preserve
  `min(sanitizedNumber(x), cap)` with `sanitizedNumber` as the inner
  call — do not reorder to `sanitizedNumber(min(x, cap))` and do not
  drop the coercion; Swift's generic `min` passes NaN through unchanged
  if it ever receives one directly.
- **C1/C7/C8 error-path byte-identity holds today.** `ErrorCopy.needsPositiveRadius`
  and `ErrorCopy.needsPositiveDiameter` are untouched; any future change
  must not edit this copy or reorder the `guard ... > 0` checks relative
  to the clamp.
- **C2/C6 single-owner holds today.** `clampRadius` is used by exactly
  `.circle` and `.arc`; `clampDiameter` by exactly `.dot`'s explicit
  branch; the fill-mode path inherits the same clamped vertices with no
  forked geometry. A future change must not introduce a second call site
  or a bypass path that reaches `circlePoints`/`arcPoints`/the dot frame
  without going through these helpers.
- **C4/C8 no-regression holds today**, confirmed empirically via the
  full pre-existing test suites passing unmodified.

No Condition is violated, no bypass or forked path exists, and no test
asserts something weaker than its Condition. Nothing further is required
of the Builder for this change.

## Verdict

PASS — the code on disk matches design.md's Decision 2 exactly, all
eight Conditions (C1-C8) are verified against the real implementation
(not the plan), the new tests assert real magnitudes rather than
weaker checks, and the full pre-existing regression suite for this file
passes unmodified.

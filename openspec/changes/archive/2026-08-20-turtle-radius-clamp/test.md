# Test: turtle radius & dot-diameter clamp

## Actor

Tester (sonnet) — delegated persona

## Coverage added

Read `Sources/HypeCore/Script/TurtleEngine.swift` in full (the `.circle`/`.arc`/`.dot`
cases, `clampRadius`/`clampDiameter`/`clampPosition`/`sanitizedNumber`, `emitCurve`,
`move`, `frame(for:strokeWidth:)`) and the existing `TurtleEngineTests.swift`,
including the Builder's inline `TurtleRadiusClampTests` suite (finiteness + bound
checks on a single `hugeRadius` constant, the exact-boundary identity test, the E2
byte-copy checks, and the fill-mode C6 check) and the file's existing
property/fuzz idiom (`TurtleSeededRNG`, `circleVerticesWithinTolerance`,
`arc360EqualsCircle`).

Added one new `@Suite("Radius/diameter clamp — fuzz corpus, extreme-center
composition, non-finite inputs, randomized metamorphic, vertex-count invariance")`
(`TurtleRadiusClampPropertyTests`) directly after the Builder's suite, in
`Tests/HypeCoreTests/TurtleEngineTests.swift`. It deliberately does not repeat what
`TurtleRadiusClampTests` already pins; every new test below targets a gap:

1. **Fuzz corpus, bound invariant (C5, C8)** — `circleCorpusStaysBounded`,
   `arcCorpusStaysBounded`, `dotCorpusStaysBounded`, each parametrized over a
   7-value corpus spanning `positionLimit+1`, `1e7`, `1e9`, `1e12`,
   `.greatestFiniteMagnitude`, and the exact identity boundary
   (`positionLimit` for radius / `2·positionLimit` for diameter), plus one
   value well above the diameter cap. Where the Builder's suite checked one
   fixed `hugeRadius` value, this sweeps the corpus including
   `.greatestFiniteMagnitude` (not previously exercised) and asserts every
   emitted coordinate/frame edge is finite and `|value| ≤ 2·positionLimit`, and
   for circle additionally that the vertex count stays 61 regardless of input
   magnitude.
2. **Composition with a clamped, extreme center (the real end-to-end
   invariant, C5/C6)** — `extremeCenterComposesWithSizeClamp` and
   `extremeCenterFillCurveStaysBounded`. `setPos` to `±1e12` first (which the
   engine's *other*, already-shipped clamp reduces to `±positionLimit`), then
   `circle`/`arc`/`dot` with a huge size, and confirm every emitted
   coordinate/frame edge is still within `±2·positionLimit` of the true
   origin — not just within `positionLimit` of the (already extreme) center.
   Neither the Builder's suite nor the file's existing tests exercised this
   composition; every existing test uses the canvas-center default position.
   The fill variant repeats the same composition for the C6 fill-mode path.
3. **Non-finite / sign inputs, byte-exact E2 (C1, C3, C8)** —
   `circleNonFiniteRadiusRaisesE2GotZero`, `arcNonFiniteRadiusRaisesE2GotZero`,
   `dotNonFiniteDiameterRaisesE2GotZero` (each over `[.nan, .infinity,
   -.infinity]`) confirm `sanitizedNumber` runs *inside* the clamp helper
   before `min()` ever sees the value, so a non-finite radius/diameter throws
   with the exact `"got 0"` copy rather than `"got nan"` or crashing `min()`
   on a NaN comparison. `negativeFiniteSizesEchoRawValue` (over
   `[-0.5, -100, -1e6, -1e12]`) confirms `min(negative, cap)` never raises a
   negative value — the raw input is echoed byte-identically in all three E2
   messages, pinning that the clamp is upper-bound-only (design.md Decision
   5) even for very large-magnitude negatives, not just the small examples
   the Builder's suite used (`-5`, `-1`, `-7`).
4. **Metamorphic, randomized (C4-adjacent, deepens the Builder's single-value
   check)** — `randomHugeRadiiClampIdentically`, 50 seeded cases
   (`TurtleSeededRNG`, reproducible): for two independently random radii
   `r1, r2 ∈ (positionLimit, 1e15]`, `circle(r1)` and `circle(r2)` must be
   byte-identical polygons (both clamp to the same `positionLimit`), and
   `arc(360, r1)` must equal `circle(r1)`. The Builder's suite checked this
   relation for exactly one fixed value; this sweeps the relation across the
   clamp's entire "above the cap" domain.
5. **Vertex-count invariance (non-functional / resource, §5.5)** —
   `circleVertexCountInvariantUnderClamp` and
   `arcVertexCountInvariantUnderClamp` (5 degree spans) directly compare a
   normal-radius run against a `.greatestFiniteMagnitude`-radius run and
   assert identical vertex counts. This pins that the clamp changes magnitude
   only, never point count, so it cannot interact with
   `maxPathPointsPerRun`/`maxPartsPerRun` — a budget-accounting concern the
   Builder's suite did not directly compare across radii.

## Non-functional

**Vertex-count invariance / resource note**: per-point cost is fixed by
`degrees`/curve type, never by radius magnitude (`circlePoints` always emits 61;
`arcPoints`'s segment count is `max(8, ceil(|degrees|/6))`, independent of
`radius`). The new tests assert this by direct cross-radius comparison rather
than by wall-clock timing, per the brief. Combined with the existing
`TurtleResourceBoundsTests` (point/part cap boundary tests already in the file),
this confirms the clamp introduces no new path to `maxPathPointsPerRun`/
`maxPartsPerRun` blowup — a pathological radius can only make individual
coordinates larger, never generate more of them.

## Results

Full suite (`bash scripts/mpd-test.sh`, DEVELOPER_DIR=Xcode-beta, `--no-parallel`,
run twice independently for confirmation):

```
Test run with 3480 tests in 384 suites passed after 113.344 seconds.
Test run with 34 tests in 1 suite passed after 2.786 seconds.
test result: ok. 3544 passed; 0 failed
```

Exit code: `0` (both runs; the second run's `EXIT=$?` capture also printed `0`).

New test count added this pass: 12 new `@Test` functions in
`TurtleRadiusClampPropertyTests`, expanding to 92 individual test cases via
`arguments:` parametrization (7 + 7 + 7 + 1 + 1 + 3 + 3 + 3 + 4 + 50 + 1 + 5).
All pass; zero regressions in the pre-existing 3452 cases (`TurtleEngineTests.swift`
and every other suite in the target).

## Conditions for Builder

- **C1** (upper-bound only, raw negative echoed) — pinned by both the
  Builder's `clampDoesNotAffectRadiusErrorPath`/`clampDoesNotAffectDotDiameterErrorPath`
  and this pass's `negativeFiniteSizesEchoRawValue` (wider magnitude range).
- **C2** (single owner per input) — structural; confirmed by reading
  `TurtleEngine.swift` (`.circle`/`.arc` both call `clampRadius`, `.dot`'s
  explicit path calls `clampDiameter`, no fork).
- **C3** (finite-coercion precedes clamping) — pinned by
  `circleNonFiniteRadiusRaisesE2GotZero`, `arcNonFiniteRadiusRaisesE2GotZero`,
  `dotNonFiniteDiameterRaisesE2GotZero` (new this pass — the Builder's suite
  did not exercise NaN/Infinity on circle/arc/dot specifically).
- **C4** (no normal-size regression) — pinned by the Builder's
  `inRangeSizesAreClampIdentity` plus every pre-existing circle/arc/dot test
  in the file, all still green.
- **C5** (bounded, finite emissions for any clamped curve) — pinned by the
  Builder's fixed-value tests and, more thoroughly, this pass's fuzz-corpus
  tests (`circleCorpusStaysBounded`, `arcCorpusStaysBounded`) and the
  composition tests (`extremeCenterComposesWithSizeClamp`).
- **C6** (fill-mode curves bounded) — pinned by the Builder's
  `hugeRadiusCircleInsideFillIsBounded` and this pass's
  `extremeCenterFillCurveStaysBounded` (adds the extreme-center composition).
- **C7** (E2 copy unchanged) — pinned by the Builder's exact-string tests and
  reaffirmed by this pass's parametrized non-finite/negative tests, which all
  assert the literal `ErrorCopy.needsPositiveRadius`/`needsPositiveDiameter`
  format.
- **C8** (`dot` upper-bound-only clamp, position-relative edge bound) —
  pinned by the Builder's `hugeDiameterDotClampsToPositionLimit` and this
  pass's `dotCorpusStaysBounded`/`extremeCenterComposesWithSizeClamp`.

No residual gap identified against C1–C8.

## Verdict

PASS

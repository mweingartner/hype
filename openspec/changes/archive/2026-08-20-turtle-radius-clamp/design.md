# Design: turtle radius & dot-diameter clamp

## Actor

Architect (fable)

## Context

Verified in `Sources/HypeCore/Script/TurtleEngine.swift` (2026-08-20):

- The engine's input-hygiene discipline: `sanitizedNumber` (~line 656,
  non-finite → 0) is applied to every numeric input; positions clamp to
  ±`positionLimit` (1,000,000; line 290) via `clampCoordinate` (~line 664)
  / `clampPosition`; `penWidth` clamps to [0.5, 100] (line 368); `arc`
  degrees clamp to [−360, 360] (line 421).
- Two size inputs lack an upper bound:
  - `.circle` case (lines 412–416): `let r = TurtleEngine.sanitizedNumber(radius)`,
    then `guard r > 0 else { throw TurtleError(ErrorCopy.needsPositiveRadius(shape: "circle", got: r)) }`,
    then `circlePoints` (61 vertices).
  - `.arc` case (lines 418–424): same sanitize + guard (shape `"arc"`),
    then degree clamp, zero-degree early-out, `arcPoints`.
  - `.dot` case (lines 426–438): the EXPLICIT-diameter path sanitizes,
    guards `> 0` (`ErrorCopy.needsPositiveDiameter`, line 231), then uses
    `d` unbounded in `FrameRect(left: x − d/2, top: y − d/2, width: d, height: d)`.
    The no-argument default branch `max(2 * state.penWidth, 4)` is already
    bounded (≤ 200) by the penWidth clamp.
- Both curves route through `emitCurve` (line 588): while filling, the
  vertices are appended to `fillBuffer` (the fill polygon emitted at
  `endFill`); otherwise a standalone `.path` emission with a frame from
  `frame(for:strokeWidth:)`. `vertexOnCircle` (line 707) is
  `center ± radius·trig`, |trig| ≤ 1 — so with center clamped to ±1e6 and
  radius ≤ 1e6, every emitted coordinate is within ±2·`positionLimit`.
  Today, `circle 1e12` emits vertices ≈ ±1e12 and `dot 1e12` a ~1e12-wide
  frame.
- E2 copy has single owners: `ErrorCopy.needsPositiveRadius` (line 226)
  and `ErrorCopy.needsPositiveDiameter` (line 231).
- Reachability: `circle`, `arc`, and `dot` are allowlisted turtle verbs
  (lines 778/786), and `TurtleProgramValidator.isAllowedExpression`
  accepts `.literal` unconditionally, so `circle 999999999999` and
  `dot 999999999999` pass the `draw_with_turtle` allowlist unmodified.
- **Completeness of the size-input survey** (the full `Command` enum,
  lines 113–134): `forward`/`back` distance and `setPos` are unbounded as
  inputs but their emitted geometry is position-clamped — `move`
  (line 556) clamps BEFORE appending any stroke/fill vertex or mutating
  state, so output is bounded; `right`/`left`/`setHeading` normalize mod
  360; `setPenWidth` clamps; `arc` degrees clamp; the remaining commands
  take strings (colors) or no arguments. Radius and explicit diameter are
  therefore the complete set of unclamped size inputs.

Downstream was traced and is already safe (context only, not scope):
`RenderGeometry.freeformLocalPoints` (origin-relative, finite-guarded),
`TargetRuntimeControlViews.normalizedPathPoints` (~line 1324,
stretch-to-fit), and `TurtlePartApplier.makePart` (frame → part bounds)
all tolerate 1e12 without crashing — CGFloat is 64-bit, so 1e12 is exact.
This fix is hardening, not a crash fix; after it, those paths only ever
see values ≤ ~2e6, strictly easier than before.

## Goals / Non-Goals

**Goals**

- Bound every drawn primitive's size input, completing the engine's
  input-hygiene invariant (finite-coerce, then clamp) across its numeric
  inputs: after this change, every emission's pathData and frame lie
  within ±2·`positionLimit` of the origin (+ ≤ 50 stroke pad on path
  frames).
- Keep both E2 error paths (`needsPositiveRadius`,
  `needsPositiveDiameter`) byte-identical.
- Zero behavior change for any radius ≤ `positionLimit` or diameter ≤
  2·`positionLimit`, including the default (no-argument) `dot`.

**Non-Goals**

- No spec delta (see Decisions).
- No per-vertex clamping of emitted pathData (rejected — see Decisions).
- No clamp on `forward`/`back` distance as an input — its output is
  already position-clamped in `move` before any vertex is buffered
  (verified above), so an input clamp would be redundant.
- No renderer or applier changes (traced safe, above).

## Decisions

1. **Clamp size at the input (option b), under one unifying rule: no
   drawn primitive's reach from its center may exceed `positionLimit`.**
   For `circle`/`arc` the reach is the radius (clamp ≤ `positionLimit`);
   for `dot` the reach is the half-diameter (clamp the explicit diameter
   ≤ 2·`positionLimit`). A reach larger than the entire coordinate world
   (±`positionLimit`) is off-world nonsense; capping it keeps the shape a
   true circle/arc/dot (just size-capped) and makes the emitted-geometry
   invariant uniform: a max dot spans exactly the coordinate world when
   centered, consistent with a max circle, and every primitive's
   frame/pathData is within ±2·`positionLimit` of the (clamped) center.
   This completes the engine's existing, deliberate input-hygiene
   discipline that positions/`penWidth`/`arc` degrees already follow.

2. **Owner shape: two sibling one-line helpers, each in its input's
   native unit, sharing the rule via documentation** — next to
   `clampCoordinate`:

   ```swift
   /// Shared size rule: no drawn primitive's reach from its center may
   /// exceed the coordinate world (±positionLimit) — a larger reach is
   /// off-world nonsense that would emit astronomically large geometry.
   /// For circle/arc the reach is the radius; clamp it to positionLimit.
   /// Upper-bound only: the lower bound is left to the caller's `> 0`
   /// check (E2), so a non-positive radius still errors.
   private static func clampRadius(_ r: Double) -> Double {
       min(sanitizedNumber(r), positionLimit)
   }

   /// For a dot the reach is the half-diameter; clamp the diameter to
   /// 2·positionLimit (see clampRadius for the shared rule). Upper-bound
   /// only — a non-positive diameter still errors via the caller's E2.
   private static func clampDiameter(_ d: Double) -> Double {
       min(sanitizedNumber(d), 2 * positionLimit)
   }
   ```

   Rejected: a shared `clampReach` that `clampDiameter` would call as
   `2 * clampReach(d / 2)`. The unit round-trip is not the identity at
   the bottom of the double range — `(5e-324 / 2) * 2 == 0` under
   round-to-nearest-even — so a legal subnormal diameter would flip from
   drawing to throwing E2, violating the byte-identical no-regression
   condition. `min(d, 2 * positionLimit)` in the native unit is exact for
   every in-range value; `2 * positionLimit` is the radius↔diameter
   conversion, not a magic constant.

3. **Rejected (a): per-vertex clamp of emitted coordinates.** It distorts
   *legitimate* edge-of-world circles — a circle at position 1e6 with
   radius 100 legitimately reaches 1,000,100 — into flat-sided blobs, and
   still wouldn't uniformly bound frames/dots. Worse fidelity for no gain.

4. **Rejected (c): doc-only / leave the code.** There is NO live
   spec-vs-code inconsistency to fix: the live spec only ever promised
   that positions clamp to ±1,000,000, and the over-broad "all pathData
   within ±1,000,000" wording exists only in an ARCHIVED design.md test
   plan (the Test phase already recorded the true guarantee). But (c)
   leaves the AI-tool-reachable footgun open. We choose to harden.

5. **Upper-bound-only clamps.** The lower bounds stay with the callers'
   existing `guard ... > 0` E2 checks, so a non-positive radius or
   diameter still errors with the raw value echoed. `min()` only lowers
   large positives — it never raises a negative or zero — so both error
   paths are byte-identical before and after this change. The `.dot`
   default branch (`max(2·penWidth, 4)`, already bounded ≤ 200) is
   untouched.

6. **One owner per input.** Both `.circle` and `.arc` call `clampRadius`;
   `.dot`'s explicit path calls `clampDiameter` — no forked or duplicated
   clamp logic, matching the single-owner pattern of `clampCoordinate`,
   `ErrorCopy.needsPositiveRadius`, and `ErrorCopy.needsPositiveDiameter`.

7. **No spec delta — deliberate.** The live spec
   (`openspec/specs/turtle-graphics/spec.md`) states only "positions clamp
   to ±1,000,000", and its general clamp philosophy encompasses size
   clamping; adding radius/diameter to the enumerated clamp list would be
   spec-completeness scope-creep on a low-severity fix. A `--fix` skips
   Documentation/Doc-Validation for exactly this reason: it changes
   nothing the durable docs describe. Recorded here explicitly so the
   Security and Doc reviewers can see the omission was deliberate, not an
   oversight.

## Risks / Trade-offs

- **The only behavioral changes**: an absurd radius (> 1e6) now produces
  a world-sized-capped circle/arc (radius 1,000,000) instead of a 1e12
  one, and an absurd explicit dot diameter (> 2e6) a world-spanning dot
  (diameter 2,000,000) instead of a 1e12 one. → Acceptable: the inputs
  are pathological, and the capped results are still true primitives
  rather than degenerate parts. Tests pin both.
- [Risk] A clamp accidentally engages for normal sizes. → C4/C8: for
  radius ≤ `positionLimit` and diameter ≤ 2·`positionLimit`, the helpers
  are the identity (`min(x, limit) = x`, exact in FP), so emissions are
  byte-identical; the existing geometry/property/metamorphic tests
  (circle tolerance, arc≡circle, exact closure) must stay green
  untouched.
- [Risk] Error-copy drift on either E2 path. → C1/C7/C8: the guards,
  `ErrorCopy.needsPositiveRadius`, and `ErrorCopy.needsPositiveDiameter`
  are unchanged; the existing exact-copy E2 tests
  (`TurtleEngineTests.swift` ~lines 290–298) must stay green.
- No new attack surface: the change only ADDS bounds (strictly safer).

## Conditions for Builder

- **C1** — The radius clamp is upper-bound only: r ≤ 0 (including a raw
  negative such as −5, and 0) still throws E2 with the raw non-positive
  value echoed in the `got:` position, byte-identical to today.
- **C2** — Both `.circle` and `.arc` route their radius through the
  single `clampRadius` owner; `.dot`'s explicit diameter routes through
  the single `clampDiameter` owner; no forked or duplicated clamp logic.
- **C3** — Finite-coercion precedes clamping: `sanitizedNumber` runs
  inside each helper before `min()`, so a NaN/Inf radius or diameter
  coerces to 0 and still fails the `> 0` guard with "got 0" (and `min()`
  never receives a NaN).
- **C4** — No normal-size regression: for radius ≤ `positionLimit` and
  diameter ≤ 2·`positionLimit`, the helpers are the identity and
  emissions are byte-identical; all existing circle/arc/dot tests pass
  unmodified.
- **C5** — For any clamped curve (radius > `positionLimit`), every
  emitted pathData coordinate is finite with |coordinate| ≤
  `positionLimit` + `positionLimit`, and the emission's frame is finite.
  (Tester: CONFIRM this by assertion, not by assumption.)
- **C6** — Fill-mode curves are covered: a `circle`/`arc` inside
  `beginFill`/`endFill` feeds clamped vertices into the fill polygon, so
  the `endFill` emission is likewise bounded per C5.
- **C7** — Both E2 error copies are unchanged: single owners
  `ErrorCopy.needsPositiveRadius` and `ErrorCopy.needsPositiveDiameter`,
  no text edits.
- **C8** — `dot`: the explicit diameter clamps upper-bound only (d ≤ 0
  still throws E2 with the raw value echoed, byte-identical); the
  default-diameter branch (`max(2·penWidth, 4)`) is unchanged; a clamped
  huge `dot` yields a finite frame with every edge within
  position ± `positionLimit` (i.e. |edge| ≤ 2·`positionLimit`).
  (Tester: CONFIRM by assertion.)

## Verdict

PASS

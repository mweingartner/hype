# turtle radius & dot-diameter clamp

## Why

The `TurtleEngine` (`TurtleEngine.swift`) clamps the turtle's position to
±`positionLimit` (1,000,000) via `clampCoordinate`/`clampPosition`,
finite-coerces every numeric input via `sanitizedNumber` (non-finite → 0),
clamps `penWidth` to [0.5, 100], and clamps `arc` degrees to [−360, 360] —
but two size inputs have only a `> 0` check and no upper bound: the
`circle`/`arc` **radius** and the explicit `dot` **diameter**. So
`circle 999999999999` computes curve vertices at `center ± radius·trig`
≈ 1e12, and `dot 999999999999` emits a frame ~1e12 wide — finite values,
but ~six orders of magnitude beyond the ±1e6 coordinate world, producing
degenerate freeform parts. Both are reachable from HypeTalk AND from the
`draw_with_turtle` AI tool (`circle`, `arc`, and `dot` are allowlisted
verbs, and the allowed-expression validator accepts number literals of any
magnitude).

## What Changes

- Adopt one rule for every drawn primitive: **no primitive's reach from
  its center may exceed `positionLimit`.** For `circle`/`arc` the reach is
  the radius; for `dot` it is the half-diameter.
- Add two static helpers, siblings to `clampCoordinate`, each upper-bound
  only: `clampRadius(_:) = min(sanitizedNumber(r), positionLimit)` and
  `clampDiameter(_:) = min(sanitizedNumber(d), 2 * positionLimit)`.
- Route the `.circle` and `.arc` radius through `clampRadius`, and the
  `.dot` EXPLICIT diameter through `clampDiameter` (the no-argument
  default `max(2·penWidth, 4)` is already bounded by the penWidth clamp
  and is untouched). The existing `guard ... > 0` E2 checks
  (`needsPositiveRadius`, `needsPositiveDiameter`) stay and their error
  paths are byte-identical: `min()` only lowers large positives, never
  raises a negative or zero, so non-positive inputs still throw with the
  raw value echoed.
- Add tests asserting huge inputs yield bounded, finite geometry — all
  pathData/frame coordinates within ±2·`positionLimit` (+ stroke pad) —
  for standalone circle, standalone arc, `arc 360 ≡ circle` under
  clamping, a curve inside `beginFill`/`endFill`, and a huge `dot`; and
  that non-positive inputs, the default `dot`, and normal-sized inputs
  behave exactly as before.

No behavior change for any radius ≤ 1,000,000 or diameter ≤ 2,000,000.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

_None — this is a defect fix completing the engine's existing, deliberate
input-hygiene discipline (finite-coerce, then clamp to a sane domain) that
positions, `penWidth`, and `arc` degrees already follow. The live spec
(`openspec/specs/turtle-graphics/spec.md`) only ever promised that
positions clamp to ±1,000,000; its general clamp philosophy encompasses
size clamping, and enumerating radius/diameter there would be
spec-completeness scope-creep on a low-severity fix. No documented
capability changes._

## Impact

- `Sources/HypeCore/Script/TurtleEngine.swift` — `clampRadius` and
  `clampDiameter` helpers plus the `.circle`, `.arc`, and `.dot` cases.
- `Tests/HypeCoreTests/TurtleEngineTests.swift` — huge-size bounding tests
  and error-path/no-regression pins.

Provenance: this footgun escaped the archived `2026-08-20-turtle-graphics`
change (the `--introduced-by` flag was dropped at conduct time, so
provenance is recorded here in prose).

Severity: low under the local-trusted-user threat profile, but reachable
from the `draw_with_turtle` AI tool via allowlisted huge number literals —
not just by a trusted stack author. Nothing crashes today (all three
freeform render paths are stretch-to-fit/NaN-safe and CGFloat is 64-bit);
this is a consistency/robustness fix completing the engine's input-hygiene
invariant across its numeric size inputs, not a crash fix. With it, the
clamp discipline covers every numeric input the engine takes: positions,
heading (normalized), penWidth, arc degrees, radius, and diameter.

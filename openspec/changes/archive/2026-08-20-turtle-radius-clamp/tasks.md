# Tasks — turtle-radius-clamp

## 1. Fix (ends green)

- [x] 1.1 In `Sources/HypeCore/Script/TurtleEngine.swift`, add the static
      `clampRadius(_:)` and `clampDiameter(_:)` helpers as siblings to
      `clampCoordinate` (~line 664): `min(sanitizedNumber(r), positionLimit)`
      and `min(sanitizedNumber(d), 2 * positionLimit)`, with the doc
      comments from design.md Decision 2 (shared reach ≤ `positionLimit`
      rule; upper-bound only; lower bounds left to the callers' `> 0` E2
      checks).
- [x] 1.2 Wire the `.circle` case (~line 413) and the `.arc` case (~line
      419): replace `let r = TurtleEngine.sanitizedNumber(radius)` with
      `let r = TurtleEngine.clampRadius(radius)`. The `guard r > 0` E2
      throws and everything else stay untouched.
- [x] 1.3 Wire the `.dot` case (~line 429), explicit-diameter branch only:
      replace `let sanitized = TurtleEngine.sanitizedNumber(diameter)`
      with `let sanitized = TurtleEngine.clampDiameter(diameter)`. The
      `guard sanitized > 0` E2 throw and the default branch
      (`max(2 * state.penWidth, 4)`) stay untouched.
- [x] 1.4 Add tests to `Tests/HypeCoreTests/TurtleEngineTests.swift`:
      (a) `circle 999999999999` → one emission whose pathData is all
      finite with |x|,|y| ≤ 2·`positionLimit` and whose frame is finite
      (a true radius-1,000,000 circle);
      (b) huge-radius `arc` likewise;
      (c) `arc 360, r` ≡ `circle r` still holds for a clamped huge r
      (metamorphic — both clamp to the same radius);
      (d) negative/zero radius still throws E2 with the exact existing
      copy (raw value echoed — clamping must not touch the error path);
      (e) no normal-size regression: radius ≤ `positionLimit` and
      diameter ≤ 2·`positionLimit` emissions unchanged (existing
      geometry/property tests stay green unmodified);
      (f) a clamped huge-radius curve inside `beginFill`/`endFill`
      produces a bounded, finite fill polygon (C6);
      (g) `dot 999999999999` → a finite frame spanning exactly
      diameter 2·`positionLimit`, every edge within
      position ± `positionLimit` (C8);
      (h) negative/zero explicit diameter still throws E2 with the exact
      existing `needsPositiveDiameter` copy (raw value echoed);
      (i) default `dot` (no argument) unchanged: frame diameter
      `max(2·penWidth, 4)`.
- [x] 1.5 `bash scripts/mpd-test.sh` green.

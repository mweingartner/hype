import Testing
import Foundation
@testable import HypeCore

// Engine-level tests for `turtle-graphics` P1 (design.md test plan,
// `TurtleEngineTests.swift`): criteria 1–3 (geometry), 5 (square is one
// part), 6 (trail splits on pen change), 7 (frame math), 8 (fill
// contract), 9 (curve approximation), the engine half of 15 (E1–E5
// verbatim strings, clamps, coercions, E8 atomicity), `ScalarState`
// encode/decode round-trip, and the per-run limits. Interpreter/AI
// surface integration is exercised in P2/P3's own test files.

private func makeEngine(width: Double = 800, height: Double = 600) -> TurtleEngine {
    TurtleEngine(canvas: TurtleEngine.Canvas(width: width, height: height), restoring: nil)
}

// MARK: - Criteria 1–3: geometry

@Suite("Geometry — movement, rotation, absolute forms, tolerant numerics")
struct TurtleGeometryTests {

    @Test("forward 100 from defaults on an 800×600 canvas: (400,300) → (400,200)")
    func firstLineFromDefaults() throws {
        var engine = makeEngine()
        _ = try engine.perform(.forward(100))
        #expect(engine.scalarState.x == 400)
        #expect(engine.scalarState.y == 200)

        let outcome = engine.endRun()
        #expect(outcome.emissions.count == 1)
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData == [PathPoint(x: 400, y: 300), PathPoint(x: 400, y: 200)])
        #expect(emission.strokeColor == "#000000")
        #expect(emission.strokeWidth == 2)
        #expect(emission.fillColor == "")
        #expect(emission.kind == .path)
    }

    @Test("right 90 then forward 100 reaches (500,300); left 90 inverts the rotation")
    func rightThenForward() throws {
        var engine = makeEngine()
        _ = try engine.perform(.right(90))
        #expect(engine.scalarState.heading == 90)
        _ = try engine.perform(.forward(100))
        #expect(engine.scalarState.x == 500)
        #expect(engine.scalarState.y == 300)

        _ = try engine.perform(.left(90))
        #expect(engine.scalarState.heading == 0)
    }

    @Test("setHeading 270 then forward 100 from home reaches (300,300)")
    func setHeadingThenForward() throws {
        var engine = makeEngine()
        _ = try engine.perform(.setHeading(270))
        _ = try engine.perform(.forward(100))
        #expect(engine.scalarState.x == 300)
        #expect(engine.scalarState.y == 300)
    }

    @Test("right 450 normalizes the heading to 90")
    func rightWraps() throws {
        var engine = makeEngine()
        _ = try engine.perform(.right(450))
        #expect(engine.scalarState.heading == 90)
    }

    @Test("forward with a non-finite distance coerces to 0 (quiet no-op)")
    func nonFiniteDistanceCoercesToZero() throws {
        var engine = makeEngine()
        let before = engine.scalarState
        _ = try engine.perform(.forward(.nan))
        #expect(engine.scalarState == before)
    }

    @Test("setPenWidth clamps to [0.5, 100] silently")
    func penWidthClamps() throws {
        var engine = makeEngine()
        _ = try engine.perform(.setPenWidth(500))
        #expect(engine.scalarState.penWidth == 100)
        _ = try engine.perform(.setPenWidth(0.001))
        #expect(engine.scalarState.penWidth == 0.5)
    }

    @Test("setPenColor with an invalid value raises E1 verbatim, leaving pen state unchanged")
    func invalidPenColorRaisesE1() {
        var engine = makeEngine()
        let before = engine.scalarState
        #expect(throws: TurtleEngine.TurtleError("turtle: \"blurple\" isn't a color — use #RRGGBB, #RRGGBBAA, or a name like red, blue, orange.")) {
            try engine.perform(.setPenColor("blurple"))
        }
        #expect(engine.scalarState == before)
    }
}

// MARK: - Criterion 5: square is one part

@Suite("Trail buffering — square closure, split on pen change")
struct TurtleTrailBufferingTests {

    @Test("repeat 4 times { forward 120; right 90 } is one part, 5 vertices, first == last")
    func squareIsOnePart() throws {
        var engine = makeEngine()
        for _ in 0..<4 {
            _ = try engine.perform(.forward(120))
            _ = try engine.perform(.right(90))
        }
        let outcome = engine.endRun()
        #expect(outcome.emissions.count == 1)
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData.count == 5)
        #expect(emission.pathData.first == emission.pathData.last)
    }

    @Test("forward 50 / setPenColor red / forward 50 produces two stroke parts")
    func trailSplitsOnPenChange() throws {
        var engine = makeEngine()
        let first = try engine.perform(.forward(50))
        #expect(first.emissions.isEmpty, "movement itself never flushes")

        let colorChange = try engine.perform(.setPenColor("red"))
        #expect(colorChange.emissions.count == 1, "an actual pen-color change flushes the open stroke")
        #expect(try #require(colorChange.emissions.first).strokeColor == "#000000")

        let second = try engine.perform(.forward(50))
        #expect(second.emissions.isEmpty)

        let final = engine.endRun()
        #expect(final.emissions.count == 1)
        #expect(try #require(final.emissions.first).strokeColor == "#FF0000")
    }
}

// MARK: - Criterion 7: frame math

@Suite("Frame math — §5.1 padding and minimum size")
struct TurtleFrameMathTests {

    @Test("frame pads by strokeWidth/2 and enforces a 1×1 minimum")
    func framePadsAndClampsMinimum() throws {
        var engine = makeEngine()
        _ = try engine.perform(.setPenWidth(4))
        _ = try engine.perform(.forward(100))
        let outcome = engine.endRun()
        let emission = try #require(outcome.emissions.first)
        // Straight up from (400,300) to (400,200): tight bbox is
        // x ∈ [400,400], y ∈ [200,300]; padded by strokeWidth/2 = 2.
        #expect(emission.frame.left == 398)
        #expect(emission.frame.top == 198)
        #expect(emission.frame.width == 4)   // max(1, 0 + 2*2)
        #expect(emission.frame.height == 104) // max(1, 100 + 2*2)
    }

    @Test("a fill's strokeWidth 0 (pen up at endFill) means zero padding: frame == tight bbox exactly")
    func fillFrameWithZeroStrokeWidthHasNoPadding() throws {
        var engine = makeEngine()
        _ = try engine.perform(.penUp)
        _ = try engine.perform(.beginFill)
        for _ in 0..<3 {
            _ = try engine.perform(.forward(130))
            _ = try engine.perform(.right(120))
        }
        let outcome = try engine.perform(.endFill)
        let emission = try #require(outcome.emissions.first)
        let xs = emission.pathData.map(\.x)
        let ys = emission.pathData.map(\.y)
        #expect(emission.frame.left == xs.min())
        #expect(emission.frame.top == ys.min())
        #expect(emission.frame.width == max(1, (xs.max() ?? 0) - (xs.min() ?? 0)))
        #expect(emission.frame.height == max(1, (ys.max() ?? 0) - (ys.min() ?? 0)))
    }
}

// MARK: - Criterion 8: fill contract

@Suite("Fill contract — beginFill/endFill, pen-up width 0, no stray stroke")
struct TurtleFillTests {

    @Test("beginFill / three forward+right(120) legs / endFill emits one 4-vertex fill part; no stray stroke")
    func fillEmitsOnePart() throws {
        var engine = makeEngine()
        let beginOutcome = try engine.perform(.beginFill)
        #expect(beginOutcome.emissions.isEmpty)
        for _ in 0..<3 {
            let moveOutcome = try engine.perform(.forward(130))
            #expect(moveOutcome.emissions.isEmpty, "movement while filling never emits a stray stroke part")
            _ = try engine.perform(.right(120))
        }
        let endOutcome = try engine.perform(.endFill)
        #expect(endOutcome.emissions.count == 1)
        let emission = try #require(endOutcome.emissions.first)
        #expect(emission.kind == .fill)
        #expect(emission.pathData.count == 4)
        #expect(emission.fillColor == engine.scalarState.fillColor)
        #expect(emission.strokeColor == engine.scalarState.penColor)
        #expect(emission.strokeWidth == engine.scalarState.penWidth)

        // No separate stroke part should exist from the movement.
        let final = engine.endRun()
        #expect(final.emissions.isEmpty)
    }

    @Test("the same fill sequence with pen up emits strokeWidth 0")
    func fillWithPenUpHasZeroStrokeWidth() throws {
        var engine = makeEngine()
        _ = try engine.perform(.penUp)
        _ = try engine.perform(.beginFill)
        for _ in 0..<3 {
            _ = try engine.perform(.forward(130))
            _ = try engine.perform(.right(120))
        }
        let endOutcome = try engine.perform(.endFill)
        let emission = try #require(endOutcome.emissions.first)
        #expect(emission.strokeWidth == 0)
    }

    @Test("beginFill while already filling raises E4")
    func alreadyFillingRaisesE4() throws {
        var engine = makeEngine()
        _ = try engine.perform(.beginFill)
        #expect(throws: TurtleEngine.TurtleError("turtle: already filling — call endFill before starting another fill.")) {
            try engine.perform(.beginFill)
        }
    }

    @Test("endFill without beginFill raises E5")
    func endFillWithoutBeginFillRaisesE5() {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: endFill without beginFill — nothing to fill.")) {
            try engine.perform(.endFill)
        }
    }

    @Test("endFill with fewer than 3 vertices emits nothing and sets the E6 result note")
    func tooFewFillVerticesSetsE6() throws {
        var engine = makeEngine()
        _ = try engine.perform(.beginFill)
        _ = try engine.perform(.forward(10))
        let outcome = try engine.perform(.endFill)
        #expect(outcome.emissions.isEmpty)
        #expect(outcome.resultNote == "turtle: fill needs at least 3 points — nothing drawn.")
    }

    @Test("an unclosed beginFill at end of run emits nothing and sets the E7 result note")
    func unclosedFillAtRunEndSetsE7() throws {
        var engine = makeEngine()
        _ = try engine.perform(.beginFill)
        _ = try engine.perform(.forward(10))
        _ = try engine.perform(.right(120))
        _ = try engine.perform(.forward(10))
        let outcome = engine.endRun()
        #expect(outcome.emissions.isEmpty)
        #expect(outcome.resultNote == "turtle: beginFill was never closed — no fill drawn.")
        #expect(engine.isFilling == false)
    }
}

// MARK: - Criterion 9: curve approximation

@Suite("Curve approximation — circle, arc, dot")
struct TurtleCurveTests {

    @Test("circle 50 has 61 vertices, first == last, all within 0.07pt of the radius; the turtle does not move")
    func circleGeometry() throws {
        var engine = makeEngine()
        let before = engine.scalarState
        let outcome = try engine.perform(.circle(radius: 50))
        #expect(engine.scalarState == before, "circle never moves the turtle")
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData.count == 61)
        #expect(emission.pathData.first == emission.pathData.last)
        for point in emission.pathData {
            let dx = point.x - before.x
            let dy = point.y - before.y
            let radius = (dx * dx + dy * dy).squareRoot()
            #expect(abs(radius - 50) <= 0.07)
        }
    }

    @Test("arc 90,50 has max(8, ceil(90/6)) = 15 segments (16 vertices); the turtle does not move")
    func arcGeometry() throws {
        var engine = makeEngine()
        let before = engine.scalarState
        let outcome = try engine.perform(.arc(degrees: 90, radius: 50))
        #expect(engine.scalarState == before)
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData.count == 16)
    }

    @Test("circle/arc with radius ≤ 0 raise E2 with the exact copy")
    func nonPositiveRadiusRaisesE2() {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: circle needs a radius greater than 0 (got 0).")) {
            try engine.perform(.circle(radius: 0))
        }
        #expect(throws: TurtleEngine.TurtleError("turtle: arc needs a radius greater than 0 (got -5).")) {
            try engine.perform(.arc(degrees: 90, radius: -5))
        }
    }

    @Test("dot 10 emits a 10×10 oval centered on the turtle with fillColor = pen color, strokeWidth 0")
    func dotGeometry() throws {
        var engine = makeEngine()
        let outcome = try engine.perform(.dot(diameter: 10))
        let emission = try #require(outcome.emissions.first)
        #expect(emission.kind == .dot)
        #expect(emission.pathData.isEmpty)
        #expect(emission.frame.width == 10)
        #expect(emission.frame.height == 10)
        #expect(emission.frame.left == engine.scalarState.x - 5)
        #expect(emission.frame.top == engine.scalarState.y - 5)
        #expect(emission.fillColor == engine.scalarState.penColor)
        #expect(emission.strokeWidth == 0)
    }

    @Test("an omitted dot diameter defaults to max(2·penWidth, 4) and never errors")
    func dotDefaultDiameter() throws {
        var engine = makeEngine()
        _ = try engine.perform(.setPenWidth(10))
        let outcome = try engine.perform(.dot(diameter: nil))
        let emission = try #require(outcome.emissions.first)
        #expect(emission.frame.width == 20) // max(2*10, 4)
    }

    @Test("dot with a non-positive diameter raises E2")
    func dotNonPositiveDiameterRaisesE2() {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: dot needs a diameter greater than 0 (got -1).")) {
            try engine.perform(.dot(diameter: -1))
        }
    }

    @Test("dot emits even with pen up and mid-fill")
    func dotAlwaysEmits() throws {
        var engine = makeEngine()
        _ = try engine.perform(.penUp)
        let penUpOutcome = try engine.perform(.dot(diameter: 4))
        #expect(penUpOutcome.emissions.count == 1)

        _ = try engine.perform(.beginFill)
        let midFillOutcome = try engine.perform(.dot(diameter: 4))
        #expect(midFillOutcome.emissions.count == 1)
        #expect(engine.isFilling, "dot must not disturb the open fill")
    }
}

// MARK: - turtle-radius-clamp fix: radius/diameter bound to the coordinate world

@Suite("Radius/diameter clamp — astronomically large circle/arc/dot inputs bound to positionLimit")
struct TurtleRadiusClampTests {

    /// An input far beyond `positionLimit` (1e6) that must clamp rather
    /// than emit off-world geometry.
    private static let hugeRadius: Double = 999_999_999_999

    @Test("circle with an astronomically large radius clamps to positionLimit: finite, bounded pathData and frame")
    func hugeRadiusCircleClampsToPositionLimit() throws {
        var engine = makeEngine()
        let center = engine.scalarState
        let outcome = try engine.perform(.circle(radius: Self.hugeRadius))
        #expect(outcome.emissions.count == 1)
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData.count == 61)
        for point in emission.pathData {
            #expect(point.x.isFinite && point.y.isFinite)
            #expect(abs(point.x) <= 2 * TurtleEngine.positionLimit)
            #expect(abs(point.y) <= 2 * TurtleEngine.positionLimit)
            // A genuine radius-1,000,000 circle, not merely "some bounded shape".
            let radius = hypot(point.x - center.x, point.y - center.y)
            #expect(abs(radius - TurtleEngine.positionLimit) <= 1e-6)
        }
        // Tighter frame bound (Security C5 note): the real magnitude, not
        // just finiteness — |edge| ≤ 2·positionLimit + strokeWidth/2.
        let strokeHalf = engine.scalarState.penWidth / 2
        let frame = emission.frame
        #expect(frame.left.isFinite && frame.top.isFinite && frame.width.isFinite && frame.height.isFinite)
        #expect(abs(frame.left) <= 2 * TurtleEngine.positionLimit + strokeHalf)
        #expect(abs(frame.top) <= 2 * TurtleEngine.positionLimit + strokeHalf)
        #expect(abs(frame.left + frame.width) <= 2 * TurtleEngine.positionLimit + strokeHalf)
        #expect(abs(frame.top + frame.height) <= 2 * TurtleEngine.positionLimit + strokeHalf)
    }

    @Test("arc with an astronomically large radius clamps to positionLimit: finite, bounded pathData and frame")
    func hugeRadiusArcClampsToPositionLimit() throws {
        var engine = makeEngine()
        let center = engine.scalarState
        let outcome = try engine.perform(.arc(degrees: 90, radius: Self.hugeRadius))
        #expect(outcome.emissions.count == 1)
        let emission = try #require(outcome.emissions.first)
        for point in emission.pathData {
            #expect(point.x.isFinite && point.y.isFinite)
            #expect(abs(point.x) <= 2 * TurtleEngine.positionLimit)
            #expect(abs(point.y) <= 2 * TurtleEngine.positionLimit)
            let radius = hypot(point.x - center.x, point.y - center.y)
            #expect(abs(radius - TurtleEngine.positionLimit) <= 1e-6)
        }
        let strokeHalf = engine.scalarState.penWidth / 2
        let frame = emission.frame
        #expect(frame.left.isFinite && frame.top.isFinite && frame.width.isFinite && frame.height.isFinite)
        #expect(abs(frame.left) <= 2 * TurtleEngine.positionLimit + strokeHalf)
        #expect(abs(frame.top) <= 2 * TurtleEngine.positionLimit + strokeHalf)
        #expect(abs(frame.left + frame.width) <= 2 * TurtleEngine.positionLimit + strokeHalf)
        #expect(abs(frame.top + frame.height) <= 2 * TurtleEngine.positionLimit + strokeHalf)
    }

    @Test("arc 360 with a huge radius equals circle with the same huge radius (metamorphic, post-clamp)")
    func hugeRadiusArc360EqualsHugeRadiusCircle() throws {
        var circleEngine = makeEngine()
        var arcEngine = makeEngine()
        let circleOutcome = try circleEngine.perform(.circle(radius: Self.hugeRadius))
        let arcOutcome = try arcEngine.perform(.arc(degrees: 360, radius: Self.hugeRadius))
        let circlePath = try #require(circleOutcome.emissions.first).pathData
        let arcPath = try #require(arcOutcome.emissions.first).pathData
        #expect(arcPath.count == circlePath.count, "both clamp to the same radius, so vertex counts must match")
        #expect(arcPath == circlePath, "both clamp to radius positionLimit, so the polygons must be identical")
    }

    @Test("clamping does not touch the E2 error path: negative and zero radii still throw byte-identical copy for circle and arc")
    func clampDoesNotAffectRadiusErrorPath() {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: circle needs a radius greater than 0 (got -5).")) {
            try engine.perform(.circle(radius: -5))
        }
        #expect(throws: TurtleEngine.TurtleError("turtle: arc needs a radius greater than 0 (got 0).")) {
            try engine.perform(.arc(degrees: 90, radius: 0))
        }
    }

    @Test("no regression: radius exactly at positionLimit and diameter exactly at 2·positionLimit are the clamp's identity boundary")
    func inRangeSizesAreClampIdentity() throws {
        let atLimit = TurtleEngine.positionLimit
        var circleEngine = makeEngine()
        let center = circleEngine.scalarState
        let circleOutcome = try circleEngine.perform(.circle(radius: atLimit))
        let circleEmission = try #require(circleOutcome.emissions.first)
        for point in circleEmission.pathData {
            let radius = hypot(point.x - center.x, point.y - center.y)
            #expect(abs(radius - atLimit) <= 1e-6, "radius == positionLimit must draw a true, unclamped circle of that radius")
        }

        var dotEngine = makeEngine()
        let dotOutcome = try dotEngine.perform(.dot(diameter: 2 * atLimit))
        let dotEmission = try #require(dotOutcome.emissions.first)
        #expect(dotEmission.frame.width == 2 * atLimit, "diameter == 2·positionLimit must be untouched by the clamp")
        #expect(dotEmission.frame.height == 2 * atLimit)
    }

    @Test("a clamped huge-radius circle inside beginFill/endFill produces a bounded, finite fill polygon (C6)")
    func hugeRadiusCircleInsideFillIsBounded() throws {
        var engine = makeEngine()
        _ = try engine.perform(.beginFill)
        let curveOutcome = try engine.perform(.circle(radius: Self.hugeRadius))
        #expect(curveOutcome.emissions.isEmpty, "a curve while filling feeds the polygon, it does not emit its own part")
        let endOutcome = try engine.perform(.endFill)
        let emission = try #require(endOutcome.emissions.first)
        #expect(emission.kind == .fill)
        // beginFill's initial vertex + the circle's 61 clamped vertices.
        #expect(emission.pathData.count == 62)
        for point in emission.pathData {
            #expect(point.x.isFinite && point.y.isFinite)
            #expect(abs(point.x) <= 2 * TurtleEngine.positionLimit)
            #expect(abs(point.y) <= 2 * TurtleEngine.positionLimit)
        }
        let frame = emission.frame
        #expect(frame.left.isFinite && frame.top.isFinite && frame.width.isFinite && frame.height.isFinite)
        #expect(abs(frame.left) <= 2 * TurtleEngine.positionLimit + emission.strokeWidth / 2)
        #expect(abs(frame.top) <= 2 * TurtleEngine.positionLimit + emission.strokeWidth / 2)
    }

    @Test("dot with an astronomically large diameter clamps to 2·positionLimit: finite, bounded frame spanning exactly that diameter (C8)")
    func hugeDiameterDotClampsToPositionLimit() throws {
        var engine = makeEngine()
        let position = engine.scalarState
        let outcome = try engine.perform(.dot(diameter: Self.hugeRadius))
        let emission = try #require(outcome.emissions.first)
        #expect(emission.kind == .dot)
        let frame = emission.frame
        #expect(frame.left.isFinite && frame.top.isFinite && frame.width.isFinite && frame.height.isFinite)
        // Span == exactly the clamped diameter (not merely "some bounded value").
        #expect(frame.width == 2 * TurtleEngine.positionLimit)
        #expect(frame.height == 2 * TurtleEngine.positionLimit)
        // Every edge within position ± positionLimit (C8), the tighter,
        // position-relative bound (which implies |edge| ≤ 2·positionLimit).
        #expect(abs(frame.left - position.x) <= TurtleEngine.positionLimit)
        #expect(abs(frame.top - position.y) <= TurtleEngine.positionLimit)
        #expect(abs((frame.left + frame.width) - position.x) <= TurtleEngine.positionLimit)
        #expect(abs((frame.top + frame.height) - position.y) <= TurtleEngine.positionLimit)
    }

    @Test("clamping does not touch the E2 error path: negative and zero explicit dot diameters still throw byte-identical copy")
    func clampDoesNotAffectDotDiameterErrorPath() {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: dot needs a diameter greater than 0 (got 0).")) {
            try engine.perform(.dot(diameter: 0))
        }
        #expect(throws: TurtleEngine.TurtleError("turtle: dot needs a diameter greater than 0 (got -7).")) {
            try engine.perform(.dot(diameter: -7))
        }
    }

    @Test("default dot diameter is unaffected by the diameter clamp: default penWidth 2 gives the max(2·penWidth,4) floor of 4")
    func defaultDotDiameterUnaffectedByClamp() throws {
        var engine = makeEngine()
        let outcome = try engine.perform(.dot(diameter: nil))
        let emission = try #require(outcome.emissions.first)
        #expect(emission.frame.width == 4)
        #expect(emission.frame.height == 4)
    }
}

// MARK: - Tester pass (Test gate): deepens `TurtleRadiusClampTests` above
// with a fuzz corpus, extreme-center composition, non-finite inputs,
// randomized metamorphic checks, and vertex-count invariance. Pins
// design.md's Conditions C1, C3, C5, C6, C8. Uses the file's seeded
// `TurtleSeededRNG` (declared further below, in file scope) so any
// failure replays from its printed seed.

@Suite("Radius/diameter clamp — fuzz corpus, extreme-center composition, non-finite inputs, randomized metamorphic, vertex-count invariance")
struct TurtleRadiusClampPropertyTests {

    /// Deterministic fuzz corpus for the RADIUS clamp (circle/arc): spans
    /// just over the cap, several huge magnitudes, the largest finite
    /// double, and the exact identity boundary. Every one of these must
    /// yield a finite result with |coordinate| ≤ 2·positionLimit — never a
    /// crash, never an off-world value (C5).
    static let radiusCorpus: [Double] = [
        TurtleEngine.positionLimit + 1, // just over the cap
        1e7, 1e9, 1e12,
        .greatestFiniteMagnitude,
        TurtleEngine.positionLimit,     // exact identity boundary
        2 * TurtleEngine.positionLimit, // well above the cap
    ]

    /// Same corpus, in diameter units, for `dot`'s own cap
    /// (2·positionLimit) — C8.
    static let diameterCorpus: [Double] = [
        2 * TurtleEngine.positionLimit + 1, // just over the cap
        1e7, 1e9, 1e12,
        .greatestFiniteMagnitude,
        TurtleEngine.positionLimit,         // below the cap — identity
        2 * TurtleEngine.positionLimit,     // exact identity boundary
    ]

    // MARK: 1. Fuzz corpus — bound invariant

    @Test("circle over the fuzz corpus: every vertex is finite, within ±2·positionLimit, and the vertex count never changes (C5)",
          arguments: TurtleRadiusClampPropertyTests.radiusCorpus)
    func circleCorpusStaysBounded(_ radius: Double) throws {
        var engine = makeEngine()
        let outcome = try engine.perform(.circle(radius: radius))
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData.count == 61, "radius \(radius): clamping must not change the vertex count")
        for point in emission.pathData {
            #expect(point.x.isFinite && point.y.isFinite, "radius \(radius): non-finite vertex")
            #expect(abs(point.x) <= 2 * TurtleEngine.positionLimit, "radius \(radius): x \(point.x) exceeds the bound")
            #expect(abs(point.y) <= 2 * TurtleEngine.positionLimit, "radius \(radius): y \(point.y) exceeds the bound")
        }
    }

    @Test("arc over the fuzz corpus: every vertex is finite and within ±2·positionLimit (C5)",
          arguments: TurtleRadiusClampPropertyTests.radiusCorpus)
    func arcCorpusStaysBounded(_ radius: Double) throws {
        var engine = makeEngine()
        let outcome = try engine.perform(.arc(degrees: 200, radius: radius))
        let emission = try #require(outcome.emissions.first)
        for point in emission.pathData {
            #expect(point.x.isFinite && point.y.isFinite, "radius \(radius): non-finite vertex")
            #expect(abs(point.x) <= 2 * TurtleEngine.positionLimit, "radius \(radius): x \(point.x) exceeds the bound")
            #expect(abs(point.y) <= 2 * TurtleEngine.positionLimit, "radius \(radius): y \(point.y) exceeds the bound")
        }
    }

    @Test("dot over the fuzz corpus: every frame edge is finite and within ±2·positionLimit (C8)",
          arguments: TurtleRadiusClampPropertyTests.diameterCorpus)
    func dotCorpusStaysBounded(_ diameter: Double) throws {
        var engine = makeEngine()
        let outcome = try engine.perform(.dot(diameter: diameter))
        let emission = try #require(outcome.emissions.first)
        let frame = emission.frame
        #expect(frame.left.isFinite && frame.top.isFinite && frame.width.isFinite && frame.height.isFinite,
                "diameter \(diameter): non-finite frame")
        #expect(abs(frame.left) <= 2 * TurtleEngine.positionLimit, "diameter \(diameter): left \(frame.left) exceeds the bound")
        #expect(abs(frame.top) <= 2 * TurtleEngine.positionLimit, "diameter \(diameter): top \(frame.top) exceeds the bound")
        #expect(abs(frame.left + frame.width) <= 2 * TurtleEngine.positionLimit, "diameter \(diameter): right edge exceeds the bound")
        #expect(abs(frame.top + frame.height) <= 2 * TurtleEngine.positionLimit, "diameter \(diameter): bottom edge exceeds the bound")
    }

    // MARK: 2. Composition with a clamped, extreme center

    @Test("circle/arc/dot after setPos to an extreme coordinate stay within ±2·positionLimit of the true ORIGIN (position-clamp ∘ size-clamp composition)")
    func extremeCenterComposesWithSizeClamp() throws {
        // setPos(1e12, −1e12) clamps to (positionLimit, −positionLimit) via
        // the engine's OTHER, already-shipped position clamp. This pins the
        // real end-to-end invariant: neither clamp alone is enough — the
        // position clamp and the size clamp must COMPOSE to keep every
        // emission within 2·positionLimit of the true origin, not merely
        // within positionLimit of an already-extreme center.
        var circleEngine = makeEngine()
        _ = try circleEngine.perform(.penUp)
        _ = try circleEngine.perform(.setPos(x: 1e12, y: -1e12))
        #expect(circleEngine.scalarState.x == TurtleEngine.positionLimit)
        #expect(circleEngine.scalarState.y == -TurtleEngine.positionLimit)
        let circleOutcome = try circleEngine.perform(.circle(radius: 1e12))
        let circleEmission = try #require(circleOutcome.emissions.first)
        for point in circleEmission.pathData {
            #expect(point.x.isFinite && point.y.isFinite)
            #expect(abs(point.x) <= 2 * TurtleEngine.positionLimit, "x \(point.x) exceeds 2·positionLimit from the true origin")
            #expect(abs(point.y) <= 2 * TurtleEngine.positionLimit, "y \(point.y) exceeds 2·positionLimit from the true origin")
        }

        var arcEngine = makeEngine()
        _ = try arcEngine.perform(.penUp)
        _ = try arcEngine.perform(.setPos(x: -1e12, y: 1e12))
        #expect(arcEngine.scalarState.x == -TurtleEngine.positionLimit)
        #expect(arcEngine.scalarState.y == TurtleEngine.positionLimit)
        let arcOutcome = try arcEngine.perform(.arc(degrees: 270, radius: 1e12))
        let arcEmission = try #require(arcOutcome.emissions.first)
        for point in arcEmission.pathData {
            #expect(point.x.isFinite && point.y.isFinite)
            #expect(abs(point.x) <= 2 * TurtleEngine.positionLimit)
            #expect(abs(point.y) <= 2 * TurtleEngine.positionLimit)
        }

        var dotEngine = makeEngine()
        _ = try dotEngine.perform(.penUp)
        _ = try dotEngine.perform(.setPos(x: 1e12, y: 1e12))
        let dotOutcome = try dotEngine.perform(.dot(diameter: 1e12))
        let dotEmission = try #require(dotOutcome.emissions.first)
        let frame = dotEmission.frame
        #expect(frame.left.isFinite && frame.top.isFinite && frame.width.isFinite && frame.height.isFinite)
        #expect(abs(frame.left) <= 2 * TurtleEngine.positionLimit)
        #expect(abs(frame.top) <= 2 * TurtleEngine.positionLimit)
        #expect(abs(frame.left + frame.width) <= 2 * TurtleEngine.positionLimit)
        #expect(abs(frame.top + frame.height) <= 2 * TurtleEngine.positionLimit)
    }

    @Test("a huge circle inside beginFill/endFill after an extreme setPos still produces a bounded polygon (C6 × composition)")
    func extremeCenterFillCurveStaysBounded() throws {
        var engine = makeEngine()
        _ = try engine.perform(.penUp)
        _ = try engine.perform(.setPos(x: -1e12, y: -1e12))
        _ = try engine.perform(.beginFill)
        let curveOutcome = try engine.perform(.circle(radius: 1e12))
        #expect(curveOutcome.emissions.isEmpty, "a curve while filling feeds the polygon, it does not emit its own part")
        let endOutcome = try engine.perform(.endFill)
        let emission = try #require(endOutcome.emissions.first)
        #expect(emission.pathData.count == 62) // beginFill's seed vertex + the circle's 61 vertices
        for point in emission.pathData {
            #expect(point.x.isFinite && point.y.isFinite)
            #expect(abs(point.x) <= 2 * TurtleEngine.positionLimit)
            #expect(abs(point.y) <= 2 * TurtleEngine.positionLimit)
        }
    }

    // MARK: 3. Non-finite / sign inputs → E2, byte-exact

    @Test("circle radius NaN/±Infinity sanitize to 0 and raise E2 with the exact 'got 0' copy (C3)",
          arguments: [Double.nan, .infinity, -.infinity])
    func circleNonFiniteRadiusRaisesE2GotZero(_ radius: Double) {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: circle needs a radius greater than 0 (got 0).")) {
            try engine.perform(.circle(radius: radius))
        }
    }

    @Test("arc radius NaN/±Infinity sanitize to 0 and raise E2 with the exact 'got 0' copy (C3)",
          arguments: [Double.nan, .infinity, -.infinity])
    func arcNonFiniteRadiusRaisesE2GotZero(_ radius: Double) {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: arc needs a radius greater than 0 (got 0).")) {
            try engine.perform(.arc(degrees: 90, radius: radius))
        }
    }

    @Test("dot explicit diameter NaN/±Infinity sanitize to 0 and raise E2 with the exact 'got 0' copy (C3)",
          arguments: [Double.nan, .infinity, -.infinity])
    func dotNonFiniteDiameterRaisesE2GotZero(_ diameter: Double) {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: dot needs a diameter greater than 0 (got 0).")) {
            try engine.perform(.dot(diameter: diameter))
        }
    }

    @Test("negative finite radii/diameters still echo the raw value in E2, byte-identical — min() never raises a negative (C1/C8)",
          arguments: [-0.5, -100, -1e6, -1e12])
    func negativeFiniteSizesEchoRawValue(_ negative: Double) {
        var circleEngine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: circle needs a radius greater than 0 (got \(HypeTalkFormat.number(negative))).")) {
            try circleEngine.perform(.circle(radius: negative))
        }
        var arcEngine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: arc needs a radius greater than 0 (got \(HypeTalkFormat.number(negative))).")) {
            try arcEngine.perform(.arc(degrees: 90, radius: negative))
        }
        var dotEngine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("turtle: dot needs a diameter greater than 0 (got \(HypeTalkFormat.number(negative))).")) {
            try dotEngine.perform(.dot(diameter: negative))
        }
    }

    // MARK: 4. Metamorphic, randomized: any two huge radii clamp identically

    @Test("randomized: any two radii > positionLimit clamp to the identical circle polygon, and arc 360 at that radius matches too (metamorphic)",
          arguments: 0..<50)
    func randomHugeRadiiClampIdentically(seed: Int) throws {
        var rng = TurtleSeededRNG(seed: UInt64(seed) &* 0xA24BAED4963EE407 &+ 11)
        let r1 = rng.double((TurtleEngine.positionLimit + 1)...1e15)
        let r2 = rng.double((TurtleEngine.positionLimit + 1)...1e15)

        var engine1 = makeEngine()
        var engine2 = makeEngine()
        let outcome1 = try engine1.perform(.circle(radius: r1))
        let outcome2 = try engine2.perform(.circle(radius: r2))
        let path1 = try #require(outcome1.emissions.first, "seed \(seed): r1=\(r1)").pathData
        let path2 = try #require(outcome2.emissions.first, "seed \(seed): r2=\(r2)").pathData
        #expect(path1 == path2, "seed \(seed): r1=\(r1) and r2=\(r2) both clamp to positionLimit, so their circles must be byte-identical")

        var arcEngine = makeEngine()
        let arcOutcome = try arcEngine.perform(.arc(degrees: 360, radius: r1))
        let arcPath = try #require(arcOutcome.emissions.first, "seed \(seed): arc r=\(r1)").pathData
        #expect(arcPath == path1, "seed \(seed): arc 360 at r1=\(r1) must equal circle at the same clamped radius")
    }

    // MARK: 5. Vertex-count invariance (resource / non-functional) — the
    // clamp changes MAGNITUDE only, never vertex count, so it cannot
    // interact with `maxPathPointsPerRun`/`maxPartsPerRun` (§5.5).

    @Test("circle vertex count (61) is identical for a normal and an astronomically clamped radius")
    func circleVertexCountInvariantUnderClamp() throws {
        var normalEngine = makeEngine()
        var hugeEngine = makeEngine()
        let normal = try normalEngine.perform(.circle(radius: 42))
        let huge = try hugeEngine.perform(.circle(radius: .greatestFiniteMagnitude))
        let normalCount = try #require(normal.emissions.first).pathData.count
        let hugeCount = try #require(huge.emissions.first).pathData.count
        #expect(normalCount == 61)
        #expect(hugeCount == 61)
        #expect(normalCount == hugeCount,
                "the clamp changes magnitude only — vertex count (and therefore the maxPathPointsPerRun budget) is unaffected by radius size")
    }

    @Test("arc vertex count is identical for a normal and an astronomically clamped radius, at several degree spans",
          arguments: [1.0, 45, 90, 200, 360])
    func arcVertexCountInvariantUnderClamp(_ degrees: Double) throws {
        var normalEngine = makeEngine()
        var hugeEngine = makeEngine()
        let normal = try normalEngine.perform(.arc(degrees: degrees, radius: 42))
        let huge = try hugeEngine.perform(.arc(degrees: degrees, radius: .greatestFiniteMagnitude))
        let normalCount = try #require(normal.emissions.first).pathData.count
        let hugeCount = try #require(huge.emissions.first).pathData.count
        #expect(normalCount == hugeCount,
                "degrees=\(degrees): the clamp must not change the arc's segment count (max(8, ceil(|degrees|/6)) + 1), only its magnitude")
    }
}

// MARK: - Criterion 15 (engine half) — limits, atomicity

@Suite("Limits — E8 atomicity, per-run part and point caps")
struct TurtleLimitsTests {

    @Test("more than 200 parts in a run raises E8; the 200th call already succeeded")
    func partCapRaisesE8() throws {
        var engine = makeEngine()
        for i in 0..<TurtleEngine.maxPartsPerRun {
            let outcome = try engine.perform(.dot(diameter: 4))
            #expect(outcome.emissions.count == 1, "dot #\(i) should still succeed under the cap")
        }
        #expect(throws: TurtleEngine.TurtleError("turtle: drawing limit reached — a single run may draw at most 200 shapes and 50000 points.")) {
            try engine.perform(.dot(diameter: 4))
        }
    }

    @Test("more than 50,000 points in a run raises E8 atomically, leaving position unchanged")
    func pointCapRaisesE8Atomically() throws {
        var engine = makeEngine()
        _ = try engine.perform(.setHeading(90)) // move along +x so every step is distinct, well within ±1,000,000
        // First call buffers 2 points (start + destination); each
        // subsequent call buffers 1 more. maxPathPointsPerRun total
        // points are reached after maxPathPointsPerRun - 1 calls.
        for _ in 0..<(TurtleEngine.maxPathPointsPerRun - 1) {
            _ = try engine.perform(.forward(1))
        }
        let before = engine.scalarState
        #expect(throws: TurtleEngine.TurtleError("turtle: drawing limit reached — a single run may draw at most 200 shapes and 50000 points.")) {
            try engine.perform(.forward(1))
        }
        #expect(engine.scalarState == before, "a command that would exceed a limit leaves state fully unchanged")
    }

    @Test("clean discards buffers instead of emitting and requests deletion")
    func cleanDiscardsBuffers() throws {
        var engine = makeEngine()
        _ = try engine.perform(.forward(10))
        let outcome = try engine.perform(.clean)
        #expect(outcome.deletesTurtleParts)
        #expect(outcome.emissions.isEmpty)
        #expect(engine.hasOpenStroke == false)
        // The stroke was discarded, not flushed, so ending the run now
        // produces nothing.
        #expect(engine.endRun().emissions.isEmpty)
    }

    @Test("clearScreen deletes, homes without drawing, and resets heading")
    func clearScreenHomesWithoutDrawing() throws {
        var engine = makeEngine()
        _ = try engine.perform(.right(45))
        _ = try engine.perform(.forward(200))
        let outcome = try engine.perform(.clearScreen)
        #expect(outcome.deletesTurtleParts)
        #expect(outcome.emissions.isEmpty)
        #expect(engine.scalarState.x == 400)
        #expect(engine.scalarState.y == 300)
        #expect(engine.scalarState.heading == 0)
        #expect(engine.endRun().emissions.isEmpty)
    }

    @Test("resetTurtle restores defaults without deleting parts")
    func resetTurtleRestoresDefaults() throws {
        var engine = makeEngine()
        _ = try engine.perform(.right(45))
        _ = try engine.perform(.forward(200))
        _ = try engine.perform(.setPenColor("red"))
        let outcome = try engine.perform(.resetTurtle)
        #expect(outcome.deletesTurtleParts == false)
        #expect(outcome.emissions.isEmpty)
        #expect(engine.scalarState == TurtleEngine.ScalarState.defaults(canvas: TurtleEngine.Canvas(width: 800, height: 600)))
    }
}

// MARK: - ScalarState encoding round-trip

@Suite("ScalarState — encode/decode round-trip")
struct TurtleScalarStateEncodingTests {

    @Test("encoded round-trips through init?(encoded:) exactly")
    func roundTrip() {
        let state = TurtleEngine.ScalarState(
            x: 123.456, y: -78.9, heading: 271.5, penDown: false,
            penColor: "#AABBCC", penWidth: 12.5, fillColor: "#112233"
        )
        let decoded = TurtleEngine.ScalarState(encoded: state.encoded)
        #expect(decoded == state)
    }

    @Test("defaults(canvas:) is the card center, heading 0, pen down, black pen/fill at width 2")
    func defaultsAreCardCenter() {
        let canvas = TurtleEngine.Canvas(width: 800, height: 600)
        let defaults = TurtleEngine.ScalarState.defaults(canvas: canvas)
        #expect(defaults.x == 400)
        #expect(defaults.y == 300)
        #expect(defaults.heading == 0)
        #expect(defaults.penDown)
        #expect(defaults.penColor == "#000000")
        #expect(defaults.penWidth == 2)
        #expect(defaults.fillColor == "#000000")
    }

    @Test("malformed encodings decode to nil", arguments: [
        "",
        "garbage",
        "v1|1|2|3|1|2|#000000", // too few fields
        "v2|1|2|3|1|2|#000000|#000000", // wrong version
        "v1|nan-not-a-number|2|3|1|2|#000000|#000000",
    ])
    func malformedEncodingIsNil(_ raw: String) {
        #expect(TurtleEngine.ScalarState(encoded: raw) == nil)
    }
}

// MARK: - Property surface (engine-level; interpreter integration is P2)

@Suite("Property surface — GET/SET, aliases, read-only, unknown")
struct TurtlePropertySurfaceTests {

    @Test("position/loc/location GET return \"x,y\"; xcor/ycor/heading/penWidth GET are numeric")
    func getters() throws {
        var engine = makeEngine()
        _ = try engine.perform(.setHeading(45))
        #expect(try engine.propertyValue("position") == "400,300")
        #expect(try engine.propertyValue("loc") == "400,300")
        #expect(try engine.propertyValue("location") == "400,300")
        #expect(try engine.propertyValue("xcor") == "400")
        #expect(try engine.propertyValue("ycor") == "300")
        #expect(try engine.propertyValue("heading") == "45")
        #expect(try engine.propertyValue("penWidth") == "2")
        #expect(try engine.propertyValue("penColor") == "#000000")
        #expect(try engine.propertyValue("fillColor") == "#000000")
        #expect(try engine.propertyValue("penDown") == "true")
        #expect(try engine.propertyValue("filling") == "false")
    }

    @Test("set the heading of the turtle to 45 matches perform(.setHeading(45))")
    func setHeadingPropertyMatchesCommand() throws {
        var engine = makeEngine()
        _ = try engine.setProperty("heading", to: "45")
        #expect(try engine.propertyValue("heading") == "45")
    }

    @Test("xcor/ycor/filling are read-only on SET")
    func readOnlyProperties() {
        var engine = makeEngine()
        #expect(throws: TurtleEngine.TurtleError("\"xcor\" of the turtle is read-only — set the position instead.")) {
            try engine.setProperty("xcor", to: "10")
        }
        #expect(throws: TurtleEngine.TurtleError("\"ycor\" of the turtle is read-only — set the position instead.")) {
            try engine.setProperty("ycor", to: "10")
        }
        #expect(throws: TurtleEngine.TurtleError("\"filling\" of the turtle is read-only — use beginFill and endFill.")) {
            try engine.setProperty("filling", to: "true")
        }
    }

    @Test("an unknown property errors on GET and SET with the exact registry-style copy")
    func unknownPropertyErrors() {
        var engine = makeEngine()
        let expectedMessage = "no such property \"bogus\" for the turtle — the turtle has position, xcor, ycor, heading, penDown, penColor, penWidth, fillColor, and filling."
        #expect(throws: TurtleEngine.TurtleError(expectedMessage)) {
            try engine.propertyValue("bogus")
        }
        #expect(throws: TurtleEngine.TurtleError(expectedMessage)) {
            try engine.setProperty("bogus", to: "1")
        }
    }

    @Test("set the position of the turtle to \"x,y\" moves the turtle like setPos")
    func setPositionProperty() throws {
        var engine = makeEngine()
        _ = try engine.setProperty("position", to: "10,20")
        #expect(engine.scalarState.x == 10)
        #expect(engine.scalarState.y == 20)
    }

    @Test("set the penDown of the turtle to false/true routes through penUp/penDown")
    func setPenDownProperty() throws {
        var engine = makeEngine()
        _ = try engine.setProperty("pendown", to: "false")
        #expect(engine.scalarState.penDown == false)
        _ = try engine.setProperty("pendown", to: "true")
        #expect(engine.scalarState.penDown == true)
    }
}

// MARK: - TurtleVocabulary (D3)

@Suite("TurtleVocabulary — verb map, abbreviations, zero-argument verbs")
struct TurtleVocabularyTests {

    @Test("abbreviations map to the same command as their long form")
    func abbreviationsMatchLongForm() {
        #expect(TurtleVocabulary.command(verb: "fd", args: ["10"]) == TurtleVocabulary.command(verb: "forward", args: ["10"]))
        #expect(TurtleVocabulary.command(verb: "bk", args: ["10"]) == TurtleVocabulary.command(verb: "back", args: ["10"]))
        #expect(TurtleVocabulary.command(verb: "rt", args: ["10"]) == TurtleVocabulary.command(verb: "right", args: ["10"]))
        #expect(TurtleVocabulary.command(verb: "lt", args: ["10"]) == TurtleVocabulary.command(verb: "left", args: ["10"]))
        #expect(TurtleVocabulary.command(verb: "seth", args: ["10"]) == TurtleVocabulary.command(verb: "setheading", args: ["10"]))
        #expect(TurtleVocabulary.command(verb: "setxy", args: ["1", "2"]) == TurtleVocabulary.command(verb: "setpos", args: ["1", "2"]))
        #expect(TurtleVocabulary.command(verb: "pu", args: []) == TurtleVocabulary.command(verb: "penup", args: []))
        #expect(TurtleVocabulary.command(verb: "pd", args: []) == TurtleVocabulary.command(verb: "pendown", args: []))
        #expect(TurtleVocabulary.command(verb: "cs", args: []) == TurtleVocabulary.command(verb: "clearscreen", args: []))
    }

    @Test("missing numeric arguments coerce to 0; extra arguments are ignored")
    func missingArgsCoerceToZero() {
        #expect(TurtleVocabulary.command(verb: "forward", args: []) == .forward(0))
        #expect(TurtleVocabulary.command(verb: "forward", args: ["10", "ignored", "also-ignored"]) == .forward(10))
    }

    @Test("dot accepts zero or one argument")
    func dotAcceptsZeroOrOneArgument() {
        #expect(TurtleVocabulary.command(verb: "dot", args: []) == .dot(diameter: nil))
        #expect(TurtleVocabulary.command(verb: "dot", args: ["8"]) == .dot(diameter: 8))
    }

    @Test("a non-turtle verb returns nil")
    func nonTurtleVerbReturnsNil() {
        #expect(TurtleVocabulary.command(verb: "goto", args: ["10"]) == nil)
        #expect(TurtleVocabulary.isTurtleVerb("goto") == false)
    }

    @Test("zeroArgumentVerbs matches the design.md D3 set exactly")
    func zeroArgumentVerbSet() {
        let expected: Set<String> = [
            "penup", "pendown", "pu", "pd", "home",
            "beginfill", "endfill", "clean", "clearscreen", "cs", "dot",
        ]
        #expect(TurtleVocabulary.zeroArgumentVerbs == expected)
    }
}

// MARK: - Tester deepening (Test gate): property / metamorphic / resource /
// accessibility / edge passes the Builder's inline suites don't cover.
//
// Everything below is engine-level and pure (no document, no interpreter),
// mirroring the file's existing `makeEngine()` idiom. Seeded PRNG cases are
// reproducible: a failing seed prints in the message so it can be replayed
// and pinned.

/// SplitMix64 — the same small, reproducible generator the fuzz harness
/// uses, redeclared file-privately here (the fuzz copy is file-private to
/// `InterpreterFuzzTests.swift`). Seeded per case so any failure replays.
private struct TurtleSeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) // 2^-53
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func bool() -> Bool { next() & 1 == 0 }
}

/// The engine's own heading contract, recomputed independently as the test
/// oracle: non-finite coerces to 0, then `((h mod 360)+360) mod 360`.
private func referenceNormalizedHeading(_ h: Double) -> Double {
    let sanitized = h.isFinite ? h : 0
    let m = sanitized.truncatingRemainder(dividingBy: 360)
    return (m + 360).truncatingRemainder(dividingBy: 360)
}

// MARK: - Property: heading normalization is always in [0,360)

@Suite("Heading normalization is total and always in [0,360)")
struct TurtleHeadingNormalizationTests {

    /// The interesting non-random inputs: cardinal exacts, negatives,
    /// wrap boundaries, huge magnitudes, and the non-finite trio.
    static let headingInputs: [Double] = [
        0, 90, 180, 270, 359.999, 360, 450, 720, -0.0, -1, -90, -359, -360, -450, -720,
        0.5, 123.456, 1_000_000.25, 1e15, -1e15, 1e300, -1e300,
        .nan, .infinity, -.infinity,
    ]

    @Test("setHeading normalizes every input into [0,360) matching the reference formula",
          arguments: TurtleHeadingNormalizationTests.headingInputs)
    func setHeadingNormalizes(_ h: Double) throws {
        var engine = makeEngine()
        _ = try engine.perform(.setHeading(h))
        let heading = engine.scalarState.heading
        #expect(heading >= 0 && heading < 360, "setHeading(\(h)) left heading out of [0,360): \(heading)")
        #expect(heading == referenceNormalizedHeading(h), "setHeading(\(h)) = \(heading), expected \(referenceNormalizedHeading(h))")
    }

    @Test("right/left over arbitrary (huge / negative / non-finite) deltas keep heading in [0,360)",
          arguments: 0..<200)
    func rotationsStayNormalized(seed: Int) throws {
        var rng = TurtleSeededRNG(seed: UInt64(seed) &* 0x100000001B3 &+ 1)
        var engine = makeEngine()
        // A random but finite starting heading.
        let start = rng.double(-10_000...10_000)
        _ = try engine.perform(.setHeading(start))

        // Apply a handful of random right/left turns, including occasional
        // huge or non-finite deltas, checking the [0,360) invariant after
        // every single one.
        var expected = referenceNormalizedHeading(start)
        for _ in 0..<8 {
            let delta: Double
            switch rng.next() % 5 {
            case 0: delta = rng.double(-720...720)
            case 1: delta = rng.double(-1_000_000...1_000_000)
            case 2: delta = 1e18
            case 3: delta = .nan
            default: delta = rng.double(-360...360)
            }
            let sanitized = delta.isFinite ? delta : 0
            if rng.bool() {
                _ = try engine.perform(.right(delta))
                expected = referenceNormalizedHeading(expected + sanitized)
            } else {
                _ = try engine.perform(.left(delta))
                expected = referenceNormalizedHeading(expected - sanitized)
            }
            let heading = engine.scalarState.heading
            #expect(heading >= 0 && heading < 360, "seed \(seed): heading escaped [0,360): \(heading)")
            #expect(heading == expected, "seed \(seed): heading \(heading) != expected \(expected)")
        }
    }
}

// MARK: - Property/metamorphic: closed polygons, circle tolerance, arc≈circle

@Suite("Geometry properties — N-gon closure, circle radius tolerance, arc≡circle")
struct TurtleGeometryPropertyTests {

    /// N×(forward L, right 360/N) from a pen-down start must produce ONE
    /// stroke part of N+1 vertices whose closing vertex returns to the
    /// start — exact for the cardinal N=4, within a tight FP tolerance for
    /// the non-cardinal regular polygons.
    @Test("regular N-gon closes back to its start vertex",
          arguments: [3, 4, 5, 6, 8, 12])
    func regularPolygonCloses(_ n: Int) throws {
        var engine = makeEngine()
        let length = 120.0
        let turn = 360.0 / Double(n)
        for _ in 0..<n {
            _ = try engine.perform(.forward(length))
            _ = try engine.perform(.right(turn))
        }
        let outcome = engine.endRun()
        #expect(outcome.emissions.count == 1, "an N-gon walk is one continuous stroke")
        let path = try #require(outcome.emissions.first).pathData
        #expect(path.count == n + 1, "N=\(n): expected \(n + 1) vertices, got \(path.count)")
        let first = try #require(path.first)
        let last = try #require(path.last)
        let gap = hypot(last.x - first.x, last.y - first.y)
        #expect(gap <= 1e-6, "N=\(n): closing vertex drifted \(gap) from the start")
    }

    @Test("circle r vertices all lie within the design tolerance (r·(1−cos3°)) of r, for a range of r",
          arguments: [1.0, 3.5, 10, 22, 50, 100, 250, 1000])
    func circleVerticesWithinTolerance(_ r: Double) throws {
        var engine = makeEngine()
        _ = try engine.perform(.setHeading(37)) // non-cardinal start angle
        let center = engine.scalarState
        let outcome = try engine.perform(.circle(radius: r))
        let path = try #require(outcome.emissions.first).pathData
        #expect(path.count == 61)
        #expect(path.first == path.last, "circle must close exactly (vertex 60 copied from vertex 0)")
        // §5.4 chord tolerance: every polyline vertex is exactly on the
        // circle, so the only error is FP; assert a generous but tight
        // absolute-plus-relative bound.
        let tolerance = max(1e-9, r * 1e-12)
        for point in path {
            let radius = hypot(point.x - center.x, point.y - center.y)
            #expect(abs(radius - r) <= tolerance, "r=\(r): vertex radius \(radius) off by \(abs(radius - r))")
        }
    }

    @Test("arc 360, r draws exactly the same polygon as circle r (metamorphic)",
          arguments: [1.0, 7, 22, 50, 137.5, 400])
    func arc360EqualsCircle(_ r: Double) throws {
        var circleEngine = makeEngine()
        var arcEngine = makeEngine()
        _ = try circleEngine.perform(.setHeading(53))
        _ = try arcEngine.perform(.setHeading(53))
        let circleOutcome = try circleEngine.perform(.circle(radius: r))
        let arcOutcome = try arcEngine.perform(.arc(degrees: 360, radius: r))
        let circlePath = try #require(circleOutcome.emissions.first).pathData
        let arcPath = try #require(arcOutcome.emissions.first).pathData
        #expect(arcPath.count == circlePath.count, "arc 360 and circle must have the same vertex count for r=\(r)")
        for (a, c) in zip(arcPath, circlePath) {
            #expect(hypot(a.x - c.x, a.y - c.y) <= 1e-9, "arc 360 diverged from circle at r=\(r)")
        }
    }
}

// MARK: - Property: ScalarState encode/decode round-trips exactly

@Suite("ScalarState round-trips exactly for random states")
struct TurtleScalarStateRandomRoundTripTests {

    @Test("encode → decode is the identity for arbitrary finite states",
          arguments: 0..<200)
    func randomRoundTrip(seed: Int) throws {
        var rng = TurtleSeededRNG(seed: UInt64(seed) &* 0x2545F4914F6CDD1D &+ 7)
        func hex() -> String { String(format: "#%06X", Int(rng.double(0...Double(0xFFFFFF)))) }
        let state = TurtleEngine.ScalarState(
            x: rng.double(-1_000_000...1_000_000),
            y: rng.double(-1_000_000...1_000_000),
            heading: rng.double(0...359.999),
            penDown: rng.bool(),
            penColor: hex(),
            penWidth: rng.double(0.5...100),
            fillColor: hex()
        )
        let decoded = try #require(TurtleEngine.ScalarState(encoded: state.encoded),
                                   "seed \(seed): a well-formed state failed to decode: \(state.encoded)")
        #expect(decoded == state, "seed \(seed): round-trip changed the state")
    }
}

// MARK: - Determinism: same commands on two fresh engines → identical parts

@Suite("Determinism — identical command streams emit byte-identical shapes")
struct TurtleDeterminismTests {

    @Test("two fresh engines running the same varied program emit identical emissions")
    func identicalProgramsAreByteIdentical() throws {
        func run() throws -> [TurtleEngine.Emission] {
            var engine = makeEngine()
            var emissions: [TurtleEngine.Emission] = []
            let commands: [TurtleEngine.Command] = [
                .setPenColor("blue"), .setPenWidth(3), .forward(120), .right(90),
                .forward(60), .setPenColor("red"), .forward(40), .circle(radius: 22),
                .setHeading(210), .arc(degrees: 135, radius: 33), .dot(diameter: 9),
                .beginFill, .forward(50), .right(120), .forward(50), .right(120),
                .forward(50), .endFill,
            ]
            for command in commands { emissions += try engine.perform(command).emissions }
            emissions += engine.endRun().emissions
            return emissions
        }
        // `Emission` is `Equatable`; two independent runs must be bit-equal.
        let first = try run()
        let second = try run()
        #expect(first == second, "the engine is deterministic — identical inputs must yield identical shapes")
    }
}

// MARK: - Edge cases the inline suites don't reach

@Suite("Edge cases — zero moves, radius epsilon, clamping, pen-up fill, boundary fills")
struct TurtleEdgeCaseTests {

    @Test("forward 0 buffers a single point and emits no stroke part")
    func zeroLengthMoveEmitsNothing() throws {
        var engine = makeEngine()
        let move = try engine.perform(.forward(0))
        #expect(move.emissions.isEmpty)
        #expect(engine.scalarState.x == 400 && engine.scalarState.y == 300, "forward 0 never moves")
        #expect(engine.endRun().emissions.isEmpty, "a zero-length trail has < 2 distinct vertices — no part")
    }

    @Test("circle with a radius just above 0 succeeds with a full 61-vertex ring")
    func circleJustAboveZeroSucceeds() throws {
        var engine = makeEngine()
        let outcome = try engine.perform(.circle(radius: 0.0001))
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData.count == 61)
        #expect(emission.pathData.first == emission.pathData.last)
    }

    @Test("setPos clamps each coordinate to ±positionLimit")
    func setPosClampsAtPositionLimit() throws {
        var engine = makeEngine()
        _ = try engine.perform(.penUp) // don't draw the huge segment
        _ = try engine.perform(.setPos(x: 5_000_000, y: -5_000_000))
        #expect(engine.scalarState.x == TurtleEngine.positionLimit)
        #expect(engine.scalarState.y == -TurtleEngine.positionLimit)
    }

    @Test("setPos with non-finite coordinates coerces them to 0 (never NaN in state)")
    func setPosNonFiniteCoercesToZero() throws {
        var engine = makeEngine()
        _ = try engine.perform(.penUp)
        _ = try engine.perform(.setPos(x: .infinity, y: .nan))
        #expect(engine.scalarState.x == 0)
        #expect(engine.scalarState.y == 0)
    }

    @Test("pen up mid-fill still feeds the polygon (d6); pen state at endFill sets outline width 0")
    func penUpMidFillStillFeedsPolygon() throws {
        var engine = makeEngine()
        _ = try engine.perform(.beginFill)          // seed vertex
        _ = try engine.perform(.forward(50))        // + vertex 2
        let penUp = try engine.perform(.penUp)
        #expect(penUp.emissions.isEmpty, "penUp while filling must not flush a stray stroke part")
        #expect(engine.isFilling, "penUp must not end the fill")
        _ = try engine.perform(.right(120))
        _ = try engine.perform(.forward(50))        // + vertex 3, though pen is up
        let outcome = try engine.perform(.endFill)
        let emission = try #require(outcome.emissions.first)
        #expect(emission.kind == .fill)
        #expect(emission.pathData.count == 3, "movement while filling feeds the polygon regardless of pen state (d6)")
        #expect(emission.strokeWidth == 0, "pen up at endFill → zero-width outline")
    }

    @Test("a fill with exactly 3 accumulated vertices succeeds (the 3-vs-2 boundary above E6)")
    func exactlyThreeVertexFillSucceeds() throws {
        var engine = makeEngine()
        _ = try engine.perform(.beginFill)   // vertex 1 (seed)
        _ = try engine.perform(.forward(10)) // vertex 2
        _ = try engine.perform(.right(90))
        _ = try engine.perform(.forward(10)) // vertex 3
        let outcome = try engine.perform(.endFill)
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData.count == 3)
        #expect(outcome.resultNote == nil, "3 vertices is at the boundary — no E6 note")
    }

    @Test("setPenColor is case-insensitive: RED ≡ red ≡ Red ≡ rEd all resolve to #FF0000")
    func namedColorIsCaseInsensitiveThroughEngine() throws {
        for spelling in ["red", "RED", "Red", "rEd"] {
            var engine = makeEngine()
            _ = try engine.perform(.setPenColor(spelling))
            #expect(engine.scalarState.penColor == "#FF0000", "\(spelling) should resolve to #FF0000")
        }
    }
}

// MARK: - Resource / limit bounds (non-functional)

@Suite("Resource bounds — cap boundaries, point accounting, near-limit completion")
struct TurtleResourceBoundsTests {

    @Test("endRun may emit the open stroke even when the run already sits at the 200-part cap")
    func endRunEmitsBonusStrokeAtPartCap() throws {
        var engine = makeEngine()
        _ = try engine.perform(.forward(100)) // opens a 2-vertex stroke (points reserved, 0 parts)
        for _ in 0..<TurtleEngine.maxPartsPerRun {
            _ = try engine.perform(.dot(diameter: 4)) // 200 dot parts — exactly at the cap
        }
        #expect(throws: TurtleEngine.TurtleError.self, "a 201st emitting command must throw E8") {
            try engine.perform(.dot(diameter: 4))
        }
        let end = engine.endRun()
        #expect(end.emissions.count == 1, "endRun flushes the open stroke even at the part cap (the bounded +1)")
        #expect(end.emissions.first?.kind == .path)
    }

    @Test("each circle contributes exactly 61 vertices to a fill — point accounting matches emitted geometry")
    func fillPointAccountingMatchesGeometry() throws {
        var engine = makeEngine()
        _ = try engine.perform(.beginFill) // seed vertex (1 point)
        let circles = 200
        for _ in 0..<circles { _ = try engine.perform(.circle(radius: 20)) }
        let outcome = try engine.perform(.endFill)
        let emission = try #require(outcome.emissions.first)
        #expect(emission.pathData.count == 1 + 61 * circles,
                "the emitted polygon must carry exactly the points the engine reserved — no phantom/lost vertices")
    }

    @Test("a fill of exactly 50,000 points succeeds; the 50,001st point throws E8 atomically")
    func exactlyAtPointCapSucceedsOneMoreThrows() throws {
        var engine = makeEngine()
        _ = try engine.perform(.setHeading(90)) // travel +x so every step is a distinct vertex
        _ = try engine.perform(.beginFill)      // point 1 (the seed)
        for _ in 0..<(TurtleEngine.maxPathPointsPerRun - 1) {
            _ = try engine.perform(.forward(1))  // 49,999 appends → exactly 50,000 points buffered
        }
        #expect(throws: TurtleEngine.TurtleError.self, "the point that would make 50,001 must throw E8") {
            try engine.perform(.forward(1))
        }
        // The throw was atomic: the polygon is still exactly at the cap and closes.
        let outcome = try engine.perform(.endFill)
        #expect(outcome.emissions.first?.pathData.count == TurtleEngine.maxPathPointsPerRun)
    }

    @Test("a representative near-part-cap run (199 standalone circles) completes within both caps")
    func nearCapRunCompletesWithinBudget() throws {
        var engine = makeEngine()
        var emittedParts = 0
        var emittedPoints = 0
        let circles = TurtleEngine.maxPartsPerRun - 1 // 199 standalone circle parts
        for _ in 0..<circles {
            let outcome = try engine.perform(.circle(radius: 15))
            emittedParts += outcome.emissions.count
            emittedPoints += outcome.emissions.reduce(0) { $0 + $1.pathData.count }
        }
        // Assert on operation/point counts, not wall-clock (per the Test brief).
        #expect(emittedParts == circles, "each standalone circle emits exactly one part")
        #expect(emittedPoints == circles * 61)
        #expect(emittedParts <= TurtleEngine.maxPartsPerRun)
        #expect(emittedPoints <= TurtleEngine.maxPathPointsPerRun)
        #expect(engine.endRun().emissions.isEmpty, "no open stroke remains after standalone circles")
    }
}

// MARK: - Accessibility / representation parity with hand-drawn freeform

@Suite("Turtle output carries the same inspectable representation as hand-drawn parts")
struct TurtleAccessibilityRepresentationTests {

    /// Turtle drawings are ordinary shape parts (design-mock §9): they must
    /// carry the same accessible identity (a non-empty, reserved-prefix
    /// name), part-list membership, visibility, and editable shape type a
    /// hand-authored freeform part has — the feature adds no inaccessible
    /// surface. This asserts what is machine-checkable at the model layer;
    /// the rendered/inspector surface is the Designer Sign-off's domain.
    @Test("applied stroke/dot parts are named, visible, editable, and members of the document like a hand-drawn freeform")
    func turtlePartsMatchHandDrawnFreeformRepresentation() throws {
        var document = HypeDocument.newDocument()
        let cardId = document.cards[0].id

        var engine = makeEngine()
        _ = try engine.perform(.forward(100))            // a stroke
        let dotOutcome = try engine.perform(.dot(diameter: 12))
        TurtlePartApplier.apply(dotOutcome, to: &document, cardId: cardId)
        let strokeOutcome = engine.endRun()
        TurtlePartApplier.apply(strokeOutcome, to: &document, cardId: cardId)

        let parts = document.parts.filter { $0.cardId == cardId }
        #expect(parts.count == 2, "one dot part and one stroke part should have been applied")

        // A hand-authored freeform reference part — the representation the
        // turtle output must be indistinguishable from at the model layer.
        let handDrawn = { () -> Part in
            var p = Part(partType: .shape, cardId: cardId, name: "hand freeform")
            p.shapeType = .freeform
            return p
        }()

        for part in parts {
            #expect(!part.name.isEmpty, "an emitted part must always be named (its accessible identity)")
            #expect(TurtlePartApplier.namePrefixes.contains { part.name.hasPrefix($0) },
                    "\(part.name) must carry a reserved turtle prefix")
            #expect(part.partType == handDrawn.partType, "turtle parts are ordinary shape parts")
            #expect(part.visible, "emitted parts are visible like any drawn part")
            #expect(part.script.isEmpty, "emitted parts carry no attached script")
            #expect(part.shapeType == .freeform || part.shapeType == .oval,
                    "turtle output uses the existing editable freeform/oval shapes — no new part type")
            // Membership + inspectability: the part is addressable by its name.
            #expect(document.parts.contains { $0.id == part.id })
        }

        // The stroke part specifically shares the hand-drawn freeform's
        // shapeType — proving representation parity, not just non-nil.
        let strokePart = try #require(parts.first { $0.shapeType == .freeform })
        #expect(strokePart.shapeType == handDrawn.shapeType)
    }
}

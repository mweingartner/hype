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

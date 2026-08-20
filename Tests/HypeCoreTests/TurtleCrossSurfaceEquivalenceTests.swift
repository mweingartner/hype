import Testing
import Foundation
@testable import HypeCore

// AI-tool-surface tests for `turtle-graphics` P3 (design.md test plan,
// `TurtleCrossSurfaceEquivalenceTests.swift`): criterion 18 (cross-surface
// equivalence — the mandatory crux of this package), criterion 16
// (`draw_with_turtle` tool contract), criterion 17 (all-or-nothing
// refusal), and the Security C4/C14 escape-case and containment evidence
// called out in design.md's Conditions for Builder 4 and 14.

// MARK: - Test support

/// The canonical Turtle Garden program body (design-mock.md §8), with the
/// `on mouseUp` / `end mouseUp` wrapper stripped — this exact text is both
/// the HypeTalk handler body under test and the `draw_with_turtle`
/// payload, so any divergence between the two surfaces would show up as
/// a field mismatch below.
private let turtleGardenProgramBody = """
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
"""

/// A structural fingerprint of a turtle-drawn `Part`, covering every
/// field the "Cross-surface equivalence" requirement calls out —
/// `pathData`, `shapeType`, `fillColor`, `strokeColor`, `strokeWidth`,
/// frame, and `name` — explicitly excluding `id` and `sortKey`.
private struct TurtlePartFingerprint: Equatable {
    let name: String
    let shapeType: ShapeType
    let pathData: [PathPoint]
    let fillColor: String
    let strokeColor: String
    let strokeWidth: Double
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    init(_ part: Part) {
        name = part.name
        shapeType = part.shapeType
        pathData = part.pathData
        fillColor = part.fillColor
        strokeColor = part.strokeColor
        strokeWidth = part.strokeWidth
        left = part.left
        top = part.top
        width = part.width
        height = part.height
    }
}

/// Runs `source` (a full `on <handlerName> ... end <handlerName>` script)
/// against `document` on the HypeTalk surface and returns the result.
/// Mirrors `InterpreterFuzzTests.swift`'s `execTurtleHandler` helper — a
/// direct async call is sufficient for these programs (no pathological
/// nesting is involved).
private func runHypeTalkHandler(_ source: String, document: HypeDocument, cardId: UUID) async -> ExecutionResult {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else {
        return ExecutionResult(status: .error, error: ScriptError(message: "parse error", line: 0, handler: "test"))
    }
    let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
    return await Interpreter().executeAsync(handler: handler, params: [], context: context)
}

// MARK: - Criterion 18: cross-surface equivalence (mandatory)

@Suite("Cross-surface equivalence — Turtle Garden on both surfaces (criterion 18)")
struct TurtleGardenEquivalenceTests {

    @Test("The Turtle Garden program produces field-identical parts on the HypeTalk and draw_with_turtle surfaces")
    func gardenProgramIsFieldIdenticalOnBothSurfaces() async throws {
        var hypeTalkDoc = HypeDocument.newDocument(name: "Garden")
        hypeTalkDoc.cards[0].name = "Garden"
        let hypeTalkCardId = hypeTalkDoc.cards[0].id

        var toolDoc = HypeDocument.newDocument(name: "Garden")
        toolDoc.cards[0].name = "Garden"
        let toolCardId = toolDoc.cards[0].id

        // (a) HypeTalk handler surface.
        let handlerSource = "on mouseUp\n\(turtleGardenProgramBody)\nend mouseUp"
        let handlerResult = await runHypeTalkHandler(handlerSource, document: hypeTalkDoc, cardId: hypeTalkCardId)
        #expect(handlerResult.status == .completed)
        let handlerDocument = try #require(handlerResult.modifiedDocument)
        let handlerParts = handlerDocument.parts.filter { $0.cardId == hypeTalkCardId }

        // (b) draw_with_turtle AI-tool surface, from a document with the
        // same starting shape (fresh, zero parts, identical stack size).
        let executor = HypeToolExecutor()
        let toolSummary = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": turtleGardenProgramBody],
            document: &toolDoc,
            currentCardId: toolCardId
        )
        let toolParts = toolDoc.parts.filter { $0.cardId == toolCardId }

        #expect(!handlerParts.isEmpty, "the HypeTalk surface should have drawn the garden")
        #expect(handlerParts.count == toolParts.count, "both surfaces must emit the same number of parts")
        #expect(toolSummary.hasPrefix("Drew \(toolParts.count) shapes on card \"Garden\":"))

        let handlerFingerprints = handlerParts.map(TurtlePartFingerprint.init)
        let toolFingerprints = toolParts.map(TurtlePartFingerprint.init)
        #expect(handlerFingerprints == toolFingerprints, "parts must be field-identical (pathData, shapeType, colors, width, frame, name) across surfaces")
    }

    @Test("An invalid color (setPenColor \"blurple\") produces the identical E1 string on both surfaces")
    func invalidColorProducesIdenticalErrorOnBothSurfaces() async throws {
        let handlerDoc = HypeDocument.newDocument()
        let handlerCardId = handlerDoc.cards[0].id
        let handlerResult = await runHypeTalkHandler(
            "on mouseUp\n  setPenColor \"blurple\"\nend mouseUp",
            document: handlerDoc,
            cardId: handlerCardId
        )
        #expect(handlerResult.status == .error)
        let handlerMessage = try #require(handlerResult.error?.message)

        var toolDoc = HypeDocument.newDocument()
        let toolCardId = toolDoc.cards[0].id
        let executor = HypeToolExecutor()
        let toolMessage = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": "setPenColor \"blurple\""],
            document: &toolDoc,
            currentCardId: toolCardId
        )

        #expect(handlerMessage == toolMessage)
        #expect(handlerMessage == "turtle: \"blurple\" isn't a color — use #RRGGBB, #RRGGBBAA, or a name like red, blue, orange.")
    }
}

// MARK: - Criterion 16: tool contract (allTools, description, catalog absence)

@Suite("draw_with_turtle tool contract (criterion 16)")
struct TurtleToolContractTests {

    private static let expectedDescription = "Draw vector graphics on the current card with the classic Logo turtle. Pass a program of turtle commands, one per line — forward/back, right/left, setHeading, setPos, home, penUp/penDown, setPenColor, setPenWidth, setFillColor, beginFill/endFill, circle, arc, dot, clean, clearScreen — plus repeat loops. Same commands and semantics as HypeTalk's turtle; heading 0 points up, degrees clockwise, card coordinates. Output becomes editable freeform shape parts named 'turtle path N' / 'turtle fill N'."

    @Test("draw_with_turtle is present in allTools with the §7.1 description and a single required 'program' string param")
    func toolPresentWithExpectedSchema() throws {
        let tool = try #require(HypeToolDefinitions.allTools.first { $0.function.name == "draw_with_turtle" })
        #expect(tool.function.description == Self.expectedDescription)
        #expect(tool.function.parameters.required == ["program"])
        #expect(tool.function.parameters.properties["program"]?.type == "string")
    }

    @Test("draw_with_turtle is in the card-control and sprite-scene authoring catalogs")
    func toolInAuthoringCatalogs() {
        #expect(HypeToolDefinitions.cardControlAuthoringTools.contains { $0.function.name == "draw_with_turtle" })
        #expect(HypeToolDefinitions.spriteSceneAuthoringTools.contains { $0.function.name == "draw_with_turtle" })
    }

    @Test("draw_with_turtle is ABSENT from RuntimeAIToolCatalog (design-mock §7.3 — deployed runtime, no)")
    func toolAbsentFromRuntimeCatalog() {
        #expect(!RuntimeAIToolCatalog.defaultTools.contains { $0.name == "draw_with_turtle" })
    }

    @Test("A successful call creates the parts and returns the naming + turtle-state summary")
    func successfulCallReturnsNamingSummary() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        let summary = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": "forward 100"],
            document: &doc,
            currentCardId: cardId
        )
        let parts = doc.parts.filter { $0.cardId == cardId }
        #expect(parts.count == 1)
        #expect(parts[0].name == "turtle path 1")
        #expect(summary.contains("turtle path 1 (2 points)"))
        #expect(summary.contains("Turtle at 400,200 heading 0, pen down."))
    }

    @Test("A program that draws nothing reports zero shapes")
    func emptyProgramReportsZeroShapes() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        let summary = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": "-- just a comment, no commands"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(summary == "Drew no shapes on card \"Card 1\".")
        #expect(doc.parts.isEmpty)
    }
}

// MARK: - Criterion 17 + Security C4: all-or-nothing refusal

@Suite("draw_with_turtle refusals are all-or-nothing (criterion 17, Security C4)")
struct TurtleRefusalTests {

    @Test("A non-turtle statement (go next card) refuses E9 verbatim and creates zero parts")
    func nonTurtleStatementRefuses() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let program = "reset turtle\nclearScreen\nforward 10\ngo next card"
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": program],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result == "turtle: line 4 isn't a turtle command (\"go next card\") — draw_with_turtle accepts only turtle commands and repeat loops.")
        #expect(doc.parts.isEmpty)
    }

    @Test("repeat foo() times refuses E9 and creates zero parts — the loop count is validated")
    func functionCallInRepeatCountRefuses() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": "repeat foo() times\n  forward 10\nend repeat"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("turtle: line 1 isn't a turtle command"))
        #expect(doc.parts.isEmpty)
    }

    @Test("repeat with i = 1 to foo() refuses E9 and creates zero parts — the loop bound is validated")
    func functionCallInRepeatWithBoundRefuses() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": "repeat with i = 1 to foo()\n  forward 10\nend repeat"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("turtle: line 1 isn't a turtle command"))
        #expect(doc.parts.isEmpty)
    }

    @Test("set the heading of the turtle to foo() refuses E9 and creates zero parts — the set value is validated")
    func functionCallInSetValueRefuses() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": "set the heading of the turtle to foo()"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("turtle: line 1 isn't a turtle command"))
        #expect(doc.parts.isEmpty)
    }

    @Test("forward foo() refuses E9 and creates zero parts — a command argument is validated")
    func functionCallInCommandArgumentRefuses() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": "forward foo()"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("turtle: line 1 isn't a turtle command"))
        #expect(doc.parts.isEmpty)
    }

    @Test("A program over the 64 KB cap refuses without parsing and creates zero parts")
    func oversizedProgramRefuses() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let line = "forward 1\n"
        let repeatCount = (TurtleProgramValidator.maxProgramBytes / line.utf8.count) + 10
        let program = String(repeating: line, count: repeatCount)
        #expect(program.utf8.count > TurtleProgramValidator.maxProgramBytes)

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": program],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result == "turtle: program is too large — the limit is 65536 bytes.")
        #expect(doc.parts.isEmpty)
    }

    @Test("Security A2: a depth-1000 nested-parens program refuses cleanly (never reaches the parser) and creates zero parts")
    func deeplyNestedProgramRefusesCleanly() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let nested = String(repeating: "(", count: 1000) + "1" + String(repeating: ")", count: 1000)
        let program = "forward \(nested)"

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": program],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.contains("nested too deeply"))
        #expect(doc.parts.isEmpty)
    }
}

// MARK: - Security C14: provider containment

@Suite("draw_with_turtle provider containment (Security C14)")
struct TurtleProviderContainmentTests {

    @Test("A shadowed on forward handler cannot reach the filesystem through draw_with_turtle — the stub file provider denies it, and the run is all-or-nothing")
    func shadowedHandlerFileWriteIsDenied() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.cards[0].script = """
        on forward n
          write "leaked" to file "leak.txt"
        end forward
        """
        let existingPartCount = doc.parts.count

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "draw_with_turtle",
            arguments: ["program": "forward 50"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result == FileAccessError.accessDenied.scriptMessage)
        #expect(doc.parts.count == existingPartCount, "the tool is all-or-nothing: a denied file write must leave no part behind")
    }
}

import Testing
import Foundation
@testable import HypeCore

// Interpreter-surface tests for `turtle-graphics` P2 (design.md test plan,
// `TurtleScriptingTests.swift`): criteria 1, 3, 4 (abbreviations), 11
// (cross-run persistence via scriptGlobals; `reset turtle`; `clean`
// exactness incl. renamed-part survival; `clearScreen`), 12 (property
// reads/settable round-trips/read-only errors), 13 (encode → decode
// `.hype`, re-render fields identical, `documentVersion` unchanged), the
// interpreter half of 15 (E-strings via `ScriptError.message`; E6/E7 via
// `the result`; E8 partial parts via a capturing `ScriptRuntimeProviding`
// double), the message-box REPL walk, navigation flush, and `on forward`
// handler shadowing. Engine-level geometry is covered in
// `TurtleEngineTests.swift` (P1); grammar-fuzz + metamorphic coverage is in
// `InterpreterFuzzTests.swift`.

// MARK: - Test support

/// Parses and executes a single-statement handler (`on t / <body> / end t`)
/// against `document`. Mirrors the `runScript` helper in
/// `InterpreterPublishGatingTests.swift` — runs on a dedicated 8 MB-stack
/// thread because `Interpreter.executeStatement` is a large compiled
/// function whose frame can exceed the cooperative thread pool's default
/// stack.
private func runTurtleLine(
    _ body: String,
    document: HypeDocument,
    cardId: UUID? = nil,
    targetId: UUID? = nil,
    runtimeProvider: (any ScriptRuntimeProviding)? = nil
) async -> ExecutionResult {
    await runTurtleHandler(
        "on t\n\(body)\nend t",
        document: document,
        cardId: cardId,
        targetId: targetId,
        runtimeProvider: runtimeProvider
    )
}

/// Parses and executes a full handler source string against `document`.
private func runTurtleHandler(
    _ source: String,
    document: HypeDocument,
    cardId: UUID? = nil,
    targetId: UUID? = nil,
    runtimeProvider: (any ScriptRuntimeProviding)? = nil
) async -> ExecutionResult {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else {
        return ExecutionResult(status: .error, error: ScriptError(message: "parse error", line: 0, handler: "test"))
    }
    let resolvedCardId = cardId ?? document.cards[0].id
    let context = ExecutionContext(
        targetId: targetId ?? resolvedCardId,
        currentCardId: resolvedCardId,
        document: document,
        runtimeProvider: runtimeProvider
    )
    let interp = Interpreter()
    return await runOnLargeStack {
        interp.execute(handler: handler, params: [], context: context)
    }
}

/// A `ScriptRuntimeProviding` double that captures the most recently
/// published document. Used for criterion 15's E8 partial-state
/// assertion: a `ScriptError` result carries no `modifiedDocument`
/// (Deviations d2), so parts already emitted before the throw are only
/// observable through the live per-statement `publishDocument` channel
/// (`InterpreterPublishGatingTests.swift`'s `CountingRuntime` is the
/// established pattern this mirrors).
private final class CapturingRuntime: ScriptRuntimeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _lastPublishedDocument: HypeDocument?

    var lastPublishedDocument: HypeDocument? { lock.withLock { _lastPublishedDocument } }

    func sleep(seconds: TimeInterval) async throws {}
    func navigateToCard(_ cardId: UUID) async {}

    func publishDocument(_ document: HypeDocument) async {
        lock.withLock { _lastPublishedDocument = document }
    }

    func enqueueMessage(_ message: String, params: [Value],
                        targetId: UUID, currentCardId: UUID,
                        mouseX: Double, mouseY: Double,
                        scriptContext: ScriptDispatchContext?) async {}
    func startAIRequest(prompt: String, model: String?, callbackMessage: String,
                        owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startMeshyRequest(prompt: String, style: String?, model: String?,
                           callbackMessage: String,
                           owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startRemeshRequest(sourceAssetName: String, targetPolycount: Int,
                            callbackMessage: String,
                            owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startRetextureRequest(sourceAssetName: String, stylePrompt: String,
                               callbackMessage: String,
                               owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func setSpeechListenerActive(_ active: Bool, owner: RuntimeOwnerContext) async throws {}
    func isSpeechListenerActive() async -> Bool { false }
    func startHTTPRequest(_ spec: OutboundHTTPRequestSpec,
                          owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func reply(to requestID: UUID, status: Int, headersText: String, body: String) async throws {}
    func startListener(_ spec: ListenerSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func connectTCP(_ spec: TCPConnectionSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func send(_ data: String, toConnection id: UUID) async throws {}
    func closeConnection(_ id: UUID) async {}
    func stopListener(_ id: UUID) async {}
    func runtimeProperty(objectType: String, id: UUID, property: String,
                         argument: String?) async -> String { "" }
    func pushCardToHistory(_ cardId: UUID) async {}
    func popCardFromHistory() async -> UUID? { nil }
    func recentCards() async -> String { "" }
    func setFoundState(_ state: FoundState?) async {}
    func foundState() async -> FoundState? { nil }
    func setSelectedState(_ state: SelectedState?) async {}
    func selectedState() async -> SelectedState? { nil }
    func setClickState(_ state: ClickState) async {}
    func clickState() async -> ClickState? { nil }
}

// MARK: - Criteria 1, 3, 4: basic vocabulary, tolerant numerics, abbreviations

@Suite("Turtle HypeTalk surface — criteria 1, 3, 4")
struct TurtleBasicScriptingTests {

    @Test("forward 100 from defaults on an 800×600 stack: (400,300) → (400,200), one freeform part")
    func firstLineFromDefaults() async throws {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let result = await runTurtleLine("forward 100", document: doc, cardId: cardId)
        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        let parts = modified.parts.filter { $0.cardId == cardId }
        #expect(parts.count == 1)
        let part = try #require(parts.first)
        #expect(part.shapeType == .freeform)
        #expect(part.pathData == [PathPoint(x: 400, y: 300), PathPoint(x: 400, y: 200)])
        #expect(part.strokeColor == "#000000")
        #expect(part.strokeWidth == 2)
        #expect(part.fillColor == "")
        #expect(part.name == "turtle path 1")
    }

    @Test("right 90 then forward 100 reaches (500,300); left 90 inverts the rotation")
    func rightThenForwardAndLeftInverts() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        let moved = await runTurtleLine(
            "right 90\nforward 100\nreturn the position of the turtle",
            document: doc, cardId: cardId
        )
        #expect(moved.returnValue == "500,300")

        let inverted = await runTurtleLine(
            "right 90\nleft 90\nreturn the heading of the turtle",
            document: doc, cardId: cardId
        )
        #expect(inverted.returnValue == "0")
    }

    @Test("setHeading 270 then forward 100 from home reaches (300,300)")
    func setHeadingThenForward() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let result = await runTurtleLine(
            "setHeading 270\nforward 100\nreturn the position of the turtle",
            document: doc, cardId: cardId
        )
        #expect(result.returnValue == "300,300")
    }

    @Test("After right 450, the heading of the turtle is 90")
    func rightWraps() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let result = await runTurtleLine("right 450\nreturn the heading of the turtle", document: doc, cardId: cardId)
        #expect(result.returnValue == "90")
    }

    @Test("forward \"banana\" coerces to 0 (quiet no-op); setPenWidth 500 clamps to 100 silently")
    func tolerantNumerics() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let result = await runTurtleLine(
            "forward \"banana\"\nsetPenWidth 500\nreturn the position of the turtle & \",\" & the penWidth of the turtle",
            document: doc, cardId: cardId
        )
        #expect(result.status == .completed)
        #expect(result.returnValue == "400,300,100")
    }

    @Test("setPenColor \"blurple\" raises E1 leaving pen state unchanged")
    func invalidColorRaisesE1LeavingStateUnchanged() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let result = await runTurtleLine("setPenColor \"blurple\"", document: doc, cardId: cardId)
        #expect(result.status == .error)
        #expect(result.error?.message == "turtle: \"blurple\" isn't a color — use #RRGGBB, #RRGGBBAA, or a name like red, blue, orange.")

        // Pen state (color) is unchanged: a subsequent forward on a fresh
        // run from the same starting document still draws in the default
        // black pen color.
        let after = await runTurtleLine("forward 10\nreturn the penColor of the turtle", document: doc, cardId: cardId)
        #expect(after.returnValue == "#000000")
    }

    @Test("Abbreviations (fd, bk, rt, lt, setH, setXY, pu, pd, cs) behave identically to their long forms")
    func abbreviationsMatchLongForms() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let stateProbe = "return the position of the turtle & \",\" & the heading of the turtle & \",\" & the penDown of the turtle"
        let pairs: [(long: String, short: String)] = [
            ("forward 60", "fd 60"),
            ("back 40", "bk 40"),
            ("right 30", "rt 30"),
            ("left 20", "lt 20"),
            ("setHeading 200", "setH 200"),
            ("setPos 10, 20", "setXY 10, 20"),
            ("penUp", "pu"),
            ("penDown", "pd"),
        ]
        for pair in pairs {
            let longResult = await runTurtleLine("\(pair.long)\n\(stateProbe)", document: doc, cardId: cardId)
            let shortResult = await runTurtleLine("\(pair.short)\n\(stateProbe)", document: doc, cardId: cardId)
            #expect(
                longResult.returnValue == shortResult.returnValue,
                "\(pair.long) vs \(pair.short): \(String(describing: longResult.returnValue)) != \(String(describing: shortResult.returnValue))"
            )
        }

        let csLong = await runTurtleLine("forward 10\nclearScreen\nreturn the position of the turtle", document: doc, cardId: cardId)
        let csShort = await runTurtleLine("forward 10\ncs\nreturn the position of the turtle", document: doc, cardId: cardId)
        #expect(csLong.returnValue == csShort.returnValue)
    }
}

// MARK: - Criterion 12: turtle property surface

@Suite("Turtle property surface — criterion 12")
struct TurtleScriptingPropertySurfaceTests {

    @Test("GET reads every property (and its aliases) from defaults")
    func propertyGetsFromDefaults() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let cases: [(property: String, expected: String)] = [
            ("position", "400,300"), ("loc", "400,300"), ("location", "400,300"),
            ("xcor", "400"), ("ycor", "300"), ("heading", "0"),
            ("penDown", "true"), ("penColor", "#000000"), ("penWidth", "2"),
            ("fillColor", "#000000"), ("filling", "false"),
        ]
        for testCase in cases {
            let result = await runTurtleLine("return the \(testCase.property) of the turtle", document: doc, cardId: cardId)
            #expect(
                result.returnValue == testCase.expected,
                "the \(testCase.property) of the turtle expected \(testCase.expected), got \(String(describing: result.returnValue))"
            )
        }
    }

    @Test("SET then GET round-trips for position, heading, penDown, penColor, penWidth, fillColor")
    func propertySetGetRoundTrips() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let cases: [(property: String, valueExpr: String, expected: String)] = [
            ("position", "\"100,150\"", "100,150"),
            ("heading", "45", "45"),
            ("penDown", "false", "false"),
            ("penColor", "\"#FF0000\"", "#FF0000"),
            ("penWidth", "10", "10"),
            ("fillColor", "\"#00FF00\"", "#00FF00"),
        ]
        for testCase in cases {
            let result = await runTurtleLine(
                "set the \(testCase.property) of the turtle to \(testCase.valueExpr)\nreturn the \(testCase.property) of the turtle",
                document: doc, cardId: cardId
            )
            #expect(
                result.returnValue == testCase.expected,
                "\(testCase.property) round-trip expected \(testCase.expected), got \(String(describing: result.returnValue))"
            )
        }
    }

    @Test("setHeading 45 and `set the heading of the turtle to 45` are identical (property round-trip scenario)")
    func setHeadingCommandMatchesPropertySet() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let viaCommand = await runTurtleLine("setHeading 45\nreturn the heading of the turtle", document: doc, cardId: cardId)
        let viaSet = await runTurtleLine("set the heading of the turtle to 45\nreturn the heading of the turtle", document: doc, cardId: cardId)
        #expect(viaCommand.returnValue == "45")
        #expect(viaSet.returnValue == "45")
    }

    @Test("SET on xcor/ycor/filling raises the read-only registry-style error")
    func readOnlyPropertiesError() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let cases: [(property: String, valueExpr: String, message: String)] = [
            ("xcor", "5", "\"xcor\" of the turtle is read-only — set the position instead."),
            ("ycor", "5", "\"ycor\" of the turtle is read-only — set the position instead."),
            ("filling", "true", "\"filling\" of the turtle is read-only — use beginFill and endFill."),
        ]
        for testCase in cases {
            let result = await runTurtleLine("set the \(testCase.property) of the turtle to \(testCase.valueExpr)", document: doc, cardId: cardId)
            #expect(result.status == .error)
            #expect(result.error?.message == testCase.message)
        }
    }

    @Test("GET/SET on an unknown turtle property raises the registry-style unknown-property error")
    func unknownPropertyErrors() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let expected = "no such property \"bearing\" for the turtle — the turtle has position, xcor, ycor, heading, penDown, penColor, penWidth, fillColor, and filling."
        let get = await runTurtleLine("return the bearing of the turtle", document: doc, cardId: cardId)
        #expect(get.status == .error)
        #expect(get.error?.message == expected)

        let set = await runTurtleLine("set the bearing of the turtle to 5", document: doc, cardId: cardId)
        #expect(set.status == .error)
        #expect(set.error?.message == expected)
    }
}

// MARK: - Criterion 11: session-scoped state

@Suite("Session-scoped turtle state — criterion 11")
struct TurtleSessionStateTests {

    @Test("Message-box REPL: three separate runs continue the walk; two parts total")
    func messageBoxReplWalk() async throws {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        let r1 = await runTurtleLine("forward 100", document: doc, cardId: cardId)
        #expect(r1.status == .completed)
        doc = try #require(r1.modifiedDocument)

        let r2 = await runTurtleLine("rt 90", document: doc, cardId: cardId)
        #expect(r2.status == .completed)
        doc = try #require(r2.modifiedDocument)

        let r3 = await runTurtleLine("forward 100", document: doc, cardId: cardId)
        #expect(r3.status == .completed)
        doc = try #require(r3.modifiedDocument)

        let parts = doc.parts.filter { $0.cardId == cardId }
        #expect(parts.count == 2, "expected exactly two parts across the three runs, got \(parts.count)")
        let paths = parts.map(\.pathData)
        #expect(paths.contains([PathPoint(x: 400, y: 300), PathPoint(x: 400, y: 200)]))
        #expect(paths.contains([PathPoint(x: 400, y: 200), PathPoint(x: 500, y: 200)]))
    }

    @Test("reset turtle restores defaults without deleting parts")
    func resetTurtleRestoresDefaultsWithoutDeleting() async throws {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        let draw = await runTurtleLine("right 90\nforward 100", document: doc, cardId: cardId)
        doc = try #require(draw.modifiedDocument)
        #expect(doc.parts.filter { $0.cardId == cardId }.count == 1)

        let reset = await runTurtleLine(
            "reset turtle\nreturn the position of the turtle & \",\" & the heading of the turtle",
            document: doc, cardId: cardId
        )
        #expect(reset.status == .completed)
        #expect(reset.returnValue == "400,300,0")
        doc = try #require(reset.modifiedDocument)
        #expect(doc.parts.filter { $0.cardId == cardId }.count == 1, "reset turtle must not delete parts")
    }

    @Test("clean deletes turtle-named parts on the current card but spares a renamed one")
    func cleanDeletesTurtleNamedPartsExceptRenamed() async throws {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        let draw = await runTurtleLine("forward 50\nsetPenColor \"red\"\nforward 50", document: doc, cardId: cardId)
        doc = try #require(draw.modifiedDocument)
        let drawnParts = doc.parts.filter { $0.cardId == cardId }
        #expect(drawnParts.count == 2, "the pen-color change should split the trail into two parts")
        #expect(drawnParts.contains { $0.name == "turtle path 1" })
        #expect(drawnParts.contains { $0.name == "turtle path 2" })

        let keeperId = try #require(doc.parts.first { $0.cardId == cardId && $0.name == "turtle path 1" }).id
        let rename = await runTurtleLine("set the name of shape \"turtle path 1\" to \"Keeper\"", document: doc, cardId: cardId)
        doc = try #require(rename.modifiedDocument)
        #expect(doc.part(byId: keeperId)?.name == "Keeper")

        let clean = await runTurtleLine("clean", document: doc, cardId: cardId)
        doc = try #require(clean.modifiedDocument)
        let survivors = doc.parts.filter { $0.cardId == cardId }
        #expect(survivors.count == 1)
        #expect(survivors.first?.name == "Keeper")
        #expect(survivors.first?.id == keeperId)
    }

    @Test("clearScreen deletes turtle parts and homes without drawing")
    func clearScreenDeletesAndHomes() async throws {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        let draw = await runTurtleLine("right 90\nforward 100", document: doc, cardId: cardId)
        doc = try #require(draw.modifiedDocument)
        #expect(doc.parts.filter { $0.cardId == cardId }.count == 1)

        let clear = await runTurtleLine(
            "clearScreen\nreturn the position of the turtle & \",\" & the heading of the turtle",
            document: doc, cardId: cardId
        )
        #expect(clear.returnValue == "400,300,0")
        doc = try #require(clear.modifiedDocument)
        #expect(doc.parts.filter { $0.cardId == cardId }.isEmpty, "clearScreen must delete every turtle-named part and draw nothing new")
    }
}

// MARK: - Criterion 13: document round-trip

@Suite("Turtle parts survive document encode/decode — criterion 13")
struct TurtleDocumentRoundTripTests {

    @Test("Turtle-drawn part fields survive JSON encode/decode; documentVersion unchanged; scriptGlobals excluded")
    func encodeDecodeRoundTrip() async throws {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let result = await runTurtleLine("right 90\nforward 120\nright 90\nforward 80", document: doc, cardId: cardId)
        let modified = try #require(result.modifiedDocument)
        let originalVersion = modified.documentVersion
        let originalPart = try #require(modified.parts.first { $0.cardId == cardId })
        #expect(
            modified.scriptGlobals[TurtleEngine.sessionGlobalKey] != nil,
            "sanity: the run should have seeded the session key before encoding"
        )

        let data = try JSONEncoder().encode(modified)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: data)

        #expect(decoded.documentVersion == originalVersion)
        let decodedPart = try #require(decoded.parts.first { $0.id == originalPart.id })
        #expect(decodedPart.pathData == originalPart.pathData)
        #expect(decodedPart.shapeType == originalPart.shapeType)
        #expect(decodedPart.fillColor == originalPart.fillColor)
        #expect(decodedPart.strokeColor == originalPart.strokeColor)
        #expect(decodedPart.strokeWidth == originalPart.strokeWidth)
        #expect(decodedPart.name == originalPart.name)
        #expect(decodedPart.left == originalPart.left)
        #expect(decodedPart.top == originalPart.top)
        #expect(decodedPart.width == originalPart.width)
        #expect(decodedPart.height == originalPart.height)

        // Condition 9: turtle session state is never written into the
        // `.hype` document — `scriptGlobals` decodes empty regardless of
        // what the live document held.
        #expect(decoded.scriptGlobals.isEmpty, "scriptGlobals is session-only and must decode empty")
    }
}

// MARK: - Interpreter half of criterion 15: error surface

@Suite("Turtle errors on the HypeTalk surface — criterion 15 (interpreter half)")
struct TurtleErrorSurfaceTests {

    @Test("endFill with fewer than 3 distinct points sets the result to E6, synchronously observable")
    func endFillTooFewPointsSetsResultE6() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let result = await runTurtleLine("beginFill\nforward 1\nendFill\nreturn the result", document: doc, cardId: cardId)
        #expect(result.status == .completed)
        #expect(result.returnValue == "turtle: fill needs at least 3 points — nothing drawn.")
    }

    @Test("An unclosed beginFill sets the result to E7 at flush, observable via a same-run navigation flush")
    func unclosedFillSetsResultE7AtFlush() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        // `go this card` triggers `flushTurtleForNavigation` mid-run (the
        // same helper the run-end flush uses), so the E7 note lands in
        // `env.result` before the closing `return the result` statement
        // executes — the run-end flush alone happens *after* the body
        // finishes and so is not observable from within the same run.
        let result = await runTurtleLine(
            "beginFill\nforward 50\ngo this card\nreturn the result",
            document: doc, cardId: cardId
        )
        #expect(result.status == .completed)
        #expect(result.returnValue == "turtle: beginFill was never closed — no fill drawn.")
    }

    @Test("beginFill without a prior endFill raises E4; endFill without beginFill raises E5")
    func alreadyFillingAndNoFillToCloseErrors() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        let doubleBegin = await runTurtleLine("beginFill\nbeginFill", document: doc, cardId: cardId)
        #expect(doubleBegin.status == .error)
        #expect(doubleBegin.error?.message == "turtle: already filling — call endFill before starting another fill.")

        let strayEnd = await runTurtleLine("endFill", document: doc, cardId: cardId)
        #expect(strayEnd.status == .error)
        #expect(strayEnd.error?.message == "turtle: endFill without beginFill — nothing to fill.")
    }

    @Test("circle/arc/dot with a non-positive size raise E2 with the offending value")
    func nonPositiveSizeRaisesE2() async {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        let circle = await runTurtleLine("circle 0", document: doc, cardId: cardId)
        #expect(circle.error?.message == "turtle: circle needs a radius greater than 0 (got 0).")

        let arc = await runTurtleLine("arc 90, -5", document: doc, cardId: cardId)
        #expect(arc.error?.message == "turtle: arc needs a radius greater than 0 (got -5).")

        let dot = await runTurtleLine("dot 0", document: doc, cardId: cardId)
        #expect(dot.error?.message == "turtle: dot needs a diameter greater than 0 (got 0).")
    }

    @Test("Hitting the 200-part draw limit throws E8; parts already emitted survive on the live publish channel")
    func drawingLimitThrowsE8WithPartialStateOnPublishChannel() async throws {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let runtime = CapturingRuntime()
        let result = await runTurtleLine(
            "repeat 250 times\ndot 5\nend repeat",
            document: doc, cardId: cardId, runtimeProvider: runtime
        )
        #expect(result.status == .error)
        #expect(result.error?.message == "turtle: drawing limit reached — a single run may draw at most 200 shapes and 50000 points.")
        #expect(result.modifiedDocument == nil, "a ScriptError result carries no document (Deviations d2)")

        let published = try #require(runtime.lastPublishedDocument)
        let survivors = published.parts.filter { $0.cardId == cardId }
        #expect(survivors.count == 200, "the 200 already-emitted dots must survive on the live publish channel even though the run errored")
    }
}

// MARK: - Navigation flush

@Suite("Navigation flush (Deviations d8)")
struct TurtleNavigationFlushTests {

    @Test("go to another card flushes the open stroke to the departing card, not the destination")
    func navigationFlushesToDepartingCard() async throws {
        var doc = HypeDocument.newDocument()
        let firstCardId = doc.cards[0].id
        var secondCard = Card(stackId: doc.stack.id, backgroundId: doc.cards[0].backgroundId, name: "Second")
        secondCard.sortKey = "a1"
        doc.cards.append(secondCard)
        let secondCardId = secondCard.id

        let result = await runTurtleHandler(
            """
            on t
              forward 100
              go to card "Second"
              forward 50
            end t
            """,
            document: doc, cardId: firstCardId, targetId: firstCardId
        )
        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)

        let firstCardParts = modified.parts.filter { $0.cardId == firstCardId }
        #expect(firstCardParts.count == 1, "the first forward's stroke must flush to the departing (first) card")
        #expect(firstCardParts.first?.pathData == [PathPoint(x: 400, y: 300), PathPoint(x: 400, y: 200)])

        let secondCardParts = modified.parts.filter { $0.cardId == secondCardId }
        #expect(secondCardParts.count == 1, "the second forward's stroke must land on the destination card at run end")
        #expect(secondCardParts.first?.pathData == [PathPoint(x: 400, y: 200), PathPoint(x: 400, y: 150)])
    }
}

// MARK: - `on forward` handler shadowing

@Suite("User handlers shadow turtle built-ins (Requirement: Turtle vocabulary)")
struct TurtleHandlerShadowingTests {

    @Test("A card-level `on forward` handler intercepts `forward 50` — the built-in never runs")
    func onForwardHandlerShadowsBuiltin() async throws {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.cards[0].script = """
        on forward n
          global shadowed
          put "true" into shadowed
        end forward
        """

        let result = await runTurtleHandler(
            "on t\n  forward 50\nend t",
            document: doc, cardId: cardId, targetId: cardId
        )
        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        #expect(modified.scriptGlobals["shadowed"] == "true", "the user handler must run instead of the built-in")
        #expect(
            modified.scriptGlobals[TurtleEngine.sessionGlobalKey] == nil,
            "the built-in turtle command must never execute when shadowed — no session state should be seeded"
        )
        #expect(modified.parts.filter { $0.cardId == cardId }.isEmpty, "no turtle part should be drawn when the built-in is shadowed")
    }
}

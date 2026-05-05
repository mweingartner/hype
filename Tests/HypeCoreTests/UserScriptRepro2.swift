import Testing
import Foundation
@testable import HypeCore

/// Regression probe for the user's second failing script — an
/// AI-generated idle handler that randomly moves and rotates each
/// shape on the card.
///
/// User report: "it did not work and has parse errors". Script:
///
///     on idle
///       global dx, dy, rot
///       if dx is empty then put (random 2 - 1) * 2 into dx
///       if dy is empty then put (random 2 - 1) * 2 into dy
///       if rot is empty then put 0 into rot
///       put the loc of me into pos
///       put item 1 of pos into x
///       put item 2 of pos into y
///       add dx to x
///       add dy to y
///       add 5 to rot
///       if x < 0 or x > 800 then multiply dx by -1
///       if y < 0 or y > 600 then multiply dy by -int 1
///       set the loc of me to x & "," & y
///       set the rotation of me to rot
///     end idle
///
/// The script has three categories of problem:
///
/// 1. **Prefix-function syntax**: `random 2` is the HyperTalk-era
///    idiom — call a unary function without parens. Hype's parser
///    only accepted `random(2)`.
///
/// 2. **`-int 1` garbage**: the AI hallucinated an `int`
///    identifier. There's nothing to fix in the language here; we
///    need to (a) surface the parse error clearly, and (b) teach
///    the AI via HypeTalkGuide to not write this.
///
/// 3. **`the <prop> of me` / `set the <prop> of me`**: property
///    access where `me` is the target. For a shape, that should
///    resolve to the current part. Also, shapes didn't have a
///    `rotation` property in the Part model at all.
@Suite("User script — random move + rotate", .serialized)
struct UserScriptRepro2Tests {

    private func parseError(_ source: String) -> String? {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
            return nil
        } catch let error as ParseError {
            return error.errorDescription ?? String(describing: error)
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Grammar forms the user's script uses

    @Test("prefix-function syntax 'random N' parses")
    func prefixRandomParses() {
        let err = parseError("""
            on test
              put random 5 into x
            end test
            """)
        #expect(err == nil, "random 5 failed: \(err ?? "")")
    }

    @Test("prefix-function 'random N' works inside a parenthesized arithmetic expression")
    func prefixRandomInsideParens() {
        let err = parseError("""
            on test
              put (random 2 - 1) * 2 into dx
            end test
            """)
        #expect(err == nil, "(random 2 - 1) * 2 failed: \(err ?? "")")
    }

    @Test("other prefix-function unary builtins also parse")
    func prefixFunctionsParse() {
        let forms = [
            "put abs -5 into x",
            "put sqrt 16 into x",
            "put round 3.7 into x",
            "put length \"hello\" into x",
            "put trunc 3.9 into x",
        ]
        for form in forms {
            let err = parseError("on test\n  \(form)\nend test")
            #expect(err == nil, "'\(form)' failed: \(err ?? "")")
        }
    }

    @Test("'the loc of me' parses")
    func locOfMeParses() {
        let err = parseError("""
            on test
              put the loc of me into pos
            end test
            """)
        #expect(err == nil, "the loc of me failed: \(err ?? "")")
    }

    @Test("'set the loc of me to ...' parses")
    func setLocOfMeParses() {
        let err = parseError("""
            on test
              set the loc of me to "100,200"
            end test
            """)
        #expect(err == nil, "set the loc of me failed: \(err ?? "")")
    }

    @Test("'set the rotation of me to N' parses")
    func setRotationOfMeParses() {
        let err = parseError("""
            on test
              set the rotation of me to 45
            end test
            """)
        #expect(err == nil, "set the rotation of me failed: \(err ?? "")")
    }

    // MARK: - User's exact script (minus the -int 1 garbage)

    /// The user's script with `-int 1` replaced by `-1` (which is
    /// what the AI meant to write). This is the "does it parse
    /// when the obvious AI hallucination is fixed" test.
    static let userScriptCorrected = """
        on idle
          global dx, dy, rot
          if dx is empty then put (random 2 - 1) * 2 into dx
          if dy is empty then put (random 2 - 1) * 2 into dy
          if rot is empty then put 0 into rot

          put the loc of me into pos
          put item 1 of pos into x
          put item 2 of pos into y

          add dx to x
          add dy to y
          add 5 to rot

          if x < 0 or x > 800 then multiply dx by -1
          if y < 0 or y > 600 then multiply dy by -1

          set the loc of me to x & "," & y
          set the rotation of me to rot
        end idle
        """

    @Test("user's corrected script (random prefix + -1 instead of -int 1) parses end-to-end")
    func userScriptCorrectedParses() {
        let err = parseError(Self.userScriptCorrected)
        #expect(err == nil, "corrected user script failed: \(err ?? "")")
    }

    // MARK: - End-to-end dispatch

    /// Create a card with a shape part and attach the corrected
    /// idle handler to it, then dispatch `idle` to the shape's ID
    /// (simulating how the idle timer targets individual parts
    /// that have their own `on idle` handler).
    private func makeDocWithShapeAndIdle() -> (HypeDocument, UUID, UUID) {
        var doc = HypeDocument.newDocument(name: "Random Move Test")
        let cardId = doc.cards[0].id
        var shape = Part(
            partType: .shape,
            cardId: cardId,
            name: "box",
            left: 100, top: 100, width: 50, height: 50
        )
        shape.shapeType = .rectangle
        shape.fillColor = "#FF0000"
        shape.script = Self.userScriptCorrected
        doc.addPart(shape)
        return (doc, cardId, shape.id)
    }

    /// Run a script ten idle ticks and return the final document.
    /// Ten ticks with dx/dy in {0, 2} will definitely move the
    /// shape (expected value per axis is ~10 units).
    private func dispatchIdleTicks(
        _ count: Int,
        doc: HypeDocument,
        cardId: UUID,
        shapeId: UUID
    ) async -> HypeDocument {
        var current = doc
        let dispatcher = MessageDispatcher()
        for _ in 0..<count {
            let result = await runOnLargeStack { [current, shapeId, cardId] in dispatcher.dispatch(
                message: "idle",
                params: [],
                targetId: shapeId,
                document: current,
                currentCardId: cardId
            ) }
            if let modified = result.modifiedDocument {
                current = modified
            }
        }
        return current
    }

    @Test("idle handler on a shape mutates the shape's position via 'set the loc of me'") func idleMovesShapeViaLocOfMe() async {
        var (doc, cardId, shapeId) = makeDocWithShapeAndIdle()
        let original = doc.parts.first(where: { $0.id == shapeId })!
        let origLeft = original.left
        let origTop = original.top

        // Pre-seed dx and dy globals so the movement is
        // deterministic. The user's script initializes dx/dy via
        // `if dx is empty then put (random 2 - 1) * 2 into dx`,
        // which yields 0 or -2 with equal probability on the FIRST
        // tick only (after that dx is no longer empty and the
        // branch is skipped). That gave the test a 1/4 chance of
        // being stuck at (0,0) forever — a real flake. The grammar
        // that `(random 2 - 1) * 2` actually PARSES is covered by
        // prefixRandomInsideParens(); this test's job is to prove
        // `set the loc of me` actually mutates left/top, so we
        // just seed the globals to nonzero values and let the
        // `if dx is empty` check pass through untouched.
        doc.scriptGlobals["dx"] = "3"
        doc.scriptGlobals["dy"] = "2"
        doc.scriptGlobals["rot"] = "0"

        let modified = await dispatchIdleTicks(10, doc: doc, cardId: cardId, shapeId: shapeId)
        guard let shape = modified.parts.first(where: { $0.id == shapeId }) else {
            Issue.record("shape missing from modified document")
            return
        }
        // After 10 ticks with dx=3, dy=2 the shape should have
        // moved by exactly 30 on x and 20 on y (ignoring bounds
        // bounces — it stays well inside 800×600).
        let displacement = abs(shape.left - origLeft) + abs(shape.top - origTop)
        #expect(displacement > 0,
                "shape didn't move after 10 idle ticks with seeded dx=3, dy=2 (left=\(shape.left), top=\(shape.top))")
    }

    @Test("idle handler on a shape sets rotation via 'set the rotation of me'") func idleRotatesShape() async {
        let (doc, cardId, shapeId) = makeDocWithShapeAndIdle()
        let modified = await dispatchIdleTicks(5, doc: doc, cardId: cardId, shapeId: shapeId)
        guard let shape = modified.parts.first(where: { $0.id == shapeId }) else {
            Issue.record("shape missing from modified document")
            return
        }
        // After 5 ticks the handler's `add 5 to rot` has been
        // called 5 times, so rot is 25. `set the rotation of me
        // to rot` should have written that into the shape's
        // rotation field.
        #expect(shape.rotation == 25,
                "shape.rotation = \(shape.rotation), expected 25 after 5 ticks")
    }
}

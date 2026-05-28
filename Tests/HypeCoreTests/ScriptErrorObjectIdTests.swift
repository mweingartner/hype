import Testing
import Foundation
@testable import HypeCore

/// Regression tests for the `ScriptError.objectId` plumbing.
///
/// Before this plumbing existed, a runtime or parse error from
/// HypeTalk dispatch was logged to stderr and the view layer had no
/// way to figure out which object's script caused it. Users had to
/// hunt through every card, background, and stack script to find the
/// error line manually. Now the dispatcher stamps `objectId` onto
/// every error it returns so `CardCanvasView.Coordinator` can open
/// the script editor for the offending object and highlight the
/// exact line that blew up.
///
/// These tests pin the contract:
/// 1. Parse errors on any object (part, card, background, stack)
///    return an `ExecutionResult` whose `error.objectId` matches the
///    object whose script failed to parse.
/// 2. Runtime errors (thrown from deep inside the interpreter) also
///    have their `objectId` populated by the dispatcher, even though
///    the interpreter itself doesn't know the owning object.
/// 3. Line numbers on parse errors are extracted from the
///    ParseError description so the view layer can highlight the
///    right row in the editor.
@Suite("ScriptError objectId is populated", .serialized)
struct ScriptErrorObjectIdTests {

    private func makeDoc() -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Error ObjectId Test")
        let cardId = doc.cards[0].id
        var button = Part(
            partType: .button,
            cardId: cardId,
            name: "Go",
            left: 10, top: 10, width: 100, height: 40
        )
        button.textContent = "Go"
        doc.addPart(button)
        return (doc, cardId)
    }

    // MARK: - Parse errors carry objectId

    @Test("parse error in a part's script returns error.objectId == part.id") func parseErrorOnPartHasPartId() async {
        var (doc, cardId) = makeDoc()
        let partId = doc.parts.first { $0.name == "Go" }!.id
        // Deliberately invalid HypeTalk — `int` is not a keyword.
        doc.updatePart(id: partId) { $0.script = "on mouseUp\n  put -int 1 into x\nend mouseUp" }

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: partId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .error)
        #expect(result.error != nil)
        #expect(result.error?.objectId == partId,
                "parse error on button should surface with objectId == button.id so the view layer can reopen its script")
    }

    @Test("parse error in a card's script returns error.objectId == card.id") func parseErrorOnCardHasCardId() async {
        var (doc, cardId) = makeDoc()
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        // `-int 1` is the same hallucination we guard against in the
        // HypeTalkGuide's "Common AI hallucinations" section.
        doc.cards[idx].script = "on openCard\n  put -int 1 into x\nend openCard"

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .error)
        #expect(result.error?.objectId == cardId)
    }

    @Test("parse error in a background's script returns error.objectId == background.id") func parseErrorOnBackgroundHasBgId() async {
        var (doc, cardId) = makeDoc()
        let bgId = doc.backgrounds[0].id
        doc.backgrounds[0].script = "on openCard\n  put -int 1 into x\nend openCard"

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .error)
        #expect(result.error?.objectId == bgId,
                "parse error on background-level script should surface with the background's UUID")
    }

    @Test("parse error in the stack script returns error.objectId == stack.id") func parseErrorOnStackHasStackId() async {
        var (doc, cardId) = makeDoc()
        doc.stack.script = "on openStack\n  put -int 1 into x\nend openStack"

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "openStack",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .error)
        #expect(result.error?.objectId == doc.stack.id)
    }

    @Test("parse error line number is extracted from ParseError description") func parseErrorLineNumberExtracted() async {
        var (doc, cardId) = makeDoc()
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        // The bogus `-int 1` is on line 3 (line 1 = `on openCard`,
        // line 2 = `  put "ok" into y`, line 3 = `  put -int 1 into x`).
        doc.cards[idx].script = """
            on openCard
              put "ok" into y
              put -int 1 into x
            end openCard
            """

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .error)
        #expect(result.error?.line == 3,
                "ParseError's Line N prefix should be extracted into ScriptError.line")
    }

    @Test("parse errors are logged to the Hype console") func parseErrorIsLoggedToConsole() async {
        HypeLogger.shared.clear()
        var (doc, cardId) = makeDoc()
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = "on openCard\n  put -int 1 into x\nend openCard"

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .error)
        #expect(HypeLogger.shared.entries.contains {
            $0.source == "Parser" &&
            $0.message.contains("[HypeTalk parse error]") &&
            $0.message.contains("card") &&
            $0.message.contains("hype-ref=hype://script-error") &&
            $0.actionTitle == "Open script" &&
            $0.actionURL?.scheme == "hype" &&
            $0.actionURL?.host == "script-error"
        })
    }

    // MARK: - Runtime errors carry objectId

    @Test("runtime error on a card script is stamped with card.id by the dispatcher") func runtimeErrorOnCardHasCardId() async {
        var (doc, cardId) = makeDoc()
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        // This script parses fine, but hits the interpreter's
        // instruction limit — a clean way to produce a runtime
        // ScriptError without depending on any particular runtime
        // failure mode. The `repeat while true` never terminates,
        // so the interpreter throws
        // ScriptError(message: "Instruction limit exceeded", ...).
        doc.cards[idx].script = """
            on openCard
              repeat while true
                put "x" into y
              end repeat
            end openCard
            """

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .error)
        #expect(result.error != nil)
        #expect(result.error?.objectId == cardId,
                "runtime error on card script should have its objectId stamped to card.id by the dispatcher")
        // The message from the interpreter should still be preserved.
        #expect(result.error?.message.lowercased().contains("instruction limit") == true)
    }

    @Test("runtime errors are logged to the Hype console") func runtimeErrorIsLoggedToConsole() async {
        HypeLogger.shared.clear()
        var (doc, cardId) = makeDoc()
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = """
            on openCard
              repeat while true
                put "x" into y
              end repeat
            end openCard
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .error)
        #expect(HypeLogger.shared.entries.contains {
            $0.source == "Runtime" &&
            $0.message.contains("[HypeTalk runtime error]") &&
            $0.message.contains("Instruction limit") &&
            $0.message.contains("hype-ref=hype://script-error") &&
            $0.actionTitle == "Open script" &&
            $0.actionURL?.scheme == "hype" &&
            $0.actionURL?.host == "script-error"
        })
    }

    // MARK: - Valid scripts produce nil errors

    @Test("valid script returns no error and no objectId") func validScriptHasNoError() async {
        var (doc, cardId) = makeDoc()
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = "on openCard\n  put \"hi\" into it\nend openCard"

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.error == nil)
    }
}

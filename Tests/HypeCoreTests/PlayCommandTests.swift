import Testing
import Foundation
@testable import HypeCore

@Suite("Play/Beep/Wait Command Tests", .serialized)
struct PlayCommandTests {

    // MARK: - Helpers

    private func parse(_ source: String) -> Script? {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return try? parser.parse()
    }

    private func parses(_ source: String) -> Bool {
        parse(source) != nil
    }

    // MARK: - Parser tests

    @Test func playSound() {
        #expect(parses("""
        on test
          play "Glass"
        end test
        """))
    }

    @Test func playStop() {
        #expect(parses("""
        on test
          play stop
        end test
        """))
    }

    @Test func playSoundWithNotes() {
        #expect(parses("""
        on test
          play "flute" "c d e"
        end test
        """))
    }

    @Test func playSoundWithTempoAndNotes() {
        #expect(parses("""
        on test
          play "flute" tempo 160 "c d e"
        end test
        """))
    }

    @Test func beepAlone() {
        #expect(parses("""
        on test
          beep
        end test
        """))
    }

    @Test func beepWithCount() {
        #expect(parses("""
        on test
          beep 3
        end test
        """))
    }

    @Test func waitDuration() {
        #expect(parses("""
        on test
          wait 5
        end test
        """))
    }

    @Test func waitDurationWithUnit() {
        #expect(parses("""
        on test
          wait 5 seconds
        end test
        """))
    }

    @Test func waitUntilCondition() {
        #expect(parses("""
        on test
          wait until the sound is "done"
        end test
        """))
    }

    // MARK: - Lexer tests

    @Test func playTokenType() {
        var lexer = Lexer(source: "play")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .play)
    }

    @Test func beepTokenType() {
        var lexer = Lexer(source: "beep")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .beep)
    }

    @Test func waitTokenType() {
        var lexer = Lexer(source: "wait")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .wait)
    }

    // MARK: - Interpreter tests

    @Test func theSoundPropertyReturnsDone() {
        // `the sound` should return "done" when no sound is playing.
        // This exercises the global-property path in evaluateProperty
        // (not the evaluateBuiltIn function-call path).
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        if let idx = doc.cards.firstIndex(where: { $0.id == cardId }) {
            doc.cards[idx].script = """
            on openCard
              put the sound into field "output"
            end openCard
            """
        }

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        )

        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "done",
                "the sound should return 'done' when no sound is playing, got '\(outputField?.textContent ?? "nil")'")
    }

    @Test func beepExecutesWithoutCrash() {
        var lexer = Lexer(source: """
        on test
          beep
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("Parse failed")
            return
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc)
        let interpreter = Interpreter()
        let result = interpreter.execute(handler: handler, params: [], context: context)
        #expect(result.status == .completed)
    }

    @Test func playStopExecutesWithoutCrash() {
        var lexer = Lexer(source: """
        on test
          play stop
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("Parse failed")
            return
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc)
        let interpreter = Interpreter()
        let result = interpreter.execute(handler: handler, params: [], context: context)
        #expect(result.status == .completed)
    }

    @Test func waitZeroExecutesWithoutCrash() {
        var lexer = Lexer(source: """
        on test
          wait 0
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("Parse failed")
            return
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc)
        let interpreter = Interpreter()
        let result = interpreter.execute(handler: handler, params: [], context: context)
        #expect(result.status == .completed)
    }
}

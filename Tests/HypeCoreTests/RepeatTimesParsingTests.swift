import Testing
import Foundation
@testable import HypeCore

/// `repeat N times` used to leave the trailing `times` keyword unconsumed,
/// so `parseRepeatBody` captured it as a stray
/// `expressionStatement(.literal("times"))` first body statement. The parser
/// now consumes the optional `times`, so the body is clean. (repeat-times-token)
@Suite("repeat N times parsing — no stray token", .serialized)
struct RepeatTimesParsingTests {

    private func handlerBody(_ src: String) -> [Statement]? {
        var lexer = Lexer(source: src)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return (try? parser.parse())?.handlers.first?.body
    }

    private func firstRepeatCountBody(_ stmts: [Statement]?) -> [Statement]? {
        for s in stmts ?? [] {
            if case .repeatCount(_, let body) = s { return body }
        }
        return nil
    }

    @Test("repeat N times body has no stray `times` statement")
    func repeatNTimesBodyIsClean() {
        let body = firstRepeatCountBody(handlerBody("on m\n repeat 3 times\n forward 10\n end repeat\nend m"))
        #expect(body?.count == 1,
                "expected 1 body statement (forward), got \(body?.count ?? -1): \(String(describing: body))")
        guard let first = body?.first, case .externalCommand(let name, _) = first else {
            Issue.record("first body statement is not the forward command: \(String(describing: body?.first))")
            return
        }
        #expect(name.lowercased() == "forward")
    }

    @Test("bare `repeat N` (no times) parses to a clean single-statement body")
    func bareRepeatNIsClean() {
        let body = firstRepeatCountBody(handlerBody("on m\n repeat 3\n forward 10\n end repeat\nend m"))
        #expect(body?.count == 1, "bare `repeat N` body expected 1, got \(body?.count ?? -1)")
    }

    @Test("`repeat for N times` parses to a clean single-statement body")
    func repeatForNTimesIsClean() {
        let body = firstRepeatCountBody(handlerBody("on m\n repeat for 3 times\n forward 10\n end repeat\nend m"))
        #expect(body?.count == 1, "`repeat for N times` body expected 1, got \(body?.count ?? -1)")
    }

    @Test("nested `repeat N times` bodies are both clean")
    func nestedRepeatTimesClean() {
        let outer = firstRepeatCountBody(handlerBody(
            "on m\n repeat 2 times\n repeat 3 times\n forward 10\n end repeat\n end repeat\nend m"))
        #expect(outer?.count == 1, "outer body expected 1 (inner loop), got \(outer?.count ?? -1)")
        guard let inner = outer?.first, case .repeatCount(_, let innerBody) = inner else {
            Issue.record("outer body first statement is not a repeatCount: \(String(describing: outer?.first))")
            return
        }
        #expect(innerBody.count == 1, "inner body expected 1, got \(innerBody.count)")
    }

    @Test("repeat N times still runs the loop exactly N times")
    func repeatNTimesRunsNTimes() {
        var lexer = Lexer(source: "on t\n put 0 into c\n repeat 3 times\n add 1 to c\n end repeat\n return c\nend t")
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("parse failed"); return
        }
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        #expect(result.returnValue == "3",
                "repeat 3 times produced c=\(result.returnValue ?? "nil"); expected 3")
    }
}

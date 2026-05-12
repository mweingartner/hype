import Testing
import Foundation
@testable import HypeCore

// MARK: - Helpers

private func parseFirstStatement(_ source: String) throws -> Statement {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    let script = try parser.parse()
    guard let first = script.handlers.first?.body.first else {
        throw TestError("No statements in parsed output")
    }
    return first
}

private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ desc: String) { self.description = desc }
}

// MARK: - Tests

@Suite("Parser — ask meshy expression form (Phase 5)")
struct HypeTalkAskMeshyExpressionParserTests {

    // MARK: (a) `put ask meshy "barrel" into x` → .put with .askMeshy source

    @Test("put ask meshy expression parses to .put with .askMeshy source")
    func putAskMeshyIntoParsesCorrectly() throws {
        let src = "on t\n  put ask meshy \"a barrel\" into x\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .put(source, preposition, target) = stmt else {
            Issue.record("Expected .put statement, got \(stmt)")
            return
        }
        #expect(preposition == .into)
        // Target should be a variable named "x"
        guard case let .variable(name) = target else {
            Issue.record("Expected .variable target, got \(target)")
            return
        }
        #expect(name == "x")
        // Source should be Expression.askMeshy
        guard case let .askMeshy(promptExpr, style) = source else {
            Issue.record("Expected .askMeshy source expression, got \(source)")
            return
        }
        guard case let .literal(promptText) = promptExpr else {
            Issue.record("Expected string literal prompt")
            return
        }
        #expect(promptText == "a barrel")
        #expect(style == nil)
    }

    // MARK: (b) `put ask meshy "barrel" with style "realistic" into x` — style modifier

    @Test("put ask meshy with style modifier parses style in expression")
    func putAskMeshyWithStyleParses() throws {
        let src = "on t\n  put ask meshy \"barrel\" with style \"realistic\" into x\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .put(source, _, _) = stmt else {
            Issue.record("Expected .put, got \(stmt)")
            return
        }
        guard case let .askMeshy(_, style) = source else {
            Issue.record("Expected .askMeshy source expression, got \(source)")
            return
        }
        guard case let .literal(styleText) = style else {
            Issue.record("Expected string literal style")
            return
        }
        #expect(styleText == "realistic")
    }

    // MARK: (c) `ask meshy "x"` as a statement still parses as .askMeshy statement

    @Test("standalone ask meshy statement still parses to Statement.askMeshy")
    func standaloneMeshyStatementUnchanged() throws {
        let src = "on t\n  ask meshy \"x\"\nend t"
        let stmt = try parseFirstStatement(src)
        guard case let .askMeshy(_, _, _, _) = stmt else {
            Issue.record("Expected Statement.askMeshy, got \(stmt)")
            return
        }
    }

    // MARK: (d) `ask meshy "x" with message "cb"` as statement still uses callback form

    @Test("ask meshy with message modifier in statement context still parses as statement")
    func meshyStatementWithCallbackUnchanged() throws {
        let src = "on t\n  ask meshy \"barrel\" with message \"ready\"\nend t"
        let stmt = try parseFirstStatement(src)
        guard case let .askMeshy(_, _, _, callback) = stmt else {
            Issue.record("Expected Statement.askMeshy, got \(stmt)")
            return
        }
        guard case let .literal(cbText) = callback else {
            Issue.record("Expected string literal callback")
            return
        }
        #expect(cbText == "ready")
    }
}

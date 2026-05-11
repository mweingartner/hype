import Testing
import Foundation
@testable import HypeCore

// MARK: - Helpers

private func parseStatements(_ source: String) throws -> [Statement] {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    let script = try parser.parse()
    // Return the body of the first handler.
    return script.handlers.first?.body ?? []
}

private func parseFirstStatement(_ source: String) throws -> Statement {
    let stmts = try parseStatements(source)
    guard let first = stmts.first else {
        throw TestError("No statements in parsed output")
    }
    return first
}

private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ desc: String) { self.description = desc }
}

// MARK: - Tests

@Suite("Parser — ask meshy grammar (Phase 3)")
struct HypeTalkAskMeshyParserTests {

    // MARK: (a) ask meshy "barrel" → .askMeshy(prompt:, style:nil, model:nil, callback:nil)

    @Test("ask meshy with prompt only parses to askMeshy with nil modifiers")
    func parseAskMeshyPromptOnly() throws {
        let src = "on t\n  ask meshy \"barrel\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .askMeshy(promptExpr, style, model, callback) = stmt else {
            Issue.record("Expected .askMeshy, got \(stmt)")
            return
        }
        guard case let .literal(promptText) = promptExpr else {
            Issue.record("Expected string literal prompt")
            return
        }
        #expect(promptText == "barrel")
        #expect(style == nil)
        #expect(model == nil)
        #expect(callback == nil)
    }

    // MARK: (b) ask meshy "x" with style "sculpture" parses with style

    @Test("ask meshy with style modifier parses style expression")
    func parseAskMeshyWithStyle() throws {
        let src = "on t\n  ask meshy \"x\" with style \"sculpture\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .askMeshy(_, style, model, callback) = stmt else {
            Issue.record("Expected .askMeshy")
            return
        }
        guard case let .literal(styleText) = style else {
            Issue.record("Expected string literal style")
            return
        }
        #expect(styleText == "sculpture")
        #expect(model == nil)
        #expect(callback == nil)
    }

    // MARK: (c) ask meshy "x" with model "meshy-5" parses with model

    @Test("ask meshy with model modifier parses model expression")
    func parseAskMeshyWithModel() throws {
        let src = "on t\n  ask meshy \"x\" with model \"meshy-5\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .askMeshy(_, style, model, callback) = stmt else {
            Issue.record("Expected .askMeshy")
            return
        }
        #expect(style == nil)
        guard case let .literal(modelText) = model else {
            Issue.record("Expected string literal model")
            return
        }
        #expect(modelText == "meshy-5")
        #expect(callback == nil)
    }

    // MARK: (d) ask meshy "x" with message "ready" parses with callback

    @Test("ask meshy with message modifier parses callback expression")
    func parseAskMeshyWithMessage() throws {
        let src = "on t\n  ask meshy \"x\" with message \"ready\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .askMeshy(_, style, model, callback) = stmt else {
            Issue.record("Expected .askMeshy")
            return
        }
        #expect(style == nil)
        #expect(model == nil)
        guard case let .literal(callbackName) = callback else {
            Issue.record("Expected string literal callback")
            return
        }
        #expect(callbackName == "ready")
    }

    // MARK: (e) ask meshy "x" with style "realistic" with message "done" parses both

    @Test("ask meshy with both style and message modifiers parses both")
    func parseAskMeshyWithStyleAndMessage() throws {
        let src = "on t\n  ask meshy \"x\" with style \"realistic\" with message \"done\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .askMeshy(_, style, _, callback) = stmt else {
            Issue.record("Expected .askMeshy")
            return
        }
        guard case let .literal(styleText) = style else {
            Issue.record("Expected style expression")
            return
        }
        #expect(styleText == "realistic")
        guard case let .literal(cbName) = callback else {
            Issue.record("Expected callback expression")
            return
        }
        #expect(cbName == "done")
    }

    // MARK: (f) ask "raw prompt" (no meshy keyword) still parses to .ask

    @Test("ask without meshy keyword still parses to .ask")
    func parseAskWithoutMeshyKeyword() throws {
        let src = "on t\n  ask \"what is your name?\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case .ask = stmt else {
            Issue.record("Expected .ask, got \(stmt)")
            return
        }
    }

    // MARK: (g) ask ai "x" still parses to .askAI

    @Test("ask ai keyword still parses to .askAI")
    func parseAskAiKeywordStillWorks() throws {
        let src = "on t\n  ask ai \"summarise this\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case .askAI = stmt else {
            Issue.record("Expected .askAI, got \(stmt)")
            return
        }
    }
}

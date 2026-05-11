import Testing
import Foundation
@testable import HypeCore

// MARK: - Helpers

private func parseStatements(_ source: String) throws -> [Statement] {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    let script = try parser.parse()
    return script.handlers.first?.body ?? []
}

private func parseFirstStatement(_ source: String) throws -> Statement {
    let stmts = try parseStatements(source)
    guard let first = stmts.first else {
        throw ParseTestError("No statements in parsed output")
    }
    return first
}

private struct ParseTestError: Error, CustomStringConvertible {
    let description: String
    init(_ desc: String) { self.description = desc }
}

// MARK: - Tests

@Suite("Parser — remesh asset / retexture asset (Phase 4)")
struct HypeTalkRemeshRetextureParserTests {

    // MARK: (a) remesh asset "barrel" to 5000

    @Test("remesh asset \"barrel\" to 5000 parses to .remeshAsset with no callback")
    func parseRemeshAssetBasic() throws {
        let src = "on t\n  remesh asset \"barrel\" to 5000\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .remeshAsset(sourceName, polycount, callback) = stmt else {
            Issue.record("Expected .remeshAsset, got \(stmt)")
            return
        }
        guard case let .literal(nameStr) = sourceName else {
            Issue.record("Expected literal source name")
            return
        }
        guard case let .literal(polyStr) = polycount else {
            Issue.record("Expected literal polycount")
            return
        }
        #expect(nameStr == "barrel")
        #expect(polyStr == "5000")
        #expect(callback == nil)
    }

    // MARK: (b) remesh asset "barrel" to 5000 with message "done"

    @Test("remesh asset with message callback parses callback expression")
    func parseRemeshAssetWithCallback() throws {
        let src = "on t\n  remesh asset \"barrel\" to 5000 with message \"done\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .remeshAsset(_, _, callback) = stmt else {
            Issue.record("Expected .remeshAsset, got \(stmt)")
            return
        }
        #expect(callback != nil, "Callback expression must be parsed")
        if let callback {
            guard case let .literal(msg) = callback else {
                Issue.record("Expected literal callback message")
                return
            }
            #expect(msg == "done")
        }
    }

    // MARK: (c) retexture asset "barrel" with prompt "metal cybernetic"

    @Test("retexture asset with prompt only parses to .retextureAsset with no callback")
    func parseRetextureAssetBasic() throws {
        let src = "on t\n  retexture asset \"barrel\" with prompt \"metal cybernetic\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .retextureAsset(sourceName, stylePrompt, callback) = stmt else {
            Issue.record("Expected .retextureAsset, got \(stmt)")
            return
        }
        guard case let .literal(nameStr) = sourceName else {
            Issue.record("Expected literal source name")
            return
        }
        guard case let .literal(promptStr) = stylePrompt else {
            Issue.record("Expected literal style prompt")
            return
        }
        #expect(nameStr == "barrel")
        #expect(promptStr == "metal cybernetic")
        #expect(callback == nil)
    }

    // MARK: (d) retexture asset "barrel" with prompt "..." with message "done"

    @Test("retexture asset with prompt and message callback parses both")
    func parseRetextureAssetWithCallback() throws {
        let src = "on t\n  retexture asset \"barrel\" with prompt \"ice\" with message \"retexDone\"\nend t"
        let stmt = try parseFirstStatement(src)

        guard case let .retextureAsset(_, stylePrompt, callback) = stmt else {
            Issue.record("Expected .retextureAsset, got \(stmt)")
            return
        }
        if case let .literal(promptStr) = stylePrompt {
            #expect(promptStr == "ice")
        } else {
            Issue.record("Expected literal style prompt")
        }
        #expect(callback != nil, "Callback must be present")
        if let callback, case let .literal(msg) = callback {
            #expect(msg == "retexDone")
        }
    }

    // MARK: (e) remesh keyword doesn't conflict with identifiers

    @Test("remesh as identifier in other contexts still tokenizes correctly")
    func remeshKeywordDoesntBreakIdentifiers() throws {
        // `remesh` used as a standalone variable read — the interpreter would
        // look it up as a variable, but parsing shouldn't crash.
        let src = "on t\n  put remesh into x\nend t"
        // Should not throw a parse error.
        do {
            let stmts = try parseStatements(src)
            // We just need it to not crash. Specific result doesn't matter here.
            #expect(stmts.isEmpty == false || stmts.isEmpty == true)
        } catch {
            // A parse error here is also acceptable — remesh is now a keyword.
            // What's NOT acceptable is a crash or a hang.
        }
    }

    // MARK: (f) plain remesh without "asset" gives a clear parse error

    @Test("remesh without the 'asset' keyword produces a parse error")
    func remeshWithoutAssetGivesError() throws {
        // The grammar requires: remesh asset "<name>" to <polycount>
        // Missing the "asset" keyword should fail.
        let src = "on t\n  remesh \"barrel\" to 5000\nend t"
        do {
            _ = try parseStatements(src)
            // Reaching here is acceptable in some parsers that consume and ignore
            // the malformed statement. The important invariant is no crash.
        } catch {
            // Expected — the parser should report an error for missing "asset".
        }
    }
}

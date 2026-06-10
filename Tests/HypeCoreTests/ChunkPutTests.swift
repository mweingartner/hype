import Testing
import Foundation
@testable import HypeCore

// MARK: - End-to-end chunk put tests (interpreter level)

/// Minimal script execution harness — replicated from ScriptTests.InterpreterTests
/// because that struct's `executeScript` is `private`.
private func runScript(_ source: String, document: HypeDocument = HypeDocument.newDocument()) -> ExecutionResult {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else {
        return ExecutionResult(status: .error, error: ScriptError(message: "Parse failed", line: 0, handler: ""))
    }
    let context = ExecutionContext(
        targetId: document.cards[0].id,
        currentCardId: document.cards[0].id,
        document: document
    )
    let interpreter = Interpreter()
    return interpreter.execute(handler: handler, params: [], context: context)
}

@Suite("ChunkPut End-to-End Tests", .serialized)
struct ChunkPutTests {

    // MARK: - T6: Nested chunk put

    @Test func nestedChunkPut() {
        // Build the multi-line container in the interpreter so we avoid
        // embedding literal newlines inside HypeTalk string literals
        // (the lexer breaks strings at line boundaries).
        // v = "aa bb cc" & return & "dd ee ff" & return & "gg hh ii"
        // word 3 of line 1 = "cc", char 2 of "cc" = "Z" → "cZ"
        // result v line 1 = "aa bb cZ"
        let result = runScript("""
        on test
          put "aa bb cc" & return & "dd ee ff" & return & "gg hh ii" into v
          put "Z" into char 2 of word 3 of line 1 of v
          return v
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "aa bb cZ\ndd ee ff\ngg hh ii")
    }

    // MARK: - T7: Myst pattern (char padding)

    @Test func mystPatternCharPadding() {
        // Classic Myst pattern: put 0 into char 6 of ST_Drawers
        // ST_Drawers = "abc", char 6 → pad with spaces → "abc  0"
        let result = runScript("""
        on test
          put "abc" into ST_Drawers
          put 0 into char 6 of ST_Drawers
          return ST_Drawers
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "abc  0")
    }

    @Test func mystPatternCharPaddingGlobal() {
        // Same as mystPatternCharPadding but with a global variable.
        let result = runScript("""
        on test
          global ST_Drawers
          put "abc" into ST_Drawers
          put 0 into char 6 of ST_Drawers
          return ST_Drawers
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "abc  0")
    }

    // MARK: - Field write-back

    @Test func fieldWriteBackWithItUnchanged() {
        // Seed a field with "alpha,beta,gamma".
        // put "SENTINEL" into it (to verify it is not clobbered).
        // put "X" into item 2 of field "data".
        // Assert textContent is "alpha,X,gamma" AND it is still "SENTINEL".
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var field = Part(partType: .field, cardId: cardId, name: "data")
        field.textContent = "alpha,beta,gamma"
        doc.addPart(field)

        let result = runScript("""
        on test
          put "SENTINEL" into it
          put "X" into item 2 of field "data"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        // `it` must remain "SENTINEL" — field chunk put must not clobber it.
        #expect(result.returnValue == "SENTINEL")
        // The field's text content must reflect the put.
        let updatedField = result.modifiedDocument?.parts.first(where: { $0.name == "data" })
        #expect(updatedField?.textContent == "alpha,X,gamma")
    }

    // MARK: - T12: Error routing

    @Test func errorPutIntoBareNumber() {
        // put 5 into 3  — literal target → error
        let result = runScript("""
        on test
          put 5 into 3
        end test
        """)
        #expect(result.status == .error)
        #expect(result.error?.message == "Can't put into that container")
    }

    @Test func errorPutIntoChunkOfMissingField() {
        // put "x" into char 1 of field "nope" — field doesn't exist → error
        let result = runScript("""
        on test
          put "x" into char 1 of field "nope"
        end test
        """)
        #expect(result.status == .error)
        #expect(result.error?.message == "Can't put into a chunk of that container")
    }

    // MARK: - T13: it-hygiene across handler dispatch

    @Test func itHygieneCallerIsolatedFromCallee() {
        // Caller seeds `it`, calls doThing (defined in stack script) which sets its
        // own `it` and returns a value.  After return, caller's `it` must be unchanged;
        // `the result` must be the callee's return value.
        var doc = HypeDocument.newDocument()
        doc.stack.script = """
        on doThing
          put "CALLEE_IT" into it
          return "RETVAL"
        end doThing
        """
        let result = runScript("""
        on test
          put "CALLER" into it
          doThing
          put it & "|" & the result into out
          return out
        end test
        """, document: doc)
        #expect(result.status == .completed)
        #expect(result.returnValue == "CALLER|RETVAL")
    }

    // MARK: - T14: say does not set it

    @Test func sayDoesNotSetIt() {
        let result = runScript("""
        on test
          put "ORIGINAL" into it
          say "hi"
          return it
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "ORIGINAL")
    }

    // MARK: - T15: type does not set it

    @Test func typeDoesNotSetIt() {
        let result = runScript("""
        on test
          put "ORIGINAL" into it
          type "hi"
          return it
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "ORIGINAL")
    }

    // MARK: - T16: choose does not set it

    @Test func chooseDoesNotSetIt() {
        let result = runScript("""
        on test
          put "ORIGINAL" into it
          choose "browse" tool
          return it
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "ORIGINAL")
    }

    // MARK: - put empty into line keeps delimiters

    @Test func putEmptyIntoLineKeepsDelimiters() {
        // put empty into line 2 of v — the line becomes empty but delimiters survive.
        // Build the multi-line container using concatenation (avoids embedded newlines
        // in HypeTalk string literals, which the lexer does not support).
        let result = runScript("""
        on test
          put "l1" & return & "l2" & return & "l3" into v
          put empty into line 2 of v
          return v
        end test
        """)
        #expect(result.status == .completed)
        // After modification, lines are joined with "\n" by ChunkWriter.
        // Normalized: "l1\n\nl3"
        #expect(result.returnValue == "l1\n\nl3")
    }

    // MARK: - After range (range after test)

    @Test func afterItemRange() {
        // put "!" after item 2 to 3 of "a,b,c,d" → "a,b,c!,d"
        let result = runScript("""
        on test
          put "a,b,c,d" into v
          put "!" after item 2 to 3 of v
          return v
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "a,b,c!,d")
    }

    // MARK: - Item spacing preserved

    @Test func itemSpacingPreservedOnWrite() {
        // Items are NOT trimmed on the write path.
        // "a, b, c" item 2 ← "Z" → "a,Z, c"
        let result = runScript("""
        on test
          put "a, b, c" into v
          put "Z" into item 2 of v
          return v
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "a,Z, c")
    }

    // MARK: - Item range collapse

    @Test func itemRangeCollapse() {
        // put "ZZ" into item 2 to 3 of "a,b,c,d" → "a,ZZ,d"
        let result = runScript("""
        on test
          put "a,b,c,d" into v
          put "ZZ" into item 2 to 3 of v
          return v
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "a,ZZ,d")
    }

    // MARK: - Word padding

    @Test func wordPaddingPastExtent() {
        // put "Z" into word 4 of "a b" → "a b  Z"
        let result = runScript("""
        on test
          put "a b" into v
          put "Z" into word 4 of v
          return v
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "a b  Z")
    }

    // MARK: - Item padding

    @Test func itemPaddingPastExtent() {
        // put "X" into item 5 of "a,b" → "a,b,,,X"
        let result = runScript("""
        on test
          put "a,b" into v
          put "X" into item 5 of v
          return v
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "a,b,,,X")
    }

    // MARK: - before / after on last char

    @Test func afterLastCharAppends() {
        // put "." after last char of "ab" → "ab."
        let result = runScript("""
        on test
          put "ab" into v
          put "." after last char of v
          return v
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "ab.")
    }
}

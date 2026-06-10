import AppKit
import Testing
import Foundation
@testable import HypeCore

/// Tests that HypeTalk scripts producing huge or non-finite doubles never
/// crash the host process. Each test exercises one of the Int-conversion
/// trap sites identified in the code review.
@Suite("Script Numeric Safety", .serialized)
struct ScriptNumericSafetyTests {

    // MARK: - Harness

    /// Execute a minimal `on test … end test` handler and return the result.
    /// Mirrors the pattern in InterpreterTests; replicated here so the suite
    /// is self-contained (the helper in ScriptTests.swift is fileprivate).
    private func executeScript(_ source: String) async -> ExecutionResult {
        let doc = HypeDocument.newDocument()
        return await runOnLargeStack {
            var lexer = Lexer(source: source)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            guard let script = try? parser.parse(), let handler = script.handlers.first else {
                return ExecutionResult(status: .error, error: ScriptError(message: "Parse failed", line: 0, handler: ""))
            }
            let context = ExecutionContext(
                targetId: doc.cards[0].id,
                currentCardId: doc.cards[0].id,
                document: doc
            )
            let interpreter = Interpreter()
            return interpreter.execute(handler: handler, params: [], context: context)
        }
    }

    // MARK: - formatNumber / power operator

    @Test("put 10 ^ 30 into x produces \"1e+30\" — no crash")
    func hugePowerNoTrap() async {
        let result = await executeScript("""
        on test
          put 10 ^ 30 into x
          return x
        end test
        """)
        #expect(result.status == .completed)
        // formatNumber falls through to String(Double) for out-of-Int-range values
        #expect(result.returnValue == "1e+30")
    }

    // MARK: - round / trunc builtins

    @Test("round(10^300) returns a string without crashing")
    func roundHugeNoTrap() async {
        let result = await executeScript("""
        on test
          return round(10 ^ 300)
        end test
        """)
        #expect(result.status == .completed)
        // 1e300 rounds to itself; formatNumber emits the Swift default string
        #expect(result.returnValue != nil)
        #expect(!(result.returnValue ?? "").isEmpty)
    }

    @Test("trunc(10^300) returns a string without crashing")
    func truncHugeNoTrap() async {
        let result = await executeScript("""
        on test
          return trunc(10 ^ 300)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue != nil)
        #expect(!(result.returnValue ?? "").isEmpty)
    }

    // MARK: - numtochar

    @Test("numtochar(55296) — surrogate code point — returns empty string")
    func numToCharSurrogateReturnsEmpty() async {
        let result = await executeScript("""
        on test
          return numtochar(55296)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "")
    }

    @Test("numtochar(99999999999999999999) — out-of-range — returns empty string")
    func numToCharHugeReturnsEmpty() async {
        let result = await executeScript("""
        on test
          return numtochar(99999999999999999999)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "")
    }

    @Test("numtochar(65) returns \"A\" — regression")
    func numToCharAsciiRegression() async {
        let result = await executeScript("""
        on test
          return numtochar(65)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "A")
    }

    // MARK: - random

    @Test("random(0) returns \"1\" — no crash")
    func randomZeroNoTrap() async {
        let result = await executeScript("""
        on test
          return random(0)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "1")
    }

    @Test("random(-5) returns \"1\" — no crash")
    func randomNegativeNoTrap() async {
        let result = await executeScript("""
        on test
          return random(-5)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "1")
    }

    // MARK: - repeat count

    @Test("repeat with huge literal count and exit repeat — no crash")
    func repeatHugeCountExitsCleanly() async {
        let result = await executeScript("""
        on test
          repeat 999999999999999999999999 times
            exit repeat
          end repeat
          return "ok"
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "ok")
    }

    // MARK: - In-range regressions

    @Test("put 5 + 2 into x produces \"7\" — formatting unchanged")
    func inRangeAdditionFormatting() async {
        let result = await executeScript("""
        on test
          put 5 + 2 into x
          return x
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "7")
    }

    @Test("put 2.5 * 2 into x produces \"5\" — formatting unchanged")
    func inRangeMultiplicationFormatting() async {
        let result = await executeScript("""
        on test
          put 2.5 * 2 into x
          return x
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "5")
    }

    @Test("round(2.4) returns \"2\" — formatting unchanged")
    func inRangeRoundFormatting() async {
        let result = await executeScript("""
        on test
          return round(2.4)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "2")
    }

    @Test("round(2.5) returns \"3\" — rounding unchanged")
    func inRangeRoundHalfUp() async {
        let result = await executeScript("""
        on test
          return round(2.5)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "3")
    }

    @Test("trunc(3.9) returns \"3\" — formatting unchanged")
    func inRangeTruncFormatting() async {
        let result = await executeScript("""
        on test
          return trunc(3.9)
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "3")
    }
}

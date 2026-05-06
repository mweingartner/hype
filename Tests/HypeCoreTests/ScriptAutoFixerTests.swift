import Testing
import Foundation
@testable import HypeCore

@Suite("ScriptAutoFixer — surgical pre-flight repairs")
struct ScriptAutoFixerTests {

    // MARK: - Bare `end` repair

    @Test("bare `end` after `on mouseUp` becomes `end mouseUp`")
    func barEndMatchesHandler() {
        let input = """
        on mouseUp
          go next
        end
        """
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed.contains("end mouseUp"))
        #expect(!fixed.contains("\nend\n") && !fixed.hasSuffix("\nend"))
    }

    @Test("bare `end` after a custom handler picks up the custom name")
    func bareEndMatchesCustomHandler() {
        let input = """
        on requestFinished requestId, eventName
          put requestId into field "log"
        end
        """
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed.contains("end requestFinished"))
    }

    @Test("nested `if` / `end if` is preserved; only the outer `end` is repaired")
    func nestedIfPreserved() {
        let input = """
        on mouseUp
          if x = 1 then
            put 1 into y
          end if
        end
        """
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed.contains("end if"))
        #expect(fixed.contains("end mouseUp"))
    }

    @Test("nested `repeat` / `end repeat` is preserved")
    func nestedRepeatPreserved() {
        let input = """
        on idle
          repeat 5 times
            beep
          end repeat
        end
        """
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed.contains("end repeat"))
        #expect(fixed.contains("end idle"))
    }

    @Test("explicit `end mouseUp` is left untouched")
    func explicitEndMatches() {
        let input = """
        on mouseUp
          go next
        end mouseUp
        """
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed == input)
    }

    @Test("indentation on the bare `end` line is preserved")
    func indentationPreserved() {
        let input = "on mouseUp\n  go next\n  end"
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed.contains("  end mouseUp"))
    }

    @Test("bare `end` with no enclosing handler is left for the parser to flag")
    func bareEndWithoutHandler() {
        let input = "end"
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed == "end")
    }

    @Test("two stacked handlers each get their own `end <name>`")
    func twoHandlersBothFixed() {
        let input = """
        on openCard
          put "hi" into field "x"
        end

        on closeCard
          put "bye" into field "x"
        end
        """
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed.contains("end openCard"))
        #expect(fixed.contains("end closeCard"))
    }

    // MARK: - elseif repair

    @Test("joined `elseif` becomes `else if`")
    func joinedElseIf() {
        let input = """
        on mouseUp
          if x = 1 then
            put 1 into y
          elseif x = 2 then
            put 2 into y
          end if
        end mouseUp
        """
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed.contains("else if x = 2"))
        #expect(!fixed.contains("elseif"))
    }

    @Test("`elseif` matching is case-insensitive")
    func elseIfCaseInsensitive() {
        let input = "ELSEIF x THEN"
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed == "else if x THEN")
    }

    @Test("identifiers containing `elseif` as a substring are NOT changed")
    func elseIfIdentifierNotAffected() {
        // `\belseif\b` should not match the middle of a longer
        // identifier even though the substring appears.
        let input = "put preElseIfMarker into x"
        let fixed = ScriptAutoFixer.autoFix(input)
        #expect(fixed == input)
    }

    // MARK: - Idempotence

    @Test("autoFix is idempotent — running twice produces the same output")
    func idempotent() {
        let input = """
        on mouseUp
          if x = 1 then
            put 1 into y
          elseif x = 2 then
            put 2 into y
          end if
        end
        """
        let once = ScriptAutoFixer.autoFix(input)
        let twice = ScriptAutoFixer.autoFix(once)
        #expect(once == twice)
    }

    // MARK: - Reporting variant

    @Test("autoFixWithReport names every fix that fired")
    func reportingApi() {
        let input = "on mouseUp\n  if x then put 1 into y\n  elseif y then put 2 into y\nend"
        // Note: this one doesn't have `end if` — the elseif fires
        // and so does the bare-end fix. Verify both reported.
        let (fixed, applied) = ScriptAutoFixer.autoFixWithReport(input)
        #expect(applied.contains("bare-end-named"))
        #expect(applied.contains("elseif-spaced"))
        #expect(fixed.contains("end mouseUp"))
        #expect(fixed.contains("else if"))
    }

    @Test("autoFixWithReport returns an empty applied list when nothing changes")
    func reportingApiNoOp() {
        let input = "on mouseUp\n  go next\nend mouseUp"
        let (fixed, applied) = ScriptAutoFixer.autoFixWithReport(input)
        #expect(fixed == input)
        #expect(applied.isEmpty)
    }
}

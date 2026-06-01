import Testing
import Foundation
@testable import HypeCore

/// Regression tests for the `check_script` AI tool.
///
/// `check_script` is the AI-callable syntax checker: before the AI
/// stores a HypeTalk script (via `create_button`, `set_part_property`,
/// etc.), it's instructed by `HypeTalkGuide` to run the script through
/// this tool first and iterate on fixes until it passes. These tests
/// pin the response format so the AI's pattern-matching against `OK:`
/// and `FAIL:` prefixes keeps working, and they cover every AI
/// hallucination the guide documents as an explicit gotcha.
@Suite("check_script tool — syntax validation")
struct CheckScriptToolTests {

    private func makeDoc() -> (HypeDocument, UUID) {
        let doc = HypeDocument.newDocument(name: "Check Script Test")
        return (doc, doc.cards[0].id)
    }

    // MARK: - OK path

    @Test("a simple handler block parses successfully")
    func simpleHandlerBlockPasses() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "check_script",
            arguments: [
                "script": "on mouseUp\n  go next\nend mouseUp",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("OK:"))
        #expect(result.contains("mouseUp"))
    }

    @Test("a bare one-liner is auto-wrapped and passes")
    func bareOneLinerIsAutoWrapped() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "check_script",
            arguments: [
                "script": "go next",
            ],
            document: &doc,
            currentCardId: cardId
        )
        // A bare command is what the AI passes as `create_button`'s
        // script argument. The storage tool auto-wraps it in `on
        // mouseUp ... end mouseUp`, and check_script does the same
        // so the AI can validate either form.
        #expect(result.hasPrefix("OK:"))
    }

    @Test("multi-handler script reports handler count")
    func multiHandlerScriptReportsCount() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = """
            on mouseUp
              go next
            end mouseUp

            on mouseDown
              beep
            end mouseDown
            """
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("OK:"))
        #expect(result.contains("2 handlers"))
    }

    @Test("prefix-function syntax passes (random 5, abs -3, sqrt 16)")
    func prefixFunctionSyntaxPasses() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = """
            on idle
              put random 5 into r
              put abs -3 into a
              put sqrt 16 into s
            end idle
            """
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("OK:"))
    }

    @Test("chunk expressions with plural keywords parse")
    func chunkExpressionsPass() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = """
            on mouseUp
              put "a,b,c,d" into s
              put item 2 of s into x
              put items 1 to 3 of s into y
              put the length of s into n
            end mouseUp
            """
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("OK:"))
    }

    @Test("model-style nested logic with else-if, line counts, and loops passes")
    func modelStyleNestedLogicPasses() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = """
            on mouseUp
              put "Torch" & linefeed & "Rope" & linefeed & "Map" into invDump
              put "" into outcome
              repeat with i from 1 to the number of lines in invDump
                put line i of invDump into itemName
                if itemName is "Torch" then
                  put "light" after outcome
                else if itemName is "Rope" then
                  if outcome contains "light" then
                    put ",climb" after outcome
                  else
                    put ",tie" after outcome
                  end if
                else
                  put ",other" after outcome
                end if
              end repeat
            end mouseUp
            """
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("OK:"))
    }

    @Test("the loc of me and set the rotation of me parse")
    func meReferencePasses() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = """
            on idle
              put the loc of me into pos
              set the rotation of me to 45
            end idle
            """
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("OK:"))
    }

    // MARK: - FAIL path

    @Test("the -int 1 hallucination reports a parse error in a put statement")
    func intHallucinationFails() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        // The `-int 1` form came from an LLM that conflated HypeTalk
        // with other scripting languages. `int` isn't a keyword, so
        // this should parse-fail and the AI can be told to use `-1`
        // instead via the guide's "Common AI hallucinations" section.
        //
        // We deliberately place the hallucination inside a `put`
        // statement because the `put <expr> into <target>` grammar
        // requires `into` after a complete expression — `-int 1`
        // leaves `1` dangling and the parser rejects it cleanly.
        // (`multiply dy by -int 1` ALSO happens to parse because
        // multiply's statement boundary is newline-based, which
        // means the trailing `1` is silently dropped — a separate
        // parser weakness we're not fixing here.)
        let script = """
            on idle
              put -int 1 into x
            end idle
            """
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("FAIL:"))
        // The response must mention the line number so the AI can
        // anchor its fix.
        #expect(result.contains("Line"))
    }

    @Test("javascript-style hype.showNextCard call reports a parse error")
    func javaScriptStyleNavigationFails() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": "hype.showNextCard();"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("FAIL:"))
    }

    @Test("misspelled keyword reports a parse error")
    func misspelledKeywordFails() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = """
            on mouseUp
              iff x > 10 then
                beep
              end if
            end mouseUp
            """
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("FAIL:"))
    }

    @Test("unclosed handler block reports a parse error")
    func unclosedHandlerFails() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = """
            on mouseUp
              go next
            """
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("FAIL:"))
    }

    @Test("empty script returns a soft EMPTY error")
    func emptyScriptIsSoftError() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": ""],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("EMPTY:"))
    }

    @Test("whitespace-only script returns EMPTY error")
    func whitespaceOnlyScriptIsSoftError() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": "   \n  \t  \n"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("EMPTY:"))
    }

    @Test("FAIL response instructs the AI to call check_script again")
    func failResponseEncouragesIteration() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        // `set` requires `the <prop> of <ref> to <val>` — a bare
        // `set x` with no property path leaves the parser expecting
        // `the`, which forces a clean parse failure we can assert
        // against.
        let result = await executor.execute(
            toolName: "check_script",
            arguments: ["script": "on mouseUp\n  set\nend mouseUp"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix("FAIL:"))
        #expect(result.contains("check_script"))
    }

    // MARK: - Tool schema

    @Test("check_script is registered in HypeToolDefinitions.allTools")
    func checkScriptIsRegistered() {
        let tool = HypeToolDefinitions.allTools.first { $0.function.name == "check_script" }
        #expect(tool != nil)
        #expect(tool?.function.parameters.required.contains("script") == true)
    }

    @Test("check_script tool description mentions the iterate-until-OK protocol")
    func checkScriptDescriptionMentionsProtocol() {
        let tool = HypeToolDefinitions.allTools.first { $0.function.name == "check_script" }
        #expect(tool != nil)
        let desc = tool?.function.description ?? ""
        #expect(desc.contains("REQUIRED"))
        #expect(desc.lowercased().contains("iterat"))
    }

    // MARK: - Runtime document state unaffected

    @Test("check_script does not mutate the document")
    func checkScriptIsSideEffectFree() async {
        var (doc, cardId) = makeDoc()
        let before = doc.parts.count
        let beforeCards = doc.cards.count
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "check_script",
            arguments: ["script": "on mouseUp\n  go next\nend mouseUp"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.parts.count == before)
        #expect(doc.cards.count == beforeCards)
    }
}

// MARK: - HypeTalkGuide mandate section

@Suite("HypeTalkGuide — check_script mandate")
struct HypeTalkGuideCheckScriptTests {

    @Test("guide contains the MANDATORY check_script section")
    func guideHasCheckScriptMandate() {
        let guide = HypeTalkGuide.llmContext
        #expect(guide.contains("check_script"))
        #expect(guide.contains("MANDATORY"))
    }

    @Test("guide describes the iterate-until-OK loop")
    func guideDescribesIterationLoop() {
        let guide = HypeTalkGuide.llmContext
        // The guide should tell the AI what to do on OK and FAIL.
        #expect(guide.contains("OK:"))
        #expect(guide.contains("FAIL:"))
    }
}

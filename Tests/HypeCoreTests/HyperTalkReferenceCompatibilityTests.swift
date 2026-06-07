import Foundation
import Testing
@testable import HypeCore

/// Reference-backed compatibility checks for Apple HyperTalk syntax.
///
/// Source used for this suite:
/// https://cancel.fm/stuff/share/HyperCard_Script_Language_Guide_1.pdf
///
/// These tests intentionally cover representative grammar and runtime contracts
/// from the command/function syntax summary rather than every vocabulary word.
/// Hype-specific extensions are included so compatibility work does not narrow
/// the modern language surface.
@Suite("HyperTalk reference compatibility", .serialized)
struct HyperTalkReferenceCompatibilityTests {
    private func parse(_ source: String) -> Script? {
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        return try? parser.parse()
    }

    private func parsesStatement(_ statement: String) -> Bool {
        parse("""
        on mouseUp
          \(statement)
        end mouseUp
        """) != nil
    }

    @Test("classic command forms from Appendix H parse")
    func classicCommandFormsParse() {
        let statements = [
            "add 3 to total",
            "subtract 2 from total",
            "multiply total by 4",
            "divide total by 2",
            "answer file \"Choose a file\" of type \"TEXT\"",
            "answer program \"Choose an app\" of type \"APPL\"",
            "answer \"Continue?\" with \"Yes\" or \"No\" or \"Cancel\"",
            "ask file \"Save as\" with default \"Untitled\"",
            "ask password clear \"Password\" with \"secret\"",
            "arrowKey left",
            "commandKeyDown \"P\"",
            "controlKey 26",
            "functionKey 1",
            "keyDown \"a\"",
            "enterInField",
            "enterKey",
            "returnInField",
            "returnKey",
            "tabKey",
            "read from file \"input.txt\" at 4 for 20",
            "read from file \"input.txt\" until return",
            "read from file \"input.txt\" until eof",
            "write \"abc\" to file \"output.txt\" at start",
            "write \"abc\" to file \"output.txt\" at end",
            "write \"abc\" to file \"output.txt\" at eof",
            "hide card picture",
            "show background picture",
            "lock messages",
            "unlock recent",
            "play \"harpsichord\" tempo 120 \"c4q e4q g4q\"",
            "play stop"
        ]

        for statement in statements {
            #expect(parsesStatement(statement), "Expected to parse: \(statement)")
        }
    }

    @Test("classic object aliases and collection names parse")
    func classicObjectAliasesParse() {
        let statements = [
            "put the name of cd 1 into cardName",
            "put the script of bkgnd 1 into backgroundScript",
            "put the number of cds into cardCount",
            "put the number of bkgnds into bgCount",
            "put the number of btns into buttonCount",
            "put the number of flds into fieldCount",
            "put the visible of card button \"OK\" into isVisible",
            "set the hilite of bg btn \"Choice\" to true"
        ]

        for statement in statements {
            #expect(parsesStatement(statement), "Expected to parse: \(statement)")
        }
    }

    @Test("the-function-of-value forms parse and execute")
    func classicTheFunctionOfFormsExecute() async {
        var (document, cardId, buttonId) = makeReferenceDoc()
        let result = await dispatchReferenceScript("""
        on mouseUp
          put the abs of -5 into field "Out"
          put "," after field "Out"
          put the sqrt of 16 after field "Out"
          put "," after field "Out"
          put the length of "hello" after field "Out"
          put "," after field "Out"
          put the charToNum of "A" after field "Out"
        end mouseUp
        """, document: &document, cardId: cardId, targetId: buttonId)

        #expect(result.status == .completed, "Execution failed: \(result.error?.message ?? "nil")")
        #expect(referenceFieldText(result, name: "Out") == "5,4,5,65")
    }

    @Test("classic file read bounds and write placement execute in sandbox")
    func classicReadWriteFormsExecute() async throws {
        let root = try makeReferenceTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("abcdef\rghij".utf8).write(to: root.appendingPathComponent("input.txt"))

        var (document, cardId, buttonId) = makeReferenceDoc()
        let provider = SandboxedFileAccessProvider(root: root)
        let result = await dispatchReferenceScript("""
        on mouseUp
          read from file "input.txt" at 4 for 3
          put it into field "Out"
          put "|" after field "Out"
          read from file "input.txt" until return
          put it after field "Out"
          write "middle" to file "out.txt"
          write "start-" to file "out.txt" at start
          write "-end" to file "out.txt" at eof
          read from file "out.txt"
          put "|" after field "Out"
          put it after field "Out"
        end mouseUp
        """, document: &document, cardId: cardId, targetId: buttonId, fileProvider: provider)

        #expect(result.status == .completed, "Execution failed: \(result.error?.message ?? "nil")")
        let outContents = try? String(contentsOf: root.appendingPathComponent("out.txt"), encoding: .utf8)
        #expect(outContents == "start-middle-end")
        #expect(referenceFieldText(result, name: "Out") == "def|abcdef\r|start-middle-end")
    }

    @Test("put into a field does not clobber It")
    func putIntoFieldDoesNotClobberIt() async {
        var (document, cardId, buttonId) = makeReferenceDoc()
        let result = await dispatchReferenceScript("""
        on mouseUp
          get "original"
          put "visible" into field "Out"
          put "|" after field "Out"
          put it after field "Out"
        end mouseUp
        """, document: &document, cardId: cardId, targetId: buttonId)

        #expect(result.status == .completed, "Execution failed: \(result.error?.message ?? "nil")")
        #expect(referenceFieldText(result, name: "Out") == "visible|original")
    }

    @Test("answer with three buttons keeps separate button expressions")
    func answerButtonsRemainSeparate() throws {
        let script = try #require(parse("""
        on mouseUp
          answer "Continue?" with "Yes" or "No" or "Cancel"
        end mouseUp
        """))
        guard case .answer(_, let buttons)? = script.handlers.first?.body.first else {
            Issue.record("Expected first statement to be answer")
            return
        }
        #expect(buttons.count == 3)
    }

    @Test("arrowKey left and right navigate cards")
    func arrowKeyNavigatesCards() async {
        var document = HypeDocument.newDocument()
        let firstCardId = document.cards[0].id
        var secondCard = document.addCard(afterIndex: 0)
        secondCard.name = "Second"
        document.cards[1] = secondCard
        let secondCardId = secondCard.id
        var button = Part(partType: .button, cardId: firstCardId, name: "Nav", left: 0, top: 0, width: 80, height: 24)
        button.script = "on mouseUp\n  arrowKey right\nend mouseUp"
        document.addPart(button)

        let rightResult = await MessageDispatcher().dispatch(
            message: "mouseUp",
            params: [],
            targetId: button.id,
            document: document,
            currentCardId: firstCardId
        )
        #expect(rightResult.navigationTarget == secondCardId)

        var secondButton = Part(partType: .button, cardId: secondCardId, name: "Back", left: 0, top: 0, width: 80, height: 24)
        secondButton.script = "on mouseUp\n  arrowKey left\nend mouseUp"
        document.addPart(secondButton)
        let leftResult = await MessageDispatcher().dispatch(
            message: "mouseUp",
            params: [],
            targetId: secondButton.id,
            document: document,
            currentCardId: secondCardId
        )
        #expect(leftResult.navigationTarget == firstCardId)
    }

    @Test("Hype extensions still parse")
    func hypeExtensionsStillParse() {
        let script = """
        on mouseUp
          ask ai "Improve this card" with model "gpt-4.1"
          ask meshy "low poly robot" with style realistic with message "meshDone"
          remesh asset "ship" to 1000 with message "remeshDone"
          retexture asset "ship" with prompt "brass"
          say "hello"
          activateListener true
          set the theme of this card to "Classic"
          create music pattern "Theme" with instrument "Harpsichord" tempo 120 notes "c4q e4q g4q"
          play pattern "Theme" loop
          authorize apple music
          search apple music for "Miles Davis" type song limit 1
          create sprite "player" with asset "hero"
          create tilemap "maze" columns 10 rows 10 tilesize 32
          fill tilemap "maze" with 1
          clear tilemap "maze"
          set the chartType of chart "Stats" to "spider"
        end mouseUp
        """
        #expect(parse(script) != nil)
    }

    @Test("nested control flow used by AI-authored scripts still parses")
    func nestedControlFlowParses() {
        let script = """
        on updateFrame
          repeat with i = 1 to 4
            if i mod 2 is 0 then
              repeat while score < 10
                add 1 to score
                if score > 5 then
                  exit repeat
                else
                  next repeat
                end if
              end repeat
            else if i is 3 then
              put "three" into marker
            else
              put "other" into marker
            end if
          end repeat
        end updateFrame
        """
        #expect(parse(script) != nil)
    }
}

private func makeReferenceTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("HypeTalkReference-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeReferenceDoc() -> (HypeDocument, UUID, UUID) {
    var document = HypeDocument.newDocument(name: "HyperTalk Reference")
    let cardId = document.cards[0].id
    var button = Part(partType: .button, cardId: cardId, name: "Run", left: 0, top: 0, width: 80, height: 24)
    button.script = ""
    document.addPart(button)
    let field = Part(partType: .field, cardId: cardId, name: "Out", left: 0, top: 32, width: 320, height: 48)
    document.addPart(field)
    return (document, cardId, button.id)
}

private func dispatchReferenceScript(
    _ script: String,
    document: inout HypeDocument,
    cardId: UUID,
    targetId: UUID,
    fileProvider: FileAccessProvider = StubFileAccessProvider()
) async -> ExecutionResult {
    document.updatePart(id: targetId) { $0.script = script }
    let snapshot = document
    let result = await runOnLargeStack {
        MessageDispatcher().dispatch(
            message: "mouseUp",
            params: [],
            targetId: targetId,
            document: snapshot,
            currentCardId: cardId,
            fileProvider: fileProvider
        )
    }
    if let modifiedDocument = result.modifiedDocument {
        document = modifiedDocument
    }
    return result
}

private func referenceFieldText(_ result: ExecutionResult, name: String) -> String? {
    result.modifiedDocument?.parts.first { $0.name == name }?.textContent
}

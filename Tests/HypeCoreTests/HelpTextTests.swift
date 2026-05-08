import Testing
import Foundation
@testable import HypeCore

// MARK: - Test Helpers

private func makeTestDoc() -> (HypeDocument, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    var btn = Part(partType: .button, cardId: cardId, name: "TestButton",
                   left: 10, top: 10, width: 100, height: 30)
    btn.script = ""
    doc.addPart(btn)
    return (doc, cardId, btn.id)
}

private func runScript(_ script: String,
                       on doc: inout HypeDocument,
                       cardId: UUID,
                       targetId: UUID) async -> ExecutionResult {
    doc.updatePart(id: targetId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    let snapshot = doc
    let result = await runOnLargeStack {
        dispatcher.dispatch(
            message: "mouseUp", params: [], targetId: targetId,
            document: snapshot, currentCardId: cardId
        )
    }
    if let modified = result.modifiedDocument { doc = modified }
    return result
}

// MARK: - Codable forward-compat

@Suite("Part.helpText Codable")
struct HelpTextCodableTests {

    @Test func partHelpTextRoundTrip() throws {
        var p = Part(partType: .button, name: "x", left: 0, top: 0, width: 100, height: 30)
        p.helpText = "Click to save the document"
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.helpText == "Click to save the document")
    }

    @Test func partHelpTextDefaultIsEmpty() throws {
        // A part encoded WITHOUT a helpText key (forward-compat:
        // older .hype files saved before helpText existed) decodes
        // with `helpText == ""`.
        let p = Part(partType: .button, name: "x", left: 0, top: 0, width: 100, height: 30)
        let data = try JSONEncoder().encode(p)
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("encoded Part isn't a JSON dict")
            return
        }
        dict.removeValue(forKey: "helpText")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.helpText == "")
    }

    @Test func partHelpTextPreservesNewlines() throws {
        // Multi-line is allowed; embedded `\n` round-trips through
        // JSON unchanged. The system tooltip will render it as
        // multiple lines.
        var p = Part(partType: .button, name: "x", left: 0, top: 0, width: 100, height: 30)
        p.helpText = "First line\nSecond line"
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.helpText == "First line\nSecond line")
    }
}

// MARK: - HypeTalk get/set

@Suite("HypeTalk helpText")
struct HypeTalkHelpTextTests {

    @Test func setHelpTextCanonical() async {
        var (doc, cardId, btnId) = makeTestDoc()
        let result = await runScript("""
        on mouseUp
          set the helpText of button "TestButton" to "Saves the document"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.helpText == "Saves the document")
    }

    @Test func setHelpTextViaTooltipAlias() async {
        // `tooltip` is the natural macOS-author alias.
        var (doc, cardId, btnId) = makeTestDoc()
        let result = await runScript("""
        on mouseUp
          set the tooltip of button "TestButton" to "Hint shown on hover"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.helpText == "Hint shown on hover")
    }

    @Test func setHelpTextViaShortAlias() async {
        // `help` is the short form.
        var (doc, cardId, btnId) = makeTestDoc()
        let result = await runScript("""
        on mouseUp
          set the help of button "TestButton" to "Press to advance"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.helpText == "Press to advance")
    }

    @Test func clearHelpText() async {
        var (doc, cardId, btnId) = makeTestDoc()
        doc.updatePart(id: btnId) { $0.helpText = "old text" }
        let result = await runScript("""
        on mouseUp
          set the helpText of button "TestButton" to ""
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.helpText == "")
    }

    @Test func getHelpTextViaScript() async {
        var (doc, cardId, btnId) = makeTestDoc()
        doc.updatePart(id: btnId) { $0.helpText = "Stored bubble" }
        // Add an output field to capture the read value.
        var out = Part(partType: .field, cardId: cardId, name: "out",
                       left: 0, top: 100, width: 200, height: 30)
        out.lockText = false
        doc.addPart(out)
        let result = await runScript("""
        on mouseUp
          put the tooltip of button "TestButton" into field "out"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let outField = result.modifiedDocument?.parts.first(where: { $0.name == "out" })
        #expect(outField?.textContent == "Stored bubble")
    }
}

// MARK: - AI tool surface

@Suite("AI tool helpText")
struct AIToolHelpTextTests {

    @Test func setPartPropertyHelpText() async {
        var (doc, cardId, _) = makeTestDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "TestButton",
                "property": "helpText",
                "value": "Set via AI tool",
            ],
            document: &doc, currentCardId: cardId
        )
        let btn = doc.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.helpText == "Set via AI tool")
    }

    @Test func setPartPropertyHelpTextSnakeCase() async {
        // The model emits snake_case sometimes; the dispatcher
        // accepts both `helpText` and `help_text`.
        var (doc, cardId, _) = makeTestDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "TestButton",
                "property": "help_text",
                "value": "Snake-case set",
            ],
            document: &doc, currentCardId: cardId
        )
        let btn = doc.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.helpText == "Snake-case set")
    }

    @Test func formatAllPropertiesIncludesHelpText() async {
        var (doc, cardId, _) = makeTestDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "list_all_properties",
            arguments: ["part_name": "TestButton"],
            document: &doc, currentCardId: cardId
        )
        // Should mention helpText so the AI knows the surface
        // exists, with `(none)` when empty.
        #expect(result.contains("helpText"))
        #expect(result.contains("(none)"))
    }
}

import Testing
import Foundation
@testable import HypeCore

/// Integration tests for the host-side script storage gate in `HypeToolExecutor`.
///
/// These tests confirm that:
/// - Valid scripts pass and mutate the document.
/// - Invalid scripts are refused (sentinel returned, document unchanged).
/// - The executor's atomicity guarantee holds for create_button/create_field.
@Suite("Script storage gate — executor integration")
struct ScriptStorageGateIntegrationTests {

    // MARK: - Test helpers

    private func makeDoc() -> (HypeDocument, UUID) {
        let doc = HypeDocument.newDocument(name: "Gate Test")
        return (doc, doc.cards[0].id)
    }

    private func isSentinel(_ result: String) -> Bool {
        result.hasPrefix(ScriptDraftRefusal.sentinelPrefix)
    }

    // MARK: - set_card_script

    @Test("set_card_script with valid draft commits script and returns success")
    func setCardScript_validDraft_commits() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = "on mouseUp\nput 1 into x\nend mouseUp"
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result))
        #expect(result.contains("Set script"))
        #expect(doc.cards[0].script.contains("put 1 into x"))
    }

    @Test("set_card_script with invalid syntax refuses and leaves doc unchanged")
    func setCardScript_invalidSyntax_refuses() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let badScript = "on mouseUp\nput 1 into x"  // missing end mouseUp
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["script": badScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result))
        #expect(doc.cards[0].script.isEmpty)
    }

    @Test("set_card_script with markdown fence refuses")
    func setCardScript_markdownFence_refuses() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let fencedScript = "```\non mouseUp\nput 1 into x\nend mouseUp\n```"
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["script": fencedScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result))
        #expect(doc.cards[0].script.isEmpty)
    }

    @Test("set_card_script with unresolved field reference refuses")
    func setCardScript_unresolvedRef_refuses() async {
        var (doc, cardId) = makeDoc()  // no parts in this doc
        let executor = HypeToolExecutor()
        let script = "on mouseUp\nput 99 into field \"NonExistent\"\nend mouseUp"
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result))
        #expect(doc.cards[0].script.isEmpty)
    }

    // MARK: - set_stack_script

    @Test("set_stack_script with valid draft commits script")
    func setStackScript_validDraft_commits() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = "on openStack\nput \"hello\" into x\nend openStack"
        let result = await executor.execute(
            toolName: "set_stack_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result))
        #expect(doc.stack.script.contains("openStack"))
    }

    // MARK: - set_background_script

    @Test("set_background_script with valid draft commits script")
    func setBackgroundScript_validDraft_commits() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let script = "on closeBackground\nput \"bye\" into x\nend closeBackground"
        let result = await executor.execute(
            toolName: "set_background_script",
            arguments: ["script": script, "background_name": ""],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result))
        #expect(doc.backgrounds[0].script.contains("closeBackground"))
    }

    // MARK: - set_scene_script

    @Test("set_scene_script with valid draft commits script")
    func setSceneScript_validDraft_commits() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()

        // First create a sprite area to have a scene.
        let createResult = await executor.execute(
            toolName: "create_sprite_area",
            arguments: [
                "name": "GameArea",
                "left": "10", "top": "10", "width": "300", "height": "200"
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(createResult.contains("GameArea"))

        let script = "on frameUpdate\nput 1 into x\nend frameUpdate"
        let result = await executor.execute(
            toolName: "set_scene_script",
            arguments: ["sprite_area_name": "GameArea", "script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result))
    }

    // MARK: - set_node_script

    @Test("set_node_script with valid draft commits script")
    func setNodeScript_validDraft_commits() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()

        // Create area + sprite node.
        _ = await executor.execute(
            toolName: "create_sprite_area",
            arguments: ["name": "Arena", "left": "10", "top": "10", "width": "300", "height": "200"],
            document: &doc,
            currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "add_sprite_to_scene",
            arguments: ["sprite_area_name": "Arena", "sprite_name": "ball", "x": "100", "y": "100"],
            document: &doc,
            currentCardId: cardId
        )

        let script = "on beginContact\nput 1 into x\nend beginContact"
        let result = await executor.execute(
            toolName: "set_node_script",
            arguments: ["sprite_area_name": "Arena", "node_name": "ball", "script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result))
    }

    // MARK: - set_part_property (script)

    @Test("set_part_property with valid script commits it")
    func setPartProperty_scriptValid_commits() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()

        // Create a button first.
        _ = await executor.execute(
            toolName: "create_button",
            arguments: ["name": "MyBtn", "left": "50", "top": "50", "width": "100", "height": "40"],
            document: &doc,
            currentCardId: cardId
        )

        let script = "on mouseUp\ngo next\nend mouseUp"
        let result = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "MyBtn", "property": "script", "value": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result))
        let part = doc.parts.first(where: { $0.name == "MyBtn" })
        #expect(part?.script.contains("go next") == true)
    }

    @Test("set_part_property with invalid script refuses and leaves script unchanged")
    func setPartProperty_scriptInvalid_refuses() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "create_button",
            arguments: ["name": "MyBtn", "left": "50", "top": "50", "width": "100", "height": "40"],
            document: &doc,
            currentCardId: cardId
        )

        let badScript = "on mouseUp\nvar x = 5;"  // JS syntax, no end
        let result = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "MyBtn", "property": "script", "value": badScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result))
        let part = doc.parts.first(where: { $0.name == "MyBtn" })
        // Script should still be empty (the button was created without a script).
        #expect(part?.script.isEmpty == true)
    }

    // MARK: - create_button atomicity

    @Test("create_button with valid script creates part and stores script")
    func createButton_validScript_partCreatedWithScript() async {
        var (doc, cardId) = makeDoc()
        let partCountBefore = doc.parts.count
        let executor = HypeToolExecutor()
        let script = "on mouseUp\ngo next\nend mouseUp"
        let result = await executor.execute(
            toolName: "create_button",
            arguments: ["name": "NavBtn", "left": "10", "top": "10", "width": "80", "height": "30", "script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result))
        #expect(doc.parts.count == partCountBefore + 1)
        #expect(doc.parts.last?.name == "NavBtn")
        #expect(doc.parts.last?.script.contains("go next") == true)
    }

    @Test("create_button with invalid script refuses outright and part is NOT created")
    func createButton_invalidScript_refusesOutright_partNotCreated() async {
        var (doc, cardId) = makeDoc()
        let partCountBefore = doc.parts.count
        let executor = HypeToolExecutor()
        let badScript = "function() { return 5; }"
        let result = await executor.execute(
            toolName: "create_button",
            arguments: ["name": "BadBtn", "left": "10", "top": "10", "width": "80", "height": "30", "script": badScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result))
        // No part should have been added — atomicity guarantee.
        #expect(doc.parts.count == partCountBefore)
    }

    // MARK: - create_field atomicity

    @Test("create_field with invalid script refuses outright and field is NOT created")
    func createField_invalidScript_refusesOutright() async {
        var (doc, cardId) = makeDoc()
        let partCountBefore = doc.parts.count
        let executor = HypeToolExecutor()
        let badScript = "```\nconst x = 5;\n```"
        let result = await executor.execute(
            toolName: "create_field",
            arguments: ["name": "BadField", "left": "10", "top": "60", "width": "200", "height": "30", "script": badScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result))
        #expect(doc.parts.count == partCountBefore)
    }

    // MARK: - Oversized draft truncation

    @Test("oversized script draft is truncated and refused with forbiddenPattern failure")
    func setCardScript_oversizedDraft_truncated() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        // 50 KB of script content
        let oversized = "on mouseUp\n" + String(repeating: "put 1 into x\n", count: 4000) + "end mouseUp"
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["script": oversized],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result))
        // Decode and check
        let refusal = ScriptDraftRefusal.decode(from: result)
        #expect(refusal != nil)
        #expect(refusal?.rawScript.count ?? 0 <= ScriptDraftRefusal.scriptSizeCap + 100)
        #expect(refusal?.failures.contains(where: { $0.kind == .forbiddenPattern }) == true)
        // Doc should be unchanged.
        #expect(doc.cards[0].script.isEmpty)
    }

    // MARK: - Sentinel well-formedness

    @Test("refused result is a valid decodeable sentinel")
    func refusedResult_isValidSentinel() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let badScript = "on mouseUp\nput 1 into x"  // no end
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["script": badScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result))
        let refusal = ScriptDraftRefusal.decode(from: result)
        #expect(refusal != nil)
        #expect(refusal?.toolName == "set_card_script")
        #expect(refusal?.failures.isEmpty == false)
    }
}

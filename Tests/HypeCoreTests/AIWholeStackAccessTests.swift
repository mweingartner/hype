import Foundation
import Testing
@testable import HypeCore

@Suite("AI whole-stack access")
struct AIWholeStackAccessTests {
    private func fixture() -> (HypeDocument, UUID, UUID, UUID) {
        var document = HypeDocument.newDocument(name: "Whole stack")
        let first = document.cards[0].id
        let second = document.addCard(afterIndex: 0, backgroundName: nil)
        let remote = Part(partType: .field, cardId: second.id, name: "Remote content", left: 10, top: 10, width: 100, height: 30)
        document.addPart(remote)
        return (document, first, second.id, remote.id)
    }

    @Test("inspect a named target card without navigating the active card")
    func readsOffCardContents() async {
        var (document, current, other, _) = fixture()
        let result = await HypeToolExecutor().execute(toolName: "get_card_parts", arguments: ["target_card": other.uuidString], document: &document, currentCardId: current)
        #expect(result.contains("Remote content"))
        #expect(document.cards[0].id == current)
    }

    @Test("edit an exact off-card part ID even when its card is not visible")
    func editsOffCardPartByID() async {
        var (document, current, _, partID) = fixture()
        _ = await HypeToolExecutor().execute(toolName: "set_part_property", arguments: ["part_name": partID.uuidString, "property": "text", "value": "Edited remotely"], document: &document, currentCardId: current)
        #expect(document.parts.first(where: { $0.id == partID })?.textContent == "Edited remotely")
    }

    @Test("an invalid or conflicting explicit target cannot fall back to another card")
    func refusesInvalidTargets() async {
        var (document, current, other, partID) = fixture()
        let executor = HypeToolExecutor()
        for target in [UUID().uuidString, current.uuidString] {
            let result = await executor.execute(toolName: "set_part_property", arguments: ["target_card": target, "part_name": partID.uuidString, "property": "text", "value": "wrong"], document: &document, currentCardId: current)
            #expect(result.contains("not found") || result.contains("does not belong"))
            #expect(document.parts.first(where: { $0.id == partID })?.textContent == "")
        }
        _ = await executor.execute(toolName: "set_part_property", arguments: ["target_card": other.uuidString, "part_name": partID.uuidString, "property": "text", "value": "right"], document: &document, currentCardId: current)
        #expect(document.parts.first(where: { $0.id == partID })?.textContent == "right")
    }

    @Test("duplicate card and part names can be addressed exactly by UUID")
    func duplicateNamesHaveExactIdentity() async {
        var (document, current, other, partID) = fixture()
        document.cards[1].name = document.cards[0].name
        document.addPart(Part(partType: .field, cardId: current, name: "Remote content", left: 0, top: 0, width: 100, height: 30))
        _ = await HypeToolExecutor().execute(toolName: "set_part_property", arguments: ["part_name": partID.uuidString, "property": "text", "value": "Only this one"], document: &document, currentCardId: current)
        #expect(document.parts.first(where: { $0.id == partID })?.textContent == "Only this one")
        #expect(document.parts.first(where: { $0.cardId == current })?.textContent == "")
        let read = await HypeToolExecutor().execute(toolName: "get_card_parts", arguments: ["target_card": other.uuidString], document: &document, currentCardId: current)
        #expect(read.contains("Only this one"))
        let ambiguous = await HypeToolExecutor().execute(toolName: "get_card_parts", arguments: ["target_card": document.cards[0].name], document: &document, currentCardId: current)
        #expect(ambiguous.contains("ambiguous"))
    }

    @Test("inventory pagination covers every object once and masks secure values")
    func inventoryIsBoundedAndPrivate() async throws {
        var (document, current, _, _) = fixture()
        var secret = Part(partType: .field, cardId: current, name: "Password", left: 0, top: 0, width: 100, height: 30)
        secret.fieldStyle = .secure
        secret.textContent = "private-value-for-test"
        document.addPart(secret)
        for pageSize in [1, 2, 3, 10] {
            var offset = 0
            var ids: [String] = []
            while true {
                let result = await HypeToolExecutor().execute(toolName: "list_stack_contents", arguments: ["limit": String(pageSize), "offset": String(offset)], document: &document, currentCardId: current)
                #expect(!result.contains(secret.textContent))
                let json = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
                let items = try #require(json["items"] as? [[String: String]])
                #expect(items.count <= pageSize)
                ids += items.compactMap { $0["id"] }
                guard let next = json["next_offset"] as? Int else { break }
                #expect(next > offset)
                offset = next
            }
            #expect(ids.count == 6) // stack, two cards, one background, two fields
            #expect(Set(ids).count == ids.count)
        }
        let search = await HypeToolExecutor().execute(toolName: "list_stack_contents", arguments: ["query": secret.textContent], document: &document, currentCardId: current)
        let json = try #require(JSONSerialization.jsonObject(with: Data(search.utf8)) as? [String: Any])
        #expect(json["total"] as? Int == 0)
        let masked = await HypeToolExecutor().execute(toolName: "get_part_property", arguments: ["part_name": secret.id.uuidString, "property": "text"], document: &document, currentCardId: current)
        #expect(masked == "(masked)")
    }

    @Test("discovery exposes complete real schemas without filesystem or context-policy bypasses")
    func discoveryPreservesCatalogAndPolicy() {
        let base = HypeToolDefinitions.cardControlAuthoringTools
        #expect(!base.contains { $0.function.name == "set_node_property" })
        let names = HypeToolDefinitions.addingStackToolDiscoveries([], query: "set_node_property")
        let expanded = HypeToolDefinitions.withDiscoveredStackTools(base, names: names)
        let node = expanded.first { $0.function.name == "set_node_property" }
        #expect(node?.function.parameters.properties["sprite_area_name"]?.type == "string")
        #expect(node?.function.parameters.properties["target_card"]?.type == "string")
        #expect(Set(expanded.map(\.function.name)).count == expanded.count)
        let unsafe = HypeToolDefinitions.withDiscoveredStackTools(base, names: ["read_file", "write_file", "fetch_url", "read_ai_context_item"])
        #expect(!unsafe.contains { ["read_file", "write_file", "fetch_url", "read_ai_context_item"].contains($0.function.name) })
        #expect(HypeToolDefinitions.discoverStackTools(query: "scene").count <= 12)
        #expect(base.contains { $0.function.name == "list_stack_contents" })
        #expect(HypeToolDefinitions.spriteSceneAuthoringTools.contains { $0.function.name == "discover_stack_tools" })
    }

    @Test("off-card edits preserve transaction preview, apply, and rollback")
    func transactionSemantics() async {
        var (document, current, _, partID) = fixture()
        let engine = AIEditTransactionRunner(executor: HypeToolExecutor())
        let call = OllamaToolCall(function: OllamaToolCallFunction(name: "set_part_property", arguments: ["part_name": partID.uuidString, "property": "text", "value": "previewed"]))
        var transaction = await engine.preview(toolCalls: [call], document: document, currentCardId: current, prompt: "Edit the off-card field", providerName: "test")
        #expect(document.parts.first(where: { $0.id == partID })?.textContent == "")
        #expect(transaction.delta.changedPartIds == [partID])
        _ = engine.apply(&transaction, to: &document)
        #expect(document.parts.first(where: { $0.id == partID })?.textContent == "previewed")
        _ = engine.rollback(&transaction, to: &document)
        #expect(document.parts.first(where: { $0.id == partID })?.textContent == "")
    }

    @Test("card creation, background assignment and reordering accept stable identities")
    func cardManagementByID() async {
        var (document, current, other, _) = fixture()
        let executor = HypeToolExecutor()
        let background = document.addBackground(name: "Other background")
        _ = await executor.execute(toolName: "set_card_background", arguments: ["card_name": other.uuidString, "background_name": background.id.uuidString], document: &document, currentCardId: current)
        #expect(document.cards.first(where: { $0.id == other })?.backgroundId == background.id)
        _ = await executor.execute(toolName: "reorder_card", arguments: ["card_name": other.uuidString, "new_position": "1"], document: &document, currentCardId: current)
        #expect(document.sortedCards[0].id == other)
        let result = await executor.execute(toolName: "create_card", arguments: ["name": "New exact background", "background_name": background.id.uuidString], document: &document, currentCardId: current)
        #expect(result.hasPrefix("CREATED_CARD:"))
        #expect(document.cards.first(where: { $0.name == "New exact background" })?.backgroundId == background.id)
        #expect(document.backgrounds.count == 2)
    }

    @Test("off-card scene nodes with duplicate names can be edited by exact IDs")
    func sceneNodeIdentity() async {
        var (document, current, other, _) = fixture()
        var area = Part(partType: .spriteArea, cardId: other, name: "Arena", left: 0, top: 0, width: 300, height: 200)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 300, height: 200)))
        let first = HypeNodeSpec(name: "player", nodeType: .sprite)
        let second = HypeNodeSpec(name: "player", nodeType: .sprite)
        area.updateActiveSceneSpec { $0.nodes = [first, second] }
        document.addPart(area)
        _ = await HypeToolExecutor().execute(toolName: "set_node_property", arguments: ["sprite_area_name": area.id.uuidString, "node_name": second.id.uuidString, "property": "alpha", "value": "0.25"], document: &document, currentCardId: current)
        let scene = document.parts.first(where: { $0.id == area.id })?.activeSceneSpec
        #expect(scene?.node(id: first.id)?.alpha == first.alpha)
        #expect(scene?.node(id: second.id)?.alpha == 0.25)
    }

    @Test("assets can be inspected by identity without exposing their binary data")
    func assetIdentity() async {
        var (document, current, _, _) = fixture()
        let asset = Asset(name: "Test asset", kind: .imageTexture, mimeType: "image/png", data: Data("private-binary-payload".utf8))
        document.assetRepository.assets.append(asset)
        let result = await HypeToolExecutor().execute(toolName: "get_repository_asset", arguments: ["name": asset.id.uuidString], document: &document, currentCardId: current)
        #expect(result.contains("Test asset"))
        #expect(result.contains("id=\(asset.id.uuidString)"))
        #expect(result.contains("byteCount=22"))
        #expect(!result.contains("private-binary-payload"))
    }
}

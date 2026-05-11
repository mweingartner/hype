import Foundation
import Testing
@testable import HypeCore

@Suite("HypeToolExecutor — AI Context Library tools")
struct AIContextToolExecutorTests {
    private let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    @Test("list/search/read AI context tools expose bounded context")
    func listSearchReadContext() async throws {
        var document = HypeDocument.newDocument(name: "Context Stack")
        let result = AIContextIngestor.makeTextNote(
            title: "Quest Rules",
            text: "Every card should use a forest theme and include a score field.",
            role: .rules
        )
        document.aiContextLibrary.addSource(result.0, items: result.1)
        let itemId = try #require(document.aiContextLibrary.items.first?.id)
        let executor = HypeToolExecutor()
        let cardId = document.sortedCards[0].id

        let listed = await executor.execute(
            toolName: "list_ai_context",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(listed.contains("Quest Rules"))

        let searched = await executor.execute(
            toolName: "search_ai_context",
            arguments: ["query": "forest score"],
            document: &document,
            currentCardId: cardId
        )
        #expect(searched.contains(itemId.uuidString))
        #expect(searched.contains("forest"))

        let read = await executor.execute(
            toolName: "read_ai_context_item",
            arguments: ["item_id": itemId.uuidString, "max_chars": "4000"],
            document: &document,
            currentCardId: cardId
        )
        #expect(read.contains("Every card should use a forest theme"))
    }

    @Test("import_context_asset copies attached image into sprite repository")
    func importContextAssetCopiesImage() async throws {
        var document = HypeDocument.newDocument(name: "Asset Stack")
        let sourceId = UUID()
        let item = AIContextItem(
            sourceId: sourceId,
            name: "blue_ball",
            relativePath: "sprites/blue_ball.png",
            mimeType: "image/png",
            role: .asset,
            textSummary: "Blue ball sprite.",
            data: onePixelPNG,
            thumbnailData: onePixelPNG,
            width: 1,
            height: 1,
            byteCount: onePixelPNG.count,
            hash: "test"
        )
        document.aiContextLibrary.addSource(
            AIContextSource(id: sourceId, name: "sprites", kind: .directory),
            items: [item]
        )

        let executor = HypeToolExecutor()
        let output = await executor.execute(
            toolName: "import_context_asset",
            arguments: ["item_id": item.id.uuidString, "asset_name": "blue_ball"],
            document: &document,
            currentCardId: document.sortedCards[0].id
        )

        let asset = try #require(document.spriteRepository.asset(byName: "blue_ball"))
        #expect(output.contains("Imported AI context asset"))
        #expect(asset.data == onePixelPNG)
        #expect(asset.tags.contains("ai-context"))
        #expect(asset.provenance?.origin == .aiContext)
        #expect(asset.provenance?.license.name == "User supplied")
    }

    @Test("write_ai_context_note stores durable project memory in the current stack")
    func writeContextNoteStoresProjectMemory() async throws {
        var document = HypeDocument.newDocument(name: "Memory Stack")
        let executor = HypeToolExecutor()
        let cardId = document.sortedCards[0].id
        let output = await executor.execute(
            toolName: "write_ai_context_note",
            arguments: [
                "title": "Current RPG Build State",
                "text": "Card 1 uses RPG UI. Next session should wire doCamp and inventory display.",
            ],
            document: &document,
            currentCardId: cardId
        )

        let item = try #require(document.aiContextLibrary.items.first)
        #expect(output.contains("Wrote AI context note"))
        #expect(item.role == .projectMemory)
        #expect(item.name == "Current RPG Build State")
        #expect(item.textSummary.contains("Card 1 uses RPG UI"))
        #expect(document.aiContextLibrary.search(query: "doCamp inventory", role: .projectMemory).count == 1)
    }

    @Test("stack property tools read context count/summary and set cloud sharing gate")
    func stackPropertiesExposeContextGate() async {
        var document = HypeDocument.newDocument(name: "Context Stack")
        let result = AIContextIngestor.makeTextNote(title: "Rules", text: "Use only controls.", role: .rules)
        document.aiContextLibrary.addSource(result.0, items: result.1)
        let executor = HypeToolExecutor()
        let cardId = document.sortedCards[0].id

        let count = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "aiContextCount"],
            document: &document,
            currentCardId: cardId
        )
        #expect(count == "1")

        let summary = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "aiContextSummary"],
            document: &document,
            currentCardId: cardId
        )
        #expect(summary.contains("Rules"))

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "aiContextCloudSharingAllowed", "value": "true"],
            document: &document,
            currentCardId: cardId
        )
        #expect(document.stack.aiContextCloudSharingAllowed)
    }

    @Test("AI context tool schemas are opt-in appended to existing surfaces")
    func toolSchemaGateAppendsContextTools() {
        let disabled = HypeToolDefinitions.withAIContextTools(HypeToolDefinitions.spriteRepositoryAuthoringTools, enabled: false)
        #expect(!disabled.contains { $0.function.name == "import_context_asset" })
        #expect(disabled.contains { $0.function.name == "write_ai_context_note" })

        let enabled = HypeToolDefinitions.withAIContextTools(HypeToolDefinitions.spriteRepositoryAuthoringTools, enabled: true)
        #expect(enabled.contains { $0.function.name == "list_ai_context" })
        #expect(enabled.contains { $0.function.name == "import_context_asset" })
        #expect(enabled.contains { $0.function.name == "write_ai_context_note" })
    }
}

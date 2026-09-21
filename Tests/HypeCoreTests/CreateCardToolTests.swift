import Foundation
import Testing
@testable import HypeCore

/// The authoring prompt tells every model "When creating a card, ALWAYS pass
/// `name=`". The tool has to advertise that argument and the executor has to
/// honour it, or AI-created cards silently stay unnamed.
@Suite("create_card tool")
struct CreateCardToolTests {
    private func createCard(_ arguments: [String: String]) async -> (HypeDocument, String) {
        var document = HypeDocument.newDocument()
        let result = await HypeToolExecutor().execute(
            toolName: "create_card", arguments: arguments,
            document: &document, currentCardId: document.sortedCards[0].id)
        return (document, result)
    }

    @Test("the schema advertises an optional `name`")
    func schemaHasName() throws {
        let tool = try #require(HypeToolDefinitions.allTools.first { $0.function.name == "create_card" })
        #expect(tool.function.parameters.properties["name"] != nil)
        #expect(!tool.function.parameters.required.contains("name"))
    }

    @Test("`name` names the new card")
    func nameIsApplied() async throws {
        let (document, result) = await createCard(["name": "  about "])
        let id = try #require(UUID(uuidString: String(result.dropFirst("CREATED_CARD:".count))))
        #expect(document.cards.first { $0.id == id }?.name == "about")
    }

    @Test("without a name — or with a blank one — the card is created unnamed, as before")
    func nameIsOptional() async throws {
        for arguments in [[:], ["name": "   "]] as [[String: String]] {
            let (document, result) = await createCard(arguments)
            let id = try #require(UUID(uuidString: String(result.dropFirst("CREATED_CARD:".count))))
            #expect(document.cards.count == 2)
            #expect(document.cards.first { $0.id == id }?.name == "")
        }
    }

    @Test("a very long name is stored in full, not truncated")
    func veryLongNameIsPreserved() async throws {
        let longName = String(repeating: "a", count: 5000)
        let (document, result) = await createCard(["name": longName])
        let id = try #require(UUID(uuidString: String(result.dropFirst("CREATED_CARD:".count))))
        let stored = document.cards.first { $0.id == id }?.name
        #expect(stored?.count == 5000)
        #expect(stored == longName)
    }

    @Test("only leading/trailing whitespace and newlines are trimmed; embedded newlines survive")
    func embeddedNewlinesSurviveTrimming() async throws {
        let (document, result) = await createCard(["name": "\n\n  intro\nscreen  \n"])
        let id = try #require(UUID(uuidString: String(result.dropFirst("CREATED_CARD:".count))))
        #expect(document.cards.first { $0.id == id }?.name == "intro\nscreen")
    }

    @Test("naming a new card the same as an existing card is allowed, but makes the older card the only one go_to_card's name match can reach")
    func duplicateNameIsAllowedButAmbiguousToNavigate() async throws {
        var document = HypeDocument.newDocument()
        let firstCardId = document.sortedCards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_card_name", arguments: ["card_name": document.cards[0].name, "new_name": "intro"],
            document: &document, currentCardId: firstCardId)
        #expect(document.cards.first { $0.id == firstCardId }?.name == "intro")

        let createResult = await executor.execute(
            toolName: "create_card", arguments: ["name": "intro"],
            document: &document, currentCardId: firstCardId)
        let secondCardId = try #require(UUID(uuidString: String(createResult.dropFirst("CREATED_CARD:".count))))
        #expect(secondCardId != firstCardId)
        #expect(document.cards.filter { $0.name == "intro" }.count == 2)

        // go_to_card itself is name-agnostic: it just echoes the destination string
        // for the caller to resolve.
        let navigateResult = await executor.execute(
            toolName: "go_to_card", arguments: ["destination": "intro"],
            document: &document, currentCardId: secondCardId)
        #expect(navigateResult == "NAVIGATE:intro")

        // The real caller (AIChatPanel / the in-process tournament harness) both
        // resolve the destination the same way: a case-insensitive FIRST match.
        let dest = String(navigateResult.dropFirst("NAVIGATE:".count))
        let resolved = document.cards.first { $0.name.lowercased() == dest.lowercased() }
        #expect(resolved?.id == firstCardId, "navigation always lands on the first same-named card, never the one just created")
    }

    @Test("`name` and `background_name` are both honored from a single call")
    func nameAndBackgroundNameTogether() async throws {
        var document = HypeDocument.newDocument()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_background", arguments: ["name": "title_bg"],
            document: &document, currentCardId: document.sortedCards[0].id)

        let result = await executor.execute(
            toolName: "create_card", arguments: ["name": "title", "background_name": "title_bg"],
            document: &document, currentCardId: document.sortedCards[0].id)
        let id = try #require(UUID(uuidString: String(result.dropFirst("CREATED_CARD:".count))))
        let card = try #require(document.cards.first { $0.id == id })
        #expect(card.name == "title")
        let background = try #require(document.backgrounds.first { $0.id == card.backgroundId })
        #expect(background.name == "title_bg")
    }

    @Test("go_to_card, resolved the way the real caller resolves it, reaches a freshly created named card (case-insensitively)")
    func goToCardFindsTheNewlyNamedCard() async throws {
        var document = HypeDocument.newDocument()
        let executor = HypeToolExecutor()
        let createResult = await executor.execute(
            toolName: "create_card", arguments: ["name": "about"],
            document: &document, currentCardId: document.sortedCards[0].id)
        let newId = try #require(UUID(uuidString: String(createResult.dropFirst("CREATED_CARD:".count))))

        let navigateResult = await executor.execute(
            toolName: "go_to_card", arguments: ["destination": "About"],
            document: &document, currentCardId: newId)
        #expect(navigateResult == "NAVIGATE:About")
        let dest = String(navigateResult.dropFirst("NAVIGATE:".count))
        let resolved = document.cards.first { $0.name.lowercased() == dest.lowercased() }
        #expect(resolved?.id == newId)
    }
}

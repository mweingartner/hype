import Foundation
import Testing
@testable import HypeCore

@Suite("Current card selection resolver")
struct CurrentCardSelectionResolverTests {
    @Test("keeps preferred card when it still belongs to the document")
    func keepsValidPreferredCard() throws {
        let document = HypeDocument.newDocument(name: "Cards")
        let card = try #require(document.sortedCards.first)

        let resolved = CurrentCardSelectionResolver.resolvedCardId(preferred: card.id, in: document)

        #expect(resolved == card.id)
        #expect(CurrentCardSelectionResolver.containsRenderableCard(card.id, in: document))
    }

    @Test("falls back when preferred card came from another document")
    func fallsBackFromStalePreferredCard() throws {
        let document = HypeDocument.newDocument(name: "Cards")
        let card = try #require(document.sortedCards.first)

        let resolved = CurrentCardSelectionResolver.resolvedCardId(preferred: UUID(), in: document)

        #expect(resolved == card.id)
    }

    @Test("skips cards whose background no longer exists")
    func skipsCardsWithMissingBackground() throws {
        var document = HypeDocument.newDocument(name: "Cards")
        let validBackground = try #require(document.backgrounds.first)
        let orphan = Card(stackId: document.stack.id, backgroundId: UUID(), name: "Orphan", sortKey: "a000000")
        let valid = Card(stackId: document.stack.id, backgroundId: validBackground.id, name: "Valid", sortKey: "a000001")
        document.cards = [orphan, valid]

        let resolved = CurrentCardSelectionResolver.resolvedCardId(preferred: orphan.id, in: document)

        #expect(resolved == valid.id)
        #expect(!CurrentCardSelectionResolver.containsRenderableCard(orphan.id, in: document))
    }
}

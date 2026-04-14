import Testing
import Foundation
@testable import HypeCore

/// Regression tests for the workflow around creating and using
/// backgrounds.
///
/// Background: a user reported that "creating a second background
/// within a single stack didn't seem to create an actual second
/// background". After investigation we found that the model layer
/// (`HypeDocument.addBackground`) was actually working correctly —
/// the bug was in the UX:
///
///   1. The menu item silently called `addBackground` with a
///      generated name and provided NO visual feedback.
///   2. No card was bound to the new background, so the canvas
///      didn't change.
///   3. The inspector had no UI showing the list of backgrounds,
///      so the user couldn't see the new one or assign a card to
///      it.
///
/// The user-facing fix lives in `MainContentView.addNewBackgroundFlow`
/// + `PropertyInspector.backgroundsPicker`. The tests below pin
/// the model invariants the fixed UX depends on:
///
///   - addBackground actually grows the backgrounds array
///   - cards-on-background bookkeeping is correct
///   - re-binding a card's backgroundId to a new background
///     transfers it (since the picker writes through this path)
@Suite("Background creation and assignment", .serialized)
struct BackgroundUsageTests {

    @Test("addBackground grows the backgrounds array")
    func addBackgroundGrowsArray() {
        var doc = HypeDocument.newDocument(name: "Test")
        let initialCount = doc.backgrounds.count
        let bg = doc.addBackground(name: "Customer")
        #expect(doc.backgrounds.count == initialCount + 1)
        #expect(doc.backgrounds.contains(where: { $0.id == bg.id }))
        #expect(bg.name == "Customer")
    }

    @Test("creating multiple distinct backgrounds yields distinct IDs and names")
    func multipleBackgroundsDistinct() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg1 = doc.addBackground(name: "First")
        let bg2 = doc.addBackground(name: "Second")
        let bg3 = doc.addBackground(name: "Third")
        #expect(bg1.id != bg2.id)
        #expect(bg2.id != bg3.id)
        #expect(bg1.id != bg3.id)
        #expect(doc.backgrounds.count == 4) // includes default Background 1
    }

    @Test("a fresh background starts with zero cards")
    func freshBackgroundHasNoCards() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg = doc.addBackground(name: "Empty")
        #expect(doc.cardsForBackground(bg.id).count == 0)
    }

    @Test("addCard with backgroundId binds the card to that background")
    func addCardWithBackgroundId() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg = doc.addBackground(name: "New")
        let card = doc.addCard(backgroundId: bg.id)
        #expect(card.backgroundId == bg.id)
        #expect(doc.cardsForBackground(bg.id).count == 1)
    }

    @Test("re-assigning a card's backgroundId transfers it to the new background")
    func reassignCardBackground() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg1 = doc.backgrounds[0]
        let bg2 = doc.addBackground(name: "Other")
        let cardId = doc.cards[0].id
        // Default card is on bg1
        #expect(doc.cards[0].backgroundId == bg1.id)
        #expect(doc.cardsForBackground(bg1.id).count == 1)
        #expect(doc.cardsForBackground(bg2.id).count == 0)
        // Move it to bg2 — this is exactly what the inspector
        // picker does via `bindCardBackground`.
        doc.cards[0].backgroundId = bg2.id
        #expect(doc.cardsForBackground(bg1.id).count == 0)
        #expect(doc.cardsForBackground(bg2.id).count == 1)
    }

    @Test("the New Background flow result: bg + new card on it + card count grows")
    func newBackgroundFlowEndToEnd() {
        // Simulates the SEQUENCE the addNewBackgroundFlow runs:
        //   1. addBackground
        //   2. addCard with the new background's id, after the
        //      current card
        // After the flow, the new background must exist, contain
        // exactly one card, and the total card count must have
        // grown by 1.
        var doc = HypeDocument.newDocument(name: "Test")
        let initialBgCount = doc.backgrounds.count
        let initialCardCount = doc.cards.count
        let currentCardId = doc.cards[0].id

        let bg = doc.addBackground(name: "Detail Page")
        let currentIndex = doc.sortedCards.firstIndex { $0.id == currentCardId }
        let newCard = doc.addCard(afterIndex: currentIndex, backgroundId: bg.id)

        #expect(doc.backgrounds.count == initialBgCount + 1)
        #expect(doc.cards.count == initialCardCount + 1)
        #expect(newCard.backgroundId == bg.id)
        #expect(doc.cardsForBackground(bg.id).count == 1)
        #expect(doc.cardsForBackground(bg.id).first?.id == newCard.id)
    }

    @Test("backgrounds with duplicate names get a numeric suffix instead of colliding")
    func duplicateNamesGetSuffix() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg1 = doc.addBackground(name: "Duplicate")
        let bg2 = doc.addBackground(name: "Duplicate")
        let bg3 = doc.addBackground(name: "Duplicate")
        #expect(bg1.name == "Duplicate")
        #expect(bg2.name == "Duplicate 2")
        #expect(bg3.name == "Duplicate 3")
        #expect(bg1.id != bg2.id)
        #expect(bg2.id != bg3.id)
    }

    @Test("backgrounds survive a Codable round-trip with their cards")
    func backgroundsRoundTripWithCards() throws {
        var doc = HypeDocument.newDocument(name: "RoundTrip")
        let bg2 = doc.addBackground(name: "Second")
        let _ = doc.addCard(backgroundId: bg2.id)
        let _ = doc.addCard(backgroundId: bg2.id)
        let bg3 = doc.addBackground(name: "Third")
        let _ = doc.addCard(backgroundId: bg3.id)

        let encoded = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: encoded)

        #expect(decoded.backgrounds.count == doc.backgrounds.count)
        // bg2 and bg3 should still have the right number of cards
        #expect(decoded.cardsForBackground(bg2.id).count == 2)
        #expect(decoded.cardsForBackground(bg3.id).count == 1)
    }

    // MARK: - removeBackground Tests

    @Test("removeBackground refuses to delete the last background")
    func removeBackgroundRefusesLastBackground() {
        var doc = HypeDocument.newDocument(name: "Test")
        #expect(doc.backgrounds.count == 1)
        let removed = doc.removeBackground(id: doc.backgrounds[0].id)
        #expect(removed == false)
        #expect(doc.backgrounds.count == 1)
    }

    @Test("removeBackground reassigns orphaned cards to the default")
    func removeBackgroundReassignsOrphanedCards() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg2 = doc.addBackground(name: "Second")
        let card = doc.addCard(backgroundId: bg2.id)
        let bg3 = doc.addBackground(name: "Third")
        doc.defaultBackgroundId = bg3.id
        let removed = doc.removeBackground(id: bg2.id)
        #expect(removed == true)
        // The card should have been reassigned to bg3 (the default)
        let updatedCard = doc.cards.first(where: { $0.id == card.id })
        #expect(updatedCard?.backgroundId == bg3.id)
    }

    @Test("removeBackground removes background-owned parts")
    func removeBackgroundRemovesBgParts() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg2 = doc.addBackground(name: "Second")
        // Add a background-level part (cardId == nil)
        var bgPart = Part(partType: .field, backgroundId: bg2.id, name: "BG Field")
        bgPart.cardId = nil
        doc.addPart(bgPart)
        #expect(doc.parts.contains(where: { $0.id == bgPart.id }))
        let removed = doc.removeBackground(id: bg2.id)
        #expect(removed == true)
        #expect(!doc.parts.contains(where: { $0.id == bgPart.id }))
    }

    @Test("removeBackground promotes first when default is deleted")
    func removeBackgroundPromotesFirstWhenDefaultDeleted() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg1 = doc.backgrounds[0]
        let bg2 = doc.addBackground(name: "Second")
        doc.defaultBackgroundId = bg2.id
        let removed = doc.removeBackground(id: bg2.id)
        #expect(removed == true)
        #expect(doc.defaultBackgroundId == bg1.id)
    }

    // MARK: - resolvedDefaultBackgroundId Tests

    @Test("resolvedDefaultBackgroundId returns first background when defaultBackgroundId is nil")
    func resolvedDefaultBgIdNilFallback() {
        var doc = HypeDocument.newDocument(name: "Test")
        let firstBgId = doc.backgrounds[0].id
        doc.defaultBackgroundId = nil
        #expect(doc.resolvedDefaultBackgroundId == firstBgId)
    }

    @Test("resolvedDefaultBackgroundId returns first background when defaultBackgroundId points to deleted bg")
    func resolvedDefaultBgIdDeletedFallback() {
        var doc = HypeDocument.newDocument(name: "Test")
        let firstBgId = doc.backgrounds[0].id
        doc.defaultBackgroundId = UUID()  // random UUID not in backgrounds
        #expect(doc.resolvedDefaultBackgroundId == firstBgId)
    }

    // MARK: - addCard default background Tests

    @Test("addCard uses resolvedDefaultBackgroundId as fallback")
    func addCardUsesResolvedDefault() {
        var doc = HypeDocument.newDocument(name: "Test")
        let bg2 = doc.addBackground(name: "Second")
        doc.defaultBackgroundId = bg2.id
        let card = doc.addCard()
        #expect(card.backgroundId == bg2.id)
    }

    // MARK: - HypeTalk background scripting Tests

    @Test("HypeTalk set the background of card works")
    func hypeTalkSetBackgroundOfCard() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.cards[0].name = "Card 1"
        let _ = doc.addBackground(name: "Detail")

        // Put script on the card
        doc.cards[0].script = """
        on openCard
          set the background of card "Card 1" to "Detail"
        end openCard
        """

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed, "Script should not error: \(result.error?.message ?? "")")
        let updatedCard = result.modifiedDocument?.cards.first(where: { $0.id == cardId })
        let detailBg = result.modifiedDocument?.backgroundByName("Detail")
        #expect(updatedCard?.backgroundId == detailBg?.id, "Card should now be on the Detail background")
    }

    @Test("HypeTalk the background of card returns the name")
    func hypeTalkGetBackgroundOfCard() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.cards[0].name = "Card 1"
        // Name the default background
        doc.backgrounds[0].name = "Main"

        // Add a field to capture the result
        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        // Put script on the card
        doc.cards[0].script = """
        on openCard
          put the background of card "Card 1" into field "output"
        end openCard
        """

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed, "Script should not error: \(result.error?.message ?? "")")
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "Main", "Expected 'Main' but got '\(outputField?.textContent ?? "nil")'")
    }
}

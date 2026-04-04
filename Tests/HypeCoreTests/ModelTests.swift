import Testing
@testable import HypeCore

@Suite("HypeDocument Model Tests")
struct ModelTests {

    @Test func newDocumentHasDefaultCardAndBackground() {
        let doc = HypeDocument.newDocument(name: "Test")
        #expect(doc.stack.name == "Test")
        #expect(doc.backgrounds.count == 1)
        #expect(doc.cards.count == 1)
        #expect(doc.parts.isEmpty)
        #expect(doc.cards[0].backgroundId == doc.backgrounds[0].id)
    }

    @Test func sortedCardsReturnsByKey() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addCard()
        let _ = doc.addCard()
        #expect(doc.sortedCards.count == 3)
        for i in 1..<doc.sortedCards.count {
            #expect(doc.sortedCards[i-1].sortKey <= doc.sortedCards[i].sortKey)
        }
    }

    @Test func addPartAndRetrieve() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var part = Part(partType: .button, cardId: cardId)
        part.name = "MyButton"
        doc.addPart(part)

        let found = doc.partsForCard(cardId)
        #expect(found.count == 1)
        #expect(found[0].name == "MyButton")
    }

    @Test func removePartById() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let part = Part(partType: .field, cardId: cardId)
        doc.addPart(part)
        #expect(doc.parts.count == 1)
        doc.removePart(id: part.id)
        #expect(doc.parts.isEmpty)
    }

    @Test func updatePart() {
        var doc = HypeDocument.newDocument()
        let part = Part(partType: .button, cardId: doc.cards[0].id, name: "Original")
        doc.addPart(part)
        doc.updatePart(id: part.id) { $0.name = "Updated" }
        #expect(doc.parts[0].name == "Updated")
    }

    @Test func backgroundForCard() {
        let doc = HypeDocument.newDocument()
        let card = doc.cards[0]
        let bg = doc.backgroundForCard(card)
        #expect(bg != nil)
        #expect(bg?.id == card.backgroundId)
    }

    @Test func partsForBackground() {
        var doc = HypeDocument.newDocument()
        let bgId = doc.backgrounds[0].id
        let bgPart = Part(partType: .button, backgroundId: bgId)
        doc.addPart(bgPart)

        let cardPart = Part(partType: .field, cardId: doc.cards[0].id)
        doc.addPart(cardPart)

        let bgParts = doc.partsForBackground(bgId)
        #expect(bgParts.count == 1)
        #expect(bgParts[0].id == bgPart.id)
    }

    @Test func partDefaultValues() {
        let part = Part(partType: .button)
        #expect(part.visible == true)
        #expect(part.enabled == true)
        #expect(part.hilite == false)
        #expect(part.textFont == "SF Pro")
        #expect(part.textSize == 14)
        #expect(part.buttonStyle == .roundRect)
        #expect(part.fillColor == "#FFFFFF")
        #expect(part.strokeColor == "#000000")
    }
}

@Suite("CardNavigator Tests")
struct NavigatorTests {

    @Test func navigateFirst() {
        let doc = HypeDocument.newDocument()
        let result = CardNavigator.navigate(direction: .first, currentCardId: doc.cards[0].id, document: doc)
        #expect(result == doc.cards[0].id)
    }

    @Test func navigateLast() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addCard()
        let result = CardNavigator.navigate(direction: .last, currentCardId: doc.cards[0].id, document: doc)
        #expect(result == doc.sortedCards.last?.id)
    }

    @Test func navigateNextAtEnd() {
        let doc = HypeDocument.newDocument()
        let result = CardNavigator.navigate(direction: .next, currentCardId: doc.cards[0].id, document: doc)
        #expect(result == nil)
    }

    @Test func navigatePreviousAtStart() {
        let doc = HypeDocument.newDocument()
        let result = CardNavigator.navigate(direction: .previous, currentCardId: doc.cards[0].id, document: doc)
        #expect(result == nil)
    }

    @Test func cardPosition() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addCard()
        let _ = doc.addCard()
        let (index, count) = CardNavigator.cardPosition(currentCardId: doc.sortedCards[1].id, document: doc)
        #expect(index == 1)
        #expect(count == 3)
    }
}

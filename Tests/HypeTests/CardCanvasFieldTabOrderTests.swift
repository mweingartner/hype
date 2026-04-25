import Testing
import Foundation
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("CardCanvas field tab order")
struct CardCanvasFieldTabOrderTests {

    @Test("editable field tab order is top-to-bottom then left-to-right")
    func editableFieldTabOrderUsesVisualOrder() {
        var doc = HypeDocument.newDocument(name: "Tab Order")
        let cardId = doc.cards[0].id

        doc.addPart(Part(partType: .field, cardId: cardId, name: "last", left: 260, top: 120, width: 160, height: 28))
        doc.addPart(Part(partType: .field, cardId: cardId, name: "first", left: 40, top: 80, width: 160, height: 28))
        doc.addPart(Part(partType: .field, cardId: cardId, name: "middle", left: 40, top: 120, width: 160, height: 28))

        let orderedNames = CardCanvasNSView
            .editableFieldTabOrder(in: doc, currentCardId: cardId)
            .map(\.name)

        #expect(orderedNames == ["first", "middle", "last"])
    }

    @Test("tab order skips labels, hidden fields, disabled fields, and other cards")
    func editableFieldTabOrderSkipsNonEditableFields() {
        var doc = HypeDocument.newDocument(name: "Tab Order")
        let cardId = doc.cards[0].id
        let otherCardId = doc.addCard(afterIndex: 0, backgroundName: nil).id

        var label = Part(partType: .field, cardId: cardId, name: "label", left: 10, top: 10, width: 100, height: 20)
        label.lockText = true
        doc.addPart(label)

        var hidden = Part(partType: .field, cardId: cardId, name: "hidden", left: 10, top: 40, width: 100, height: 20)
        hidden.visible = false
        doc.addPart(hidden)

        var disabled = Part(partType: .field, cardId: cardId, name: "disabled", left: 10, top: 70, width: 100, height: 20)
        disabled.enabled = false
        doc.addPart(disabled)

        doc.addPart(Part(partType: .field, cardId: otherCardId, name: "other_card", left: 10, top: 100, width: 100, height: 20))
        doc.addPart(Part(partType: .field, cardId: cardId, name: "editable", left: 10, top: 130, width: 100, height: 20))

        let orderedNames = CardCanvasNSView
            .editableFieldTabOrder(in: doc, currentCardId: cardId)
            .map(\.name)

        #expect(orderedNames == ["editable"])
    }

    @Test("tab order includes editable background fields visible on the current card")
    func editableFieldTabOrderIncludesBackgroundFields() {
        var doc = HypeDocument.newDocument(name: "Tab Order")
        let cardId = doc.cards[0].id
        let backgroundId = doc.cards[0].backgroundId

        doc.addPart(Part(partType: .field, backgroundId: backgroundId, name: "shared", left: 10, top: 10, width: 100, height: 20))
        doc.addPart(Part(partType: .field, cardId: cardId, name: "card_field", left: 10, top: 40, width: 100, height: 20))

        let orderedNames = CardCanvasNSView
            .editableFieldTabOrder(in: doc, currentCardId: cardId)
            .map(\.name)

        #expect(orderedNames == ["shared", "card_field"])
    }
}

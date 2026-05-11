import AppKit
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("CardCanvas hover infrastructure")
struct CardCanvasHoverInfrastructureTests {

    @Test("tooltip descriptors register background parts before card parts")
    func tooltipDescriptorsPreserveRendererZOrder() {
        var doc = HypeDocument.newDocument(name: "Tooltip Order")
        let cardId = doc.cards[0].id
        let backgroundId = doc.cards[0].backgroundId

        var backgroundButton = Part(
            partType: .button,
            backgroundId: backgroundId,
            name: "background",
            left: 20,
            top: 20,
            width: 100,
            height: 40
        )
        backgroundButton.helpText = "Background help"

        var cardButton = Part(
            partType: .button,
            cardId: cardId,
            name: "card",
            left: 20,
            top: 20,
            width: 100,
            height: 40
        )
        cardButton.helpText = "Card help"

        doc.addPart(backgroundButton)
        doc.addPart(cardButton)

        let descriptors = CardCanvasNSView.toolTipDescriptors(
            in: doc,
            currentCardId: cardId,
            isBrowseMode: true
        )

        #expect(descriptors.map(\.partId) == [backgroundButton.id, cardButton.id])
    }

    @Test("tooltip descriptors skip non-hoverable parts and edit mode")
    func tooltipDescriptorsFilterInactiveParts() {
        var doc = HypeDocument.newDocument(name: "Tooltip Filtering")
        let cardId = doc.cards[0].id

        var visible = Part(partType: .button, cardId: cardId, name: "visible")
        visible.helpText = "Visible help"

        var emptyHelp = Part(partType: .button, cardId: cardId, name: "empty")
        emptyHelp.helpText = ""

        var hidden = Part(partType: .button, cardId: cardId, name: "hidden")
        hidden.visible = false
        hidden.helpText = "Hidden help"

        var zeroWidth = Part(partType: .button, cardId: cardId, name: "zero")
        zeroWidth.width = 0
        zeroWidth.helpText = "No rect"

        doc.addPart(visible)
        doc.addPart(emptyHelp)
        doc.addPart(hidden)
        doc.addPart(zeroWidth)

        let browseDescriptors = CardCanvasNSView.toolTipDescriptors(
            in: doc,
            currentCardId: cardId,
            isBrowseMode: true
        )
        let editDescriptors = CardCanvasNSView.toolTipDescriptors(
            in: doc,
            currentCardId: cardId,
            isBrowseMode: false
        )

        #expect(browseDescriptors.map(\.partId) == [visible.id])
        #expect(editDescriptors.isEmpty)
    }

    @Test("canvas tracking refresh preserves tracking areas owned by other systems")
    func trackingAreaRefreshPreservesForeignAreas() {
        let view = CardCanvasNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let owner = NSObject()
        let foreignArea = NSTrackingArea(
            rect: NSRect(x: 10, y: 10, width: 20, height: 20),
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: owner,
            userInfo: nil
        )

        view.addTrackingArea(foreignArea)
        view.updateTrackingAreas()

        withExtendedLifetime(owner) {
            #expect(view.trackingAreas.contains { $0 === foreignArea })
        }
    }
}

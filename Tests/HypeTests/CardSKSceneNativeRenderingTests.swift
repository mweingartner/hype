import AppKit
import SpriteKit
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("CardSKScene native rendering")
struct CardSKSceneNativeRenderingTests {
    @Test("nativeRenderablePartIds includes basic card/background parts")
    func nativeRenderablePartIdsIncludesBasicParts() {
        var doc = HypeDocument.newDocument(name: "Native")
        let cardId = doc.cards[0].id
        let backgroundId = doc.cards[0].backgroundId
        let cardShape = Part(partType: .shape, cardId: cardId, name: "Card Shape")
        let backgroundField = Part(partType: .field, backgroundId: backgroundId, name: "BG Field")
        let nonNativeMap = Part(partType: .map, cardId: cardId, name: "Map")
        doc.addPart(cardShape)
        doc.addPart(backgroundField)
        doc.addPart(nonNativeMap)

        let ids = CardSKScene.nativeRenderablePartIds(document: doc, cardId: cardId)

        #expect(ids.contains(cardShape.id))
        #expect(ids.contains(backgroundField.id))
        #expect(!ids.contains(nonNativeMap.id))
    }

    @Test("updateNativeContent reconciles nodes and paint layer")
    func updateNativeContentReconcilesNodes() {
        var doc = HypeDocument.newDocument(name: "Native")
        let cardId = doc.cards[0].id
        var button = Part(partType: .button, cardId: cardId, name: "Go", left: 10, top: 10, width: 80, height: 28)
        button.fillColor = "#FFFFFF"
        button.strokeColor = "#000000"
        let field = Part(partType: .field, cardId: cardId, name: "Name", left: 20, top: 50, width: 120, height: 32)
        let shape = Part(partType: .shape, cardId: cardId, name: "Box", left: 40, top: 100, width: 80, height: 60)
        var image = Part(partType: .image, cardId: cardId, name: "Icon", left: 130, top: 100, width: 32, height: 32)
        image.imageData = pngData(color: .systemBlue)
        doc.addPart(button)
        doc.addPart(field)
        doc.addPart(shape)
        doc.addPart(image)

        let paint = PaintLayer(width: 200, height: 150)
        paint.plot(x: 1, y: 1, color: .black)
        doc.setPaintLayer(paint.snapshot(cardId: cardId))

        let scene = CardSKScene(cardSize: CGSize(width: 200, height: 150))
        scene.updateNativeContent(document: doc, cardId: cardId)

        #expect(scene.nativePartNodeIds == Set([button.id, field.id, shape.id, image.id]))
        #expect(scene.nativeLayer.children.count >= 5)
        #expect(scene.hasPaintLayerNode)

        doc.removePart(id: field.id)
        doc.removePaintLayer(forCardId: cardId)
        scene.updateNativeContent(document: doc, cardId: cardId)

        #expect(!scene.nativePartNodeIds.contains(field.id))
        #expect(!scene.hasPaintLayerNode)
    }

    private func pngData(color: NSColor) -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()

        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }
}

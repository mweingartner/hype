import Testing
import Foundation
@testable import HypeCore

@Suite("WebPageController Tests")
struct WebPageControllerTests {
    @Test func validHTTPSUrl() {
        let url = WebPageController.validateURL("https://example.com")
        #expect(url != nil)
        #expect(url?.scheme == "https")
    }

    @Test func validHTTPUrl() {
        let url = WebPageController.validateURL("http://example.com")
        #expect(url != nil)
    }

    @Test func rejectsFileUrl() {
        #expect(WebPageController.validateURL("file:///etc/passwd") == nil)
    }

    @Test func rejectsJavascriptUrl() {
        #expect(WebPageController.validateURL("javascript:alert(1)") == nil)
    }

    @Test func rejectsLocalhost() {
        #expect(WebPageController.validateURL("https://localhost/api") == nil)
        #expect(WebPageController.validateURL("https://127.0.0.1/api") == nil)
    }

    @Test func rejectsPrivateIPs() {
        #expect(WebPageController.validateURL("https://10.0.0.1/api") == nil)
        #expect(WebPageController.validateURL("https://192.168.1.1/api") == nil)
        #expect(WebPageController.validateURL("https://172.16.0.1/api") == nil)
    }

    @Test func rejectsEmptyUrl() {
        #expect(WebPageController.validateURL("") == nil)
    }

    @Test func resolvesLinkedField() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var urlField = Part(partType: .field, cardId: cardId, name: "URL")
        urlField.textContent = "https://example.com"
        doc.addPart(urlField)

        var webPart = Part(partType: .webpage, cardId: cardId, name: "Web")
        webPart.urlSourceFieldId = urlField.id
        doc.addPart(webPart)

        let resolved = WebPageController.resolveURL(part: webPart, document: doc)
        #expect(resolved?.absoluteString == "https://example.com")
    }
}

@Suite("VisualEffect Tests")
struct VisualEffectTests {
    @Test func parseEffectName() {
        #expect(VisualEffect.fromName("dissolve") == .dissolve)
        #expect(VisualEffect.fromName("fade") == .fade)
        #expect(VisualEffect.fromName("cross fade") == .crossFade)
        #expect(VisualEffect.fromName("wipe left") == .wipeLeft)
        #expect(VisualEffect.fromName("wipe-right") == .wipeRight)
        #expect(VisualEffect.fromName("iris open") == .irisOpen)
        #expect(VisualEffect.fromName("iris_close") == .irisClose)
        #expect(VisualEffect.fromName("scroll up") == .scrollUp)
        #expect(VisualEffect.fromName("push down") == .pushDown)
        #expect(VisualEffect.fromName("move in right") == .moveInRight)
        #expect(VisualEffect.fromName("reveal left") == .revealLeft)
        #expect(VisualEffect.fromName("flip horizontal") == .flipHorizontal)
        #expect(VisualEffect.fromName("flipVertical") == .flipVertical)
        #expect(VisualEffect.fromName("cut") == .none)
        #expect(VisualEffect.fromName("unknown") == .none)
    }
}

@Suite("PaintLayer Tests")
struct PaintLayerTests {
    @Test func newLayerIsEmpty() {
        let layer = PaintLayer(width: 100, height: 100)
        #expect(layer.isEmpty)
    }

    @Test func plotMakesNonEmpty() {
        let layer = PaintLayer(width: 100, height: 100)
        layer.plot(x: 50, y: 50, color: .black)
        #expect(!layer.isEmpty)
    }

    @Test func clearRestoresEmpty() {
        let layer = PaintLayer(width: 100, height: 100)
        layer.plot(x: 50, y: 50, color: .black)
        layer.clear()
        #expect(layer.isEmpty)
    }

    @Test func drawCircleMakesNonEmpty() {
        let layer = PaintLayer(width: 100, height: 100)
        layer.drawCircle(cx: 50, cy: 50, radius: 5, color: .red)
        #expect(!layer.isEmpty)
    }

    @Test func drawThickLineMakesNonEmpty() {
        let layer = PaintLayer(width: 200, height: 200)
        layer.drawThickLine(x0: 10, y0: 10, x1: 190, y1: 190, radius: 3, color: .blue)
        #expect(!layer.isEmpty)
    }

    @Test func snapshotRoundTripsPaintData() {
        let cardId = UUID()
        let layer = PaintLayer(width: 20, height: 15)
        layer.plot(x: 5, y: 6, color: .black)

        let snapshot = layer.snapshot(cardId: cardId)
        let restored = PaintLayer(snapshot: snapshot)

        #expect(snapshot.cardId == cardId)
        #expect(snapshot.width == 20)
        #expect(snapshot.height == 15)
        #expect(!snapshot.isEmpty)
        #expect(restored.rawRGBAData == layer.rawRGBAData)
    }

    @Test func documentPersistsPaintLayerSnapshots() throws {
        var document = HypeDocument.newDocument(name: "Painted")
        let cardId = document.cards[0].id
        let layer = PaintLayer(width: 10, height: 10)
        layer.plot(x: 1, y: 1, color: .red)
        document.setPaintLayer(layer.snapshot(cardId: cardId))

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: data)

        #expect(decoded.paintLayer(forCardId: cardId) != nil)
        #expect(decoded.paintLayers.count == 1)
    }
}

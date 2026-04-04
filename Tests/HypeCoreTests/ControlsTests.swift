import Testing
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
        #expect(VisualEffect.fromName("wipe left") == .wipeLeft)
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
}

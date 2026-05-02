#if canImport(AppKit)
import Testing
import Foundation
import AppKit
@testable import HypeCore

/// Unit tests for `CardImageCapturer` — rendering, size capping, and error handling.
///
/// These tests run on macOS only (CardImageCapturer wraps AppKit).
/// Tests that produce actual pixel output decode the base64 back to an NSImage
/// and inspect `.size` to verify the dimensions are correct.
@Suite("CardImageCapturer — rendering, sizing, and error paths")
struct CardImageCapturerTests {

    // MARK: - Test helpers

    @MainActor
    private func makeDocWithCard(
        cardName: String = "Test Card",
        canvasWidth: Int = 800,
        canvasHeight: Int = 600
    ) -> (doc: HypeDocument, cardId: UUID) {
        var stack = Stack(name: "Test Stack", width: canvasWidth, height: canvasHeight)
        let bg = Background(stackId: stack.id, name: "Background 1")
        let card = Card(stackId: stack.id, backgroundId: bg.id, name: cardName)
        let button = Part(
            partType: .button,
            cardId: card.id,
            name: "OK",
            left: 100,
            top: 200,
            width: 120,
            height: 40
        )
        let field = Part(
            partType: .field,
            cardId: card.id,
            name: "Name",
            left: 100,
            top: 100,
            width: 200,
            height: 30
        )
        let doc = HypeDocument(
            stack: stack,
            backgrounds: [bg],
            cards: [card],
            parts: [button, field],
            defaultBackgroundId: bg.id
        )
        return (doc, card.id)
    }

    @MainActor
    private func decodedImage(from base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Basic capture

    @Test("capture returns base64 PNG and dimensions match canvas at default maxLongEdge")
    @MainActor
    func capture_defaultSize() throws {
        let (doc, cardId) = makeDocWithCard(canvasWidth: 800, canvasHeight: 600)
        let capturer = CardImageCapturer()
        let result = try capturer.capture(cardName: nil, document: doc, currentCardId: cardId)
        // Default maxLongEdge is 1024. Canvas is 800×600 (long edge 800 < 1024), so no scaling.
        #expect(result.pixelWidth == 800)
        #expect(result.pixelHeight == 600)
        #expect(!result.imageBase64.isEmpty)
        // Verify the base64 decodes to a valid image with the expected size.
        let img = decodedImage(from: result.imageBase64)
        #expect(img != nil)
        if let img {
            #expect(Int(img.size.width) == 800)
            #expect(Int(img.size.height) == 600)
        }
    }

    @Test("capture with empty cardName falls back to currentCardId")
    @MainActor
    func capture_emptyCardName_fallsBackToCurrentId() throws {
        let (doc, cardId) = makeDocWithCard(cardName: "Home")
        let capturer = CardImageCapturer()
        // Empty string should behave the same as nil — use currentCardId.
        let result = try capturer.capture(cardName: "", document: doc, currentCardId: cardId)
        #expect(result.cardId == cardId)
        #expect(!result.imageBase64.isEmpty)
    }

    @Test("capture with nil cardName falls back to currentCardId")
    @MainActor
    func capture_nilCardName_fallsBackToCurrentId() throws {
        let (doc, cardId) = makeDocWithCard(cardName: "Welcome")
        let capturer = CardImageCapturer()
        let result = try capturer.capture(cardName: nil, document: doc, currentCardId: cardId)
        #expect(result.cardId == cardId)
        #expect(result.cardName == "Welcome")
    }

    // MARK: - Named card lookup

    @Test("capture with valid cardName resolves to the named card")
    @MainActor
    func capture_namedCard_resolves() throws {
        var (doc, cardId) = makeDocWithCard(cardName: "Home")
        // Add a second card.
        let bg = doc.backgrounds[0]
        let secondCard = Card(stackId: doc.stack.id, backgroundId: bg.id, name: "About")
        doc.cards.append(secondCard)

        let capturer = CardImageCapturer()
        let result = try capturer.capture(cardName: "About", document: doc, currentCardId: cardId)
        #expect(result.cardId == secondCard.id)
        #expect(result.cardName == "About")
    }

    @Test("capture with non-existent cardName throws cardNotFound")
    @MainActor
    func capture_nonExistentCardName_throwsCardNotFound() throws {
        let (doc, cardId) = makeDocWithCard(cardName: "Home")
        let capturer = CardImageCapturer()
        #expect(throws: CardImageCapturer.CaptureError.cardNotFound(name: "NoSuchCard")) {
            try capturer.capture(cardName: "NoSuchCard", document: doc, currentCardId: cardId)
        }
    }

    @Test("capture with case-insensitive cardName matches correctly")
    @MainActor
    func capture_caseInsensitiveLookup() throws {
        let (doc, cardId) = makeDocWithCard(cardName: "Welcome Screen")
        let capturer = CardImageCapturer()
        // Should find "Welcome Screen" regardless of case.
        let result = try capturer.capture(cardName: "welcome screen", document: doc, currentCardId: cardId)
        #expect(result.cardId == cardId)
    }

    // MARK: - Size capping

    @Test("capture with maxLongEdge=512 produces image with long edge <= 512")
    @MainActor
    func capture_maxLongEdge512() throws {
        let (doc, cardId) = makeDocWithCard(canvasWidth: 1200, canvasHeight: 900)
        let capturer = CardImageCapturer()
        let result = try capturer.capture(cardName: nil, document: doc, currentCardId: cardId, maxLongEdge: 512)
        // Long edge should be 512 (1200 > 512, scale = 512/1200 ≈ 0.4267, height = 900*0.4267 ≈ 384)
        #expect(result.pixelWidth <= 512)
        #expect(result.pixelHeight <= 512)
        let maxEdge = max(result.pixelWidth, result.pixelHeight)
        #expect(maxEdge <= 512)
    }

    @Test("capture with maxLongEdge larger than canvas does not upscale")
    @MainActor
    func capture_largeMaxLongEdge_doesNotUpscale() throws {
        let (doc, cardId) = makeDocWithCard(canvasWidth: 400, canvasHeight: 300)
        let capturer = CardImageCapturer()
        let result = try capturer.capture(cardName: nil, document: doc, currentCardId: cardId, maxLongEdge: 2048)
        // Canvas is 400×300, max edge is 400. With maxLongEdge=2048, scale is min(1, 2048/400) = 1.
        #expect(result.pixelWidth == 400)
        #expect(result.pixelHeight == 300)
    }

    // MARK: - No cards

    @Test("capture on document with no cards throws noCardLoaded")
    @MainActor
    func capture_noCards_throwsNoCardLoaded() throws {
        let stack = Stack(name: "Empty", width: 800, height: 600)
        let doc = HypeDocument(
            stack: stack,
            backgrounds: [],
            cards: [],
            parts: [],
            defaultBackgroundId: nil
        )
        let capturer = CardImageCapturer()
        #expect(throws: CardImageCapturer.CaptureError.noCardLoaded) {
            try capturer.capture(cardName: nil, document: doc, currentCardId: UUID())
        }
    }

    // MARK: - base64 format

    @Test("capture returns base64 with no line breaks and no data URI prefix")
    @MainActor
    func capture_base64Format() throws {
        let (doc, cardId) = makeDocWithCard()
        let capturer = CardImageCapturer()
        let result = try capturer.capture(cardName: nil, document: doc, currentCardId: cardId)
        #expect(!result.imageBase64.contains("\n"))
        #expect(!result.imageBase64.contains("\r"))
        #expect(!result.imageBase64.hasPrefix("data:"))
    }
}
#endif

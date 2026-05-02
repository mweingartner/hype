#if canImport(AppKit)
import Testing
import Foundation
@testable import HypeCore

/// Integration tests for the `capture_card_image` tool path in `HypeToolExecutor`.
///
/// These tests verify the full dispatch from `execute(toolName:arguments:document:currentCardId:)`
/// down through `CardImageCapturer` and back. They run on macOS only because
/// `CardImageCapturer` wraps AppKit rendering.
///
/// No NSWorkspace is opened, no files are written to permanent disk locations —
/// all rendering stays in-memory (NSImage → PNG Data → base64 string).
@Suite("capture_card_image — executor integration")
struct CardCaptureExecutorIntegrationTests {

    // MARK: - Helpers

    /// Build a minimal valid document with one named card and return the doc + card UUID.
    private func makeDoc(cardName: String = "Home") -> (HypeDocument, UUID) {
        let doc = HypeDocument.newDocument(name: "Capture Test")
        // newDocument already creates one card. Use its ID.
        let cardId = doc.cards[0].id
        return (doc, cardId)
    }

    /// Build a document with no cards (stack only — degenerate case).
    private func makeEmptyDoc() -> (HypeDocument, UUID) {
        let stack = Stack(name: "Empty Stack", width: 800, height: 600)
        let doc = HypeDocument(
            stack: stack,
            backgrounds: [],
            cards: [],
            parts: [],
            defaultBackgroundId: nil
        )
        return (doc, UUID())
    }

    // MARK: - Success path

    @Test("capture_card_image returns a sentinel string starting with the capture prefix")
    func captureCardImage_returnsSentinel() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: [:],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.hasPrefix(CardCaptureResult.sentinelPrefix))
    }

    @Test("capture_card_image sentinel decodes to a CardCaptureResult")
    func captureCardImage_sentinelIsDecodeable() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: [:],
            document: &doc,
            currentCardId: cardId
        )
        let decoded = CardCaptureResult.decode(from: result)
        #expect(decoded != nil)
    }

    @Test("capture_card_image decoded imageBase64 is valid PNG data")
    func captureCardImage_imageBase64IsValidPNG() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: [:],
            document: &doc,
            currentCardId: cardId
        )
        guard let decoded = CardCaptureResult.decode(from: result) else {
            Issue.record("Expected decodeable sentinel, got: \(result)")
            return
        }
        guard let data = Data(base64Encoded: decoded.imageBase64) else {
            Issue.record("imageBase64 could not be base64-decoded")
            return
        }
        // PNG magic bytes: 0x89 50 4E 47 0D 0A 1A 0A
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let leading = Array(data.prefix(8))
        #expect(leading == pngMagic, "First 8 bytes should be PNG magic header")
    }

    // MARK: - Empty card_name defaults to currentCardId

    @Test("capture_card_image with empty card_name defaults to currentCardId")
    func captureCardImage_emptyCardName_usesCurrentCard() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: ["card_name": ""],
            document: &doc,
            currentCardId: cardId
        )
        guard let decoded = CardCaptureResult.decode(from: result) else {
            Issue.record("Expected decodeable sentinel, got: \(result)")
            return
        }
        #expect(decoded.cardId == cardId)
    }

    @Test("capture_card_image with whitespace-only card_name defaults to currentCardId")
    func captureCardImage_whitespaceCardName_usesCurrentCard() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: ["card_name": "   "],
            document: &doc,
            currentCardId: cardId
        )
        guard let decoded = CardCaptureResult.decode(from: result) else {
            Issue.record("Expected decodeable sentinel, got: \(result)")
            return
        }
        #expect(decoded.cardId == cardId)
    }

    // MARK: - card_name not found

    @Test("capture_card_image with non-existent card_name returns plain error (not a sentinel)")
    func captureCardImage_missingCardName_returnsPlainError() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: ["card_name": "doesnt-exist"],
            document: &doc,
            currentCardId: cardId
        )
        // Must NOT be a capture sentinel.
        #expect(!result.hasPrefix(CardCaptureResult.sentinelPrefix))
        // Must contain the card name and "not found".
        #expect(result.contains("doesnt-exist"))
        #expect(result.localizedCaseInsensitiveContains("not found"))
    }

    // MARK: - No cards in document

    @Test("capture_card_image on document with no cards returns plain error (not a sentinel)")
    func captureCardImage_noCards_returnsPlainError() async {
        var (doc, fallbackId) = makeEmptyDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: [:],
            document: &doc,
            currentCardId: fallbackId
        )
        #expect(!result.hasPrefix(CardCaptureResult.sentinelPrefix))
        // Should contain the "No card loaded" message from the executor.
        #expect(result.contains("No card loaded"))
    }

    // MARK: - __captures_remaining_hint propagation

    @Test("__captures_remaining_hint argument is stored in decoded result")
    func captureCardImage_remainingHint_isStored() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: ["__captures_remaining_hint": "3"],
            document: &doc,
            currentCardId: cardId
        )
        guard let decoded = CardCaptureResult.decode(from: result) else {
            Issue.record("Expected decodeable sentinel, got: \(result)")
            return
        }
        #expect(decoded.capturesRemainingHint == 3)
    }

    @Test("__captures_remaining_hint defaults to 0 when not provided")
    func captureCardImage_remainingHint_defaultsToZero() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: [:],
            document: &doc,
            currentCardId: cardId
        )
        guard let decoded = CardCaptureResult.decode(from: result) else {
            Issue.record("Expected decodeable sentinel, got: \(result)")
            return
        }
        #expect(decoded.capturesRemainingHint == 0)
    }

    // MARK: - purpose propagation

    @Test("purpose argument is stored in decoded result")
    func captureCardImage_purpose_isStored() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: ["purpose": "verify button layout"],
            document: &doc,
            currentCardId: cardId
        )
        guard let decoded = CardCaptureResult.decode(from: result) else {
            Issue.record("Expected decodeable sentinel, got: \(result)")
            return
        }
        #expect(decoded.purpose == "verify button layout")
    }

    // MARK: - Sentinel does not collide with draft-refusal sentinel

    @Test("capture sentinel does not decode as ScriptDraftRefusal")
    func captureSentinel_doesNotCollideWithDraftRefusal() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "capture_card_image",
            arguments: [:],
            document: &doc,
            currentCardId: cardId
        )
        // Must start with capture prefix, not draft-refused prefix.
        #expect(result.hasPrefix(CardCaptureResult.sentinelPrefix))
        #expect(!result.hasPrefix(ScriptDraftRefusal.sentinelPrefix))
        // ScriptDraftRefusal.decode must return nil for a capture sentinel.
        let refusal = ScriptDraftRefusal.decode(from: result)
        #expect(refusal == nil)
    }

    // MARK: - Document is not mutated by a capture

    @Test("capture_card_image does not mutate the document")
    func captureCardImage_doesNotMutateDocument() async {
        var (doc, cardId) = makeDoc()
        let cardCountBefore = doc.cards.count
        let partCountBefore = doc.parts.count
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "capture_card_image",
            arguments: [:],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.cards.count == cardCountBefore)
        #expect(doc.parts.count == partCountBefore)
    }
}
#endif

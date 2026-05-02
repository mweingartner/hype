import Testing
import Foundation
@testable import HypeCore

/// Unit tests for `CardCaptureResult` — sentinel encode/decode round-trip,
/// display summary safety, and large-payload fidelity.
@Suite("CardCaptureResult — sentinel encode/decode and display")
struct CardCaptureResultTests {

    // MARK: - Test helpers

    private func makeResult(
        cardId: UUID = UUID(),
        cardName: String = "Home",
        pixelWidth: Int = 1024,
        pixelHeight: Int = 768,
        imageBase64: String = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
        purpose: String = "verify layout",
        capturesRemainingHint: Int = 4
    ) -> CardCaptureResult {
        CardCaptureResult(
            cardId: cardId,
            cardName: cardName,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            imageBase64: imageBase64,
            purpose: purpose,
            capturesRemainingHint: capturesRemainingHint
        )
    }

    // MARK: - Sentinel round-trip

    @Test("encodedSentinel decodes back to an equal value via decode(from:)")
    func sentinelRoundTrip() {
        let original = makeResult()
        let sentinel = original.encodedSentinel()
        let decoded = CardCaptureResult.decode(from: sentinel)
        #expect(decoded != nil)
        if let decoded {
            #expect(decoded.cardId == original.cardId)
            #expect(decoded.cardName == original.cardName)
            #expect(decoded.pixelWidth == original.pixelWidth)
            #expect(decoded.pixelHeight == original.pixelHeight)
            #expect(decoded.imageBase64 == original.imageBase64)
            #expect(decoded.purpose == original.purpose)
            #expect(decoded.capturesRemainingHint == original.capturesRemainingHint)
        }
    }

    @Test("sentinel string starts with the expected prefix")
    func sentinelHasCorrectPrefix() {
        let result = makeResult()
        let sentinel = result.encodedSentinel()
        #expect(sentinel.hasPrefix(CardCaptureResult.sentinelPrefix))
    }

    // MARK: - Decode guard cases

    @Test("decode returns nil for strings missing the sentinel prefix")
    func decode_returnsNilForNonSentinel() {
        #expect(CardCaptureResult.decode(from: "Hello world") == nil)
        #expect(CardCaptureResult.decode(from: "") == nil)
        #expect(CardCaptureResult.decode(from: "CREATED_CARD:some-uuid") == nil)
        #expect(CardCaptureResult.decode(from: "__HYPE_INTERNAL_DRAFT_REFUSED_v1:{}") == nil)
    }

    @Test("decode returns nil for sentinel-prefixed strings with malformed JSON")
    func decode_returnsNilForBadJSON() {
        let badSentinel = CardCaptureResult.sentinelPrefix + "not-valid-json"
        #expect(CardCaptureResult.decode(from: badSentinel) == nil)
    }

    @Test("decode returns nil for sentinel-prefixed string with empty JSON object")
    func decode_returnsNilForEmptyJSONObject() {
        let badSentinel = CardCaptureResult.sentinelPrefix + "{}"
        // An empty JSON object will fail to decode because required fields are missing.
        #expect(CardCaptureResult.decode(from: badSentinel) == nil)
    }

    // MARK: - compactDisplaySummary safety

    @Test("compactDisplaySummary contains card name and size but never base64 chars")
    func compactDisplaySummary_neverContainsBase64() {
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let result = makeResult(cardName: "Welcome", pixelWidth: 800, pixelHeight: 600, imageBase64: b64)
        let summary = result.compactDisplaySummary
        #expect(summary.contains("Welcome"))
        #expect(summary.contains("800"))
        #expect(summary.contains("600"))
        #expect(!summary.contains(b64))
        // Spot-check no base64 fragment appears
        #expect(!summary.contains("iVBORw0KGgo"))
    }

    @Test("compactDisplaySummary uses generic description when cardName is empty")
    func compactDisplaySummary_emptyCardName() {
        let result = makeResult(cardName: "")
        let summary = result.compactDisplaySummary
        #expect(summary.contains("current card"))
    }

    // MARK: - Large payload fidelity

    @Test("decode handles a 4MB base64 payload without truncation")
    func decode_handlesLargeBase64Payload() {
        // Build a stub 4M-character base64 string (valid base64 characters).
        let chunkSize = 64
        let totalChars = 4_000_000
        let chunk = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", count: chunkSize / 64)
        var b64 = ""
        b64.reserveCapacity(totalChars)
        while b64.count < totalChars {
            b64.append(contentsOf: chunk)
        }
        b64 = String(b64.prefix(totalChars))

        let original = CardCaptureResult(
            cardId: UUID(),
            cardName: "BigCard",
            pixelWidth: 2048,
            pixelHeight: 1536,
            imageBase64: b64,
            purpose: "",
            capturesRemainingHint: 1
        )
        let sentinel = original.encodedSentinel()
        let decoded = CardCaptureResult.decode(from: sentinel)
        #expect(decoded != nil)
        if let decoded {
            #expect(decoded.imageBase64.count == totalChars)
            #expect(decoded.imageBase64 == b64)
        }
    }
}

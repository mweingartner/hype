import Testing
import Foundation
@testable import HypeCore

/// Unit tests for `CardCaptureCoordinator` — classification, message builders, and log redaction.
@Suite("CardCaptureCoordinator — classification and message building")
struct CardCaptureCoordinatorTests {

    // MARK: - Test helpers

    private func makeResult(
        cardName: String = "Home",
        pixelWidth: Int = 800,
        pixelHeight: Int = 600,
        imageBase64: String = "abc123XYZ",
        purpose: String = ""
    ) -> CardCaptureResult {
        CardCaptureResult(
            cardId: UUID(),
            cardName: cardName,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            imageBase64: imageBase64,
            purpose: purpose,
            capturesRemainingHint: 3
        )
    }

    @MainActor
    private func makeCoordinator() -> CardCaptureCoordinator {
        CardCaptureCoordinator()
    }

    // MARK: - classify

    @Test("classify returns .captured for valid sentinel")
    func classify_captured() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let result = makeResult()
        let sentinel = result.encodedSentinel()
        let outcome = coordinator.classify(toolResult: sentinel)
        if case .captured(let decoded) = outcome {
            #expect(decoded.cardName == "Home")
        } else {
            Issue.record("Expected .captured but got \(outcome)")
        }
    }

    @Test("classify returns .decodeFailed for sentinel with bad JSON")
    func classify_decodeFailed() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let badSentinel = CardCaptureResult.sentinelPrefix + "not-json"
        let outcome = coordinator.classify(toolResult: badSentinel)
        if case .decodeFailed(let raw) = outcome {
            #expect(raw == badSentinel)
        } else {
            Issue.record("Expected .decodeFailed but got \(outcome)")
        }
    }

    @Test("classify returns .notACapture for non-sentinel string")
    func classify_notACapture() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let outcome = coordinator.classify(toolResult: "Card 'X' not found")
        if case .notACapture = outcome {
            // Expected
        } else {
            Issue.record("Expected .notACapture but got \(outcome)")
        }
    }

    @Test("classify returns .notACapture for empty string")
    func classify_notACapture_empty() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let outcome = coordinator.classify(toolResult: "")
        if case .notACapture = outcome {
            // Expected
        } else {
            Issue.record("Expected .notACapture for empty string but got \(outcome)")
        }
    }

    // MARK: - makeSyntheticUserMessage

    @Test("makeSyntheticUserMessage uses role=user and includes base64 in images")
    func makeSyntheticUserMessage_roleAndImages() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let b64 = "testBase64ImageData"
        let result = makeResult(imageBase64: b64)
        let msg = coordinator.makeSyntheticUserMessage(for: result)
        #expect(msg.role == "user")
        #expect(msg.images?.contains(b64) == true)
        #expect(msg.images?.count == 1)
    }

    @Test("makeSyntheticUserMessage content reflects purpose hint when present")
    func makeSyntheticUserMessage_purposeInContent() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let result = makeResult(purpose: "verify button alignment")
        let msg = coordinator.makeSyntheticUserMessage(for: result)
        #expect(msg.content?.contains("verify button alignment") == true)
        #expect(msg.content?.contains("purpose:") == true)
    }

    @Test("makeSyntheticUserMessage content uses card name when purpose is empty")
    func makeSyntheticUserMessage_usesCardNameWhenNoPurpose() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let result = makeResult(cardName: "Welcome Screen", purpose: "")
        let msg = coordinator.makeSyntheticUserMessage(for: result)
        #expect(msg.content?.contains("Welcome Screen") == true)
    }

    @Test("makeSyntheticUserMessage content uses generic description when cardName is empty and no purpose")
    func makeSyntheticUserMessage_genericWhenEmpty() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let result = makeResult(cardName: "", purpose: "")
        let msg = coordinator.makeSyntheticUserMessage(for: result)
        #expect(msg.content?.contains("the current card") == true)
    }

    // MARK: - makeAcknowledgmentMessage

    @Test("makeAcknowledgmentMessage uses role=tool and includes dimensions and remaining count")
    func makeAcknowledgmentMessage_roleAndContent() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let result = makeResult(pixelWidth: 1024, pixelHeight: 768)
        let msg = coordinator.makeAcknowledgmentMessage(for: result, remaining: 3)
        #expect(msg.role == "tool")
        #expect(msg.content?.contains("1024") == true)
        #expect(msg.content?.contains("768") == true)
        #expect(msg.content?.contains("3") == true)
        // Must NOT include the base64 payload.
        #expect(msg.content?.contains("abc123XYZ") == false)
    }

    // MARK: - makeRedactedLogString (Security F1)

    @Test("makeRedactedLogString never contains the base64 payload")
    func makeRedactedLogString_neverContainsBase64() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
        let result = makeResult(imageBase64: b64)
        let logStr = coordinator.makeRedactedLogString(for: result)
        #expect(!logStr.contains(b64))
        #expect(logStr.contains("redacted"))
        #expect(logStr.contains("\(b64.count)"))
    }

    @Test("makeRedactedLogString contains dimensions")
    func makeRedactedLogString_containsDimensions() async {
        let coordinator = await MainActor.run { CardCaptureCoordinator() }
        let result = makeResult(pixelWidth: 512, pixelHeight: 384)
        let logStr = coordinator.makeRedactedLogString(for: result)
        #expect(logStr.contains("512"))
        #expect(logStr.contains("384"))
    }
}

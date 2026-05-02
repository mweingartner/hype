import Foundation

// MARK: - CardCaptureCoordinator

/// Coordinates the host-side capture flow for `capture_card_image` tool results.
///
/// When the executor processes a `capture_card_image` call, it returns a sentinel
/// string. The `AIChatPanel` delegates to this coordinator to:
/// 1. Classify the tool result as a capture, a decode failure, or not a capture.
/// 2. Build the acknowledgment message fed back to the model as a `tool` role message.
/// 3. Build the synthetic user message that injects the image into the conversation.
/// 4. Produce a log-safe redacted string for `HypeLogger.aiDialog` (never includes base64).
///
/// The coordinator is intentionally `nonisolated`-friendly — its pure methods can be
/// called from any context because they operate only on value types.
@MainActor
public final class CardCaptureCoordinator {

    // MARK: - Outcome types

    /// Classification of a single `capture_card_image` tool-result string.
    public enum CaptureOutcome: Sendable, Equatable {
        /// The result is a valid capture sentinel that decoded successfully.
        case captured(CardCaptureResult)

        /// The result starts with the sentinel prefix but the JSON could not be decoded.
        ///
        /// Callers MUST treat this as a hard error — log a warning, surface a generic
        /// error message, and do NOT inject an image into the conversation.
        case decodeFailed(rawString: String)

        /// The result is a plain string (not a capture sentinel).
        ///
        /// This happens when the executor returns an error message such as
        /// "Card 'X' not found" or "Capture encoding failed". Surface the string as-is.
        case notACapture
    }

    // MARK: - Initializer

    public init() {}

    // MARK: - Classification

    /// Classify a `capture_card_image` tool-result string.
    ///
    /// - Parameter toolResult: The raw string returned by `HypeToolExecutor.execute`.
    /// - Returns: A `CaptureOutcome` describing the result type.
    public nonisolated func classify(toolResult: String) -> CaptureOutcome {
        guard toolResult.hasPrefix(CardCaptureResult.sentinelPrefix) else {
            return .notACapture
        }
        guard let result = CardCaptureResult.decode(from: toolResult) else {
            return .decodeFailed(rawString: toolResult)
        }
        return .captured(result)
    }

    // MARK: - Message builders

    /// Build the `tool`-role acknowledgment message sent back to the model immediately
    /// after a successful capture, BEFORE the synthetic user message with the image.
    ///
    /// This message tells the model that the capture succeeded and how many captures
    /// remain, without carrying the image bytes (those come in the synthetic user message).
    ///
    /// - Parameters:
    ///   - result: The decoded capture result.
    ///   - remaining: Captures remaining in the session budget (post-consumption).
    public nonisolated func makeAcknowledgmentMessage(for result: CardCaptureResult, remaining: Int) -> OllamaMessage {
        let content = "Captured card image (\(result.pixelWidth)×\(result.pixelHeight)). Image attached as next user message. Captures remaining: \(remaining)."
        return OllamaMessage(role: "tool", content: content)
    }

    /// Build the synthetic `user`-role message that carries the captured image.
    ///
    /// This message is injected AFTER all tool result messages for the current assistant
    /// turn so the Ollama conversation ordering is:
    /// ```
    /// assistant (tool_calls) → tool → tool → … → user (images) → next assistant
    /// ```
    ///
    /// - Parameter result: The decoded capture result.
    public nonisolated func makeSyntheticUserMessage(for result: CardCaptureResult) -> OllamaMessage {
        let framing: String
        if !result.purpose.isEmpty {
            framing = "Here is the requested capture (purpose: \(result.purpose)). Analyze and continue."
        } else {
            let nameDesc = result.cardName.isEmpty ? "the current card" : "card '\(result.cardName)'"
            framing = "Here is the requested capture of \(nameDesc). Analyze and continue."
        }
        return OllamaMessage(role: "user", content: framing, images: [result.imageBase64])
    }

    /// Build a log-safe redacted string describing a capture result.
    ///
    /// This string is safe to pass to `HypeLogger.aiDialog` because it replaces the
    /// base64 payload with a character count. The actual image bytes must never appear
    /// in the log file.
    ///
    /// - Parameter result: The decoded capture result.
    public nonisolated func makeRedactedLogString(for result: CardCaptureResult) -> String {
        "[capture_card_image: \(result.pixelWidth)×\(result.pixelHeight), \(result.imageBase64.count) base64 chars redacted]"
    }
}

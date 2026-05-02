import Foundation

// MARK: - CardCaptureResult

/// A structured record of a successful card visual capture.
///
/// When the `capture_card_image` tool renders a card to a PNG, the executor
/// creates one of these and encodes it as a sentinel tool-result string so the
/// `AIChatPanel` can classify it, display a thumbnail, and inject the image
/// into the model conversation as a synthetic user message.
///
/// ## Sentinel contract
/// The tool result string takes the form:
/// ```
/// __HYPE_INTERNAL_CAPTURE_v1:<json>
/// ```
/// The prefix is intentionally verbose to minimise collision risk. The base64
/// image payload is embedded in the JSON and MUST be redacted before being
/// passed to `HypeLogger.aiDialog` — use `CardCaptureCoordinator.makeRedactedLogString(for:)`
/// for all logging paths.
///
/// ## Security note
/// `imageBase64` is the raw base64-encoded PNG data. It is included in the
/// sentinel JSON so the chat panel can inject it as a synthetic user message
/// with the `images` field of `OllamaMessage`. It must NEVER be passed to any
/// logging function directly. The `compactDisplaySummary` property is safe to
/// log — it never includes base64 content.
public struct CardCaptureResult: Codable, Sendable, Equatable {

    // MARK: - Constants

    /// Sentinel prefix used to identify capture results in the tool-result string.
    ///
    /// The `AIChatPanel` MUST check for this prefix before processing a tool result
    /// from `capture_card_image`. If a result starts with this prefix but fails
    /// JSON decode, the caller MUST treat it as a hard error — do NOT inject.
    public static let sentinelPrefix = "__HYPE_INTERNAL_CAPTURE_v1:"

    /// Maximum image size in bytes (4 MB). The capturer retries at a lower resolution
    /// before throwing `CardImageCapturer.CaptureError.imageTooLarge`.
    public static let maxImageBytes = 4_000_000

    // MARK: - Stored properties

    /// The UUID of the card that was captured.
    public let cardId: UUID

    /// The human-readable name of the card, or empty string if the card has no name.
    public let cardName: String

    /// Width of the captured image in pixels.
    public let pixelWidth: Int

    /// Height of the captured image in pixels.
    public let pixelHeight: Int

    /// Raw base64-encoded PNG data with no `data:` URI prefix and no line breaks.
    ///
    /// WARNING: Never pass this value to `HypeLogger.aiDialog` or any disk-persistent
    /// logging path. Use `CardCaptureCoordinator.makeRedactedLogString(for:)` instead.
    public let imageBase64: String

    /// Model-supplied free-text hint describing the reason for the capture.
    /// May be empty. Recorded in the chat log for user visibility.
    public let purpose: String

    /// A hint from the host indicating how many captures remain in the session budget,
    /// as of the time the executor ran. Injected by the chat panel before dispatch.
    public let capturesRemainingHint: Int

    // MARK: - Initializer

    public init(
        cardId: UUID,
        cardName: String,
        pixelWidth: Int,
        pixelHeight: Int,
        imageBase64: String,
        purpose: String,
        capturesRemainingHint: Int
    ) {
        self.cardId = cardId
        self.cardName = cardName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.imageBase64 = imageBase64
        self.purpose = purpose
        self.capturesRemainingHint = capturesRemainingHint
    }

    // MARK: - Sentinel encoding / decoding

    /// Encode this capture result as a tool-result sentinel string.
    ///
    /// The returned string is safe to store as an `OllamaMessage(role: "tool", ...)` content,
    /// but must be redacted before logging. Use `CardCaptureCoordinator.makeRedactedLogString(for:)`.
    public func encodedSentinel() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            // Fallback: emit a minimal sentinel that decode will recognise as failed.
            return Self.sentinelPrefix + "{}"
        }
        return Self.sentinelPrefix + json
    }

    /// Decode a capture result from a sentinel string.
    ///
    /// ## Contract for callers
    /// - Returns `nil` ONLY when:
    ///   a) The string does not start with `sentinelPrefix` (not a capture result), OR
    ///   b) The JSON after the prefix fails to decode.
    /// - When the string STARTS WITH `sentinelPrefix` but decode fails, this returns `nil`
    ///   and the CALLER MUST treat it as `.decodeFailed`.
    public static func decode(from sentinel: String) -> CardCaptureResult? {
        guard sentinel.hasPrefix(sentinelPrefix) else { return nil }
        let jsonPart = String(sentinel.dropFirst(sentinelPrefix.count))
        guard let data = jsonPart.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CardCaptureResult.self, from: data) else {
            return nil
        }
        return decoded
    }

    // MARK: - User-facing presentation

    /// One-line summary safe for display in the chat and for logging.
    ///
    /// Never includes the base64 image data — only card name and dimensions.
    public var compactDisplaySummary: String {
        let nameDesc = cardName.isEmpty ? "current card" : "card '\(cardName)'"
        return "Captured \(nameDesc) at \(pixelWidth)×\(pixelHeight)"
    }
}

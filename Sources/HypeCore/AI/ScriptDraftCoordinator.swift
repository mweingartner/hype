import Foundation

// MARK: - ScriptDraftCoordinator

/// Coordinates the host-side script validation iteration loop.
///
/// When the executor's storage gate refuses a draft (returning a sentinel string),
/// the `AIChatPanel` delegates to this coordinator to:
/// 1. Classify the tool result as passed/refused/error.
/// 2. Build structured retry envelopes for the model.
/// 3. Track attempt count and produce the abandoned-draft message when budget
///    is exhausted.
///
/// The coordinator is intentionally `nonisolated`-friendly — its pure methods
/// (classify, makeRetryEnvelope, makeAbandonedDraftMessage) can be called from
/// any context because they only operate on value types.
@MainActor
public final class ScriptDraftCoordinator {

    // MARK: - Configuration

    /// Tunable parameters for the iteration loop.
    public struct Configuration: Sendable {
        /// Maximum number of attempts (including the initial one that produced the refusal).
        public var maxAttempts: Int

        public init(maxAttempts: Int = 3) {
            self.maxAttempts = maxAttempts
        }
    }

    // MARK: - Outcome types

    /// Classification of a single tool-result string.
    public enum AttemptOutcome: Sendable {
        /// The tool succeeded and the document was mutated. The result string is the
        /// success message (e.g. "Set script of card 'Home'").
        case passed(committedResult: String)

        /// The host gate refused the draft. The refusal record contains failure details
        /// and can produce a retry envelope for the model.
        case refused(ScriptDraftRefusal)

        /// The result is a non-refusal, non-success string (e.g. "Part not found").
        /// The chat panel should surface this as-is and stop iterating.
        case other(String)

        /// The result starts with the sentinel prefix but the JSON could not be decoded.
        ///
        /// The caller MUST treat this as a hard error: log a warning, surface
        /// "Script rejected — internal error reading host gate response", and
        /// do NOT iterate further.
        case decodeFailed(rawString: String)
    }

    /// The result returned by the chat panel's iteration helper when the loop exits.
    public struct LoopResult: Sendable {
        /// Number of attempts actually made (including the one that produced `initialRefusal`).
        public let finalAttempts: Int
        /// True when a storage tool committed the script successfully.
        public let didPass: Bool
        /// The raw script from the final refused draft, if the loop ended with a refusal.
        public let lastDraftRawScript: String?
        /// The failures from the final refused draft, if any.
        public let lastFailures: [ValidationFailure]
        /// The string to surface to the user / append to conversationMessages.
        public let finalToolResultString: String

        public init(
            finalAttempts: Int,
            didPass: Bool,
            lastDraftRawScript: String?,
            lastFailures: [ValidationFailure],
            finalToolResultString: String
        ) {
            self.finalAttempts = finalAttempts
            self.didPass = didPass
            self.lastDraftRawScript = lastDraftRawScript
            self.lastFailures = lastFailures
            self.finalToolResultString = finalToolResultString
        }
    }

    // MARK: - Stored state

    public private(set) var configuration: Configuration

    // MARK: - Initializer

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    // MARK: - Pure classification

    /// Classify a tool-result string into one of the four outcome cases.
    ///
    /// This method is `nonisolated` because it only operates on value types
    /// and has no mutable state.
    ///
    /// - Note: All non-sentinel strings are classified as `.passed` or `.other`.
    ///   The convention in this executor is that every non-empty success result is
    ///   a human-readable string. There is no typed error type for executor failures —
    ///   they surface as informational strings. The coordinator therefore treats all
    ///   non-sentinel results as pass-through `.passed` (the chat panel will surface
    ///   them as-is). The distinction between "success" and "other error string" is
    ///   intentionally not made here — that's the chat panel's responsibility.
    public nonisolated func classify(toolResult: String) -> AttemptOutcome {
        guard toolResult.hasPrefix(ScriptDraftRefusal.sentinelPrefix) else {
            return .passed(committedResult: toolResult)
        }

        // Starts with the sentinel prefix — must be a refusal.
        if let refusal = ScriptDraftRefusal.decode(from: toolResult) {
            return .refused(refusal)
        }

        // Prefix present but decode failed — hard error per the sentinel contract.
        return .decodeFailed(rawString: toolResult)
    }

    // MARK: - Retry envelope builder

    /// Build an `OllamaMessage` to feed back to the model as the "tool" result
    /// for the refused call. This tells the model exactly what went wrong and
    /// asks it to call the same tool with a corrected script.
    ///
    /// - Parameters:
    ///   - refusal: The refusal from the previous attempt.
    ///   - attemptNumber: The attempt number that PRODUCED this refusal (1-based).
    ///   - maxAttempts: The total allowed attempts.
    public nonisolated func makeRetryEnvelope(
        for refusal: ScriptDraftRefusal,
        attemptNumber: Int,
        maxAttempts: Int
    ) -> OllamaMessage {
        let header = "DRAFT_REFUSED for \(refusal.toolName) on \(refusal.targetDescription) (attempt \(attemptNumber) of \(maxAttempts)).\n\n"
        let body = header + refusal.retryEnvelopeContent
        return OllamaMessage(role: "tool", content: body)
    }

    // MARK: - Abandoned-draft message

    /// Build the user-facing message shown when all retry attempts have been exhausted
    /// without the script passing validation.
    ///
    /// - Parameters:
    ///   - refusal: The last refusal record.
    ///   - maxAttempts: The total allowed attempts (used in the message).
    public nonisolated func makeAbandonedDraftMessage(
        _ refusal: ScriptDraftRefusal,
        maxAttempts: Int
    ) -> String {
        var lines: [String] = []

        lines.append("The AI tried \(maxAttempts) time\(maxAttempts == 1 ? "" : "s") to write a valid script for \(refusal.targetDescription) and never produced one that passed validation. The script was NOT saved.")
        lines.append("")
        lines.append("Last failures:")
        for failure in refusal.failures {
            lines.append("  - [\(failure.kind.rawValue)] \(failure.message)")
        }
        lines.append("")
        lines.append("Last attempted script:")
        lines.append("<<<DRAFT_\(refusal.fenceNonce)")
        lines.append(refusal.rawScript)
        lines.append("\(refusal.fenceNonce)_DRAFT>>>")
        lines.append("")
        lines.append("You can copy this draft to the Script Editor and fix it manually, or rephrase the request and try again.")

        return lines.joined(separator: "\n")
    }
}

import Foundation

// MARK: - ScriptDraftRefusal

/// A structured record of a host-side script gate refusal.
///
/// When the `HypeTalkScriptValidator` rejects an AI-authored draft, the executor
/// creates one of these and encodes it as a sentinel tool-result string so the
/// `AIChatPanel`'s iteration loop can classify it, surface a user-visible summary,
/// and feed a structured retry envelope back to the model.
///
/// ## Sentinel contract
/// The tool result string takes the form:
/// ```
/// __HYPE_INTERNAL_DRAFT_REFUSED_v1:<json>
/// ```
/// The prefix is intentionally verbose to minimise collision risk. A collision
/// would only occur if a tool's legitimate result string LITERALLY started with
/// this exact magic prefix — extremely unlikely and immediately visible in review.
///
/// This sentinel is one entry in the tool-result dispatch table alongside
/// `CREATED_CARD:<uuid>` and `NAVIGATE:<dest>`. Migrating those to a typed return
/// is out of scope; the sentinel idiom is the established pattern in this codebase.
///
/// ## Security notes (fence nonce — finding 2)
/// `fenceNonce` is a freshly generated `UUID().uuidString` produced AFTER the model's
/// draft was received. Because the nonce is generated here and not derived from the
/// script content, the script body cannot possibly contain the opening or closing
/// fence. This eliminates fence-injection as an attack vector.
///
/// ## Script size cap (finding 3)
/// Scripts larger than `scriptSizeCap` characters are truncated in `init`. The
/// truncation is logged once and a `ValidationFailure(.forbiddenPattern, ...)` is
/// appended to `failures` so the model knows it must regenerate a tighter version.
/// Decode does NOT reverse the truncation — the model sees the truncated form.
public struct ScriptDraftRefusal: Codable, Sendable, Equatable {

    // MARK: - Constants

    /// Sentinel prefix used to identify refusal results in the tool-result string.
    ///
    /// The `AIChatPanel` MUST check for this prefix before any other prefix match
    /// so the iteration loop fires. If a result starts with this prefix but fails
    /// JSON decode, the caller MUST treat it as a hard error (`.decodeFailed`) and
    /// surface an error message — it must NOT iterate.
    public static let sentinelPrefix = "__HYPE_INTERNAL_DRAFT_REFUSED_v1:"

    /// Maximum byte count for `rawScript` and `wrappedScript` stored inside a
    /// refusal. Drafts exceeding this are truncated to prevent oversized context
    /// blowup when the refusal is passed back to the model.
    public static let scriptSizeCap = 16_384

    // MARK: - Stored properties

    /// The name of the storage tool that was refused (e.g. `set_card_script`).
    public let toolName: String

    /// The original arguments passed to the storage tool (all values as strings).
    public let originalArguments: [String: String]

    /// Human-readable description of the target (e.g. "card 'Home'").
    public let targetDescription: String

    /// The raw script text as produced by the model (possibly truncated — see `scriptSizeCap`).
    public let rawScript: String

    /// The wrapped script text after `wrapScript()` auto-wrapping (possibly truncated).
    public let wrappedScript: String

    /// The ordered list of validation failures, priority-sorted (most actionable first).
    public let failures: [ValidationFailure]

    /// A fresh UUID string generated at refusal creation time.
    ///
    /// Used as the fence delimiter in `retryEnvelopeContent` to prevent the script body
    /// from breaking the fence. Since the nonce is generated AFTER the script was produced,
    /// the body cannot contain it.
    public let fenceNonce: String

    // MARK: - Initializer

    /// Create a refusal record.
    ///
    /// If `rawScript.count` or `wrappedScript.count` exceeds `scriptSizeCap`, both
    /// are truncated and a `forbiddenPattern` failure is prepended to `failures`.
    public init(
        toolName: String,
        originalArguments: [String: String],
        targetDescription: String,
        rawScript: String,
        wrappedScript: String,
        failures: [ValidationFailure]
    ) {
        self.toolName = toolName
        self.originalArguments = originalArguments
        self.targetDescription = targetDescription
        self.fenceNonce = UUID().uuidString

        var mutableFailures = failures
        var mutableRaw = rawScript
        var mutableWrapped = wrappedScript

        if rawScript.count > Self.scriptSizeCap {
            mutableRaw = String(rawScript.prefix(Self.scriptSizeCap))
                + "\n-- [truncated by host gate at \(Self.scriptSizeCap) chars]"
            mutableWrapped = String(wrappedScript.prefix(Self.scriptSizeCap))
                + "\n-- [truncated by host gate at \(Self.scriptSizeCap) chars]"
            mutableFailures.insert(
                ValidationFailure(
                    kind: .forbiddenPattern,
                    message: "Draft exceeded \(Self.scriptSizeCap) chars and was truncated; regenerate a tighter version.",
                    line: nil,
                    suggestion: "Keep scripts under \(Self.scriptSizeCap) characters."
                ),
                at: 0
            )
            HypeLogger.shared.warn(
                "Script draft for '\(targetDescription)' truncated from \(rawScript.count) chars to \(Self.scriptSizeCap)",
                source: "Script Gate"
            )
        }

        self.rawScript = mutableRaw
        self.wrappedScript = mutableWrapped
        self.failures = mutableFailures
    }

    // MARK: - Sentinel encoding / decoding

    /// Encode this refusal as a tool-result sentinel string.
    ///
    /// The returned string is safe to store as an `OllamaMessage(role: "tool", ...)` content.
    public func encodedSentinel() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            // Fallback: emit a minimal sentinel that decode will recognise as failed.
            return Self.sentinelPrefix + "{}"
        }
        return Self.sentinelPrefix + json
    }

    /// Decode a refusal from a sentinel string.
    ///
    /// ## Contract for callers
    /// - Returns `nil` ONLY when:
    ///   a) The string does not start with `sentinelPrefix` (not a refusal), OR
    ///   b) The JSON after the prefix fails to decode.
    /// - When the string STARTS WITH `sentinelPrefix` but decode fails, this returns `nil`
    ///   and the CALLER MUST treat this as `.decodeFailed` — do NOT iterate,
    ///   surface "Script rejected — internal error reading host gate response" to the user.
    /// - When the string does NOT start with `sentinelPrefix`, this returns `nil` because
    ///   the string is a normal (non-refusal) tool result.
    public static func decode(from sentinel: String) -> ScriptDraftRefusal? {
        guard sentinel.hasPrefix(sentinelPrefix) else { return nil }
        let jsonPart = String(sentinel.dropFirst(sentinelPrefix.count))
        guard let data = jsonPart.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ScriptDraftRefusal.self, from: data) else {
            return nil
        }
        return decoded
    }

    // MARK: - User-facing presentation

    /// One-line summary for display in the chat bubble.
    ///
    /// Never includes the raw script or the sentinel string — only the failure count
    /// and the first failure's message.
    public var compactDisplaySummary: String {
        let firstMsg = failures.first.map { $0.message } ?? "unknown issue"
        return "Refused: \(failures.count) issue\(failures.count == 1 ? "" : "s") — \(firstMsg)"
    }

    /// The formatted body of a model-facing retry envelope (without the attempt counter header).
    ///
    /// The coordinator wraps this with the attempt counter line when building the full
    /// retry envelope. This property owns the failure list and the fenced script block.
    public var retryEnvelopeContent: String {
        var lines: [String] = []

        lines.append("The host validated your draft and rejected it for these reasons:")
        for (i, failure) in failures.enumerated() {
            var entry = "  \(i + 1). [\(failure.kind.rawValue)] \(failure.message)"
            if let line = failure.line { entry += " (line \(line))" }
            entry += " — \(failure.suggestion ?? "no suggestion")"
            lines.append(entry)
        }
        lines.append("")
        lines.append("Your last draft was:")
        lines.append("<<<DRAFT_\(fenceNonce)")
        lines.append(rawScript)
        lines.append("\(fenceNonce)_DRAFT>>>")
        lines.append("")
        lines.append("Fix the issues above and call \(toolName) again with the corrected script.")
        lines.append("The other arguments should stay the same:")
        for (key, value) in originalArguments.sorted(by: { $0.key < $1.key }) where key != "script" {
            lines.append("  \(key): \(value)")
        }
        lines.append("Do NOT change the target. Do NOT call check_script first — the host already validated. Just call \(toolName) with the same arguments and a corrected script.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Equatable

    public static func == (lhs: ScriptDraftRefusal, rhs: ScriptDraftRefusal) -> Bool {
        lhs.toolName == rhs.toolName &&
        lhs.targetDescription == rhs.targetDescription &&
        lhs.rawScript == rhs.rawScript &&
        lhs.failures == rhs.failures
    }
}

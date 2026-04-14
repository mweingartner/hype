import Foundation

/// Prompt-size budget for outgoing Ollama chat requests.
///
/// Hype targets **128k-token context windows** as the minimum
/// supported model size. Every modern local model in routine use
/// (Llama 3.1/3.3, Mistral Large, Qwen 2.5, DeepSeek-V3, etc.)
/// ships with 128k contexts, and the user has explicitly stated
/// they do not run anything smaller. Instead of silently trimming
/// conversations to an arbitrary message count, the AI chat loop
/// now trims against a concrete character budget derived from this
/// token ceiling.
///
/// The trim runs:
///
/// 1. Once right after the user's message is appended (so the very
///    first request of a new turn is already under budget), and
/// 2. Before every chat call inside the tool-use loop (so a single
///    enormous tool result can't balloon the next request over the
///    ceiling).
///
/// Both call sites go through `trimToFit(_:maxCharacters:)`.
public enum AIPromptBudget {

    /// The maximum prompt size, in tokens, that Hype will send to
    /// the model on a single request. Set to 128k because the
    /// project targets 128k-context models as the minimum. Raise
    /// this deliberately (and update the tests) if the project
    /// ever targets a larger context class as its new minimum.
    public static let promptBudgetTokens: Int = 128_000

    /// Rough characters-per-token estimate for the mixed prose /
    /// HypeTalk code / JSON content Hype sends. BPE tokenizers on
    /// English prose produce ~4 chars/token, on code ~3; 3.5 is a
    /// conservative middle ground. Erring low means we trim a hair
    /// sooner than strictly necessary but never overshoot the
    /// model's real context window.
    public static let charactersPerToken: Double = 3.5

    /// Character ceiling derived from the token budget. Trim logic
    /// operates in characters because `String.count` is cheap;
    /// exact token counting would require linking a tokenizer
    /// (e.g. `tiktoken` or the model's own SentencePiece).
    public static let promptBudgetCharacters: Int =
        Int(Double(promptBudgetTokens) * charactersPerToken)  // = 448_000

    // MARK: - Estimation

    /// Estimate the on-the-wire character weight of a single
    /// `OllamaMessage`.
    ///
    /// Counts:
    /// - `role` length
    /// - `content` length (0 if nil)
    /// - per tool call: function name + each argument key and value
    ///   length + a small constant for JSON envelope overhead
    ///
    /// The estimate intentionally overestimates slightly (the
    /// envelope constant is larger than strictly needed) so trim
    /// calculations err on the side of the trim being slightly more
    /// aggressive than strictly necessary.
    public static func estimatedCharacterCount(_ message: OllamaMessage) -> Int {
        var count = message.role.count
        if let content = message.content {
            count += content.count
        }
        if let calls = message.tool_calls {
            for call in calls {
                count += call.function.name.count
                for (key, value) in call.function.arguments {
                    // +4 accounts for the JSON quoting and colon:
                    //   "key":"value"
                    count += key.count + value.count + 4
                }
                // Envelope: `{"function":{"name":"…","arguments":{…}}},`
                count += 40
            }
        }
        return count
    }

    /// Total estimated character weight of a list of messages.
    public static func estimatedCharacterCount(_ messages: [OllamaMessage]) -> Int {
        messages.reduce(0) { $0 + estimatedCharacterCount($1) }
    }

    // MARK: - Trimming

    /// Trim a conversation to fit under the prompt budget.
    ///
    /// Rules (in priority order):
    ///
    /// 1. If the conversation already fits, return it unchanged.
    /// 2. Always preserve the first message when it is a `system`
    ///    prompt. This is the HypeTalk guide + stack snapshot that
    ///    Hype builds fresh for every turn; dropping it would strip
    ///    the model of everything it needs to generate valid
    ///    HypeTalk.
    /// 3. Always preserve the most recent message. In a tool-use
    ///    loop that is either the newest user turn, the newest
    ///    assistant response with tool calls, or the newest tool
    ///    result — whichever the next chat call is being made
    ///    against.
    /// 4. Drop messages from the **oldest** end of the middle
    ///    region first (one at a time) until the budget is met or
    ///    only the preserved messages remain.
    /// 5. If the preserved messages alone still exceed the budget
    ///    (e.g. the system prompt plus a single huge tool result),
    ///    return them anyway. The trim function never truncates
    ///    individual message contents — that would risk producing
    ///    invalid JSON or mid-sentence garbage — and instead
    ///    surfaces an unavoidable overshoot to the model, which
    ///    will error gracefully rather than silently.
    ///
    /// - Parameters:
    ///   - messages: The conversation to trim.
    ///   - maxCharacters: Character budget. Defaults to
    ///     `promptBudgetCharacters` (128k tokens).
    /// - Returns: A trimmed copy of `messages`.
    public static func trimToFit(
        _ messages: [OllamaMessage],
        maxCharacters: Int = AIPromptBudget.promptBudgetCharacters
    ) -> [OllamaMessage] {
        // Fast path: under budget already.
        if estimatedCharacterCount(messages) <= maxCharacters {
            return messages
        }

        // Edge cases.
        guard !messages.isEmpty else { return [] }
        guard messages.count > 1 else { return messages }  // single message, nothing to trim

        var result = messages
        let hasSystem = (result.first?.role == "system")

        while estimatedCharacterCount(result) > maxCharacters {
            // preserveStart is the lowest index we're willing to drop.
            // preserveEnd is the index of the last (preserved) message.
            let preserveStart = hasSystem ? 1 : 0
            let preserveEnd = result.count - 1

            // Nothing left between the preserved ends? We can't trim
            // further without dropping the system prompt or the latest
            // message, which the policy forbids. Return what we have
            // and let the caller (and the model) deal with overshoot.
            if preserveStart >= preserveEnd {
                break
            }

            // Drop the oldest non-preserved message (one at a time so
            // we re-measure after each removal and stop as soon as
            // we're under budget).
            result.remove(at: preserveStart)
        }

        return result
    }
}

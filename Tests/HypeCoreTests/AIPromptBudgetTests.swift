import Testing
import Foundation
@testable import HypeCore

/// Regression tests for `AIPromptBudget`.
///
/// Hype pins the outgoing prompt size at 128k tokens, matching the
/// minimum context window of every local model the project targets.
/// These tests pin down:
///
/// - The numeric constants (raising the budget without updating tests
///   is a deliberate choice; drifting them accidentally is not).
/// - The `estimatedCharacterCount` math including tool-call overhead.
/// - The `trimToFit` policy: preserve the system prompt and the last
///   message, drop oldest middle messages first, handle edge cases.
@Suite("AIPromptBudget")
struct AIPromptBudgetTests {

    // MARK: - Constants

    @Test("prompt budget is 128k tokens")
    func promptBudgetIs128k() {
        #expect(AIPromptBudget.promptBudgetTokens == 128_000)
    }

    @Test("characters per token is the conservative 3.5 estimate")
    func charsPerTokenIsConservative() {
        #expect(AIPromptBudget.charactersPerToken == 3.5)
    }

    @Test("character budget derives from token budget × 3.5")
    func characterBudgetDerivation() {
        #expect(AIPromptBudget.promptBudgetCharacters == 448_000)
    }

    // MARK: - estimatedCharacterCount

    @Test("estimates an empty message list as zero")
    func estimatesEmptyListAsZero() {
        #expect(AIPromptBudget.estimatedCharacterCount([]) == 0)
    }

    @Test("estimates a plain text message as role + content")
    func estimatesPlainTextMessage() {
        let msg = OllamaMessage(role: "user", content: "hello world")
        let count = AIPromptBudget.estimatedCharacterCount(msg)
        // "user" = 4, "hello world" = 11 → 15
        #expect(count == 15)
    }

    @Test("estimates a message with nil content as just the role length")
    func estimatesNilContentMessage() {
        let msg = OllamaMessage(role: "assistant", content: nil)
        #expect(AIPromptBudget.estimatedCharacterCount(msg) == "assistant".count)
    }

    @Test("estimates a tool call message with envelope overhead")
    func estimatesToolCallMessage() {
        let call = OllamaToolCall(
            function: OllamaToolCallFunction(
                name: "create_button",
                arguments: ["name": "OK", "left": "100"]
            )
        )
        let msg = OllamaMessage(role: "assistant", content: "", tool_calls: [call])
        let count = AIPromptBudget.estimatedCharacterCount(msg)
        // "assistant" = 9
        // content = "" = 0
        // tool call: "create_button" = 13, arguments = ("name"+"OK"+4) + ("left"+"100"+4) = 8+1+8+2+8 = 27
        //   (per-arg: name=4 + OK=2 + 4 = 10; left=4 + 100=3 + 4 = 11; total 21)
        // envelope: +40
        // total: 9 + 0 + 13 + 21 + 40 = 83
        #expect(count == 83)
    }

    @Test("sums character count across a list")
    func sumsCharacterCountAcrossList() {
        let messages = [
            OllamaMessage(role: "system", content: "guide"),      // 5 + 6 = 11
            OllamaMessage(role: "user", content: "hi"),           // 2 + 4 = 6
            OllamaMessage(role: "assistant", content: "hello"),   // 5 + 9 = 14
        ]
        let total = AIPromptBudget.estimatedCharacterCount(messages)
        #expect(total == 11 + 6 + 14)
    }

    // MARK: - trimToFit: fast path

    @Test("returns the input unchanged when already under budget")
    func underBudgetReturnsUnchanged() {
        let messages = [
            OllamaMessage(role: "system", content: "guide"),
            OllamaMessage(role: "user", content: "hi"),
        ]
        let trimmed = AIPromptBudget.trimToFit(messages, maxCharacters: 1000)
        #expect(trimmed.count == 2)
        #expect(trimmed.map(\.role) == ["system", "user"])
    }

    @Test("empty input returns empty")
    func emptyInputReturnsEmpty() {
        let trimmed = AIPromptBudget.trimToFit([], maxCharacters: 100)
        #expect(trimmed.isEmpty)
    }

    @Test("single message is returned as-is even if over budget")
    func singleMessageOverBudgetReturnedAsIs() {
        // Single-message input has nothing to trim. The policy says
        // never truncate individual message contents, so we return
        // the oversized message and let the model error gracefully.
        let msg = OllamaMessage(role: "user", content: String(repeating: "x", count: 500))
        let trimmed = AIPromptBudget.trimToFit([msg], maxCharacters: 100)
        #expect(trimmed.count == 1)
        #expect(trimmed[0].content?.count == 500)
    }

    // MARK: - trimToFit: preserving system prompt + last message

    @Test("drops oldest middle messages first while preserving system + last")
    func dropsOldestMiddleFirst() {
        let system = OllamaMessage(role: "system", content: String(repeating: "s", count: 50))
        let old    = OllamaMessage(role: "user", content: String(repeating: "a", count: 200))
        let mid    = OllamaMessage(role: "assistant", content: String(repeating: "b", count: 200))
        let recent = OllamaMessage(role: "user", content: String(repeating: "c", count: 200))
        let latest = OllamaMessage(role: "assistant", content: String(repeating: "d", count: 200))

        // Total ≈ 50 + 200 + 200 + 200 + 200 + 5 (roles) + 4 (roles) + 9 + 4 + 9 = 881
        // Budget small enough to force trimming but big enough to keep system + latest + one or two more.
        let trimmed = AIPromptBudget.trimToFit(
            [system, old, mid, recent, latest],
            maxCharacters: 600
        )

        // First must still be the system prompt.
        #expect(trimmed.first?.role == "system")
        #expect(trimmed.first?.content?.hasPrefix("s") == true)

        // Last must still be the latest message.
        #expect(trimmed.last?.role == "assistant")
        #expect(trimmed.last?.content?.hasPrefix("d") == true)

        // Under budget after trim.
        #expect(AIPromptBudget.estimatedCharacterCount(trimmed) <= 600)

        // The oldest middle message ('old') should have been removed
        // before any newer middle message.
        let contents = trimmed.compactMap(\.content)
        #expect(!contents.contains(where: { $0.hasPrefix("a") }),
                "oldest middle message (prefix 'a') should have been dropped first")
    }

    @Test("drops multiple middle messages when necessary to fit budget")
    func dropsMultipleMiddleMessages() {
        let system = OllamaMessage(role: "system", content: String(repeating: "s", count: 50))
        let m1 = OllamaMessage(role: "user", content: String(repeating: "1", count: 200))
        let m2 = OllamaMessage(role: "assistant", content: String(repeating: "2", count: 200))
        let m3 = OllamaMessage(role: "user", content: String(repeating: "3", count: 200))
        let m4 = OllamaMessage(role: "assistant", content: String(repeating: "4", count: 200))
        let last = OllamaMessage(role: "user", content: String(repeating: "L", count: 50))

        // Budget forces trimming most middle messages.
        let trimmed = AIPromptBudget.trimToFit(
            [system, m1, m2, m3, m4, last],
            maxCharacters: 300
        )

        // System preserved.
        #expect(trimmed.first?.role == "system")
        // Latest preserved.
        #expect(trimmed.last?.content?.hasPrefix("L") == true)
        // Under budget.
        #expect(AIPromptBudget.estimatedCharacterCount(trimmed) <= 300)
        // Dropped in order from the oldest, so m1 is definitely gone.
        let contents = trimmed.compactMap(\.content)
        #expect(!contents.contains(where: { $0.hasPrefix("1") }))
    }

    @Test("preserves system + latest even when their combined size exceeds budget")
    func preservesAnchorsEvenWhenOversized() {
        // The policy: never truncate message content. If system +
        // latest alone exceed the budget, we return just those two
        // and let the model error gracefully rather than silently
        // corrupting anything.
        let system = OllamaMessage(role: "system", content: String(repeating: "s", count: 400))
        let old    = OllamaMessage(role: "user", content: String(repeating: "a", count: 100))
        let latest = OllamaMessage(role: "user", content: String(repeating: "L", count: 400))

        let trimmed = AIPromptBudget.trimToFit(
            [system, old, latest],
            maxCharacters: 500  // less than system + latest = 800+
        )

        // Should contain system + latest, nothing in the middle.
        #expect(trimmed.count == 2)
        #expect(trimmed.first?.role == "system")
        #expect(trimmed.last?.content?.hasPrefix("L") == true)
        #expect(!trimmed.contains(where: { $0.content?.hasPrefix("a") == true }))
    }

    @Test("drops messages when there is no leading system prompt")
    func dropsWhenNoLeadingSystem() {
        // If the conversation doesn't start with a system message,
        // the trim still preserves the latest message and drops
        // from the oldest end.
        let messages = (0..<5).map { i in
            OllamaMessage(role: "user", content: String(repeating: "\(i)", count: 200))
        }
        let trimmed = AIPromptBudget.trimToFit(messages, maxCharacters: 450)

        // Latest message preserved.
        #expect(trimmed.last?.content?.hasPrefix("4") == true)
        #expect(AIPromptBudget.estimatedCharacterCount(trimmed) <= 450)
        // Oldest (prefix "0") definitely dropped.
        #expect(!trimmed.contains(where: { $0.content?.hasPrefix("0") == true }))
    }

    @Test("128k budget is big enough to keep a realistic Hype conversation intact")
    func realisticConversationFitsUnder128k() {
        // The HypeTalkGuide (~6.5 KB) + current-state snapshot (~1 KB)
        // + a dozen user/assistant/tool turns should still be far
        // under 448 KB. This is a smoke test that the budget isn't
        // accidentally set so low that normal conversations get
        // truncated.
        let systemContent = HypeTalkGuide.llmContext + "\n\nCURRENT STATE: Stack 'Test' with 3 cards, 5 parts"
        var msgs: [OllamaMessage] = [OllamaMessage(role: "system", content: systemContent)]
        for i in 0..<20 {
            msgs.append(OllamaMessage(role: "user", content: "Please do thing \(i) to the current card"))
            msgs.append(OllamaMessage(role: "assistant", content: "Done thing \(i). Anything else?"))
        }
        let trimmed = AIPromptBudget.trimToFit(msgs)
        // Nothing should have been trimmed.
        #expect(trimmed.count == msgs.count)
        #expect(AIPromptBudget.estimatedCharacterCount(trimmed)
                == AIPromptBudget.estimatedCharacterCount(msgs))
    }
}

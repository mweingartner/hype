import Testing
import Foundation
@testable import HypeCore

/// Unit tests for `ScriptDraftCoordinator` — classification, envelope building, and
/// abandoned-draft messaging.
@Suite("ScriptDraftCoordinator — classification and envelope building")
struct ScriptDraftCoordinatorTests {

    // MARK: - Test helpers

    private func makeRefusal(
        toolName: String = "set_card_script",
        target: String = "card 'Home'",
        rawScript: String = "on mouseUp\nput 1 into x\nend mouseUp",
        failures: [ValidationFailure] = [
            ValidationFailure(kind: .syntax, message: "Line 2: expected end, got EOF", line: 2, suggestion: "Add end mouseUp")
        ]
    ) -> ScriptDraftRefusal {
        ScriptDraftRefusal(
            toolName: toolName,
            originalArguments: ["card_name": "Home", "script": rawScript],
            targetDescription: target,
            rawScript: rawScript,
            wrappedScript: rawScript,
            failures: failures
        )
    }

    @MainActor
    private func makeCoordinator() -> ScriptDraftCoordinator {
        ScriptDraftCoordinator(configuration: .init(maxAttempts: 3))
    }

    // MARK: - classify

    @Test("classify returns passed for a plain success string")
    func classify_passed() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let outcome = coordinator.classify(toolResult: "Set script of card 'Home'")
        if case .passed(let result) = outcome {
            #expect(result == "Set script of card 'Home'")
        } else {
            Issue.record("Expected .passed but got \(outcome)")
        }
    }

    @Test("classify returns refused for a valid sentinel string")
    func classify_refusal() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let refusal = makeRefusal()
        let sentinel = refusal.encodedSentinel()
        let outcome = coordinator.classify(toolResult: sentinel)
        if case .refused(let decoded) = outcome {
            #expect(decoded.toolName == "set_card_script")
        } else {
            Issue.record("Expected .refused but got \(outcome)")
        }
    }

    @Test("classify returns decodeFailed for a sentinel with invalid JSON")
    func classify_decodeFailed() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let badSentinel = ScriptDraftRefusal.sentinelPrefix + "not-json"
        let outcome = coordinator.classify(toolResult: badSentinel)
        if case .decodeFailed(let raw) = outcome {
            #expect(raw == badSentinel)
        } else {
            Issue.record("Expected .decodeFailed but got \(outcome)")
        }
    }

    @Test("classify returns passed for a non-sentinel error string")
    func classify_otherError() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let outcome = coordinator.classify(toolResult: "Part 'foo' not found")
        if case .passed = outcome {
            // OK — the coordinator treats all non-sentinel strings as pass-through
        } else {
            Issue.record("Expected .passed for non-sentinel string but got \(outcome)")
        }
    }

    // MARK: - makeRetryEnvelope

    @Test("retry envelope contains the verbatim rawScript inside the fence")
    func makeRetryEnvelope_includesScript() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let refusal = makeRefusal(rawScript: "on mouseUp\nput 99 into x\nend mouseUp")
        let envelope = coordinator.makeRetryEnvelope(for: refusal, attemptNumber: 1, maxAttempts: 3)
        let body = envelope.content ?? ""
        #expect(body.contains("put 99 into x"))
    }

    @Test("retry envelope contains all failure messages")
    func makeRetryEnvelope_includesAllFailures() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let failures = [
            ValidationFailure(kind: .syntax, message: "Missing end mouseUp", line: 3, suggestion: nil),
            ValidationFailure(kind: .nonHypeTalk, message: "Contains var keyword", line: nil, suggestion: nil),
        ]
        let refusal = makeRefusal(failures: failures)
        let envelope = coordinator.makeRetryEnvelope(for: refusal, attemptNumber: 2, maxAttempts: 3)
        let body = envelope.content ?? ""
        #expect(body.contains("Missing end mouseUp"))
        #expect(body.contains("Contains var keyword"))
    }

    @Test("retry envelope names the tool to call again")
    func makeRetryEnvelope_namesTool() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let refusal = makeRefusal(toolName: "set_background_script")
        let envelope = coordinator.makeRetryEnvelope(for: refusal, attemptNumber: 1, maxAttempts: 3)
        let body = envelope.content ?? ""
        #expect(body.contains("set_background_script"))
    }

    @Test("retry envelope fence nonce appears exactly twice (open and close)")
    func makeRetryEnvelope_fenceNonceAppearsExactlyTwice() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let refusal = makeRefusal()
        let envelope = coordinator.makeRetryEnvelope(for: refusal, attemptNumber: 1, maxAttempts: 3)
        let body = envelope.content ?? ""
        let nonce = refusal.fenceNonce
        // Opening: "<<<DRAFT_<nonce>" and closing: "<nonce>_DRAFT>>>"
        let openFence = "<<<DRAFT_\(nonce)"
        let closeFence = "\(nonce)_DRAFT>>>"
        #expect(body.contains(openFence))
        #expect(body.contains(closeFence))
        // Nonce itself should appear at least twice (once in open, once in close).
        let occurrences = body.components(separatedBy: nonce).count - 1
        #expect(occurrences >= 2)
    }

    // MARK: - makeAbandonedDraftMessage

    @Test("abandoned draft message contains the last rawScript verbatim")
    func makeAbandonedDraftMessage_quotesLastDraft() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let rawScript = "on mouseUp\nput \"hello world\" into field \"Name\"\nend mouseUp"
        let refusal = makeRefusal(rawScript: rawScript)
        let msg = coordinator.makeAbandonedDraftMessage(refusal, maxAttempts: 3)
        #expect(msg.contains("hello world"))
        #expect(msg.contains("field \"Name\""))
    }

    @Test("abandoned draft message mentions the attempt count")
    func makeAbandonedDraftMessage_mentionsAttemptCount() async {
        let coordinator = await MainActor.run { ScriptDraftCoordinator() }
        let refusal = makeRefusal()
        let msg = coordinator.makeAbandonedDraftMessage(refusal, maxAttempts: 3)
        #expect(msg.contains("3 time"))
    }

    // MARK: - Sentinel round-trip

    @Test("ScriptDraftRefusal encode and decode round-trips")
    func sentinelRoundTrip() {
        let refusal = makeRefusal()
        let sentinel = refusal.encodedSentinel()
        #expect(sentinel.hasPrefix(ScriptDraftRefusal.sentinelPrefix))
        let decoded = ScriptDraftRefusal.decode(from: sentinel)
        #expect(decoded != nil)
        #expect(decoded?.toolName == refusal.toolName)
        #expect(decoded?.targetDescription == refusal.targetDescription)
    }

    @Test("decode returns nil for a string not starting with the sentinel prefix")
    func sentinelDecode_nonSentinel() {
        let result = ScriptDraftRefusal.decode(from: "Set script of card 'Home'")
        #expect(result == nil)
    }

    @Test("decode returns nil (not a crash) when JSON is malformed")
    func sentinelDecode_malformedJSON() {
        let bad = ScriptDraftRefusal.sentinelPrefix + "{bad json}"
        let result = ScriptDraftRefusal.decode(from: bad)
        #expect(result == nil)
    }

    // MARK: - Script size cap

    @Test("oversized rawScript is truncated and adds a forbiddenPattern failure")
    func scriptSizeCap_truncatesAndAddsFailure() {
        let oversized = String(repeating: "x", count: ScriptDraftRefusal.scriptSizeCap + 100)
        let refusal = ScriptDraftRefusal(
            toolName: "set_card_script",
            originalArguments: [:],
            targetDescription: "test",
            rawScript: oversized,
            wrappedScript: oversized,
            failures: []
        )
        #expect(refusal.rawScript.count <= ScriptDraftRefusal.scriptSizeCap + 100)  // truncated
        #expect(refusal.rawScript.contains("[truncated by host gate"))
        #expect(refusal.failures.contains(where: { $0.kind == .forbiddenPattern }))
    }
}

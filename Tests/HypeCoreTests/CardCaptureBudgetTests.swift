import Testing
import Foundation
@testable import HypeCore

/// Unit tests for `CardCaptureBudget` — per-session and per-turn budget enforcement.
@Suite("CardCaptureBudget — budget enforcement and messaging")
struct CardCaptureBudgetTests {

    // MARK: - tryConsume session budget

    @Test("tryConsume returns true up to maxPerSession, then false")
    func tryConsume_upToMax() {
        var budget = CardCaptureBudget()
        for i in 1...CardCaptureBudget.maxPerSession {
            // Reset per-turn so each call is the first this turn.
            budget.beginTurn()
            let result = budget.tryConsume()
            #expect(result == true, "Expected true on attempt \(i)")
        }
        // One more beyond the cap.
        budget.beginTurn()
        #expect(budget.tryConsume() == false)
    }

    @Test("tryConsume tracks consumed count correctly")
    func tryConsume_tracksConsumed() {
        var budget = CardCaptureBudget()
        for _ in 1...3 {
            budget.beginTurn()
            _ = budget.tryConsume()
        }
        #expect(budget.consumed == 3)
        #expect(budget.remaining == CardCaptureBudget.maxPerSession - 3)
    }

    // MARK: - tryConsume per-turn budget

    @Test("tryConsume returns false on second call within same turn even if session-budget remains")
    func tryConsume_returnsFalseOnSecondCallSameTurn() {
        var budget = CardCaptureBudget()
        budget.beginTurn()
        // First call this turn should succeed.
        #expect(budget.tryConsume() == true)
        // Second call same turn should fail even though session budget remains.
        #expect(budget.tryConsume() == false)
    }

    @Test("consumedThisTurn is 1 after a successful consume")
    func tryConsume_consumedThisTurnTracking() {
        var budget = CardCaptureBudget()
        budget.beginTurn()
        _ = budget.tryConsume()
        #expect(budget.consumedThisTurn == 1)
    }

    // MARK: - beginTurn

    @Test("beginTurn resets consumedThisTurn but preserves consumed")
    func beginTurn_resetsPerTurnNotSession() {
        var budget = CardCaptureBudget()
        budget.beginTurn()
        _ = budget.tryConsume()
        let sessionAfterFirstTurn = budget.consumed

        // New turn — consumedThisTurn should reset.
        budget.beginTurn()
        #expect(budget.consumedThisTurn == 0)
        // Session count preserved.
        #expect(budget.consumed == sessionAfterFirstTurn)
        // Should be able to consume again this turn.
        #expect(budget.tryConsume() == true)
        #expect(budget.consumed == sessionAfterFirstTurn + 1)
    }

    // MARK: - resetSession

    @Test("resetSession zeroes both consumed and consumedThisTurn")
    func resetSession_zerosBoth() {
        var budget = CardCaptureBudget()
        // Consume a few captures across turns.
        for _ in 1...3 {
            budget.beginTurn()
            _ = budget.tryConsume()
        }
        #expect(budget.consumed > 0)

        budget.resetSession()
        #expect(budget.consumed == 0)
        #expect(budget.consumedThisTurn == 0)
        #expect(budget.remaining == CardCaptureBudget.maxPerSession)
    }

    // MARK: - remaining

    @Test("remaining decrements as captures are consumed")
    func remaining_decrements() {
        var budget = CardCaptureBudget()
        let max = CardCaptureBudget.maxPerSession
        #expect(budget.remaining == max)
        budget.beginTurn()
        _ = budget.tryConsume()
        #expect(budget.remaining == max - 1)
    }

    @Test("remaining is never negative when consumed exceeds max")
    func remaining_neverNegative() {
        var budget = CardCaptureBudget()
        // Exhaust the budget.
        for _ in 1...CardCaptureBudget.maxPerSession {
            budget.beginTurn()
            _ = budget.tryConsume()
        }
        #expect(budget.remaining == 0)
    }

    // MARK: - exhaustedReason

    @Test("exhaustedReason mentions cap when session-exhausted")
    func exhaustedReason_sessionExhausted() {
        var budget = CardCaptureBudget()
        for _ in 1...CardCaptureBudget.maxPerSession {
            budget.beginTurn()
            _ = budget.tryConsume()
        }
        let reason = budget.exhaustedReason()
        #expect(reason.contains("budget exhausted"))
        #expect(reason.contains("\(CardCaptureBudget.maxPerSession)/\(CardCaptureBudget.maxPerSession)"))
    }

    @Test("exhaustedReason differs when only turn-exhausted (session has remaining)")
    func exhaustedReason_turnExhausted() {
        var budget = CardCaptureBudget()
        budget.beginTurn()
        _ = budget.tryConsume()
        // Session still has remaining, but turn is done.
        #expect(budget.remaining > 0)
        let reason = budget.exhaustedReason()
        #expect(reason.contains("Already captured this turn"))
        #expect(!reason.contains("budget exhausted"))
    }

    // MARK: - refundOne (security DFR-1)

    @Test("refundOne after a successful tryConsume restores both counters")
    func refundOne_afterTryConsume() {
        var budget = CardCaptureBudget()
        #expect(budget.tryConsume() == true)
        #expect(budget.consumed == 1)
        #expect(budget.consumedThisTurn == 1)

        budget.refundOne()
        #expect(budget.consumed == 0)
        #expect(budget.consumedThisTurn == 0)
    }

    @Test("refundOne lets the same turn try again after a decode failure")
    func refundOne_allowsRetryThisTurn() {
        var budget = CardCaptureBudget()
        // First consume succeeds.
        #expect(budget.tryConsume() == true)
        // Without refund, a second tryConsume in the same turn would fail.
        budget.refundOne()
        // After refund, the slot is available again — same turn can retry.
        #expect(budget.tryConsume() == true)
        #expect(budget.consumed == 1)
        #expect(budget.consumedThisTurn == 1)
    }

    @Test("refundOne is idempotent at zero — does not go negative")
    func refundOne_clampsAtZero() {
        var budget = CardCaptureBudget()
        budget.refundOne()
        budget.refundOne()
        budget.refundOne()
        #expect(budget.consumed == 0)
        #expect(budget.consumedThisTurn == 0)
    }

    @Test("refundOne after exhausting the session unblocks one more capture")
    func refundOne_unblocksAfterExhaustion() {
        var budget = CardCaptureBudget()
        for _ in 1...CardCaptureBudget.maxPerSession {
            budget.beginTurn()
            #expect(budget.tryConsume() == true)
        }
        // Session exhausted — next attempt fails.
        budget.beginTurn()
        #expect(budget.tryConsume() == false)
        // Refund one slot (e.g. one of the prior captures was a decode failure).
        budget.refundOne()
        // Now the next turn's attempt succeeds.
        budget.beginTurn()
        #expect(budget.tryConsume() == true)
    }
}

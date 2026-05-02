import Foundation

// MARK: - CardCaptureBudget

/// Tracks and enforces the per-session and per-turn capture budget.
///
/// The AI is allowed at most `maxPerSession` card captures per chat session and at
/// most one capture per model turn. The chat panel calls `beginTurn()` at the start
/// of each `processWithTools` invocation and `tryConsume()` before dispatching a
/// `capture_card_image` tool call. `resetSession()` is called when the chat is cleared.
///
/// ## Budget rules
/// - At most `maxPerSession` captures across the entire chat session.
/// - At most 1 capture per turn (between consecutive `beginTurn()` calls).
///   This prevents the model from consuming the entire budget in a single response
///   that emits multiple capture tool calls.
public struct CardCaptureBudget: Sendable, Equatable {

    // MARK: - Constants

    /// Maximum captures allowed across the entire chat session.
    public static let maxPerSession = 5

    // MARK: - State

    /// Total captures consumed since the last `resetSession()`.
    public private(set) var consumed: Int = 0

    /// Captures consumed in the current turn (since the last `beginTurn()`).
    public private(set) var consumedThisTurn: Int = 0

    // MARK: - Initializer

    public init() {}

    // MARK: - Derived properties

    /// How many captures remain in the session budget.
    public var remaining: Int { max(0, Self.maxPerSession - consumed) }

    // MARK: - Mutations

    /// Reset all counters — call when the chat session is cleared.
    public mutating func resetSession() {
        consumed = 0
        consumedThisTurn = 0
    }

    /// Reset the per-turn counter — call at the start of each `processWithTools` invocation.
    ///
    /// Does NOT reset `consumed` — the session budget is preserved across turns.
    public mutating func beginTurn() {
        consumedThisTurn = 0
    }

    /// Attempt to consume one capture from the budget.
    ///
    /// Returns `true` and increments both counters if:
    /// - The session budget has not been exhausted (`consumed < maxPerSession`), AND
    /// - No capture has been made in the current turn (`consumedThisTurn < 1`).
    ///
    /// Returns `false` without modifying state otherwise.
    public mutating func tryConsume() -> Bool {
        guard consumed < Self.maxPerSession else { return false }
        guard consumedThisTurn < 1 else { return false }
        consumed += 1
        consumedThisTurn += 1
        return true
    }

    /// Refund a previously-consumed slot when the host commits to a capture
    /// (`tryConsume()` returns `true`) but the executor produces a malformed
    /// or unusable result (e.g. encoder fallback emits `sentinelPrefix + "{}"`,
    /// which the chat panel classifies as `.decodeFailed`).
    ///
    /// Without this refund a sustained encoder failure would silently drain
    /// the per-session budget across attempts that delivered no image.
    /// Idempotent at zero — never decrements below 0.
    public mutating func refundOne() {
        consumed = max(0, consumed - 1)
        consumedThisTurn = max(0, consumedThisTurn - 1)
    }

    /// A human-readable explanation of why the budget is exhausted.
    ///
    /// The message is passed back to the model as the tool result when
    /// `tryConsume()` returns `false`, so the model understands the constraint
    /// and can propose alternatives without retrying immediately.
    public func exhaustedReason() -> String {
        if consumed >= Self.maxPerSession {
            return "Capture budget exhausted (used \(Self.maxPerSession)/\(Self.maxPerSession) this session). Suggest changes from the previous capture or proceed without another image."
        } else {
            return "Already captured this turn. Use the previous image or wait until your next turn."
        }
    }
}

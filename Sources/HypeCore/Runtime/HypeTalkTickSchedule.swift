import Foundation

/// Fixed-rate scheduler state for HyperTalk-style engine ticks.
///
/// The schedule intentionally drops missed ticks when work overruns the next
/// deadline. That keeps script execution from trying to "catch up" by spending
/// accumulated time in a burst after the app, main actor, or runtime was busy.
public struct HypeTalkTickSchedule: Sendable {
    public static let hyperCardTickRate: TimeInterval = 60
    public static let hyperCardTickInterval: TimeInterval = 1.0 / hyperCardTickRate

    public var interval: TimeInterval
    private var nextTickTime: TimeInterval?

    public init(interval: TimeInterval = Self.hyperCardTickInterval) {
        self.interval = max(interval, 0.001)
    }

    public mutating func delayBeforeNextTick(now: TimeInterval) -> TimeInterval {
        guard let nextTickTime else {
            self.nextTickTime = now + interval
            return interval
        }
        return max(0, nextTickTime - now)
    }

    public mutating func recordTickCompleted(at completionTime: TimeInterval) {
        guard let scheduledTickTime = nextTickTime else {
            nextTickTime = completionTime + interval
            return
        }

        let nextScheduledTick = scheduledTickTime + interval
        nextTickTime = completionTime > nextScheduledTick
            ? completionTime + interval
            : nextScheduledTick
    }
}

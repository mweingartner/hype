import Foundation
import Testing
@testable import HypeCore

@Suite("HypeTalk fixed tick schedule")
struct HypeTalkTickScheduleTests {
    @Test("first tick waits one HyperCard tick")
    func firstTickWaitsOneInterval() {
        var schedule = HypeTalkTickSchedule(interval: 1.0 / 60.0)

        #expect(schedule.delayBeforeNextTick(now: 10) == 1.0 / 60.0)
    }

    @Test("unspent time is yielded until the next fixed tick")
    func unspentTimeYieldsUntilNextDeadline() {
        var schedule = HypeTalkTickSchedule(interval: 0.1)

        #expect(schedule.delayBeforeNextTick(now: 1.0) == 0.1)
        schedule.recordTickCompleted(at: 1.13)

        #expect(abs(schedule.delayBeforeNextTick(now: 1.14) - 0.06) < 0.000_001)
    }

    @Test("overrun drops missed ticks instead of catching up")
    func overrunDropsMissedTicks() {
        var schedule = HypeTalkTickSchedule(interval: 0.1)

        #expect(schedule.delayBeforeNextTick(now: 1.0) == 0.1)
        schedule.recordTickCompleted(at: 1.35)

        #expect(abs(schedule.delayBeforeNextTick(now: 1.36) - 0.09) < 0.000_001)
    }
}

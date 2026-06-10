import AppKit
import Testing
import Foundation
@testable import HypeCore

/// Tests that PartAnimator is safe to call from concurrent background
/// threads and that the Timer fires correctly on the main run loop.
///
/// The suite is `.serialized` because all tests share the singleton
/// `PartAnimator.shared` and must not run in parallel with each other.
@Suite("PartAnimator Safety", .serialized)
struct PartAnimatorSafetyTests {

    // MARK: - Concurrent-access stress test

    /// Hammers animate / stopAll / isAnimating from multiple concurrent
    /// background queues and asserts the process survives without
    /// a crash or assertion failure. The main run loop is ticked briefly
    /// so the Timer has a chance to fire during the stress window.
    @Test("Concurrent animate/stopAll from background queues — no crash")
    func concurrentAccessNoCrash() {
        let group = DispatchGroup()
        let iterations = 200
        let queues = (0..<4).map { i in
            DispatchQueue(label: "test.PartAnimator.\(i)", attributes: .concurrent)
        }

        for i in 0..<iterations {
            let q = queues[i % queues.count]
            group.enter()
            q.async {
                let id = UUID()
                PartAnimator.shared.animate(
                    partId: id, property: "left",
                    fromValue: 0, toValue: Double(i),
                    duration: 0.5
                )
                _ = PartAnimator.shared.isAnimating(partId: id)
                PartAnimator.shared.stopAll()
                group.leave()
            }
        }

        // Allow the main run loop to tick while background work is in flight
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        let completed = group.wait(timeout: .now() + 3.0)
        #expect(completed == .success, "Concurrent stress test timed out")

        // Clean up any animations left over from the stress run
        PartAnimator.shared.stopAll()
    }

    // MARK: - Functional test: animate from background, verify registration

    /// Calls animate from a background queue, spins the main run loop
    /// briefly, and asserts the animation is registered. Then calls
    /// stopAll and asserts it is cleared.
    @Test("animate from background — isAnimating true, then false after stopAll")
    func animateFromBackgroundRegisters() {
        let id = UUID()

        let exp = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            PartAnimator.shared.animate(
                partId: id, property: "top",
                fromValue: 0, toValue: 100,
                duration: 2.0
            )
            exp.signal()
        }
        // Wait for the background call to complete
        let signaled = exp.wait(timeout: .now() + 1.0)
        #expect(signaled == .success, "Background animate did not complete in time")

        // Spin the main run loop so the DispatchQueue.main.async inside
        // startTimerOnMain has a chance to execute
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        #expect(PartAnimator.shared.isAnimating(partId: id) == true,
                "Animation should be registered after animate() from background")

        PartAnimator.shared.stopAll()

        #expect(PartAnimator.shared.isAnimating(partId: id) == false,
                "Animation should be gone after stopAll()")
    }
}

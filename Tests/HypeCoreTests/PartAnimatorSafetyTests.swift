import AppKit
import Testing
import Foundation
@testable import HypeCore

/// Tests that PartAnimator is safe to call from concurrent background
/// threads and that registration is immediately visible across threads.
///
/// The suite is `.serialized` because all tests share the singleton
/// `PartAnimator.shared` and must not run in parallel with each other.
///
/// IMPORTANT (suite-wide discipline, see scripts/test.sh header): these
/// tests must never BLOCK a cooperative thread (no `group.wait`, no
/// `semaphore.wait`). Under the fully parallel runner a blocked
/// cooperative thread starves every other suite's continuations. The
/// stress workers therefore run on dedicated `Thread`s (immune to
/// dispatch-pool saturation) and completion is awaited via
/// `group.notify` bridged into a checked continuation.
@Suite("PartAnimator Safety", .serialized)
struct PartAnimatorSafetyTests {

    // MARK: - Concurrent-access stress test

    /// Hammers animate / stopAll / isAnimating from four real threads and
    /// asserts the process survives without a crash or runtime data-race
    /// trap. Surviving to the final expectation IS the assertion.
    @Test("Concurrent animate/stopAll from background threads — no crash")
    func concurrentAccessNoCrash() async {
        let group = DispatchGroup()
        let iterationsPerThread = 50

        for t in 0..<4 {
            group.enter()
            Thread.detachNewThread {
                for i in 0..<iterationsPerThread {
                    let id = UUID()
                    PartAnimator.shared.animate(
                        partId: id, property: "left",
                        fromValue: 0, toValue: Double(t * 1_000 + i),
                        duration: 0.5
                    )
                    _ = PartAnimator.shared.isAnimating(partId: id)
                    if i % 10 == 0 {
                        PartAnimator.shared.stopAll()
                    }
                }
                group.leave()
            }
        }

        // Non-blocking completion wait: the workers are real threads doing
        // pure CPU work, so they always finish; notify resumes us without
        // ever parking a cooperative thread.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { cont.resume() }
        }

        // Clean up any animations left over from the stress run.
        PartAnimator.shared.stopAll()
        #expect(PartAnimator.shared.isAnimating(partId: UUID()) == false)
    }

    // MARK: - Functional test: animate from background, verify registration

    /// Calls animate from a dedicated background thread and asserts the
    /// animation is registered (the lock makes registration visible
    /// immediately, independent of the main-thread tick timer). Then calls
    /// stopAll and asserts it is cleared.
    @Test("animate from background — isAnimating true, then false after stopAll")
    func animateFromBackgroundRegisters() async {
        let id = UUID()

        let group = DispatchGroup()
        group.enter()
        Thread.detachNewThread {
            PartAnimator.shared.animate(
                partId: id, property: "top",
                fromValue: 0, toValue: 100,
                duration: 2.0
            )
            group.leave()
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { cont.resume() }
        }

        #expect(PartAnimator.shared.isAnimating(partId: id) == true,
                "Animation should be registered after animate() from background")

        PartAnimator.shared.stopAll()

        #expect(PartAnimator.shared.isAnimating(partId: id) == false,
                "Animation should be gone after stopAll()")
    }
}

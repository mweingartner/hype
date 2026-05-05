import Foundation
@testable import HypeCore

// MARK: - Large-Stack Async Helper

/// Run synchronous work on a dedicated 8 MB-stack thread and suspend
/// the calling cooperative thread while the work executes.
///
/// Background: `Interpreter.executeStatement` is a large compiled function
/// whose stack frame exceeds the ≤512 KB stack Swift Testing's cooperative
/// thread pool allocates for detached workers. Running the work on a real
/// `Thread` with an 8 MB stack (matching the macOS main-thread default)
/// prevents SIGBUS crashes from deep-recursive scripts.
///
/// Why `withCheckedContinuation` instead of `DispatchSemaphore.wait()`?
/// The semaphore approach BLOCKS the cooperative thread. Under Swift
/// Testing's parallel runner, all cooperative threads can block
/// simultaneously — the resume continuations have nowhere to run and the
/// suite deadlocks forever. `withCheckedContinuation` SUSPENDS the
/// cooperative thread (returns it to the pool) so other work can proceed
/// while the worker thread runs.
internal func runOnLargeStack<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
    await withCheckedContinuation { continuation in
        let thread = Thread {
            let result = work()
            continuation.resume(returning: result)
        }
        thread.stackSize = 8 * 1024 * 1024  // 8 MB — matches macOS main thread
        thread.start()
    }
}

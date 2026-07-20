import Foundation

actor HypeDebugServerTestIsolation {
    static let shared = HypeDebugServerTestIsolation()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withMainActorLock<T: Sendable>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

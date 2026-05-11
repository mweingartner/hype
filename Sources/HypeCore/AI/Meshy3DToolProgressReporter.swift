import Foundation

// MARK: - Meshy3DToolProgressReporter

/// Rate-limited progress reporter for the long-running AI tool path.
///
/// Forwards monitor states to `HypeLogger.aiOutput` with a throttle so a
/// 90-second generation produces ~9 progress lines instead of ~30 (the
/// monitor polls every 3 s → 30 states for a 90 s job).
///
/// Emission rules:
/// - First `.pending` → always emits.
/// - `.inProgress(percent)`: emits when elapsed since last emission > 10 s,
///   OR when `percent - lastPercent >= 25`, OR on the first `.inProgress`.
/// - Terminal states (`.succeeded`, `.failed`, `.cancelled`) → always emit.
///
/// Threading: uses `NSLock` so `report(_:)` is safe to call from any thread.
public final class Meshy3DToolProgressReporter: @unchecked Sendable {

    // MARK: - Constants

    /// Minimum seconds between non-terminal `.inProgress` emissions.
    public static let throttleInterval: TimeInterval = 10.0

    // MARK: - Private state

    private let logger: HypeLogger
    private let toolName: String
    private let taskKindDescription: String

    private let lock = NSLock()
    private var lastEmittedAt: Date?
    private var lastEmittedPercent: Int = -1
    private var didEmitPending: Bool = false
    private var didEmitFirstInProgress: Bool = false

    // MARK: - Init

    /// Create a reporter.
    ///
    /// - Parameters:
    ///   - logger: The logger to emit to.
    ///   - toolName: Tool name used in the log prefix (e.g. `"generate_3d_model_from_text"`).
    ///   - taskKindDescription: Human-readable kind (e.g. `"text-to-3D"`).
    public init(logger: HypeLogger, toolName: String, taskKindDescription: String) {
        self.logger = logger
        self.toolName = toolName
        self.taskKindDescription = taskKindDescription
    }

    // MARK: - Public API

    /// Record a state transition. May or may not log, depending on the
    /// throttle window and state kind.
    public func report(_ state: MeshyTaskMonitor.State) {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .pending:
            guard !didEmitPending else { return }
            didEmitPending = true
            emit("Meshy: pending (\(taskKindDescription))")

        case .inProgress(let percent):
            let now = Date()
            let shouldEmit = !didEmitFirstInProgress
                || (lastEmittedAt.map { now.timeIntervalSince($0) >= Self.throttleInterval } ?? true)
                || (percent - lastEmittedPercent >= 25)

            guard shouldEmit else { return }
            didEmitFirstInProgress = true
            lastEmittedAt = now
            lastEmittedPercent = percent
            emit("Meshy: \(percent)% (\(taskKindDescription))")

        case .succeeded:
            emit("Meshy: succeeded (\(taskKindDescription))")

        case .failed(let error):
            let description = error.errorDescription ?? "unknown error"
            emit("Meshy: failed — \(description)")

        case .cancelled:
            emit("Meshy: cancelled")
        }
    }

    // MARK: - Private

    private func emit(_ message: String) {
        logger.aiOutput(message, source: "Meshy")
    }
}

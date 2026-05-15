import Foundation

// MARK: - MeshyTaskMonitor

/// State-machine actor that owns one Meshy task and polls until the task
/// reaches a terminal state or the hard wall-clock timeout fires.
///
/// Subscribers receive state updates via `progress()` — a single
/// `AsyncStream<State>` that terminates when the task enters a terminal state
/// (`.succeeded`, `.failed`, or `.cancelled`). Phase 1 supports one
/// subscriber per monitor; multi-cast is a Phase 2 concern.
///
/// Threading contract:
///   - All mutable state is isolated to this actor.
///   - The poll loop runs inside an internal `Task` started by `progress()`.
///   - Every UI state write by the subscriber must hop to `MainActor` explicitly.
///   - `cancel()` is idempotent — calling it twice or after `.succeeded` is a no-op.
public actor MeshyTaskMonitor {

    // MARK: - State

    /// The publicly-observable state of the in-flight task.
    public enum State: Sendable, Equatable {
        case pending
        case inProgress(percent: Int)
        case succeeded(MeshyTaskResult)
        case failed(MeshyError)
        case cancelled
    }

    // MARK: - Config

    public struct Config: Sendable {
        /// Seconds between polling calls to `fetchTask`.
        public var pollInterval: TimeInterval
        /// Wall-clock timeout in seconds. Default is 1800 (30 minutes).
        public var hardTimeout: TimeInterval
        /// Number of transient poll failures tolerated before surfacing the
        /// last failure. Non-retryable API/decode/auth errors fail immediately.
        public var maxTransientPollFailures: Int

        public init(
            pollInterval: TimeInterval = 3.0,
            hardTimeout: TimeInterval = 1800,
            maxTransientPollFailures: Int = 3
        ) {
            self.pollInterval = pollInterval
            self.hardTimeout = hardTimeout
            self.maxTransientPollFailures = max(0, maxTransientPollFailures)
        }
    }

    // MARK: - Private state

    private let client: MeshyClient
    private let taskId: String
    /// The kind of Meshy task being monitored — used to route `cancelTask`
    /// to the correct v1 / v2 DELETE endpoint (security M5).
    private let taskKind: MeshyTaskKind
    private let config: Config
    private let logger: HypeLogger

    /// Metadata needed to build a `MeshyTaskResult` on success.
    private let requestedFormats: Set<MeshyOutputFormat>
    private let prompt: String
    private let aiModel: MeshyAIModel

    private var currentState: State = .pending
    private var continuation: AsyncStream<State>.Continuation?
    private var pollTask: Task<Void, Never>?
    /// Guards against double-finish in `cancel()` and completion paths.
    private var didFinish: Bool = false
    /// Wall-clock timestamp captured when `progress()` is first called.
    private var startedAt: Date?
    private var transientPollFailures: Int = 0
    private var lastPollError: MeshyError?

    // MARK: - Init

    public init(
        client: MeshyClient,
        taskId: String,
        prompt: String,
        aiModel: MeshyAIModel,
        requestedFormats: Set<MeshyOutputFormat>,
        taskKind: MeshyTaskKind = .textTo3D,
        config: Config = Config(),
        logger: HypeLogger = .shared
    ) {
        self.client = client
        self.taskId = taskId
        self.taskKind = taskKind
        self.prompt = prompt
        self.aiModel = aiModel
        // Always include .glb in the requested formats.
        self.requestedFormats = requestedFormats.union([.glb])
        self.config = config
        self.logger = logger
    }

    // MARK: - Public API

    /// Returns the live progress stream.
    ///
    /// On first call, starts the internal poll loop and replays the
    /// current state as the first element. The stream finishes when
    /// the task reaches a terminal state.
    ///
    /// Subsequent calls return the same stream — only one subscriber
    /// is supported in Phase 1.
    public func progress() -> AsyncStream<State> {
        if continuation != nil {
            // Already started — return a new stream that replays current
            // state immediately. This is the "second call" path, which
            // is discouraged but tolerated gracefully.
            let snapshot = currentState
            return AsyncStream { cont in
                cont.yield(snapshot)
                // Don't start another poll — just close the extra stream.
                cont.finish()
            }
        }

        startedAt = Date()
        let initialState = currentState

        let stream = AsyncStream<State> { [weak self] cont in
            guard let self else { cont.finish(); return }
            Task {
                await self.storeContinuation(cont)
                await self.startPolling()
            }
        }

        // Yield the current state immediately.
        // (The continuation will be stored asynchronously; we yield after setup.)
        // The stream's first element will be produced by the poll loop once
        // the continuation is stored. To ensure the initial state is available,
        // the poll loop yields it on first iteration.
        _ = initialState  // Will be yielded by the loop's first tick.
        return stream
    }

    /// Current state. Useful for tests and one-shot reads.
    public var state: State { currentState }

    /// Cancels the in-flight task: stops polling, issues a best-effort
    /// DELETE, publishes `.cancelled`, and finishes the stream.
    ///
    /// Idempotent — calling twice or after `.succeeded` is a no-op.
    /// The DELETE call is awaited inline so callers can observe its
    /// completion — in particular, unit tests can check `cancelledTaskIds`
    /// immediately after `await monitor.cancel()` returns.
    public func cancel() async {
        guard !didFinish else { return }
        finish(with: .cancelled)
        // Best-effort DELETE — routes to the correct endpoint via taskKind.
        // Don't propagate failure.
        try? await client.cancelTask(taskId: taskId, kind: taskKind)
    }

    // MARK: - Private

    private func storeContinuation(_ cont: AsyncStream<State>.Continuation) {
        self.continuation = cont
        cont.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.cancel() }
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.runPollLoop()
        }
    }

    private func runPollLoop() async {
        // Yield the initial state immediately so the subscriber gets something right away.
        yield(currentState)

        while !didFinish {
            // Hard wall-clock timeout check (invariant: Date()-based, not poll count).
            if let start = startedAt, Date().timeIntervalSince(start) > config.hardTimeout {
                finish(with: .failed(.timedOut(taskId: taskId, afterSeconds: Int(config.hardTimeout))))
                break
            }

            do {
                let fact = try await client.fetchTaskFact(taskId: taskId, kind: taskKind)
                transientPollFailures = 0
                lastPollError = nil
                let newState = mapPolledFact(fact)
                if currentState != newState {
                    currentState = newState
                    yield(newState)
                }
                if isTerminal(newState) {
                    finish(with: newState)
                    break
                }
            } catch {
                let meshyError = normalizePollError(error)
                lastPollError = meshyError

                if isRetryablePollError(meshyError) {
                    transientPollFailures += 1
                    logger.info(
                        "Transient Meshy poll failure \(transientPollFailures)/\(config.maxTransientPollFailures) for task \(taskId): \(meshyError.errorDescription ?? String(describing: meshyError))",
                        source: "Meshy"
                    )
                    if transientPollFailures > config.maxTransientPollFailures {
                        finish(with: .failed(meshyError))
                        break
                    }
                } else {
                    finish(with: .failed(meshyError))
                    break
                }
            }

            // Respect cooperative cancellation.
            if Task.isCancelled { break }

            // Sleep for the poll interval.
            do {
                try await Task.sleep(for: .seconds(config.pollInterval))
            } catch {
                break  // Task was cancelled while sleeping.
            }
        }
    }

    private func mapPolledFact(_ fact: MeshyPolledFact) -> State {
        switch fact.status {
        case .pending:
            return .pending
        case .inProgress:
            return .inProgress(percent: fact.progress ?? 0)
        case .succeeded:
            guard let primaryUrl = fact.primaryModelUrl else {
                return .failed(.taskFailed(taskId: fact.taskId, message: "Meshy returned no model URL"))
            }
            let result = MeshyTaskResult(
                taskId: fact.taskId,
                modelURL: primaryUrl,
                format: .glb,
                alsoUSDZ: requestedFormats.contains(.usdz) ? fact.usdzUrl : nil,
                alsoFBX: requestedFormats.contains(.fbx) ? fact.fbxUrl : nil,
                prompt: prompt,
                aiModel: aiModel,
                basicWalkUrl: fact.basicWalkUrl,
                basicRunUrl: fact.basicRunUrl
            )
            return .succeeded(result)
        case .failed:
            let message = fact.errorMessage ?? "Generation failed"
            return .failed(.taskFailed(taskId: fact.taskId, message: String(message.prefix(200))))
        case .cancelled:
            return .cancelled
        }
    }

    private func isTerminal(_ state: State) -> Bool {
        switch state {
        case .succeeded, .failed, .cancelled: return true
        case .pending, .inProgress: return false
        }
    }

    private func normalizePollError(_ error: Error) -> MeshyError {
        if let meshyError = error as? MeshyError { return meshyError }
        if error is DecodingError { return .decodingFailed }
        if error is URLError { return .networkError }
        return .networkError
    }

    private func isRetryablePollError(_ error: MeshyError) -> Bool {
        switch error {
        case .networkError:
            return true
        case .rateLimited:
            return true
        case .requestFailed(let statusCode, _):
            return (500...599).contains(statusCode)
        default:
            return false
        }
    }

    private func yield(_ state: State) {
        continuation?.yield(state)
    }

    private func finish(with state: State) {
        guard !didFinish else { return }
        didFinish = true
        pollTask?.cancel()
        pollTask = nil
        currentState = state
        continuation?.yield(state)
        continuation?.finish()
        continuation = nil
    }
}

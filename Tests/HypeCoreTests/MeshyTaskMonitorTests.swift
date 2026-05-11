import Foundation
import Testing
@testable import HypeCore

// MARK: - Stub client

/// A stub `MeshyClient` that returns scripted task responses in sequence.
///
/// Phase 3: `fetchTask(taskId:)` is replaced by `fetchTaskFact(taskId:kind:)`.
/// `cancelTask` lists all five `MeshyTaskKind` cases explicitly (H1).
actor StubMeshyClient: MeshyClient {
    private var taskResponses: [MeshyPolledFact]
    private var responseIndex = 0
    private(set) var cancelledTaskIds: [String] = []
    private(set) var cancelledKinds: [MeshyTaskKind] = []

    init(responses: [MeshyPolledFact]) {
        self.taskResponses = responses
    }

    /// Convenience: construct from legacy `MeshyTaskResponse` values so older
    /// test helpers that call `makeTask(status:)` continue to compile.
    init(legacyResponses: [MeshyTaskResponse]) {
        self.taskResponses = legacyResponses.map { resp in
            MeshyPolledFact.fromTextOrImageTo3D(resp, kind: .textTo3D)
        }
    }

    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String {
        return "stub_task_id"
    }

    func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String {
        return "stub_image_task_id"
    }

    func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String {
        return "stub_multi_task_id"
    }

    func createRiggingTask(_ request: MeshyRiggingRequest) async throws -> String {
        return "stub_rigging_task_id"
    }

    func createAnimationTask(_ request: MeshyAnimationRequest) async throws -> String {
        return "stub_animation_task_id"
    }

    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        guard responseIndex < taskResponses.count else {
            return taskResponses.last!
        }
        defer { responseIndex += 1 }
        return taskResponses[responseIndex]
    }

    func createRemeshTask(_ request: MeshyRemeshRequest) async throws -> String { "stub_remesh_id" }
    func createRetextureTask(_ request: MeshyRetextureRequest) async throws -> String { "stub_retex_id" }

    /// **Security (H1):** all seven kinds listed explicitly; no `default:`.
    func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {
        cancelledTaskIds.append(taskId)
        cancelledKinds.append(kind)
        switch kind {
        case .textTo3D:       break
        case .imageTo3D:      break
        case .multiImageTo3D: break
        case .rigging:        break
        case .animation:      break
        case .remesh:         break
        case .retexture:      break
        }
    }

    func fetchBalance() async throws -> Int { return 100 }

    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        return Data(repeating: 0x42, count: 64)
    }
}

// MARK: - Helpers

/// Build a `MeshyPolledFact` for use in monitor tests.
private func makeTask(taskId: String = "t1", status: MeshyTaskStatus, progress: Int? = nil) -> MeshyPolledFact {
    let glbUrl = status == .succeeded ? URL(string: "https://cdn.meshy.ai/model.glb")! : nil
    return MeshyPolledFact(
        taskId: taskId,
        status: status,
        progress: progress,
        primaryModelUrl: glbUrl,
        errorMessage: nil
    )
}

/// Build a `MeshyPolledFact` with a task error, for failure tests.
private func makeFailedTask(taskId: String = "t_fail", message: String) -> MeshyPolledFact {
    MeshyPolledFact(
        taskId: taskId,
        status: .failed,
        errorMessage: message
    )
}

// MARK: - Tests

@Suite("MeshyTaskMonitor — state machine")
struct MeshyTaskMonitorTests {

    // MARK: (a) pending → inProgress → succeeded happy path

    @Test("pending→inProgress(50)→inProgress(100)→succeeded emits all states")
    func happyPath() async throws {
        let responses: [MeshyPolledFact] = [
            makeTask(status: .pending),
            makeTask(status: .inProgress, progress: 50),
            makeTask(status: .inProgress, progress: 100),
            makeTask(status: .succeeded),
        ]
        let stub = StubMeshyClient(responses: responses)
        let config = MeshyTaskMonitor.Config(pollInterval: 0.01, hardTimeout: 30)
        let monitor = MeshyTaskMonitor(
            client: stub,
            taskId: "t1",
            prompt: "barrel",
            aiModel: .meshy6,
            requestedFormats: [.glb],
            config: config,
            logger: HypeLogger(setupFileLogging: false)
        )

        var states: [MeshyTaskMonitor.State] = []
        for await state in await monitor.progress() {
            states.append(state)
        }

        let hasSucceeded = states.contains { if case .succeeded = $0 { return true }; return false }
        #expect(hasSucceeded, "Stream must end with .succeeded")

        let hasInProgress = states.contains { if case .inProgress = $0 { return true }; return false }
        #expect(hasInProgress, "Stream must include .inProgress states")
    }

    // MARK: (b) pending → failed

    @Test("pending→failed emits .failed(.taskFailed)")
    func failedTask() async throws {
        let failedFact = makeFailedTask(taskId: "t_fail", message: "Out of credits")
        let stub = StubMeshyClient(responses: [makeTask(status: .pending), failedFact])
        let config = MeshyTaskMonitor.Config(pollInterval: 0.01, hardTimeout: 30)
        let monitor = MeshyTaskMonitor(
            client: stub, taskId: "t_fail", prompt: "barrel",
            aiModel: .meshy6, requestedFormats: [.glb], config: config,
            logger: HypeLogger(setupFileLogging: false)
        )

        var lastState: MeshyTaskMonitor.State?
        for await state in await monitor.progress() {
            lastState = state
        }

        if case .failed(let err) = lastState,
           case .taskFailed(_, let msg) = err {
            #expect(msg.contains("Out of credits"))
        } else {
            Issue.record("Expected .failed(.taskFailed) as last state, got \(String(describing: lastState))")
        }
    }

    // MARK: (c) cancel() during .pending emits .cancelled and calls cancelTask

    @Test("cancel() during pending emits .cancelled")
    func cancelDuringPending() async throws {
        // Return pending forever until cancelled.
        let pendingFact = makeTask(status: .pending)
        let stub = StubMeshyClient(responses: Array(repeating: pendingFact, count: 100))
        let config = MeshyTaskMonitor.Config(pollInterval: 0.01, hardTimeout: 30)
        let monitor = MeshyTaskMonitor(
            client: stub, taskId: "t_cancel", prompt: "barrel",
            aiModel: .meshy6, requestedFormats: [.glb], config: config,
            logger: HypeLogger(setupFileLogging: false)
        )

        // Collect states in an actor-isolated collector to avoid
        // Swift 6 data-race warnings on the local `states` var.
        actor StateCollector {
            var states: [MeshyTaskMonitor.State] = []
            func append(_ s: MeshyTaskMonitor.State) { states.append(s) }
        }
        let collector = StateCollector()

        for await state in await monitor.progress() {
            await collector.append(state)
            if case .pending = state {
                // Cancel after first pending state.
                await monitor.cancel()
            }
        }

        let states = await collector.states
        let hasCancelled = states.contains { $0 == .cancelled }
        #expect(hasCancelled, "Stream must emit .cancelled")

        let cancelledIds = await stub.cancelledTaskIds
        #expect(cancelledIds.contains("t_cancel"), "cancelTask must be called with the task id")
    }

    // MARK: (d) cancel() during .inProgress likewise

    @Test("cancel() during inProgress emits .cancelled")
    func cancelDuringInProgress() async throws {
        let stub = StubMeshyClient(responses: Array(repeating: makeTask(taskId: "t_cancel2", status: .inProgress, progress: 30), count: 100))
        let config = MeshyTaskMonitor.Config(pollInterval: 0.01, hardTimeout: 30)
        let monitor = MeshyTaskMonitor(
            client: stub, taskId: "t_cancel2", prompt: "barrel",
            aiModel: .meshy6, requestedFormats: [.glb], config: config,
            logger: HypeLogger(setupFileLogging: false)
        )

        actor CancelledFlag {
            var value: Bool = false
            func set() { value = true }
        }
        let flag = CancelledFlag()

        for await state in await monitor.progress() {
            if case .inProgress = state {
                await monitor.cancel()
            } else if case .cancelled = state {
                await flag.set()
            }
        }
        let cancelled = await flag.value
        #expect(cancelled)
    }

    // MARK: (e) cancel() after .succeeded is a no-op

    @Test("cancel() after succeeded is a no-op")
    func cancelAfterSucceeded() async throws {
        let stub = StubMeshyClient(responses: [makeTask(taskId: "t_done", status: .succeeded)])
        let config = MeshyTaskMonitor.Config(pollInterval: 0.01, hardTimeout: 30)
        let monitor = MeshyTaskMonitor(
            client: stub, taskId: "t_done", prompt: "barrel",
            aiModel: .meshy6, requestedFormats: [.glb], config: config,
            logger: HypeLogger(setupFileLogging: false)
        )

        for await _ in await monitor.progress() {}

        // cancel() after stream finished — must not throw or hang.
        await monitor.cancel()
        let cancelledIds = await stub.cancelledTaskIds
        // cancelTask should NOT have been called since task already succeeded.
        #expect(!cancelledIds.contains("t_done"))
    }

    // MARK: (f) hard timeout fires .failed(.timedOut)

    @Test("hard timeout fires .failed(.timedOut)")
    func hardTimeoutFires() async throws {
        // Return pending forever.
        let stub = StubMeshyClient(responses: Array(repeating: makeTask(taskId: "t_timeout", status: .pending), count: 1000))
        // Very short timeout so the test finishes quickly.
        let config = MeshyTaskMonitor.Config(pollInterval: 0.01, hardTimeout: 0.05)
        let monitor = MeshyTaskMonitor(
            client: stub, taskId: "t_timeout", prompt: "barrel",
            aiModel: .meshy6, requestedFormats: [.glb], config: config,
            logger: HypeLogger(setupFileLogging: false)
        )

        var lastState: MeshyTaskMonitor.State?
        for await state in await monitor.progress() {
            lastState = state
        }

        if case .failed(let err) = lastState,
           case .timedOut = err {
            // Expected.
        } else {
            Issue.record("Expected .failed(.timedOut), got \(String(describing: lastState))")
        }
    }
}

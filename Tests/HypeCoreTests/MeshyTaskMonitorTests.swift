import Foundation
import Testing
@testable import HypeCore

// MARK: - Stub client

/// A stub `MeshyClient` that returns scripted task responses in sequence.
actor StubMeshyClient: MeshyClient {
    private var taskResponses: [MeshyTaskResponse]
    private var responseIndex = 0
    private(set) var cancelledTaskIds: [String] = []

    init(responses: [MeshyTaskResponse]) {
        self.taskResponses = responses
    }

    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String {
        return "stub_task_id"
    }

    func fetchTask(taskId: String) async throws -> MeshyTaskResponse {
        guard responseIndex < taskResponses.count else {
            // Return the last response indefinitely once exhausted.
            return taskResponses.last!
        }
        defer { responseIndex += 1 }
        return taskResponses[responseIndex]
    }

    func cancelTask(taskId: String) async throws {
        cancelledTaskIds.append(taskId)
    }

    func fetchBalance() async throws -> Int { return 100 }

    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        return Data(repeating: 0x42, count: 64)
    }
}

// MARK: - Helpers

private func makeTask(taskId: String = "t1", status: MeshyTaskStatus, progress: Int? = nil) -> MeshyTaskResponse {
    let urls = status == .succeeded ? MeshyModelURLs(
        glb: URL(string: "https://cdn.meshy.ai/model.glb")!,
        fbx: nil, usdz: nil, obj: nil, mtl: nil
    ) : nil
    return MeshyTaskResponse(
        id: taskId,
        status: status,
        progress: progress,
        createdAt: nil, startedAt: nil, finishedAt: nil,
        modelUrls: urls,
        taskError: nil, textureUrls: nil, preview: nil
    )
}

// MARK: - Tests

@Suite("MeshyTaskMonitor — state machine")
struct MeshyTaskMonitorTests {

    // MARK: (a) pending → inProgress → succeeded happy path

    @Test("pending→inProgress(50)→inProgress(100)→succeeded emits all states")
    func happyPath() async throws {
        let responses: [MeshyTaskResponse] = [
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
        let failedResp = MeshyTaskResponse(
            id: "t_fail",
            status: .failed,
            progress: nil,
            createdAt: nil, startedAt: nil, finishedAt: nil,
            modelUrls: nil,
            taskError: MeshyErrorEnvelope(error: nil, message: "Out of credits"),
            textureUrls: nil, preview: nil
        )
        let stub = StubMeshyClient(responses: [makeTask(status: .pending), failedResp])
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
        let stub = StubMeshyClient(responses: Array(repeating: makeTask(status: .pending), count: 100))
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
        let stub = StubMeshyClient(responses: Array(repeating: makeTask(status: .inProgress, progress: 30), count: 100))
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
        let stub = StubMeshyClient(responses: [makeTask(status: .succeeded)])
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
        let stub = StubMeshyClient(responses: Array(repeating: makeTask(status: .pending), count: 1000))
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

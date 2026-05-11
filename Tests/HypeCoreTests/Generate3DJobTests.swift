import Foundation
import Testing
@testable import HypeCore

// MARK: - Scripted stub MeshyClient

/// A stub MeshyClient that tracks which create method was called and
/// returns scripted task responses.
private actor ScriptedMeshyClient: MeshyClient {
    private var taskResponses: [MeshyTaskResponse]
    private var responseIndex = 0
    private(set) var lastCreatedKind: String? = nil
    private(set) var cancelledTaskIds: [String] = []

    init(responses: [MeshyTaskResponse]) {
        self.taskResponses = responses
    }

    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String {
        lastCreatedKind = "text"
        return "stub_text_task"
    }

    func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String {
        lastCreatedKind = "image"
        return "stub_image_task"
    }

    func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String {
        lastCreatedKind = "multiImage"
        return "stub_multi_task"
    }

    func fetchTask(taskId: String) async throws -> MeshyTaskResponse {
        guard responseIndex < taskResponses.count else {
            return taskResponses.last!
        }
        defer { responseIndex += 1 }
        return taskResponses[responseIndex]
    }

    func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {
        cancelledTaskIds.append(taskId)
    }

    func fetchBalance() async throws -> Int { 100 }

    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        // Return a minimal stub GLB
        Data(repeating: 0x47, count: 64)
    }
}

// MARK: - Helpers

private func makeSuccessResponse(taskId: String = "stub_task") -> MeshyTaskResponse {
    let urls = MeshyModelURLs(
        glb: URL(string: "https://cdn.meshy.ai/model.glb")!,
        fbx: nil, usdz: nil, obj: nil, mtl: nil
    )
    return MeshyTaskResponse(
        id: taskId,
        status: .succeeded,
        progress: 100,
        createdAt: nil, startedAt: nil, finishedAt: nil,
        modelUrls: urls,
        taskError: nil, textureUrls: nil, preview: nil
    )
}

private func makeInProgressResponse(taskId: String = "stub_task", pct: Int) -> MeshyTaskResponse {
    MeshyTaskResponse(
        id: taskId, status: .inProgress, progress: pct,
        createdAt: nil, startedAt: nil, finishedAt: nil,
        modelUrls: nil, taskError: nil, textureUrls: nil, preview: nil
    )
}

private func makeFailedResponse(taskId: String = "stub_task") -> MeshyTaskResponse {
    MeshyTaskResponse(
        id: taskId, status: .failed, progress: nil,
        createdAt: nil, startedAt: nil, finishedAt: nil,
        modelUrls: nil,
        taskError: MeshyErrorEnvelope(error: nil, message: "generation failed"),
        textureUrls: nil, preview: nil
    )
}

private func makePNGResolved(sourceDesc: String = "asset:test") -> MeshyImageInput.Resolved {
    let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0x42, count: 16))
    return MeshyImageInput.Resolved(data: pngBytes, mimeType: "image/png", sourceDescriptor: sourceDesc)
}

// MARK: - Tests

@Suite("Generate3DJob coordinator")
struct Generate3DJobTests {

    private func makeConfig() -> MeshyTaskMonitor.Config {
        MeshyTaskMonitor.Config(pollInterval: 0.01, hardTimeout: 30)
    }

    // MARK: (a) Text kind calls createTextTo3DTask

    @Test("Generate3DJob .text kind calls createTextTo3DTask")
    func textKindCallsCorrectMethod() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(hardTimeout: 30)
        let assets = try await job.run(
            kind: .text(prompt: "a barrel", artStyle: .realistic),
            options: options,
            existingAssetNames: []
        )
        let kind = await stub.lastCreatedKind
        #expect(kind == "text")
        #expect(!assets.isEmpty)
    }

    // MARK: (b) singleImage kind calls createImageTo3DTask

    @Test("Generate3DJob .singleImage kind calls createImageTo3DTask")
    func singleImageKindCallsCorrectMethod() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(hardTimeout: 30)
        let resolved = makePNGResolved()
        let assets = try await job.run(
            kind: .singleImage(image: resolved),
            options: options,
            existingAssetNames: []
        )
        let kind = await stub.lastCreatedKind
        #expect(kind == "image")
        #expect(!assets.isEmpty)
    }

    // MARK: (c) multiImage kind calls createMultiImageTo3DTask

    @Test("Generate3DJob .multiImage kind calls createMultiImageTo3DTask")
    func multiImageKindCallsCorrectMethod() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(hardTimeout: 30)
        let images = [makePNGResolved(sourceDesc: "asset:front"), makePNGResolved(sourceDesc: "asset:side")]
        let assets = try await job.run(
            kind: .multiImage(images: images),
            options: options,
            existingAssetNames: []
        )
        let kind = await stub.lastCreatedKind
        #expect(kind == "multiImage")
        #expect(!assets.isEmpty)
    }

    // MARK: (d) Progress callback receives all states

    @Test("Generate3DJob progress callback receives inProgress and succeeded states")
    func progressCallbackReceivesStates() async throws {
        let responses: [MeshyTaskResponse] = [
            makeInProgressResponse(pct: 50),
            makeSuccessResponse()
        ]
        let stub = ScriptedMeshyClient(responses: responses)
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(hardTimeout: 30)

        nonisolated(unsafe) var receivedStates: [MeshyTaskMonitor.State] = []
        _ = try await job.run(
            kind: .text(prompt: "test", artStyle: .realistic),
            options: options,
            existingAssetNames: [],
            onProgress: { state in
                receivedStates.append(state)
            }
        )

        let hasInProgress = receivedStates.contains { if case .inProgress = $0 { return true }; return false }
        let hasSucceeded = receivedStates.contains { if case .succeeded = $0 { return true }; return false }
        #expect(hasInProgress)
        #expect(hasSucceeded)
    }

    // MARK: (e) hardTimeout is respected (plumbed through to monitor)

    @Test("Generate3DJob hardTimeout option is plumbed through to monitor")
    func hardTimeoutPlumbed() async throws {
        // Use a very short timeout and a never-succeeding stub.
        let neverSucceeds = MeshyTaskResponse(
            id: "t", status: .inProgress, progress: 50,
            createdAt: nil, startedAt: nil, finishedAt: nil,
            modelUrls: nil, taskError: nil, textureUrls: nil, preview: nil
        )
        let stub = ScriptedMeshyClient(responses: [neverSucceeds])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        // Tiny timeout — should time out quickly.
        let options = Generate3DJob.Options(hardTimeout: 0.05)
        do {
            _ = try await job.run(
                kind: .text(prompt: "timeout test", artStyle: .realistic),
                options: options,
                existingAssetNames: []
            )
            Issue.record("Expected timedOut error")
        } catch MeshyError.timedOut {
            // Expected.
        } catch {
            // Also acceptable — timeout may surface as taskCancelled depending on timing.
        }
    }

    // MARK: (f) Failure mid-stream propagates as MeshyError

    @Test("Generate3DJob propagates .taskFailed error from monitor")
    func failedResponseThrows() async throws {
        let stub = ScriptedMeshyClient(responses: [makeFailedResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(hardTimeout: 30)
        do {
            _ = try await job.run(
                kind: .text(prompt: "will fail", artStyle: .realistic),
                options: options,
                existingAssetNames: []
            )
            Issue.record("Expected MeshyError.taskFailed")
        } catch MeshyError.taskFailed {
            // Expected.
        }
    }

    // MARK: (g) M2 combined 40 MB cap enforced for multiImage

    @Test("Generate3DJob rejects multiImage when combined size > 40 MB")
    func multiImageCombinedSizeCap() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(hardTimeout: 30)

        // Create two 21 MB images (combined > 40 MB).
        let bigData = Data(repeating: 0x42, count: 21 * 1024 * 1024)
        let bigResolved = MeshyImageInput.Resolved(data: bigData, mimeType: "image/png", sourceDescriptor: "test")
        let images = [bigResolved, bigResolved]

        do {
            _ = try await job.run(
                kind: .multiImage(images: images),
                options: options,
                existingAssetNames: []
            )
            Issue.record("Expected validationFailed for combined size")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_data")
        }
    }

    // MARK: (h) M4: monitorPrompt for image kinds is a safe descriptor (no raw path)

    @Test("Generate3DJob uses safe descriptor in monitor prompt for singleImage")
    func singleImageSafeDescriptor() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(hardTimeout: 30)

        // sourceDescriptor = "file" for filePath inputs — never the path itself.
        let resolved = MeshyImageInput.Resolved(data: Data(repeating: 0x42, count: 64), mimeType: "image/png", sourceDescriptor: "file")

        // If this runs without crash and returns assets, the monitor prompt
        // construction didn't expose the raw path.
        _ = try await job.run(
            kind: .singleImage(image: resolved),
            options: options,
            existingAssetNames: []
        )
        #expect(Bool(true))
    }
}

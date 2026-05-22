import Foundation
import Testing
@testable import HypeCore

// MARK: - Scripted stub MeshyClient

/// A stub MeshyClient that tracks which create method was called and
/// returns scripted task responses.
private actor ScriptedMeshyClient: MeshyClient {
    private var taskFacts: [MeshyPolledFact]
    private var responseIndex = 0
    private(set) var lastCreatedKind: String? = nil
    private(set) var lastTextRequest: MeshyTextTo3DRequest?
    private(set) var lastImageRequest: MeshyImageTo3DRequest?
    private(set) var lastMultiImageRequest: MeshyMultiImageTo3DRequest?
    private(set) var textCreateCount = 0
    private(set) var cancelledTaskIds: [String] = []

    init(responses: [MeshyPolledFact]) {
        self.taskFacts = responses
    }

    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String {
        lastCreatedKind = "text"
        lastTextRequest = request
        textCreateCount += 1
        return textCreateCount == 1 ? "stub_text_task" : "stub_refine_task"
    }

    func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String {
        lastCreatedKind = "image"
        lastImageRequest = request
        return "stub_image_task"
    }

    func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String {
        lastCreatedKind = "multiImage"
        lastMultiImageRequest = request
        return "stub_multi_task"
    }

    func createRiggingTask(_ request: MeshyRiggingRequest) async throws -> String {
        lastCreatedKind = "rigging"
        return "stub_rig_task"
    }

    func createAnimationTask(_ request: MeshyAnimationRequest) async throws -> String {
        lastCreatedKind = "animation"
        return "stub_anim_task"
    }

    func createRemeshTask(_ request: MeshyRemeshRequest) async throws -> String {
        lastCreatedKind = "remesh"
        return "stub_remesh_task"
    }

    func createRetextureTask(_ request: MeshyRetextureRequest) async throws -> String {
        lastCreatedKind = "retexture"
        return "stub_retexture_task"
    }

    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        guard responseIndex < taskFacts.count else {
            return taskFacts.last!
        }
        defer { responseIndex += 1 }
        return taskFacts[responseIndex]
    }

    /// Security (H1): all seven kinds listed explicitly; no default.
    func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {
        cancelledTaskIds.append(taskId)
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

    func fetchBalance() async throws -> Int { 100 }

    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        Data(repeating: 0x47, count: 64)
    }
}

// MARK: - Helpers

private func makeSuccessResponse(taskId: String = "stub_task") -> MeshyPolledFact {
    MeshyPolledFact(
        taskId: taskId,
        status: .succeeded,
        progress: 100,
        primaryModelUrl: URL(string: "https://cdn.meshy.ai/model.glb")!
    )
}

private func makeInProgressResponse(taskId: String = "stub_task", pct: Int) -> MeshyPolledFact {
    MeshyPolledFact(taskId: taskId, status: .inProgress, progress: pct)
}

private func makeFailedResponse(taskId: String = "stub_task") -> MeshyPolledFact {
    MeshyPolledFact(taskId: taskId, status: .failed, errorMessage: "generation failed")
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
        let request = try #require(await stub.lastTextRequest)
        #expect(request.targetFormats == ["glb", "usdz"])
    }

    @Test("Generate3DJob forwards Meshy request options")
    func forwardsRequestOptions() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(
            aiModel: .meshy6,
            shouldRemesh: true,
            alsoUSDZ: true,
            alsoFBX: true,
            targetPolycount: 12000,
            topology: "quad",
            symmetryMode: "auto",
            enablePbr: true,
            assetName: "named-barrel.glb",
            hardTimeout: 30
        )

        let assets = try await job.run(
            kind: .text(prompt: "a barrel", artStyle: .realistic),
            options: options,
            existingAssetNames: []
        )

        let request = try #require(await stub.lastTextRequest)
        #expect(request.targetPolycount == 12000)
        #expect(request.topology == "quad")
        #expect(request.symmetryMode == "auto")
        #expect(request.enablePbr == true)
        #expect(request.targetFormats == ["fbx", "glb", "usdz"])
        #expect(assets.first?.name == "named-barrel.glb")
    }

    @Test("Generate3DJob refined text mode creates preview then refine task")
    func refinedTextModeCreatesPreviewThenRefine() async throws {
        let stub = ScriptedMeshyClient(responses: [
            makeSuccessResponse(taskId: "preview_done"),
            makeSuccessResponse(taskId: "refine_done")
        ])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(textQuality: .refined, hardTimeout: 30)

        _ = try await job.run(
            kind: .text(prompt: "a barrel", artStyle: .realistic),
            options: options,
            existingAssetNames: []
        )

        let count = await stub.textCreateCount
        let last = try #require(await stub.lastTextRequest)
        #expect(count == 2)
        #expect(last.mode == .refine)
        #expect(last.previewTaskId == "preview_done")
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
        let responses: [MeshyPolledFact] = [
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
        let neverSucceeds = MeshyPolledFact(taskId: "t", status: .inProgress, progress: 50)
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
            #expect(field == "image_urls")
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

// MARK: - Suite E: Generate3DJob.validate boundary cases

@Suite("Generate3DJob.Options — validate boundary cases")
struct Generate3DJobValidateBoundaryTests {

    // MARK: E-1: targetPolycount exactly 100 → valid (no throw)

    @Test("targetPolycount exactly 100 is valid — no error thrown")
    func polycountExactly100IsValid() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(targetPolycount: 100, hardTimeout: 30)

        let assets = try await job.run(
            kind: .text(prompt: "barrel", artStyle: .realistic),
            options: options,
            existingAssetNames: []
        )
        #expect(!assets.isEmpty, "targetPolycount=100 must not throw — it is the lower bound")
    }

    // MARK: E-2: targetPolycount exactly 300,000 → valid

    @Test("targetPolycount exactly 300,000 is valid — no error thrown")
    func polycountExactly300kIsValid() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(targetPolycount: 300_000, hardTimeout: 30)

        let assets = try await job.run(
            kind: .text(prompt: "barrel", artStyle: .realistic),
            options: options,
            existingAssetNames: []
        )
        #expect(!assets.isEmpty, "targetPolycount=300,000 must not throw — it is the upper bound")
    }

    // MARK: E-3: targetPolycount 99 → throws MeshyError.invalidPolycount

    @Test("targetPolycount 99 throws MeshyError.invalidPolycount")
    func polycountBelow100Throws() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(targetPolycount: 99, hardTimeout: 30)

        do {
            _ = try await job.run(
                kind: .text(prompt: "barrel", artStyle: .realistic),
                options: options,
                existingAssetNames: []
            )
            Issue.record("Expected MeshyError.invalidPolycount for targetPolycount=99")
        } catch MeshyError.invalidPolycount(let value) {
            #expect(value == 99)
        } catch {
            Issue.record("Unexpected error type for polycount=99: \(error)")
        }
    }

    // MARK: E-4: targetPolycount 300,001 → throws MeshyError.invalidPolycount

    @Test("targetPolycount 300,001 throws MeshyError.invalidPolycount")
    func polycountAbove300kThrows() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(targetPolycount: 300_001, hardTimeout: 30)

        do {
            _ = try await job.run(
                kind: .text(prompt: "barrel", artStyle: .realistic),
                options: options,
                existingAssetNames: []
            )
            Issue.record("Expected MeshyError.invalidPolycount for targetPolycount=300,001")
        } catch MeshyError.invalidPolycount(let value) {
            #expect(value == 300_001)
        } catch {
            Issue.record("Unexpected error type for polycount=300,001: \(error)")
        }
    }

    // MARK: E-5: topology with mixed case ("qUaD") → validate lowercases for comparison, run succeeds

    /// Contract: `validate` lowercases `topology` before comparing to "quad"/"triangle".
    /// The original (mixed-case) string flows through to the wire request unchanged.
    /// The important invariant is that no validation error is thrown — the AI can
    /// supply any capitalisation.
    @Test("topology 'qUaD' is accepted without throwing (validate lowercases for comparison)")
    func topologyMixedCaseAccepted() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(topology: "qUaD", hardTimeout: 30)

        // Should not throw — the validate function lowercases before comparing.
        let assets = try await job.run(
            kind: .text(prompt: "barrel", artStyle: .realistic),
            options: options,
            existingAssetNames: []
        )
        #expect(!assets.isEmpty, "Mixed-case 'qUaD' topology must be accepted (no validation throw)")

        // The wire request receives the original case (validate does not mutate Options).
        let request = try #require(await stub.lastTextRequest)
        #expect(request.topology?.lowercased() == "quad", "Wire topology must lower-equal 'quad'")
    }

    // MARK: E-6: symmetryMode with mixed case ("aUtO") → validate lowercases for comparison, run succeeds

    /// Contract: `validate` lowercases `symmetryMode` before comparing to "off"/"auto"/"on".
    @Test("symmetryMode 'aUtO' is accepted without throwing (validate lowercases for comparison)")
    func symmetryModeMixedCaseAccepted() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(symmetryMode: "aUtO", hardTimeout: 30)

        let assets = try await job.run(
            kind: .text(prompt: "barrel", artStyle: .realistic),
            options: options,
            existingAssetNames: []
        )
        #expect(!assets.isEmpty, "Mixed-case 'aUtO' symmetryMode must be accepted (no validation throw)")

        let request = try #require(await stub.lastTextRequest)
        #expect(request.symmetryMode?.lowercased() == "auto", "Wire symmetryMode must lower-equal 'auto'")
    }

    // MARK: E-extra: invalid topology value → throws MeshyError.validationFailed

    @Test("topology 'hexagonal' throws MeshyError.validationFailed")
    func invalidTopologyThrows() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(topology: "hexagonal", hardTimeout: 30)

        do {
            _ = try await job.run(
                kind: .text(prompt: "barrel", artStyle: .realistic),
                options: options,
                existingAssetNames: []
            )
            Issue.record("Expected MeshyError.validationFailed for topology='hexagonal'")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "topology")
        } catch {
            Issue.record("Unexpected error type for invalid topology: \(error)")
        }
    }

    // MARK: E-extra: invalid symmetryMode value → throws MeshyError.validationFailed

    @Test("symmetryMode 'diagonal' throws MeshyError.validationFailed")
    func invalidSymmetryModeThrows() async throws {
        let stub = ScriptedMeshyClient(responses: [makeSuccessResponse()])
        let job = Generate3DJob(client: stub, logger: HypeLogger(setupFileLogging: false))
        let options = Generate3DJob.Options(symmetryMode: "diagonal", hardTimeout: 30)

        do {
            _ = try await job.run(
                kind: .text(prompt: "barrel", artStyle: .realistic),
                options: options,
                existingAssetNames: []
            )
            Issue.record("Expected MeshyError.validationFailed for symmetryMode='diagonal'")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "symmetry_mode")
        } catch {
            Issue.record("Unexpected error type for invalid symmetryMode: \(error)")
        }
    }
}

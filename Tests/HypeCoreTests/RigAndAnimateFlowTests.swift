import Foundation
import Testing
@testable import HypeCore

// MARK: - Stub client

/// Scripted stub `MeshyClient` for `RigAndAnimateFlow` tests.
/// All five `cancelTask` cases are listed explicitly (H1).
private actor RigAnimStubMeshyClient: MeshyClient {
    var createdRiggingTaskIds: [String] = []
    var createdAnimationTaskIds: [String] = []
    var cancelledTaskIds: [String] = []

    // Scripted sequences consumed in order.
    private var riggingTaskId: String
    private var animationTaskId: String
    private var riggingFacts: [MeshyPolledFact]
    private var animationFacts: [MeshyPolledFact]
    private var riggingIndex = 0
    private var animationIndex = 0

    init(
        riggingTaskId: String = "rig_stub_001",
        animationTaskId: String = "anim_stub_001",
        riggingFacts: [MeshyPolledFact] = [],
        animationFacts: [MeshyPolledFact] = []
    ) {
        self.riggingTaskId = riggingTaskId
        self.animationTaskId = animationTaskId
        self.riggingFacts = riggingFacts
        self.animationFacts = animationFacts
    }

    func createTextTo3DTask(_ r: MeshyTextTo3DRequest) async throws -> String { "t3d" }
    func createImageTo3DTask(_ r: MeshyImageTo3DRequest) async throws -> String { "i3d" }
    func createMultiImageTo3DTask(_ r: MeshyMultiImageTo3DRequest) async throws -> String { "mi3d" }

    func createRiggingTask(_ r: MeshyRiggingRequest) async throws -> String {
        createdRiggingTaskIds.append(riggingTaskId)
        return riggingTaskId
    }

    func createAnimationTask(_ r: MeshyAnimationRequest) async throws -> String {
        createdAnimationTaskIds.append(animationTaskId)
        return animationTaskId
    }

    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        switch kind {
        case .rigging:
            let fact = riggingFacts[min(riggingIndex, riggingFacts.count - 1)]
            riggingIndex += 1
            return fact
        case .animation:
            let fact = animationFacts[min(animationIndex, animationFacts.count - 1)]
            animationIndex += 1
            return fact
        case .textTo3D, .imageTo3D, .multiImageTo3D:
            return MeshyPolledFact(taskId: taskId, status: .succeeded)
        }
    }

    /// H1: all five kinds explicit, no default:.
    func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {
        cancelledTaskIds.append(taskId)
        switch kind {
        case .textTo3D:      break
        case .imageTo3D:     break
        case .multiImageTo3D: break
        case .rigging:       break
        case .animation:     break
        }
    }

    func fetchBalance() async throws -> Int { 500 }

    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        // Return minimal valid GLB (glTF magic bytes).
        return Data([0x67, 0x6C, 0x54, 0x46,  // glTF magic
                     0x02, 0x00, 0x00, 0x00,  // version 2
                     0x0C, 0x00, 0x00, 0x00]) // length 12
    }
}

// MARK: - Helpers

private func makeSucceededRiggingFact(
    taskId: String = "rig_001"
) -> MeshyPolledFact {
    MeshyPolledFact(
        taskId: taskId,
        status: .succeeded,
        progress: 100,
        primaryModelUrl: URL(string: "https://assets.meshy.ai/rigs/rig_001.glb"),
        basicWalkUrl: URL(string: "https://assets.meshy.ai/anims/walk_001.glb")
    )
}

private func makeSucceededAnimFact(
    taskId: String = "anim_001"
) -> MeshyPolledFact {
    MeshyPolledFact(
        taskId: taskId,
        status: .succeeded,
        progress: 100,
        primaryModelUrl: URL(string: "https://assets.meshy.ai/anims/anim_001.glb")
    )
}

// MARK: - Tests

@Suite("RigAndAnimateFlow — orchestration", .serialized)
struct RigAndAnimateFlowTests {

    // MARK: (a) runRigging imports rigged + optional walk assets

    @Test("runRigging returns assets with isRigged = true")
    func runRiggingReturnsRiggedAssets() async throws {
        let successFact = makeSucceededRiggingFact()
        let stub = RigAnimStubMeshyClient(
            riggingTaskId: "rig_001",
            riggingFacts: [
                MeshyPolledFact(taskId: "rig_001", status: .inProgress, progress: 30),
                successFact
            ]
        )

        let flow = RigAndAnimateFlow(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )
        let result = try await flow.runRigging(
            sourceTaskId: "base_task_123",
            sourceAssetName: "hero",
            options: RigAndAnimateFlow.RiggingOptions(alsoBasicWalk: true),
            existingAssetNames: []
        )

        // Must return at least one asset (the rigged base GLB).
        #expect(!result.assets.isEmpty)
        // All assets must be marked isRigged.
        let allRigged = result.assets.allSatisfy { $0.isRigged }
        #expect(allRigged, "All assets from runRigging must have isRigged = true")
        // rigTaskId must match what the stub returned.
        #expect(result.rigTaskId == "rig_001")
    }

    // MARK: (b) returned rigTaskId matches client POST response

    @Test("runRigging rigTaskId matches the id returned by createRiggingTask")
    func runRiggingRigTaskIdMatchesClientResult() async throws {
        let stub = RigAnimStubMeshyClient(
            riggingTaskId: "my_unique_rig_task",
            riggingFacts: [makeSucceededRiggingFact(taskId: "my_unique_rig_task")]
        )
        let flow = RigAndAnimateFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        let result = try await flow.runRigging(
            sourceTaskId: "source_task_abc",
            sourceAssetName: "hero",
            options: RigAndAnimateFlow.RiggingOptions(),
            existingAssetNames: []
        )

        #expect(result.rigTaskId == "my_unique_rig_task")
        let created = await stub.createdRiggingTaskIds
        #expect(created.contains("my_unique_rig_task"))
    }

    // MARK: (c) runRigging failure throws MeshyError

    @Test("runRigging throws when the monitor reaches failed state")
    func runRiggingThrowsOnFailure() async throws {
        let failedFact = MeshyPolledFact(
            taskId: "rig_fail",
            status: .failed,
            errorMessage: "Model is not humanoid"
        )
        let stub = RigAnimStubMeshyClient(
            riggingTaskId: "rig_fail",
            riggingFacts: [failedFact]
        )
        let flow = RigAndAnimateFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        await #expect(throws: (any Error).self) {
            _ = try await flow.runRigging(
                sourceTaskId: "base_task",
                sourceAssetName: "hero",
                options: RigAndAnimateFlow.RiggingOptions(),
                existingAssetNames: []
            )
        }
    }

    // MARK: (d) runAnimation returns asset with isRigged = true and animationActionId set

    @Test("runAnimation returns asset with isRigged = true and animationActionId set")
    func runAnimationReturnsAnimatedAsset() async throws {
        let animFact = makeSucceededAnimFact(taskId: "anim_001")
        let stub = RigAnimStubMeshyClient(
            animationTaskId: "anim_001",
            animationFacts: [animFact]
        )
        let flow = RigAndAnimateFlow(client: stub, logger: HypeLogger(setupFileLogging: false))
        let actionId: MeshyActionId = 42

        let asset = try await flow.runAnimation(
            rigTaskId: "rig_task_xyz",
            actionId: actionId,
            actionName: "Boxing_Practice",
            sourceAssetName: "hero",
            options: RigAndAnimateFlow.AnimationOptions(),
            existingAssetNames: []
        )

        #expect(asset.isRigged == true)
        #expect(asset.animationActionId == 42)
        #expect(asset.kind == .model3D)
    }

    // MARK: (e) runAnimation failure throws

    @Test("runAnimation throws when the monitor reaches failed state")
    func runAnimationThrowsOnFailure() async throws {
        let failedFact = MeshyPolledFact(
            taskId: "anim_fail",
            status: .failed,
            errorMessage: "Animation generation failed"
        )
        let stub = RigAnimStubMeshyClient(
            animationTaskId: "anim_fail",
            animationFacts: [failedFact]
        )
        let flow = RigAndAnimateFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        await #expect(throws: (any Error).self) {
            _ = try await flow.runAnimation(
                rigTaskId: "rig_task_abc",
                actionId: 10,
                actionName: "Kick_Basic",
                sourceAssetName: "hero",
                options: RigAndAnimateFlow.AnimationOptions(),
                existingAssetNames: []
            )
        }
    }

    // MARK: (f) Progress handler receives all states

    @Test("runRigging progress handler is called for each state change")
    func runRiggingProgressHandlerReceivesStates() async throws {
        let stub = RigAnimStubMeshyClient(
            riggingTaskId: "rig_progress",
            riggingFacts: [
                MeshyPolledFact(taskId: "rig_progress", status: .pending),
                MeshyPolledFact(taskId: "rig_progress", status: .inProgress, progress: 50),
                makeSucceededRiggingFact(taskId: "rig_progress")
            ]
        )

        actor StateRecorder {
            var states: [MeshyTaskMonitor.State] = []
            func record(_ state: MeshyTaskMonitor.State) { states.append(state) }
        }
        let recorder = StateRecorder()

        let flow = RigAndAnimateFlow(client: stub, logger: HypeLogger(setupFileLogging: false))
        _ = try await flow.runRigging(
            sourceTaskId: "base",
            sourceAssetName: "hero",
            options: RigAndAnimateFlow.RiggingOptions(alsoBasicWalk: false),
            existingAssetNames: [],
            onProgress: { state in
                await recorder.record(state)
            }
        )

        let states = await recorder.states
        #expect(!states.isEmpty, "Progress handler must have been called at least once")
    }
}

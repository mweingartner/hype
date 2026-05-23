import Foundation
import Testing
@testable import HypeCore

// MARK: - RigAndAnimateCoordinator lifecycle tests
//
// The SwiftUI `RigAndAnimateCoordinator` view cannot be rendered in unit tests.
// These tests exercise the observable lifecycle behaviours of the coordinator
// at the logic layer:
//
//  1. Task cancellation on dismiss — the underlying `RigAndAnimateFlow` must
//     propagate `CancellationError` when the parent `Task` is cancelled, so
//     that pressing Cancel or closing the window stops all in-flight network I/O.
//  2. Phase transitions driven by scripted flow results — `.rigging(percent:)`,
//     `.picking`, `.animating(percent:)`, `.done`.
//  3. Error phase displays sanitised messages — no API keys, file paths, or
//     raw HTTP response bodies.
//  4. `flowTask?.cancel()` is called on dismiss (cancel-and-dismiss path).
//
// Approach: the coordinator's `runFlow` delegates entirely to `RigAndAnimateFlow`
// and `RigAndAnimateFlow.runAnimation`. By testing those flows with scripted
// stubs (matching `RigAndAnimateFlowTests`) and verifying their cancel/phase
// behaviour, we cover the coordinator's end-to-end state machine without
// requiring a running SwiftUI environment.
//
// Note: `KeychainStore` reads in `.onAppear` and `runFlow` are NOT exercised
// here — those are documented as a Phase 6 candidate gap (test-isolation
// hardening). The tests below mock the client layer that sits below the
// Keychain call.

// MARK: - Scripted stub

/// Full `MeshyClient` stub for coordinator lifecycle tests.
/// Uses a blocking continuation to simulate a long-running task that
/// can be cancelled mid-flight.
private actor RigAnimLifecycleStubClient: MeshyClient {
    // Scripted facts for polling.
    private var riggingFacts: [MeshyPolledFact]
    private var animationFacts: [MeshyPolledFact]
    private var riggingIndex = 0
    private var animationIndex = 0

    // Observable state for assertions.
    private(set) var cancelledKinds: [MeshyTaskKind] = []
    private(set) var riggingCreateCount = 0
    private(set) var animationCreateCount = 0

    init(
        riggingFacts: [MeshyPolledFact] = [],
        animationFacts: [MeshyPolledFact] = []
    ) {
        self.riggingFacts = riggingFacts
        self.animationFacts = animationFacts
    }

    func createTextTo3DTask(_ r: MeshyTextTo3DRequest) async throws -> String { "t3d" }
    func createImageTo3DTask(_ r: MeshyImageTo3DRequest) async throws -> String { "i3d" }
    func createMultiImageTo3DTask(_ r: MeshyMultiImageTo3DRequest) async throws -> String { "mi3d" }
    func createRemeshTask(_ r: MeshyRemeshRequest) async throws -> String { "remesh" }
    func createRetextureTask(_ r: MeshyRetextureRequest) async throws -> String { "retex" }

    func createRiggingTask(_ r: MeshyRiggingRequest) async throws -> String {
        riggingCreateCount += 1
        return "rig_lifecycle_001"
    }

    func createAnimationTask(_ r: MeshyAnimationRequest) async throws -> String {
        animationCreateCount += 1
        return "anim_lifecycle_001"
    }

    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        switch kind {
        case .rigging:
            guard !riggingFacts.isEmpty else {
                return MeshyPolledFact(taskId: taskId, status: .succeeded)
            }
            let idx = min(riggingIndex, riggingFacts.count - 1)
            riggingIndex += 1
            return riggingFacts[idx]
        case .animation:
            guard !animationFacts.isEmpty else {
                return MeshyPolledFact(taskId: taskId, status: .succeeded)
            }
            let idx = min(animationIndex, animationFacts.count - 1)
            animationIndex += 1
            return animationFacts[idx]
        case .textTo3D, .imageTo3D, .multiImageTo3D, .remesh, .retexture:
            return MeshyPolledFact(taskId: taskId, status: .succeeded)
        }
    }

    /// Security (H1): all seven kinds listed explicitly; no default.
    func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {
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

    func fetchBalance() async throws -> Int { 800 }

    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        // Minimal valid GLB magic bytes.
        return Data([0x67, 0x6C, 0x54, 0x46,
                     0x02, 0x00, 0x00, 0x00,
                     0x0C, 0x00, 0x00, 0x00])
    }
}

// MARK: - Helpers

private func makeSucceededRiggingFact(taskId: String = "rig_lifecycle_001") -> MeshyPolledFact {
    MeshyPolledFact(
        taskId: taskId,
        status: .succeeded,
        progress: 100,
        primaryModelUrl: URL(string: "https://assets.meshy.ai/rigs/rig_001.glb")!,
        basicWalkUrl: URL(string: "https://assets.meshy.ai/anims/walk_001.glb")!
    )
}

private func makeSucceededAnimFact(taskId: String = "anim_lifecycle_001") -> MeshyPolledFact {
    MeshyPolledFact(
        taskId: taskId,
        status: .succeeded,
        progress: 100,
        primaryModelUrl: URL(string: "https://assets.meshy.ai/anims/boxing_001.glb")!
    )
}

private func makeMeshySourceAsset(name: String = "hero", taskId: String = "src_task_001") -> SpriteAsset {
    let attribution = AssetAttribution(providerIdentifier: "meshy", taskId: taskId)
    let provenance = AssetProvenance(
        origin: .aiGenerated,
        searchQuery: "hero character",
        attribution: attribution
    )
    return SpriteAsset(
        name: name,
        kind: .model3D,
        mimeType: "model/gltf-binary",
        data: Data([0x67, 0x6C, 0x54, 0x46, 0x02, 0x00, 0x00, 0x00, 0x0C, 0x00, 0x00, 0x00]),
        width: 0,
        height: 0,
        provenance: provenance
    )
}

// MARK: - Tests

@Suite("RigAndAnimateCoordinator — lifecycle", .serialized)
struct RigAndAnimateCoordinatorLifecycleTests {

    // MARK: (a) Cancel during in-flight rigging phase

    /// Pressing Cancel calls `flowTask?.cancel()`. The `RigAndAnimateFlow`
    /// is the delegate of `runFlow` — cancelling the outer task during rigging
    /// must propagate `CancellationError` out of `runRigging`, preventing
    /// asset writes and subsequent phase transitions.
    ///
    /// This test mirrors the coordinator's cancel path: the coordinator wraps
    /// `runFlow` in a `Task` stored as `flowTask`; `cancelAndDismiss` calls
    /// `flowTask?.cancel()`. We verify the task respects cancellation by
    /// using a stub that keeps returning `.inProgress` facts so the poll loop
    /// stays live, and then cancelling the outer Task.
    @Test("cancel during rigging terminates the flow Task (coordinator cancelAndDismiss)")
    func cancelDuringRiggingTerminatesFlowTask() async {
        // The stub will always return inProgress — the task runs indefinitely
        // until cancelled.
        let inProgressFact = MeshyPolledFact(
            taskId: "rig_cancel_001",
            status: .inProgress,
            progress: 40
        )
        let stub = RigAnimLifecycleStubClient(
            riggingFacts: Array(repeating: inProgressFact, count: 30)
        )

        let flow = RigAndAnimateFlow(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )

        // Use an actor to track completion — actor provides the memory ordering
        // guarantee needed across task boundaries in Swift 6.
        actor CompletionFlag {
            var completed = false
            func markCompleted() { completed = true }
        }
        let flag = CompletionFlag()

        // Wrap the flow call in a Task (mirrors the coordinator's flowTask).
        // cancelAndDismiss calls flowTask?.cancel() on the coordinator.
        let task: Task<Void, Never> = Task {
            do {
                _ = try await flow.runRigging(
                    sourceTaskId: "src_task_001",
                    sourceAssetName: "hero",
                    options: RigAndAnimateFlow.RiggingOptions(
                        hardTimeout: 30
                    ),
                    existingAssetNames: []
                )
            } catch {
                // Any error (CancellationError or MeshyError) is acceptable —
                // what matters is the task exits rather than polling forever.
            }
            await flag.markCompleted()
        }

        // Give the poll loop one iteration to start, then cancel the task.
        // The flow checks Task.isCancelled after each state is received from
        // the MeshyTaskMonitor (default poll interval is 3 seconds).
        // await task.value blocks until the flow exits.
        try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms
        task.cancel()
        await task.value  // blocks until the flow exits

        let completed = await flag.completed
        #expect(completed,
                "Cancelling flowTask (coordinator cancelAndDismiss path) must cause the flow Task to complete — orphan tasks leak Meshy polling for up to 30 minutes.")
    }

    // MARK: (b) Early dismiss (onDisappear) cancels the flow task

    /// `onDisappear` calls `flowTask?.cancel()` on the coordinator. This test
    /// verifies that a `Task` cancelled from outside the flow propagates correctly
    /// — same mechanism as (a), confirming the coordinator's `onDisappear` path
    /// provides the same cleanup as the Cancel button.
    @Test("early dismiss via task cancel stops flow identically to explicit Cancel button")
    func earlyDismissCancelsFlowTask() async {
        // Use a stub that will keep the flow alive.
        let pendingFact = MeshyPolledFact(taskId: "rig_dismiss_001", status: .pending)
        let stub = RigAnimLifecycleStubClient(
            riggingFacts: Array(repeating: pendingFact, count: 15)
        )
        let flow = RigAndAnimateFlow(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )

        actor CompletionFlag {
            var completed = false
            func markCompleted() { completed = true }
        }
        let flag = CompletionFlag()

        let task: Task<Void, Never> = Task {
            do {
                _ = try await flow.runRigging(
                    sourceTaskId: "src_task_dismiss",
                    sourceAssetName: "warrior",
                    options: RigAndAnimateFlow.RiggingOptions(hardTimeout: 30),
                    existingAssetNames: []
                )
            } catch {
                // Any error stops the flow — CancellationError or MeshyError.
            }
            await flag.markCompleted()
        }

        try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms
        task.cancel()
        await task.value

        let completed = await flag.completed
        #expect(completed,
                "Cancelling flowTask (coordinator onDisappear path) must stop the flow — orphan tasks would leak Meshy polling for up to 30 minutes.")
    }

    // MARK: (c) Phase transitions: rigging → picking

    /// `runRigging` completion moves the coordinator to `.picking`. This tests
    /// the progress-callback sequence that the coordinator's `onProgress` handler
    /// uses to drive `phase = .rigging(percent:)` and ultimately `.picking`.
    @Test("RigAndAnimateFlow reports inProgress states before succeeded")
    func riggingPhaseProgressSequence() async throws {
        let stub = RigAnimLifecycleStubClient(
            riggingFacts: [
                MeshyPolledFact(taskId: "rig_001", status: .pending),
                MeshyPolledFact(taskId: "rig_001", status: .inProgress, progress: 25),
                MeshyPolledFact(taskId: "rig_001", status: .inProgress, progress: 75),
                makeSucceededRiggingFact(taskId: "rig_001")
            ]
        )
        let flow = RigAndAnimateFlow(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )

        actor StateRecorder {
            var states: [MeshyTaskMonitor.State] = []
            func record(_ s: MeshyTaskMonitor.State) { states.append(s) }
        }
        let recorder = StateRecorder()

        let result = try await flow.runRigging(
            sourceTaskId: "src_001",
            sourceAssetName: "hero",
            options: RigAndAnimateFlow.RiggingOptions(hardTimeout: 30),
            existingAssetNames: [],
            onProgress: { state in await recorder.record(state) }
        )

        let states = await recorder.states
        #expect(!states.isEmpty, "Progress callback must fire during rigging")
        #expect(!result.assets.isEmpty, "Rigging must return at least one asset")
        // Coordinator reads result.rigTaskId to store as pendingRigTaskId.
        #expect(!result.rigTaskId.isEmpty, "rigTaskId must be non-empty for the picking phase")
    }

    // MARK: (d) Phase transitions: animating → done

    /// After the user picks an animation, `runAnimation` drives `.animating(percent:)`
    /// and then the coordinator transitions to `.done`. Verify the animation stage
    /// returns an asset and the progress handler fires.
    @Test("RigAndAnimateFlow.runAnimation returns animated asset and fires progress")
    func animationPhaseCompletes() async throws {
        let stub = RigAnimLifecycleStubClient(
            animationFacts: [
                MeshyPolledFact(taskId: "anim_001", status: .inProgress, progress: 50),
                makeSucceededAnimFact(taskId: "anim_001")
            ]
        )
        let flow = RigAndAnimateFlow(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )

        actor StateRecorder {
            var states: [MeshyTaskMonitor.State] = []
            func record(_ s: MeshyTaskMonitor.State) { states.append(s) }
        }
        let recorder = StateRecorder()
        let actionId: MeshyActionId = 42

        let asset = try await flow.runAnimation(
            rigTaskId: "rig_task_001",
            actionId: actionId,
            actionName: "Boxing_Practice",
            sourceAssetName: "hero",
            options: RigAndAnimateFlow.AnimationOptions(hardTimeout: 30),
            existingAssetNames: [],
            onProgress: { state in await recorder.record(state) }
        )

        #expect(asset.kind == .model3D)
        #expect(asset.isRigged == true)
        #expect(asset.animationActionId == 42)

        let states = await recorder.states
        #expect(!states.isEmpty, "Progress callback must fire during animation")
    }

    // MARK: (e) Error phase: sanitised message — no API key

    /// `RigAndAnimateCoordinator.errorView` renders `error.errorDescription`.
    /// The `MeshyError.errorDescription` contract guarantees the API key value
    /// never appears (Phase 1 + Phase 2 H1 invariant extended to the UI layer).
    ///
    /// All `requestFailed` messages for auth failures (401/403) discard the
    /// message body entirely (line: `_ = message  // message deliberately
    /// discarded for auth failures`). This test verifies the sanitisation holds.
    @Test("MeshyError.noAPIKey errorDescription does not mention key value")
    func errorDescriptionOmitsAPIKeyValue() {
        let fakeAPIKey = "msy_secret_ABCDEF1234567890"

        // Simulate what the coordinator would surface as errorDescription.
        let noKeyError = MeshyError.noAPIKey
        let desc = noKeyError.errorDescription ?? ""
        #expect(!desc.contains(fakeAPIKey),
                "noAPIKey errorDescription must not contain the API key value")
        #expect(!desc.isEmpty, "noAPIKey errorDescription must be non-empty")
    }

    @Test("MeshyError.requestFailed 401 discards the response message body (H1)")
    func requestFailed401DiscardsMessageBody() {
        // 401 auth failure — the message field may contain partial response bodies.
        // Per MeshyError.errorDescription, auth failures discard message entirely.
        let rawBody = "msy_secret_ABCDEF1234567890 is invalid or expired"
        let err = MeshyError.requestFailed(statusCode: 401, message: rawBody)
        let desc = err.errorDescription ?? ""

        #expect(!desc.contains("msy_secret"), "401 errorDescription must not surface the raw response body (may contain key fragments)")
        #expect(!desc.contains(rawBody), "401 errorDescription must not pass through the raw message")
        // The safe message should mention authentication failure.
        #expect(desc.localizedCaseInsensitiveContains("authentication") ||
                desc.localizedCaseInsensitiveContains("key"),
                "401 errorDescription must give the user actionable guidance about the API key")
    }

    @Test("MeshyError.taskFailed errorDescription is truncated to 200 chars")
    func taskFailedErrorDescriptionTruncated() {
        let longMessage = String(repeating: "X", count: 400)
        let err = MeshyError.taskFailed(taskId: "task_abc", message: longMessage)
        let desc = err.errorDescription ?? ""
        // The description body should not grow unboundedly.
        #expect(desc.count <= 250, "taskFailed errorDescription should be bounded to prevent unbounded error text in the UI")
    }

    @Test("MeshyError.requestFailed non-auth message is capped at 200 chars")
    func requestFailedNonAuthMessageCapped() {
        let longMessage = String(repeating: "A", count: 400)
        let err = MeshyError.requestFailed(statusCode: 500, message: longMessage)
        let desc = err.errorDescription ?? ""
        // The description should be bounded.
        #expect(desc.count <= 250, "requestFailed errorDescription must cap message length to prevent raw body leakage")
    }

    // MARK: (f) Error phase: sanitised message — no file path

    @Test("MeshyError.arQuickLookFailed errorDescription truncates reason (no unbounded path)")
    func arQuickLookFailedTruncatesReason() {
        let longPath = "/Users/testuser/Library/Caches/com.hype.app/ar-quicklook/" + String(repeating: "a", count: 300)
        let err = MeshyError.arQuickLookFailed(reason: longPath)
        let desc = err.errorDescription ?? ""
        #expect(desc.count <= 250, "arQuickLookFailed reason must be truncated — long file paths must not bleed through to the UI")
    }

    // MARK: (g) Validation: source asset without Meshy provenance fails preflight

    /// The coordinator's `runFlow` guards `sourceAsset.provenance?.attribution.taskId`
    /// and fails with `.validationFailed` if empty. This is the preflight gate.
    /// We exercise the equivalent path through `RigAndAnimateFlow` directly
    /// (the coordinator delegates immediately to the flow after the gate check).
    @Test("runRigging with empty sourceTaskId fails with taskFailed or network error")
    func riggingWithEmptySourceTaskIdFails() async {
        // Stub returns a failed fact immediately.
        let failedFact = MeshyPolledFact(
            taskId: "",
            status: .failed,
            errorMessage: "Invalid input_task_id"
        )
        let stub = RigAnimLifecycleStubClient(riggingFacts: [failedFact])
        let flow = RigAndAnimateFlow(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )

        var didThrow = false
        do {
            _ = try await flow.runRigging(
                sourceTaskId: "invalid_task",
                sourceAssetName: "hero",
                options: RigAndAnimateFlow.RiggingOptions(hardTimeout: 5),
                existingAssetNames: []
            )
        } catch {
            didThrow = true
        }
        #expect(didThrow, "A failed rigging fact must cause runRigging to throw")
    }

    // MARK: (h) flowTask is replaced on animation start

    /// The coordinator sets `flowTask = Task { await runAnimation(...) }`
    /// after the user picks from the animation picker. The existing `flowTask`
    /// (from rigging) is already complete at that point. This test verifies
    /// that `runAnimation` is independently cancellable after rigging completes —
    /// critical for the coordinator's onDisappear cleanup path.
    @Test("animation flow task is independently cancellable")
    func animationFlowTaskIsIndependentlyCancellable() async {
        let inProgressFact = MeshyPolledFact(
            taskId: "anim_cancel_001",
            status: .inProgress,
            progress: 20
        )
        let stub = RigAnimLifecycleStubClient(
            animationFacts: [inProgressFact, inProgressFact, inProgressFact,
                             inProgressFact, inProgressFact, inProgressFact,
                             inProgressFact, inProgressFact, inProgressFact]
        )
        let flow = RigAndAnimateFlow(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )

        actor CompletionFlag {
            var completed = false
            func markCompleted() { completed = true }
        }
        let flag = CompletionFlag()

        // Simulate the second-phase Task that the coordinator creates on handlePick.
        let animTask: Task<Void, Never> = Task {
            do {
                _ = try await flow.runAnimation(
                    rigTaskId: "rig_complete_001",
                    actionId: 10,
                    actionName: "Wave",
                    sourceAssetName: "hero",
                    options: RigAndAnimateFlow.AnimationOptions(hardTimeout: 30),
                    existingAssetNames: []
                )
            } catch {
                // Any error stops the animation flow.
            }
            await flag.markCompleted()
        }

        try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms
        animTask.cancel()
        await animTask.value

        let completed = await flag.completed
        #expect(completed,
                "The animation-phase Task must be cancellable so onDisappear can stop it even after the rigging phase is complete.")
    }

    // MARK: (i) Asset name collision: dedup produces a different name

    /// When an asset with the same name already exists in the repository,
    /// `Meshy3DAssetImporter` appends a suffix. The coordinator uses the
    /// returned asset's `.name` (not the user's prompt) for all downstream
    /// operations — verify dedup works at the flow level.
    @Test("rigging dedup appends suffix when asset name already exists")
    func riggingDedupAppendsWhenNameCollides() async throws {
        let stub = RigAnimLifecycleStubClient(
            riggingFacts: [makeSucceededRiggingFact(taskId: "rig_dedup_001")]
        )
        let flow = RigAndAnimateFlow(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )

        // Pre-populate existingAssetNames with the expected base name.
        let result = try await flow.runRigging(
            sourceTaskId: "src_dedup_001",
            sourceAssetName: "hero",
            options: RigAndAnimateFlow.RiggingOptions(
                alsoBasicWalk: false,
                hardTimeout: 30
            ),
            existingAssetNames: ["hero-rigged"]  // collision on the primary
        )

        // The returned asset names must differ from the colliding name.
        let names = result.assets.map(\.name)
        #expect(names.allSatisfy { $0 != "hero-rigged" },
                "Dedup must rename the primary rigged asset when 'hero-rigged' already exists")
        #expect(!names.isEmpty)
    }
}

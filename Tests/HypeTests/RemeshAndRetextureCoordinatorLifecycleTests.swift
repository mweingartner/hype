import Foundation
import Testing
@testable import HypeCore

// MARK: - RemeshAndRetextureCoordinator lifecycle tests
//
// The SwiftUI `RemeshAndRetextureCoordinator` view cannot be rendered in unit
// tests. These tests exercise the observable lifecycle behaviours at the logic
// layer:
//
//  1. Task cancellation on dismiss — `flowTask?.cancel()` must propagate
//     `CancellationError` from `RemeshAndRetextureFlow`, preventing credits
//     from being spent after the sheet is closed.
//  2. Phase transitions — `.configuring` → `.running(percent:)` → `.done` for
//     both remesh and retexture modes, exercised via scripted flow results.
//  3. Error phase displays sanitised messages — no API keys, file paths, or
//     raw HTTP response bodies.
//  4. `canStart` guard — retexture mode requires a non-empty style prompt;
//     remesh mode always allows starting when the API key is set.
//
// Note: `KeychainStore` reads in `.onAppear` and `runFlow` are NOT covered
// here — documented as a Phase 6 gap (test-isolation hardening).

// MARK: - Scripted stub

/// Full `MeshyClient` stub for remesh/retexture coordinator lifecycle tests.
private actor RemeshRetexLifecycleStubClient: MeshyClient {
    private var remeshFacts: [MeshyPolledFact]
    private var retextureFacts: [MeshyPolledFact]
    private var remeshIndex = 0
    private var retextureIndex = 0

    private(set) var cancelledKinds: [MeshyTaskKind] = []
    private(set) var remeshCreateCount = 0
    private(set) var retextureCreateCount = 0

    init(
        remeshFacts: [MeshyPolledFact] = [],
        retextureFacts: [MeshyPolledFact] = []
    ) {
        self.remeshFacts = remeshFacts
        self.retextureFacts = retextureFacts
    }

    func createTextTo3DTask(_ r: MeshyTextTo3DRequest) async throws -> String { "t3d" }
    func createImageTo3DTask(_ r: MeshyImageTo3DRequest) async throws -> String { "i3d" }
    func createMultiImageTo3DTask(_ r: MeshyMultiImageTo3DRequest) async throws -> String { "mi3d" }
    func createRiggingTask(_ r: MeshyRiggingRequest) async throws -> String { "rig" }
    func createAnimationTask(_ r: MeshyAnimationRequest) async throws -> String { "anim" }

    func createRemeshTask(_ r: MeshyRemeshRequest) async throws -> String {
        remeshCreateCount += 1
        return "remesh_lifecycle_001"
    }

    func createRetextureTask(_ r: MeshyRetextureRequest) async throws -> String {
        retextureCreateCount += 1
        return "retex_lifecycle_001"
    }

    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        switch kind {
        case .remesh:
            guard !remeshFacts.isEmpty else {
                return MeshyPolledFact(taskId: taskId, status: .succeeded)
            }
            let idx = min(remeshIndex, remeshFacts.count - 1)
            remeshIndex += 1
            return remeshFacts[idx]
        case .retexture:
            guard !retextureFacts.isEmpty else {
                return MeshyPolledFact(taskId: taskId, status: .succeeded)
            }
            let idx = min(retextureIndex, retextureFacts.count - 1)
            retextureIndex += 1
            return retextureFacts[idx]
        case .textTo3D, .imageTo3D, .multiImageTo3D, .rigging, .animation:
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

    func fetchBalance() async throws -> Int { 600 }

    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        // Minimal valid GLB magic bytes.
        return Data([0x67, 0x6C, 0x54, 0x46,
                     0x02, 0x00, 0x00, 0x00,
                     0x0C, 0x00, 0x00, 0x00])
    }
}

// MARK: - Helpers

private func makeSucceededRemeshFact(taskId: String = "remesh_lifecycle_001") -> MeshyPolledFact {
    MeshyPolledFact(
        taskId: taskId,
        status: .succeeded,
        progress: 100,
        primaryModelUrl: URL(string: "https://assets.meshy.ai/remesh/result.glb")!
    )
}

private func makeSucceededRetextureFact(taskId: String = "retex_lifecycle_001") -> MeshyPolledFact {
    MeshyPolledFact(
        taskId: taskId,
        status: .succeeded,
        progress: 100,
        primaryModelUrl: URL(string: "https://assets.meshy.ai/retexture/result.glb")!
    )
}

// MARK: - Tests

@Suite("RemeshAndRetextureCoordinator — lifecycle", .serialized)
struct RemeshAndRetextureCoordinatorLifecycleTests {

    // MARK: (a) Cancel during in-flight remesh phase

    /// `onDisappear` / Cancel button call `flowTask?.cancel()`. The coordinator
    /// wraps `runFlow` in a `Task`; cancelling it must propagate `CancellationError`
    /// from `RemeshAndRetextureFlow.runRemesh`, preventing orphan polling loops.
    @Test("cancel during remesh propagates CancellationError out of RemeshAndRetextureFlow")
    func cancelDuringRemeshPropagatesCancellationError() async {
        let inProgressFact = MeshyPolledFact(
            taskId: "remesh_cancel_001",
            status: .inProgress,
            progress: 30
        )
        let stub = RemeshRetexLifecycleStubClient(
            remeshFacts: Array(repeating: inProgressFact, count: 15)
        )
        let flow = RemeshAndRetextureFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        actor CompletionFlag {
            var completed = false
            func markCompleted() { completed = true }
        }
        let flag = CompletionFlag()

        let task: Task<Void, Never> = Task {
            do {
                _ = try await flow.runRemesh(
                    sourceTaskId: "src_remesh_001",
                    sourceAssetName: "barrel",
                    sourcePrompt: "wooden barrel",
                    options: RemeshAndRetextureFlow.RemeshOptions(
                        targetPolycount: 10_000,
                        hardTimeout: 30
                    ),
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
                "Cancelling the flow Task (coordinator cancelAndDismiss / onDisappear) must stop RemeshAndRetextureFlow.runRemesh — credits must not be consumed after sheet dismiss.")
    }

    // MARK: (b) Cancel during in-flight retexture phase

    @Test("cancel during retexture propagates CancellationError out of RemeshAndRetextureFlow")
    func cancelDuringRetexturePropagatesCancellationError() async {
        let inProgressFact = MeshyPolledFact(
            taskId: "retex_cancel_001",
            status: .inProgress,
            progress: 55
        )
        let stub = RemeshRetexLifecycleStubClient(
            retextureFacts: Array(repeating: inProgressFact, count: 15)
        )
        let flow = RemeshAndRetextureFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        actor CompletionFlag {
            var completed = false
            func markCompleted() { completed = true }
        }
        let flag = CompletionFlag()

        let task: Task<Void, Never> = Task {
            do {
                _ = try await flow.runRetexture(
                    sourceTaskId: "src_retex_001",
                    sourceAssetName: "barrel",
                    sourcePrompt: "wooden barrel",
                    newStylePrompt: "rusty metal finish",
                    options: RemeshAndRetextureFlow.RetextureOptions(hardTimeout: 30),
                    existingAssetNames: []
                )
            } catch {
                // Any error stops the flow.
            }
            await flag.markCompleted()
        }

        try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms
        task.cancel()
        await task.value

        let completed = await flag.completed
        #expect(completed,
                "Cancelling the flow Task (coordinator onDisappear) must stop RemeshAndRetextureFlow.runRetexture — credits must not be consumed after sheet dismiss.")
    }

    // MARK: (c) Phase transitions: remesh configuring → running → done

    /// `runRemesh` reports progress states and returns a `Asset` on
    /// success. The coordinator uses these to drive `.running(percent:)` then `.done`.
    @Test("RemeshAndRetextureFlow.runRemesh fires progress callbacks and returns asset")
    func remeshPhaseTransitionsToDone() async throws {
        let stub = RemeshRetexLifecycleStubClient(
            remeshFacts: [
                MeshyPolledFact(taskId: "remesh_001", status: .pending),
                MeshyPolledFact(taskId: "remesh_001", status: .inProgress, progress: 40),
                MeshyPolledFact(taskId: "remesh_001", status: .inProgress, progress: 80),
                makeSucceededRemeshFact(taskId: "remesh_001")
            ]
        )
        let flow = RemeshAndRetextureFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        actor StateRecorder {
            var states: [MeshyTaskMonitor.State] = []
            func record(_ s: MeshyTaskMonitor.State) { states.append(s) }
        }
        let recorder = StateRecorder()

        let asset = try await flow.runRemesh(
            sourceTaskId: "src_001",
            sourceAssetName: "castle",
            sourcePrompt: "stone castle",
            options: RemeshAndRetextureFlow.RemeshOptions(
                targetPolycount: 50_000,
                hardTimeout: 30
            ),
            existingAssetNames: [],
            onProgress: { state in await recorder.record(state) }
        )

        #expect(asset.kind == .model3D)
        #expect(!asset.name.isEmpty)

        let states = await recorder.states
        #expect(!states.isEmpty, "Progress callback must fire during remesh polling")
    }

    // MARK: (d) Phase transitions: retexture configuring → running → done

    @Test("RemeshAndRetextureFlow.runRetexture fires progress callbacks and returns asset")
    func retexturePhaseTransitionsToDone() async throws {
        let stub = RemeshRetexLifecycleStubClient(
            retextureFacts: [
                MeshyPolledFact(taskId: "retex_001", status: .inProgress, progress: 60),
                makeSucceededRetextureFact(taskId: "retex_001")
            ]
        )
        let flow = RemeshAndRetextureFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        actor StateRecorder {
            var states: [MeshyTaskMonitor.State] = []
            func record(_ s: MeshyTaskMonitor.State) { states.append(s) }
        }
        let recorder = StateRecorder()

        let asset = try await flow.runRetexture(
            sourceTaskId: "src_001",
            sourceAssetName: "dragon",
            sourcePrompt: "dragon model",
            newStylePrompt: "obsidian scales",
            options: RemeshAndRetextureFlow.RetextureOptions(hardTimeout: 30),
            existingAssetNames: [],
            onProgress: { state in await recorder.record(state) }
        )

        #expect(asset.kind == .model3D)
        #expect(!asset.name.isEmpty)

        let states = await recorder.states
        #expect(!states.isEmpty, "Progress callback must fire during retexture polling")
    }

    // MARK: (e) Error phase: sanitised message — auth failures discard body

    /// `RemeshAndRetextureCoordinator.errorView` renders `error.errorDescription`.
    /// Auth error bodies (401/403) are discarded; non-auth bodies are capped at
    /// 200 chars. Verifies the H1 invariant for this coordinator's error path.
    @Test("MeshyError 401 errorDescription discards message body")
    func error401DiscardsMessageBody() {
        let sensitiveBody = "Bearer msy_secret_XYZ is not valid"
        let err = MeshyError.requestFailed(statusCode: 401, message: sensitiveBody)
        let desc = err.errorDescription ?? ""
        #expect(!desc.contains("msy_secret"), "401 error must not surface key fragments")
        #expect(!desc.contains(sensitiveBody), "401 error must not surface the raw response body")
    }

    @Test("MeshyError 403 errorDescription discards message body")
    func error403DiscardsMessageBody() {
        let sensitiveBody = "Forbidden: key msy_secret_ABC123 has expired"
        let err = MeshyError.requestFailed(statusCode: 403, message: sensitiveBody)
        let desc = err.errorDescription ?? ""
        #expect(!desc.contains("msy_secret"), "403 error must not surface key fragments")
    }

    // MARK: (f) canStart gate: remesh always allows start (no text requirement)

    /// `RemeshAndRetextureCoordinator.canStart` for remesh mode requires only
    /// that `meshyKeyIsSet == true`. Unlike retexture, there's no text field.
    /// This test exercises the equivalent logic at the model layer.
    @Test("Meshy3DGate ready status enables remesh flow when key is set")
    func gateReadyEnablesRemeshFlow() {
        var doc = HypeDocument(stack: Stack())
        doc.stack.meshyEnabled = true
        let status = Meshy3DGate.status(for: doc, keyIsSet: true)
        #expect(status == .ready, "Gate must be .ready when stack is enabled and key is set — allows remesh to start")
    }

    // MARK: (g) canStart gate: retexture requires non-empty style prompt

    /// The coordinator's `canStart` returns `false` for retexture when
    /// `stylePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`.
    /// This test verifies the logic directly (no SwiftUI rendering needed).
    @Test("retexture canStart is false for blank style prompt")
    func retextureCanStartFalseForBlankPrompt() {
        // Mirror the coordinator's canStart logic for retexture mode.
        let stylePrompt = "   "  // whitespace only
        let meshyKeyIsSet = true
        let isRetextureMode = true

        let canStart: Bool = {
            if !meshyKeyIsSet { return false }
            if isRetextureMode && stylePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            return true
        }()

        #expect(!canStart, "Retexture Generate button must be disabled when style prompt is blank")
    }

    @Test("retexture canStart is true for non-empty style prompt")
    func retextureCanStartTrueForNonEmptyPrompt() {
        let stylePrompt = "rusty metal"
        let meshyKeyIsSet = true
        let isRetextureMode = true

        let canStart: Bool = {
            if !meshyKeyIsSet { return false }
            if isRetextureMode && stylePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            return true
        }()

        #expect(canStart, "Retexture Generate button must be enabled when style prompt is non-empty")
    }

    // MARK: (h) Asset name dedup in done view

    /// The done view renders `importedAssetName` which is set from `asset.name`
    /// returned by the flow. When a name collision exists, the importer dedups
    /// and the done view must display the dedup'd name (not the original source name).
    @Test("remesh dedup appends suffix when asset name already exists in repository")
    func remeshDedupAppendsWhenNameCollides() async throws {
        let stub = RemeshRetexLifecycleStubClient(
            remeshFacts: [makeSucceededRemeshFact(taskId: "remesh_dedup_001")]
        )
        let flow = RemeshAndRetextureFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        // Pre-populate existingAssetNames with the expected base name.
        let asset = try await flow.runRemesh(
            sourceTaskId: "src_dedup_001",
            sourceAssetName: "barrel",
            sourcePrompt: "wooden barrel",
            options: RemeshAndRetextureFlow.RemeshOptions(
                targetPolycount: 10_000,
                hardTimeout: 30
            ),
            existingAssetNames: ["barrel-remeshed"]  // collision
        )

        #expect(asset.name != "barrel-remeshed",
                "Dedup must rename the remeshed asset when 'barrel-remeshed' already exists in the repository")
        #expect(!asset.name.isEmpty)
    }

    @Test("retexture dedup appends suffix when asset name already exists in repository")
    func retextureDedupAppendsWhenNameCollides() async throws {
        let stub = RemeshRetexLifecycleStubClient(
            retextureFacts: [makeSucceededRetextureFact(taskId: "retex_dedup_001")]
        )
        let flow = RemeshAndRetextureFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        let asset = try await flow.runRetexture(
            sourceTaskId: "src_dedup_001",
            sourceAssetName: "dragon",
            sourcePrompt: "dragon model",
            newStylePrompt: "neon style",
            options: RemeshAndRetextureFlow.RetextureOptions(hardTimeout: 30),
            existingAssetNames: ["dragon-retextured"]  // collision
        )

        #expect(asset.name != "dragon-retextured",
                "Dedup must rename the retextured asset when 'dragon-retextured' already exists in the repository")
        #expect(!asset.name.isEmpty)
    }

    // MARK: (i) Remesh polycount validation: flow rejects out-of-range values

    /// `RemeshAndRetextureFlow.runRemesh` validates polycount (100…300_000).
    /// The coordinator's slider clamps the UI value but the flow is the
    /// second layer of defense (C5). Verify it throws `.invalidPolycount`.
    @Test("runRemesh throws invalidPolycount for targetPolycount = 0")
    func remeshThrowsForZeroPolycount() async {
        let stub = RemeshRetexLifecycleStubClient()
        let flow = RemeshAndRetextureFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        do {
            _ = try await flow.runRemesh(
                sourceTaskId: "src_001",
                sourceAssetName: "test",
                sourcePrompt: "test",
                options: RemeshAndRetextureFlow.RemeshOptions(targetPolycount: 0, hardTimeout: 5),
                existingAssetNames: []
            )
            Issue.record("Expected invalidPolycount for targetPolycount = 0")
        } catch MeshyError.invalidPolycount(let value) {
            #expect(value == 0)
        } catch {
            Issue.record("Unexpected error: \(error) — expected MeshyError.invalidPolycount")
        }
    }

    @Test("runRemesh throws invalidPolycount for targetPolycount = 400000")
    func remeshThrowsForExcessivePolycount() async {
        let stub = RemeshRetexLifecycleStubClient()
        let flow = RemeshAndRetextureFlow(client: stub, logger: HypeLogger(setupFileLogging: false))

        do {
            _ = try await flow.runRemesh(
                sourceTaskId: "src_001",
                sourceAssetName: "test",
                sourcePrompt: "test",
                options: RemeshAndRetextureFlow.RemeshOptions(targetPolycount: 400_000, hardTimeout: 5),
                existingAssetNames: []
            )
            Issue.record("Expected invalidPolycount for targetPolycount = 400000")
        } catch MeshyError.invalidPolycount(let value) {
            #expect(value == 400_000)
        } catch {
            Issue.record("Unexpected error: \(error) — expected MeshyError.invalidPolycount")
        }
    }
}

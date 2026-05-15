import Foundation
import Testing
@testable import HypeCore

// MARK: - Stub MeshyClient

/// Immediate-success stub for AIEditTransaction integration tests.
private actor TransactionStubMeshyClient: MeshyClient {
    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String { "stub_text" }
    func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String { "stub_image" }
    func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String { "stub_multi" }
    func createRiggingTask(_ request: MeshyRiggingRequest) async throws -> String { "stub_rig" }
    func createAnimationTask(_ request: MeshyAnimationRequest) async throws -> String { "stub_anim" }
    func createRemeshTask(_ request: MeshyRemeshRequest) async throws -> String { "stub_remesh" }
    func createRetextureTask(_ request: MeshyRetextureRequest) async throws -> String { "stub_retex" }
    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        MeshyPolledFact(
            taskId: taskId,
            status: .succeeded,
            progress: 100,
            primaryModelUrl: URL(string: "https://cdn.meshy.ai/model.glb")!
        )
    }
    /// Security (H1): all seven kinds listed explicitly; no default.
    func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {
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

private func makeDocument(meshyEnabled: Bool = false) -> HypeDocument {
    var stack = Stack()
    stack.meshyEnabled = meshyEnabled
    return HypeDocument(stack: stack)
}

private func makeRunner(meshyEnabled: Bool = false) -> AIEditTransactionRunner {
    let stub = TransactionStubMeshyClient()
    let executor = HypeToolExecutor(
        webAssetSession: nil,
        webAssetClient: nil,
        webAssetPipeline: nil,
        imageGenerationClient: nil,
        meshyClientFactory: { @Sendable in stub }
    )
    return AIEditTransactionRunner(executor: executor)
}

// MARK: - Tests

/// Integration tests for `AIEditTransactionRunner` behavior when the
/// 3-D model generation tools are involved.
///
/// Specifically:
/// - `delta.spriteRepositoryChanged` is `true` when a 3-D asset is added.
/// - `rollback` restores the repository to its pre-preview count.
/// - `apply` preserves all assets added during preview.
///
/// These complement the core `AIEditTransactionTests` (which use
/// generic `create_button`/`create_field` tool calls).
@Suite("AIEditTransactionRunner — 3D model tool integration")
struct MeshyToolAIEditTransactionTests {

    // MARK: (a) Meshy generation is deferred until apply

    /// Preview must not call Meshy or mutate the Sprite Repository. Meshy
    /// generation is an external, billable side effect, so it is represented as
    /// a deferred operation until apply.
    @Test("preview: Meshy generation is deferred and does not change repository")
    func previewDefersMeshyGenerationNoRepositoryChange() async {
        let document = makeDocument(meshyEnabled: false)
        let cardId = document.sortedCards.first?.id ?? UUID()
        let runner = makeRunner(meshyEnabled: false)

        let call = OllamaToolCall(function: OllamaToolCallFunction(
            name: "generate_3d_model_from_text",
            arguments: ["prompt": "a barrel"]
        ))

        let transaction = await runner.preview(
            toolCalls: [call],
            document: document,
            currentCardId: cardId,
            prompt: "Generate a 3D barrel",
            providerName: "Test"
        )

        #expect(transaction.delta.spriteRepositoryChanged == false)
        #expect(document.spriteRepository.assets.isEmpty)
        let previewModels = transaction.previewDocument.spriteRepository.assets.filter { $0.kind == .model3D }
        #expect(previewModels.isEmpty)
        #expect(transaction.operations.first?.phase == .deferredExternalApply)
        #expect(transaction.operations.first?.result.contains("Deferred external operation") == true)
    }

    @Test("sync apply refuses transactions with deferred Meshy operations")
    func syncApplyRefusesDeferredExternalOperations() async {
        var document = makeDocument(meshyEnabled: false)
        let cardId = document.sortedCards.first?.id ?? UUID()
        let runner = makeRunner(meshyEnabled: false)
        let call = OllamaToolCall(function: OllamaToolCallFunction(
            name: "generate_3d_model_from_text",
            arguments: ["prompt": "a barrel"]
        ))

        var transaction = await runner.preview(
            toolCalls: [call],
            document: document,
            currentCardId: cardId,
            prompt: "Generate a 3D barrel",
            providerName: "Test"
        )
        runner.apply(&transaction, to: &document)

        #expect(transaction.state == .failed)
        #expect(document.spriteRepository.assets.isEmpty)
        #expect(transaction.diagnostics.contains { $0.contains("async apply") })
    }

    // MARK: (b) rollback restores repository asset count

    /// After a preview that adds a model3D asset directly at the model layer,
    /// calling `rollback` must restore the document to its pre-preview state.
    @Test("rollback restores repository asset count to pre-preview state")
    func rollbackRestoresAssetCount() {
        var document = makeDocument()
        let runner = AIEditTransactionRunner()

        // Pre-populate the repository to create a non-empty baseline.
        let existing = SpriteAsset(name: "existing.glb", kind: .model3D,
                                   mimeType: "model/gltf-binary",
                                   data: Data(repeating: 0x47, count: 64),
                                   width: 0, height: 0)
        document.spriteRepository.addAsset(existing)
        let baselineCount = document.spriteRepository.assets.count

        // Simulate a preview that adds an asset to the repository
        // (as Generate3DJob does when it fires).  We do this by constructing
        // a transaction directly rather than calling preview with a real tool,
        // since the test environment has no Meshy key.
        var previewDoc = document
        let newAsset = SpriteAsset(name: "new-model.glb", kind: .model3D,
                                   mimeType: "model/gltf-binary",
                                   data: Data(repeating: 0x42, count: 64),
                                   width: 0, height: 0)
        previewDoc.spriteRepository.addAsset(newAsset)

        let delta = AIEditTransactionRunner.delta(from: document, to: previewDoc)
        var transaction = AIEditTransaction(
            prompt: "test",
            providerName: "Test",
            state: .preview,
            rollbackDocument: document,
            previewDocument: previewDoc,
            operations: [],
            delta: delta
        )

        // Confirm delta reports the repository changed.
        #expect(transaction.delta.spriteRepositoryChanged == true)

        // Apply then rollback.
        runner.apply(&transaction, to: &document)
        #expect(document.spriteRepository.assets.count == baselineCount + 1)

        runner.rollback(&transaction, to: &document)
        #expect(document.spriteRepository.assets.count == baselineCount)
        #expect(transaction.state == .rolledBack)
    }

    // MARK: (c) apply preserves all assets from preview

    /// After `apply`, the document must contain all assets from the preview.
    @Test("apply preserves all assets added during preview")
    func applyPreservesAssets() {
        var document = makeDocument()
        let runner = AIEditTransactionRunner()

        // Build a preview document with two model3D assets.
        var previewDoc = document
        let assetA = SpriteAsset(name: "modelA.glb", kind: .model3D,
                                 mimeType: "model/gltf-binary",
                                 data: Data(repeating: 0x41, count: 64),
                                 width: 0, height: 0)
        let assetB = SpriteAsset(name: "modelB.glb", kind: .model3D,
                                 mimeType: "model/gltf-binary",
                                 data: Data(repeating: 0x42, count: 64),
                                 width: 0, height: 0)
        previewDoc.spriteRepository.addAsset(assetA)
        previewDoc.spriteRepository.addAsset(assetB)

        let delta = AIEditTransactionRunner.delta(from: document, to: previewDoc)
        var transaction = AIEditTransaction(
            prompt: "test",
            providerName: "Test",
            state: .preview,
            rollbackDocument: document,
            previewDocument: previewDoc,
            operations: [],
            delta: delta
        )

        #expect(transaction.delta.spriteRepositoryChanged == true)

        runner.apply(&transaction, to: &document)
        #expect(transaction.state == .applied)
        let models = document.spriteRepository.assets.filter { $0.kind == .model3D }
        #expect(models.count == 2)
        #expect(models.contains(where: { $0.name == "modelA.glb" }))
        #expect(models.contains(where: { $0.name == "modelB.glb" }))
    }

    // MARK: (d) delta computed from before/after correctly identifies spriteRepositoryChanged

    @Test("AIEditTransactionRunner.delta flags spriteRepositoryChanged correctly")
    func deltaFlagsSpriteRepositoryChanged() {
        let before = makeDocument()
        var after = before

        // Before: no change flag.
        let noDeltaChange = AIEditTransactionRunner.delta(from: before, to: after)
        #expect(noDeltaChange.spriteRepositoryChanged == false)

        // After adding an asset: changed flag.
        let newAsset = SpriteAsset(name: "barrel.glb", kind: .model3D,
                                   mimeType: "model/gltf-binary",
                                   data: Data(repeating: 0x47, count: 64),
                                   width: 0, height: 0)
        after.spriteRepository.addAsset(newAsset)

        let withDelta = AIEditTransactionRunner.delta(from: before, to: after)
        #expect(withDelta.spriteRepositoryChanged == true)
    }

    // MARK: (e) list_3d_models tool yields no repository change

    @Test("list_3d_models preview does not change spriteRepositoryChanged delta")
    func listModelsNoDelta() async {
        let document = makeDocument()
        let cardId = document.sortedCards.first?.id ?? UUID()
        let runner = AIEditTransactionRunner()

        let call = OllamaToolCall(function: OllamaToolCallFunction(
            name: "list_3d_models",
            arguments: [:]
        ))

        let transaction = await runner.preview(
            toolCalls: [call],
            document: document,
            currentCardId: cardId,
            prompt: "List 3D models",
            providerName: "Test"
        )

        // list_3d_models is read-only — repository must not change.
        #expect(transaction.delta.spriteRepositoryChanged == false)
        #expect(transaction.previewDocument.spriteRepository.assets.count
                == document.spriteRepository.assets.count)
    }
}

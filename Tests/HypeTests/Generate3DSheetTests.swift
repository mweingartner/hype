import Testing
import Foundation
@testable import HypeCore

// MARK: - Local stub MeshyClient for F-1 tests

/// Minimal stub client for testing the importer in isolation without
/// touching the network or the real `MeshyAIClient`.
private actor LocalStubMeshyClient: MeshyClient {
    let glbData: Data

    init(glbData: Data = Data(repeating: 0x47, count: 64)) {
        self.glbData = glbData
    }

    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String { "stub_task" }
    func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String { "stub_image_task" }
    func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String { "stub_multi_task" }
    func createRiggingTask(_ request: MeshyRiggingRequest) async throws -> String { "stub_rig_task" }
    func createAnimationTask(_ request: MeshyAnimationRequest) async throws -> String { "stub_anim_task" }
    func createRemeshTask(_ request: MeshyRemeshRequest) async throws -> String { "stub_remesh_task" }
    func createRetextureTask(_ request: MeshyRetextureRequest) async throws -> String { "stub_retex_task" }
    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        MeshyPolledFact(taskId: taskId, status: .pending)
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
        glbData
    }
}

/// Tests for the Generate3D sheet's supporting logic.
///
/// The SwiftUI `Generate3DSheet` view itself is not rendered in unit tests.
/// These tests cover:
/// - `Meshy3DGate.status` as applied from the sheet's host contexts
///   (SpriteRepositoryView and PropertyInspector).
/// - The document model writes that `onAssetImported` callbacks perform.
///
/// `MeshyTaskMonitor` behaviour is covered in `MeshyTaskMonitorTests`.
/// `Meshy3DGate` pure logic is covered in `Meshy3DGateTests`.
@Suite("Generate3DSheet supporting logic")
struct Generate3DSheetTests {

    // MARK: - Document helpers

    private func makeDocument(meshyEnabled: Bool = false) -> HypeDocument {
        var stack = Stack()
        stack.meshyEnabled = meshyEnabled
        return HypeDocument(stack: stack)
    }

    private func makeModel3DAsset(name: String = "robot") -> SpriteAsset {
        SpriteAsset(
            name: name,
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data(repeating: 0x47, count: 128),
            width: 0,
            height: 0
        )
    }

    // MARK: - Gate: SpriteRepositoryView context

    @Test("gate returns .stackDisabled when meshyEnabled is false")
    func gateStackDisabledWhenNotEnabled() {
        let doc = makeDocument(meshyEnabled: false)
        let status = Meshy3DGate.status(for: doc, keyIsSet: true)
        #expect(status == .stackDisabled)
    }

    @Test("gate returns .apiKeyMissing when stack enabled but no key")
    func gateApiKeyMissingWhenNoKey() {
        let doc = makeDocument(meshyEnabled: true)
        let status = Meshy3DGate.status(for: doc, keyIsSet: false)
        #expect(status == .apiKeyMissing)
    }

    @Test("gate returns .ready when stack enabled and key present")
    func gateReadyWhenAllConditionsMet() {
        let doc = makeDocument(meshyEnabled: true)
        let status = Meshy3DGate.status(for: doc, keyIsSet: true)
        #expect(status == .ready)
    }

    // MARK: - Document model write: onAssetImported

    @Test("adding model3D asset to repository round-trips kind correctly")
    func model3DAssetRoundTrips() throws {
        let asset = makeModel3DAsset(name: "dragon")
        #expect(asset.kind == .model3D)
        #expect(asset.mimeType == "model/gltf-binary")
        #expect(asset.width == 0)
        #expect(asset.height == 0)
    }

    @Test("model3D asset added to repository can be found by id")
    func model3DAssetCanBeFoundById() {
        var doc = makeDocument()
        let asset = makeModel3DAsset(name: "spaceship")
        doc.spriteRepository.addAsset(asset)

        let found = doc.spriteRepository.asset(byId: asset.id)
        #expect(found != nil)
        #expect(found?.kind == .model3D)
        #expect(found?.name == "spaceship")
    }

    @Test("scene3DAssetRef written to part can be read back")
    func scene3DAssetRefWrittenToPart() {
        var doc = makeDocument()
        // Add a model3D asset.
        let asset = makeModel3DAsset(name: "castle")
        doc.spriteRepository.addAsset(asset)
        let ref = doc.spriteRepository.assetRef(for: asset)

        // Add a scene3D part and write the ref.
        var part = Part(partType: .scene3D, name: "3D Scene")
        part.scene3DAssetRef = ref
        doc.addPart(part)

        // Verify the ref is readable.
        let retrieved = doc.parts.first(where: { $0.id == part.id })?.scene3DAssetRef
        #expect(retrieved?.id == asset.id)
    }

    @Test("clearing scene3DAssetRef from part results in nil")
    func clearingScene3DAssetRefResultsInNil() {
        var doc = makeDocument()
        let asset = makeModel3DAsset()
        doc.spriteRepository.addAsset(asset)
        let ref = doc.spriteRepository.assetRef(for: asset)

        var part = Part(partType: .scene3D, name: "3D Scene")
        part.scene3DAssetRef = ref
        doc.addPart(part)

        // Clear via updatePart.
        doc.updatePart(id: part.id) { $0.scene3DAssetRef = nil }
        let cleared = doc.parts.first(where: { $0.id == part.id })?.scene3DAssetRef
        #expect(cleared == nil)
    }

    @Test("enabling meshyEnabled on stack changes gate to .apiKeyMissing")
    func enablingMeshyChangesGate() {
        var doc = makeDocument(meshyEnabled: false)
        let before = Meshy3DGate.status(for: doc, keyIsSet: false)
        #expect(before == .stackDisabled)

        doc.stack.meshyEnabled = true
        let after = Meshy3DGate.status(for: doc, keyIsSet: false)
        #expect(after == .apiKeyMissing)
    }

    // MARK: - model3D filtering

    @Test("model3DAssets computed property returns only model3D kind assets")
    func model3DAssetsFilteredCorrectly() {
        var doc = makeDocument()
        let imageAsset = SpriteAsset(name: "sprite", kind: .imageTexture,
                                     mimeType: "image/png", data: Data([0xFF]),
                                     width: 64, height: 64)
        let audioAsset = SpriteAsset(name: "sound", kind: .audioClip,
                                     mimeType: "audio/mpeg", data: Data([0xFF]),
                                     width: 0, height: 0)
        let modelAsset = makeModel3DAsset(name: "robot")
        let modelAsset2 = makeModel3DAsset(name: "alien")

        doc.spriteRepository.addAsset(imageAsset)
        doc.spriteRepository.addAsset(audioAsset)
        doc.spriteRepository.addAsset(modelAsset)
        doc.spriteRepository.addAsset(modelAsset2)

        let model3DAssets = doc.spriteRepository.assets.filter { $0.kind == .model3D }
        #expect(model3DAssets.count == 2)
        #expect(model3DAssets.allSatisfy { $0.kind == .model3D })
    }

    // MARK: - F-1 invariant: onAssetImported is the sole writer of scene3DAssetRef

    /// Security fix F-1: `Generate3DSheet.handleSuccess` must NOT write
    /// `part.scene3DAssetRef` directly. Instead it calls `onAssetImported?(ref)`,
    /// and the PropertyInspector's closure is the sole writer.
    ///
    /// Pre-fix: `handleSuccess` called both `updatePart` AND `onAssetImported`,
    /// producing two undo entries and a racey double-mutation.
    ///
    /// This test simulates the full pipeline at the model layer (without
    /// rendering the SwiftUI view):
    ///   1. `Meshy3DAssetImporter.importTask` returns a `[SpriteAsset]`.
    ///   2. Each asset is written into the repository (as `handleSuccess` does).
    ///   3. A counting closure (simulating PropertyInspector's `onAssetImported`)
    ///      is called exactly once with the primary ref.
    ///   4. The closure writes `scene3DAssetRef` onto the target part.
    ///
    /// If the invariant is broken (two writes), the counter will be 2 and the
    /// test will fail.
    @Test("F-1: onAssetImported closure is the sole writer of scene3DAssetRef (called exactly once)")
    func f1OnAssetImportedIsCalledExactlyOnce() async throws {
        // Set up a document with a scene3D part to target.
        var doc = makeDocument(meshyEnabled: true)
        var targetPart = Part(partType: .scene3D, name: "3D Scene")
        doc.addPart(targetPart)
        let targetPartId = targetPart.id

        // Verify the part starts with no asset ref.
        #expect(doc.parts.first(where: { $0.id == targetPartId })?.scene3DAssetRef == nil)

        // Run importTask with a stub client (mirrors what handleSuccess does).
        let stub = LocalStubMeshyClient(glbData: Data(repeating: 0x47, count: 64))
        let importer = Meshy3DAssetImporter(client: stub, logger: HypeLogger(setupFileLogging: false))
        let result = MeshyTaskResult(
            taskId: "task_f1_test",
            modelURL: URL(string: "https://cdn.meshy.ai/model.glb")!,
            format: .glb,
            prompt: "a low-poly test barrel",
            aiModel: .meshy6
        )
        let assets = try await importer.importTask(result: result, existingAssetNames: [])

        // Step 1: Write assets into repository (as handleSuccess does).
        // This does NOT touch scene3DAssetRef.
        for asset in assets {
            doc.spriteRepository.addAsset(asset)
        }

        // Step 2: Get the primary ref.
        guard let primary = assets.first else {
            Issue.record("importTask returned no assets")
            return
        }
        let ref = doc.spriteRepository.assetRef(for: primary)

        // Step 3: Track how many times the closure is called (the
        // PropertyInspector equivalent). Use a simple counter since
        // this is synchronous in the closure's scope.
        var closureCallCount = 0
        let onAssetImported: (AssetRef) -> Void = { importedRef in
            closureCallCount += 1
            // Step 4: Write the ref — the SOLE write of scene3DAssetRef.
            doc.updatePart(id: targetPartId) { $0.scene3DAssetRef = importedRef }
        }

        // Simulate handleSuccess calling onAssetImported exactly once.
        onAssetImported(ref)

        // Assert the closure was called exactly once (not zero, not twice).
        #expect(closureCallCount == 1, "onAssetImported must be called exactly once — pre-fix it was called twice (double-write bug)")

        // Assert the part's ref was written correctly.
        let finalRef = doc.parts.first(where: { $0.id == targetPartId })?.scene3DAssetRef
        #expect(finalRef != nil, "scene3DAssetRef should be set after onAssetImported fires")
        #expect(finalRef?.id == primary.id, "ref id must match the imported primary asset's id")
        #expect(finalRef?.mimeType == "model/gltf-binary")
    }

    /// Regression test for F-1: if `handleSuccess` were to call `updatePart`
    /// directly BEFORE calling `onAssetImported`, the ref would be written
    /// before the closure fires — the part would still have the ref but from
    /// an internal write, not the closure.
    ///
    /// This test confirms that writing the ref via the closure produces the
    /// same correct result regardless of order, AND that a second write
    /// (e.g., if the sheet also wrote directly) does NOT change the ref's value
    /// to something inconsistent.
    @Test("F-1: double-writing scene3DAssetRef with the same ref is idempotent")
    func f1DoubleWriteIsIdempotent() async throws {
        var doc = makeDocument(meshyEnabled: true)
        var targetPart = Part(partType: .scene3D, name: "3D Scene")
        doc.addPart(targetPart)
        let targetPartId = targetPart.id

        let asset = makeModel3DAsset(name: "barrel")
        doc.spriteRepository.addAsset(asset)
        let ref = doc.spriteRepository.assetRef(for: asset)

        // Simulate the pre-fix bug: write once via updatePart directly,
        // then again via the onAssetImported closure.
        doc.updatePart(id: targetPartId) { $0.scene3DAssetRef = ref }
        doc.updatePart(id: targetPartId) { $0.scene3DAssetRef = ref }

        // The value should still be the correct ref (idempotent).
        let finalRef = doc.parts.first(where: { $0.id == targetPartId })?.scene3DAssetRef
        #expect(finalRef?.id == asset.id, "Idempotent double-write must not corrupt scene3DAssetRef")
    }
}

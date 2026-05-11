import Foundation
import Testing
@testable import HypeCore

// MARK: - Stub client for importer tests

actor ImporterStubClient: MeshyClient {
    private let glbData: Data?
    private let usdzData: Data?
    private let fbxData: Data?
    private let shouldFailGLB: Bool

    init(
        glbData: Data? = Data(repeating: 0x47, count: 64),
        usdzData: Data? = nil,
        fbxData: Data? = nil,
        shouldFailGLB: Bool = false
    ) {
        self.glbData = glbData
        self.usdzData = usdzData
        self.fbxData = fbxData
        self.shouldFailGLB = shouldFailGLB
    }

    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String { "stub_id" }
    func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String { "stub_image_id" }
    func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String { "stub_multi_id" }
    func createRiggingTask(_ request: MeshyRiggingRequest) async throws -> String { "stub_rig_id" }
    func createAnimationTask(_ request: MeshyAnimationRequest) async throws -> String { "stub_anim_id" }
    func createRemeshTask(_ request: MeshyRemeshRequest) async throws -> String { "stub_remesh_id" }
    func createRetextureTask(_ request: MeshyRetextureRequest) async throws -> String { "stub_retex_id" }
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
        switch allowedFormat {
        case .glb:
            if shouldFailGLB { throw MeshyError.modelDownloadFailed("GLB intentionally failed") }
            return glbData ?? Data()
        case .usdz:
            if let d = usdzData { return d }
            throw MeshyError.modelDownloadFailed("no USDZ")
        case .fbx:
            if let d = fbxData { return d }
            throw MeshyError.modelDownloadFailed("no FBX")
        }
    }
}

private func makeResult(
    taskId: String = "t1",
    prompt: String = "a low-poly barrel",
    alsoUSDZ: URL? = nil,
    alsoFBX: URL? = nil
) -> MeshyTaskResult {
    MeshyTaskResult(
        taskId: taskId,
        modelURL: URL(string: "https://cdn.meshy.ai/model.glb")!,
        format: .glb,
        alsoUSDZ: alsoUSDZ,
        alsoFBX: alsoFBX,
        prompt: prompt,
        aiModel: .meshy6
    )
}

// MARK: - Tests

@Suite("Meshy3DAssetImporter")
struct Meshy3DAssetImporterTests {

    // MARK: (a) buildAsset produces correct kind, mimeType, provenance

    @Test("buildAsset produces model3D kind with correct mimeType and provenance")
    func buildAssetShape() {
        let provenance = AssetProvenance(
            origin: .aiGenerated,
            searchQuery: "a barrel",
            license: AssetLicense(name: "Meshy.ai", identifier: "meshy", url: "https://docs.meshy.ai", isShareable: false),
            attribution: AssetAttribution(creator: "AI", title: "a barrel", sourceURL: "", downloadURL: "", providerName: "Meshy.ai", providerIdentifier: "meshy")
        )
        let asset = Meshy3DAssetImporter.buildAsset(
            from: Data(repeating: 0x42, count: 64),
            format: .glb,
            suggestedName: "barrel.glb",
            existingNames: [],
            provenance: provenance
        )

        #expect(asset.kind == .model3D)
        #expect(asset.mimeType == "model/gltf-binary")
        #expect(asset.name == "barrel.glb")
        #expect(asset.tags.contains("meshy"))
        #expect(asset.tags.contains("ai-generated"))
        #expect(asset.provenance?.origin == .aiGenerated)
        #expect(asset.provenance?.attribution.providerName == "Meshy.ai")
        #expect(asset.width == 0)
        #expect(asset.height == 0)
    }

    // MARK: (b) name dedup against existingNames

    @Test("buildAsset deduplicates name with space+counter suffix")
    func nameDeduplicate() {
        let provenance = AssetProvenance(origin: .aiGenerated)
        let existing: Set<String> = ["barrel.glb", "barrel 2.glb"]
        let asset = Meshy3DAssetImporter.buildAsset(
            from: Data([1, 2, 3]),
            format: .glb,
            suggestedName: "barrel.glb",
            existingNames: existing,
            provenance: provenance
        )
        #expect(asset.name == "barrel 3.glb")
    }

    // MARK: (c) importTask with GLB-only returns one asset

    @Test("importTask with GLB-only returns exactly one asset")
    func importGLBOnly() async throws {
        let stub = ImporterStubClient(glbData: Data(repeating: 0x47, count: 64))
        let importer = Meshy3DAssetImporter(client: stub, logger: HypeLogger(setupFileLogging: false))
        let result = makeResult(prompt: "a low-poly barrel")
        let assets = try await importer.importTask(result: result, existingAssetNames: [])
        #expect(assets.count == 1)
        #expect(assets[0].kind == .model3D)
        #expect(assets[0].mimeType == "model/gltf-binary")
    }

    // MARK: (d) importTask with GLB+USDZ returns two assets

    @Test("importTask with GLB+USDZ returns two assets")
    func importGLBAndUSDZ() async throws {
        let stub = ImporterStubClient(
            glbData: Data(repeating: 0x47, count: 64),
            usdzData: Data(repeating: 0x55, count: 32)
        )
        let importer = Meshy3DAssetImporter(client: stub, logger: HypeLogger(setupFileLogging: false))
        let result = makeResult(
            prompt: "wooden crate",
            alsoUSDZ: URL(string: "https://cdn.meshy.ai/model.usdz")!
        )
        let assets = try await importer.importTask(result: result, existingAssetNames: [])
        #expect(assets.count == 2)
        let formats = assets.map(\.mimeType)
        #expect(formats.contains("model/gltf-binary"))
        #expect(formats.contains("model/vnd.usdz+zip"))
    }

    // MARK: (e) importTask where GLB download fails throws

    @Test("importTask where GLB download fails throws")
    func importGLBFailThrows() async throws {
        let stub = ImporterStubClient(shouldFailGLB: true)
        let importer = Meshy3DAssetImporter(client: stub, logger: HypeLogger(setupFileLogging: false))
        let result = makeResult()
        var threw = false
        do {
            _ = try await importer.importTask(result: result, existingAssetNames: [])
        } catch {
            threw = true
        }
        #expect(threw, "Expected GLB failure to throw")
    }

    // MARK: (f) importTask where optional USDZ fails returns GLB-only set

    @Test("importTask where optional USDZ fails returns GLB-only without throwing")
    func importOptionalUSDZFail() async throws {
        // usdzData = nil → stub throws for USDZ
        let stub = ImporterStubClient(glbData: Data(repeating: 0x47, count: 64), usdzData: nil)
        let importer = Meshy3DAssetImporter(client: stub, logger: HypeLogger(setupFileLogging: false))
        let result = makeResult(
            alsoUSDZ: URL(string: "https://cdn.meshy.ai/model.usdz")!
        )
        let assets = try await importer.importTask(result: result, existingAssetNames: [])
        // Should get only the GLB — USDZ failure is non-fatal.
        #expect(assets.count == 1)
        #expect(assets[0].mimeType == "model/gltf-binary")
    }
}

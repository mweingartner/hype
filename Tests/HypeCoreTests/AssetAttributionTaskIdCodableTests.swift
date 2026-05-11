import Foundation
import Testing
@testable import HypeCore

/// Tests that `AssetAttribution.taskId` round-trips correctly and that
/// `Meshy3DAssetImporter` populates it on every generated asset (Phase 3).
@Suite("AssetAttribution — taskId Codable and Meshy3DAssetImporter population")
struct AssetAttributionTaskIdCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: (a) taskId round-trips through Codable

    @Test("AssetAttribution taskId round-trips via Codable")
    func taskIdRoundTrips() throws {
        let attribution = AssetAttribution(
            creator: "Meshy.ai",
            title: "Generated Model",
            sourceURL: "https://api.meshy.ai/openapi/v2/text-to-3d/task_abc",
            downloadURL: "https://assets.meshy.ai/models/task_abc.glb",
            providerName: "Meshy.ai",
            providerIdentifier: "meshy",
            taskId: "task_abc_123"
        )
        let data = try encoder.encode(attribution)
        let decoded = try decoder.decode(AssetAttribution.self, from: data)

        #expect(decoded.taskId == "task_abc_123")
        #expect(decoded.providerIdentifier == "meshy")
    }

    // MARK: (b) Old documents decode with taskId = ""

    @Test("Legacy JSON without taskId decodes with taskId = empty string (backward compat)")
    func legacyJsonDecodesWithEmptyTaskId() throws {
        // Old AssetAttribution JSON without the taskId field.
        let legacyJson = """
        {
          "creator": "Openverse",
          "title": "An old asset",
          "sourceURL": "https://openverse.org/asset/abc",
          "downloadURL": "https://cdn.openverse.org/abc.png",
          "providerName": "Openverse",
          "providerIdentifier": "openverse"
        }
        """.data(using: .utf8)!

        let attribution = try decoder.decode(AssetAttribution.self, from: legacyJson)
        #expect(attribution.taskId == "",
                "Pre-Phase-3 documents must decode taskId as empty string (backward compat)")
    }

    // MARK: (c) Meshy3DAssetImporter populates taskId on generated assets

    @Test("Meshy3DAssetImporter populates provenance.attribution.taskId for generated assets")
    func importerPopulatesTaskId() async throws {
        // Test via the full import pipeline with a stub client. This verifies
        // that `makeProvenance(result:)` wires through `result.taskId` into
        // the returned asset's `provenance.attribution.taskId`.

        actor TaskIdStubClient: MeshyClient {
            func createTextTo3DTask(_ r: MeshyTextTo3DRequest) async throws -> String { "t" }
            func createImageTo3DTask(_ r: MeshyImageTo3DRequest) async throws -> String { "i" }
            func createMultiImageTo3DTask(_ r: MeshyMultiImageTo3DRequest) async throws -> String { "mi" }
            func createRiggingTask(_ r: MeshyRiggingRequest) async throws -> String { "rg" }
            func createAnimationTask(_ r: MeshyAnimationRequest) async throws -> String { "an" }
            func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
                MeshyPolledFact(taskId: taskId, status: .succeeded)
            }
            func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {
                switch kind {
                case .textTo3D: break; case .imageTo3D: break; case .multiImageTo3D: break
                case .rigging: break; case .animation: break
                }
            }
            func fetchBalance() async throws -> Int { 0 }
            func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
                Data(repeating: 0x42, count: 64) // 64 bytes of stub GLB
            }
        }

        let glbURL = URL(string: "https://assets.meshy.ai/models/task_xyz.glb")!
        let taskResult = MeshyTaskResult(
            taskId: "task_xyz_123",
            modelURL: glbURL,
            prompt: "a wooden barrel",
            aiModel: .meshy6
        )

        let stub = TaskIdStubClient()
        let importer = Meshy3DAssetImporter(
            client: stub,
            logger: HypeLogger(setupFileLogging: false)
        )
        let assets = try await importer.importTask(
            result: taskResult,
            existingAssetNames: []
        )

        guard let primary = assets.first else {
            Issue.record("importTask must return at least one asset")
            return
        }

        #expect(primary.provenance?.attribution.taskId == "task_xyz_123",
                "Meshy3DAssetImporter must populate taskId from the task result")
        #expect(primary.provenance?.attribution.providerIdentifier == "meshy",
                "Meshy3DAssetImporter must set providerIdentifier = 'meshy'")
    }
}

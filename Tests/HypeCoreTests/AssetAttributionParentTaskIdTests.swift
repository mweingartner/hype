import Foundation
import Testing
@testable import HypeCore

// MARK: - AssetAttributionParentTaskIdTests

@Suite("parentTaskId round-trip")
struct AssetAttributionParentTaskIdTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: (a) parentTaskId round-trips through Codable

    @Test("AssetAttribution with parentTaskId='abc' round-trips through Codable")
    func parentTaskIdRoundTrips() throws {
        let attribution = AssetAttribution(
            providerIdentifier: "meshy",
            taskId: "gen_task_001",
            parentTaskId: "abc"
        )
        let data = try encoder.encode(attribution)
        let decoded = try decoder.decode(AssetAttribution.self, from: data)

        #expect(decoded.parentTaskId == "abc")
        #expect(decoded.taskId == "gen_task_001")
    }

    // MARK: (b) pre-Phase-4 documents decode with parentTaskId = ""

    @Test("AssetAttribution without parentTaskId in JSON decodes to empty string (backward compat)")
    func oldDocumentsDecodeWithEmptyParentTaskId() throws {
        // JSON that does NOT contain parentTaskId — simulates a pre-Phase-4 document.
        let json = """
        {
          "creator": "",
          "title": "",
          "sourceURL": "",
          "downloadURL": "",
          "providerName": "meshy",
          "providerIdentifier": "meshy",
          "taskId": "old_task_001"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(AssetAttribution.self, from: json)

        #expect(decoded.parentTaskId == "", "Pre-Phase-4 documents must decode parentTaskId as empty string")
        #expect(decoded.taskId == "old_task_001")
    }

    // MARK: (c) Meshy3DAssetImporter.importRemeshTask populates parentTaskId from sourceTaskId

    @Test("importRemeshTask sets parentTaskId to the source asset's taskId")
    func importRemeshTaskPopulatesParentTaskId() async throws {
        let sourceTaskId = "gen_source_001"

        // Build a MeshyTaskResult representing a completed remesh result.
        let glbURL = URL(string: "https://assets.meshy.ai/remesh/001.glb")!
        let taskResult = MeshyTaskResult(
            taskId: "remesh_result_001",
            modelURL: glbURL,
            prompt: "a wooden barrel",
            aiModel: .meshy6
        )

        // Use a stub client that can serve the GLB download.
        let glbData = Data("mock-glb-bytes".utf8)
        let stubClient = MeshyStubClient(downloadData: glbData)
        let importer = Meshy3DAssetImporter(client: stubClient)

        let asset = try await importer.importRemeshTask(
            result: taskResult,
            sourceAssetName: "barrel.glb",
            sourceTaskId: sourceTaskId,
            sourcePrompt: "a wooden barrel",
            existingAssetNames: []
        )

        #expect(asset.provenance?.attribution.parentTaskId == sourceTaskId,
                "parentTaskId must equal the source task id (C7)")
        #expect(asset.provenance?.attribution.providerIdentifier == "meshy")
        #expect(asset.kind == .model3D)
        #expect(asset.tags.contains("meshy-remesh"))
    }

    // MARK: (d) importRetextureTask populates parentTaskId from sourceTaskId

    @Test("importRetextureTask sets parentTaskId to the source asset's taskId")
    func importRetextureTaskPopulatesParentTaskId() async throws {
        let sourceTaskId = "gen_source_002"

        let glbURL = URL(string: "https://assets.meshy.ai/retex/002.glb")!
        let taskResult = MeshyTaskResult(
            taskId: "retex_result_001",
            modelURL: glbURL,
            prompt: "a wooden barrel",
            aiModel: .meshy6
        )

        let glbData = Data("mock-retex-glb".utf8)
        let stubClient = MeshyStubClient(downloadData: glbData)
        let importer = Meshy3DAssetImporter(client: stubClient)

        let asset = try await importer.importRetextureTask(
            result: taskResult,
            sourceAssetName: "barrel.glb",
            sourceTaskId: sourceTaskId,
            sourcePrompt: "a wooden barrel",
            newStylePrompt: "rusty iron metal",
            existingAssetNames: []
        )

        #expect(asset.provenance?.attribution.parentTaskId == sourceTaskId)
        #expect(asset.provenance?.attribution.providerIdentifier == "meshy")
        #expect(asset.kind == .model3D)
        #expect(asset.tags.contains("meshy-retexture"))
        // searchQuery should include the retexture prompt.
        let sq = asset.provenance?.searchQuery ?? ""
        #expect(sq.contains("rusty iron metal"), "Retexture prompt must appear in searchQuery")
    }
}

// MARK: - MeshyStubClient helper

/// Minimal MeshyClient stub for importer tests — only downloads need to work.
private struct MeshyStubClient: MeshyClient {
    let downloadData: Data

    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String { "stub" }
    func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String { "stub" }
    func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String { "stub" }
    func createRiggingTask(_ request: MeshyRiggingRequest) async throws -> String { "stub" }
    func createAnimationTask(_ request: MeshyAnimationRequest) async throws -> String { "stub" }
    func createRemeshTask(_ request: MeshyRemeshRequest) async throws -> String { "stub" }
    func createRetextureTask(_ request: MeshyRetextureRequest) async throws -> String { "stub" }
    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        MeshyPolledFact(
            taskId: taskId,
            status: .succeeded,
            progress: 100,
            primaryModelUrl: nil,
            usdzUrl: nil,
            fbxUrl: nil,
            basicWalkUrl: nil,
            basicRunUrl: nil,
            errorMessage: nil
        )
    }
    func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {}
    func fetchBalance() async throws -> Int { 0 }
    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        downloadData
    }
}

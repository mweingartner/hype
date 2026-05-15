import Foundation
import Testing
@testable import HypeCore

@Suite("Meshy models — JSON shapes")
struct MeshyModelsCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: (a) MeshyTextTo3DRequest encodes snake_case keys verbatim

    @Test("MeshyTextTo3DRequest encodes snake_case keys")
    func requestEncodesSnakeCase() throws {
        let req = MeshyTextTo3DRequest(
            mode: .preview,
            prompt: "a wooden barrel",
            artStyle: .realistic,
            aiModel: .meshy6,
            shouldRemesh: false,
            targetPolycount: 30000,
            topology: nil,
            symmetryMode: "auto",
            moderation: true,
            enablePbr: nil,
            targetFormats: ["glb", "usdz"],
            previewTaskId: nil
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["mode"] as? String == "preview")
        #expect(json["prompt"] as? String == "a wooden barrel")
        #expect(json["art_style"] as? String == "realistic")
        #expect(json["ai_model"] as? String == "meshy-6")
        #expect(json["should_remesh"] as? Bool == false)
        #expect(json["target_polycount"] as? Int == 30000)
        #expect(json["symmetry_mode"] as? String == "auto")
        #expect(json["moderation"] as? Bool == true)
        #expect(json["target_formats"] as? [String] == ["glb", "usdz"])
    }

    // MARK: (b) MeshyTaskResponse decodes various status bodies

    @Test("MeshyTaskResponse decodes pending status")
    func decodePendingStatus() throws {
        let json = #"{"id":"task_001","status":"PENDING"}"#.data(using: .utf8)!
        let resp = try decoder.decode(MeshyTaskResponse.self, from: json)
        #expect(resp.id == "task_001")
        #expect(resp.status == .pending)
        #expect(resp.progress == nil)
    }

    @Test("MeshyTaskResponse decodes in-progress status with progress")
    func decodeInProgressStatus() throws {
        let json = #"{"id":"task_002","status":"IN_PROGRESS","progress":60}"#.data(using: .utf8)!
        let resp = try decoder.decode(MeshyTaskResponse.self, from: json)
        #expect(resp.status == .inProgress)
        #expect(resp.progress == 60)
    }

    @Test("MeshyTaskResponse decodes succeeded status with model_urls")
    func decodeSucceededStatus() throws {
        let json = """
        {
            "id": "task_003",
            "status": "SUCCEEDED",
            "progress": 100,
            "model_urls": {
                "glb": "https://cdn.meshy.ai/model.glb",
                "fbx": null,
                "usdz": null,
                "obj": null,
                "mtl": null
            }
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MeshyTaskResponse.self, from: json)
        #expect(resp.status == .succeeded)
        #expect(resp.modelUrls?.glb?.absoluteString == "https://cdn.meshy.ai/model.glb")
        #expect(resp.modelUrls?.fbx == nil)
    }

    @Test("MeshyTaskResponse decodes failed status with task_error")
    func decodeFailedStatus() throws {
        let json = """
        {
            "id": "task_004",
            "status": "FAILED",
            "task_error": {"error": null, "message": "Generation failed: prompt too complex"}
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MeshyTaskResponse.self, from: json)
        #expect(resp.status == .failed)
        #expect(resp.taskError?.message == "Generation failed: prompt too complex")
    }

    // MARK: (c) Extra unknown keys are tolerated

    @Test("MeshyTaskResponse tolerates extra unknown keys")
    func extraKeysAreIgnored() throws {
        let json = #"{"id":"t5","status":"PENDING","unknown_future_key":"value","another":42}"#.data(using: .utf8)!
        let resp = try decoder.decode(MeshyTaskResponse.self, from: json)
        #expect(resp.id == "t5")
    }

    // MARK: (d) MeshyBalanceResponse parses with and without currency

    @Test("MeshyBalanceResponse parses balance with currency")
    func balanceWithCurrency() throws {
        let json = #"{"balance":380,"currency":"credits"}"#.data(using: .utf8)!
        let resp = try decoder.decode(MeshyBalanceResponse.self, from: json)
        #expect(resp.balance == 380)
        #expect(resp.currency == "credits")
    }

    @Test("MeshyBalanceResponse parses balance without currency")
    func balanceWithoutCurrency() throws {
        let json = #"{"balance":200}"#.data(using: .utf8)!
        let resp = try decoder.decode(MeshyBalanceResponse.self, from: json)
        #expect(resp.balance == 200)
        #expect(resp.currency == nil)
    }

    // MARK: (e) MeshyCreateTaskResponse parses result

    @Test("MeshyCreateTaskResponse parses result field")
    func createTaskResponse() throws {
        let json = #"{"result":"abc123def456"}"#.data(using: .utf8)!
        let resp = try decoder.decode(MeshyCreateTaskResponse.self, from: json)
        #expect(resp.result == "abc123def456")
    }
}

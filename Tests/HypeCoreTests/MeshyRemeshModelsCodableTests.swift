import Foundation
import Testing
@testable import HypeCore

// MARK: - MeshyRemeshModelsCodableTests

@Suite("Remesh request/response JSON shapes")
struct MeshyRemeshModelsCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: (a) Request encodes snake_case keys

    @Test("MeshyRemeshRequest encodes input_task_id and target_polycount as snake_case")
    func requestEncodesSnakeCase() throws {
        let req = MeshyRemeshRequest(inputTaskId: "task_xyz", targetPolycount: 5_000)
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["input_task_id"] as? String == "task_xyz")
        #expect(json["target_polycount"] as? Int == 5_000)
    }

    @Test("MeshyRemeshRequest encodes topology when set")
    func requestEncodesTopology() throws {
        let req = MeshyRemeshRequest(inputTaskId: "t1", targetPolycount: 1_000, topology: "quad")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["topology"] as? String == "quad")
    }

    @Test("MeshyRemeshRequest encodes decimation_mode, resize_height, auto_size, origin_at, convert_format_only")
    func requestEncodesAllOptionals() throws {
        let req = MeshyRemeshRequest(
            inputTaskId: "t2",
            targetPolycount: 10_000,
            topology: "triangle",
            decimationMode: 2,
            resizeHeight: 1.8,
            autoSize: true,
            originAt: "center",
            convertFormatOnly: false
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["decimation_mode"] as? Int == 2)
        #expect(json["resize_height"] as? Double == 1.8)
        #expect(json["auto_size"] as? Bool == true)
        #expect(json["origin_at"] as? String == "center")
        #expect(json["convert_format_only"] as? Bool == false)
    }

    @Test("MeshyRemeshRequest omits nil optional keys")
    func requestOmitsNilOptionals() throws {
        let req = MeshyRemeshRequest(inputTaskId: "t3", targetPolycount: 500)
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["topology"] == nil)
        #expect(json["decimation_mode"] == nil)
        #expect(json["resize_height"] == nil)
        #expect(json["auto_size"] == nil)
        #expect(json["origin_at"] == nil)
        #expect(json["convert_format_only"] == nil)
    }

    // MARK: (b) model_url is NEVER emitted (security C2)

    @Test("MeshyRemeshRequest never emits model_url key (SSRF prevention C2)")
    func requestNeverEmitsModelUrl() throws {
        let req = MeshyRemeshRequest(inputTaskId: "t4", targetPolycount: 1_000)
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["model_url"] == nil, "model_url must never appear — SSRF prevention C2")
    }

    // MARK: (c) Response decodes the documented shape

    @Test("MeshyRemeshTaskResponse decodes SUCCEEDED response with model_urls")
    func responseDecodesSucceeded() throws {
        let jsonStr = """
        {
          "id": "remesh_001",
          "status": "SUCCEEDED",
          "progress": 100,
          "model_urls": {
            "glb": "https://assets.meshy.ai/remesh/001.glb",
            "fbx": "https://assets.meshy.ai/remesh/001.fbx"
          },
          "consumed_credits": 3
        }
        """
        let resp = try decoder.decode(MeshyRemeshTaskResponse.self, from: jsonStr.data(using: .utf8)!)

        #expect(resp.id == "remesh_001")
        #expect(resp.status == .succeeded)
        #expect(resp.progress == 100)
        #expect(resp.modelUrls?.glb?.absoluteString == "https://assets.meshy.ai/remesh/001.glb")
        #expect(resp.consumedCredits == 3)
    }

    @Test("MeshyRemeshTaskResponse decodes IN_PROGRESS state")
    func responseDecodesInProgress() throws {
        let jsonStr = """
        {"id":"r2","status":"IN_PROGRESS","progress":55}
        """
        let resp = try decoder.decode(MeshyRemeshTaskResponse.self, from: jsonStr.data(using: .utf8)!)

        #expect(resp.status == .inProgress)
        #expect(resp.progress == 55)
        #expect(resp.modelUrls == nil)
    }

    // MARK: (d) Error envelope decoded when status is FAILED

    @Test("MeshyRemeshTaskResponse decodes FAILED with task_error")
    func responseDecodesFailedWithError() throws {
        let jsonStr = """
        {
          "id": "r3",
          "status": "FAILED",
          "task_error": {"message": "Remesh failed — input mesh has no faces."}
        }
        """
        let resp = try decoder.decode(MeshyRemeshTaskResponse.self, from: jsonStr.data(using: .utf8)!)

        #expect(resp.status == .failed)
        #expect(resp.taskError?.message == "Remesh failed — input mesh has no faces.")
    }

    // MARK: (e) consumed_credits decodeIfPresent

    @Test("MeshyRemeshTaskResponse decodes without consumed_credits when absent")
    func responseDecodesWithoutConsumedCredits() throws {
        let jsonStr = """
        {"id":"r4","status":"PENDING"}
        """
        let resp = try decoder.decode(MeshyRemeshTaskResponse.self, from: jsonStr.data(using: .utf8)!)

        #expect(resp.consumedCredits == nil)
    }
}

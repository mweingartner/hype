import Foundation
import Testing
@testable import HypeCore

@Suite("Meshy rigging models — JSON shapes")
struct MeshyRiggingModelsCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: (a) MeshyRiggingRequest encodes snake_case input_task_id and height_meters

    @Test("MeshyRiggingRequest encodes snake_case keys")
    func requestEncodesSnakeCase() throws {
        let req = MeshyRiggingRequest(
            inputTaskId: "task_abc123",
            heightMeters: 1.8
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["input_task_id"] as? String == "task_abc123")
        #expect(json["height_meters"] as? Double == 1.8)
    }

    @Test("MeshyRiggingRequest encodes without height_meters when nil")
    func requestOmitsNilHeightMeters() throws {
        let req = MeshyRiggingRequest(inputTaskId: "task_xyz")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["input_task_id"] as? String == "task_xyz")
        // height_meters should be absent (nil → omit, not null)
        #expect(json["height_meters"] == nil)
    }

    // MARK: (b) model_url is NEVER emitted by the codec (security H2)

    @Test("MeshyRiggingRequest never emits model_url key (SSRF prevention)")
    func requestNeverEmitsModelUrl() throws {
        let req = MeshyRiggingRequest(inputTaskId: "task_001")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["model_url"] == nil, "model_url must never appear — SSRF prevention H2")
        #expect(json["texture_image_url"] == nil, "texture_image_url must never appear — SSRF prevention H2")
    }

    // MARK: (c) MeshyRiggingTaskResponse decodes the real response shape

    @Test("MeshyRiggingTaskResponse decodes succeeded response with GLB URL")
    func responseDecodesSucceeded() throws {
        let json = """
        {
          "id": "rig_task_001",
          "status": "SUCCEEDED",
          "progress": 100,
          "rigged_character_glb_url": "https://assets.meshy.ai/rigs/rig_001.glb",
          "rigged_character_fbx_url": "https://assets.meshy.ai/rigs/rig_001.fbx"
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MeshyRiggingTaskResponse.self, from: json)

        #expect(resp.id == "rig_task_001")
        #expect(resp.status == .succeeded)
        #expect(resp.progress == 100)
        #expect(resp.riggedCharacterGlbUrl?.absoluteString == "https://assets.meshy.ai/rigs/rig_001.glb")
        #expect(resp.riggedCharacterFbxUrl?.absoluteString == "https://assets.meshy.ai/rigs/rig_001.fbx")
    }

    @Test("MeshyRiggingTaskResponse decodes in-progress response")
    func responseDecodesInProgress() throws {
        let json = """
        {"id":"rig_002","status":"IN_PROGRESS","progress":45}
        """.data(using: .utf8)!
        let resp = try decoder.decode(MeshyRiggingTaskResponse.self, from: json)

        #expect(resp.status == .inProgress)
        #expect(resp.progress == 45)
        #expect(resp.riggedCharacterGlbUrl == nil)
    }

    // MARK: (d) basic_animations round-trips

    @Test("MeshyRiggingTaskResponse decodes basic_animations sub-structure")
    func responseDecodesBasicAnimations() throws {
        let json = """
        {
          "id": "rig_003",
          "status": "SUCCEEDED",
          "rigged_character_glb_url": "https://assets.meshy.ai/rigs/rig_003.glb",
          "basic_animations": {
            "walking": {
              "glb": "https://assets.meshy.ai/anims/walk_003.glb",
              "fbx": "https://assets.meshy.ai/anims/walk_003.fbx"
            },
            "running": {
              "glb": "https://assets.meshy.ai/anims/run_003.glb",
              "fbx": null
            }
          }
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MeshyRiggingTaskResponse.self, from: json)

        #expect(resp.basicAnimations != nil)
        #expect(resp.basicAnimations?.walking?.glb?.absoluteString == "https://assets.meshy.ai/anims/walk_003.glb")
        #expect(resp.basicAnimations?.walking?.fbx?.absoluteString == "https://assets.meshy.ai/anims/walk_003.fbx")
        #expect(resp.basicAnimations?.running?.glb?.absoluteString == "https://assets.meshy.ai/anims/run_003.glb")
        #expect(resp.basicAnimations?.running?.fbx == nil)
    }

    // MARK: (e) task_error decoded when status is failed

    @Test("MeshyRiggingTaskResponse decodes task_error on failure")
    func responseDecodesTaskError() throws {
        let json = """
        {
          "id": "rig_fail_001",
          "status": "FAILED",
          "task_error": {"message":"Model is not humanoid"}
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MeshyRiggingTaskResponse.self, from: json)

        #expect(resp.status == .failed)
        #expect(resp.taskError?.message == "Model is not humanoid")
    }
}

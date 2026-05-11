import Foundation
import Testing
@testable import HypeCore

@Suite("Meshy animation models — JSON shapes")
struct MeshyAnimationModelsCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: (a) MeshyAnimationRequest encodes snake_case

    @Test("MeshyAnimationRequest encodes rig_task_id and action_id as snake_case")
    func requestEncodesSnakeCase() throws {
        let req = MeshyAnimationRequest(
            rigTaskId: "rig_task_001",
            actionId: 42
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["rig_task_id"] as? String == "rig_task_001")
        #expect(json["action_id"] as? Int == 42)
        #expect(json["post_process"] == nil)
    }

    // MARK: (b) MeshyAnimationTaskResponse decodes all 5 result URL fields

    @Test("MeshyAnimationTaskResponse decodes succeeded response with all result URL fields")
    func responseDecodesAllResultUrls() throws {
        let json = """
        {
          "id": "anim_task_001",
          "status": "SUCCEEDED",
          "progress": 100,
          "result": {
            "animation_glb_url": "https://assets.meshy.ai/anims/anim_001.glb",
            "animation_fbx_url": "https://assets.meshy.ai/anims/anim_001.fbx",
            "processed_usdz_url": "https://assets.meshy.ai/anims/anim_001.usdz",
            "processed_armature_fbx_url": "https://assets.meshy.ai/anims/anim_001_arm.fbx",
            "processed_animation_fps_fbx_url": "https://assets.meshy.ai/anims/anim_001_fps.fbx"
          }
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MeshyAnimationTaskResponse.self, from: json)

        #expect(resp.id == "anim_task_001")
        #expect(resp.status == .succeeded)
        #expect(resp.progress == 100)
        #expect(resp.result?.animationGlbUrl?.absoluteString == "https://assets.meshy.ai/anims/anim_001.glb")
        #expect(resp.result?.animationFbxUrl?.absoluteString == "https://assets.meshy.ai/anims/anim_001.fbx")
        #expect(resp.result?.processedUsdzUrl?.absoluteString == "https://assets.meshy.ai/anims/anim_001.usdz")
        #expect(resp.result?.processedArmatureFbxUrl?.absoluteString == "https://assets.meshy.ai/anims/anim_001_arm.fbx")
        #expect(resp.result?.processedAnimationFpsFbxUrl?.absoluteString == "https://assets.meshy.ai/anims/anim_001_fps.fbx")
    }

    @Test("MeshyAnimationTaskResponse decodes in-progress response")
    func responseDecodesInProgress() throws {
        let json = """
        {"id":"anim_002","status":"IN_PROGRESS","progress":30}
        """.data(using: .utf8)!
        let resp = try decoder.decode(MeshyAnimationTaskResponse.self, from: json)

        #expect(resp.status == .inProgress)
        #expect(resp.result == nil)
    }

    // MARK: (c) MeshyActionId decodes int and encodes int (no wrapping object)

    @Test("MeshyActionId decodes from plain integer")
    func actionIdDecodesFromInt() throws {
        let json = "123".data(using: .utf8)!
        let id = try decoder.decode(MeshyActionId.self, from: json)
        #expect(id.value == 123)
    }

    @Test("MeshyActionId encodes to plain integer (not wrapped in object)")
    func actionIdEncodesToInt() throws {
        let id: MeshyActionId = 456
        let data = try encoder.encode(id)
        // JSONSerialization requires allowFragments for top-level scalars.
        let decoded = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
        // Expect a bare Int, not {"value":456}
        #expect(decoded as? Int == 456)
    }

    @Test("MeshyActionId rejects out-of-range values at decode time")
    func actionIdRejectsOutOfRange() throws {
        // Decode should throw DecodingError for values outside 0…1000.
        let overMaxJson = "1001".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try decoder.decode(MeshyActionId.self, from: overMaxJson)
        }
    }

    @Test("MeshyActionId rejects Int.max at decode time")
    func actionIdRejectsIntMax() throws {
        let intMaxJson = "\(Int.max)".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try decoder.decode(MeshyActionId.self, from: intMaxJson)
        }
    }

    @Test("MeshyActionId.init(_:) throws MeshyError.validationFailed for out-of-range values")
    func actionIdThrowingInitRejectsOutOfRange() {
        // Use computed values to avoid triggering the integerLiteral precondition.
        // (MeshyActionId: ExpressibleByIntegerLiteral calls precondition on bad literals.)
        let negativeValue = 0 - 1       // -1
        let overMaxValue = 1000 + 1     // 1001
        let intMaxValue = Int.max       // definitely out of range
        #expect(throws: MeshyError.self) { try MeshyActionId(negativeValue) }
        #expect(throws: MeshyError.self) { try MeshyActionId(overMaxValue) }
        #expect(throws: MeshyError.self) { try MeshyActionId(intMaxValue) }
    }

    @Test("MeshyActionId throwing init accepts boundary values 0 and 1000")
    func actionIdAcceptsBoundaryValues() throws {
        let id0 = try MeshyActionId(0)
        let id1000 = try MeshyActionId(1000)
        #expect(id0.value == 0)
        #expect(id1000.value == 1000)
    }

    // MARK: (d) MeshyActionId(integerLiteral:) works for test fixtures

    @Test("MeshyActionId(integerLiteral:) initialises from an integer literal")
    func actionIdFromIntegerLiteral() {
        let id: MeshyActionId = 99
        #expect(id.value == 99)
    }
}

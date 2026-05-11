import Foundation
import Testing
@testable import HypeCore

// MARK: - MeshyRetextureModelsCodableTests

@Suite("Retexture request/response JSON shapes")
struct MeshyRetextureModelsCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: (a) Request encodes snake_case

    @Test("MeshyRetextureRequest encodes input_task_id and text_style_prompt as snake_case")
    func requestEncodesSnakeCase() throws {
        let req = MeshyRetextureRequest(inputTaskId: "task_abc", textStylePrompt: "rusty iron")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["input_task_id"] as? String == "task_abc")
        #expect(json["text_style_prompt"] as? String == "rusty iron")
    }

    @Test("MeshyRetextureRequest encodes ai_model when set")
    func requestEncodesAiModel() throws {
        let req = MeshyRetextureRequest(inputTaskId: "t1", textStylePrompt: "gold", aiModel: .meshy5)
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["ai_model"] as? String == "meshy-5")
    }

    @Test("MeshyRetextureRequest encodes enable_pbr, hd_texture, remove_lighting")
    func requestEncodesAllFlags() throws {
        let req = MeshyRetextureRequest(
            inputTaskId: "t2",
            textStylePrompt: "marble",
            enablePbr: true,
            hdTexture: true,
            removeLighting: false
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["enable_pbr"] as? Bool == true)
        #expect(json["hd_texture"] as? Bool == true)
        #expect(json["remove_lighting"] as? Bool == false)
    }

    @Test("MeshyRetextureRequest encodes target_formats array")
    func requestEncodesTargetFormats() throws {
        let req = MeshyRetextureRequest(
            inputTaskId: "t3",
            textStylePrompt: "wood",
            targetFormats: ["glb", "fbx"]
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let formats = json["target_formats"] as? [String]
        #expect(formats == ["glb", "fbx"])
    }

    // MARK: (b) text_style_prompt is always present

    @Test("MeshyRetextureRequest always includes text_style_prompt in output")
    func promptAlwaysPresent() throws {
        let req = MeshyRetextureRequest(inputTaskId: "t4", textStylePrompt: "")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Key should be present even when empty.
        #expect(json.keys.contains("text_style_prompt"))
    }

    // MARK: (c) image_style_url is NEVER emitted (security C3)

    @Test("MeshyRetextureRequest never emits model_url or image_style_url (SSRF prevention C3)")
    func requestNeverEmitsRestrictedUrls() throws {
        let req = MeshyRetextureRequest(inputTaskId: "t5", textStylePrompt: "lava rock")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["model_url"] == nil, "model_url must never appear — SSRF C3")
        #expect(json["image_style_url"] == nil, "image_style_url must never appear — SSRF C3")
    }

    // MARK: (d) Response decodes model_urls + texture_urls + thumbnail_url

    @Test("MeshyRetextureTaskResponse decodes SUCCEEDED response with all URL fields")
    func responseDecodesSucceeded() throws {
        let jsonStr = """
        {
          "id": "retex_001",
          "status": "SUCCEEDED",
          "progress": 100,
          "model_urls": {
            "glb": "https://assets.meshy.ai/retex/001.glb"
          },
          "texture_urls": [
            {"base_color": "https://assets.meshy.ai/retex/001_base.png"}
          ],
          "thumbnail_url": "https://assets.meshy.ai/retex/001_thumb.png",
          "consumed_credits": 5
        }
        """
        let resp = try decoder.decode(MeshyRetextureTaskResponse.self, from: jsonStr.data(using: .utf8)!)

        #expect(resp.id == "retex_001")
        #expect(resp.status == .succeeded)
        #expect(resp.modelUrls?.glb?.absoluteString == "https://assets.meshy.ai/retex/001.glb")
        #expect(resp.textureUrls?.isEmpty == false)
        #expect(resp.thumbnailUrl?.absoluteString == "https://assets.meshy.ai/retex/001_thumb.png")
        #expect(resp.consumedCredits == 5)
    }

    @Test("MeshyRetextureTaskResponse decodes IN_PROGRESS with nil URLs")
    func responseDecodesInProgress() throws {
        let jsonStr = """
        {"id":"r2","status":"IN_PROGRESS","progress":30}
        """
        let resp = try decoder.decode(MeshyRetextureTaskResponse.self, from: jsonStr.data(using: .utf8)!)

        #expect(resp.status == .inProgress)
        #expect(resp.modelUrls == nil)
        #expect(resp.textureUrls == nil)
    }

    // MARK: (e) target_formats array round-trips

    @Test("MeshyRetextureRequest target_formats round-trips through encode/decode")
    func targetFormatsRoundTrips() throws {
        let req = MeshyRetextureRequest(
            inputTaskId: "t6",
            textStylePrompt: "ice",
            targetFormats: ["glb"]
        )
        let data = try encoder.encode(req)
        let decoded = try decoder.decode(MeshyRetextureRequest.self, from: data)

        #expect(decoded.targetFormats == ["glb"])
    }
}

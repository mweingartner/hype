import Foundation
import Testing
@testable import HypeCore

@Suite("Meshy image-request JSON shapes")
struct MeshyImageRequestsCodableTests {

    private let encoder = JSONEncoder()

    // MARK: (a) MeshyImageTo3DRequest encodes image_data snake_case

    @Test("MeshyImageTo3DRequest encodes image_data in snake_case")
    func imageRequestEncodesSnakeCase() throws {
        let uri = "data:image/png;base64,abc123"
        let req = MeshyImageTo3DRequest(
            imageData: uri,
            aiModel: .meshy6,
            shouldRemesh: false,
            moderation: true
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["image_data"] as? String == uri)
        #expect(json["ai_model"] as? String == "meshy-6")
        #expect(json["should_remesh"] as? Bool == false)
        #expect(json["moderation"] as? Bool == true)
    }

    // MARK: (b) MeshyMultiImageTo3DRequest encodes image_data as array

    @Test("MeshyMultiImageTo3DRequest encodes image_data as array")
    func multiImageRequestEncodesArray() throws {
        let uris = ["data:image/png;base64,aaa", "data:image/jpeg;base64,bbb"]
        let req = MeshyMultiImageTo3DRequest(
            imageData: uris,
            aiModel: .meshy5,
            shouldRemesh: true,
            moderation: true
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let imageDataArray = json["image_data"] as? [String]
        #expect(imageDataArray?.count == 2)
        #expect(imageDataArray?[0] == uris[0])
        #expect(imageDataArray?[1] == uris[1])
        #expect(json["should_remesh"] as? Bool == true)
    }

    // MARK: (c) Both encode moderation: true by default

    @Test("Both request types encode moderation: true by default")
    func moderationDefaultTrue() throws {
        let single = MeshyImageTo3DRequest(imageData: "data:image/png;base64,x")
        let multi = MeshyMultiImageTo3DRequest(imageData: ["data:image/png;base64,x", "data:image/png;base64,y"])

        let singleData = try encoder.encode(single)
        let multiData = try encoder.encode(multi)
        let singleJSON = try JSONSerialization.jsonObject(with: singleData) as! [String: Any]
        let multiJSON = try JSONSerialization.jsonObject(with: multiData) as! [String: Any]

        #expect(singleJSON["moderation"] as? Bool == true)
        #expect(multiJSON["moderation"] as? Bool == true)
    }

    // MARK: (d) enable_pbr is omitted when nil

    @Test("enable_pbr is omitted from JSON when nil")
    func enablePbrOmittedWhenNil() throws {
        let req = MeshyImageTo3DRequest(imageData: "data:image/png;base64,x", enablePbr: nil)
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["enable_pbr"] == nil)
    }

    // MARK: (e) MeshyCreateTaskResponse decodes "result" key

    @Test("MeshyCreateTaskResponse decodes 'result' key (v2)")
    func createTaskResponseDecodesResult() throws {
        let json = #"{"result":"task_abc123"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MeshyCreateTaskResponse.self, from: json)
        #expect(decoded.result == "task_abc123")
    }

    // MARK: (f) MeshyCreateTaskResponse falls back to "id" key

    @Test("MeshyCreateTaskResponse falls back to 'id' key (v1 endpoints)")
    func createTaskResponseFallsBackToId() throws {
        let json = #"{"id":"task_v1_xyz"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MeshyCreateTaskResponse.self, from: json)
        #expect(decoded.result == "task_v1_xyz")
    }

    // MARK: (g) MeshyCreateTaskResponse throws when neither key present

    @Test("MeshyCreateTaskResponse throws when neither 'result' nor 'id' present")
    func createTaskResponseThrowsWhenMissing() throws {
        let json = #"{"status":"PENDING"}"#.data(using: .utf8)!
        do {
            _ = try JSONDecoder().decode(MeshyCreateTaskResponse.self, from: json)
            Issue.record("Expected DecodingError")
        } catch {
            // Any DecodingError is acceptable here.
        }
    }
}

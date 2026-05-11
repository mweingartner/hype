import Foundation
import Testing
@testable import HypeCore

/// Tests for `Part.scene3DAssetRef` backward-compatible decoding.
@Suite("Part.scene3DAssetRef — backward compat")
struct PartScene3DAssetRefCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Minimal encoded Part JSON that matches what the encoder currently outputs
    /// for a freshly-created Part (scene3DAssetRef omitted — as in old files).
    private func partJSON(includeAssetRef: Bool, assetRef: AssetRef? = nil) throws -> Data {
        let part = Part(partType: .scene3D)
        var json = try JSONSerialization.jsonObject(
            with: encoder.encode(part)
        ) as! [String: Any]
        if !includeAssetRef {
            json.removeValue(forKey: "scene3DAssetRef")
        } else if let ref = assetRef {
            let refData = try encoder.encode(ref)
            json["scene3DAssetRef"] = try JSONSerialization.jsonObject(with: refData)
        } else {
            json["scene3DAssetRef"] = NSNull()
        }
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test("pre-Meshy Part JSON without scene3DAssetRef decodes to nil")
    func missingKeyDecodesToNil() throws {
        let data = try partJSON(includeAssetRef: false)
        let decoded = try decoder.decode(Part.self, from: data)
        #expect(decoded.scene3DAssetRef == nil)
    }

    @Test("explicit null scene3DAssetRef decodes to nil")
    func explicitNullDecodesToNil() throws {
        let data = try partJSON(includeAssetRef: true, assetRef: nil)
        let decoded = try decoder.decode(Part.self, from: data)
        #expect(decoded.scene3DAssetRef == nil)
    }

    @Test("populated AssetRef round-trips with id, name, mimeType")
    func assetRefRoundTrip() throws {
        let refId = UUID()
        let ref = AssetRef(id: refId, name: "barrel.glb", mimeType: "model/gltf-binary")
        let data = try partJSON(includeAssetRef: true, assetRef: ref)
        let decoded = try decoder.decode(Part.self, from: data)
        #expect(decoded.scene3DAssetRef?.id == refId)
        #expect(decoded.scene3DAssetRef?.name == "barrel.glb")
        #expect(decoded.scene3DAssetRef?.mimeType == "model/gltf-binary")
    }
}

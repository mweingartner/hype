import Foundation
import Testing
@testable import HypeCore

/// Tests for `AssetKind.model3D` backward-compat decoding and the 50 MB cap.
@Suite("AssetKind.model3D — backward compat")
struct MeshyAssetKindCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - AssetKind encoding / decoding

    @Test("SpriteAsset with kind .model3D encodes as \"model3D\"")
    func model3DEncodesCorrectly() throws {
        let asset = SpriteAsset(
            name: "barrel.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x67, 0x6C, 0x54, 0x46]) // minimal GLB header
        )
        let data = try encoder.encode(asset)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["kind"] as? String == "model3D")
    }

    @Test("model3D asset round-trips through encode/decode")
    func model3DRoundTrips() throws {
        let original = SpriteAsset(
            name: "barrel.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x01, 0x02, 0x03])
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SpriteAsset.self, from: data)
        #expect(decoded.kind == .model3D)
        #expect(decoded.name == "barrel.glb")
        #expect(decoded.mimeType == "model/gltf-binary")
    }

    @Test("pre-Meshy asset without kind key decodes to .imageTexture")
    func missingKindFallsBackToImageTexture() throws {
        let asset = SpriteAsset(name: "test.png", kind: .imageTexture, data: Data([1, 2, 3]))
        var json = try JSONSerialization.jsonObject(
            with: encoder.encode(asset)
        ) as! [String: Any]
        json.removeValue(forKey: "kind")
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(SpriteAsset.self, from: jsonData)
        #expect(decoded.kind == .imageTexture)
    }

    @Test("asset with unknown future kind decodes to .imageTexture via forward-compat init")
    func unknownFutureKindFallsBack() throws {
        let asset = SpriteAsset(name: "future.xyz", kind: .imageTexture, data: Data([1, 2, 3]))
        var json = try JSONSerialization.jsonObject(
            with: encoder.encode(asset)
        ) as! [String: Any]
        json["kind"] = "futureKindXYZ"
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(SpriteAsset.self, from: jsonData)
        // The custom AssetKind.init(from:) maps unknown values to .imageTexture.
        #expect(decoded.kind == .imageTexture)
    }

    // MARK: - 50 MB cap (M1)

    @Test("model3D asset with exactly 50 MB data decodes successfully")
    func model3DAtCapDecodes() throws {
        let capBytes = 50 * 1024 * 1024
        let asset = SpriteAsset(
            name: "big.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data(count: capBytes)
        )
        let data = try encoder.encode(asset)
        // Should not throw at exactly the cap.
        let decoded = try decoder.decode(SpriteAsset.self, from: data)
        #expect(decoded.data.count == capBytes)
    }

    @Test("model3D SpriteAsset with 51 MB of data throws DecodingError on decode")
    func model3DOver50MBThrows() throws {
        // Build a JSON payload manually to simulate a malicious document —
        // we can't use the encoder since it would produce valid data, but
        // we need the kind="model3D" + data > 50 MB in the JSON.
        // Strategy: encode a legitimate asset, then surgically inflate data.
        let overCap = 51 * 1024 * 1024
        let asset = SpriteAsset(
            name: "huge.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data(count: overCap)
        )
        // Encode bypassing the decoder path (encoder has no cap).
        let rawData = try encoder.encode(asset)
        // Decoding must throw.
        var threw = false
        do {
            _ = try decoder.decode(SpriteAsset.self, from: rawData)
        } catch DecodingError.dataCorrupted(let ctx) {
            threw = true
            #expect(ctx.debugDescription.contains("50 MB"))
        } catch {
            threw = true // any error is acceptable
        }
        #expect(threw, "Expected decode to throw for a 51 MB model3D asset")
    }

    @Test("imageTexture asset over 50 MB does NOT trigger the cap")
    func imageTextureOver50MBNotCapped() throws {
        // The cap only applies to .model3D, not to image assets.
        let overCap = 51 * 1024 * 1024
        let asset = SpriteAsset(
            name: "huge.png",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data(count: overCap)
        )
        let rawData = try encoder.encode(asset)
        // Should decode without error.
        let decoded = try decoder.decode(SpriteAsset.self, from: rawData)
        #expect(decoded.data.count == overCap)
    }
}

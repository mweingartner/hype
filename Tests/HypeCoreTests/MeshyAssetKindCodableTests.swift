import Foundation
import Testing
@testable import HypeCore

/// Tests for `AssetKind.model3D` backward-compat decoding and the 50 MB cap.
@Suite("AssetKind.model3D — backward compat")
struct MeshyAssetKindCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - AssetKind encoding / decoding

    @Test("Asset with kind .model3D encodes as \"model3D\"")
    func model3DEncodesCorrectly() throws {
        let asset = Asset(
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
        let original = Asset(
            name: "barrel.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x01, 0x02, 0x03])
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Asset.self, from: data)
        #expect(decoded.kind == .model3D)
        #expect(decoded.name == "barrel.glb")
        #expect(decoded.mimeType == "model/gltf-binary")
    }

    @Test("compound asset files and metadata round-trip")
    func compoundAssetRoundTrips() throws {
        let original = Asset(
            name: "rigged-character.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x67, 0x6C, 0x54, 0x46]),
            files: [
                AssetFile(
                    name: "walk.fbx",
                    role: .animation,
                    mimeType: "model/fbx",
                    data: Data([0x01, 0x02]),
                    tags: ["walk"]
                ),
                AssetFile(
                    name: "albedo.png",
                    role: .texture,
                    mimeType: "image/png",
                    data: Data([0x89, 0x50]),
                    width: 16,
                    height: 16,
                    tags: ["albedo"]
                ),
            ],
            metadata: [
                AssetMetadataEntry(
                    key: "legacy-resource",
                    value: #"{"type":"ppat","id":128}"#,
                    mimeType: "application/json",
                    tags: ["hypercard-import"]
                )
            ]
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Asset.self, from: data)

        #expect(decoded.files.count == 2)
        #expect(decoded.files[0].role == .animation)
        #expect(decoded.files[1].role == .texture)
        #expect(decoded.files[1].width == 16)
        #expect(decoded.metadata.first?.key == "legacy-resource")
        #expect(decoded.totalEmbeddedByteCount == original.totalEmbeddedByteCount)
        #expect(decoded.allFiles.count == 3)
        #expect(decoded.allFiles.first?.role == .primary)
    }

    @Test("pre-Meshy asset without kind key decodes to .imageTexture")
    func missingKindFallsBackToImageTexture() throws {
        let asset = Asset(name: "test.png", kind: .imageTexture, data: Data([1, 2, 3]))
        var json = try JSONSerialization.jsonObject(
            with: encoder.encode(asset)
        ) as! [String: Any]
        json.removeValue(forKey: "kind")
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(Asset.self, from: jsonData)
        #expect(decoded.kind == .imageTexture)
    }

    @Test("asset with unknown future kind decodes to .imageTexture via forward-compat init")
    func unknownFutureKindFallsBack() throws {
        let asset = Asset(name: "future.xyz", kind: .imageTexture, data: Data([1, 2, 3]))
        var json = try JSONSerialization.jsonObject(
            with: encoder.encode(asset)
        ) as! [String: Any]
        json["kind"] = "futureKindXYZ"
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(Asset.self, from: jsonData)
        // The custom AssetKind.init(from:) maps unknown values to .imageTexture.
        #expect(decoded.kind == .imageTexture)
    }

    // MARK: - 50 MB cap (M1)

    @Test("model3D asset with exactly 50 MB data decodes successfully")
    func model3DAtCapDecodes() throws {
        let capBytes = 50 * 1024 * 1024
        let asset = Asset(
            name: "big.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data(count: capBytes)
        )
        let data = try encoder.encode(asset)
        // Should not throw at exactly the cap.
        let decoded = try decoder.decode(Asset.self, from: data)
        #expect(decoded.data.count == capBytes)
    }

    @Test("model3D asset related files count toward 50 MB cap")
    func model3DRelatedFilesCountTowardCap() throws {
        let asset = Asset(
            name: "compound.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data(count: 49 * 1024 * 1024),
            files: [
                AssetFile(
                    name: "texture.png",
                    role: .texture,
                    mimeType: "image/png",
                    data: Data(count: 2 * 1024 * 1024)
                )
            ]
        )

        let rawData = try encoder.encode(asset)
        var threw = false
        do {
            _ = try decoder.decode(Asset.self, from: rawData)
        } catch DecodingError.dataCorrupted(let ctx) {
            threw = true
            #expect(ctx.debugDescription.contains("50 MB"))
        } catch {
            threw = true
        }
        #expect(threw, "Expected decode to throw when compound model3D payload exceeds 50 MB")
    }

    @Test("model3D Asset with 51 MB of data throws DecodingError on decode")
    func model3DOver50MBThrows() throws {
        // Build a JSON payload manually to simulate a malicious document —
        // we can't use the encoder since it would produce valid data, but
        // we need the kind="model3D" + data > 50 MB in the JSON.
        // Strategy: encode a legitimate asset, then surgically inflate data.
        let overCap = 51 * 1024 * 1024
        let asset = Asset(
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
            _ = try decoder.decode(Asset.self, from: rawData)
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
        let asset = Asset(
            name: "huge.png",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data(count: overCap)
        )
        let rawData = try encoder.encode(asset)
        // Should decode without error.
        let decoded = try decoder.decode(Asset.self, from: rawData)
        #expect(decoded.data.count == overCap)
    }
}

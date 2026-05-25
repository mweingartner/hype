import Foundation
import Testing
@testable import HypeCore

/// Tests for `Asset` rigging/animation metadata round-trip (Phase 3).
@Suite("Asset — rigging and animation metadata Codable (Phase 3)")
struct AssetMetadataCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Helpers

    private func makeRiggedAsset(
        isRigged: Bool = false,
        animationActionId: Int? = nil
    ) -> Asset {
        Asset(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "test-model.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x67, 0x6C, 0x54, 0x46]),  // glTF magic bytes
            width: 0,
            height: 0,
            isRigged: isRigged,
            animationActionId: animationActionId
        )
    }

    // MARK: (a) isRigged = true round-trips through Codable

    @Test("isRigged = true round-trips through encode/decode")
    func isRiggedTrueRoundTrips() throws {
        let original = makeRiggedAsset(isRigged: true)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Asset.self, from: data)

        #expect(decoded.isRigged == true)
        #expect(decoded.animationActionId == nil)
    }

    @Test("isRigged = false round-trips through encode/decode")
    func isRiggedFalseRoundTrips() throws {
        let original = makeRiggedAsset(isRigged: false)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Asset.self, from: data)

        #expect(decoded.isRigged == false)
    }

    // MARK: (b) animationActionId = 42 round-trips

    @Test("animationActionId = 42 round-trips through encode/decode")
    func animationActionIdRoundTrips() throws {
        let original = makeRiggedAsset(isRigged: true, animationActionId: 42)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Asset.self, from: data)

        #expect(decoded.isRigged == true)
        #expect(decoded.animationActionId == 42)
    }

    // MARK: (c) pre-Phase-3 document (no rigging keys) loads with safe defaults

    @Test("legacy JSON without isRigged/animationActionId decodes with false/nil defaults")
    func legacyJsonDecodesWithDefaults() throws {
        // A minimal Asset JSON as it would have been saved before Phase 3.
        let legacyJson = """
        {
          "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "name": "old-model.glb",
          "kind": "model3D",
          "mimeType": "model/gltf-binary",
          "data": "",
          "width": 0,
          "height": 0
        }
        """.data(using: .utf8)!

        let asset = try decoder.decode(Asset.self, from: legacyJson)

        #expect(asset.isRigged == false,
                "Pre-Phase-3 document must decode isRigged as false (backward compat)")
        #expect(asset.animationActionId == nil,
                "Pre-Phase-3 document must decode animationActionId as nil (backward compat)")
    }

    // MARK: (d) rigged model3D saves without losing the flag

    @Test("rigged model3D saves and reloads without losing isRigged flag")
    func riggedModel3DSavesAndReloads() throws {
        let original = makeRiggedAsset(isRigged: true)
        let encoded = try encoder.encode(original)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // isRigged must appear in the serialized JSON.
        #expect(json["isRigged"] as? Bool == true)

        // And it must survive a round-trip.
        let reloaded = try decoder.decode(Asset.self, from: encoded)
        #expect(reloaded.isRigged == true)
    }

    // MARK: (e) decode-time invariant: animationActionId set forces isRigged = true

    @Test("animationActionId present in JSON forces isRigged = true even if flag is false")
    func animationActionIdForcesIsRigged() throws {
        // Hand-crafted JSON where isRigged = false but animationActionId is set.
        // The decoder's invariant must correct this inconsistency.
        let inconsistentJson = """
        {
          "id": "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
          "name": "inconsistent-model.glb",
          "kind": "model3D",
          "mimeType": "model/gltf-binary",
          "data": "",
          "width": 0,
          "height": 0,
          "isRigged": false,
          "animationActionId": 55
        }
        """.data(using: .utf8)!

        let asset = try decoder.decode(Asset.self, from: inconsistentJson)

        #expect(asset.animationActionId == 55)
        #expect(asset.isRigged == true,
                "Decoder invariant: animationActionId != nil forces isRigged = true")
    }
}

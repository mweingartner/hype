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

    @Test("asset compilation metadata round-trips through Codable")
    func assetCompilationRoundTrips() throws {
        let sourceId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let runtimeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let runtimeRef = AssetRef(id: runtimeId, name: "hero-runtime.usdz", mimeType: "model/vnd.usdz+zip")
        let compiledAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Asset(
            id: sourceId,
            name: "hero-source.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x67, 0x6C, 0x54, 0x46]),
            compilation: AssetCompilation(
                role: .source,
                runtimeAssetRefs: [runtimeRef],
                operation: "model3d.usdz",
                compilerIdentifier: "hype.scene3d",
                compilerVersion: "1",
                sourceFingerprint: "sha256:source",
                optionsFingerprint: "sha256:options",
                compiledAt: compiledAt,
                diagnostics: ["used fallback material"]
            )
        )

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Asset.self, from: encoded)

        #expect(decoded.compilation?.role == .source)
        #expect(decoded.compilation?.runtimeAssetRefs.first?.id == runtimeId)
        #expect(decoded.compilation?.operation == "model3d.usdz")
        #expect(decoded.compilation?.compilerIdentifier == "hype.scene3d")
        #expect(decoded.compilation?.sourceFingerprint == "sha256:source")
        #expect(decoded.compilation?.optionsFingerprint == "sha256:options")
        #expect(decoded.compilation?.compiledAt == compiledAt)
        #expect(decoded.compilation?.diagnostics == ["used fallback material"])
    }

    @Test("repository links compiled runtime asset to source asset")
    func repositoryLinksCompiledRuntimeAssetToSourceAsset() throws {
        let source = Asset(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "ship-source.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x67, 0x6C, 0x54, 0x46])
        )
        let runtime = Asset(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "ship-runtime.usdz",
            kind: .model3D,
            mimeType: "model/vnd.usdz+zip",
            data: Data([0x55, 0x53, 0x44, 0x5A])
        )
        let compiledAt = Date(timeIntervalSince1970: 1_700_000_100)
        var repository = AssetRepository(assets: [source, runtime])

        repository.linkCompiledAsset(
            sourceAssetId: source.id,
            runtimeAssetId: runtime.id,
            operation: "model3d.usdz",
            compilerIdentifier: "hype.scene3d",
            compilerVersion: "1",
            sourceFingerprint: "sha256:source",
            optionsFingerprint: "sha256:options",
            compiledAt: compiledAt
        )

        let updatedSource = try #require(repository.asset(byId: source.id))
        let updatedRuntime = try #require(repository.asset(byId: runtime.id))
        #expect(updatedSource.compilation?.role == .source)
        #expect(updatedSource.compilation?.runtimeAssetRefs.first?.id == runtime.id)
        #expect(updatedRuntime.compilation?.role == .runtime)
        #expect(updatedRuntime.compilation?.sourceAssetRef?.id == source.id)
        #expect(repository.runtimeAssets(compiledFrom: source.id).map(\.id) == [runtime.id])
        #expect(repository.sourceAsset(forRuntimeAssetId: runtime.id)?.id == source.id)
    }
}

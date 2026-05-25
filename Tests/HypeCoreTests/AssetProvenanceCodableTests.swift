import Testing
import Foundation
@testable import HypeCore

/// Tests that `AssetProvenance` and `Asset` encoding/decoding are backward-
/// compatible: legacy JSON without `provenance` decodes to nil, and new format
/// round-trips correctly.
@Suite("AssetProvenance Codable — backward-compatibility and round-trip")
struct AssetProvenanceCodableTests {

    // MARK: - Helpers

    private func makeProvenance() -> AssetProvenance {
        AssetProvenance(
            origin: .webSearch,
            searchQuery: "test query",
            license: AssetLicense(
                name: "CC0",
                identifier: "cc0",
                url: "https://creativecommons.org/publicdomain/zero/1.0/",
                isShareable: true
            ),
            attribution: AssetAttribution(
                creator: "Jane Doe",
                title: "A Test Image",
                sourceURL: "https://openverse.org/image/abc123",
                downloadURL: "https://cdn.openverse.org/abc123.png",
                providerName: "Openverse",
                providerIdentifier: "openverse"
            ),
            importedAt: Date(timeIntervalSince1970: 1700000000)
        )
    }

    private func makeAsset(provenance: AssetProvenance? = nil) -> Asset {
        Asset(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!,
            name: "test_asset",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0x89, 0x50, 0x4E, 0x47]),  // PNG magic bytes
            width: 100,
            height: 100,
            tags: [],
            slices: [],
            animationClips: [],
            tileWidth: 0,
            tileHeight: 0,
            tileColumns: 0,
            tileRows: 0,
            provenance: provenance
        )
    }

    // MARK: - Legacy JSON decoding (provenance absent)

    @Test("decoding legacy Asset JSON without provenance key produces nil provenance")
    func legacyJSONNilProvenance() throws {
        // Simulate a pre-web-asset Asset JSON with no provenance field
        let legacyJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "name": "old_asset",
            "kind": "imageTexture",
            "mimeType": "image/png",
            "data": "iVBORw0K",
            "width": 100,
            "height": 100,
            "tags": [],
            "slices": [],
            "animationClips": [],
            "tileWidth": 0,
            "tileHeight": 0,
            "tileColumns": 0,
            "tileRows": 0
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let asset = try JSONDecoder().decode(Asset.self, from: data)
        #expect(asset.provenance == nil)
        #expect(asset.name == "old_asset")
    }

    @Test("decoding legacy JSON with null provenance value also produces nil")
    func nullProvenanceValueDecodes() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "name": "old_asset",
            "kind": "imageTexture",
            "mimeType": "image/png",
            "data": "iVBORw0K",
            "width": 100,
            "height": 100,
            "tags": [],
            "slices": [],
            "animationClips": [],
            "tileWidth": 0,
            "tileHeight": 0,
            "tileColumns": 0,
            "tileRows": 0,
            "provenance": null
        }
        """
        let data = json.data(using: .utf8)!
        let asset = try JSONDecoder().decode(Asset.self, from: data)
        #expect(asset.provenance == nil)
    }

    // MARK: - AssetProvenance round-trip

    @Test("AssetProvenance encodes and decodes with all fields preserved")
    func assetProvenanceRoundTrip() throws {
        let original = makeProvenance()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AssetProvenance.self, from: encoded)

        #expect(decoded.origin == .webSearch)
        #expect(decoded.searchQuery == "test query")
        #expect(decoded.license.name == "CC0")
        #expect(decoded.license.identifier == "cc0")
        #expect(decoded.license.isShareable == true)
        #expect(decoded.attribution.creator == "Jane Doe")
        #expect(decoded.attribution.title == "A Test Image")
        #expect(decoded.attribution.sourceURL == "https://openverse.org/image/abc123")
        #expect(decoded.attribution.providerName == "Openverse")
        #expect(decoded.attribution.providerIdentifier == "openverse")
        // Date round-trips within 1 second precision
        #expect(abs(decoded.importedAt.timeIntervalSince1970 - 1700000000) < 1.0)
    }

    // MARK: - Asset round-trip with provenance

    @Test("Asset with provenance round-trips correctly")
    func spriteAssetWithProvenanceRoundTrip() throws {
        let provenance = makeProvenance()
        let original = makeAsset(provenance: provenance)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Asset.self, from: encoded)

        #expect(decoded.provenance != nil)
        #expect(decoded.provenance?.origin == .webSearch)
        #expect(decoded.provenance?.searchQuery == "test query")
        #expect(decoded.provenance?.license.identifier == "cc0")
        #expect(decoded.provenance?.attribution.creator == "Jane Doe")
        #expect(decoded.name == "test_asset")
        #expect(decoded.width == 100)
    }

    @Test("Asset without provenance round-trips with nil provenance")
    func spriteAssetWithoutProvenanceRoundTrip() throws {
        let original = makeAsset(provenance: nil)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Asset.self, from: encoded)
        #expect(decoded.provenance == nil)
    }

    // MARK: - AssetOrigin Codable

    @Test("AssetOrigin.webSearch encodes to 'webSearch' string")
    func assetOriginWebSearchEncodes() throws {
        let origin = AssetOrigin.webSearch
        let data = try JSONEncoder().encode(origin)
        let string = String(data: data, encoding: .utf8)!
        #expect(string.contains("webSearch"))
    }

    @Test("AssetOrigin.userImport encodes to 'userImport' string")
    func assetOriginUserImportEncodes() throws {
        let origin = AssetOrigin.userImport
        let data = try JSONEncoder().encode(origin)
        let string = String(data: data, encoding: .utf8)!
        #expect(string.contains("userImport"))
    }

    @Test("AssetOrigin round-trips through JSON")
    func assetOriginRoundTrips() throws {
        let origins: [AssetOrigin] = [.userImport, .webSearch, .aiGenerated]
        for origin in origins {
            let data = try JSONEncoder().encode(origin)
            let decoded = try JSONDecoder().decode(AssetOrigin.self, from: data)
            #expect(decoded == origin)
        }
    }

    // MARK: - AssetLicense and AssetAttribution defaults

    @Test("AssetLicense default init has all empty/false fields")
    func assetLicenseDefaultInit() {
        let license = AssetLicense()
        #expect(license.name.isEmpty)
        #expect(license.identifier.isEmpty)
        #expect(license.url.isEmpty)
        #expect(license.isShareable == false)
    }

    @Test("AssetAttribution default init has all empty fields")
    func assetAttributionDefaultInit() {
        let attr = AssetAttribution()
        #expect(attr.creator.isEmpty)
        #expect(attr.title.isEmpty)
        #expect(attr.sourceURL.isEmpty)
        #expect(attr.downloadURL.isEmpty)
        #expect(attr.providerName.isEmpty)
        #expect(attr.providerIdentifier.isEmpty)
    }
}

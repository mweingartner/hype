import Foundation
import Testing
@testable import HypeCore

@Suite("AssetRepository")
struct AssetRepositoryTests {
    @Test("repository filters and searches multiple asset categories")
    func filtersAndSearchesMultipleAssetCategories() {
        let image = Asset(name: "Hero", kind: .imageTexture, mimeType: "image/png", data: Data([1]))
        let audio = Asset(name: "Hero", kind: .audioClip, mimeType: "audio/wav", data: Data([2]))
        let video = Asset(name: "Intro", kind: .videoClip, mimeType: "video/mp4", data: Data([3]))
        let model = Asset(name: "Robot", kind: .model3D, mimeType: "model/gltf-binary", data: Data([4]))
        let particles = Asset(name: "Smoke", kind: .particlePreset, mimeType: "application/x-spritekit-particle", data: Data([5]))
        let repository = AssetRepository(assets: [image, audio, video, model, particles])

        #expect(repository.assets(in: .image).map(\.id) == [image.id])
        #expect(repository.assets(in: .audio).map(\.id) == [audio.id])
        #expect(repository.assets(in: .video).map(\.id) == [video.id])
        #expect(repository.assets(in: .model3D).map(\.id) == [model.id])
        #expect(repository.assets(in: .effects).map(\.id) == [particles.id])
        #expect(repository.asset(byName: "Hero", kind: .audioClip)?.id == audio.id)
        #expect(repository.searchAssets(named: "ro", category: .model3D).map(\.id) == [model.id])
    }

    @Test("repository search matches metadata and all query terms")
    func searchMatchesAssetMetadataAndAllTerms() {
        let web = AssetProvenance(
            origin: .webSearch,
            searchQuery: "stone dungeon floor",
            license: AssetLicense(name: "Creative Commons", identifier: "cc0"),
            attribution: AssetAttribution(
                creator: "Map Smith",
                title: "Floor tile",
                providerName: "Wikimedia",
                providerIdentifier: "wikimedia"
            )
        )
        let tiles = Asset(
            name: "DungeonFloor",
            kind: .tileSet,
            mimeType: "image/png",
            data: Data([1]),
            width: 64,
            height: 64,
            tags: ["terrain", "stone"],
            metadata: [
                AssetMetadataEntry(key: "legacy-resource", value: "PAT 128", tags: ["classic"])
            ],
            tileWidth: 16,
            tileHeight: 16,
            tileColumns: 4,
            tileRows: 4,
            provenance: web
        )
        let audio = Asset(name: "StoneHit", kind: .audioClip, mimeType: "audio/wav", data: Data([2]))
        let repository = AssetRepository(assets: [tiles, audio])

        #expect(repository.searchAssets(named: "wikimedia cc0", category: .all).map(\.id) == [tiles.id])
        #expect(repository.searchAssets(named: "classic PAT", category: .image).map(\.id) == [tiles.id])
        #expect(repository.searchAssets(named: "stone image", category: .all).map(\.id) == [tiles.id])
        #expect(repository.searchAssets(named: "stone audio", category: .all).map(\.id) == [audio.id])
        #expect(repository.searchAssets(named: "stone audio", category: .image).isEmpty)
    }

    @Test("classic media lookup matches imported QuickTime metadata")
    func classicMediaLookupMatchesImportedQuickTimeMetadata() {
        let classic = Asset(
            name: "AtrusWrite-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data([1]),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "AtrusWrite"),
                AssetMetadataEntry(key: "lookup_key", value: "atruswrite")
            ]
        )
        let other = Asset(name: "AtrusWrite", kind: .audioClip, mimeType: "audio/wav", data: Data([2]))
        let repository = AssetRepository(assets: [other, classic])

        #expect(repository.asset(byClassicMediaName: "AtrusWrite.MooV", kind: .videoClip)?.id == classic.id)
        #expect(repository.asset(byClassicMediaName: "AtrusWrite-modern-av.mov", kind: .videoClip)?.id == classic.id)
        #expect(repository.asset(byClassicMediaName: "AtrusWrite", kind: .audioClip)?.id == other.id)
    }

    @Test("classic media lookup treats slash and colon movie names as equivalent")
    func classicMediaLookupTreatsSlashAndColonMovieNamesAsEquivalent() {
        let movie = Asset(
            name: "BR Seagulls:Water Slosh Mx Mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data([1]),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "BR Seagulls:Water Slosh Mx Mov"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("BR Seagulls:Water Slosh Mx Mov"))
            ]
        )
        let repository = AssetRepository(assets: [movie])

        #expect(AssetRepository.classicMediaLookupKey("BR Seagulls/Water Slosh Mx MoV") == "br seagulls water slosh mx mov")
        #expect(repository.asset(byClassicMediaName: "BR Seagulls/Water Slosh Mx MoV", kind: .videoClip)?.id == movie.id)
    }

    @Test("classic media lookup strips audio-only modern suffix")
    func classicMediaLookupStripsAudioOnlyModernSuffix() {
        let movie = Asset(
            name: "Intro Wind Mov-modern-audio.m4a",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("audio".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "Intro Wind Mov"),
                AssetMetadataEntry(key: "lookup_key", value: "intro wind mov"),
                AssetMetadataEntry(key: "quicktime_audio_only", value: "true")
            ]
        )
        let repository = AssetRepository(assets: [movie])

        #expect(AssetRepository.classicMediaLookupKey("Intro Wind Mov-modern-audio.m4a") == "intro wind mov")
        #expect(repository.asset(byClassicMediaName: "Intro Wind Mov", kind: .videoClip)?.id == movie.id)
    }

    @Test("classic media lookup trims and normalizes imported audio names")
    func classicMediaLookupTrimsAndNormalizesImportedAudioNames() {
        let audio = Asset(
            name: "WA Drip",
            kind: .audioClip,
            mimeType: "audio/wav",
            data: Data([1]),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "WA Drip"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("WA Drip"))
            ]
        )
        let repository = AssetRepository(assets: [audio])

        #expect(repository.asset(byClassicMediaName: "wa drip ", kind: .audioClip)?.id == audio.id)
    }

    @Test("classic media lookup tolerates collapsed word separators")
    func classicMediaLookupToleratesCollapsedWordSeparators() {
        let audio = Asset(
            name: "DR Drawer Close",
            kind: .audioClip,
            mimeType: "audio/wav",
            data: Data([1]),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "DR Drawer Close"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("DR Drawer Close"))
            ]
        )
        let repository = AssetRepository(assets: [audio])

        #expect(repository.asset(byClassicMediaName: "DR drawerClose", kind: .audioClip)?.id == audio.id)
    }

    @Test("HypeDocument exposes assetRepository while preserving assetRepository storage")
    func documentAssetRepositoryAliasMutatesStoredRepository() {
        var document = HypeDocument.newDocument()
        let sound = Asset(name: "Click", kind: .audioClip, mimeType: "audio/wav", data: Data([1, 2, 3]))

        document.assetRepository.addAsset(sound)

        #expect(document.assetRepository.asset(byName: "Click", kind: .audioClip)?.id == sound.id)
        #expect(document.assetRepository.assets(in: .audio).count == 1)
    }
}

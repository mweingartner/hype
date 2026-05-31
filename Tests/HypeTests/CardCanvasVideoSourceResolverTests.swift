import Foundation
import HypeCore
import Testing
@testable import Hype

@Suite("Card canvas video source resolver")
struct CardCanvasVideoSourceResolverTests {
    @Test("repository-backed QuickTime asset materializes to a playable file URL")
    func repositoryBackedQuickTimeAssetMaterializes() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let data = Data([0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70])
        let asset = Asset(
            name: "Intro Wind Mov-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: data,
            metadata: [
                AssetMetadataEntry(key: "lookup_key", value: "Intro Wind Mov"),
                AssetMetadataEntry(key: "sha256", value: "fixture-sha")
            ]
        )
        let repository = AssetRepository(assets: [asset])
        var part = Part(partType: .video, cardId: UUID(), name: "Intro", width: 320, height: 200)
        part.videoAssetRef = repository.assetRef(for: asset)
        part.videoAutoplay = true
        part.videoLoop = true
        part.videoVolume = 0.5

        let source = try #require(CardCanvasVideoSourceResolver.resolve(
            for: part,
            repository: repository,
            temporaryDirectory: tempDir
        ))

        #expect(source.audioOnly == false)
        #expect(source.url.pathExtension == "mov")
        #expect(source.url.path.contains(asset.id.uuidString))
        #expect(source.identity.contains("asset://\(asset.id.uuidString)/fixture-sha"))
        #expect(source.identity.contains("loop=true"))
        #expect(source.identity.contains("autoplay=true"))
        #expect(source.identity.contains("volume=0.5"))
        #expect(try Data(contentsOf: source.url) == data)
    }

    @Test("imported audio-only QuickTime metadata hides canvas video chrome")
    func importedAudioOnlyQuickTimeMetadataResolvesAsAudioOnly() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let asset = Asset(
            name: "music-modern-audio.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data([1, 2, 3]),
            metadata: [
                AssetMetadataEntry(key: "quicktime_audio_only", value: "true")
            ]
        )
        let repository = AssetRepository(assets: [asset])
        var part = Part(partType: .video, cardId: UUID(), name: "Music")
        part.videoAssetRef = repository.assetRef(for: asset)

        let source = try #require(CardCanvasVideoSourceResolver.resolve(
            for: part,
            repository: repository,
            temporaryDirectory: tempDir
        ))

        #expect(source.audioOnly)
        #expect(source.identity.contains("audioOnly=true"))
    }

    @Test("plain video URL remains supported when no repository asset is linked")
    func plainVideoURLFallbackRemainsSupported() throws {
        var part = Part(partType: .video, cardId: UUID(), name: "External")
        part.videoURL = "/tmp/Myst Intro.mov"
        part.helpText = "audioOnly=true"

        let source = try #require(CardCanvasVideoSourceResolver.resolve(
            for: part,
            repository: AssetRepository()
        ))

        #expect(source.url.isFileURL)
        #expect(source.url.path == "/tmp/Myst Intro.mov")
        #expect(source.audioOnly)
        #expect(source.identity.contains("/tmp/Myst Intro.mov"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCanvasVideoSourceResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

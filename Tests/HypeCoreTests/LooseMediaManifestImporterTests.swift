import Foundation
import Testing
@testable import HypeCore

@Suite("Loose media manifest import")
struct LooseMediaManifestImporterTests {
    @Test("imports requested loose media as repository assets")
    func importsRequestedLooseMediaAsRepositoryAssets() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let mediaRoot = root.appendingPathComponent("Myst Source", isDirectory: true)
        let manifestURL = root.appendingPathComponent("loose-media.tsv")
        let movieURL = mediaRoot.appendingPathComponent("Myst Graphics/Myst/Intro Wind Mov", isDirectory: false)
        let imageURL = mediaRoot.appendingPathComponent("Images/Frame.png", isDirectory: false)
        let soundURL = mediaRoot.appendingPathComponent("Sounds/Open.wav", isDirectory: false)
        let musicURL = mediaRoot.appendingPathComponent("Sounds/Theme.m4a", isDirectory: false)
        try FileManager.default.createDirectory(at: movieURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: soundURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("classic quicktime bytes".utf8).write(to: movieURL)
        try samplePNG.write(to: imageURL)
        try Data("RIFF----WAVEfmt ".utf8).write(to: soundURL)
        try Data("modern audio bytes".utf8).write(to: musicURL)
        try Data("""
        rel_path\tsource_path\toutput_path\tsize\tsha256\tfinder_type\tcreator\tsuffix\tkind
        Myst Graphics/Myst/Intro Wind Mov\t<myst-source-root>/Myst Graphics/Myst/Intro Wind Mov\t\t22\tmoviehash\tMYqt\tMYST\t\tunknown_binary
        Images/Frame.png\t<myst-source-root>/Images/Frame.png\t\t68\timagehash\t\t\t.png\timage
        Sounds/Open.wav\t<myst-source-root>/Sounds/Open.wav\t\t16\tsoundhash\t\t\t.wav\taudio
        Sounds/Theme.m4a\t<myst-source-root>/Sounds/Theme.m4a\t\t18\tmusichash\t\t\t.m4a\taudio
        Missing/Absent.mov\t<myst-source-root>/Missing/Absent.mov\t\t99\tmissinghash\tMYqt\tMYST\t.mov\tquicktime_movie
        """.utf8).write(to: manifestURL)

        var document = HypeDocument.newDocument(name: "Loose Media")
        let result = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: manifestURL,
                sourceRootURL: mediaRoot,
                requestedNames: ["Intro Wind Mov", "Frame", "Open", "Theme", "Absent"]
            ),
            into: &document
        )

        #expect(result.importedAssets.count == 4)
        #expect(result.missing == [LooseMediaImportDiagnostic(relPath: "Missing/Absent.mov", name: "Absent", reason: "file not found")])
        #expect(document.assetRepository.asset(byName: "Intro Wind Mov")?.kind == .videoClip)
        #expect(document.assetRepository.asset(byName: "Intro Wind Mov")?.mimeType == "video/quicktime")
        #expect(document.assetRepository.asset(byName: "Frame")?.kind == .imageTexture)
        #expect(document.assetRepository.asset(byName: "Open")?.kind == .audioClip)
        #expect(document.assetRepository.asset(byName: "Theme")?.kind == .audioClip)
        #expect(document.assetRepository.asset(byName: "Theme")?.mimeType == "audio/mp4")

        let movie = try #require(document.assetRepository.asset(byName: "Intro Wind Mov"))
        #expect(movie.tags.contains("loose-media"))
        #expect(movie.tags.contains("quicktime"))
        #expect(movie.metadata.contains { $0.key == "lookup_key" && $0.value == "intro wind mov" })
        #expect(movie.metadata.contains { $0.key == "rel_path" && $0.value == "Myst Graphics/Myst/Intro Wind Mov" })
    }

    @Test("resolves modern QuickTime replacements by classic media name")
    func resolvesModernQuickTimeReplacementsByClassicMediaName() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let replacements = root.appendingPathComponent("modern-quicktime", isDirectory: true)
        let manifestURL = root.appendingPathComponent("loose-media.tsv")
        try FileManager.default.createDirectory(at: replacements, withIntermediateDirectories: true)
        try Data("modern replacement".utf8).write(to: replacements.appendingPathComponent("AtrusWrite-modern-av.mov"))
        try Data("""
        rel_path\tsource_path\toutput_path\tsize\tsha256\tfinder_type\tcreator\tsuffix\tkind
        Myst Graphics/Dunny/AtrusWrite.MooV\t<myst-source-root>/Myst Graphics/Dunny/AtrusWrite.MooV\t\t3518373\t824a\tMYqt\tMYST\t.MooV\tquicktime_movie
        modern-quicktime/AtrusWrite-modern.mov\t<myst-source-root>/modern-quicktime/AtrusWrite-modern.mov\t\t1085557\t31ab\t\t\t.mov\tquicktime_movie
        """.utf8).write(to: manifestURL)

        var document = HypeDocument.newDocument(name: "Modern Media")
        let result = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: manifestURL,
                replacementRootURL: replacements,
                requestedNames: ["AtrusWrite"]
            ),
            into: &document
        )

        #expect(result.importedAssets.count == 1)
        #expect(result.missing.isEmpty)
        #expect(result.skipped.contains {
            $0.relPath == "modern-quicktime/AtrusWrite-modern.mov" &&
                $0.reason == "duplicate requested media"
        })
        #expect(document.assetRepository.asset(byName: "AtrusWrite")?.data == Data("modern replacement".utf8))
        #expect(document.assetRepository.asset(byName: "AtrusWrite 2") == nil)
    }

    @Test("resolves audio-only modern QuickTime replacements")
    func resolvesAudioOnlyModernQuickTimeReplacements() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let replacements = root.appendingPathComponent("modern-quicktime", isDirectory: true)
        let manifestURL = root.appendingPathComponent("loose-media.tsv")
        try FileManager.default.createDirectory(at: replacements, withIntermediateDirectories: true)
        try Data("modern audio replacement".utf8).write(to: replacements.appendingPathComponent("Intro Wind Mov-modern-audio.m4a"))
        try Data("""
        rel_path\tsource_path\toutput_path\tsize\tsha256\tfinder_type\tcreator\tsuffix\tkind
        Myst Graphics/Myst/Intro Wind Mov\t<myst-source-root>/Myst Graphics/Myst/Intro Wind Mov\t\t278258\twindhash\tMYqt\tMYST\t\tquicktime_movie
        """.utf8).write(to: manifestURL)

        var document = HypeDocument.newDocument(name: "Audio QuickTime")
        let result = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: manifestURL,
                replacementRootURL: replacements,
                requestedNames: ["Intro Wind Mov"]
            ),
            into: &document
        )

        let asset = try #require(result.importedAssets.first)
        #expect(asset.name == "Intro Wind Mov")
        #expect(asset.kind == .videoClip)
        #expect(asset.mimeType == "video/quicktime")
        #expect(asset.data == Data("modern audio replacement".utf8))
        #expect(asset.metadata.contains { $0.key == "quicktime_audio_only" && $0.value == "true" })
        #expect(document.assetRepository.asset(byClassicMediaName: "Intro Wind Mov-modern-audio.m4a", kind: .videoClip)?.id == asset.id)
    }

    @Test("attaches requested classic aliases to imported loose media")
    func attachesRequestedClassicAliasesToImportedLooseMedia() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let replacements = root.appendingPathComponent("modern-quicktime", isDirectory: true)
        let manifestURL = root.appendingPathComponent("loose-media.tsv")
        try FileManager.default.createDirectory(at: replacements, withIntermediateDirectories: true)
        try Data("generator loop audio".utf8).write(to: replacements.appendingPathComponent("EL GenAll MoV-modern-audio.m4a"))
        try Data("""
        rel_path\tsource_path\toutput_path\tsize\tsha256\tfinder_type\tcreator\tsuffix\tkind
        Myst Graphics/Myst/EL GenAll MoV\t<myst-source-root>/Myst Graphics/Myst/EL GenAll MoV\t\t441880\tgenhash\tMYqt\tMYST\t\tquicktime_movie
        """.utf8).write(to: manifestURL)

        var document = HypeDocument.newDocument(name: "Generator Media")
        let result = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: manifestURL,
                replacementRootURL: replacements,
                requestedNames: ["EL GenAll MoV"],
                mediaAliases: ["El GenRun": "EL GenAll MoV"]
            ),
            into: &document
        )

        let asset = try #require(result.importedAssets.first)
        #expect(asset.name == "EL GenAll MoV")
        #expect(asset.metadata.contains { $0.key == "classic_alias" && $0.value == "El GenRun" })
        #expect(asset.metadata.contains { $0.key == "lookup_key" && $0.value == "el genrun" })
        #expect(document.assetRepository.playableAudioAsset(byClassicMediaName: "El GenRun")?.id == asset.id)
    }

    @Test("imported loose media survives document codable round trip")
    func importedLooseMediaSurvivesDocumentCodableRoundTrip() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let mediaRoot = root.appendingPathComponent("Myst Source", isDirectory: true)
        let manifestURL = root.appendingPathComponent("loose-media.tsv")
        let movieURL = mediaRoot.appendingPathComponent("Myst Graphics/Myst/Intro Wind Mov", isDirectory: false)
        let movieData = Data("classic quicktime bytes".utf8)
        try FileManager.default.createDirectory(at: movieURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try movieData.write(to: movieURL)
        try Data("""
        rel_path\tsource_path\toutput_path\tsize\tsha256\tfinder_type\tcreator\tsuffix\tkind
        Myst Graphics/Myst/Intro Wind Mov\t<myst-source-root>/Myst Graphics/Myst/Intro Wind Mov\t\t22\tmoviehash\tMYqt\tMYST\t\tunknown_binary
        """.utf8).write(to: manifestURL)

        var document = HypeDocument.newDocument(name: "Round Trip Media")
        _ = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: manifestURL,
                sourceRootURL: mediaRoot,
                requestedNames: ["Intro Wind Mov"]
            ),
            into: &document
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: encoded)
        let asset = try #require(decoded.assetRepository.asset(byName: "Intro Wind Mov"))

        #expect(asset.kind == .videoClip)
        #expect(asset.mimeType == "video/quicktime")
        #expect(asset.data == movieData)
        #expect(asset.tags.contains("loose-media"))
        #expect(asset.metadata.contains { $0.key == "sha256" && $0.value == "moviehash" })
        #expect(asset.metadata.contains { $0.key == "finder_type" && $0.value == "MYqt" })
        #expect(asset.provenance?.origin == .userImport)
        #expect(asset.provenance?.attribution.providerIdentifier == "loose-media")
    }

    @Test("normalizes classic media lookup keys")
    func normalizesClassicMediaLookupKeys() {
        #expect(LooseMediaManifestImporter.lookupKey("AtrusWrite-modern-av.mov") == "atruswrite")
        #expect(LooseMediaManifestImporter.lookupKey("Intro Wind Mov-modern-audio.m4a") == "intro wind mov")
        #expect(LooseMediaManifestImporter.lookupKey("Intro   Wind_Mov") == "intro wind mov")
        #expect(LooseMediaManifestImporter.lookupKey("Atrus1 NoPage.MooV") == "atrus1 nopage")
        #expect(LooseMediaManifestImporter.lookupKey("BR Seagulls/Water Slosh Mx MoV") == "br seagulls water slosh mx mov")
        #expect(LooseMediaManifestImporter.lookupKey("BR Seagulls:Water Slosh Mx Mov") == "br seagulls water slosh mx mov")
    }

    private var samplePNG: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/luz9XwAAAABJRU5ErkJggg==")!
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hype-loose-media-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

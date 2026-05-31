import Foundation
import Testing
@testable import HypeCore

@Suite("StackImport package document importer")
struct StackImportPackageDocumentImporterTests {
    @Test("converts xstk package, applies stack library, and saves hype package")
    func convertsPackageAppliesStackLibraryAndSavesPackage() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let packageURL = root.appendingPathComponent("Sample.xstk", isDirectory: true)
        let outputURL = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try writeSyntheticPackage(at: packageURL)

        let allRes = HypeStackLibraryEntry(
            stackName: "ALLRes",
            aliases: ["ALLRes", "ALL Res"],
            source: .importedStackPackage,
            packagePath: "exports/stacks/ALLRes.xstk",
            legacyFirstCardId: 5907,
            cardCount: 1,
            stackScript: "on sharedHandler\nreturn \"allres\"\nend sharedHandler",
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 5907, name: "Resources", sortIndex: 0)
            ]
        )
        let myst = HypeStackLibraryEntry(
            stackName: "Myst",
            aliases: ["Myst"],
            source: .importedStackPackage,
            packagePath: "exports/stacks/Myst.xstk",
            legacyFirstCardId: 21776,
            cardCount: 330
        )
        let sample = HypeStackLibraryEntry(
            stackName: "Sample",
            aliases: ["Sample"],
            source: .importedStackPackage,
            packagePath: packageURL.path,
            legacyFirstCardId: 100,
            cardCount: 1,
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 100, name: "Card", sortIndex: 0)
            ]
        )

        let result = try StackImportPackageDocumentImporter().importPackage(
            options: StackImportPackageDocumentImportOptions(
                packageURL: packageURL,
                outputDirectoryURL: outputURL,
                outputFileName: "Sample-debug.hype",
                stackLibraryEntries: [allRes, myst, sample],
                usedStackAliases: ["ALLRes"]
            )
        )

        #expect(result.summary.stackName == "Sample")
        #expect(result.summary.cardCount == 1)
        #expect(result.summary.backgroundCount == 1)
        #expect(result.summary.partCount == 1)
        #expect(result.summary.outputPackagePath.hasSuffix("Sample-debug.hype"))
        #expect(result.summary.stackLibrary?.entryCount == 3)
        #expect(result.summary.stackLibrary?.usedStackAliases == ["ALLRes"])
        #expect(result.document.stackLibrary.resolution(for: "all res") == .resolved(allRes))
        #expect(result.document.stackLibrary.entries.first?.stackScript?.contains("sharedHandler") == true)
        #expect(result.document.stackLibrary.entries.first?.cardReferences.first?.legacyCardId == 5907)
        guard case .resolved(let sampleEntry) = result.document.stackLibrary.resolution(for: "Sample") else {
            Issue.record("Expected Sample stack library entry")
            return
        }
        #expect(sampleEntry.documentPath == result.outputPackageURL.path)
        #expect(sampleEntry.cardReferences.first?.hypeCardId == result.document.cards.first?.id)

        let reloaded = try HypeSQLiteStackStore().load(fromPackageAt: result.outputPackageURL)
        #expect(reloaded.stack.name == "Sample")
        #expect(reloaded.cards.count == 1)
        #expect(reloaded.stackLibrary.resolution(for: "Myst") == .resolved(myst))
        guard case .resolved(let reloadedSampleEntry) = reloaded.stackLibrary.resolution(for: "Sample") else {
            Issue.record("Expected reloaded Sample stack library entry")
            return
        }
        #expect(reloadedSampleEntry.documentPath == result.outputPackageURL.path)
        #expect(ProjectNavigationTargetResolver.resolveCardId(
            for: ProjectNavigationTarget(
                stackEntryId: reloadedSampleEntry.id,
                stackName: "Sample",
                stackAlias: "Sample",
                legacyCardId: 100,
                cardName: "Card"
            ),
            in: reloaded
        ) == reloaded.cards.first?.id)
    }

    @Test("imports requested loose media and reports missing classic media")
    func importsRequestedLooseMediaAndReportsMissingClassicMedia() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let packageURL = root.appendingPathComponent("Sample.xstk", isDirectory: true)
        let outputURL = root.appendingPathComponent("out", isDirectory: true)
        let mediaRoot = root.appendingPathComponent("Myst Source", isDirectory: true)
        let moviesURL = mediaRoot.appendingPathComponent("Movies", isDirectory: true)
        let movieURL = moviesURL.appendingPathComponent("Intro Wind Mov", isDirectory: false)
        let manifestURL = root.appendingPathComponent("loose-media.tsv", isDirectory: false)
        let movieData = Data("classic movie bytes".utf8)

        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: moviesURL, withIntermediateDirectories: true)
        try writeSyntheticPackage(at: packageURL)
        try movieData.write(to: movieURL)
        try Data("""
        rel_path\tsource_path\toutput_path\tsize\tsha256\tfinder_type\tcreator\tsuffix\tkind
        Movies/Intro Wind Mov\t<myst-source-root>/Movies/Intro Wind Mov\t\t19\tmoviehash\tMYqt\tMYST\t\tunknown_binary
        Movies/Missing Mov\t<myst-source-root>/Movies/Missing Mov\t\t10\tmissinghash\tMYqt\tMYST\t\tquicktime_movie
        """.utf8).write(to: manifestURL)

        let result = try StackImportPackageDocumentImporter().importPackage(
            options: StackImportPackageDocumentImportOptions(
                packageURL: packageURL,
                outputDirectoryURL: outputURL,
                outputFileName: "Sample-debug.hype",
                looseMediaManifestURL: manifestURL,
                looseMediaSourceRootURL: mediaRoot,
                looseMediaNames: ["Intro Wind Mov", "Missing Mov"]
            )
        )

        #expect(result.summary.looseMedia?.importedAssetCount == 1)
        #expect(result.summary.looseMedia?.imported == [
            StackImportLooseMediaImportedAssetSummary(
                relPath: "Movies/Intro Wind Mov",
                name: "Intro Wind Mov",
                assetName: "Intro Wind Mov",
                kind: AssetKind.videoClip.rawValue,
                resolvedPath: movieURL.path
            )
        ])
        #expect(result.summary.looseMedia?.missing == [
            LooseMediaImportDiagnostic(
                relPath: "Movies/Missing Mov",
                name: "Missing Mov",
                reason: "file not found"
            )
        ])

        let imported = try #require(result.document.assetRepository.asset(byClassicMediaName: "Intro Wind Mov", kind: .videoClip))
        #expect(imported.data == movieData)
        #expect(imported.metadata.contains { $0.key == "rel_path" && $0.value == "Movies/Intro Wind Mov" })

        let reloaded = try HypeSQLiteStackStore().load(fromPackageAt: result.outputPackageURL)
        let reloadedMovie = try #require(reloaded.assetRepository.asset(byClassicMediaName: "Intro Wind Mov", kind: .videoClip))
        #expect(reloadedMovie.data == movieData)
    }

    @Test("project importer writes related document paths into every stack library")
    func projectImporterWritesRelatedDocumentPathsIntoEveryStackLibrary() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let samplePackageURL = root.appendingPathComponent("Sample.xstk", isDirectory: true)
        let otherPackageURL = root.appendingPathComponent("Other.xstk", isDirectory: true)
        let outputURL = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: samplePackageURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherPackageURL, withIntermediateDirectories: true)
        try writeSyntheticPackage(at: samplePackageURL, name: "Sample", cardId: 100, cardName: "Sample Card")
        try writeSyntheticPackage(at: otherPackageURL, name: "Other", cardId: 200, cardName: "Other Card")

        let sampleEntry = HypeStackLibraryEntry(
            stackName: "Sample",
            source: .importedStackPackage,
            packagePath: samplePackageURL.path,
            legacyFirstCardId: 100,
            cardCount: 1,
            cardReferences: [HypeStackLibraryCardReference(legacyCardId: 100, name: "Sample Card", sortIndex: 0)]
        )
        let otherEntry = HypeStackLibraryEntry(
            stackName: "Other",
            source: .importedStackPackage,
            packagePath: otherPackageURL.path,
            legacyFirstCardId: 200,
            cardCount: 1,
            cardReferences: [HypeStackLibraryCardReference(legacyCardId: 200, name: "Other Card", sortIndex: 0)]
        )

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: [samplePackageURL, otherPackageURL],
                outputDirectoryURL: outputURL,
                stackLibraryEntries: [sampleEntry, otherEntry]
            )
        )

        #expect(result.summary.stackCount == 2)
        #expect(result.summary.stackLibraryEntryCount == 2)
        #expect(result.summary.outputPackagePaths.count == 2)
        #expect(result.summary.stacks.map(\.stackName) == ["Sample", "Other"])
        #expect(result.summary.stacks.map(\.firstCardName) == ["Sample Card", "Other Card"])
        #expect(result.summary.stacks.map(\.legacyFirstCardId) == [100, 200])
        #expect(result.summary.stacks.map(\.documentPath) == result.summary.outputPackagePaths)
        #expect(result.summary.stacks.allSatisfy { $0.firstCardId != nil })

        let reloadedSample = try HypeSQLiteStackStore().load(fromPackageAt: result.packageResults[0].outputPackageURL)
        let reloadedOther = try HypeSQLiteStackStore().load(fromPackageAt: result.packageResults[1].outputPackageURL)
        guard case .resolved(let sampleInSample) = reloadedSample.stackLibrary.resolution(for: "Sample"),
              case .resolved(let otherInSample) = reloadedSample.stackLibrary.resolution(for: "Other"),
              case .resolved(let sampleInOther) = reloadedOther.stackLibrary.resolution(for: "Sample"),
              case .resolved(let otherInOther) = reloadedOther.stackLibrary.resolution(for: "Other") else {
            Issue.record("Expected both imported documents to carry both stack library entries")
            return
        }

        #expect(sampleInSample.documentPath == result.packageResults[0].outputPackageURL.path)
        #expect(otherInSample.documentPath == result.packageResults[1].outputPackageURL.path)
        #expect(sampleInOther.documentPath == result.packageResults[0].outputPackageURL.path)
        #expect(otherInOther.documentPath == result.packageResults[1].outputPackageURL.path)
        #expect(sampleInSample.cardReferences.first?.hypeCardId == reloadedSample.cards.first?.id)
        #expect(otherInOther.cardReferences.first?.hypeCardId == reloadedOther.cards.first?.id)

        let target = ProjectNavigationTarget(
            stackEntryId: otherInSample.id,
            stackName: "Other",
            stackAlias: "Other",
            documentPath: otherInSample.documentPath,
            legacyCardId: 200,
            cardName: "Other Card"
        )
        #expect(ProjectNavigationTargetResolver.resolveCardId(for: target, in: reloadedOther) == reloadedOther.cards.first?.id)
    }

    @Test("project importer keeps same-named package entries distinct by package path")
    func projectImporterKeepsSameNamedPackageEntriesDistinctByPackagePath() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let appPackageURL = root.appendingPathComponent("Myst-Application.xstk", isDirectory: true)
        let islandPackageURL = root.appendingPathComponent("Myst.xstk", isDirectory: true)
        let outputURL = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: appPackageURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: islandPackageURL, withIntermediateDirectories: true)
        try writeSyntheticPackage(at: appPackageURL, name: " Myst", cardId: 2953, cardName: "Application")
        try writeSyntheticPackage(at: islandPackageURL, name: " Myst", cardId: 21776, cardName: "Dock")

        let appEntry = HypeStackLibraryEntry(
            stackName: " Myst",
            aliases: ["Myst-Application"],
            source: .importedStackPackage,
            packagePath: appPackageURL.path,
            legacyFirstCardId: 2953,
            cardCount: 1,
            cardReferences: [HypeStackLibraryCardReference(legacyCardId: 2953, name: "Application", sortIndex: 0)]
        )
        let islandEntry = HypeStackLibraryEntry(
            stackName: " Myst",
            aliases: ["Myst"],
            source: .importedStackPackage,
            packagePath: islandPackageURL.path,
            legacyFirstCardId: 21776,
            cardCount: 1,
            cardReferences: [HypeStackLibraryCardReference(legacyCardId: 21776, name: "Dock", sortIndex: 0)]
        )

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: [appPackageURL, islandPackageURL],
                outputDirectoryURL: outputURL,
                stackLibraryEntries: [appEntry, islandEntry]
            )
        )

        #expect(result.summary.outputPackagePaths.count == Set(result.summary.outputPackagePaths).count)
        #expect(result.packageResults[0].outputPackageURL.lastPathComponent == "Myst-Application-debug-imported.hype")
        #expect(result.packageResults[1].outputPackageURL.lastPathComponent == "Myst-debug-imported.hype")

        let reloadedIsland = try HypeSQLiteStackStore().load(fromPackageAt: result.packageResults[1].outputPackageURL)
        let appInIsland = try #require(reloadedIsland.stackLibrary.entries.first { $0.packagePath == appPackageURL.path })
        let islandInIsland = try #require(reloadedIsland.stackLibrary.entries.first { $0.packagePath == islandPackageURL.path })

        #expect(appInIsland.documentPath == result.packageResults[0].outputPackageURL.path)
        #expect(islandInIsland.documentPath == result.packageResults[1].outputPackageURL.path)
        #expect(appInIsland.cardReferences.first?.legacyCardId == 2953)
        #expect(islandInIsland.cardReferences.first?.legacyCardId == 21776)
        #expect(appInIsland.cardReferences.first?.hypeCardId != islandInIsland.cardReferences.first?.hypeCardId)
        #expect(islandInIsland.cardReferences.first?.hypeCardId == reloadedIsland.cards.first?.id)
    }

    @Test("project importer shares content stack assets into related stacks")
    func projectImporterSharesContentStackAssetsIntoRelatedStacks() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let contentPackageURL = root.appendingPathComponent("ALLRes.xstk", isDirectory: true)
        let mystPackageURL = root.appendingPathComponent("Myst.xstk", isDirectory: true)
        let outputURL = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: contentPackageURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mystPackageURL, withIntermediateDirectories: true)
        try writeSyntheticPackage(at: contentPackageURL, name: "ALLRes", cardId: 5907, cardName: "Resources")
        try writeSyntheticPackage(at: mystPackageURL, name: "Myst", cardId: 21776, cardName: "Dock")
        try writeSyntheticResourceManifest(
            at: contentPackageURL,
            type: "PICT",
            id: 128,
            name: "Shared View",
            artifactPath: "PICT_128.png",
            mediaType: "image/png",
            data: Data("shared pict bytes".utf8)
        )

        let allResEntry = HypeStackLibraryEntry(
            stackName: "ALLRes",
            source: .importedStackPackage,
            packagePath: contentPackageURL.path,
            legacyFirstCardId: 5907,
            cardCount: 1,
            cardReferences: [HypeStackLibraryCardReference(legacyCardId: 5907, name: "Resources", sortIndex: 0)],
            metadata: [HypeStackLibraryMetadataEntry(key: "contentStack", value: "true")]
        )
        let mystEntry = HypeStackLibraryEntry(
            stackName: "Myst",
            source: .importedStackPackage,
            packagePath: mystPackageURL.path,
            legacyFirstCardId: 21776,
            cardCount: 1,
            cardReferences: [HypeStackLibraryCardReference(legacyCardId: 21776, name: "Dock", sortIndex: 0)]
        )

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: [contentPackageURL, mystPackageURL],
                outputDirectoryURL: outputURL,
                stackLibraryEntries: [allResEntry, mystEntry],
                usedStackAliases: ["ALLRes"]
            )
        )

        #expect(result.summary.sharedContentAssetCopyCount >= 1)
        #expect(result.summary.packages.first?.sharedContentAssetCount == 0)
        #expect(result.summary.packages.last?.sharedContentAssetCount == result.summary.sharedContentAssetCopyCount)

        let reloadedMyst = try HypeSQLiteStackStore().load(fromPackageAt: result.packageResults[1].outputPackageURL)
        let shared = try #require(reloadedMyst.assetRepository.assets.first { asset in
            asset.metadata.contains { $0.key == "classic_name" && $0.value == "Shared View" }
        })
        #expect(shared.data == Data("shared pict bytes".utf8))
        #expect(shared.tags.contains("content-stack-shared"))
        #expect(shared.metadata.contains { $0.key == "shared_from_content_stack" && $0.value == "ALLRes" })
        #expect(shared.metadata.contains { $0.key == "shared_from_asset_id" })
        #expect(reloadedMyst.assetRepository.assets.first { asset in
            asset.metadata.contains { $0.key == "classic_name" && $0.value == "PICT 128" }
        }?.id == shared.id)

        let reloadedAllRes = try HypeSQLiteStackStore().load(fromPackageAt: result.packageResults[0].outputPackageURL)
        #expect(reloadedAllRes.assetRepository.assets.filter { asset in
            asset.metadata.contains { $0.key == "shared_from_content_stack" }
        }.isEmpty)
    }

    private func writeSyntheticPackage(
        at url: URL,
        name: String = "Sample",
        cardId: Int = 100,
        cardName: String = "Card"
    ) throws {
        try Data("""
        {"sourceFileName":"\(name)","stackFile":"stack_-1.json","blocks":[],"fonts":[{"id":1,"name":"Chicago"}]}
        """.utf8).write(to: url.appendingPathComponent("project.json"))
        try Data("""
        {"name":"\(name)","cardWidth":512,"cardHeight":342,"script":"","pages":[{"cardIds":[\(cardId)]}],"layers":[{"kind":"background","id":10,"file":"background_10.json"},{"kind":"card","id":\(cardId),"owner":10,"file":"card_\(cardId).json"}]}
        """.utf8).write(to: url.appendingPathComponent("stack_-1.json"))
        try Data("""
        {"id":10,"bitmap":null,"name":"Background","script":"","parts":[],"contents":[]}
        """.utf8).write(to: url.appendingPathComponent("background_10.json"))
        try Data("""
        {"id":\(cardId),"bitmap":null,"name":"\(cardName)","script":"on openCard\\rplayQT \\"Intro Wind Mov\\"\\rend openCard","parts":[{"id":1,"type":"button","style":"transparent","rect":{"left":10,"top":20,"right":110,"bottom":50},"name":"Start","script":"on mouseUp\\rgo next\\rend mouseUp"}],"contents":[]}
        """.utf8).write(to: url.appendingPathComponent("card_\(cardId).json"))
        try Data("""
        {"sourcePath":"/Myst/\(name)","outputPackage":"\(name).xstk","dataForkBytes":123,"resourceForkBytes":456,"resources":[]}
        """.utf8).write(to: url.appendingPathComponent("source-manifest.json"))
    }

    private func writeSyntheticResourceManifest(
        at url: URL,
        type: String,
        id: Int,
        name: String,
        artifactPath: String,
        mediaType: String,
        data: Data
    ) throws {
        try Data("""
        {
          "sourcePath": "/Myst/\(url.deletingPathExtension().lastPathComponent)",
          "outputPackage": "\(url.lastPathComponent)",
          "sourceFile": {"resourceForkBytes": \(data.count)},
          "resourceFork": {
            "resources": [
              {
                "type": "\(type)",
                "id": \(id),
                "flags": 0,
                "name": "\(name)",
                "bytes": \(data.count),
                "status": "exported",
                "outputArtifacts": [
                  {"path": "\(artifactPath)", "format": "\(URL(fileURLWithPath: artifactPath).pathExtension)", "mediaType": "\(mediaType)", "description": "synthetic test artifact", "variantIndex": 0}
                ]
              }
            ]
          }
        }
        """.utf8).write(to: url.appendingPathComponent("source-manifest.json"))
        try data.write(to: url.appendingPathComponent(artifactPath))
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hype-stackimport-document-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

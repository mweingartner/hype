import Foundation
import Testing
@testable import HypeCore

#if canImport(AppKit)
import AppKit
#endif

@Suite(
    "Myst stackimport local acceptance",
    .disabled(if: ProcessInfo.processInfo.environment["MYST_EXPORT_ROOT"] == nil)
)
struct MystStackImportAcceptanceTests {
    @Test("imports first-path Myst project packages with stack library and shared assets")
    func importsFirstPathMystProjectPackages() throws {
        let root = try mystExportRoot()
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)
        let packageURLs = [
            stacksRoot.appendingPathComponent("Myst-Application.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("ALLRes.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("INRes1.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true),
        ]
        let outputURL = makeTemporaryDirectory(prefix: "hype-myst-project")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let sourceRootURL = try materializeMystSourceArchive(
            root: root,
            entries: [
                "Myst/Myst Graphics/Myst/AR Howling&Birds Mov",
                "Myst/Myst Graphics/Myst/BR Seagulls:Water Slosh Mx Mov",
                "Myst/Myst Graphics/Myst/Intro Wind Mov",
            ]
        )
        defer { try? FileManager.default.removeItem(at: sourceRootURL.deletingLastPathComponent()) }

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: packageURLs,
                outputDirectoryURL: outputURL,
                looseMediaManifestURL: root.appendingPathComponent("manifests/loose-media.tsv"),
                looseMediaSourceRootURL: sourceRootURL,
                looseMediaReplacementRootURL: root.appendingPathComponent("exports/modern-quicktime", isDirectory: true),
                looseMediaNames: [
                    "AtrusWrite",
                    "Atrus1 Page",
                    "Intro Wind Mov",
                    "AR Howling&Birds Mov",
                    "BR Seagulls/Water Slosh Mx MoV",
                ],
                stackLibraryEntries: packageURLs.map(stackLibraryEntry),
                usedStackAliases: ["ALLRes", "INRes1"]
            )
        )

        #expect(result.summary.stackCount == 4)
        #expect(result.summary.stackLibraryEntryCount == 4)
        #expect(result.summary.outputPackagePaths.allSatisfy { FileManager.default.fileExists(atPath: $0) })
        #expect(result.summary.sharedContentAssetCopyCount > 0)
        #expect(result.summary.packages.allSatisfy { $0.stackLibrary?.entryCount == 4 })
        #expect(result.summary.packages.allSatisfy { $0.looseMedia?.missing.isEmpty == true })

        let parseFailures = result.packageResults.flatMap { storedScriptParseFailures(in: $0.document) }
        #expect(parseFailures.isEmpty)

        let mystResult = try #require(result.packageResults.first { $0.document.stack.name == "Myst" })
        let mystDocument = try HypeSQLiteStackStore().load(fromPackageAt: mystResult.outputPackageURL)
        let legacyMystCards = try legacyCardMap(
            packageURL: stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true),
            document: mystDocument
        )

        #expect(mystDocument.stackLibrary.resolution(for: "ALLRes").isResolved)
        #expect(mystDocument.stackLibrary.resolution(for: "INRes1").isResolved)
        #expect(mystDocument.assetRepository.asset(byName: "AtrusWrite")?.kind == .videoClip)
        #expect(mystDocument.assetRepository.asset(byClassicMediaName: "BR Seagulls/Water Slosh Mx MoV", kind: .videoClip) != nil)
        #expect(mystDocument.assetRepository.assets.contains { asset in
            asset.metadata.contains { $0.key == "shared_from_content_stack" }
        })

        let diagnostics = try #require(mystDocument.legacyImport?.report.stackImportDiagnostics)
        #expect(diagnostics.fontSummary?.contains { $0.name == "Chicago" && !$0.resolvedFontName.isEmpty } == true)
        #expect(diagnostics.externalCallSummary.contains { $0.name.caseInsensitiveCompare("playQT") == .orderedSame })

        try assertImportedButtonNavigates(
            scriptFragment: "go to card id 22764",
            fromLegacyCardId: 21776,
            toLegacyCardId: 22764,
            legacyCardMap: legacyMystCards,
            document: mystDocument
        )
        try assertImportedButtonNavigates(
            scriptFragment: "go to card id 21716",
            fromLegacyCardId: 21776,
            toLegacyCardId: 21716,
            legacyCardMap: legacyMystCards,
            document: mystDocument
        )
        try assertImportedButtonNavigates(
            scriptFragment: "go to card id 22034",
            fromLegacyCardId: 21776,
            toLegacyCardId: 22034,
            legacyCardMap: legacyMystCards,
            document: mystDocument
        )
    }

    @Test("imports selected Myst loose media from manifest")
    func importsSelectedMystLooseMediaFromManifest() throws {
        let root = try mystExportRoot()
        let sourceRoot = try materializeMystSourceArchive(
            root: root,
            entries: [
                "Myst/Myst Graphics/Myst/AR Howling&Birds Mov",
                "Myst/Myst Graphics/Myst/BR Seagulls:Water Slosh Mx Mov",
                "Myst/Myst Graphics/Myst/Intro Wind Mov",
            ]
        )
        defer { try? FileManager.default.removeItem(at: sourceRoot.deletingLastPathComponent()) }

        var document = HypeDocument.newDocument(name: "Myst Loose Media")
        let result = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: root.appendingPathComponent("manifests/loose-media.tsv"),
                sourceRootURL: sourceRoot,
                replacementRootURL: root.appendingPathComponent("exports/modern-quicktime", isDirectory: true),
                requestedNames: [
                    "AtrusWrite",
                    "Atrus1 Page",
                    "Intro Wind Mov",
                    "AR Howling&Birds Mov",
                    "BR Seagulls/Water Slosh Mx MoV",
                ]
            ),
            into: &document
        )

        #expect(result.importedAssets.count >= 5)
        #expect(document.assetRepository.asset(byName: "AtrusWrite")?.kind == .videoClip)
        #expect(document.assetRepository.asset(byName: "Atrus1 Page")?.kind == .videoClip)

        let intro = try #require(document.assetRepository.assets.first { $0.name == "Intro Wind Mov" })
        #expect(intro.kind == .videoClip)
        #expect(intro.tags.contains("finder-myqt"))
        #expect(intro.metadata.contains { $0.key == "quicktime_audio_only" && $0.value == "true" })
        #expect(intro.metadata.contains { $0.key == "resolved_path" && $0.value.contains("modern-quicktime") })

        let seagulls = try #require(document.assetRepository.asset(byClassicMediaName: "BR Seagulls/Water Slosh Mx MoV", kind: .videoClip))
        #expect(seagulls.name == "BR Seagulls:Water Slosh Mx Mov")
        #expect(seagulls.metadata.contains { $0.key == "quicktime_audio_only" && $0.value == "true" })
        #expect(seagulls.metadata.contains { $0.key == "resolved_path" && $0.value.contains("modern-quicktime") })
    }

    @Test("imports broader converted Myst QuickTime batches from manifest")
    func importsBroaderConvertedMystQuickTimeBatchesFromManifest() throws {
        let root = try mystExportRoot()
        var document = HypeDocument.newDocument(name: "Myst Broader QuickTime")
        let names = [
            "Intro",
            "Holo-SMessage",
            "Fountain",
            "Caldera South",
            "EV StoneForest Mov",
        ]
        let result = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: root.appendingPathComponent("manifests/loose-media.tsv"),
                replacementRootURL: root.appendingPathComponent("exports/modern-quicktime", isDirectory: true),
                requestedNames: Set(names)
            ),
            into: &document
        )

        #expect(result.missing.isEmpty)
        #expect(result.importedAssets.count == names.count)

        let intro = try #require(document.assetRepository.asset(byClassicMediaName: "Intro", kind: .videoClip))
        #expect(intro.mimeType == "video/quicktime")
        #expect(intro.metadata.contains { $0.key == "quicktime_audio_only" && $0.value.isEmpty })
        #expect(intro.metadata.contains { $0.key == "resolved_path" && $0.value.hasSuffix("Intro-modern-av.mov") })

        let holo = try #require(document.assetRepository.asset(byClassicMediaName: "Holo-SMessage", kind: .videoClip))
        #expect(holo.mimeType == "video/quicktime")
        #expect(holo.metadata.contains { $0.key == "resolved_path" && $0.value.hasSuffix("Holo-SMessage-modern-av.mov") })

        let fountain = try #require(document.assetRepository.asset(byClassicMediaName: "Fountain", kind: .videoClip))
        #expect(fountain.mimeType == "video/quicktime")
        #expect(fountain.metadata.contains { $0.key == "resolved_path" && $0.value.hasSuffix("Fountain-modern.mov") })

        let caldera = try #require(document.assetRepository.asset(byClassicMediaName: "Caldera South", kind: .videoClip))
        #expect(caldera.mimeType == "video/quicktime")
        #expect(caldera.metadata.contains { $0.key == "resolved_path" && $0.value.hasSuffix("Caldera South-modern.mov") })

        let stoneForest = try #require(document.assetRepository.asset(byClassicMediaName: "EV StoneForest Mov", kind: .videoClip))
        #expect(stoneForest.mimeType == "video/quicktime")
        #expect(stoneForest.metadata.contains { $0.key == "quicktime_audio_only" && $0.value == "true" })
        #expect(stoneForest.metadata.contains { $0.key == "resolved_path" && $0.value.hasSuffix("EV StoneForest Mov-modern-audio.m4a") })
    }

    @Test("runs broader converted Myst QuickTime assets through runtime")
    func runsBroaderConvertedMystQuickTimeAssetsThroughRuntime() throws {
        let root = try mystExportRoot()
        var document = HypeDocument.newDocument(name: "Myst Broader QuickTime Runtime")
        let mediaNames: Set<String> = [
            "Intro",
            "Holo-SMessage",
            "Fountain",
            "EV StoneForest Mov",
        ]
        let importResult = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: root.appendingPathComponent("manifests/loose-media.tsv"),
                replacementRootURL: root.appendingPathComponent("exports/modern-quicktime", isDirectory: true),
                requestedNames: mediaNames
            ),
            into: &document
        )
        #expect(importResult.missing.isEmpty)

        let currentCardId = try #require(document.sortedCards.first?.id)
        let script = try parseScript("""
        on test
          xSetSoundVol 128
          playQT "Intro", "loop"
          playQT "EV StoneForest Mov"
          Movie "Fountain","borderless","12,34","visible","FountainWindow"
          send play to window "FountainWindow"
          send movieIdle to window "FountainWindow"
          send pause to window "FountainWindow"
          playQT "Holo-SMessage"
          return the lastMessage of window "FountainWindow"
        end test
        """)
        let handler = try #require(script.handlers.first { $0.name.caseInsensitiveCompare("test") == .orderedSame })
        let result = Interpreter().execute(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: document.stack.id, currentCardId: currentCardId, document: document)
        )

        #expect(result.status == .completed)
        #expect(result.returnValue == "pause")
        let runtimeDocument = try #require(result.modifiedDocument)
        let videoParts = runtimeDocument.partsForCard(currentCardId).filter { $0.partType == .video }
        #expect(videoParts.count == mediaNames.count)

        let intro = try #require(videoParts.first { $0.name == "Intro" })
        let introAsset = try #require(runtimeDocument.assetRepository.asset(byClassicMediaName: "Intro", kind: .videoClip))
        #expect(intro.videoAssetRef?.id == introAsset.id)
        #expect(intro.videoLoop == true)
        #expect(intro.videoAutoplay == true)
        #expect(intro.videoVolume == 128.0 / 255.0)
        #expect(intro.width == Double(runtimeDocument.stack.width))
        #expect(intro.height == Double(runtimeDocument.stack.height))

        let stoneForest = try #require(videoParts.first { $0.name == "EV StoneForest Mov" })
        let stoneForestAsset = try #require(runtimeDocument.assetRepository.asset(byClassicMediaName: "EV StoneForest Mov", kind: .videoClip))
        #expect(stoneForest.videoAssetRef?.id == stoneForestAsset.id)
        #expect(stoneForest.width == 1)
        #expect(stoneForest.height == 1)
        #expect(stoneForest.helpText.contains("audioOnly=true"))

        let fountain = try #require(videoParts.first { $0.name == "Fountain" })
        let fountainAsset = try #require(runtimeDocument.assetRepository.asset(byClassicMediaName: "Fountain", kind: .videoClip))
        #expect(fountain.videoAssetRef?.id == fountainAsset.id)
        #expect(fountain.left == 12)
        #expect(fountain.top == 34)
        #expect(fountain.videoAutoplay == false)
        #expect(runtimeDocument.scriptGlobals["hypercard.window.fountainwindow.message.play.count"] == "1")
        #expect(runtimeDocument.scriptGlobals["hypercard.window.fountainwindow.message.movieidle.count"] == "1")
        #expect(runtimeDocument.scriptGlobals["hypercard.window.fountainwindow.message.pause.count"] == "1")
        #expect(runtimeDocument.scriptGlobals["hypercard.window.fountainwindow.rate"] == "0.0")

        let holo = try #require(videoParts.first { $0.name == "Holo-SMessage" })
        let holoAsset = try #require(runtimeDocument.assetRepository.asset(byClassicMediaName: "Holo-SMessage", kind: .videoClip))
        #expect(holo.videoAssetRef?.id == holoAsset.id)
        #expect(holo.videoAutoplay == true)
    }

    @Test("imports full Myst project with shared content and broader loose media")
    func importsFullMystProjectWithSharedContentAndBroaderLooseMedia() throws {
        let root = try mystExportRoot()
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)
        let packageNames = [
            "Myst-Application.xstk",
            "ALLRes.xstk",
            "INRes1.xstk",
            "Myst.xstk",
            "Mechanical-Age.xstk",
            "Stoneship-Age.xstk",
            "Channelwood-Age.xstk",
            "Selenitic-Age.xstk",
            "Dunny-Age.xstk",
        ]
        let packageURLs = packageNames.map { stacksRoot.appendingPathComponent($0, isDirectory: true) }
        let outputURL = makeTemporaryDirectory(prefix: "hype-myst-full-media")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let mediaNames: Set<String> = [
            "Intro",
            "Holo-SMessage",
            "Fountain",
            "Caldera South",
            "EV StoneForest Mov",
        ]

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: packageURLs,
                outputDirectoryURL: outputURL,
                looseMediaManifestURL: root.appendingPathComponent("manifests/loose-media.tsv"),
                looseMediaReplacementRootURL: root.appendingPathComponent("exports/modern-quicktime", isDirectory: true),
                looseMediaNames: mediaNames,
                stackLibraryEntries: packageURLs.map(stackLibraryEntry),
                usedStackAliases: ["ALLRes", "INRes1"]
            )
        )

        #expect(result.summary.stackCount == packageNames.count)
        #expect(result.summary.sourcePackagePaths.count == packageNames.count)
        #expect(result.summary.outputPackagePaths.count == packageNames.count)
        #expect(result.summary.outputPackagePaths.allSatisfy { FileManager.default.fileExists(atPath: $0) })
        #expect((result.summary.totalOutputPackageByteCount ?? 0) > 0)
        #expect(result.summary.sharedContentAssetCopyCount > 0)
        #expect(result.summary.packages.count == packageNames.count)
        #expect(result.summary.packages.allSatisfy { $0.sourcePackagePath?.hasSuffix(".xstk") == true })
        #expect(result.summary.packages.allSatisfy { ($0.outputPackageByteCount ?? 0) > 0 })
        #expect(result.summary.packages.allSatisfy { $0.sharedContentAssetCount > 0 })
        #expect(result.summary.packages.allSatisfy { $0.looseMedia?.missing.isEmpty == true })
        #expect(result.summary.packages.allSatisfy { $0.looseMedia?.importedAssetCount == mediaNames.count })
        #expect(result.summary.packages.allSatisfy { package in
            let importedNames = Set(package.looseMedia?.imported.map(\.name) ?? [])
            return mediaNames.isSubset(of: importedNames)
        })
        let disabledImportedScripts = result.packageResults.flatMap { package in
            storedScripts(in: package.document).compactMap { script in
                LegacyHyperTalkScript.isDisabledForHypeTalkRuntime(script.source)
                    ? "\(package.document.stack.name): \(script.ownerPath)"
                    : nil
            }
        }
        #expect(disabledImportedScripts.isEmpty)
    }

    @Test("full Myst project packages survive SQLite save reload validation")
    func fullMystProjectPackagesSurviveSQLiteSaveReloadValidation() throws {
        let root = try mystExportRoot()
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)
        let packageNames = [
            "Myst-Application.xstk",
            "ALLRes.xstk",
            "INRes1.xstk",
            "Myst.xstk",
            "Mechanical-Age.xstk",
            "Stoneship-Age.xstk",
            "Channelwood-Age.xstk",
            "Selenitic-Age.xstk",
            "Dunny-Age.xstk",
        ]
        let packageURLs = packageNames.map { stacksRoot.appendingPathComponent($0, isDirectory: true) }
        let outputURL = makeTemporaryDirectory(prefix: "hype-myst-persistence-source")
        let roundTripRootURL = makeTemporaryDirectory(prefix: "hype-myst-persistence-roundtrip")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: roundTripRootURL)
        }
        let mediaNames: Set<String> = [
            "Intro",
            "Holo-SMessage",
            "Fountain",
            "Caldera South",
            "EV StoneForest Mov",
        ]

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: packageURLs,
                outputDirectoryURL: outputURL,
                looseMediaManifestURL: root.appendingPathComponent("manifests/loose-media.tsv"),
                looseMediaReplacementRootURL: root.appendingPathComponent("exports/modern-quicktime", isDirectory: true),
                looseMediaNames: mediaNames,
                stackLibraryEntries: packageURLs.map(stackLibraryEntry),
                usedStackAliases: ["ALLRes", "INRes1"]
            )
        )

        #expect(result.packageResults.count == packageNames.count)
        let store = HypeSQLiteStackStore()
        for packageResult in result.packageResults {
            let original = try store.load(fromPackageAt: packageResult.outputPackageURL)
            let roundTripURL = roundTripRootURL.appendingPathComponent(packageResult.outputPackageURL.lastPathComponent, isDirectory: true)
            try store.save(original, toPackageAt: roundTripURL)
            let diagnostics = try store.validate(packageURL: roundTripURL)
            #expect(diagnostics.isHealthy, "\(roundTripURL.lastPathComponent) failed SQLite validation: \(diagnostics)")

            let reloaded = try store.load(fromPackageAt: roundTripURL)
            #expect(reloaded.stack.id == original.stack.id)
            #expect(reloaded.stack.name == original.stack.name)
            #expect(reloaded.cards.count == original.cards.count)
            #expect(reloaded.backgrounds.count == original.backgrounds.count)
            #expect(reloaded.parts.count == original.parts.count)
            #expect(reloaded.stackLibrary.entries.count == packageNames.count)
            #expect(reloaded.assetRepository.assets.count == original.assetRepository.assets.count)
            #expect(reloaded.assetRepository.assets.filter(isSharedContentAsset).count == original.assetRepository.assets.filter(isSharedContentAsset).count)
            #expect(reloaded.assetRepository.assets.filter { $0.kind == .videoClip }.count == original.assetRepository.assets.filter { $0.kind == .videoClip }.count)
            #expect(reloaded.paintLayers.count == original.paintLayers.count)
            #expect(storedScriptParseFailures(in: reloaded).isEmpty)
        }
    }

    @Test("seeded Myst launcher marker click returns dock project navigation target")
    func seededMystLauncherMarkerClickReturnsDockProjectNavigationTarget() throws {
        let root = try mystExportRoot()
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)
        let packageURLs = [
            stacksRoot.appendingPathComponent("Myst-Application.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("ALLRes.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("INRes1.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true),
        ]
        let outputURL = makeTemporaryDirectory(prefix: "hype-myst-launcher")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: packageURLs,
                outputDirectoryURL: outputURL,
                stackLibraryEntries: packageURLs.map(stackLibraryEntry),
                usedStackAliases: ["ALLRes", "INRes1"]
            )
        )

        let appResult = try #require(result.packageResults.first { $0.outputPackageURL.lastPathComponent == "Myst-Application-debug-imported.hype" })
        var appDocument = try HypeSQLiteStackStore().load(fromPackageAt: appResult.outputPackageURL)
        let allResResult = try #require(result.packageResults.first { $0.outputPackageURL.lastPathComponent == "ALLRes-debug-imported.hype" })
        let allResDocument = try HypeSQLiteStackStore().load(fromPackageAt: allResResult.outputPackageURL)
        appDocument.scriptGlobals = try #require(HyperCardImportedGlobalSeeder.newGameGlobals(
            from: appDocument,
            resourceDocuments: [allResDocument]
        ))
        #expect(appDocument.scriptGlobals["ALL_CurrStack"] == "Myst")
        #expect(appDocument.scriptGlobals["Start_Game"] == "new")
        #expect(appDocument.scriptGlobals["MY_RedBook"] == "000000")

        let appCardMap = try legacyCardMap(
            packageURL: stacksRoot.appendingPathComponent("Myst-Application.xstk", isDirectory: true),
            document: appDocument
        )
        let launcherCardId = try #require(appCardMap[4981])
        let marker = try #require(appDocument.partsForCard(launcherCardId).first { $0.name == "marker2" })
        #expect(!LegacyHyperTalkScript.isDisabledForHypeTalkRuntime(marker.script), "Imported marker2 script should run: \(marker.script)")

        let dispatch = MessageDispatcher().dispatch(
            message: "mouseUp",
            params: [],
            targetId: marker.id,
            document: appDocument,
            currentCardId: launcherCardId
        )

        #expect(dispatch.status == .completed)
        #expect(dispatch.navigationTarget == nil)
        #expect(dispatch.projectNavigationTarget?.stackName == "Myst")
        #expect(dispatch.projectNavigationTarget?.legacyCardId == 8336)
        #expect(dispatch.projectNavigationTarget?.cardName.caseInsensitiveCompare("dock") == .orderedSame)

        let mystResult = try #require(result.packageResults.first { $0.outputPackageURL.lastPathComponent == "Myst-debug-imported.hype" })
        let mystDocument = try HypeSQLiteStackStore().load(fromPackageAt: mystResult.outputPackageURL)
        #expect(ProjectNavigationTargetResolver.resolveCardId(for: try #require(dispatch.projectNavigationTarget), in: mystDocument) != nil)
    }

    @Test("imported Myst age book markers return routable project navigation targets")
    func importedMystAgeBookMarkersReturnRoutableProjectNavigationTargets() throws {
        let root = try mystExportRoot()
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)
        let packageNames = [
            "ALLRes.xstk",
            "INRes1.xstk",
            "Myst.xstk",
            "Mechanical-Age.xstk",
            "Stoneship-Age.xstk",
            "Channelwood-Age.xstk",
        ]
        let packageURLs = packageNames.map { stacksRoot.appendingPathComponent($0, isDirectory: true) }
        let outputURL = makeTemporaryDirectory(prefix: "hype-myst-age-clicks")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: packageURLs,
                outputDirectoryURL: outputURL,
                stackLibraryEntries: packageURLs.map(stackLibraryEntry),
                usedStackAliases: ["ALLRes", "INRes1"]
            )
        )

        let mystResult = try #require(result.packageResults.first { $0.outputPackageURL.lastPathComponent == "Myst-debug-imported.hype" })
        let mystDocument = try HypeSQLiteStackStore().load(fromPackageAt: mystResult.outputPackageURL)
        let mystCardMap = try legacyCardMap(
            packageURL: stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true),
            document: mystDocument
        )

        let cases = [
            AgeBookClickCase(
                sourceLegacyCardId: 72560,
                expectedScriptFragment: "go to card \"Restart\" of stack \"Mechanical Age\"",
                expectedStackName: "Mechanical Age",
                expectedTargetPackageName: "Mechanical-Age-debug-imported.hype",
                expectedTargetLegacyCardId: 17290,
                expectedTargetCardName: "restart"
            ),
            AgeBookClickCase(
                sourceLegacyCardId: 77008,
                expectedScriptFragment: "go to card \"Restart\" of stack \"StoneShip Age\"",
                expectedStackName: "StoneShip Age",
                expectedTargetPackageName: "Stoneship-Age-debug-imported.hype",
                expectedTargetLegacyCardId: 3004,
                expectedTargetCardName: "restart"
            ),
            AgeBookClickCase(
                sourceLegacyCardId: 77588,
                expectedScriptFragment: "go to card \"Restart\" of stack \"Channelwood Age\"",
                expectedStackName: "Channelwood Age",
                expectedTargetPackageName: "Channelwood-Age-debug-imported.hype",
                expectedTargetLegacyCardId: 28497,
                expectedTargetCardName: "restart"
            ),
        ]

        for ageCase in cases {
            let sourceCardId = try #require(mystCardMap[ageCase.sourceLegacyCardId])
            let marker = try #require(mystDocument.partsForCard(sourceCardId).first { part in
                part.name == "marker" && part.script.localizedCaseInsensitiveContains(ageCase.expectedScriptFragment)
            })
            #expect(!LegacyHyperTalkScript.isDisabledForHypeTalkRuntime(marker.script), "Imported age-book marker script should run: \(marker.script)")

            let dispatch = MessageDispatcher().dispatch(
                message: "mouseUp",
                params: [],
                targetId: marker.id,
                document: mystDocument,
                currentCardId: sourceCardId
            )

            #expect(dispatch.status == .completed)
            #expect(dispatch.projectNavigationTarget?.stackName.caseInsensitiveCompare(ageCase.expectedStackName) == .orderedSame)
            #expect(dispatch.projectNavigationTarget?.legacyCardId == ageCase.expectedTargetLegacyCardId)
            #expect(dispatch.projectNavigationTarget?.cardName.caseInsensitiveCompare(ageCase.expectedTargetCardName) == .orderedSame)

            let targetResult = try #require(result.packageResults.first {
                $0.outputPackageURL.lastPathComponent == ageCase.expectedTargetPackageName
            })
            let targetDocument = try HypeSQLiteStackStore().load(fromPackageAt: targetResult.outputPackageURL)
            #expect(ProjectNavigationTargetResolver.resolveCardId(for: try #require(dispatch.projectNavigationTarget), in: targetDocument) != nil)
        }
    }

    @Test("imported Myst age transition card scripts return routable final project navigation targets")
    func importedMystAgeTransitionCardScriptsReturnRoutableFinalProjectNavigationTargets() throws {
        let root = try mystExportRoot()
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)
        let packageNames = [
            "ALLRes.xstk",
            "INRes1.xstk",
            "Myst.xstk",
            "Mechanical-Age.xstk",
            "Stoneship-Age.xstk",
            "Channelwood-Age.xstk",
            "Selenitic-Age.xstk",
            "Dunny-Age.xstk",
        ]
        let packageURLs = packageNames.map { stacksRoot.appendingPathComponent($0, isDirectory: true) }
        let outputURL = makeTemporaryDirectory(prefix: "hype-myst-age-dispatch")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: packageURLs,
                outputDirectoryURL: outputURL,
                stackLibraryEntries: packageURLs.map(stackLibraryEntry),
                usedStackAliases: ["ALLRes", "INRes1"]
            )
        )
        let packageResults = Dictionary(
            uniqueKeysWithValues: result.packageResults.map { ($0.outputPackageURL.lastPathComponent, $0.outputPackageURL) }
        )

        let cases = [
            AgeCardDispatchCase(
                sourcePackageName: "Channelwood-Age.xstk",
                sourceOutputPackageName: "Channelwood-Age-debug-imported.hype",
                sourceLegacyCardId: 100894,
                expectedScriptFragment: "go to card id 44018 of stack \"Myst\"",
                expectedStackName: "Myst",
                expectedTargetPackageName: "Myst-debug-imported.hype",
                expectedTargetLegacyCardId: 44018,
                expectedTargetCardName: "restart"
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Dunny-Age.xstk",
                sourceOutputPackageName: "Dunny-Age-debug-imported.hype",
                sourceLegacyCardId: 11088,
                expectedScriptFragment: "go to card id 44018 of stack \"Myst\"",
                expectedStackName: "Myst",
                expectedTargetPackageName: "Myst-debug-imported.hype",
                expectedTargetLegacyCardId: 44018,
                expectedTargetCardName: "restart",
                scriptGlobals: ["DU_End": "win"]
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Mechanical-Age.xstk",
                sourceOutputPackageName: "Mechanical-Age-debug-imported.hype",
                sourceLegacyCardId: 46649,
                expectedScriptFragment: "go to card id 44018 of stack \"Myst\"",
                expectedStackName: "Myst",
                expectedTargetPackageName: "Myst-debug-imported.hype",
                expectedTargetLegacyCardId: 44018,
                expectedTargetCardName: "restart"
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Selenitic-Age.xstk",
                sourceOutputPackageName: "Selenitic-Age-debug-imported.hype",
                sourceLegacyCardId: 59926,
                expectedScriptFragment: "go to card id 44018 of stack \"Myst\"",
                expectedStackName: "Myst",
                expectedTargetPackageName: "Myst-debug-imported.hype",
                expectedTargetLegacyCardId: 44018,
                expectedTargetCardName: "restart"
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Stoneship-Age.xstk",
                sourceOutputPackageName: "Stoneship-Age-debug-imported.hype",
                sourceLegacyCardId: 53570,
                expectedScriptFragment: "go to card id 44018 of stack \"Myst\"",
                expectedStackName: "Myst",
                expectedTargetPackageName: "Myst-debug-imported.hype",
                expectedTargetLegacyCardId: 44018,
                expectedTargetCardName: "restart"
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Myst.xstk",
                sourceOutputPackageName: "Myst-debug-imported.hype",
                sourceLegacyCardId: 28552,
                expectedScriptFragment: "go to card \"restart\" of stack \"Dunny Age\"",
                expectedStackName: "Dunny Age",
                expectedTargetPackageName: "Dunny-Age-debug-imported.hype",
                expectedTargetLegacyCardId: 6532,
                expectedTargetCardName: "Restart"
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Myst.xstk",
                sourceOutputPackageName: "Myst-debug-imported.hype",
                sourceLegacyCardId: 55938,
                expectedScriptFragment: "go to card id 45136 of stack \"Selenitic Age\"",
                expectedStackName: "Selenitic Age",
                expectedTargetPackageName: "Selenitic-Age-debug-imported.hype",
                expectedTargetLegacyCardId: 45136,
                expectedTargetCardName: "Restart",
                scriptGlobals: ["MY_Selenitic": "true"],
                params: ["SeleniticBook.MooV"]
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Myst.xstk",
                sourceOutputPackageName: "Myst-debug-imported.hype",
                sourceLegacyCardId: 72560,
                expectedScriptFragment: "go to card \"Restart\" of stack \"Mechanical Age\"",
                expectedStackName: "Mechanical Age",
                expectedTargetPackageName: "Mechanical-Age-debug-imported.hype",
                expectedTargetLegacyCardId: 17290,
                expectedTargetCardName: "restart"
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Myst.xstk",
                sourceOutputPackageName: "Myst-debug-imported.hype",
                sourceLegacyCardId: 77008,
                expectedScriptFragment: "go to card \"Restart\" of stack \"StoneShip Age\"",
                expectedStackName: "StoneShip Age",
                expectedTargetPackageName: "Stoneship-Age-debug-imported.hype",
                expectedTargetLegacyCardId: 3004,
                expectedTargetCardName: "restart"
            ),
            AgeCardDispatchCase(
                sourcePackageName: "Myst.xstk",
                sourceOutputPackageName: "Myst-debug-imported.hype",
                sourceLegacyCardId: 77588,
                expectedScriptFragment: "go to card \"Restart\" of stack \"Channelwood Age\"",
                expectedStackName: "Channelwood Age",
                expectedTargetPackageName: "Channelwood-Age-debug-imported.hype",
                expectedTargetLegacyCardId: 28497,
                expectedTargetCardName: "restart"
            ),
        ]

        for ageCase in cases {
            let sourcePackageURL = stacksRoot.appendingPathComponent(ageCase.sourcePackageName, isDirectory: true)
            let sourceOutputPackageURL = try #require(packageResults[ageCase.sourceOutputPackageName])
            var sourceDocument = try HypeSQLiteStackStore().load(fromPackageAt: sourceOutputPackageURL)
            sourceDocument.scriptGlobals = ageCase.scriptGlobals
            let sourceCardMap = try legacyCardMap(packageURL: sourcePackageURL, document: sourceDocument)
            let sourceCardId = try #require(sourceCardMap[ageCase.sourceLegacyCardId])
            let sourceCard = try #require(sourceDocument.cards.first { $0.id == sourceCardId })
            #expect(sourceCard.script.localizedCaseInsensitiveContains(ageCase.expectedScriptFragment))
            #expect(!LegacyHyperTalkScript.isDisabledForHypeTalkRuntime(sourceCard.script), "Imported age transition card script should run: \(sourceCard.script)")

            let dispatch = MessageDispatcher().dispatch(
                message: "mouseDownInMovie",
                params: ageCase.params,
                targetId: sourceCardId,
                document: sourceDocument,
                currentCardId: sourceCardId
            )

            #expect(dispatch.status == .completed)
            #expect(dispatch.projectNavigationTarget?.stackName.caseInsensitiveCompare(ageCase.expectedStackName) == .orderedSame)
            #expect(dispatch.projectNavigationTarget?.legacyCardId == ageCase.expectedTargetLegacyCardId)
            #expect(dispatch.projectNavigationTarget?.cardName.caseInsensitiveCompare(ageCase.expectedTargetCardName) == .orderedSame)

            let targetOutputPackageURL = try #require(packageResults[ageCase.expectedTargetPackageName])
            let targetDocument = try HypeSQLiteStackStore().load(fromPackageAt: targetOutputPackageURL)
            #expect(ProjectNavigationTargetResolver.resolveCardId(for: try #require(dispatch.projectNavigationTarget), in: targetDocument) != nil)
        }
    }

    #if canImport(AppKit)
    @Test("imports Myst font layout audit candidates for rendered metric probes")
    func importsMystFontLayoutAuditCandidatesForRenderedMetricProbes() throws {
        let stacksRoot = try mystExportRoot().appendingPathComponent("exports/stacks", isDirectory: true)

        let app = try importPackage(stacksRoot.appendingPathComponent("Myst-Application.xstk", isDirectory: true))
        let defaults = try #require(app.document.parts.first { $0.name == "defaults" })
        let defaultsMeasurement = renderedTextMeasurement(for: defaults, text: defaults.textContent)
        #expect(defaults.textContent.contains("Myst\n\n1\ntrue"))
        #expect(defaultsMeasurement.measuredHeight > defaultsMeasurement.contentRect.height)

        let myst = try importPackage(stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true))
        let newButton = try #require(myst.document.parts.first { $0.name == "New Button" })
        let newButtonMeasurement = renderedTextMeasurement(for: newButton, text: newButton.name)
        #expect(newButton.showName)
        #expect(newButtonMeasurement.measuredWidth > 0)
        #expect(newButtonMeasurement.contentRect.width > 0)
        #expect(newButtonMeasurement.measuredWidth >= newButtonMeasurement.contentRect.width)

        let selenitic = try importPackage(stacksRoot.appendingPathComponent("Selenitic-Age.xstk", isDirectory: true))
        let diagnostics = try #require(selenitic.report.stackImportDiagnostics)
        let mystDisplay = try #require(diagnostics.fontSummary?.first { $0.name == "MystDisplay" })
        let heading = try #require(selenitic.document.parts.first { $0.name == "heading" })
        #expect(mystDisplay.available == false)
        #expect(mystDisplay.resolvedFontName == "Helvetica")
        #expect(heading.textFont == "Helvetica")
        #expect(heading.textSize == 32)
    }

    @Test("captures imported Myst cards as nonblank visual evidence")
    @MainActor
    func capturesImportedMystCardsAsNonblankVisualEvidence() throws {
        let stacksRoot = try mystExportRoot().appendingPathComponent("exports/stacks", isDirectory: true)
        let capturer = CardImageCapturer()

        let app = try importPackage(stacksRoot.appendingPathComponent("Myst-Application.xstk", isDirectory: true))
        let defaults = try #require(app.document.parts.first { $0.name == "defaults" })
        let defaultsCardId = try #require(defaults.cardId)
        let defaultsCapture = try capturer.capture(
            cardName: nil,
            document: app.document,
            currentCardId: defaultsCardId,
            maxLongEdge: 512
        )
        let defaultsStats = try visualStats(fromBase64PNG: defaultsCapture.imageBase64)
        #expect(defaultsCapture.pixelWidth > 0)
        #expect(defaultsCapture.pixelHeight > 0)
        #expect(defaultsStats.darkOpaquePixelCount > 100)
        #expect(defaultsStats.sampledColorCount > 1)

        let mystPackageURL = stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true)
        let myst = try importPackage(mystPackageURL)
        let legacyMystCards = try legacyCardMap(packageURL: mystPackageURL, document: myst.document)
        let blackCardId = try #require(legacyMystCards[23444])
        let blackCapture = try capturer.capture(
            cardName: nil,
            document: myst.document,
            currentCardId: blackCardId,
            maxLongEdge: 512
        )
        let blackStats = try visualStats(fromBase64PNG: blackCapture.imageBase64)
        #expect(blackCapture.pixelWidth > 0)
        #expect(blackCapture.pixelHeight > 0)
        #expect(blackStats.nonWhiteOpaquePixelCount > blackStats.pixelCount / 3)
    }

    @Test("captures representative cards from full Myst project import")
    @MainActor
    func capturesRepresentativeCardsFromFullMystProjectImport() throws {
        let root = try mystExportRoot()
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)
        let packageNames = [
            "Myst-Application.xstk",
            "ALLRes.xstk",
            "INRes1.xstk",
            "Myst.xstk",
            "Mechanical-Age.xstk",
            "Stoneship-Age.xstk",
            "Channelwood-Age.xstk",
            "Selenitic-Age.xstk",
            "Dunny-Age.xstk",
        ]
        let packageURLs = packageNames.map { stacksRoot.appendingPathComponent($0, isDirectory: true) }
        let outputURL = makeTemporaryDirectory(prefix: "hype-myst-full-visual")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result = try StackImportPackageProjectImporter().importProject(
            options: StackImportPackageProjectImportOptions(
                packageURLs: packageURLs,
                outputDirectoryURL: outputURL,
                stackLibraryEntries: packageURLs.map(stackLibraryEntry),
                usedStackAliases: ["ALLRes", "INRes1"]
            )
        )

        #expect(result.packageResults.count == packageNames.count)

        let capturer = CardImageCapturer()
        for packageResult in result.packageResults {
            let document = try HypeSQLiteStackStore().load(fromPackageAt: packageResult.outputPackageURL)
            let captureCandidates = visualCaptureCandidates(in: document)
            #expect(!captureCandidates.isEmpty)

            var bestStats: VisualStats?
            var bestCardName = ""
            for card in captureCandidates {
                let capture = try capturer.capture(
                    cardName: nil,
                    document: document,
                    currentCardId: card.id,
                    maxLongEdge: 512
                )
                let stats = try visualStats(fromBase64PNG: capture.imageBase64)
                if bestStats == nil || stats.nonWhiteOpaquePixelCount > (bestStats?.nonWhiteOpaquePixelCount ?? 0) {
                    bestStats = stats
                    bestCardName = card.name
                }
                if stats.nonWhiteOpaquePixelCount > max(64, stats.pixelCount / 100),
                   stats.sampledColorCount > 1 || stats.darkOpaquePixelCount > 64 {
                    break
                }
            }

            let stats = try #require(bestStats, "\(packageResult.outputPackageURL.lastPathComponent) produced no card captures")
            #expect(
                stats.nonWhiteOpaquePixelCount > max(64, stats.pixelCount / 100),
                "\(packageResult.outputPackageURL.lastPathComponent) representative captures were effectively blank; best card: \(bestCardName)"
            )
            #expect(
                stats.sampledColorCount > 1 || stats.darkOpaquePixelCount > 64,
                "\(packageResult.outputPackageURL.lastPathComponent) representative captures had no meaningful visual variation; best card: \(bestCardName)"
            )
        }
    }
    #endif

    @Test("imported Myst palette drives runtime QuickDraw color indexes")
    func importedMystPaletteDrivesRuntimeQuickDrawColorIndexes() throws {
        let stacksRoot = try mystExportRoot().appendingPathComponent("exports/stacks", isDirectory: true)
        let myst = try importPackage(stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true))
        let currentCardId = try #require(myst.document.sortedCards.first?.id)

        let paletteScript = try parseScript("""
        on test
          HTUDefPal 9001
          xLine "2,2","2,2",1,1
          return the result
        end test
        """)
        let paletteHandler = try #require(paletteScript.handlers.first { $0.name.caseInsensitiveCompare("test") == .orderedSame })
        let paletteResult = Interpreter().execute(
            handler: paletteHandler,
            params: [],
            context: ExecutionContext(targetId: myst.document.stack.id, currentCardId: currentCardId, document: myst.document)
        )

        #expect(paletteResult.status == .completed)
        #expect(paletteResult.returnValue == "2,2,2,2,1,1")
        let paletteDocument = try #require(paletteResult.modifiedDocument)
        #expect(paletteDocument.scriptGlobals["hypercard.htudefpal.palette"] == "9001")
        #expect(paletteDocument.scriptGlobals["hypercard.htudefpal.status"] == "resolved")
        #expect(paletteDocument.scriptGlobals["hypercard.htudefpal.resourceType"] == "pltt")
        #expect(paletteDocument.scriptGlobals["hypercard.htudefpal.colorCount"] == "256")
        let paletteColors = (paletteDocument.scriptGlobals["hypercard.htudefpal.colors"] ?? "")
            .split(separator: "\t")
            .map(String.init)
        #expect(paletteColors.count == 256)
        let paletteColor = try #require(paletteColors.dropFirst().first)
        let expectedColor = try #require(rgb(fromHex: paletteColor))

        let layer = try #require(paletteDocument.paintLayer(forCardId: currentCardId))
        let pixel = try #require(rgba(atX: 2, y: 2, in: layer))
        #expect(pixel.red == expectedColor.red)
        #expect(pixel.green == expectedColor.green)
        #expect(pixel.blue == expectedColor.blue)
        #expect(pixel.alpha == 255)
    }

    private func mystExportRoot() throws -> URL {
        let rootPath = try #require(ProcessInfo.processInfo.environment["MYST_EXPORT_ROOT"])
        return URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    private func importPackage(_ url: URL) throws -> HyperCardImportResult {
        #expect(FileManager.default.fileExists(atPath: url.path))
        return try StackImportPackageConverter().convert(packageURL: url)
    }

    private func materializeMystSourceArchive(root: URL, entries: [String]) throws -> URL {
        let archiveURL = root.appendingPathComponent("source/Myst-source-2026-05-29.zip", isDirectory: false)
        try #require(FileManager.default.fileExists(atPath: archiveURL.path))
        let outputURL = makeTemporaryDirectory(prefix: "hype-myst-source")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", archiveURL.path] + entries + ["-d", outputURL.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return outputURL.appendingPathComponent("Myst", isDirectory: true)
    }

    private func stackLibraryEntry(for packageURL: URL) -> HypeStackLibraryEntry {
        let stack = try? decode(XSTKAcceptanceStack.self, from: packageURL.appendingPathComponent("stack_-1.json"))
        let project = try? decode(XSTKAcceptanceProject.self, from: packageURL.appendingPathComponent("project.json"))
        let cardIds = stack?.pages?.flatMap(\.cardIds) ?? []
        let firstCardId = stack?.firstCardId ?? cardIds.first
        let cardReferences = cardIds.enumerated().map { index, cardId in
            let cardName = (try? decode(
                XSTKAcceptanceLayerDetail.self,
                from: packageURL.appendingPathComponent("card_\(cardId).json")
            ))?.name
            return HypeStackLibraryCardReference(
                legacyCardId: cardId,
                name: cardName ?? "",
                sortIndex: index
            )
        }
        let packageName = packageURL.lastPathComponent
        let stackName = stack?.name ?? packageURL.deletingPathExtension().lastPathComponent
        let aliases = [stackName, packageURL.deletingPathExtension().lastPathComponent, project?.sourceFileName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return HypeStackLibraryEntry(
            stackName: stackName,
            aliases: stableAliases(aliases),
            source: .importedStackPackage,
            packagePath: packageURL.path,
            legacyFirstCardId: firstCardId,
            cardCount: stack?.cardCount,
            cardReferences: cardReferences,
            metadata: isContentStack(packageName)
                ? [HypeStackLibraryMetadataEntry(key: "contentStack", value: "true")]
                : []
        )
    }

    private func isContentStack(_ packageName: String) -> Bool {
        packageName == "ALLRes.xstk" || packageName == "INRes1.xstk"
    }

    private func stableAliases(_ aliases: [String]) -> [String] {
        aliases.reduce(into: [String]()) { result, alias in
            guard !result.contains(where: { HypeStackLibrary.lookupKey($0) == HypeStackLibrary.lookupKey(alias) }) else { return }
            result.append(alias)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func makeTemporaryDirectory(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct AgeBookClickCase {
        var sourceLegacyCardId: Int
        var expectedScriptFragment: String
        var expectedStackName: String
        var expectedTargetPackageName: String
        var expectedTargetLegacyCardId: Int
        var expectedTargetCardName: String
    }

    private struct AgeCardDispatchCase {
        var sourcePackageName: String
        var sourceOutputPackageName: String
        var sourceLegacyCardId: Int
        var expectedScriptFragment: String
        var expectedStackName: String
        var expectedTargetPackageName: String
        var expectedTargetLegacyCardId: Int
        var expectedTargetCardName: String
        var scriptGlobals: [String: String] = [:]
        var params: [Value] = []
    }

    private func legacyCardMap(packageURL: URL, document: HypeDocument) throws -> [Int: UUID] {
        let stack = try decode(XSTKAcceptanceStack.self, from: packageURL.appendingPathComponent("stack_-1.json"))
        let legacyCardIds = stack.pages?.flatMap(\.cardIds) ?? []
        return Dictionary(uniqueKeysWithValues: zip(legacyCardIds, document.sortedCards.map(\.id)))
    }

    private func assertImportedButtonNavigates(
        scriptFragment: String,
        fromLegacyCardId: Int,
        toLegacyCardId: Int,
        legacyCardMap: [Int: UUID],
        document: HypeDocument
    ) throws {
        let sourceCardId = try #require(legacyCardMap[fromLegacyCardId])
        let expectedCardId = try #require(legacyCardMap[toLegacyCardId])
        let currentStackEntry = try #require(matchingCurrentStackEntry(in: document))
        let targetReference = try #require(currentStackEntry.cardReferences.first { $0.legacyCardId == toLegacyCardId })
        #expect(targetReference.hypeCardId == expectedCardId)
        let part = try #require(document.partsForCard(sourceCardId).first { part in
            part.script.localizedCaseInsensitiveContains(scriptFragment)
        })
        #expect(!LegacyHyperTalkScript.isDisabledForHypeTalkRuntime(part.script), "Imported first-path hotspot script should run: \(part.script)")

        let parsedScript = try parseScript(part.script)
        let handler = try #require(parsedScript.handlers.first { $0.name.caseInsensitiveCompare("mouseUp") == .orderedSame })
        let directResult = Interpreter().execute(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: part.id, currentCardId: sourceCardId, document: document)
        )
        #expect(directResult.navigationTarget == expectedCardId)

        let result = MessageDispatcher().dispatch(
            message: "mouseUp",
            params: [],
            targetId: part.id,
            document: document,
            currentCardId: sourceCardId
        )
        #expect(result.status == .completed)
        #expect(result.navigationTarget == expectedCardId)
    }

    private func matchingCurrentStackEntry(in document: HypeDocument) -> HypeStackLibraryEntry? {
        switch document.stackLibrary.resolution(for: document.stack.name) {
        case .resolved(let entry):
            return entry
        case .ambiguous(_, let candidates):
            return entryContainingDocumentCards(candidates, document: document)
        case .missing:
            return entryContainingDocumentCards(document.stackLibrary.entries, document: document)
        }
    }

    private func entryContainingDocumentCards(_ entries: [HypeStackLibraryEntry], document: HypeDocument) -> HypeStackLibraryEntry? {
        let cardIds = Set(document.cards.map(\.id))
        return entries.first { entry in
            entry.cardReferences.contains { reference in
                reference.hypeCardId.map { cardIds.contains($0) } ?? false
            }
        }
    }

    private func storedScriptParseFailures(in document: HypeDocument) -> [String] {
        storedScripts(in: document).compactMap { script in
            do {
                _ = try parseScript(script.source)
                return nil
            } catch {
                return "\(script.ownerPath): \(error.localizedDescription)"
            }
        }
    }

    private func parseScript(_ source: String) throws -> Script {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return try parser.parse()
    }

    private func rgb(fromHex hex: String) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard hex.hasPrefix("#"), hex.count == 7 else { return nil }
        let body = String(hex.dropFirst())
        guard let value = Int(body, radix: 16) else { return nil }
        return (
            red: UInt8((value >> 16) & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8(value & 0xFF)
        )
    }

    private func rgba(atX x: Int, y: Int, in layer: CardPaintLayer) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        guard x >= 0, y >= 0, x < layer.width, y < layer.height else { return nil }
        let data = layer.normalizedRGBAData
        let offset = (y * layer.width + x) * 4
        guard data.indices.contains(offset + 3) else { return nil }
        return (
            red: data[offset],
            green: data[offset + 1],
            blue: data[offset + 2],
            alpha: data[offset + 3]
        )
    }

    private func visualCaptureCandidates(in document: HypeDocument) -> [Card] {
        let cards = document.sortedCards
        let paintLayerCardIds = Set(document.paintLayers.map(\.cardId))
        let partCardIds = Set(document.parts.compactMap(\.cardId))
        let cardOrder = Dictionary(uniqueKeysWithValues: cards.enumerated().map { ($0.element.id, $0.offset) })
        return cards.sorted(by: { lhs, rhs in
            let lhsRank = visualCaptureRank(card: lhs, paintLayerCardIds: paintLayerCardIds, partCardIds: partCardIds)
            let rhsRank = visualCaptureRank(card: rhs, paintLayerCardIds: paintLayerCardIds, partCardIds: partCardIds)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return (cardOrder[lhs.id] ?? Int.max) < (cardOrder[rhs.id] ?? Int.max)
        })
    }

    private func visualCaptureRank(card: Card, paintLayerCardIds: Set<UUID>, partCardIds: Set<UUID>) -> Int {
        if paintLayerCardIds.contains(card.id) { return 0 }
        if partCardIds.contains(card.id) { return 1 }
        return 2
    }

    private func isSharedContentAsset(_ asset: Asset) -> Bool {
        asset.metadata.contains { $0.key == "shared_from_content_stack" }
    }

    private func storedScripts(in document: HypeDocument) -> [(ownerPath: String, source: String)] {
        var scripts: [(ownerPath: String, source: String)] = []
        scripts.append(("stack \(document.stack.name)", document.stack.script))
        scripts.append(contentsOf: document.backgrounds.enumerated().map { index, background in
            ("background \(index + 1) \(background.name)", background.script)
        })
        scripts.append(contentsOf: document.cards.enumerated().map { index, card in
            ("card \(index + 1) \(card.name)", card.script)
        })
        scripts.append(contentsOf: document.parts.map { part in
            ("\(part.partType.rawValue) \(part.name)", part.script)
        })
        return scripts.filter { !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    #if canImport(AppKit)
    private func renderedTextMeasurement(for part: Part, text: String) -> (contentRect: CGRect, measuredWidth: CGFloat, measuredHeight: CGFloat) {
        let rect = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
        let font = NSFont(name: part.textFont, size: CGFloat(part.textSize)) ?? NSFont.systemFont(ofSize: CGFloat(part.textSize))
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let contentRect: CGRect
        if part.partType == .field {
            contentRect = FieldTextLayout.contentRect(in: rect, wideMargins: part.wideMargins, fieldStyle: part.fieldStyle)
        } else {
            contentRect = rect.insetBy(dx: 6, dy: 2)
        }
        let bounds = attributed.boundingRect(
            with: CGSize(width: max(1, contentRect.width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return (contentRect, ceil(bounds.width), ceil(bounds.height))
    }

    private func visualStats(fromBase64PNG base64: String) throws -> VisualStats {
        let data = try #require(Data(base64Encoded: base64))
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var darkOpaquePixelCount = 0
        var nonWhiteOpaquePixelCount = 0
        var sampledColors = Set<Int>()
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.8 else { continue }
                let red = Int((color.redComponent * 255).rounded())
                let green = Int((color.greenComponent * 255).rounded())
                let blue = Int((color.blueComponent * 255).rounded())
                let luminance = (0.2126 * Double(red)) + (0.7152 * Double(green)) + (0.0722 * Double(blue))
                if luminance < 96 {
                    darkOpaquePixelCount += 1
                }
                if red < 245 || green < 245 || blue < 245 {
                    nonWhiteOpaquePixelCount += 1
                }
                if x.isMultiple(of: 16), y.isMultiple(of: 16) {
                    sampledColors.insert((red << 16) | (green << 8) | blue)
                }
            }
        }
        return VisualStats(
            pixelCount: width * height,
            darkOpaquePixelCount: darkOpaquePixelCount,
            nonWhiteOpaquePixelCount: nonWhiteOpaquePixelCount,
            sampledColorCount: sampledColors.count
        )
    }

    private struct VisualStats {
        var pixelCount: Int
        var darkOpaquePixelCount: Int
        var nonWhiteOpaquePixelCount: Int
        var sampledColorCount: Int
    }
    #endif
}

private struct XSTKAcceptanceProject: Decodable {
    var sourceFileName: String?
}

private struct XSTKAcceptanceStack: Decodable {
    var name: String?
    var firstCardId: Int?
    var cardCount: Int?
    var pages: [XSTKAcceptancePage]?
}

private struct XSTKAcceptancePage: Decodable {
    var cardIds: [Int]
}

private struct XSTKAcceptanceLayerDetail: Decodable {
    var name: String?
}

private extension HypeStackLibraryResolution {
    var isResolved: Bool {
        if case .resolved = self {
            return true
        }
        return false
    }
}

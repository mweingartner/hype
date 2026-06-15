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
        let rootPath = try #require(ProcessInfo.processInfo.environment["MYST_EXPORT_ROOT"])
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)
        let packageURLs = [
            stacksRoot.appendingPathComponent("Myst-Application.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("ALLRes.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("INRes1.xstk", isDirectory: true),
            stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true),
        ]
        let outputURL = makeTemporaryDirectory()
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
        #expect(result.summary.stacks.map(\.stackName).contains("ALLRes"))
        #expect(result.summary.stacks.map(\.stackName).contains("INRes1"))
        #expect(result.summary.stacks.map(\.stackName).contains("Myst"))
        #expect(result.summary.sharedContentAssetCopyCount > 0)
        #expect(result.summary.packages.allSatisfy { $0.stackLibrary?.entryCount == 4 })
        #expect(result.summary.packages.allSatisfy { $0.stackLibrary?.usedStackAliases == ["ALLRes", "INRes1"] })
        #expect(result.summary.packages.allSatisfy { $0.looseMedia?.missing.isEmpty == true })
        #expect(result.summary.packages.contains { package in
            package.looseMedia?.imported.contains {
                $0.name == "BR Seagulls:Water Slosh Mx Mov" && $0.kind == AssetKind.videoClip.rawValue
            } == true
        })
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

        let mystDiagnostics = try #require(mystDocument.legacyImport?.report.stackImportDiagnostics)
        #expect(mystDiagnostics.fontSummary?.contains { $0.name == "Chicago" && !$0.resolvedFontName.isEmpty } == true)
        #expect(mystDiagnostics.externalCallSummary.contains { $0.name.caseInsensitiveCompare("playQT") == .orderedSame })

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

    @Test("imports local Myst and ALLRes xstk packages with diagnostics")
    func importsMystAndALLResPackages() throws {
        let rootPath = try #require(ProcessInfo.processInfo.environment["MYST_EXPORT_ROOT"])
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let stacksRoot = root.appendingPathComponent("exports/stacks", isDirectory: true)

        let myst = try importPackage(stacksRoot.appendingPathComponent("Myst.xstk", isDirectory: true))
        #expect(myst.document.stack.name == "Myst")
        #expect(myst.document.stack.width == 544)
        #expect(myst.document.stack.height == 332)
        #expect(myst.document.cards.count >= 300)
        #expect(myst.document.backgrounds.count >= 1)
        #expect(myst.document.parts.contains { $0.partType == .image })

        let mystDiagnostics = try #require(myst.report.stackImportDiagnostics)
        #expect(mystDiagnostics.sourcePath == "Myst")
        #expect((mystDiagnostics.dataForkBytes ?? 0) > 300_000)
        #expect((mystDiagnostics.resourceForkBytes ?? 0) > 800_000)
        #expect(mystDiagnostics.scriptEntries > 1_000)
        #expect(mystDiagnostics.handlerCount > 1_000)
        #expect(mystDiagnostics.callCount > 2_000)
        #expect(mystDiagnostics.externalCallSummary.contains { $0.name.caseInsensitiveCompare("playQT") == .orderedSame })

        let allRes = try importPackage(stacksRoot.appendingPathComponent("ALLRes.xstk", isDirectory: true))
        #expect(allRes.document.stack.name == "ALLRes")
        #expect(allRes.document.cards.count >= 1)
        #expect(allRes.document.assetRepository.assets.contains { $0.tags.contains("hypercard-import") })

        let allResDiagnostics = try #require(allRes.report.stackImportDiagnostics)
        #expect(allResDiagnostics.sourcePath == "ALLRes")
        #expect((allResDiagnostics.resourceForkBytes ?? 0) > 5_000_000)
        #expect(allRes.report.resourceSummary.contains { $0.type == "XCMD" || $0.type == "XFCN" })
        #expect(allRes.report.blockSummary.contains { $0.type == "STAK" && $0.count == 1 })
    }

    @Test("imports selected Myst loose media from manifest")
    func importsSelectedMystLooseMediaFromManifest() throws {
        let rootPath = try #require(ProcessInfo.processInfo.environment["MYST_EXPORT_ROOT"])
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let manifestURL = root.appendingPathComponent("manifests/loose-media.tsv", isDirectory: false)
        let replacementRoot = root.appendingPathComponent("exports/modern-quicktime", isDirectory: true)
        let sourceRoot = ProcessInfo.processInfo.environment["MYST_SOURCE_ROOT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? (try? materializeMystSourceArchive(
            root: root,
            entries: [
                "Myst/Myst Graphics/Myst/AR Howling&Birds Mov",
                "Myst/Myst Graphics/Myst/BR Seagulls:Water Slosh Mx Mov",
                "Myst/Myst Graphics/Myst/Intro Wind Mov",
            ]
        ))
        defer {
            if ProcessInfo.processInfo.environment["MYST_SOURCE_ROOT"] == nil,
               let sourceRoot {
                try? FileManager.default.removeItem(at: sourceRoot.deletingLastPathComponent())
            }
        }

        var document = HypeDocument.newDocument(name: "Myst Loose Media")
        let result = try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: manifestURL,
                sourceRootURL: sourceRoot,
                replacementRootURL: replacementRoot,
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

        #expect(result.importedAssets.count >= 2)
        let atrusWrite = try #require(document.assetRepository.asset(byName: "AtrusWrite"))
        #expect(atrusWrite.kind == .videoClip)
        #expect(atrusWrite.mimeType == "video/quicktime")
        #expect(atrusWrite.metadata.contains { $0.key == "resolved_path" && $0.value.contains("modern-quicktime") })

        let atrusPage = try #require(document.assetRepository.asset(byName: "Atrus1 Page"))
        #expect(atrusPage.kind == .videoClip)

        if sourceRoot != nil {
            let intro = try #require(document.assetRepository.assets.first { $0.name == "Intro Wind Mov" })
            #expect(intro.kind == .videoClip)
            #expect(intro.tags.contains("finder-myqt"))
            #expect(intro.metadata.contains { $0.key == "quicktime_audio_only" && $0.value == "true" })
            #expect(intro.metadata.contains { $0.key == "resolved_path" && $0.value.contains("modern-quicktime") })
            let ambient = try #require(document.assetRepository.assets.first { $0.name == "AR Howling&Birds Mov" })
            #expect(ambient.kind == .videoClip)
            #expect(ambient.tags.contains("finder-myqt"))
            #expect(ambient.metadata.contains { $0.key == "quicktime_audio_only" && $0.value == "true" })
            #expect(ambient.metadata.contains { $0.key == "resolved_path" && $0.value.contains("modern-quicktime") })
            let seagulls = try #require(document.assetRepository.asset(byClassicMediaName: "BR Seagulls/Water Slosh Mx MoV", kind: .videoClip))
            #expect(seagulls.name == "BR Seagulls:Water Slosh Mx Mov")
            #expect(seagulls.metadata.contains { $0.key == "quicktime_audio_only" && $0.value == "true" })
            #expect(seagulls.metadata.contains { $0.key == "resolved_path" && $0.value.contains("modern-quicktime") })
            #expect(result.importedAssets.contains { $0.id == seagulls.id })
        } else {
            #expect(result.missing.contains {
                $0.name == "AR Howling&Birds Mov" && $0.reason == "file not found"
            })
        }
    }

    #if canImport(AppKit)
    @Test("imports Myst font layout audit candidates for rendered metric probes")
    func importsMystFontLayoutAuditCandidatesForRenderedMetricProbes() throws {
        let rootPath = try #require(ProcessInfo.processInfo.environment["MYST_EXPORT_ROOT"])
        let stacksRoot = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("exports/stacks", isDirectory: true)

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
    #endif

    private func importPackage(_ url: URL) throws -> HyperCardImportResult {
        #expect(FileManager.default.fileExists(atPath: url.path))
        return try StackImportPackageConverter().convert(packageURL: url)
    }

    private func materializeMystSourceArchive(root: URL, entries: [String]) throws -> URL {
        let archiveURL = root.appendingPathComponent("source/Myst-source-2026-05-29.zip", isDirectory: false)
        try #require(FileManager.default.fileExists(atPath: archiveURL.path))
        let outputURL = makeTemporaryDirectory()
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

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hype-myst-first-path-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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

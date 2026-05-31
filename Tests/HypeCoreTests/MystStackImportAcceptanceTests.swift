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
        appDocument.scriptGlobals = seededLauncherGlobals()

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
    #endif

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

    private func seededLauncherGlobals() -> [String: String] {
        [
            "ALL_CurrStack": "Myst",
            "ALL_Page": "",
            "DU_End": "",
            "MY_BlueBook": "000000",
            "MY_RedBook": "000000",
            "Quick": "false",
            "RestoreData": "card field Defaults of card Defaults",
            "Start_Game": "new",
            "Trans": "2",
            "playsounds": "true",
        ]
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

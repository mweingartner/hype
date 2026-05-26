import Foundation
import Testing
@testable import HypeCore

@Suite("SQLite-backed Hype document persistence")
struct HypeDocumentSelfContainedPersistenceTests {
    @Test("portable SQLite package round-trip preserves stack-authored content surfaces")
    func portableDocumentRoundTripPreservesAuthoredContent() throws {
        let store = HypeSQLiteStackStore()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortableSQLite-\(UUID().uuidString).hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        var document = try makePortableDocument()
        document.scriptGlobals["sessionOnly"] = "do not persist"

        try store.save(document, toPackageAt: packageURL)

        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent(HypeSQLiteStackStore.manifestFileName).path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent(HypeSQLiteStackStore.sqliteFileName).path))
        #expect(try packageEntryNames(at: packageURL) == [
            HypeSQLiteStackStore.manifestFileName,
            HypeSQLiteStackStore.sqliteFileName,
        ])

        let diagnostics = try store.validate(packageURL: packageURL)
        #expect(diagnostics.isHealthy)
        #expect(diagnostics.tableCounts["stacks"] == 1)
        #expect(diagnostics.tableCounts["deployment_targets"] == 2)
        #expect(diagnostics.tableCounts["runtime_ai_settings"] == 1)
        #expect(diagnostics.tableCounts["parts"] == 2)
        #expect((diagnostics.tableCounts["scripts"] ?? 0) >= 5)
        #expect((diagnostics.tableCounts["scene_nodes"] ?? 0) >= 2)
        #expect(diagnostics.searchEntryCount > 0)

        let decoded = try store.load(fromPackageAt: packageURL)

        #expect(decoded.stack.script == document.stack.script)
        #expect(decoded.stack.webAssetsAllowed)
        #expect(decoded.stack.aiContextCloudSharingAllowed)
        #expect(decoded.stack.meshyEnabled)
        #expect(decoded.stack.runtimeModeEnabled)
        #expect(decoded.stack.deploymentTargets.selectedPlatforms == [.macOS, .iPad])
        #expect(decoded.stack.deploymentTargets.selectionPromptAcknowledged)
        #expect(decoded.stack.deploymentTargets.layoutPolicy == .scaleToFit)
        #expect(decoded.stack.runtimeAISettings.providerPolicy == .appleFoundationModels)
        #expect(decoded.stack.runtimeAISettings.allowedToolNames == ["set_runtime_variable"])
        #expect(decoded.backgrounds.first?.script == document.backgrounds[0].script)
        #expect(decoded.cards.first?.script == document.cards[0].script)
        #expect(decoded.parts.first { $0.name == "btn_start" }?.script.contains("startGame") == true)
        #expect(decoded.spriteRepository.asset(byName: "hero")?.data == Data([0, 1, 2, 3]))
        #expect(decoded.aiContextLibrary.itemCount == 1)
        #expect(decoded.aiContextLibrary.items.first?.data?.isEmpty == false)
        #expect(decoded.aiPromptHistory == document.aiPromptHistory)
        #expect(decoded.paintLayers.first?.rgbaData == Data([255, 0, 0, 255]))
        #expect(decoded.themes.contains { $0.name == "Portable Theme" })
        #expect(decoded.stack.themeName == "Portable Theme")
        #expect(decoded.scriptGlobals.isEmpty)
        #expect(try normalizedJSON(decoded) == normalizedJSON(document))
        #expect(try packageEntryNames(at: packageURL) == [
            HypeSQLiteStackStore.manifestFileName,
            HypeSQLiteStackStore.sqliteFileName,
        ])
    }

    @Test("SQLite search finds scripts text context assets and SpriteKit nodes")
    func sqliteSearchFindsStackContent() throws {
        let store = HypeSQLiteStackStore()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchableSQLite-\(UUID().uuidString).hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try store.save(try makePortableDocument(), toPackageAt: packageURL)

        let scriptResults = try store.search(packageURL: packageURL, query: "startGame")
        #expect(scriptResults.contains { $0.objectType == "part" || $0.objectType == "script" })

        let contextResults = try store.search(packageURL: packageURL, query: "native controls")
        #expect(contextResults.contains { $0.objectType == "ai_context_item" })

        let spriteResults = try store.search(packageURL: packageURL, query: "hero_node")
        #expect(spriteResults.contains { $0.objectType == "scene_node" })

        let assetResults = try store.search(packageURL: packageURL, query: "hero")
        #expect(assetResults.contains { $0.objectType == "asset" })
    }

    @Test("FileWrapper package is self-contained")
    func fileWrapperPackageIsSelfContained() throws {
        let store = HypeSQLiteStackStore()
        let wrapper = try store.fileWrapper(for: try makePortableDocument())

        #expect(wrapper.isDirectory)
        #expect(wrapper.fileWrappers?[HypeSQLiteStackStore.manifestFileName]?.regularFileContents != nil)
        #expect(wrapper.fileWrappers?[HypeSQLiteStackStore.sqliteFileName]?.regularFileContents != nil)

        let decoded = try store.load(from: wrapper)
        #expect(decoded.stack.name == "Portable Stack")
        #expect(decoded.spriteRepository.asset(byName: "hero")?.data == Data([0, 1, 2, 3]))
        #expect(decoded.aiContextLibrary.itemCount == 1)
    }

    @Test("manifest checksum protects package integrity")
    func manifestChecksumProtectsPackageIntegrity() throws {
        let store = HypeSQLiteStackStore()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChecksumSQLite-\(UUID().uuidString).hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try store.save(try makePortableDocument(), toPackageAt: packageURL)

        let sqliteURL = packageURL.appendingPathComponent(HypeSQLiteStackStore.sqliteFileName)
        var data = try Data(contentsOf: sqliteURL)
        data.append(0xFF)
        try data.write(to: sqliteURL, options: [.atomic])

        do {
            _ = try store.load(fromPackageAt: packageURL)
            Issue.record("Expected package checksum validation to reject the modified database")
        } catch HypeSQLiteStackStoreError.databaseHashMismatch {
            // Expected.
        } catch {
            Issue.record("Expected databaseHashMismatch, got \(error)")
        }
    }

    private func makePortableDocument() throws -> HypeDocument {
        var document = HypeDocument.newDocument(name: "Portable Stack")
        let cardId = try #require(document.cards.first?.id)

        document.stack.script = "on openStack\n  put \"ready\" into status\nend openStack"
        document.stack.webAssetsAllowed = true
        document.stack.aiContextCloudSharingAllowed = true
        document.stack.meshyEnabled = true
        document.stack.runtimeModeEnabled = true
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPad],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        document.stack.runtimeAISettings = RuntimeAISettings(
            providerPolicy: .appleFoundationModels,
            allowRuntimeSideEffectTools: true,
            allowedToolNames: ["set_runtime_variable"],
            unavailableFallbackText: "Runtime AI is unavailable.",
            persistTranscript: false
        )
        document.backgrounds[0].script = "on openBackground\n  pass openBackground\nend openBackground"
        document.cards[0].script = "on openCard\n  pass openCard\nend openCard"
        document.aiPromptHistory = ["create a maze game", "add ghosts"]

        var button = Part(partType: .button, cardId: cardId, name: "btn_start")
        button.script = "on mouseUp\n  send \"startGame\" to this stack\nend mouseUp"
        document.parts.append(button)

        var spriteArea = Part(partType: .spriteArea, cardId: cardId, name: "game_area", left: 20, top: 60, width: 300, height: 220)
        let child = HypeNodeSpec(
            name: "spark_label",
            nodeType: .label,
            position: PointSpec(x: 100, y: 100),
            text: "Score",
            fontName: "Helvetica",
            fontSize: 18,
            fontColor: "#FFFFFF",
            script: "on mouseUp\n  pass mouseUp\nend mouseUp"
        )
        let hero = HypeNodeSpec(
            name: "hero_node",
            nodeType: .sprite,
            position: PointSpec(x: 50, y: 60),
            size: SizeSpec(width: 32, height: 32),
            children: [child],
            script: "on updateFrame\n  pass updateFrame\nend updateFrame"
        )
        let scene = SceneSpec(
            name: "main",
            size: SizeSpec(width: 300, height: 220),
            backgroundColor: "#000000",
            nodes: [hero],
            script: "on sceneDidLoad\n  put \"loaded\" into sceneState\nend sceneDidLoad"
        )
        spriteArea.setSpriteAreaSpec(SpriteAreaSpec(scene: scene, fallbackSize: SizeSpec(width: 300, height: 220)))
        document.parts.append(spriteArea)

        document.spriteRepository.addAsset(SpriteAsset(
            name: "hero",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0, 1, 2, 3]),
            width: 1,
            height: 1
        ))

        let context = AIContextIngestor.makeTextNote(
            title: "Design Notes",
            text: "Keep the form controls native and store all asset choices in the stack.",
            role: .projectMemory
        )
        document.aiContextLibrary.addSource(context.0, items: context.1)
        document.setPaintLayer(CardPaintLayer(
            cardId: cardId,
            width: 1,
            height: 1,
            rgbaData: Data([255, 0, 0, 255])
        ))
        _ = document.duplicateTheme(named: BuiltInThemes.fallbackName, candidateName: "Portable Theme")
        document.stack.themeName = "Portable Theme"
        document.backgrounds[0].themeName = "Portable Theme"
        document.cards[0].themeName = "Portable Theme"

        return document
    }

    private func normalizedJSON(_ document: HypeDocument) throws -> Data {
        var copy = document
        copy.scriptGlobals = [:]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(copy)
    }

    private func packageEntryNames(at packageURL: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: packageURL.path))
    }
}

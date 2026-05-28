import Foundation
import CryptoKit
import SQLite3
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

        let manifest = try readManifest(at: packageURL)
        #expect(manifest.documentVersion == HypeDocument.currentDocumentVersion)
        #expect(try documentValue("documentVersion", in: packageURL) == "\(HypeDocument.currentDocumentVersion)")

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
        #expect(decoded.documentVersion == HypeDocument.currentDocumentVersion)
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
        #expect(decoded.assetRepository.asset(byName: "hero")?.data == Data([0, 1, 2, 3]))
        #expect(decoded.assetRepository.asset(byName: "hero")?.files.first?.role == .palette)
        #expect(decoded.assetRepository.asset(byName: "hero")?.files.first?.data == Data([4, 5, 6]))
        #expect(decoded.assetRepository.asset(byName: "hero")?.metadata.first?.key == "legacy-resource")
        let sourceModel = try #require(decoded.assetRepository.asset(byName: "source-model.glb"))
        let runtimeModel = try #require(decoded.assetRepository.asset(byName: "runtime-model.usdz"))
        #expect(decoded.assetRepository.runtimeAssets(compiledFrom: sourceModel.id).map(\.id) == [runtimeModel.id])
        #expect(decoded.assetRepository.sourceAsset(forRuntimeAssetId: runtimeModel.id)?.id == sourceModel.id)
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

    @Test("legacy imported raw HyperTalk scripts are disabled on load")
    func legacyImportedRawHyperTalkScriptsAreDisabledOnLoad() throws {
        let store = HypeSQLiteStackStore()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyRawScriptSQLite-\(UUID().uuidString).hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        var document = HypeDocument.newDocument(name: "Legacy Raw Script")
        document.stack.script = "on openstack\rhide titlebar\rhide menubar\rdeskcover on,black\rend openstack"
        document.cards[0].script = "on openCard\n  put 1 into x\nend openCard"
        document.legacyImport = LegacyStackImportMetadata(
            sourceFileName: "Legacy Raw Script",
            dataForkSHA256: "fixture",
            report: HyperCardImportReport(
                stackName: "Legacy Raw Script",
                cardSize: HyperCardSize(width: document.stack.width, height: document.stack.height)
            )
        )

        try store.save(document, toPackageAt: packageURL)
        let loaded = try store.load(fromPackageAt: packageURL)

        #expect(loaded.stack.script.hasPrefix("-- Imported HyperCard script preserved for reference."))
        #expect(loaded.stack.script.contains("-- on openstack"))
        #expect(loaded.cards[0].script == document.cards[0].script)
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
        #expect(decoded.assetRepository.asset(byName: "hero")?.data == Data([0, 1, 2, 3]))
        #expect(decoded.aiContextLibrary.itemCount == 1)
    }

    @Test("older SQLite packages run document migrations before decoding")
    func olderSQLitePackagesRunDocumentMigrationsBeforeDecoding() throws {
        let store = HypeSQLiteStackStore()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigratedSQLite-\(UUID().uuidString).hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try store.save(try makePortableDocument(), toPackageAt: packageURL)
        try executeSQLite(
            """
            UPDATE document_values SET value_json = '1' WHERE key = 'documentVersion';
            INSERT OR REPLACE INTO document_values (key, value_json)
            VALUES ('migrationProbe', '{"spriteRepository":{"marker":true}}');
            """,
            in: packageURL
        )
        var manifest = try readManifest(at: packageURL)
        manifest.documentVersion = 1
        try writeManifest(manifest, at: packageURL)

        let loaded = try store.load(fromPackageAt: packageURL)

        #expect(loaded.documentVersion == HypeDocument.currentDocumentVersion)
        #expect(loaded.assetRepository.asset(byName: "hero")?.data == Data([0, 1, 2, 3]))
        #expect(try documentValue("documentVersion", in: packageURL) == "1", "Migration runs on a temporary copy; the source package changes only when saved again.")
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

        document.assetRepository.addAsset(Asset(
            name: "hero",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0, 1, 2, 3]),
            width: 1,
            height: 1,
            files: [
                AssetFile(
                    name: "hero-palette-preview.png",
                    role: .palette,
                    mimeType: "image/png",
                    data: Data([4, 5, 6]),
                    width: 1,
                    height: 1,
                    tags: ["hypercard-import"]
                )
            ],
            metadata: [
                AssetMetadataEntry(
                    key: "legacy-resource",
                    value: #"{"type":"PLTE","id":128}"#,
                    mimeType: "application/json",
                    tags: ["hypercard-import"]
                )
            ]
        ))
        let sourceModel = Asset(
            name: "source-model.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x67, 0x6C, 0x54, 0x46])
        )
        let runtimeModel = Asset(
            name: "runtime-model.usdz",
            kind: .model3D,
            mimeType: "model/vnd.usdz+zip",
            data: Data([0x55, 0x53, 0x44, 0x5A])
        )
        document.assetRepository.addAsset(sourceModel)
        document.assetRepository.addAsset(runtimeModel)
        document.assetRepository.linkCompiledAsset(
            sourceAssetId: sourceModel.id,
            runtimeAssetId: runtimeModel.id,
            operation: "model3d.usdz",
            compilerIdentifier: "hype.scene3d",
            compilerVersion: "1",
            sourceFingerprint: "sha256:source-model",
            optionsFingerprint: "sha256:default",
            compiledAt: Date(timeIntervalSince1970: 1_700_000_200)
        )

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

    private func readManifest(at packageURL: URL) throws -> HypeSQLiteManifest {
        let data = try Data(contentsOf: packageURL.appendingPathComponent(HypeSQLiteStackStore.manifestFileName))
        return try JSONDecoder().decode(HypeSQLiteManifest.self, from: data)
    }

    private func writeManifest(_ manifest: HypeSQLiteManifest, at packageURL: URL) throws {
        var updated = manifest
        let sqliteData = try Data(contentsOf: packageURL.appendingPathComponent(HypeSQLiteStackStore.sqliteFileName))
        updated.databaseSHA256 = SHA256.hash(data: sqliteData).map { String(format: "%02x", $0) }.joined()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(updated)
        try data.write(to: packageURL.appendingPathComponent(HypeSQLiteStackStore.manifestFileName), options: [.atomic])
    }

    private func documentValue(_ key: String, in packageURL: URL) throws -> String? {
        var result: String?
        try withSQLite(packageURL: packageURL, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT value_json FROM document_values WHERE key = ?", -1, &statement, nil) == SQLITE_OK, let statement else {
                throw HypeSQLiteStackStoreError.sqlite("Could not prepare document value query.")
            }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, key, -1, transient)
            if sqlite3_step(statement) == SQLITE_ROW {
                result = sqlite3_column_text(statement, 0).map { String(cString: $0) }
            }
        }
        return result
    }

    private func executeSQLite(_ sql: String, in packageURL: URL) throws {
        try withSQLite(packageURL: packageURL, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX) { db in
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "SQLite exec failed."
                throw HypeSQLiteStackStoreError.sqlite(message)
            }
        }
    }

    private func withSQLite(packageURL: URL, flags: Int32, _ work: (OpaquePointer) throws -> Void) throws {
        let sqliteURL = packageURL.appendingPathComponent(HypeSQLiteStackStore.sqliteFileName)
        var db: OpaquePointer?
        guard sqlite3_open_v2(sqliteURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw HypeSQLiteStackStoreError.sqlite("Could not open SQLite test database.")
        }
        defer { sqlite3_close(db) }
        try work(db)
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

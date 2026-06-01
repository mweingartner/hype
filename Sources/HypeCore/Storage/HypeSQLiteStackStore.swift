import CryptoKit
import Foundation
import SQLite3

public struct HypeSQLiteManifest: Codable, Sendable, Equatable {
    public var format: String
    public var formatVersion: Int
    public var schemaVersion: Int
    public var documentVersion: Int
    public var stackId: UUID
    public var stackName: String
    public var sqliteFile: String
    public var savedAt: Date
    public var databaseSHA256: String

    public init(
        format: String = "hype-sqlite-package",
        formatVersion: Int = 1,
        schemaVersion: Int = HypeSQLiteStackStore.schemaVersion,
        documentVersion: Int = HypeDocument.currentDocumentVersion,
        stackId: UUID,
        stackName: String,
        sqliteFile: String = HypeSQLiteStackStore.sqliteFileName,
        savedAt: Date = Date(),
        databaseSHA256: String
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.schemaVersion = schemaVersion
        self.documentVersion = documentVersion
        self.stackId = stackId
        self.stackName = stackName
        self.sqliteFile = sqliteFile
        self.savedAt = savedAt
        self.databaseSHA256 = databaseSHA256
    }

    private enum CodingKeys: String, CodingKey {
        case format, formatVersion, schemaVersion, documentVersion
        case stackId, stackName, sqliteFile, savedAt, databaseSHA256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        documentVersion = try container.decodeIfPresent(Int.self, forKey: .documentVersion) ?? 1
        stackId = try container.decode(UUID.self, forKey: .stackId)
        stackName = try container.decode(String.self, forKey: .stackName)
        sqliteFile = try container.decode(String.self, forKey: .sqliteFile)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        databaseSHA256 = try container.decode(String.self, forKey: .databaseSHA256)
    }
}

public struct HypeSQLiteDiagnostics: Sendable, Equatable {
    public var integrityCheck: String
    public var foreignKeyViolationCount: Int
    public var tableCounts: [String: Int]
    public var missingAssetReferenceCount: Int
    public var searchEntryCount: Int

    public var isHealthy: Bool {
        integrityCheck.lowercased() == "ok" &&
        foreignKeyViolationCount == 0 &&
        missingAssetReferenceCount == 0
    }
}

public struct HypeSQLiteSearchResult: Identifiable, Sendable, Equatable {
    public var id: String { "\(objectType):\(objectId)" }
    public var objectType: String
    public var objectId: String
    public var title: String
    public var snippet: String

    public init(objectType: String, objectId: String, title: String, snippet: String) {
        self.objectType = objectType
        self.objectId = objectId
        self.title = title
        self.snippet = snippet
    }
}

public enum HypeSQLiteStackStoreError: Error, LocalizedError, Equatable {
    case notAPackage
    case missingManifest
    case invalidManifest
    case missingSQLiteFile
    case databaseHashMismatch(expected: String, actual: String)
    case missingStack
    case unsupportedSchema(Int)
    case unsupportedDocumentVersion(Int)
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .notAPackage:
            return "The Hype stack is not a SQLite package."
        case .missingManifest:
            return "The Hype stack package does not contain \(HypeSQLiteStackStore.manifestFileName)."
        case .invalidManifest:
            return "The Hype stack package manifest is invalid."
        case .missingSQLiteFile:
            return "The Hype stack package does not contain \(HypeSQLiteStackStore.sqliteFileName)."
        case .databaseHashMismatch(let expected, let actual):
            return "The Hype stack database checksum does not match its manifest. Expected \(expected), got \(actual)."
        case .missingStack:
            return "The SQLite stack database does not contain a stack row."
        case .unsupportedSchema(let version):
            return "Unsupported Hype SQLite schema version \(version)."
        case .unsupportedDocumentVersion(let version):
            return "Unsupported Hype document version \(version)."
        case .sqlite(let message):
            return message
        }
    }
}

public final class HypeSQLiteStackStore {
    public static let schemaVersion = 7
    public static let manifestFileName = "manifest.json"
    public static let sqliteFileName = "stack.sqlite"

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func fileWrapper(for document: HypeDocument) throws -> FileWrapper {
        let temporaryDirectory = try makeTemporaryDirectory(prefix: "HypeSQLitePackage")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try save(document, toPackageAt: temporaryDirectory)
        let manifestData = try Data(contentsOf: temporaryDirectory.appendingPathComponent(Self.manifestFileName))
        let sqliteData = try Data(contentsOf: temporaryDirectory.appendingPathComponent(Self.sqliteFileName))
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            Self.manifestFileName: FileWrapper(regularFileWithContents: manifestData),
            Self.sqliteFileName: FileWrapper(regularFileWithContents: sqliteData),
        ])
        wrapper.preferredFilename = "\(document.stack.name).hype"
        return wrapper
    }

    public func load(from fileWrapper: FileWrapper) throws -> HypeDocument {
        guard fileWrapper.isDirectory, let wrappers = fileWrapper.fileWrappers else {
            throw HypeSQLiteStackStoreError.notAPackage
        }
        guard let manifestData = wrappers[Self.manifestFileName]?.regularFileContents else {
            throw HypeSQLiteStackStoreError.missingManifest
        }
        guard let sqliteData = wrappers[Self.sqliteFileName]?.regularFileContents else {
            throw HypeSQLiteStackStoreError.missingSQLiteFile
        }
        let manifest = try validateManifestData(manifestData, sqliteData: sqliteData)

        let temporaryDirectory = try makeTemporaryDirectory(prefix: "HypeSQLiteRead")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sqliteURL = temporaryDirectory.appendingPathComponent(Self.sqliteFileName)
        try sqliteData.write(to: sqliteURL, options: [.atomic])
        try migrateDatabaseIfNeeded(at: sqliteURL, manifest: manifest)
        return try load(fromDatabaseAt: sqliteURL)
    }

    public func load(fromPackageAt packageURL: URL) throws -> HypeDocument {
        let manifestURL = packageURL.appendingPathComponent(Self.manifestFileName)
        let sqliteURL = packageURL.appendingPathComponent(Self.sqliteFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw HypeSQLiteStackStoreError.missingManifest
        }
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else {
            throw HypeSQLiteStackStoreError.missingSQLiteFile
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let sqliteData = try Data(contentsOf: sqliteURL)
        let manifest = try validateManifestData(manifestData, sqliteData: sqliteData)
        let temporaryDirectory = try makeTemporaryDirectory(prefix: "HypeSQLiteRead")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let migratedSQLiteURL = temporaryDirectory.appendingPathComponent(Self.sqliteFileName)
        try sqliteData.write(to: migratedSQLiteURL, options: [.atomic])
        try migrateDatabaseIfNeeded(at: migratedSQLiteURL, manifest: manifest)
        return try load(fromDatabaseAt: migratedSQLiteURL)
    }

    public func save(_ document: HypeDocument, toPackageAt packageURL: URL) throws {
        let parent = packageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporaryDirectory = parent.appendingPathComponent(".\(packageURL.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        do {
            let sqliteURL = temporaryDirectory.appendingPathComponent(Self.sqliteFileName)
            try writeDatabase(for: document, at: sqliteURL)
            let sqliteData = try Data(contentsOf: sqliteURL)
            let manifest = HypeSQLiteManifest(
                documentVersion: HypeDocument.currentDocumentVersion,
                stackId: document.stack.id,
                stackName: document.stack.name,
                databaseSHA256: sqliteData.hypeSQLiteSHA256Hex
            )
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: temporaryDirectory.appendingPathComponent(Self.manifestFileName), options: [.atomic])

            try replacePackage(at: packageURL, with: temporaryDirectory)
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    public func validate(packageURL: URL) throws -> HypeSQLiteDiagnostics {
        let manifestURL = packageURL.appendingPathComponent(Self.manifestFileName)
        let sqliteURL = packageURL.appendingPathComponent(Self.sqliteFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw HypeSQLiteStackStoreError.missingManifest
        }
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else {
            throw HypeSQLiteStackStoreError.missingSQLiteFile
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let sqliteData = try Data(contentsOf: sqliteURL)
        let manifest = try validateManifestData(manifestData, sqliteData: sqliteData)
        let temporaryDirectory = try makeTemporaryDirectory(prefix: "HypeSQLiteValidate")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let migratedSQLiteURL = temporaryDirectory.appendingPathComponent(Self.sqliteFileName)
        try sqliteData.write(to: migratedSQLiteURL, options: [.atomic])
        try migrateDatabaseIfNeeded(at: migratedSQLiteURL, manifest: manifest)
        return try validate(databaseURL: migratedSQLiteURL)
    }

    public func validate(databaseURL: URL) throws -> HypeSQLiteDiagnostics {
        let db = try SQLiteDatabase(path: databaseURL.path, mode: .readOnly)
        try configureRead(db)
        let schemaVersion = try Int(db.scalarInt("PRAGMA user_version"))
        guard schemaVersion <= Self.schemaVersion else {
            throw HypeSQLiteStackStoreError.unsupportedSchema(schemaVersion)
        }

        let integrity = try db.scalarString("PRAGMA integrity_check") ?? "unknown"
        let foreignKeyViolations = try db.countRows("PRAGMA foreign_key_check")
        let tableNames = [
            "stacks", "backgrounds", "cards", "parts", "scripts",
            "assets", "ai_context_sources", "ai_context_items",
            "sprite_areas", "scenes", "scene_nodes", "themes",
            "paint_layers", "constraints", "music_patterns", "music_tracks",
            "music_notes", "apple_music_items", "apple_music_queues",
            "deployment_targets", "runtime_ai_settings", "search_fts",
        ]
        var tableCounts: [String: Int] = [:]
        for table in tableNames {
            tableCounts[table] = try db.tableExists(table)
                ? try db.scalarInt("SELECT COUNT(*) FROM \(table)")
                : 0
        }
        let missingAssetRefs = try db.countRows("""
            SELECT scene_nodes.id
            FROM scene_nodes
            LEFT JOIN assets ON assets.id = scene_nodes.asset_id
            WHERE scene_nodes.asset_id IS NOT NULL AND assets.id IS NULL
            """)
        let searchCount = try db.scalarInt("SELECT COUNT(*) FROM search_fts")
        return HypeSQLiteDiagnostics(
            integrityCheck: integrity,
            foreignKeyViolationCount: foreignKeyViolations,
            tableCounts: tableCounts,
            missingAssetReferenceCount: missingAssetRefs,
            searchEntryCount: searchCount
        )
    }

    public func search(packageURL: URL, query: String, limit: Int = 20) throws -> [HypeSQLiteSearchResult] {
        let sqliteURL = packageURL.appendingPathComponent(Self.sqliteFileName)
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else {
            throw HypeSQLiteStackStoreError.missingSQLiteFile
        }
        let manifestURL = packageURL.appendingPathComponent(Self.manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw HypeSQLiteStackStoreError.missingManifest
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let sqliteData = try Data(contentsOf: sqliteURL)
        let manifest = try validateManifestData(manifestData, sqliteData: sqliteData)
        let temporaryDirectory = try makeTemporaryDirectory(prefix: "HypeSQLiteSearch")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let migratedSQLiteURL = temporaryDirectory.appendingPathComponent(Self.sqliteFileName)
        try sqliteData.write(to: migratedSQLiteURL, options: [.atomic])
        try migrateDatabaseIfNeeded(at: migratedSQLiteURL, manifest: manifest)
        return try search(databaseURL: migratedSQLiteURL, query: query, limit: limit)
    }

    public func search(databaseURL: URL, query: String, limit: Int = 20) throws -> [HypeSQLiteSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let db = try SQLiteDatabase(path: databaseURL.path, mode: .readOnly)
        try configureRead(db)
        var results: [HypeSQLiteSearchResult] = []
        try db.query(
            """
            SELECT object_type, object_id, title,
                   snippet(search_fts, 3, '[', ']', '...', 12) AS snippet
            FROM search_fts
            WHERE search_fts MATCH ?
            LIMIT ?
            """,
            [.text(trimmed), .int(Int64(max(1, limit)))]
        ) { statement in
            results.append(HypeSQLiteSearchResult(
                objectType: statement.columnString(0) ?? "",
                objectId: statement.columnString(1) ?? "",
                title: statement.columnString(2) ?? "",
                snippet: statement.columnString(3) ?? ""
            ))
        }
        return results
    }

    private func load(fromDatabaseAt sqliteURL: URL) throws -> HypeDocument {
        let db = try SQLiteDatabase(path: sqliteURL.path, mode: .readOnly)
        try configureRead(db)
        let schemaVersion = try Int(db.scalarInt("PRAGMA user_version"))
        guard schemaVersion <= Self.schemaVersion else {
            throw HypeSQLiteStackStoreError.unsupportedSchema(schemaVersion)
        }
        let documentVersion: Int = try loadDocumentValue(Int.self, key: "documentVersion", db: db) ?? 1
        guard documentVersion <= HypeDocument.currentDocumentVersion else {
            throw HypeSQLiteStackStoreError.unsupportedDocumentVersion(documentVersion)
        }

        guard let stackPayload = try db.scalarString("SELECT payload_json FROM stacks LIMIT 1") else {
            throw HypeSQLiteStackStoreError.missingStack
        }
        let stack = try decode(Stack.self, from: stackPayload)
        let backgrounds: [Background] = try loadPayloadRows(Background.self, db: db, table: "backgrounds")
        let cards: [Card] = try loadPayloadRows(Card.self, db: db, table: "cards")
        let parts: [Part] = try loadParts(db: db)
        let paintLayers: [CardPaintLayer] = try loadPayloadRows(CardPaintLayer.self, db: db, table: "paint_layers")
        let constraints: [LayoutConstraint] = try loadPayloadRows(LayoutConstraint.self, db: db, table: "constraints")
        let assets: [Asset] = try loadPayloadRows(Asset.self, db: db, table: "assets")
        let musicLibrary = try loadMusicLibrary(db: db)
        let contextSources: [AIContextSource] = try loadPayloadRows(AIContextSource.self, db: db, table: "ai_context_sources")
        let contextItems: [AIContextItem] = try loadPayloadRows(AIContextItem.self, db: db, table: "ai_context_items")
        let themes: [HypeTheme] = try loadPayloadRows(HypeTheme.self, db: db, table: "themes")
        let aiPromptHistory: [String] = try loadDocumentValue([String].self, key: "aiPromptHistory", db: db) ?? []
        let defaultBackgroundId: UUID? = try loadDocumentValue(UUID.self, key: "defaultBackgroundId", db: db)
        let legacyImport: LegacyStackImportMetadata? = try loadDocumentValue(LegacyStackImportMetadata.self, key: "legacyImport", db: db)
        let stackLibrary: HypeStackLibrary = try loadDocumentValue(HypeStackLibrary.self, key: "stackLibrary", db: db) ?? HypeStackLibrary()

        var document = HypeDocument(
            documentVersion: documentVersion,
            stack: stack,
            backgrounds: backgrounds,
            cards: cards,
            parts: parts,
            paintLayers: paintLayers,
            constraints: constraints,
            assetRepository: AssetRepository(assets: assets),
            musicLibrary: musicLibrary,
            aiContextLibrary: AIContextLibrary(sources: contextSources, items: contextItems),
            aiPromptHistory: aiPromptHistory,
            scriptGlobals: [:],
            defaultBackgroundId: defaultBackgroundId,
            legacyImport: legacyImport,
            stackLibrary: stackLibrary,
            themes: themes
        )
        disableUntranslatedLegacyScriptsIfNeeded(&document)
        return document
    }

    private func disableUntranslatedLegacyScriptsIfNeeded(_ document: inout HypeDocument) {
        guard document.legacyImport != nil else { return }
        document.stack.script = disableLegacyScriptIfItCannotParse(document.stack.script)
        for index in document.backgrounds.indices {
            document.backgrounds[index].script = disableLegacyScriptIfItCannotParse(document.backgrounds[index].script)
        }
        for index in document.cards.indices {
            document.cards[index].script = disableLegacyScriptIfItCannotParse(document.cards[index].script)
        }
        for index in document.parts.indices {
            document.parts[index].script = disableLegacyScriptIfItCannotParse(document.parts[index].script)
        }
    }

    private func disableLegacyScriptIfItCannotParse(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("-- Imported HyperCard script preserved for reference.") else {
            return source
        }

        do {
            var lexer = Lexer(source: source)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            _ = try parser.parse()
            return source
        } catch {
            return LegacyHyperTalkScript.disabledForHypeTalkRuntime(source)
        }
    }

    private func writeDatabase(for document: HypeDocument, at sqliteURL: URL) throws {
        if FileManager.default.fileExists(atPath: sqliteURL.path) {
            try FileManager.default.removeItem(at: sqliteURL)
        }
        do {
            let db = try SQLiteDatabase(path: sqliteURL.path, mode: .readWriteCreate)
            try configureWrite(db)
            try createSchema(db)
            try db.transaction {
                try insertDocument(document, db: db)
            }
            try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            try db.execute("PRAGMA journal_mode = DELETE")
        }
        try removeSQLiteSidecars(for: sqliteURL)
    }

    private func configureRead(_ db: SQLiteDatabase) throws {
        try db.execute("PRAGMA foreign_keys = ON")
        try db.execute("PRAGMA query_only = ON")
    }

    private func configureWrite(_ db: SQLiteDatabase) throws {
        try db.execute("PRAGMA foreign_keys = ON")
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA synchronous = NORMAL")
    }

    private func createSchema(_ db: SQLiteDatabase) throws {
        try db.execute("PRAGMA user_version = \(Self.schemaVersion)")
        try db.execute("""
            CREATE TABLE document_values (
                key TEXT PRIMARY KEY,
                value_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE stacks (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                created_at REAL NOT NULL,
                modified_at REAL NOT NULL,
                default_font TEXT NOT NULL,
                theme_name TEXT NOT NULL,
                runtime_mode_enabled INTEGER NOT NULL,
                web_assets_allowed INTEGER NOT NULL,
                ai_context_cloud_allowed INTEGER NOT NULL,
                meshy_enabled INTEGER NOT NULL,
                script_id TEXT,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE deployment_targets (
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                platform TEXT NOT NULL,
                primary_target INTEGER NOT NULL,
                prompt_acknowledged INTEGER NOT NULL,
                profile_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                input_model TEXT NOT NULL,
                layout_policy TEXT NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL,
                PRIMARY KEY (stack_id, platform)
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE runtime_ai_settings (
                stack_id TEXT PRIMARY KEY REFERENCES stacks(id) ON DELETE CASCADE,
                provider_policy TEXT NOT NULL,
                allow_side_effect_tools INTEGER NOT NULL,
                allowed_tools_text TEXT NOT NULL,
                unavailable_fallback_text TEXT NOT NULL,
                persist_transcript INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE backgrounds (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                sort_key TEXT NOT NULL,
                theme_name TEXT,
                script_id TEXT,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE cards (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                background_id TEXT NOT NULL REFERENCES backgrounds(id),
                name TEXT NOT NULL,
                sort_key TEXT NOT NULL,
                marked INTEGER NOT NULL,
                theme_name TEXT,
                script_id TEXT,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE parts (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                card_id TEXT REFERENCES cards(id) ON DELETE CASCADE,
                background_id TEXT REFERENCES backgrounds(id) ON DELETE CASCADE,
                part_type TEXT NOT NULL,
                name TEXT NOT NULL,
                sort_key TEXT NOT NULL,
                group_id TEXT,
                left REAL NOT NULL,
                top REAL NOT NULL,
                width REAL NOT NULL,
                height REAL NOT NULL,
                rotation REAL NOT NULL,
                visible INTEGER NOT NULL,
                enabled INTEGER NOT NULL,
                hilite INTEGER NOT NULL,
                auto_hilite INTEGER NOT NULL,
                script_id TEXT,
                text_content TEXT NOT NULL,
                help_text TEXT NOT NULL,
                document_order INTEGER NOT NULL,
                audio_data BLOB,
                payload_json TEXT NOT NULL,
                CHECK ((card_id IS NOT NULL) != (background_id IS NOT NULL))
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE scripts (
                id TEXT PRIMARY KEY,
                owner_type TEXT NOT NULL,
                owner_id TEXT NOT NULL,
                language TEXT NOT NULL,
                source TEXT NOT NULL,
                parse_status TEXT NOT NULL,
                parse_error TEXT,
                parse_hash TEXT NOT NULL,
                updated_at REAL NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE assets (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                byte_count INTEGER NOT NULL,
                sha256 TEXT NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                tags TEXT NOT NULL,
                data BLOB NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE music_patterns (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                tempo INTEGER NOT NULL,
                time_signature TEXT NOT NULL,
                loop INTEGER NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE music_tracks (
                id TEXT PRIMARY KEY,
                pattern_id TEXT NOT NULL REFERENCES music_patterns(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                instrument TEXT NOT NULL,
                volume REAL NOT NULL,
                pan REAL NOT NULL,
                muted INTEGER NOT NULL,
                solo INTEGER NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE music_notes (
                id TEXT PRIMARY KEY,
                track_id TEXT NOT NULL REFERENCES music_tracks(id) ON DELETE CASCADE,
                note_index INTEGER NOT NULL,
                token TEXT NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE apple_music_items (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                source_kind TEXT NOT NULL,
                item_kind TEXT NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL,
                artwork_url TEXT NOT NULL,
                duration REAL,
                storefront TEXT NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE apple_music_queues (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                item_count INTEGER NOT NULL,
                shuffle INTEGER NOT NULL,
                repeat_mode TEXT NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE ai_context_sources (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE ai_context_items (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL REFERENCES ai_context_sources(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                role TEXT NOT NULL,
                text_summary TEXT NOT NULL,
                byte_count INTEGER NOT NULL,
                data BLOB,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE themes (
                id TEXT PRIMARY KEY,
                stack_id TEXT NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                is_built_in INTEGER NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE paint_layers (
                card_id TEXT PRIMARY KEY REFERENCES cards(id) ON DELETE CASCADE,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                byte_count INTEGER NOT NULL,
                rgba_data BLOB NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE constraints (
                id TEXT PRIMARY KEY,
                source_part_id TEXT NOT NULL,
                target_part_id TEXT,
                source_edge TEXT NOT NULL,
                target_edge TEXT NOT NULL,
                target_type TEXT NOT NULL,
                distance REAL NOT NULL,
                document_order INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE sprite_areas (
                part_id TEXT PRIMARY KEY REFERENCES parts(id) ON DELETE CASCADE,
                active_scene_id TEXT,
                design_width REAL NOT NULL,
                design_height REAL NOT NULL,
                scale_mode TEXT NOT NULL,
                shows_physics INTEGER NOT NULL,
                shows_fps INTEGER NOT NULL,
                shows_node_count INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE scenes (
                id TEXT PRIMARY KEY,
                sprite_area_part_id TEXT NOT NULL REFERENCES sprite_areas(part_id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                sort_key INTEGER NOT NULL,
                width REAL NOT NULL,
                height REAL NOT NULL,
                background_color TEXT NOT NULL,
                gravity_dx REAL NOT NULL,
                gravity_dy REAL NOT NULL,
                is_paused INTEGER NOT NULL,
                scale_mode TEXT NOT NULL,
                script_id TEXT,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE TABLE scene_nodes (
                id TEXT PRIMARY KEY,
                scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
                parent_node_id TEXT REFERENCES scene_nodes(id) ON DELETE CASCADE,
                node_type TEXT NOT NULL,
                name TEXT NOT NULL,
                sort_key INTEGER NOT NULL,
                x REAL NOT NULL,
                y REAL NOT NULL,
                z REAL NOT NULL,
                rotation REAL NOT NULL,
                x_scale REAL NOT NULL,
                y_scale REAL NOT NULL,
                alpha REAL NOT NULL,
                hidden INTEGER NOT NULL,
                width REAL,
                height REAL,
                asset_id TEXT,
                script_id TEXT,
                payload_json TEXT NOT NULL
            ) STRICT
            """)
        try db.execute("""
            CREATE VIRTUAL TABLE search_fts USING fts5(
                object_type UNINDEXED,
                object_id UNINDEXED,
                title,
                body,
                tags
            )
            """)
        try db.execute("CREATE INDEX idx_cards_stack_sort ON cards(stack_id, sort_key)")
        try db.execute("CREATE INDEX idx_parts_card_sort ON parts(card_id, document_order)")
        try db.execute("CREATE INDEX idx_parts_background_sort ON parts(background_id, document_order)")
        try db.execute("CREATE INDEX idx_parts_name_scope ON parts(stack_id, name COLLATE NOCASE)")
        try db.execute("CREATE INDEX idx_scripts_owner ON scripts(owner_type, owner_id)")
        try db.execute("CREATE INDEX idx_scene_nodes_scene_parent_sort ON scene_nodes(scene_id, parent_node_id, sort_key)")
        try db.execute("CREATE INDEX idx_assets_name ON assets(stack_id, name COLLATE NOCASE)")
        try db.execute("CREATE INDEX idx_music_patterns_name ON music_patterns(stack_id, name COLLATE NOCASE)")
        try db.execute("CREATE INDEX idx_music_tracks_pattern_sort ON music_tracks(pattern_id, document_order)")
        try db.execute("CREATE INDEX idx_apple_music_items_lookup ON apple_music_items(stack_id, item_kind, id)")
        try db.execute("CREATE INDEX idx_apple_music_queues_name ON apple_music_queues(stack_id, name COLLATE NOCASE)")
        try db.execute("CREATE INDEX idx_deployment_targets_stack ON deployment_targets(stack_id, document_order)")
        try db.execute("CREATE INDEX idx_runtime_ai_settings_policy ON runtime_ai_settings(provider_policy)")
        try db.execute("CREATE VIEW v_card_layout AS SELECT cards.name AS card, parts.name AS part, parts.part_type, parts.left, parts.top, parts.width, parts.height, parts.document_order FROM cards JOIN parts ON parts.card_id = cards.id")
        try db.execute("CREATE VIEW v_object_scripts AS SELECT owner_type, owner_id, parse_status, substr(source, 1, 160) AS preview FROM scripts")
        try db.execute("CREATE VIEW v_missing_asset_refs AS SELECT scene_nodes.id AS node_id, scene_nodes.name, scene_nodes.asset_id FROM scene_nodes LEFT JOIN assets ON assets.id = scene_nodes.asset_id WHERE scene_nodes.asset_id IS NOT NULL AND assets.id IS NULL")
        try db.execute("CREATE VIEW v_music_patterns AS SELECT music_patterns.name AS pattern, music_patterns.tempo, music_tracks.name AS track, music_tracks.instrument, music_tracks.document_order FROM music_patterns LEFT JOIN music_tracks ON music_tracks.pattern_id = music_patterns.id")
        try db.execute("CREATE VIEW v_apple_music_items AS SELECT title, artist, album, source_kind, item_kind, id FROM apple_music_items")
        try db.execute("CREATE VIEW v_deployment_targets AS SELECT stacks.name AS stack, deployment_targets.platform, deployment_targets.display_name, deployment_targets.width, deployment_targets.height, deployment_targets.primary_target, deployment_targets.layout_policy FROM deployment_targets JOIN stacks ON stacks.id = deployment_targets.stack_id")
        try db.execute("CREATE VIEW v_runtime_ai_settings AS SELECT stacks.name AS stack, runtime_ai_settings.provider_policy, runtime_ai_settings.allow_side_effect_tools, runtime_ai_settings.allowed_tools_text, runtime_ai_settings.persist_transcript FROM runtime_ai_settings JOIN stacks ON stacks.id = runtime_ai_settings.stack_id")
    }

    private func insertDocument(_ document: HypeDocument, db: SQLiteDatabase) throws {
        let stackScriptId = try insertScript(ownerType: "stack", ownerId: document.stack.id.uuidString, source: document.stack.script, db: db)
        try db.execute(
            """
            INSERT INTO stacks (
                id, name, width, height, created_at, modified_at, default_font,
                theme_name, runtime_mode_enabled, web_assets_allowed,
                ai_context_cloud_allowed, meshy_enabled, script_id, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(document.stack.id.uuidString),
                .text(document.stack.name),
                .int(Int64(document.stack.width)),
                .int(Int64(document.stack.height)),
                .double(document.stack.createdAt.timeIntervalSince1970),
                .double(document.stack.modifiedAt.timeIntervalSince1970),
                .text(document.stack.defaultFont),
                .text(document.stack.themeName),
                .int(document.stack.runtimeModeEnabled.sqliteInt),
                .int(document.stack.webAssetsAllowed.sqliteInt),
                .int(document.stack.aiContextCloudSharingAllowed.sqliteInt),
                .int(document.stack.meshyEnabled.sqliteInt),
                .text(stackScriptId),
                .text(try encode(document.stack)),
            ]
        )
        try insertSearch(objectType: "stack", objectId: document.stack.id.uuidString, title: document.stack.name, body: document.stack.script, tags: "stack", db: db)
        try insertDeploymentTargets(document.stack.deploymentTargets, stackId: document.stack.id, db: db)
        try insertRuntimeAISettings(document.stack.runtimeAISettings, stackId: document.stack.id, db: db)

        try storeDocumentValue(HypeDocument.currentDocumentVersion, key: "documentVersion", db: db)
        try storeDocumentValue(document.aiPromptHistory, key: "aiPromptHistory", db: db)
        if let defaultBackgroundId = document.defaultBackgroundId {
            try storeDocumentValue(defaultBackgroundId, key: "defaultBackgroundId", db: db)
        }
        if let legacyImport = document.legacyImport {
            try storeDocumentValue(legacyImport, key: "legacyImport", db: db)
        }
        if !document.stackLibrary.isEmpty {
            try storeDocumentValue(document.stackLibrary, key: "stackLibrary", db: db)
        }

        for (index, background) in document.backgrounds.enumerated() {
            let scriptId = try insertScript(ownerType: "background", ownerId: background.id.uuidString, source: background.script, db: db)
            try db.execute(
                "INSERT INTO backgrounds (id, stack_id, name, sort_key, theme_name, script_id, document_order, payload_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(background.id.uuidString),
                    .text(background.stackId.uuidString),
                    .text(background.name),
                    .text(background.sortKey),
                    background.themeName.sqliteValue,
                    .text(scriptId),
                    .int(Int64(index)),
                    .text(try encode(background)),
                ]
            )
            try insertSearch(objectType: "background", objectId: background.id.uuidString, title: background.name, body: background.script, tags: "background", db: db)
        }

        for (index, card) in document.cards.enumerated() {
            let scriptId = try insertScript(ownerType: "card", ownerId: card.id.uuidString, source: card.script, db: db)
            try db.execute(
                "INSERT INTO cards (id, stack_id, background_id, name, sort_key, marked, theme_name, script_id, document_order, payload_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(card.id.uuidString),
                    .text(card.stackId.uuidString),
                    .text(card.backgroundId.uuidString),
                    .text(card.name),
                    .text(card.sortKey),
                    .int(card.marked.sqliteInt),
                    card.themeName.sqliteValue,
                    .text(scriptId),
                    .int(Int64(index)),
                    .text(try encode(card)),
                ]
            )
            try insertSearch(objectType: "card", objectId: card.id.uuidString, title: card.name, body: card.script, tags: "card", db: db)
        }

        for (index, part) in document.parts.enumerated() {
            let scriptId = try insertScript(ownerType: "part", ownerId: part.id.uuidString, source: part.script, db: db)
            var payloadPart = part
            payloadPart.audioData = nil
            try db.execute(
                """
                INSERT INTO parts (
                    id, stack_id, card_id, background_id, part_type, name, sort_key, group_id,
                    left, top, width, height, rotation, visible, enabled, hilite, auto_hilite,
                    script_id, text_content, help_text, document_order, audio_data, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(part.id.uuidString),
                    .text(document.stack.id.uuidString),
                    part.cardId.sqliteValue,
                    part.backgroundId.sqliteValue,
                    .text(part.partType.rawValue),
                    .text(part.name),
                    .text(part.sortKey),
                    part.groupId.sqliteValue,
                    .double(part.left),
                    .double(part.top),
                    .double(part.width),
                    .double(part.height),
                    .double(part.rotation),
                    .int(part.visible.sqliteInt),
                    .int(part.enabled.sqliteInt),
                    .int(part.hilite.sqliteInt),
                    .int(part.autoHilite.sqliteInt),
                    .text(scriptId),
                    .text(part.textContent),
                    .text(part.helpText),
                    .int(Int64(index)),
                    part.audioData.map(SQLiteValue.blob) ?? .null,
                    .text(try encode(payloadPart)),
                ]
            )
            let body = [part.textContent, part.helpText, part.script, part.popupItems, part.url, part.searchText, part.menuItems]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            try insertSearch(objectType: "part", objectId: part.id.uuidString, title: part.name, body: body, tags: part.partType.rawValue, db: db)
            if let area = part.spriteAreaSpecModel {
                try insertSpriteArea(area, partId: part.id, db: db)
            }
        }

        for (index, asset) in document.assetRepository.assets.enumerated() {
            try db.execute(
                """
                INSERT INTO assets (
                    id, stack_id, name, kind, mime_type, byte_count, sha256,
                    width, height, tags, data, document_order, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(asset.id.uuidString),
                    .text(document.stack.id.uuidString),
                    .text(asset.name),
                    .text(asset.kind.rawValue),
                    .text(asset.mimeType),
                    .int(Int64(asset.data.count)),
                    .text(asset.data.hypeSQLiteSHA256Hex),
                    .int(Int64(asset.width)),
                    .int(Int64(asset.height)),
                    .text(asset.tags.joined(separator: ",")),
                    .blob(asset.data),
                    .int(Int64(index)),
                    .text(try encode(asset)),
                ]
            )
            let provenance = asset.provenance.map { (try? encode($0)) ?? "" } ?? ""
            try insertSearch(objectType: "asset", objectId: asset.id.uuidString, title: asset.name, body: provenance, tags: ([asset.kind.rawValue] + asset.tags).joined(separator: " "), db: db)
        }

        for (index, pattern) in document.musicLibrary.patterns.enumerated() {
            try insertMusicPattern(pattern, stackId: document.stack.id, documentOrder: index, db: db)
            let body = pattern.tracks
                .map { "\($0.name) \($0.instrument)\n\($0.noteString)" }
                .joined(separator: "\n")
            try insertSearch(objectType: "music_pattern", objectId: pattern.id.uuidString, title: pattern.name, body: body, tags: "music pattern", db: db)
        }
        for (index, item) in document.musicLibrary.appleMusicItems.enumerated() {
            try insertAppleMusicItem(item, stackId: document.stack.id, documentOrder: index, db: db)
            let body = [item.artistSnapshot, item.albumSnapshot, item.encodedSource].filter { !$0.isEmpty }.joined(separator: "\n")
            try insertSearch(objectType: "apple_music_item", objectId: item.id, title: item.titleSnapshot, body: body, tags: "apple music \(item.kind.rawValue) \(item.source.rawValue)", db: db)
        }
        for (index, queue) in document.musicLibrary.appleMusicQueues.enumerated() {
            try insertAppleMusicQueue(queue, stackId: document.stack.id, documentOrder: index, db: db)
            let body = queue.items.map { "\($0.titleSnapshot) \($0.artistSnapshot)" }.joined(separator: "\n")
            try insertSearch(objectType: "apple_music_queue", objectId: queue.id.uuidString, title: queue.name, body: body, tags: "apple music queue", db: db)
        }

        for (index, source) in document.aiContextLibrary.sources.enumerated() {
            try db.execute(
                "INSERT INTO ai_context_sources (id, stack_id, name, kind, status, document_order, payload_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(source.id.uuidString),
                    .text(document.stack.id.uuidString),
                    .text(source.name),
                    .text(source.kind.rawValue),
                    .text(source.status.rawValue),
                    .int(Int64(index)),
                    .text(try encode(source)),
                ]
            )
        }
        for (index, item) in document.aiContextLibrary.items.enumerated() {
            try db.execute(
                """
                INSERT INTO ai_context_items (
                    id, source_id, name, relative_path, mime_type, role, text_summary,
                    byte_count, data, document_order, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(item.id.uuidString),
                    .text(item.sourceId.uuidString),
                    .text(item.name),
                    .text(item.relativePath),
                    .text(item.mimeType),
                    .text(item.role.rawValue),
                    .text(item.textSummary),
                    .int(Int64(item.byteCount)),
                    item.data.map(SQLiteValue.blob) ?? .null,
                    .int(Int64(index)),
                    .text(try encode(item)),
                ]
            )
            let body = ([item.textSummary] + item.textChunks.map(\.text)).joined(separator: "\n")
            try insertSearch(objectType: "ai_context_item", objectId: item.id.uuidString, title: item.name, body: body, tags: item.role.rawValue, db: db)
        }

        for (index, theme) in document.themes.enumerated() {
            try db.execute(
                "INSERT INTO themes (id, stack_id, name, is_built_in, document_order, payload_json) VALUES (?, ?, ?, ?, ?, ?)",
                [
                    .text(theme.id.uuidString),
                    .text(document.stack.id.uuidString),
                    .text(theme.name),
                    .int(theme.isBuiltIn.sqliteInt),
                    .int(Int64(index)),
                    .text(try encode(theme)),
                ]
            )
        }

        for (index, layer) in document.paintLayers.enumerated() {
            let data = layer.normalizedRGBAData
            try db.execute(
                "INSERT INTO paint_layers (card_id, width, height, byte_count, rgba_data, document_order, payload_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(layer.cardId.uuidString),
                    .int(Int64(layer.width)),
                    .int(Int64(layer.height)),
                    .int(Int64(data.count)),
                    .blob(data),
                    .int(Int64(index)),
                    .text(try encode(layer)),
                ]
            )
        }

        for (index, constraint) in document.constraints.enumerated() {
            try db.execute(
                "INSERT INTO constraints (id, source_part_id, target_part_id, source_edge, target_edge, target_type, distance, document_order, payload_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(constraint.id.uuidString),
                    .text(constraint.sourcePartId.uuidString),
                    constraint.targetPartId.sqliteValue,
                    .text(constraint.sourceEdge.rawValue),
                    .text(constraint.targetEdge.rawValue),
                    .text(constraint.targetType.rawValue),
                    .double(constraint.distance),
                    .int(Int64(index)),
                    .text(try encode(constraint)),
                ]
            )
        }
    }

    private func insertSpriteArea(_ area: SpriteAreaSpec, partId: UUID, db: SQLiteDatabase) throws {
        try db.execute(
            """
            INSERT INTO sprite_areas (
                part_id, active_scene_id, design_width, design_height, scale_mode,
                shows_physics, shows_fps, shows_node_count, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(partId.uuidString),
                .text(area.activeSceneID.uuidString),
                .double(area.designSize.width),
                .double(area.designSize.height),
                .text(area.scaleMode.rawValue),
                .int(area.showsPhysics.sqliteInt),
                .int(area.showsFPS.sqliteInt),
                .int(area.showsNodeCount.sqliteInt),
                .text(try encode(area)),
            ]
        )
        for (index, entry) in area.scenes.enumerated() {
            let scene = entry.scene
            let scriptId = try insertScript(ownerType: "scene", ownerId: entry.id.uuidString, source: scene.script, db: db)
            try db.execute(
                """
                INSERT INTO scenes (
                    id, sprite_area_part_id, name, sort_key, width, height,
                    background_color, gravity_dx, gravity_dy, is_paused,
                    scale_mode, script_id, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(entry.id.uuidString),
                    .text(partId.uuidString),
                    .text(scene.name),
                    .int(Int64(index)),
                    .double(scene.size.width),
                    .double(scene.size.height),
                    .text(scene.backgroundColor),
                    .double(scene.gravity.dx),
                    .double(scene.gravity.dy),
                    .int(scene.isPaused.sqliteInt),
                    .text(scene.scaleMode.rawValue),
                    .text(scriptId),
                    .text(try encode(scene)),
                ]
            )
            try insertSearch(objectType: "scene", objectId: entry.id.uuidString, title: scene.name, body: scene.script, tags: "scene spritekit", db: db)
            try insertSceneNodes(scene.nodes, sceneId: entry.id, parentNodeId: nil, db: db)
        }
    }

    private func insertMusicPattern(_ pattern: MusicPatternSpec, stackId: UUID, documentOrder: Int, db: SQLiteDatabase) throws {
        try db.execute(
            """
            INSERT INTO music_patterns (
                id, stack_id, name, tempo, time_signature, loop, document_order, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(pattern.id.uuidString),
                .text(stackId.uuidString),
                .text(pattern.name),
                .int(Int64(pattern.tempo)),
                .text(pattern.timeSignature),
                .int(pattern.loop.sqliteInt),
                .int(Int64(documentOrder)),
                .text(try encode(pattern)),
            ]
        )
        for (trackIndex, track) in pattern.tracks.enumerated() {
            try db.execute(
                """
                INSERT INTO music_tracks (
                    id, pattern_id, name, instrument, volume, pan, muted, solo,
                    document_order, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(track.id.uuidString),
                    .text(pattern.id.uuidString),
                    .text(track.name),
                    .text(track.instrument),
                    .double(track.volume),
                    .double(track.pan),
                    .int(track.muted.sqliteInt),
                    .int(track.solo.sqliteInt),
                    .int(Int64(trackIndex)),
                    .text(try encode(track)),
                ]
            )
            for (noteIndex, token) in track.noteString.split(separator: " ", omittingEmptySubsequences: true).enumerated() {
                let escaped = String(token).replacingOccurrences(of: "\"", with: "\\\"")
                try db.execute(
                    "INSERT INTO music_notes (id, track_id, note_index, token, payload_json) VALUES (?, ?, ?, ?, ?)",
                    [
                        .text("\(track.id.uuidString)-\(noteIndex)"),
                        .text(track.id.uuidString),
                        .int(Int64(noteIndex)),
                        .text(String(token)),
                        .text("{\"token\":\"\(escaped)\"}"),
                    ]
                )
            }
        }
    }

    private func insertAppleMusicItem(_ item: AppleMusicItemRef, stackId: UUID, documentOrder: Int, db: SQLiteDatabase) throws {
        try db.execute(
            """
            INSERT INTO apple_music_items (
                id, stack_id, source_kind, item_kind, title, artist, album, artwork_url,
                duration, storefront, document_order, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id),
                .text(stackId.uuidString),
                .text(item.source.rawValue),
                .text(item.kind.rawValue),
                .text(item.titleSnapshot),
                .text(item.artistSnapshot),
                .text(item.albumSnapshot),
                .text(item.artworkURLSnapshot),
                item.durationSnapshot.map { .double($0) } ?? .null,
                .text(item.storefront),
                .int(Int64(documentOrder)),
                .text(try encode(item)),
            ]
        )
    }

    private func insertAppleMusicQueue(_ queue: AppleMusicQueueSpec, stackId: UUID, documentOrder: Int, db: SQLiteDatabase) throws {
        try db.execute(
            """
            INSERT INTO apple_music_queues (
                id, stack_id, name, item_count, shuffle, repeat_mode, document_order, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(queue.id.uuidString),
                .text(stackId.uuidString),
                .text(queue.name),
                .int(Int64(queue.items.count)),
                .int(queue.shuffle.sqliteInt),
                .text(queue.repeatMode),
                .int(Int64(documentOrder)),
                .text(try encode(queue)),
            ]
        )
    }

    private func insertDeploymentTargets(_ targets: StackDeploymentTargets, stackId: UUID, db: SQLiteDatabase) throws {
        var normalized = targets
        normalized.normalize()
        for (index, platform) in normalized.selectedPlatforms.enumerated() {
            let profile = HypeDeviceProfileCatalog.defaultProfile(for: platform)
            try db.execute(
                """
                INSERT INTO deployment_targets (
                    stack_id, platform, primary_target, prompt_acknowledged,
                    profile_id, display_name, width, height, input_model,
                    layout_policy, document_order, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(stackId.uuidString),
                    .text(platform.rawValue),
                    .int((platform == normalized.primaryPlatform).sqliteInt),
                    .int(normalized.selectionPromptAcknowledged.sqliteInt),
                    .text(profile.id),
                    .text(profile.displayName),
                    .int(Int64(profile.width)),
                    .int(Int64(profile.height)),
                    .text(profile.inputModel.rawValue),
                    .text(normalized.layoutPolicy.rawValue),
                    .int(Int64(index)),
                    .text(try encode(profile)),
                ]
            )
        }
    }

    private func insertRuntimeAISettings(_ settings: RuntimeAISettings, stackId: UUID, db: SQLiteDatabase) throws {
        var normalized = settings
        normalized.normalize()
        try db.execute(
            """
            INSERT INTO runtime_ai_settings (
                stack_id, provider_policy, allow_side_effect_tools,
                allowed_tools_text, unavailable_fallback_text,
                persist_transcript, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(stackId.uuidString),
                .text(normalized.providerPolicy.rawValue),
                .int(normalized.allowRuntimeSideEffectTools.sqliteInt),
                .text(normalized.allowedToolNames.joined(separator: ",")),
                .text(normalized.unavailableFallbackText),
                .int(normalized.persistTranscript.sqliteInt),
                .text(try encode(normalized)),
            ]
        )
    }

    private func insertSceneNodes(_ nodes: [HypeNodeSpec], sceneId: UUID, parentNodeId: UUID?, db: SQLiteDatabase) throws {
        for (index, node) in nodes.enumerated() {
            let scriptId = try insertScript(ownerType: "scene_node", ownerId: node.id.uuidString, source: node.script, db: db)
            try db.execute(
                """
                INSERT INTO scene_nodes (
                    id, scene_id, parent_node_id, node_type, name, sort_key,
                    x, y, z, rotation, x_scale, y_scale, alpha, hidden,
                    width, height, asset_id, script_id, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(node.id.uuidString),
                    .text(sceneId.uuidString),
                    parentNodeId.sqliteValue,
                    .text(node.nodeType.rawValue),
                    .text(node.name),
                    .int(Int64(index)),
                    .double(node.position.x),
                    .double(node.position.y),
                    .double(node.zPosition),
                    .double(node.rotation),
                    .double(node.xScale),
                    .double(node.yScale),
                    .double(node.alpha),
                    .int(node.isHidden.sqliteInt),
                    node.size.map { .double($0.width) } ?? .null,
                    node.size.map { .double($0.height) } ?? .null,
                    node.assetRef?.id.sqliteValue ?? .null,
                    .text(scriptId),
                    .text(try encode(node)),
                ]
            )
            let body = [node.text ?? "", node.script].filter { !$0.isEmpty }.joined(separator: "\n")
            try insertSearch(objectType: "scene_node", objectId: node.id.uuidString, title: node.name, body: body, tags: node.nodeType.rawValue, db: db)
            try insertSceneNodes(node.children, sceneId: sceneId, parentNodeId: node.id, db: db)
        }
    }

    private func insertScript(ownerType: String, ownerId: String, source: String, db: SQLiteDatabase) throws -> String {
        let id = "\(ownerType):\(ownerId)"
        let parseResult = parseStatus(for: source)
        try db.execute(
            "INSERT INTO scripts (id, owner_type, owner_id, language, source, parse_status, parse_error, parse_hash, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                .text(id),
                .text(ownerType),
                .text(ownerId),
                .text("HypeTalk"),
                .text(source),
                .text(parseResult.status),
                parseResult.error.sqliteValue,
                .text(source.data(using: .utf8)?.hypeSQLiteSHA256Hex ?? ""),
                .double(Date().timeIntervalSince1970),
            ]
        )
        return id
    }

    private func parseStatus(for source: String) -> (status: String, error: String?) {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ("empty", nil)
        }
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        do {
            _ = try parser.parse()
            return ("valid", nil)
        } catch {
            return ("invalid", String(describing: error))
        }
    }

    private func insertSearch(objectType: String, objectId: String, title: String, body: String, tags: String, db: SQLiteDatabase) throws {
        guard !(title.isEmpty && body.isEmpty && tags.isEmpty) else { return }
        try db.execute(
            "INSERT INTO search_fts (object_type, object_id, title, body, tags) VALUES (?, ?, ?, ?, ?)",
            [.text(objectType), .text(objectId), .text(title), .text(body), .text(tags)]
        )
    }

    private func storeDocumentValue<T: Encodable>(_ value: T, key: String, db: SQLiteDatabase) throws {
        try db.execute(
            "INSERT INTO document_values (key, value_json) VALUES (?, ?)",
            [.text(key), .text(try encode(value))]
        )
    }

    private func loadDocumentValue<T: Decodable>(_ type: T.Type, key: String, db: SQLiteDatabase) throws -> T? {
        guard let payload = try db.scalarString("SELECT value_json FROM document_values WHERE key = ?", [.text(key)]) else {
            return nil
        }
        return try decode(T.self, from: payload)
    }

    private func loadPayloadRows<T: Decodable>(_ type: T.Type, db: SQLiteDatabase, table: String) throws -> [T] {
        var values: [T] = []
        try db.query("SELECT payload_json FROM \(table) ORDER BY document_order") { statement in
            if let payload = statement.columnString(0) {
                values.append(try decode(T.self, from: payload))
            }
        }
        return values
    }

    private func loadParts(db: SQLiteDatabase) throws -> [Part] {
        let hasAudioDataColumn = try db.columnExists(table: "parts", column: "audio_data")
        var values: [Part] = []
        let sql = hasAudioDataColumn
            ? "SELECT payload_json, audio_data FROM parts ORDER BY document_order"
            : "SELECT payload_json FROM parts ORDER BY document_order"
        try db.query(sql) { statement in
            guard let payload = statement.columnString(0) else { return }
            var part = try decode(Part.self, from: payload)
            if hasAudioDataColumn, let data = statement.columnData(1), !data.isEmpty {
                part.audioData = data
                part.audioEmbedInStack = true
            }
            values.append(part)
        }
        return values
    }

    private func loadMusicLibrary(db: SQLiteDatabase) throws -> MusicLibrary {
        guard try db.tableExists("music_patterns") else {
            return try loadDocumentValue(MusicLibrary.self, key: "musicLibrary", db: db) ?? MusicLibrary()
        }
        let patterns: [MusicPatternSpec] = try loadPayloadRows(MusicPatternSpec.self, db: db, table: "music_patterns")
        let appleMusicItems: [AppleMusicItemRef] = try db.tableExists("apple_music_items")
            ? loadPayloadRows(AppleMusicItemRef.self, db: db, table: "apple_music_items")
            : (try loadDocumentValue(MusicLibrary.self, key: "musicLibrary", db: db)?.appleMusicItems ?? [])
        let appleMusicQueues: [AppleMusicQueueSpec] = try db.tableExists("apple_music_queues")
            ? loadPayloadRows(AppleMusicQueueSpec.self, db: db, table: "apple_music_queues")
            : (try loadDocumentValue(MusicLibrary.self, key: "musicLibrary", db: db)?.appleMusicQueues ?? [])
        return MusicLibrary(patterns: patterns, appleMusicItems: appleMusicItems, appleMusicQueues: appleMusicQueues)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw HypeSQLiteStackStoreError.sqlite("Encoded JSON was not UTF-8.")
        }
        return string
    }

    private func decode<T: Decodable>(_ type: T.Type, from payload: String) throws -> T {
        guard let data = payload.data(using: .utf8) else {
            throw HypeSQLiteStackStoreError.sqlite("Stored JSON payload was not UTF-8.")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func validateManifestData(_ manifestData: Data, sqliteData: Data) throws -> HypeSQLiteManifest {
        let manifest: HypeSQLiteManifest
        do {
            manifest = try decoder.decode(HypeSQLiteManifest.self, from: manifestData)
        } catch {
            throw HypeSQLiteStackStoreError.invalidManifest
        }
        guard manifest.format == "hype-sqlite-package",
              manifest.formatVersion == 1,
              manifest.sqliteFile == Self.sqliteFileName else {
            throw HypeSQLiteStackStoreError.invalidManifest
        }
        guard manifest.schemaVersion <= Self.schemaVersion else {
            throw HypeSQLiteStackStoreError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.documentVersion <= HypeDocument.currentDocumentVersion else {
            throw HypeSQLiteStackStoreError.unsupportedDocumentVersion(manifest.documentVersion)
        }
        let actualHash = sqliteData.hypeSQLiteSHA256Hex
        guard manifest.databaseSHA256 == actualHash else {
            throw HypeSQLiteStackStoreError.databaseHashMismatch(
                expected: manifest.databaseSHA256,
                actual: actualHash
            )
        }
        return manifest
    }

    private func migrateDatabaseIfNeeded(at sqliteURL: URL, manifest: HypeSQLiteManifest) throws {
        do {
            let db = try SQLiteDatabase(path: sqliteURL.path, mode: .readWriteCreate)
            try configureWrite(db)
            let storedDocumentVersion = try loadStoredDocumentVersion(db: db)
            var documentVersion = storedDocumentVersion ?? manifest.documentVersion
            guard documentVersion <= HypeDocument.currentDocumentVersion else {
                throw HypeSQLiteStackStoreError.unsupportedDocumentVersion(documentVersion)
            }

            if documentVersion < HypeDocument.currentDocumentVersion {
                try db.transaction {
                    while documentVersion < HypeDocument.currentDocumentVersion {
                        switch documentVersion {
                        case 1:
                            try HypeDocumentMigrationV1ToV2().migrate(db: db)
                            documentVersion = 2
                        default:
                            throw HypeSQLiteStackStoreError.unsupportedDocumentVersion(documentVersion)
                        }
                        try storeDocumentVersion(documentVersion, db: db)
                    }
                }
            }
            try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            try db.execute("PRAGMA journal_mode = DELETE")
        }
        try removeSQLiteSidecars(for: sqliteURL)
    }

    private func loadStoredDocumentVersion(db: SQLiteDatabase) throws -> Int? {
        guard try db.tableExists("document_values"),
              let payload = try db.scalarString("SELECT value_json FROM document_values WHERE key = 'documentVersion'") else {
            return nil
        }
        return try decode(Int.self, from: payload)
    }

    private func storeDocumentVersion(_ version: Int, db: SQLiteDatabase) throws {
        guard try db.tableExists("document_values") else { return }
        try db.execute(
            "INSERT OR REPLACE INTO document_values (key, value_json) VALUES ('documentVersion', ?)",
            [.text(String(version))]
        )
    }

    private func replacePackage(at packageURL: URL, with temporaryDirectory: URL) throws {
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            try FileManager.default.moveItem(at: temporaryDirectory, to: packageURL)
            return
        }

        let backupURL = packageURL.deletingLastPathComponent()
            .appendingPathComponent(".\(packageURL.lastPathComponent)-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: packageURL, to: backupURL)
        do {
            try FileManager.default.moveItem(at: temporaryDirectory, to: packageURL)
            try? FileManager.default.removeItem(at: backupURL)
        } catch {
            try? FileManager.default.moveItem(at: backupURL, to: packageURL)
            throw error
        }
    }

    private func removeSQLiteSidecars(for sqliteURL: URL) throws {
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: sqliteURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.removeItem(at: sidecar)
            }
        }
    }
}

private protocol HypeDocumentSQLiteMigration {
    var fromVersion: Int { get }
    var toVersion: Int { get }
    func migrate(db: SQLiteDatabase) throws
}

/// Document v2 renamed the stack-scoped repository model from
/// `spriteRepository` to `assetRepository`. SQLite packages store assets in a
/// first-class `assets` table, but several JSON payload surfaces can still
/// contain document-shaped or tool-generated JSON. This migration rewrites the
/// persisted key before any model decoding happens, then the loader records
/// documentVersion=2 in `document_values`.
private struct HypeDocumentMigrationV1ToV2: HypeDocumentSQLiteMigration {
    let fromVersion = 1
    let toVersion = 2

    func migrate(db: SQLiteDatabase) throws {
        let payloadTables = [
            "stacks", "backgrounds", "cards", "parts", "assets",
            "music_patterns", "music_tracks", "music_notes",
            "ai_context_sources", "ai_context_items", "themes",
            "paint_layers", "constraints", "sprite_areas", "scenes",
            "scene_nodes",
        ]
        for table in payloadTables {
            guard try db.tableExists(table),
                  try db.columnExists(table: table, column: "payload_json") else {
                continue
            }
            try db.execute(
                """
                UPDATE \(table)
                SET payload_json = replace(payload_json, '"spriteRepository"', '"assetRepository"')
                WHERE instr(payload_json, '"spriteRepository"') > 0
                """
            )
        }
        if try db.tableExists("document_values") {
            try db.execute(
                """
                UPDATE document_values
                SET value_json = replace(value_json, '"spriteRepository"', '"assetRepository"')
                WHERE instr(value_json, '"spriteRepository"') > 0
                """
            )
        }
    }
}

private enum SQLiteValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

private enum SQLiteOpenMode {
    case readOnly
    case readWriteCreate

    var flags: Int32 {
        switch self {
        case .readOnly:
            return SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        case .readWriteCreate:
            return SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        }
    }
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String, mode: SQLiteOpenMode) throws {
        if sqlite3_open_v2(path, &handle, mode.flags, nil) != SQLITE_OK {
            let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Could not open SQLite database."
            throw HypeSQLiteStackStoreError.sqlite(message)
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, values)
        defer { statement.finalize() }
        while true {
            let result = sqlite3_step(statement.raw)
            if result == SQLITE_DONE {
                return
            }
            if result != SQLITE_ROW {
                throw error()
            }
        }
    }

    func query(_ sql: String, _ values: [SQLiteValue] = [], row: (SQLiteStatement) throws -> Void) throws {
        let statement = try prepare(sql, values)
        defer { statement.finalize() }
        while true {
            let result = sqlite3_step(statement.raw)
            if result == SQLITE_ROW {
                try row(statement)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw error()
            }
        }
    }

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func scalarString(_ sql: String, _ values: [SQLiteValue] = []) throws -> String? {
        var value: String?
        try query(sql, values) { statement in
            if value == nil {
                value = statement.columnString(0)
            }
        }
        return value
    }

    func scalarInt(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int {
        var value = 0
        try query(sql, values) { statement in
            value = Int(statement.columnInt64(0))
        }
        return value
    }

    func countRows(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int {
        var count = 0
        try query(sql, values) { _ in count += 1 }
        return count
    }

    func columnExists(table: String, column: String) throws -> Bool {
        var exists = false
        try query("PRAGMA table_info(\(table))") { statement in
            if statement.columnString(1) == column {
                exists = true
            }
        }
        return exists
    }

    func tableExists(_ table: String) throws -> Bool {
        let count = try scalarInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            [.text(table)]
        )
        return count > 0
    }

    private func prepare(_ sql: String, _ values: [SQLiteValue]) throws -> SQLiteStatement {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw error()
        }
        let statement = SQLiteStatement(raw: pointer, database: self)
        for (offset, value) in values.enumerated() {
            try statement.bind(value, at: Int32(offset + 1))
        }
        return statement
    }

    fileprivate func error() -> HypeSQLiteStackStoreError {
        let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "SQLite error."
        return .sqlite(message)
    }
}

private final class SQLiteStatement {
    fileprivate let raw: OpaquePointer
    private unowned let database: SQLiteDatabase
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(raw: OpaquePointer, database: SQLiteDatabase) {
        self.raw = raw
        self.database = database
    }

    func finalize() {
        sqlite3_finalize(raw)
    }

    func bind(_ value: SQLiteValue, at index: Int32) throws {
        let result: Int32
        switch value {
        case .null:
            result = sqlite3_bind_null(raw, index)
        case .int(let value):
            result = sqlite3_bind_int64(raw, index, value)
        case .double(let value):
            result = sqlite3_bind_double(raw, index, value)
        case .text(let value):
            result = sqlite3_bind_text(raw, index, value, -1, Self.transient)
        case .blob(let data):
            result = data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(raw, index, buffer.baseAddress, Int32(data.count), Self.transient)
            }
        }
        guard result == SQLITE_OK else {
            throw database.error()
        }
    }

    func columnString(_ index: Int32) -> String? {
        guard let text = sqlite3_column_text(raw, index) else { return nil }
        return String(cString: text)
    }

    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(raw, index)
    }

    func columnData(_ index: Int32) -> Data? {
        guard sqlite3_column_type(raw, index) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(raw, index))
        guard count > 0 else { return Data() }
        guard let bytes = sqlite3_column_blob(raw, index) else { return nil }
        return Data(bytes: bytes, count: count)
    }
}

private extension Bool {
    var sqliteInt: Int64 { self ? 1 : 0 }
}

private extension Optional where Wrapped == UUID {
    var sqliteValue: SQLiteValue {
        switch self {
        case .some(let uuid): return .text(uuid.uuidString)
        case .none: return .null
        }
    }
}

private extension Optional where Wrapped == String {
    var sqliteValue: SQLiteValue {
        switch self {
        case .some(let value): return .text(value)
        case .none: return .null
        }
    }
}

private extension UUID {
    var sqliteValue: SQLiteValue { .text(uuidString) }
}

private extension Data {
    var hypeSQLiteSHA256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

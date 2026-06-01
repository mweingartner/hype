import Foundation

// MARK: - Asset Provenance Types

/// The origin of an asset — how it arrived in the repository.
public enum AssetOrigin: String, Codable, Sendable {
    case userImport      // From local disk, drag-drop, Finder.
    case webSearch       // Downloaded via the AI web-asset pipeline.
    case aiGenerated     // Reserved; unused in v1.
    case aiContext       // Imported from the stack's AI Context Library.
}

/// License information for an asset, sourced from the provider's metadata.
public struct AssetLicense: Codable, Sendable, Equatable {
    public var name: String        // "CC0", "CC-BY-4.0", "Pexels License", "Unknown".
    public var identifier: String  // "cc-by-4.0", "cc0-1.0", "pexels", "public-domain".
    public var url: String         // Canonical URL; may be empty.
    public var isShareable: Bool   // Informational only.

    public init(
        name: String = "",
        identifier: String = "",
        url: String = "",
        isShareable: Bool = false
    ) {
        self.name = name
        self.identifier = identifier
        self.url = url
        self.isShareable = isShareable
    }
}

/// Attribution metadata for an asset — who made it and where it came from.
public struct AssetAttribution: Codable, Sendable, Equatable {
    public var creator: String
    public var title: String
    public var sourceURL: String
    public var downloadURL: String
    public var providerName: String
    public var providerIdentifier: String
    /// When non-empty, this is the Meshy.ai task id whose output produced
    /// this asset. Used by the rigging flow to chain `input_task_id`
    /// without re-uploading the model.
    ///
    /// Default empty string. Old documents without this field decode as `""`.
    public var taskId: String

    /// Phase 4: when this asset was produced by a remesh or retexture
    /// operation, this is the Meshy task id of the SOURCE asset.
    /// Enables ancestry tracking and "regenerate from source" workflows.
    ///
    /// Default empty string. Old documents decode with `""`. (C17)
    public var parentTaskId: String

    public init(
        creator: String = "",
        title: String = "",
        sourceURL: String = "",
        downloadURL: String = "",
        providerName: String = "",
        providerIdentifier: String = "",
        taskId: String = "",
        parentTaskId: String = ""
    ) {
        self.creator = creator
        self.title = title
        self.sourceURL = sourceURL
        self.downloadURL = downloadURL
        self.providerName = providerName
        self.providerIdentifier = providerIdentifier
        self.taskId = taskId
        self.parentTaskId = parentTaskId
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case creator, title, sourceURL, downloadURL, providerName, providerIdentifier, taskId, parentTaskId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        creator             = try c.decodeIfPresent(String.self, forKey: .creator)             ?? ""
        title               = try c.decodeIfPresent(String.self, forKey: .title)               ?? ""
        sourceURL           = try c.decodeIfPresent(String.self, forKey: .sourceURL)           ?? ""
        downloadURL         = try c.decodeIfPresent(String.self, forKey: .downloadURL)         ?? ""
        providerName        = try c.decodeIfPresent(String.self, forKey: .providerName)        ?? ""
        providerIdentifier  = try c.decodeIfPresent(String.self, forKey: .providerIdentifier)  ?? ""
        // Phase 3: new field — absent in pre-Phase-3 documents; defaults to "".
        taskId              = try c.decodeIfPresent(String.self, forKey: .taskId)              ?? ""
        // Phase 4: new field — absent in pre-Phase-4 documents; defaults to "". (C17)
        parentTaskId        = try c.decodeIfPresent(String.self, forKey: .parentTaskId)        ?? ""
    }
}

/// Full provenance record for a web-search asset, stored inside `Asset`.
public struct AssetProvenance: Codable, Sendable, Equatable {
    public var origin: AssetOrigin
    /// The user's or AI's original search query. Preserved for internal
    /// provenance/debugging ONLY. It is NEVER written into Stack.script.
    public var searchQuery: String
    public var license: AssetLicense
    public var attribution: AssetAttribution
    public var importedAt: Date

    public init(
        origin: AssetOrigin,
        searchQuery: String = "",
        license: AssetLicense = AssetLicense(),
        attribution: AssetAttribution = AssetAttribution(),
        importedAt: Date = Date()
    ) {
        self.origin = origin
        self.searchQuery = searchQuery
        self.license = license
        self.attribution = attribution
        self.importedAt = importedAt
    }
}

// MARK: - Asset Kind

/// The kind of asset stored in the stack asset repository.
///
/// `tileSet` was added 2026-04-09 for first-class SpriteKit tile map
/// support. A tileSet asset is a sprite sheet that has been
/// classified for tile map use — it carries additional metadata
/// (`tileWidth`, `tileHeight`, `tileColumns`, `tileRows` on
/// `Asset`) that `Interpreter.createTileMap` and
/// `HypeToolExecutor.create_tilemap` read to pre-populate
/// `TileMapSpec.tileSetColumns`, tile size, and tile grid dimensions
/// so you don't have to restate them every time you use the asset.
/// A plain `.spriteSheet` has slices but no tile grid; a `.tileSet`
/// has a uniform grid suitable for `SKTileMapNode`.
public enum AssetKind: String, Codable, Sendable {
    case imageTexture, spriteSheet, tileSet, audioClip, videoClip, document, particlePreset, placeholderAsset
    /// A 3D model asset (GLB, USDZ, FBX, etc.) generated by Meshy.ai or
    /// imported directly. Bytes are stored inline in the document.
    case model3D

    // MARK: - Forward-compatible decoding (OQ3)
    //
    // `decodeIfPresent(AssetKind.self, …) ?? .imageTexture` handles
    // the missing-key case.  This custom init handles the "key present
    // but raw value unknown" case — older builds reading a future stack
    // that contains a kind string they don't recognise fall back to
    // `.imageTexture` rather than throwing a decode error.
    // This mirrors the `PartType.init(from:)` forward-compat pattern.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let known = AssetKind(rawValue: raw) {
            self = known
        } else {
            // Unknown future kind — graceful degradation.
            self = .imageTexture
        }
    }
}

/// High-level asset categories used by repository queries and UX filters.
public enum AssetCategory: String, CaseIterable, Codable, Sendable {
    case all
    case image
    case audio
    case video
    case model3D
    case effects
    case other

    public var displayName: String {
        switch self {
        case .all: return "All"
        case .image: return "Images"
        case .audio: return "Audio"
        case .video: return "Video"
        case .model3D: return "3D"
        case .effects: return "Effects"
        case .other: return "Other"
        }
    }
}

public extension AssetKind {
    var category: AssetCategory {
        switch self {
        case .imageTexture, .spriteSheet, .tileSet:
            return .image
        case .audioClip:
            return .audio
        case .videoClip:
            return .video
        case .model3D:
            return .model3D
        case .particlePreset:
            return .effects
        case .document:
            return .other
        case .placeholderAsset:
            return .other
        }
    }
}

/// A rectangle within a sprite sheet, used for slicing.
public struct SliceRect: Codable, Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int = 0, y: Int = 0, width: Int = 0, height: Int = 0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A named slice within a sprite sheet.
public struct AssetSlice: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var rect: SliceRect

    public init(id: UUID = UUID(), name: String = "", rect: SliceRect = SliceRect()) {
        self.id = id
        self.name = name
        self.rect = rect
    }
}

/// An animation clip composed of ordered sprite sheet slices.
public struct AnimationClip: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var frameSliceIds: [UUID]
    public var fps: Double
    public var loops: Bool

    public init(id: UUID = UUID(), name: String = "", frameSliceIds: [UUID] = [], fps: Double = 12, loops: Bool = true) {
        self.id = id
        self.name = name
        self.frameSliceIds = frameSliceIds
        self.fps = fps
        self.loops = loops
    }
}

/// Role of an embedded file that belongs to a logical repository asset.
///
/// The top-level `Asset.data` remains the primary renderable payload for simple
/// assets and compatibility with existing callers. `Asset.files` holds related
/// media for compound assets such as model + skeleton + animation + textures, or
/// legacy palette resources that produce metadata plus several preview images.
public enum AssetFileRole: String, Codable, Sendable, CaseIterable {
    case primary
    case source
    case metadata
    case preview
    case texture
    case normalMap
    case roughnessMap
    case metalnessMap
    case ambientOcclusionMap
    case skeleton
    case animation
    case material
    case palette
    case mask
    case auxiliary

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AssetFileRole(rawValue: raw) ?? .auxiliary
    }
}

/// One embedded file belonging to a logical repository asset.
public struct AssetFile: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var role: AssetFileRole
    public var mimeType: String
    public var data: Data
    public var width: Int
    public var height: Int
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        name: String = "",
        role: AssetFileRole = .auxiliary,
        mimeType: String = "application/octet-stream",
        data: Data = Data(),
        width: Int = 0,
        height: Int = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.mimeType = mimeType
        self.data = data
        self.width = width
        self.height = height
        self.tags = tags
    }
}

/// Structured metadata attached to a logical repository asset.
///
/// `value` is intentionally stored as a string so callers can preserve JSON,
/// plist text, source-manifest fragments, or concise scalar values without
/// forcing every importer to share one schema. `mimeType` identifies how the
/// value should be interpreted.
public struct AssetMetadataEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var key: String
    public var value: String
    public var mimeType: String
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        mimeType: String = "text/plain",
        tags: [String] = []
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.mimeType = mimeType
        self.tags = tags
    }
}

/// Role of an asset in an asset-compilation relationship.
public enum AssetCompilationRole: String, Codable, Sendable {
    /// Author/source asset. It may have compiled runtime outputs.
    case source
    /// Runtime asset generated by a compiler/converter from a source asset.
    case runtime
    /// Intermediate product that can itself feed another compiler.
    case intermediate

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AssetCompilationRole(rawValue: raw) ?? .runtime
    }
}

/// Stable link between authoring assets and compiler-generated runtime assets.
///
/// This is intentionally converter-neutral. A future compiler can use it for
/// GLB -> USDZ, layered texture -> flattened runtime texture, palette ->
/// generated previews, sprite sheet -> packed atlas, or any other asset
/// conversion without adding one-off fields to `Asset`.
public struct AssetCompilation: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var role: AssetCompilationRole
    public var sourceAssetRef: AssetRef?
    public var runtimeAssetRefs: [AssetRef]
    public var operation: String
    public var compilerIdentifier: String
    public var compilerVersion: String
    public var sourceFingerprint: String
    public var optionsFingerprint: String
    public var compiledAt: Date?
    public var diagnostics: [String]

    public init(
        id: UUID = UUID(),
        role: AssetCompilationRole = .runtime,
        sourceAssetRef: AssetRef? = nil,
        runtimeAssetRefs: [AssetRef] = [],
        operation: String = "",
        compilerIdentifier: String = "",
        compilerVersion: String = "",
        sourceFingerprint: String = "",
        optionsFingerprint: String = "",
        compiledAt: Date? = nil,
        diagnostics: [String] = []
    ) {
        self.id = id
        self.role = role
        self.sourceAssetRef = sourceAssetRef
        self.runtimeAssetRefs = runtimeAssetRefs
        self.operation = operation
        self.compilerIdentifier = compilerIdentifier
        self.compilerVersion = compilerVersion
        self.sourceFingerprint = sourceFingerprint
        self.optionsFingerprint = optionsFingerprint
        self.compiledAt = compiledAt
        self.diagnostics = diagnostics
    }
}

/// A single stack asset with raw data and optional type-specific metadata.
///
/// Tile set metadata (`tileWidth`, `tileHeight`, `tileColumns`,
/// `tileRows`) is only meaningful when `kind == .tileSet`. For every
/// other asset kind these fields stay at zero and are ignored. The
/// decoder defaults them to zero for backward compatibility with
/// `.hype` files saved before 2026-04-09, so loading an old document
/// never fails and older assets behave exactly as they did before.
public struct Asset: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AssetKind
    public var mimeType: String
    public var data: Data
    public var width: Int
    public var height: Int
    public var tags: [String]
    public var slices: [AssetSlice]
    public var animationClips: [AnimationClip]
    /// Related embedded media files that belong to this logical asset.
    public var files: [AssetFile]
    /// Structured metadata records attached to this logical asset.
    public var metadata: [AssetMetadataEntry]
    /// Optional compile/link metadata for source/runtime asset conversion.
    public var compilation: AssetCompilation?

    // MARK: - Tile set metadata (kind == .tileSet)

    /// Width of a single tile in pixels. Only meaningful for
    /// `.tileSet` assets. `Interpreter.createTileMap` uses this to
    /// pre-populate `TileMapSpec.tileWidth` when a tilemap is built
    /// from this asset.
    public var tileWidth: Int
    /// Height of a single tile in pixels. See `tileWidth`.
    public var tileHeight: Int
    /// Number of tile columns in the sprite sheet grid. This is
    /// copied into `TileMapSpec.tileSetColumns` when a tilemap is
    /// built from the asset — SceneBridge uses it to slice the
    /// texture into individual tile groups for `SKTileMapNode`.
    /// Before this field existed, `tileSetColumns` defaulted to 1
    /// and multi-column tilesets rendered as a single vertical
    /// strip.
    public var tileColumns: Int
    /// Number of tile rows in the sprite sheet grid. Used to
    /// validate that tileData indices fall within the tile set's
    /// addressable range when setting per-cell tiles.
    public var tileRows: Int

    // MARK: - Provenance (web-asset search)

    /// Provenance record, present only for assets sourced from the web-asset
    /// search pipeline. Nil for all assets imported from local disk before
    /// the web-asset feature was introduced (backward-compatible decode).
    public var provenance: AssetProvenance?

    // MARK: - Rigging / animation metadata (Phase 3)

    /// True when this 3D model has been auto-rigged by Meshy's rigging
    /// pipeline. Only meaningful when `kind == .model3D`.
    ///
    /// Default `false`. Pre-Phase-3 documents decode with `false`.
    public var isRigged: Bool

    /// When set, identifies the Meshy animation action id baked into
    /// this asset. Only meaningful when `kind == .model3D && isRigged`.
    ///
    /// `nil` on:
    ///   - Non-rigged models.
    ///   - Rigged models without a baked custom animation.
    ///   - Basic walk/run clips (those carry tag "meshy-basic-walking" /
    ///     "meshy-basic-running" instead of a numeric action id).
    ///
    /// Default `nil`. Pre-Phase-3 documents decode with `nil`.
    public var animationActionId: Int?

    public init(
        id: UUID = UUID(),
        name: String = "",
        kind: AssetKind = .imageTexture,
        mimeType: String = "image/png",
        data: Data = Data(),
        width: Int = 0,
        height: Int = 0,
        tags: [String] = [],
        slices: [AssetSlice] = [],
        animationClips: [AnimationClip] = [],
        files: [AssetFile] = [],
        metadata: [AssetMetadataEntry] = [],
        compilation: AssetCompilation? = nil,
        tileWidth: Int = 0,
        tileHeight: Int = 0,
        tileColumns: Int = 0,
        tileRows: Int = 0,
        provenance: AssetProvenance? = nil,
        isRigged: Bool = false,
        animationActionId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.mimeType = mimeType
        self.data = data
        self.width = width
        self.height = height
        self.tags = tags
        self.slices = slices
        self.animationClips = animationClips
        self.files = files
        self.metadata = metadata
        self.compilation = compilation
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.tileColumns = tileColumns
        self.tileRows = tileRows
        self.provenance = provenance
        self.isRigged = isRigged
        self.animationActionId = animationActionId
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, mimeType, data, width, height, tags, slices, animationClips
        case files, metadata, compilation
        case tileWidth, tileHeight, tileColumns, tileRows
        case provenance
        // Phase 3 fields
        case isRigged, animationActionId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(AssetKind.self, forKey: .kind) ?? .imageTexture
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "image/png"
        data = try container.decodeIfPresent(Data.self, forKey: .data) ?? Data()
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        slices = try container.decodeIfPresent([AssetSlice].self, forKey: .slices) ?? []
        animationClips = try container.decodeIfPresent([AnimationClip].self, forKey: .animationClips) ?? []
        files = try container.decodeIfPresent([AssetFile].self, forKey: .files) ?? []
        metadata = try container.decodeIfPresent([AssetMetadataEntry].self, forKey: .metadata) ?? []
        compilation = try container.decodeIfPresent(AssetCompilation.self, forKey: .compilation)
        // Tile set metadata: decodeIfPresent so old documents load
        // clean. New assets without tile metadata default to zero,
        // which is the "not a tile set" sentinel checked everywhere.
        tileWidth = try container.decodeIfPresent(Int.self, forKey: .tileWidth) ?? 0
        tileHeight = try container.decodeIfPresent(Int.self, forKey: .tileHeight) ?? 0
        tileColumns = try container.decodeIfPresent(Int.self, forKey: .tileColumns) ?? 0
        tileRows = try container.decodeIfPresent(Int.self, forKey: .tileRows) ?? 0
        // Provenance: nil for all pre-web-asset documents (backward-compatible).
        provenance = try container.decodeIfPresent(AssetProvenance.self, forKey: .provenance)

        // Phase 3: rigging / animation metadata. Old documents without
        // these fields decode with safe defaults (false / nil).
        let decodedIsRigged = try container.decodeIfPresent(Bool.self, forKey: .isRigged) ?? false
        let decodedActionId = try container.decodeIfPresent(Int.self, forKey: .animationActionId)

        // Decode-time invariant: if animationActionId is set, isRigged must be true.
        // Guards against hand-edited documents with inconsistent flags.
        if decodedActionId != nil && !decodedIsRigged {
            isRigged = true
        } else {
            isRigged = decodedIsRigged
        }
        animationActionId = decodedActionId

        // Security (M1): enforce a 50 MB cap on model3D assets at decode time.
        // A malicious .hype file could embed a very large model3D asset — this
        // cap prevents it from being fully deserialised into memory.
        if kind == .model3D && totalEmbeddedByteCount > Self.maxModel3DEmbeddedBytes {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "model3D asset exceeds 50 MB cap"
            ))
        }
    }

    public static let maxModel3DEmbeddedBytes = 50 * 1024 * 1024

    /// Total embedded byte count for the primary payload plus related files.
    public var totalEmbeddedByteCount: Int {
        data.count + files.reduce(0) { $0 + $1.data.count }
    }

    /// The primary payload as a file-like value. Useful for code that wants to
    /// inspect compound and simple assets through the same shape.
    public var primaryFile: AssetFile {
        AssetFile(
            id: id,
            name: name,
            role: .primary,
            mimeType: mimeType,
            data: data,
            width: width,
            height: height,
            tags: tags
        )
    }

    /// The primary payload followed by related embedded files.
    public var allFiles: [AssetFile] {
        [primaryFile] + files
    }

    /// True when this asset is a tileset with enough metadata to
    /// build a `TileMapSpec` from. Used as a gate by create-tilemap
    /// paths that only auto-populate columns/rows when the metadata
    /// is actually present.
    public var isTileSet: Bool {
        kind == .tileSet && tileWidth > 0 && tileHeight > 0 && tileColumns > 0 && tileRows > 0
    }

    fileprivate var searchableText: String {
        var fields: [String] = [
            id.uuidString,
            name,
            kind.rawValue,
            kind.category.displayName,
            mimeType,
            "\(width)x\(height)",
            "\(data.count)"
        ]

        fields.append(contentsOf: tags)
        fields.append(contentsOf: slices.map(\.name))
        fields.append(contentsOf: animationClips.map(\.name))
        fields.append(contentsOf: files.flatMap { file in
            [file.name, file.role.rawValue, file.mimeType] + file.tags
        })
        fields.append(contentsOf: metadata.flatMap { entry in
            [entry.key, entry.value, entry.mimeType] + entry.tags
        })

        if isTileSet {
            fields.append("tileset")
            fields.append("\(tileColumns)x\(tileRows)")
            fields.append("\(tileWidth)x\(tileHeight)")
        }

        if let provenance {
            fields.append(provenance.origin.rawValue)
            fields.append(provenance.searchQuery)
            fields.append(provenance.license.name)
            fields.append(provenance.license.identifier)
            fields.append(provenance.attribution.creator)
            fields.append(provenance.attribution.title)
            fields.append(provenance.attribution.providerName)
            fields.append(provenance.attribution.providerIdentifier)
            fields.append(provenance.attribution.sourceURL)
            fields.append(provenance.attribution.taskId)
            fields.append(provenance.attribution.parentTaskId)
        }

        if isRigged {
            fields.append("rigged")
        }
        if let animationActionId {
            fields.append("animation \(animationActionId)")
        }

        return fields.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// A collection of stack assets for a Hype document.
public struct AssetRepository: Codable, Sendable {
    public var assets: [Asset]

    public init(assets: [Asset] = []) {
        self.assets = assets
    }

    /// Find an asset by its unique identifier.
    public func asset(byId id: UUID) -> Asset? {
        assets.first { $0.id == id }
    }

    /// Find an asset by name.
    ///
    /// If a document has duplicate asset names, prefer the newest matching
    /// asset. AI authoring flows often regenerate an asset with the same name;
    /// resolving to the latest match avoids stale tiles or sprites being used
    /// after a repair pass.
    public func asset(byName name: String) -> Asset? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return assets.reversed().first { $0.name.lowercased() == needle }
    }

    /// Find the newest matching asset by name and kind.
    public func asset(byName name: String, kind: AssetKind) -> Asset? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return assets.reversed().first { $0.name.lowercased() == needle && $0.kind == kind }
    }

    /// Find the newest asset by classic HyperCard media name.
    ///
    /// Loose-media imports preserve a normalized `lookup_key` and
    /// `classic_name` in asset metadata. Compatibility commands such as
    /// `playQT "Intro Wind Mov"` use those classic names rather than modern
    /// filenames, so repository lookup needs to match both direct asset names
    /// and imported metadata.
    public func asset(byClassicMediaName name: String, kind: AssetKind? = nil) -> Asset? {
        let key = Self.classicMediaLookupKey(name)
        guard !key.isEmpty else { return nil }
        return assets.reversed().first { asset in
            if let kind, asset.kind != kind { return false }
            if Self.classicMediaLookupKey(asset.name) == key { return true }
            return asset.metadata.contains { entry in
                let metadataKey = entry.key.lowercased()
                guard metadataKey == "lookup_key" || metadataKey == "classic_name" else { return false }
                return Self.classicMediaLookupKey(entry.value) == key
            }
        }
    }

    /// Return all assets of one exact kind in document order.
    public func assets(ofKind kind: AssetKind) -> [Asset] {
        assets.filter { $0.kind == kind }
    }

    /// Return all assets whose kind is in `kinds`, preserving document order.
    public func assets(ofKinds kinds: Set<AssetKind>) -> [Asset] {
        assets.filter { kinds.contains($0.kind) }
    }

    /// Return all assets in a high-level category, preserving document order.
    public func assets(in category: AssetCategory) -> [Asset] {
        guard category != .all else { return assets }
        return assets.filter { $0.kind.category == category }
    }

    /// Search assets by user-visible repository text, optionally limited to one
    /// high-level category. This intentionally searches descriptive metadata as
    /// well as names so the Asset Repository browser can find imported/web/AI
    /// assets by tags, kind, MIME type, source, attribution, or provenance.
    public func searchAssets(named query: String, category: AssetCategory = .all) -> [Asset] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
        let scoped = assets(in: category)
        guard !terms.isEmpty else { return scoped }
        return scoped.filter { asset in
            let haystack = asset.searchableText.lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// Create an AssetRef pointing to the given asset.
    public func assetRef(for asset: Asset) -> AssetRef {
        AssetRef(id: asset.id, name: asset.name, mimeType: asset.mimeType)
    }

    public static func classicMediaLookupKey(_ name: String) -> String {
        var stem = classicMediaLookupStem(name)
        for suffix in ["-modern-audio", "-modern-av", "-modern"] where stem.lowercased().hasSuffix(suffix) {
            stem.removeLast(suffix.count)
        }
        return stem
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[:/\\\s_\-\.]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func classicMediaLookupStem(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let separatorCount = trimmed.filter { $0 == ":" || $0 == "/" }.count
        let candidate: String
        if separatorCount >= 2 {
            candidate = trimmed
                .split(whereSeparator: { $0 == ":" || $0 == "/" })
                .last
                .map(String.init) ?? trimmed
        } else {
            candidate = trimmed
        }
        let nsName = candidate as NSString
        let stem = nsName.deletingPathExtension
        return stem.isEmpty ? candidate : stem
    }

    /// Runtime assets compiled from the given source asset.
    public func runtimeAssets(compiledFrom sourceAssetId: UUID) -> [Asset] {
        assets.filter { asset in
            asset.compilation?.sourceAssetRef?.id == sourceAssetId
        }
    }

    /// Source asset for the given compiled runtime asset, if both link and
    /// source are present in the repository.
    public func sourceAsset(forRuntimeAssetId runtimeAssetId: UUID) -> Asset? {
        guard let runtime = asset(byId: runtimeAssetId),
              let sourceId = runtime.compilation?.sourceAssetRef?.id else {
            return nil
        }
        return asset(byId: sourceId)
    }

    /// Attach a bidirectional source/runtime compilation link.
    ///
    /// The runtime asset receives `sourceAssetRef`. The source asset records the
    /// runtime output in `runtimeAssetRefs`, preserving any existing outputs for
    /// other compiler options or target formats.
    public mutating func linkCompiledAsset(
        sourceAssetId: UUID,
        runtimeAssetId: UUID,
        operation: String,
        compilerIdentifier: String,
        compilerVersion: String = "",
        sourceFingerprint: String = "",
        optionsFingerprint: String = "",
        compiledAt: Date = Date(),
        diagnostics: [String] = []
    ) {
        guard let sourceIndex = assets.firstIndex(where: { $0.id == sourceAssetId }),
              let runtimeIndex = assets.firstIndex(where: { $0.id == runtimeAssetId }) else {
            return
        }

        let sourceRef = assetRef(for: assets[sourceIndex])
        let runtimeRef = assetRef(for: assets[runtimeIndex])
        let compileId = assets[runtimeIndex].compilation?.id ??
            assets[sourceIndex].compilation?.id ??
            UUID()

        assets[runtimeIndex].compilation = AssetCompilation(
            id: compileId,
            role: .runtime,
            sourceAssetRef: sourceRef,
            runtimeAssetRefs: [],
            operation: operation,
            compilerIdentifier: compilerIdentifier,
            compilerVersion: compilerVersion,
            sourceFingerprint: sourceFingerprint,
            optionsFingerprint: optionsFingerprint,
            compiledAt: compiledAt,
            diagnostics: diagnostics
        )

        var runtimeRefs = assets[sourceIndex].compilation?.runtimeAssetRefs ?? []
        if !runtimeRefs.contains(where: { $0.id == runtimeRef.id }) {
            runtimeRefs.append(runtimeRef)
        }
        assets[sourceIndex].compilation = AssetCompilation(
            id: compileId,
            role: .source,
            sourceAssetRef: nil,
            runtimeAssetRefs: runtimeRefs,
            operation: operation,
            compilerIdentifier: compilerIdentifier,
            compilerVersion: compilerVersion,
            sourceFingerprint: sourceFingerprint,
            optionsFingerprint: optionsFingerprint,
            compiledAt: compiledAt,
            diagnostics: diagnostics
        )
    }

    /// Add an asset to the repository.
    public mutating func addAsset(_ asset: Asset) {
        assets.append(asset)
    }

    /// Remove an asset by its unique identifier.
    public mutating func removeAsset(id: UUID) {
        assets.removeAll { $0.id == id }
    }

    /// Update an asset in place by its unique identifier.
    public mutating func updateAsset(id: UUID, _ transform: (inout Asset) -> Void) {
        if let index = assets.firstIndex(where: { $0.id == id }) {
            transform(&assets[index])
        }
    }
}

import Foundation

// MARK: - Asset Provenance Types

/// The origin of a sprite asset — how it arrived in the repository.
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

/// Full provenance record for a web-search asset, stored inside `SpriteAsset`.
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

/// The kind of asset stored in the sprite repository.
///
/// `tileSet` was added 2026-04-09 for first-class SpriteKit tile map
/// support. A tileSet asset is a sprite sheet that has been
/// classified for tile map use — it carries additional metadata
/// (`tileWidth`, `tileHeight`, `tileColumns`, `tileRows` on
/// `SpriteAsset`) that `Interpreter.createTileMap` and
/// `HypeToolExecutor.create_tilemap` read to pre-populate
/// `TileMapSpec.tileSetColumns`, tile size, and tile grid dimensions
/// so you don't have to restate them every time you use the asset.
/// A plain `.spriteSheet` has slices but no tile grid; a `.tileSet`
/// has a uniform grid suitable for `SKTileMapNode`.
public enum AssetKind: String, Codable, Sendable {
    case imageTexture, spriteSheet, tileSet, audioClip, videoClip, particlePreset, placeholderAsset
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

/// A single sprite asset with raw image data and optional slicing/animation metadata.
///
/// Tile set metadata (`tileWidth`, `tileHeight`, `tileColumns`,
/// `tileRows`) is only meaningful when `kind == .tileSet`. For every
/// other asset kind these fields stay at zero and are ignored. The
/// decoder defaults them to zero for backward compatibility with
/// `.hype` files saved before 2026-04-09, so loading an old document
/// never fails and older assets behave exactly as they did before.
public struct SpriteAsset: Identifiable, Codable, Sendable {
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
        if kind == .model3D && data.count > 50 * 1024 * 1024 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "model3D asset exceeds 50 MB cap"
            ))
        }
    }

    /// True when this asset is a tileset with enough metadata to
    /// build a `TileMapSpec` from. Used as a gate by create-tilemap
    /// paths that only auto-populate columns/rows when the metadata
    /// is actually present.
    public var isTileSet: Bool {
        kind == .tileSet && tileWidth > 0 && tileHeight > 0 && tileColumns > 0 && tileRows > 0
    }
}

/// A collection of sprite assets for a Hype document.
public struct SpriteRepository: Codable, Sendable {
    public var assets: [SpriteAsset]

    public init(assets: [SpriteAsset] = []) {
        self.assets = assets
    }

    /// Find an asset by its unique identifier.
    public func asset(byId id: UUID) -> SpriteAsset? {
        assets.first { $0.id == id }
    }

    /// Find an asset by name.
    ///
    /// If a document has duplicate asset names, prefer the newest matching
    /// asset. AI authoring flows often regenerate an asset with the same name;
    /// resolving to the latest match avoids stale tiles or sprites being used
    /// after a repair pass.
    public func asset(byName name: String) -> SpriteAsset? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return assets.reversed().first { $0.name.lowercased() == needle }
    }

    /// Create an AssetRef pointing to the given asset.
    public func assetRef(for asset: SpriteAsset) -> AssetRef {
        AssetRef(id: asset.id, name: asset.name, mimeType: asset.mimeType)
    }

    /// Add an asset to the repository.
    public mutating func addAsset(_ asset: SpriteAsset) {
        assets.append(asset)
    }

    /// Remove an asset by its unique identifier.
    public mutating func removeAsset(id: UUID) {
        assets.removeAll { $0.id == id }
    }

    /// Update an asset in place by its unique identifier.
    public mutating func updateAsset(id: UUID, _ transform: (inout SpriteAsset) -> Void) {
        if let index = assets.firstIndex(where: { $0.id == id }) {
            transform(&assets[index])
        }
    }
}

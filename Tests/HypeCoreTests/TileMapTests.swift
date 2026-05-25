import Testing
import Foundation
@testable import HypeCore

/// Regression tests for first-class SpriteKit tile map support.
///
/// Background: before 2026-04-09 the Hype repository had placeholder
/// tile map plumbing — `TileMapSpec.tileSetColumns` existed on the
/// model, but no code path populated it. Users importing a sprite
/// sheet and referencing it from `create tilemap "X" with tileset "Y"`
/// got a tile map whose sprite sheet was sliced as a single vertical
/// strip (because the renderer fell back to `tileSetColumns = 1`).
///
/// The fix was twofold:
///   1. `Asset` gained a `.tileSet` AssetKind and tile
///      metadata fields (`tileWidth`, `tileHeight`, `tileColumns`,
///      `tileRows`) so an image can be classified once and reused.
///   2. `Interpreter.createTileMap` and `HypeToolExecutor.create_tilemap`
///      now read that metadata and populate `TileMapSpec.tileSetColumns`,
///      tile width, and tile height automatically.
///
/// These tests pin both layers — model serialization (including
/// backward-compat for old documents that pre-date the new fields)
/// and the wire-up in the interpreter + AI tool paths.
@Suite("Tile map support", .serialized)
struct TileMapTests {

    // MARK: - Asset model

    @Test("Asset defaults tile metadata to zero")
    func tileMetadataDefaultsZero() {
        let asset = Asset(name: "img", kind: .imageTexture)
        #expect(asset.tileWidth == 0)
        #expect(asset.tileHeight == 0)
        #expect(asset.tileColumns == 0)
        #expect(asset.tileRows == 0)
        #expect(asset.isTileSet == false)
    }

    @Test("Asset isTileSet requires kind == .tileSet AND non-zero metadata")
    func isTileSetRequiresFullMetadata() {
        // kind alone is not enough — the renderer needs the grid
        // dimensions to slice the sheet.
        var asset = Asset(name: "x", kind: .tileSet)
        #expect(asset.isTileSet == false, "kind=.tileSet with zero metadata should not count as classified")

        asset.tileWidth = 32
        asset.tileHeight = 32
        #expect(asset.isTileSet == false, "tile width/height alone without columns/rows is incomplete")

        asset.tileColumns = 4
        asset.tileRows = 4
        #expect(asset.isTileSet == true, "kind=.tileSet with full metadata should report as classified")
    }

    @Test("Asset encodes and decodes tile metadata round-trip")
    func tileMetadataRoundTrip() throws {
        let original = Asset(
            name: "grass_tiles",
            kind: .tileSet,
            width: 256,
            height: 64,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 8,
            tileRows: 2
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Asset.self, from: encoded)
        #expect(decoded.kind == .tileSet)
        #expect(decoded.tileWidth == 32)
        #expect(decoded.tileHeight == 32)
        #expect(decoded.tileColumns == 8)
        #expect(decoded.tileRows == 2)
        #expect(decoded.isTileSet == true)
    }

    @Test("Asset decoder is backward-compatible with pre-tile-metadata documents")
    func decoderBackwardCompat() throws {
        // Minimal JSON shape from an older document that never had
        // tileWidth/tileHeight/tileColumns/tileRows fields. The
        // decoder must not throw — it has to default the missing
        // fields to zero.
        let legacyJson = """
        {
            "id": "\(UUID().uuidString)",
            "name": "old_image",
            "kind": "imageTexture",
            "mimeType": "image/png",
            "data": "",
            "width": 128,
            "height": 128,
            "tags": [],
            "slices": [],
            "animationClips": []
        }
        """
        let data = legacyJson.data(using: .utf8)!
        let asset = try JSONDecoder().decode(Asset.self, from: data)
        #expect(asset.name == "old_image")
        #expect(asset.width == 128)
        #expect(asset.tileWidth == 0)
        #expect(asset.tileHeight == 0)
        #expect(asset.tileColumns == 0)
        #expect(asset.tileRows == 0)
        #expect(asset.isTileSet == false)
    }

    // MARK: - Filename heuristic

    @Test("filenameLooksLikeTileset matches common conventions")
    func filenameHeuristic() {
        // Positive cases
        #expect(HypeToolExecutor.filenameLooksLikeTileset("grass_tileset") == true)
        #expect(HypeToolExecutor.filenameLooksLikeTileset("dungeon-tiles") == true)
        #expect(HypeToolExecutor.filenameLooksLikeTileset("level1_tilemap") == true)
        #expect(HypeToolExecutor.filenameLooksLikeTileset("Tileset Forest") == true)
        #expect(HypeToolExecutor.filenameLooksLikeTileset("TileSheet 01") == true)
        // Negative cases — should NOT misclassify a regular sprite
        #expect(HypeToolExecutor.filenameLooksLikeTileset("player") == false)
        #expect(HypeToolExecutor.filenameLooksLikeTileset("enemy_walk") == false)
        #expect(HypeToolExecutor.filenameLooksLikeTileset("explosion") == false)
        // "tile" alone is too loose — shouldn't match
        #expect(HypeToolExecutor.filenameLooksLikeTileset("tile") == false)
    }

    // MARK: - classify_asset_as_tileset AI tool

    @Test("classify_asset_as_tileset sets kind and tile metadata")
    func classifyAssetTool() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let asset = Asset(
            name: "grass_sheet",
            kind: .imageTexture,
            width: 256,
            height: 64
        )
        doc.assetRepository.addAsset(asset)
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "classify_asset_as_tileset",
            arguments: [
                "asset_name": "grass_sheet",
                "tile_width": "32",
                "tile_height": "32",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.contains("Classified"))
        let reloaded = doc.assetRepository.asset(byName: "grass_sheet")!
        #expect(reloaded.kind == .tileSet)
        #expect(reloaded.tileWidth == 32)
        #expect(reloaded.tileHeight == 32)
        // Auto-derived from 256 wide / 32 = 8 cols, 64 tall / 32 = 2 rows
        #expect(reloaded.tileColumns == 8)
        #expect(reloaded.tileRows == 2)
        #expect(reloaded.isTileSet == true)
    }

    @Test("classify_asset_as_tileset treats generated single tile art as one tile")
    func classifyGeneratedSingleTileArtAsOneTile() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let asset = Asset(
            name: "maze_tile_wall",
            kind: .imageTexture,
            width: 1024,
            height: 1024,
            tags: ["ai-generated"],
            provenance: AssetProvenance(
                origin: .aiGenerated,
                searchQuery: "Top-down maze wall tile for a Pac-Man style maze, seamless 32x32 tile appearance"
            )
        )
        doc.assetRepository.addAsset(asset)
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()

        let result = await executor.execute(
            toolName: "classify_asset_as_tileset",
            arguments: [
                "asset_name": "maze_tile_wall",
                "tile_width": "32",
                "tile_height": "32",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.contains("AI-generated single tile"))
        let reloaded = doc.assetRepository.asset(byName: "maze_tile_wall")!
        #expect(reloaded.kind == .tileSet)
        #expect(reloaded.tileWidth == 32)
        #expect(reloaded.tileHeight == 32)
        #expect(reloaded.tileColumns == 1)
        #expect(reloaded.tileRows == 1)
    }

    @Test("classify_asset_as_tileset honors explicit tile_columns and tile_rows")
    func classifyAssetExplicitGrid() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        doc.assetRepository.addAsset(Asset(
            name: "weird_sheet",
            width: 128,
            height: 64
        ))
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "classify_asset_as_tileset",
            arguments: [
                "asset_name": "weird_sheet",
                "tile_width": "32",
                "tile_height": "32",
                "tile_columns": "3",
                "tile_rows": "1",
            ],
            document: &doc,
            currentCardId: cardId
        )
        let reloaded = doc.assetRepository.asset(byName: "weird_sheet")!
        #expect(reloaded.tileColumns == 3, "explicit tile_columns must override auto-derivation")
        #expect(reloaded.tileRows == 1)
    }

    @Test("classify_asset_as_tileset rejects tile_width = 0")
    func classifyAssetRejectsZeroSize() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        doc.assetRepository.addAsset(Asset(name: "x", width: 32, height: 32))
        let cardId = doc.cards[0].id
        let result = await HypeToolExecutor().execute(
            toolName: "classify_asset_as_tileset",
            arguments: ["asset_name": "x", "tile_width": "0", "tile_height": "32"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.lowercased().contains("required"))
    }

    // MARK: - create_tilemap + asset metadata wire-up

    @Test("create_tilemap tool pulls tileSetColumns from a classified asset")
    func createTilemapPullsColumns() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id

        // Add a classified tileset asset to the repository.
        doc.assetRepository.addAsset(Asset(
            name: "grass",
            kind: .tileSet,
            width: 256,
            height: 64,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 8,
            tileRows: 2
        ))
        // Create a sprite area for the tilemap to live in.
        var area = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "game",
            left: 0, top: 0, width: 800, height: 600
        )
        area.sceneSpec = SceneSpec(name: "main", size: SizeSpec(width: 800, height: 600)).toJSON()
        doc.addPart(area)

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_tilemap",
            arguments: [
                "sprite_area_name": "game",
                "tilemap_name": "ground",
                "columns": "20",
                "rows": "15",
                "tileset_asset": "grass",
                // Deliberately no tile_size — must be picked up from asset
            ],
            document: &doc,
            currentCardId: cardId
        )

        let areaPart = doc.parts.first { $0.name == "game" }!
        let spec = SceneSpec.fromJSON(areaPart.sceneSpec)!
        let tmNode = spec.nodes.first { $0.nodeType == .tileMap && $0.name == "ground" }!
        let tmSpec = tmNode.tileMapSpec!

        #expect(tmSpec.columns == 20)
        #expect(tmSpec.rows == 15)
        // THESE are the assertions that would have failed before
        // the fix — with a non-classified asset or missing
        // wire-up, tileSetColumns stayed at 1 and tile size at
        // the default of 32 regardless of the actual sheet.
        #expect(tmSpec.tileSetColumns == 8,
                "tileSetColumns must be copied from the classified asset or multi-column tilesets render wrong")
        #expect(tmSpec.tileWidth == 32)
        #expect(tmSpec.tileHeight == 32)
        #expect(tmSpec.tileSetAssetRef?.name == "grass")
    }

    @Test("create_tilemap tool expands scene design size to fit the map grid")
    func createTilemapExpandsSceneSizeToMap() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "maze_tiles",
            kind: .tileSet,
            width: 1024,
            height: 1024,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 32,
            tileRows: 32
        ))
        var area = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "pacmanArea",
            left: 0,
            top: 0,
            width: 608,
            height: 449
        )
        area.setSpriteAreaSpec(
            SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 608, height: 449))
        )
        doc.addPart(area)

        let result = await HypeToolExecutor().execute(
            toolName: "create_tilemap",
            arguments: [
                "sprite_area_name": "pacmanArea",
                "tilemap_name": "maze",
                "columns": "24",
                "rows": "17",
                "tileset_asset": "maze_tiles",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let areaPart = doc.parts.first { $0.name == "pacmanArea" }!
        let areaSpec = areaPart.spriteAreaSpecModel!
        #expect(result.contains("expanded scene"))
        #expect(areaSpec.designSize.width == 768)
        #expect(areaSpec.designSize.height == 544)
        #expect(areaSpec.activeScene?.size.width == 768)
        #expect(areaSpec.activeScene?.size.height == 544)
    }

    @Test("add_sprite_to_scene defaults oversized generated assets to game-sized sprites")
    func addSpriteDefaultsGeneratedAssetToGameSize() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "power_pellet",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            width: 1024,
            height: 1024
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game", left: 0, top: 0, width: 800, height: 600)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 800, height: 600)))
        doc.addPart(area)

        _ = await HypeToolExecutor().execute(
            toolName: "add_sprite_to_scene",
            arguments: [
                "sprite_area_name": "game",
                "sprite_name": "powerPellet1",
                "asset_name": "power_pellet",
                "x": "64",
                "y": "96",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let areaPart = doc.parts.first { $0.name == "game" }!
        let node = areaPart.activeSceneSpec?.node(named: "powerPellet1")
        #expect(node?.size?.width == 64)
        #expect(node?.size?.height == 64)
    }

    @Test("add_sprite_to_scene without asset creates a visible placeholder sprite")
    func addSpriteWithoutAssetDefaultsToVisiblePlaceholder() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game", left: 0, top: 0, width: 800, height: 600)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 800, height: 600)))
        doc.addPart(area)

        _ = await HypeToolExecutor().execute(
            toolName: "add_sprite_to_scene",
            arguments: [
                "sprite_area_name": "game",
                "sprite_name": "sprite_1",
                "x": "50",
                "y": "200",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let areaPart = doc.parts.first { $0.name == "game" }!
        let node = areaPart.activeSceneSpec?.node(named: "sprite_1")
        #expect(node?.size?.width == 48)
        #expect(node?.size?.height == 48)
        #expect(node?.shapeSpec?.fillColor == "#4AA8FF")
    }

    @Test("set_node_property accepts loc alias used by AI game authoring")
    func setNodePropertyAcceptsLocAlias() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game", left: 0, top: 0, width: 800, height: 600)
        var scene = SceneSpec(name: "main", size: SizeSpec(width: 800, height: 600))
        scene.nodes.append(HypeNodeSpec(name: "player", nodeType: .sprite))
        area.setSpriteAreaSpec(SpriteAreaSpec(scene: scene, fallbackSize: scene.size))
        doc.addPart(area)

        _ = await HypeToolExecutor().execute(
            toolName: "set_node_property",
            arguments: [
                "sprite_area_name": "game",
                "node_name": "player",
                "property": "loc",
                "value": "96,480",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let areaPart = doc.parts.first { $0.name == "game" }!
        let player = areaPart.activeSceneSpec?.node(named: "player")
        #expect(player?.position.x == 96)
        #expect(player?.position.y == 480)
    }

    @Test("create_tilemap tool reports unclassified tileset as a warning")
    func createTilemapWarnsOnUnclassified() async {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "raw_sheet",
            kind: .imageTexture,
            width: 256,
            height: 64
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game",
                        left: 0, top: 0, width: 800, height: 600)
        area.sceneSpec = SceneSpec().toJSON()
        doc.addPart(area)

        let result = await HypeToolExecutor().execute(
            toolName: "create_tilemap",
            arguments: [
                "sprite_area_name": "game",
                "tilemap_name": "ground",
                "columns": "20",
                "rows": "15",
                "tileset_asset": "raw_sheet",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.lowercased().contains("not classified") || result.contains("NOT CLASSIFIED"),
                "result should warn the AI that the asset needs classification")
    }

    // MARK: - set_tile / fill_tilemap / get_tilemap_info

    private func docWithEmptyTileMap() async -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "ts",
            kind: .tileSet,
            width: 128,
            height: 32,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 4,
            tileRows: 1
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game",
                        left: 0, top: 0, width: 800, height: 600)
        area.sceneSpec = SceneSpec().toJSON()
        doc.addPart(area)
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_tilemap",
            arguments: [
                "sprite_area_name": "game",
                "tilemap_name": "level",
                "columns": "5",
                "rows": "3",
                "tileset_asset": "ts",
            ],
            document: &doc,
            currentCardId: cardId
        )
        return (doc, cardId)
    }

    @Test("set_tile tool writes a single cell")
    func setTileWritesOneCell() async {
        var (doc, cardId) = await docWithEmptyTileMap()
        let result = await HypeToolExecutor().execute(
            toolName: "set_tile",
            arguments: [
                "sprite_area_name": "game",
                "tilemap_name": "level",
                "column": "2",
                "row": "1",
                "tile_index": "3",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.contains("Set tile"))
        let area = doc.parts.first { $0.name == "game" }!
        let spec = SceneSpec.fromJSON(area.sceneSpec)!
        let node = spec.nodes.first { $0.name == "level" }!
        let tm = node.tileMapSpec!
        #expect(tm.tileData[1][2] == 3)
        // Other cells should remain -1.
        #expect(tm.tileData[0][0] == -1)
    }

    @Test("set_tile rejects out-of-bounds column/row")
    func setTileRejectsOOB() async {
        var (doc, cardId) = await docWithEmptyTileMap()
        let result = await HypeToolExecutor().execute(
            toolName: "set_tile",
            arguments: [
                "sprite_area_name": "game",
                "tilemap_name": "level",
                "column": "99",
                "row": "0",
                "tile_index": "1",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.lowercased().contains("out of bounds"))
    }

    @Test("fill_tilemap paints every cell")
    func fillTilemapPaintsAll() async {
        var (doc, cardId) = await docWithEmptyTileMap()
        _ = await HypeToolExecutor().execute(
            toolName: "fill_tilemap",
            arguments: [
                "sprite_area_name": "game",
                "tilemap_name": "level",
                "tile_index": "1",
            ],
            document: &doc,
            currentCardId: cardId
        )
        let area = doc.parts.first { $0.name == "game" }!
        let spec = SceneSpec.fromJSON(area.sceneSpec)!
        let tm = spec.nodes.first { $0.name == "level" }!.tileMapSpec!
        // 5x3 grid, all should be tile 1.
        #expect(tm.tileData.count == 3)
        for row in tm.tileData {
            #expect(row.count == 5)
            for cell in row { #expect(cell == 1) }
        }
    }

    @Test("get_tilemap_info reports grid and tileset binding")
    func getTilemapInfoReports() async {
        var (doc, cardId) = await docWithEmptyTileMap()
        let result = await HypeToolExecutor().execute(
            toolName: "get_tilemap_info",
            arguments: [
                "sprite_area_name": "game",
                "tilemap_name": "level",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.contains("5 cols") || result.contains("5 \u{00d7} 3"))
        #expect(result.contains("level"))
        #expect(result.contains("ts"))
    }

    // MARK: - HypeTalk interpreter: createTileMap pulls asset metadata

    @Test("HypeTalk `create tilemap` pulls tileSetColumns from classified asset")
    func hypetalkCreateTilemapPullsColumns() {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "grass",
            kind: .tileSet,
            width: 256,
            height: 64,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 8,
            tileRows: 2
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game",
                        left: 0, top: 0, width: 800, height: 600)
        area.sceneSpec = SceneSpec().toJSON()
        doc.addPart(area)

        let script = """
            on openCard
              create tilemap "ground" columns 20 rows 15 with tileset "grass"
            end openCard
            """
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = script
        let result = MessageDispatcher().dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed)
        let modified = result.modifiedDocument ?? doc
        let areaPart = modified.parts.first { $0.name == "game" }!
        let spec = SceneSpec.fromJSON(areaPart.sceneSpec)!
        let tm = spec.nodes.first { $0.name == "ground" }!.tileMapSpec!
        #expect(tm.tileSetColumns == 8)
        #expect(tm.tileWidth == 32)
        #expect(tm.tileHeight == 32)
    }

    // MARK: - HypeTalk parser: new tile forms

    private func parses(_ source: String) -> Bool {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
            return true
        } catch {
            return false
        }
    }

    @Test("parser accepts `the tile at col,row of tilemap \"X\"`")
    func parsesTheTileAt() {
        #expect(parses("""
            on test
              put the tile at 3,5 of tilemap "ground" into t
            end test
            """))
    }

    @Test("parser accepts `the tile 3,5 of tilemap \"X\"` (at is optional)")
    func parsesTheTileBareCommaForm() {
        #expect(parses("""
            on test
              put the tile 3,5 of tilemap "ground" into t
            end test
            """))
    }

    @Test("parser accepts `fill tilemap \"X\" with N`")
    func parsesFillTilemap() {
        #expect(parses("""
            on test
              fill tilemap "ground" with 7
            end test
            """))
    }

    @Test("parser accepts `clear tilemap \"X\"`")
    func parsesClearTilemap() {
        #expect(parses("""
            on test
              clear tilemap "ground"
            end test
            """))
    }

    @Test("parser still treats `fill` as a bare identifier when not followed by tilemap")
    func fillIsNotReservedOutsideTilemap() {
        // A script that uses `fill` as a variable name should
        // still parse clean — the `fill` dispatch gate in
        // parseStatement only activates when the next token is
        // `.tilemap`, so normal expressions are unaffected.
        #expect(parses("""
            on test
              put "red" into fill
              put fill into x
            end test
            """))
    }

    // MARK: - HypeTalk interpreter: set/get/fill/clear end-to-end

    @Test("HypeTalk set + get tile round-trips through a tile map")
    func setGetTileRoundTrips() {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "ts",
            kind: .tileSet,
            width: 128,
            height: 32,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 4,
            tileRows: 1
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game",
                        left: 0, top: 0, width: 800, height: 600)
        area.sceneSpec = SceneSpec().toJSON()
        doc.addPart(area)

        let script = """
            on openCard
              create tilemap "level" columns 5 rows 3 with tileset "ts"
              set tile 2,1 of tilemap "level" to 3
              put the tile at 2,1 of tilemap "level" into it
              put it into field "log"
            end openCard
            """
        // Need a field to write into so we can read the value out.
        var fld = Part(partType: .field, cardId: cardId, name: "log",
                       left: 0, top: 0, width: 200, height: 40)
        fld.textContent = ""
        doc.addPart(fld)
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = script

        let result = MessageDispatcher().dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed)
        let modified = result.modifiedDocument ?? doc
        let field = modified.parts.first { $0.name == "log" }!
        #expect(field.textContent == "3",
                "set tile 2,1 to 3 then reading it back should return \"3\", got '\(field.textContent)'")
    }

    @Test("HypeTalk create tilemap expands scene design size to fit the map grid")
    func hypetalkCreateTilemapExpandsSceneSizeToMap() {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "maze_tiles",
            kind: .tileSet,
            width: 1024,
            height: 1024,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 32,
            tileRows: 32
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game",
                        left: 0, top: 0, width: 608, height: 449)
        area.setSpriteAreaSpec(
            SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 608, height: 449))
        )
        doc.addPart(area)
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = """
            on openCard
              create tilemap "maze" columns 24 rows 17 with tileset "maze_tiles"
            end openCard
            """

        let result = MessageDispatcher().dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        )

        #expect(result.status == .completed)
        let modified = result.modifiedDocument ?? doc
        let areaPart = modified.parts.first { $0.name == "game" }!
        let areaSpec = areaPart.spriteAreaSpecModel!
        #expect(areaSpec.designSize.width == 768)
        #expect(areaSpec.designSize.height == 544)
        #expect(areaSpec.activeScene?.size.width == 768)
        #expect(areaSpec.activeScene?.size.height == 544)
    }

    @Test("HypeTalk `fill tilemap \"X\" with N` paints every cell")
    func hypetalkFillTilemapPaintsAll() {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "ts", kind: .tileSet,
            width: 128, height: 32,
            tileWidth: 32, tileHeight: 32,
            tileColumns: 4, tileRows: 1
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game",
                        left: 0, top: 0, width: 800, height: 600)
        area.sceneSpec = SceneSpec().toJSON()
        doc.addPart(area)
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = """
            on openCard
              create tilemap "level" columns 3 rows 2 with tileset "ts"
              fill tilemap "level" with 2
            end openCard
            """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        let modified = result.modifiedDocument ?? doc
        let areaPart = modified.parts.first { $0.name == "game" }!
        let spec = SceneSpec.fromJSON(areaPart.sceneSpec)!
        let tm = spec.nodes.first { $0.name == "level" }!.tileMapSpec!
        #expect(tm.tileData.count == 2)
        for row in tm.tileData {
            #expect(row.count == 3)
            for cell in row { #expect(cell == 2) }
        }
    }

    @Test("HypeTalk `clear tilemap \"X\"` resets every cell to -1")
    func hypetalkClearTilemap() {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "ts", kind: .tileSet,
            width: 128, height: 32,
            tileWidth: 32, tileHeight: 32,
            tileColumns: 4, tileRows: 1
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game",
                        left: 0, top: 0, width: 800, height: 600)
        area.sceneSpec = SceneSpec().toJSON()
        doc.addPart(area)
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = """
            on openCard
              create tilemap "level" columns 2 rows 2 with tileset "ts"
              fill tilemap "level" with 1
              clear tilemap "level"
            end openCard
            """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        let modified = result.modifiedDocument ?? doc
        let areaPart = modified.parts.first { $0.name == "game" }!
        let spec = SceneSpec.fromJSON(areaPart.sceneSpec)!
        let tm = spec.nodes.first { $0.name == "level" }!.tileMapSpec!
        for row in tm.tileData {
            for cell in row { #expect(cell == -1) }
        }
    }

    @Test("the tile at out-of-bounds returns -1 sentinel")
    func tileAtOOBReturnsMinus1() {
        var doc = HypeDocument.newDocument(name: "Tile Test")
        let cardId = doc.cards[0].id
        doc.assetRepository.addAsset(Asset(
            name: "ts", kind: .tileSet,
            width: 128, height: 32,
            tileWidth: 32, tileHeight: 32,
            tileColumns: 4, tileRows: 1
        ))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game",
                        left: 0, top: 0, width: 800, height: 600)
        area.sceneSpec = SceneSpec().toJSON()
        doc.addPart(area)
        var fld = Part(partType: .field, cardId: cardId, name: "log",
                       left: 0, top: 0, width: 100, height: 30)
        fld.textContent = ""
        doc.addPart(fld)
        let idx = doc.cards.firstIndex { $0.id == cardId }!
        doc.cards[idx].script = """
            on openCard
              create tilemap "level" columns 2 rows 2 with tileset "ts"
              put the tile at 99,99 of tilemap "level" into field "log"
            end openCard
            """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        let modified = result.modifiedDocument ?? doc
        #expect(modified.parts.first { $0.name == "log" }?.textContent == "-1")
    }

    // MARK: - Tool registry

    @Test("all new tile tools are registered in HypeToolDefinitions.allTools")
    func newTileToolsRegistered() {
        let names = HypeToolDefinitions.allTools.map { $0.function.name }
        #expect(names.contains("classify_asset_as_tileset"))
        #expect(names.contains("set_tile"))
        #expect(names.contains("fill_tilemap"))
        #expect(names.contains("get_tilemap_info"))
    }
}

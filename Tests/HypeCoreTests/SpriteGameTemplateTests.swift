import Foundation
import Testing
@testable import HypeCore

@Suite("Sprite game template tools")
struct SpriteGameTemplateTests {
    @Test("repository name lookup prefers newest duplicate asset")
    func repositoryLookupUsesNewestDuplicate() throws {
        let old = SpriteAsset(name: "maze_tile_wall", data: Data([1]), width: 32, height: 32)
        let newer = SpriteAsset(name: "maze_tile_wall", kind: .tileSet, data: Data([2]), width: 64, height: 32, tileWidth: 32, tileHeight: 32, tileColumns: 2, tileRows: 1)
        let repository = SpriteRepository(assets: [old, newer])

        let resolved = try #require(repository.asset(byName: "maze_tile_wall"))
        #expect(resolved.id == newer.id)
        #expect(resolved.isTileSet)
        #expect(resolved.tileColumns == 2)
    }

    @Test("deterministic tileset asset is classified and embedded")
    func deterministicTilesetAssetIsClassified() throws {
        let asset = try SpriteGameTemplateBuilder.createBasicMazeTilesetAsset(name: "maze_tiles_basic", tileSize: 32)

        #expect(asset.name == "maze_tiles_basic")
        #expect(asset.kind == .tileSet)
        #expect(asset.isTileSet)
        #expect(asset.tileWidth == 32)
        #expect(asset.tileHeight == 32)
        #expect(asset.tileColumns == 4)
        #expect(asset.tileRows == 1)
        #expect(asset.width == 128)
        #expect(asset.height == 32)
        #expect(!asset.data.isEmpty)
    }

    @Test("create_basic_tileset_asset tool stores a ready-to-use tileset")
    func createBasicTilesetToolStoresAsset() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id

        let result = await HypeToolExecutor().execute(
            toolName: "create_basic_tileset_asset",
            arguments: ["asset_name": "local_maze_tiles"],
            document: &document,
            currentCardId: cardId
        )

        let asset = try #require(document.spriteRepository.asset(byName: "local_maze_tiles"))
        #expect(result.contains("Created deterministic tileset asset 'local_maze_tiles'"))
        #expect(asset.kind == .tileSet)
        #expect(asset.isTileSet)
        #expect(asset.tileColumns == 4)
    }

    @Test("create_sprite_game_template builds Pac-Man scene from scratch")
    func createSpriteGameTemplateBuildsPacmanScene() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id

        let result = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "sprite_area_name": "pacmanArea",
                "game_type": "pacman"
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("Pac-Man-style game"))
        let area = try #require(document.parts.first { $0.name == "pacmanArea" })
        #expect(area.partType == .spriteArea)
        let scene = try #require(area.activeSceneSpec)
        #expect(scene.size.width == 768)
        #expect(scene.size.height == 544)
        #expect(scene.gravity.dx == 0)
        #expect(scene.gravity.dy == 0)

        let tileset = try #require(document.spriteRepository.asset(byName: "hype_pacman_maze_tiles"))
        #expect(tileset.kind == .tileSet)
        #expect(tileset.tileColumns == 4)

        let maze = try #require(scene.node(named: "maze"))
        #expect(maze.nodeType == .tileMap)
        #expect(maze.tileMapSpec?.columns == 24)
        #expect(maze.tileMapSpec?.rows == 17)
        #expect(maze.tileMapSpec?.tileSetColumns == 4)
        #expect(maze.tileMapSpec?.tileSetAssetRef?.id == tileset.id)

        #expect(scene.node(named: "pacmanPlayer")?.physicsBody?.categoryBitmask == 2)
        #expect(scene.node(named: "ghost_blinky")?.physicsBody?.velocityX == 120)
        #expect(scene.node(named: "ghost_pinky")?.physicsBody?.velocityX == -120)
        #expect(scene.node(named: "scoreLabel")?.nodeType == .label)

        let wallColliders = scene.allNodes.filter { $0.name.hasPrefix("wall_") && $0.physicsBody?.isDynamic == false }
        let pellets = scene.allNodes.filter { $0.name.hasPrefix("pellet_") }
        let powerPellets = scene.allNodes.filter { $0.name.hasPrefix("power_pellet_") }
        #expect(wallColliders.count > 40)
        #expect(pellets.count > 100)
        #expect(powerPellets.count == 4)

        var lexer = Lexer(source: scene.script)
        var parser = Parser(tokens: lexer.tokenize())
        let parsed = try parser.parse()
        let handlers = Set(parsed.handlers.map { $0.name.lowercased() })
        #expect(handlers.contains("scenedidload"))
        #expect(handlers.contains("keydown"))
        #expect(handlers.contains("keyup"))
        #expect(handlers.contains("begincontact"))
    }

    @Test("SpriteKit and repository AI catalogs include deterministic game tools")
    func toolCatalogsIncludeGameTools() {
        let spriteTools = Set(HypeToolDefinitions.spriteSceneAuthoringTools.map(\.function.name))
        let repoTools = Set(HypeToolDefinitions.spriteRepositoryAuthoringTools.map(\.function.name))

        #expect(spriteTools.contains("create_sprite_game_template"))
        #expect(spriteTools.contains("create_basic_tileset_asset"))
        #expect(repoTools.contains("create_basic_tileset_asset"))
        #expect(!repoTools.contains("create_sprite_game_template"))
    }
}

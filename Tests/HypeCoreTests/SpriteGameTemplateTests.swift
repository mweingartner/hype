import Foundation
import Testing
@testable import HypeCore

@Suite("Sprite game template tools")
struct SpriteGameTemplateTests {
    @Test("sprite game template catalog exposes the full deterministic template set")
    func spriteGameTemplateCatalogExposesFullSet() throws {
        let ids = Set(SpriteGameTemplateBuilder.supportedGameTypes)
        #expect(ids == Set([
            "maze_chase",
            "barrel_climber",
            "side_scroller_platformer",
            "top_down_adventure",
            "twin_stick_shooter",
            "space_shooter",
            "physics_puzzle",
            "breakout",
            "pinball_pachinko",
            "endless_runner",
            "tower_defense",
            "missile_command",
            "match3_grid_puzzle",
            "sokoban_block_puzzle",
            "racing_lane",
            "pong_sports_arena",
            "rhythm_timing",
            "board_card_game",
            "boss_wave_arena",
            "sandbox_physics_toy",
            "educational_sim",
        ]))
        #expect(try SpriteGameTemplateBuilder.normalizedGameType("pacman") == "maze_chase")
        #expect(try SpriteGameTemplateBuilder.normalizedGameType("donkey_kong_style") == "barrel_climber")
        #expect(try SpriteGameTemplateBuilder.normalizedGameType("shmup") == "space_shooter")
        #expect(try SpriteGameTemplateBuilder.normalizedGameType("zelda-like") == "top_down_adventure")
        #expect(try SpriteGameTemplateBuilder.normalizedGameType("angry birds") == "physics_puzzle")
        #expect(try SpriteGameTemplateBuilder.normalizedGameType("missile command") == "missile_command")
    }

    @Test("repository name lookup prefers newest duplicate asset")
    func repositoryLookupUsesNewestDuplicate() throws {
        let old = Asset(name: "maze_tile_wall", data: Data([1]), width: 32, height: 32)
        let newer = Asset(name: "maze_tile_wall", kind: .tileSet, data: Data([2]), width: 64, height: 32, tileWidth: 32, tileHeight: 32, tileColumns: 2, tileRows: 1)
        let repository = AssetRepository(assets: [old, newer])

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

        let asset = try #require(document.assetRepository.asset(byName: "local_maze_tiles"))
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

        let tileset = try #require(document.assetRepository.asset(byName: "hype_pacman_maze_tiles"))
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
        #expect(scene.script.contains("the key is \"up\""))
        #expect(scene.script.contains("the key is \"down\""))
        #expect(scene.script.contains("the key is \"left\""))
        #expect(scene.script.contains("the key is \"right\""))
        #expect(scene.script.contains("the key is \"w\""))

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

    @Test("create_sprite_game_template rebuilds idempotently without duplicate parts or assets")
    func createSpriteGameTemplateRebuildsIdempotently() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "create_sprite_game_template",
            arguments: ["sprite_area_name": "pacmanArea", "game_type": "pacman"],
            document: &document,
            currentCardId: cardId
        )
        let firstArea = try #require(document.parts.first { $0.name == "pacmanArea" })
        let firstAreaId = firstArea.id
        let firstAssetIdsByName = Dictionary(uniqueKeysWithValues: document.assetRepository.assets.map { ($0.name, $0.id) })

        let rebuildResult = await executor.execute(
            toolName: "create_sprite_game_template",
            arguments: ["sprite_area_name": "pacmanArea", "game_type": "maze_chase"],
            document: &document,
            currentCardId: cardId
        )

        #expect(rebuildResult.contains("Rebuilt Pac-Man-style game"))
        #expect(document.parts.filter { $0.name == "pacmanArea" }.count == 1)
        #expect(document.parts.first { $0.name == "pacmanArea" }?.id == firstAreaId)
        let templateAssets = document.assetRepository.assets.filter { $0.tags.contains("hype-template") }
        #expect(templateAssets.count == 8)
        for asset in templateAssets {
            #expect(firstAssetIdsByName[asset.name] == asset.id)
        }
        let scene = try #require(document.parts.first { $0.name == "pacmanArea" }?.activeSceneSpec)
        #expect(scene.node(named: "maze")?.tileMapSpec?.tileSetColumns == 4)
        #expect(scene.allNodes.filter { $0.name.hasPrefix("wall_") }.count > 40)
    }

    @Test("create_sprite_game_template builds and parses every catalog template")
    func createSpriteGameTemplateBuildsEveryCatalogTemplate() async throws {
        for descriptor in SpriteGameTemplateBuilder.templateCatalog {
            var document = HypeDocument.newDocument()
            let cardId = document.sortedCards[0].id
            let result = await HypeToolExecutor().execute(
                toolName: "create_sprite_game_template",
                arguments: [
                    "sprite_area_name": descriptor.defaultSpriteAreaName,
                    "game_type": descriptor.id
                ],
                document: &document,
                currentCardId: cardId
            )

            #expect(result.contains(descriptor.displayName))
            let area = try #require(document.parts.first { $0.name == descriptor.defaultSpriteAreaName })
            let scene = try #require(area.activeSceneSpec)
            #expect(scene.name == "main")
            #expect(scene.size == descriptor.defaultSceneSize)
            #expect(scene.node(named: descriptor.generatedNodeNames.first ?? "") != nil)
            #expect(!scene.script.isEmpty)

            var lexer = Lexer(source: scene.script)
            var parser = Parser(tokens: lexer.tokenize())
            let parsed = try parser.parse()
            let handlers = Set(parsed.handlers.map { $0.name.lowercased() })
            #expect(handlers.contains("scenedidload"))
            #expect(handlers.contains("keydown"))
            #expect(handlers.contains("begincontact"))
        }
    }

    @Test("generic catalog template rebuild is idempotent")
    func genericCatalogTemplateRebuildsIdempotently() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "create_sprite_game_template",
            arguments: ["sprite_area_name": "towerDefenseArea", "game_type": "tower_defense"],
            document: &document,
            currentCardId: cardId
        )
        let firstArea = try #require(document.parts.first { $0.name == "towerDefenseArea" })
        let firstAreaId = firstArea.id
        let firstAssets = Dictionary(uniqueKeysWithValues: document.assetRepository.assets.map { ($0.name, $0.id) })

        let result = await executor.execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "sprite_area_name": "towerDefenseArea",
                "game_type": "tower_defense",
                "scene_width": "640",
                "scene_height": "480",
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("Rebuilt tower defense game"))
        #expect(document.parts.filter { $0.name == "towerDefenseArea" }.count == 1)
        let rebuiltArea = try #require(document.parts.first { $0.name == "towerDefenseArea" })
        #expect(rebuiltArea.id == firstAreaId)
        #expect(rebuiltArea.width == 640)
        #expect(rebuiltArea.height == 480)
        for asset in document.assetRepository.assets where asset.tags.contains("tower_defense") {
            #expect(firstAssets[asset.name] == asset.id)
        }
        let scene = try #require(document.parts.first { $0.name == "towerDefenseArea" }?.activeSceneSpec)
        #expect(scene.node(named: "tower_1") != nil)
        #expect(scene.node(named: "templateTileMap")?.nodeType == .tileMap)
    }

    @Test("create_sprite_game_template builds Donkey Kong-style platformer scene from scratch")
    func createSpriteGameTemplateBuildsPlatformerScene() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id

        let result = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "game_type": "donkey_kong_style",
                "left": "0",
                "top": "0",
                "width": "800",
                "height": "600"
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("barrel-climber platformer game"))
        let area = try #require(document.parts.first { $0.name == "barrelClimberArea" })
        #expect(area.partType == .spriteArea)
        #expect(area.left == 0)
        #expect(area.top == 0)
        #expect(area.width == 800)
        #expect(area.height == 600)

        let scene = try #require(area.activeSceneSpec)
        #expect(scene.size.width == 800)
        #expect(scene.size.height == 600)
        #expect(scene.gravity.dy == -9.8)
        #expect(scene.node(named: "hero")?.physicsBody?.categoryBitmask == 2)
        #expect(scene.node(named: "hero")?.physicsBody?.contactTestBitmask == 228)
        #expect(scene.node(named: "hero")?.physicsBody?.collisionBitmask == 5)
        #expect(scene.node(named: "barrel_1")?.position == PointSpec(x: 148, y: 130))
        #expect(scene.node(named: "barrel_1")?.physicsBody?.velocityX == 165)
        #expect(scene.node(named: "goal_prize")?.physicsBody?.contactTestBitmask == 2)
        #expect(scene.node(named: "platform_ground")?.physicsBody?.isDynamic == false)
        #expect(scene.node(named: "platform_gorilla")?.physicsBody?.isDynamic == false)
        #expect(scene.node(named: "ladder_1")?.physicsBody?.categoryBitmask == 64)
        #expect(scene.node(named: "ladder_1")?.physicsBody?.contactTestBitmask == 2)
        #expect(scene.node(named: "ladder_1")?.physicsBody?.collisionBitmask == 0)
        #expect(scene.node(named: "hammer_1")?.physicsBody?.categoryBitmask == 128)
        #expect(scene.node(named: "hammer_1")?.physicsBody?.contactTestBitmask == 2)
        #expect(scene.node(named: "hammer_2")?.position == PointSpec(x: 468, y: 242))
        #expect(scene.node(named: "hammerSwing")?.isHidden == true)
        #expect(scene.node(named: "hammerSwing")?.physicsBody?.categoryBitmask == 2)
        #expect(scene.node(named: "hammerSwing")?.physicsBody?.contactTestBitmask == 4)
        #expect(scene.node(named: "livesLabel")?.text == "Lives: 3")
        #expect(scene.node(named: "statusLabel")?.text?.contains("Ladders are safe") == true)
        #expect(scene.script.contains("the key is \"space\""))
        #expect(scene.script.contains("set the velocityX of sprite \"hero\""))
        #expect(scene.script.contains("global lives"))
        #expect(scene.script.contains("global hammerActive"))
        #expect(scene.script.contains("send \"sceneDidLoad\"") == false)

        for assetName in [
            "hype_barrel_platform",
            "hype_barrel_hero",
            "hype_barrel_hazard",
            "hype_barrel_rival",
            "hype_barrel_trophy",
            "hype_barrel_ladder",
            "hype_barrel_hammer",
        ] {
            #expect(document.assetRepository.asset(byName: assetName) != nil)
        }

        let newGameButton = try #require(document.parts.first { $0.partType == .button && $0.name == "New Game" })
        #expect(newGameButton.cardId == cardId)
        #expect(newGameButton.script.contains("send \"sceneDidLoad\" to spriteArea \"barrelClimberArea\""))

        var sceneLexer = Lexer(source: scene.script)
        var sceneParser = Parser(tokens: sceneLexer.tokenize())
        let parsedScene = try sceneParser.parse()
        let handlers = Set(parsedScene.handlers.map { $0.name.lowercased() })
        #expect(handlers.contains("scenedidload"))
        #expect(handlers.contains("keydown"))
        #expect(handlers.contains("keyup"))
        #expect(handlers.contains("begincontact"))
        #expect(handlers.contains("endcontact"))
        #expect(handlers.contains("frameupdate"))

        var buttonLexer = Lexer(source: newGameButton.script)
        var buttonParser = Parser(tokens: buttonLexer.tokenize())
        let parsedButton = try buttonParser.parse()
        #expect(parsedButton.handlers.map { $0.name.lowercased() }.contains("mouseup"))
    }

    @Test("Donkey Kong platformer keyboard and reset handlers mutate sprite scene state")
    func platformerKeyboardAndResetHandlersMutateSceneState() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        _ = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "game_type": "donkey_kong_style",
                "width": "800",
                "height": "600"
            ],
            document: &document,
            currentCardId: cardId
        )

        let area = try #require(document.parts.first { $0.name == "barrelClimberArea" })
        let sceneId = try #require(area.activeSceneID)
        let scene = try #require(area.activeSceneSpec)
        let context = ScriptDispatchContext(
            hierarchyPrefix: [sceneId, area.id],
            objectScripts: [sceneId: scene.script],
            objectDescriptions: [sceneId: "scene \"\(scene.name)\""]
        )
        let dispatcher = MessageDispatcher()

        func dispatch(_ message: String, _ params: [Value], document sourceDocument: HypeDocument) async -> ExecutionResult {
            await runOnLargeStack { [sourceDocument, cardId] in dispatcher.dispatch(
                message: message,
                params: params,
                targetId: sceneId,
                document: sourceDocument,
                currentCardId: cardId,
                scriptContext: context
            ) }
        }

        let reset = await dispatch("sceneDidLoad", [], document: document)
        #expect(reset.status == .completed)
        var mutated = try #require(reset.modifiedDocument)
        #expect(mutated.scriptGlobals["score"] == "0")
        #expect(mutated.scriptGlobals["lives"] == "3")
        #expect(mutated.scriptGlobals["onladder"] == "false")
        #expect(mutated.scriptGlobals["hammeractive"] == "false")
        #expect(mutated.scriptGlobals["gameover"] == "false")
        var mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        var hero = try #require(mutatedScene.node(named: "hero"))
        #expect(hero.position == PointSpec(x: 82, y: 516))
        #expect(hero.physicsBody?.velocityX == 0)
        #expect(hero.physicsBody?.velocityY == 0)
        #expect(hero.physicsBody?.affectedByGravity == true)
        #expect(hero.physicsBody?.collisionBitmask == 5)
        #expect(mutatedScene.node(named: "barrel_1")?.position == PointSpec(x: 148, y: 130))
        #expect(mutatedScene.node(named: "barrel_5")?.physicsBody?.velocityX == 145)
        #expect(mutatedScene.node(named: "hammer_1")?.isHidden == false)
        #expect(mutatedScene.node(named: "hammer_1")?.physicsBody?.contactTestBitmask == 2)

        let keyDownD = await dispatch("keyDown", ["d"], document: mutated)
        #expect(keyDownD.status == .completed)
        mutated = try #require(keyDownD.modifiedDocument)
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hero")?.physicsBody?.velocityX == 190)
        #expect(mutated.scriptGlobals["facing"] == "right")

        let keyDownA = await dispatch("keyDown", ["a"], document: mutated)
        #expect(keyDownA.status == .completed)
        mutated = try #require(keyDownA.modifiedDocument)
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hero")?.physicsBody?.velocityX == -190)
        #expect(mutated.scriptGlobals["facing"] == "left")

        let keyDownW = await dispatch("keyDown", ["w"], document: mutated)
        #expect(keyDownW.status == .completed)
        mutated = try #require(keyDownW.modifiedDocument)
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hero")?.physicsBody?.velocityY == 190)

        let keyDownS = await dispatch("keyDown", ["s"], document: mutated)
        #expect(keyDownS.status == .completed)
        mutated = try #require(keyDownS.modifiedDocument)
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hero")?.physicsBody?.velocityY == -190)

        let jump = await dispatch("keyDown", ["space"], document: mutated)
        #expect(jump.status == .completed)
        mutated = try #require(jump.modifiedDocument)
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hero")?.physicsBody?.velocityY == 620)

        let keyUp = await dispatch("keyUp", ["a"], document: mutated)
        #expect(keyUp.status == .completed)
        mutated = try #require(keyUp.modifiedDocument)
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hero")?.physicsBody?.velocityX == 0)

        let ladderStart = await dispatch("beginContact", ["ladder_1"], document: mutated)
        #expect(ladderStart.status == .completed)
        mutated = try #require(ladderStart.modifiedDocument)
        #expect(mutated.scriptGlobals["onladder"] == "true")
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        hero = try #require(mutatedScene.node(named: "hero"))
        #expect(hero.physicsBody?.affectedByGravity == false)
        #expect(hero.physicsBody?.collisionBitmask == 1)

        let safeBarrel = await dispatch("beginContact", ["barrel_1"], document: mutated)
        #expect(safeBarrel.status == .completed)
        mutated = try #require(safeBarrel.modifiedDocument)
        #expect(mutated.scriptGlobals["lives"] == "3")
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "statusLabel")?.text?.contains("Safe on ladder") == true)

        let ladderEnd = await dispatch("endContact", ["ladder_1"], document: mutated)
        #expect(ladderEnd.status == .completed)
        mutated = try #require(ladderEnd.modifiedDocument)
        #expect(mutated.scriptGlobals["onladder"] == "false")
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        hero = try #require(mutatedScene.node(named: "hero"))
        #expect(hero.physicsBody?.affectedByGravity == true)
        #expect(hero.physicsBody?.collisionBitmask == 5)

        let hitOne = await dispatch("beginContact", ["barrel_1"], document: mutated)
        #expect(hitOne.status == .completed)
        mutated = try #require(hitOne.modifiedDocument)
        #expect(mutated.scriptGlobals["lives"] == "2")
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        hero = try #require(mutatedScene.node(named: "hero"))
        #expect(hero.position == PointSpec(x: 82, y: 516))
        #expect(mutatedScene.node(named: "livesLabel")?.text == "Lives: 2")

        let hitTwo = await dispatch("beginContact", ["barrel_2"], document: mutated)
        #expect(hitTwo.status == .completed)
        mutated = try #require(hitTwo.modifiedDocument)
        let hitThree = await dispatch("beginContact", ["barrel_3"], document: mutated)
        #expect(hitThree.status == .completed)
        mutated = try #require(hitThree.modifiedDocument)
        #expect(mutated.scriptGlobals["lives"] == "0")
        #expect(mutated.scriptGlobals["gameover"] == "true")
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "statusLabel")?.text?.contains("Game over") == true)
        #expect(mutatedScene.node(named: "barrel_1")?.physicsBody?.velocityX == 0)
        #expect(mutatedScene.node(named: "barrel_5")?.physicsBody?.velocityX == 0)

        let hammerReset = await dispatch("sceneDidLoad", [], document: document)
        #expect(hammerReset.status == .completed)
        var hammerDoc = try #require(hammerReset.modifiedDocument)
        let hammerPickup = await dispatch("beginContact", ["hammer_1"], document: hammerDoc)
        #expect(hammerPickup.status == .completed)
        hammerDoc = try #require(hammerPickup.modifiedDocument)
        #expect(hammerDoc.scriptGlobals["hammeractive"] == "true")
        #expect(hammerDoc.scriptGlobals["hammerticks"] == "240")
        mutatedScene = try #require(hammerDoc.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hammer_1")?.isHidden == true)
        #expect(mutatedScene.node(named: "hammer_1")?.physicsBody?.contactTestBitmask == 0)

        let smash = await dispatch("beginContact", ["barrel_2"], document: hammerDoc)
        #expect(smash.status == .completed)
        hammerDoc = try #require(smash.modifiedDocument)
        #expect(hammerDoc.scriptGlobals["lives"] == "3")
        #expect(hammerDoc.scriptGlobals["score"] == "25")
        mutatedScene = try #require(hammerDoc.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "barrel_2")?.position == PointSpec(x: 148, y: 130))
        #expect(mutatedScene.node(named: "barrel_2")?.physicsBody?.velocityX == 165)

        let frame = await dispatch("frameUpdate", ["0.016"], document: hammerDoc)
        #expect(frame.status == .completed)
        hammerDoc = try #require(frame.modifiedDocument)
        #expect(hammerDoc.scriptGlobals["hammerticks"] == "239")
        mutatedScene = try #require(hammerDoc.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hammerSwing")?.isHidden == false)
        #expect(mutatedScene.node(named: "hammerSwing")?.position == PointSpec(x: 118, y: 516))

        hammerDoc.scriptGlobals["hammerticks"] = "1"
        hammerDoc.scriptGlobals["hammeractive"] = "true"
        let expiredFrame = await dispatch("frameUpdate", ["0.016"], document: hammerDoc)
        #expect(expiredFrame.status == .completed)
        hammerDoc = try #require(expiredFrame.modifiedDocument)
        #expect(hammerDoc.scriptGlobals["hammeractive"] == "false")
        mutatedScene = try #require(hammerDoc.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "hammerSwing")?.isHidden == true)
    }

    @Test("exact Donkey Kong chat prompt infers the platformer template")
    func donkeyKongPromptInfersPlatformerTemplate() {
        let prompt = """
        Create a SpriteKit based game on the current card in the style of Donkey Kong.
        Set the play area to 800w x 600h. Create all necessary assets with the image generation AI API.
        Add a button for "New Game" that resets the game state. Use the WASD keys to move the main character and the space key to make him jump barrels.
        """

        #expect(SpriteGameTemplateBuilder.inferredGameType(forPrompt: prompt) == "barrel_climber")
        #expect(SpriteGameTemplateBuilder.defaultSpriteAreaName(for: "platformer") == "barrelClimberArea")
        #expect(SpriteGameTemplateBuilder.defaultSceneSize(for: "platformer") == SizeSpec(width: 800, height: 600))
    }

    @Test("catalog game aliases infer deterministic templates from chat prompts")
    func catalogGameAliasesInferTemplatesFromChatPrompts() {
        #expect(SpriteGameTemplateBuilder.inferredGameType(forPrompt: "make a tower defense game") == "tower_defense")
        #expect(SpriteGameTemplateBuilder.inferredGameType(forPrompt: "create a top-down shooter") == "twin_stick_shooter")
        #expect(SpriteGameTemplateBuilder.inferredGameType(forPrompt: "build an angry birds physics puzzle") == "physics_puzzle")
        #expect(SpriteGameTemplateBuilder.inferredGameType(forPrompt: "make a match-3 puzzle") == "match3_grid_puzzle")
        #expect(SpriteGameTemplateBuilder.inferredGameType(forPrompt: "create a zelda-like dungeon") == "top_down_adventure")
        #expect(SpriteGameTemplateBuilder.inferredGameType(forPrompt: "build a Missile Command-style city defense game") == "missile_command")
    }

    @Test("missile command template options route to deterministic missile template")
    func missileCommandTemplateOptionsRouteToMissileTemplate() async throws {
        var document = HypeDocument.newDocument()
        let cardId = try #require(document.sortedCards.first?.id)

        let result = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "game_type": "educational_sim",
                "sprite_area_name": "missileCommandArea",
                "template_options": #"{"genre":"missile_command","fireKey":"space","empKey":"enter"}"#
            ],
            document: &document,
            currentCardId: cardId
        )

        let area = try #require(document.parts.first { $0.name == "missileCommandArea" })
        let scene = try #require(area.activeSceneSpec)
        #expect(result.contains("Missile Command-style city defense game"))
        #expect(scene.node(named: "launcher") != nil)
        #expect(scene.node(named: "city_1") != nil)
        #expect(scene.node(named: "incoming_missile_1") != nil)
    }

    @Test("sprite game inference preserves explicit existing scene intent")
    func spriteGameInferencePreservesExplicitSceneIntent() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let result = await HypeToolExecutor().execute(
            toolName: "infer_sprite_game_template",
            arguments: [
                "user_prompt": """
                create a missile command style game in the sprite scene "missile" on the current card. The sprite scene already exists so add the needed assets to this existing sprite scene. Create all needed sprite and background images with the image generation api. add all needed logic for the game to fully work.
                """
            ],
            document: &document,
            currentCardId: cardId
        )

        let data = try #require(result.data(using: .utf8))
        let inference = try JSONDecoder().decode(GameTemplateInferenceResult.self, from: data)
        #expect(inference.templateID == "missile_command")
        #expect(inference.templateUse == .createThenCustomize)
        #expect(inference.shouldAutoApplyTemplate == false)
        #expect(inference.explicitSceneName == "missile")
        #expect(inference.requiresExistingTarget == true)
        #expect(inference.requestsImageGeneration == true)
        #expect(inference.recommendedCreateArguments["scene_name"] == "missile")
        #expect(inference.recommendedCreateArguments["require_existing_scene"] == "true")
        #expect(inference.recommendedCreateArguments["sprite_area_name"] == nil)
    }

    @Test("create_sprite_game_template targets an existing named scene without creating template default area")
    func createSpriteGameTemplateTargetsExistingNamedScene() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let size = SizeSpec(width: 640, height: 480)
        var area = Part(partType: .spriteArea, cardId: cardId, name: "game_area", left: 20, top: 20, width: 640, height: 480)
        let mainEntry = SpriteAreaScene(scene: SceneSpec(name: "main", size: size, backgroundColor: "#111111"))
        let missileEntry = SpriteAreaScene(scene: SceneSpec(name: "missile", size: size, backgroundColor: "#222222"))
        area.setSpriteAreaSpec(SpriteAreaSpec(
            activeSceneID: mainEntry.id,
            scenes: [mainEntry, missileEntry],
            designSize: size
        ))
        document.addPart(area)

        let result = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "game_type": "missile_command",
                "scene_name": "missile",
                "require_existing_scene": "true"
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("scene 'missile' in sprite area 'game_area'"))
        #expect(document.parts.first { $0.name == "missileCommandArea" } == nil)
        let rebuiltArea = try #require(document.parts.first { $0.name == "game_area" })
        let spec = try #require(rebuiltArea.spriteAreaSpecModel)
        #expect(spec.sceneNames.contains("main"))
        #expect(spec.sceneNames.contains("missile"))
        let main = try #require(spec.scene(named: "main"))
        #expect(main.allNodes.isEmpty)
        let missile = try #require(spec.scene(named: "missile"))
        #expect(missile.node(named: "launcher") != nil)
        #expect(missile.node(named: "city_1") != nil)
        #expect(spec.activeScene?.name == "missile")
    }

    @Test("create_sprite_game_template infers existing sprite area from user_intent instead of creating default area")
    func createSpriteGameTemplateInfersExistingAreaFromUserIntent() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "missile", left: 20, top: 20, width: 640, height: 480)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 640, height: 480)))
        document.addPart(area)

        let result = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "game_type": "missile_command",
                "user_intent": #"create a missile command style game in the current card within the existing sprite area called "missile". Implement all game logic and use the image generation API to create all needed assets for sprites, walls, etc."#
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("sprite area 'missile'"))
        #expect(document.parts.first { $0.name == "missileCommandArea" } == nil)
        let rebuiltArea = try #require(document.parts.first { $0.name == "missile" })
        let scene = try #require(rebuiltArea.activeSceneSpec)
        #expect(scene.node(named: "launcher") != nil)
        #expect(scene.node(named: "city_1") != nil)
        #expect(!scene.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("create_sprite_game_template honors quoted sprite area before suffix in user_intent")
    func createSpriteGameTemplateHonorsQuotedAreaBeforeSuffix() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "missile", left: 20, top: 20, width: 640, height: 480)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 640, height: 480)))
        document.addPart(area)

        let result = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "game_type": "missile_command",
                "user_intent": #"there is zero game logic in the missile command game in the "missile" sprite area. Why didn't you create it?"#
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("sprite area 'missile'"))
        #expect(document.parts.first { $0.name == "missileCommandArea" } == nil)
        let rebuiltArea = try #require(document.parts.first { $0.name == "missile" })
        let scene = try #require(rebuiltArea.activeSceneSpec)
        #expect(scene.node(named: "launcher") != nil)
        #expect(scene.node(named: "city_1") != nil)
    }

    @Test("create_sprite_game_template fails safely when required existing scene is missing")
    func createSpriteGameTemplateFailsWhenRequiredSceneMissing() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id

        let result = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: [
                "game_type": "missile_command",
                "scene_name": "missile",
                "require_existing_scene": "true"
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("Sprite scene 'missile' was not found"))
        #expect(document.parts.first { $0.name == "missileCommandArea" } == nil)
        #expect(document.parts.filter { $0.partType == .spriteArea }.isEmpty)
    }

    @Test("generic template keyboard and contact handlers mutate scene state")
    func genericTemplateKeyboardAndContactHandlersMutateSceneState() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        _ = await HypeToolExecutor().execute(
            toolName: "create_sprite_game_template",
            arguments: ["game_type": "top_down_adventure"],
            document: &document,
            currentCardId: cardId
        )

        let area = try #require(document.parts.first { $0.name == "adventureArea" })
        let sceneId = try #require(area.activeSceneID)
        let scene = try #require(area.activeSceneSpec)
        let context = ScriptDispatchContext(
            hierarchyPrefix: [sceneId, area.id],
            objectScripts: [sceneId: scene.script],
            objectDescriptions: [sceneId: "scene \"\(scene.name)\""]
        )
        let dispatcher = MessageDispatcher()

        func dispatch(_ message: String, _ params: [Value], document sourceDocument: HypeDocument) async -> ExecutionResult {
            await runOnLargeStack { [sourceDocument, cardId] in dispatcher.dispatch(
                message: message,
                params: params,
                targetId: sceneId,
                document: sourceDocument,
                currentCardId: cardId,
                scriptContext: context
            ) }
        }

        let reset = await dispatch("sceneDidLoad", [], document: document)
        #expect(reset.status == .completed)
        var mutated = try #require(reset.modifiedDocument)
        #expect(mutated.scriptGlobals["score"] == "0")
        #expect(mutated.scriptGlobals["shotactive"] == "false")

        let right = await dispatch("keyDown", ["d"], document: mutated)
        #expect(right.status == .completed)
        mutated = try #require(right.modifiedDocument)
        var mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "player")?.physicsBody?.velocityX == 220)

        let space = await dispatch("keyDown", ["space"], document: mutated)
        #expect(space.status == .completed)
        mutated = try #require(space.modifiedDocument)
        #expect(mutated.scriptGlobals["shotactive"] == "true")
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "projectile_1")?.isHidden == false)
        #expect(mutatedScene.node(named: "projectile_1")?.physicsBody?.velocityX == 320)

        let pickup = await dispatch("beginContact", ["pickup_1"], document: mutated)
        #expect(pickup.status == .completed)
        mutated = try #require(pickup.modifiedDocument)
        #expect(mutated.scriptGlobals["score"] == "10")
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "scoreLabel")?.text == "Score: 10")

        let hazard = await dispatch("beginContact", ["enemy_1"], document: mutated)
        #expect(hazard.status == .completed)
        mutated = try #require(hazard.modifiedDocument)
        mutatedScene = try #require(mutated.parts.first { $0.id == area.id }?.activeSceneSpec)
        #expect(mutatedScene.node(named: "player")?.position == PointSpec(x: 80, y: 300))
    }

    @Test("SpriteKit and repository AI catalogs include deterministic game tools")
    func toolCatalogsIncludeGameTools() {
        let spriteTools = Set(HypeToolDefinitions.spriteSceneAuthoringTools.map(\.function.name))
        let repoTools = Set(HypeToolDefinitions.assetRepositoryAuthoringTools.map(\.function.name))

        #expect(spriteTools.contains("create_sprite_game_template"))
        #expect(spriteTools.contains("list_sprite_game_templates"))
        #expect(spriteTools.contains("infer_sprite_game_template"))
        #expect(spriteTools.contains("get_sprite_game_template_guide"))
        #expect(spriteTools.contains("create_basic_tileset_asset"))
        #expect(repoTools.contains("create_basic_tileset_asset"))
        #expect(!repoTools.contains("create_sprite_game_template"))
    }

    @Test("list_sprite_game_templates tool is compact by default and queryable")
    func listSpriteGameTemplatesToolDescribesCatalog() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let result = await HypeToolExecutor().execute(
            toolName: "list_sprite_game_templates",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("maze_chase"))
        #expect(result.contains("barrel_climber"))
        #expect(result.contains("tower_defense"))
        #expect(!result.contains("aliases:"))

        let detailedResult = await HypeToolExecutor().execute(
            toolName: "list_sprite_game_templates",
            arguments: [
                "query": "missile",
                "compact": "false",
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(detailedResult.contains("missile_command"))
        #expect(detailedResult.contains("aliases:"))
        #expect(detailedResult.localizedCaseInsensitiveContains("missile command"))
    }

    @Test("infer_sprite_game_template returns recommended create arguments")
    func inferSpriteGameTemplateToolReturnsRecommendedArguments() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let result = await HypeToolExecutor().execute(
            toolName: "infer_sprite_game_template",
            arguments: [
                "user_prompt": "Build a Missile Command style city defense game with EMP on enter",
                "current_card_context": "The current card has an empty sprite area named game_area.",
            ],
            document: &document,
            currentCardId: cardId
        )

        let data = try #require(result.data(using: .utf8))
        let inference = try JSONDecoder().decode(GameTemplateInferenceResult.self, from: data)
        #expect(inference.templateID == "missile_command")
        #expect(inference.recommendedCreateArguments["game_type"] == "missile_command")
        #expect(inference.matchedTerms.contains { $0.localizedCaseInsensitiveContains("missile") })
        #expect(inference.templateUse == .createThenCustomize)
        #expect(inference.shouldAutoApplyTemplate == false)
        #expect(inference.guidance.contains("create_sprite_game_template"))
    }

    @Test("get_sprite_game_template_guide returns focused details")
    func getSpriteGameTemplateGuideReturnsFocusedDetails() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let result = await HypeToolExecutor().execute(
            toolName: "get_sprite_game_template_guide",
            arguments: [
                "game_type": "barrel_climber",
                "detail_level": "full",
                "intent": "tune hammer duration and jump height",
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("Template guide: barrel_climber"))
        #expect(result.contains("create_sprite_game_template"))
        #expect(result.contains("sceneDidLoad"))
        #expect(result.localizedCaseInsensitiveContains("hammer"))
        #expect(!result.contains("Template guide: maze_chase"))
    }

    @Test("create_sprite_game_template schema defers catalog details to guide tools")
    func createSpriteGameTemplateSchemaIsCompact() throws {
        let tool = try #require(HypeToolDefinitions.spriteSceneAuthoringTools.first {
            $0.function.name == "create_sprite_game_template"
        })
        let gameTypeDescription = try #require(tool.function.parameters.properties["game_type"]?.description)

        #expect(tool.function.description.contains("infer_sprite_game_template"))
        #expect(tool.function.description.contains("get_sprite_game_template_guide"))
        #expect(gameTypeDescription.contains("infer_sprite_game_template"))
        #expect(!gameTypeDescription.contains("side_scroller_platformer"))
        #expect(!tool.function.description.contains("pinball_pachinko"))
    }
}

import Foundation
import Testing
@testable import HypeCore

// MARK: - RecipeCompilerGoldenTests

@Suite("RecipeCompiler — golden/intent fidelity tests")
struct RecipeCompilerGoldenTests {

    // MARK: - Helpers

    private func assertScriptParses(_ script: String, _ label: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
        } catch {
            Issue.record("Script parse failed\(label.isEmpty ? "" : " [\(label)]"): \(error)\n\nScript:\n\(script)", sourceLocation: sourceLocation)
        }
    }

    private func handlerCount(_ script: String, named name: String) -> Int {
        script.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("on \(name)") }
            .count
    }

    // MARK: - Canonical "asteroids dodge" recipe

    @Test("asteroids dodge recipe: nodes, physics, and script all correct")
    func asteroidsDodgeRecipe() {
        // Ship: player with topDownMovement + constrainToBounds
        let ship = GameEntity(
            name: "ship",
            role: .player,
            position: PointSpec(x: 400, y: 300),
            size: SizeSpec(width: 64, height: 64),
            behaviors: [
                Behavior(kind: .topDownMovement, params: ["speed": "200"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .loseOnContact, params: ["withRole": "hazard"]),
            ]
        )

        // Asteroid hazard (count 6 pre-placed + a spawner)
        let asteroid = GameEntity(
            name: "asteroid",
            role: .hazard,
            position: PointSpec(x: 100, y: 50),
            size: SizeSpec(width: 48, height: 48),
            count: 6,
            behaviors: [Behavior(kind: .destroyOutsideBounds, params: ["margin": "80"])]
        )

        // Spawner entity
        let spawnerNode = GameEntity(
            name: "spawner",
            role: .spawner,
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "hazard",
                    "interval": "1.5",
                    "fromEdge": "top",
                    "velocity": "0,120",
                    "max": "8"
                ])
            ]
        )

        // Score HUD
        let scoreHUD = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: 400, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0",
            fontSize: 18
        )

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            loseConditions: [
                WinLoseCondition(kind: .contactRole, contactRole: .hazard)
            ],
            scoreHUDEntityName: "scoreLabel"
        )

        let recipe = GameRecipe(
            sceneName: "AsteroidsDodge",
            sceneSize: SizeSpec(width: 800, height: 600),
            entities: [ship, asteroid, spawnerNode, scoreHUD],
            gameState: gameState
        )

        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // MARK: Node names
        let nodeNames = Set(result.nodes.map(\.name))
        #expect(nodeNames.contains("ship"))
        // Multiple asteroids: asteroid_1 … asteroid_6
        for i in 1...6 {
            #expect(nodeNames.contains("asteroid_\(i)"))
        }
        #expect(nodeNames.contains("scoreLabel"))

        // MARK: Physics categories
        let shipNode = result.nodes.first { $0.name == "ship" }
        #expect(shipNode != nil)
        // Player bit = 1<<1 = 2
        #expect(shipNode?.physicsBody?.categoryBitmask == (1 << 1))

        let asteroidNode = result.nodes.first { $0.name == "asteroid_1" }
        #expect(asteroidNode != nil)
        // Hazard bit = 1<<7 = 128
        #expect(asteroidNode?.physicsBody?.categoryBitmask == (1 << 7))

        // MARK: Script validity
        assertScriptParses(result.sceneScript, "asteroidsDodge")
        #expect(result.sceneScript.contains("on keyDown"))
        #expect(result.sceneScript.contains("on frameUpdate"))
        #expect(result.sceneScript.contains("on beginContact"))

        // MARK: No diagnostics from a well-formed recipe
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - Intent fidelity: name, art, scene size preserved verbatim

    @Test("intent fidelity: entity name, assetRef, and scene size honored verbatim")
    func intentFidelity() throws {
        // Build a test asset repository with one known asset.
        let testAsset = Asset(
            id: UUID(),
            name: "myShipSprite",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0x89, 0x50, 0x4E, 0x47]),  // minimal PNG header bytes
            width: 64,
            height: 64
        )
        let repository = AssetRepository(assets: [testAsset])

        let entity = GameEntity(
            name: "myShip",
            role: .player,
            position: PointSpec(x: 200, y: 300),
            size: SizeSpec(width: 64, height: 64),
            artRoleRef: "shipArt",
            behaviors: [Behavior(kind: .topDownMovement)]
        )

        let recipe = GameRecipe(
            sceneName: "myArena",
            sceneSize: SizeSpec(width: 400, height: 600),
            entities: [entity],
            artRoles: [
                ArtRoleBinding(role: "shipArt", assetName: "myShipSprite")
            ]
        )

        let result = RecipeCompiler.compile(recipe, repository: repository)

        // Entity name preserved verbatim.
        let shipNode = try #require(result.nodes.first { $0.name == "myShip" })
        #expect(shipNode.name == "myShip")

        // Asset resolved correctly.
        #expect(shipNode.assetRef?.id == testAsset.id)
        #expect(shipNode.assetRef?.name == "myShipSprite")

        // Node type should be sprite when asset is resolved.
        #expect(shipNode.nodeType == .sprite)

        // Owned names include the entity.
        #expect(result.recipeOwnedNodeNames.contains("myShip"))

        // Script parseable.
        assertScriptParses(result.sceneScript, "intentFidelity")
    }

    // MARK: - Missing asset falls back to shape with diagnostic

    @Test("missing art asset produces shape node and diagnostic")
    func missingArtAssetFallback() {
        let entity = GameEntity(
            name: "ghost",
            role: .enemy,
            size: SizeSpec(width: 48, height: 48),
            artRoleRef: "ghostArt"
        )
        let recipe = GameRecipe(
            entities: [entity],
            artRoles: [
                // Asset name is set but not in repository.
                ArtRoleBinding(role: "ghostArt", assetName: "nonexistent_sprite")
            ]
        )
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // Node should fall back to a shape.
        let node = result.nodes.first { $0.name == "ghost" }
        #expect(node?.nodeType == .shape)
        #expect(node?.shapeSpec != nil)

        // A diagnostic should be emitted.
        let hasArtDiagnostic = result.diagnostics.contains { $0.contains("ghost") || $0.contains("ghostArt") }
        #expect(hasArtDiagnostic)
    }

    // MARK: - Multi-count entity produces correctly named instances

    @Test("entity with count>1 produces name_1..name_N nodes")
    func multiCountEntityNames() {
        let enemy = GameEntity(
            name: "goomba",
            role: .enemy,
            size: SizeSpec(width: 48, height: 48),
            count: 3
        )
        let recipe = GameRecipe(entities: [enemy])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        let nodeNames = result.nodes.map(\.name)
        #expect(nodeNames.contains("goomba_1"))
        #expect(nodeNames.contains("goomba_2"))
        #expect(nodeNames.contains("goomba_3"))
        // No bare "goomba".
        #expect(!nodeNames.contains("goomba"))
    }

    // MARK: - Name collision deduplication

    @Test("duplicate entity names are deduplicated with diagnostic")
    func nameCollisionDeduplication() {
        let e1 = GameEntity(name: "rock", role: .hazard, size: SizeSpec(width: 40, height: 40))
        let e2 = GameEntity(name: "rock", role: .enemy,  size: SizeSpec(width: 40, height: 40))
        let recipe = GameRecipe(entities: [e1, e2])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        let nodeNames = result.nodes.map(\.name)
        // Both should be present with distinct names.
        #expect(nodeNames.count == 2)
        #expect(Set(nodeNames).count == 2)

        // A collision diagnostic should be reported.
        let hasDiagnostic = result.diagnostics.contains { $0.contains("rock") }
        #expect(hasDiagnostic)

        // Script still parses.
        assertScriptParses(result.sceneScript, "name collision")
    }

    // MARK: - HUD entity becomes a label node

    @Test("hud entity compiles to a label node")
    func hudEntityBecomesLabel() {
        let hud = GameEntity(
            name: "scoreDisplay",
            role: .hud,
            position: PointSpec(x: 400, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0",
            fontSize: 18,
            fontColor: "#FFFF00"
        )
        let recipe = GameRecipe(entities: [hud])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        let node = result.nodes.first { $0.name == "scoreDisplay" }
        #expect(node?.nodeType == .label)
        #expect(node?.text == "Score: 0")
        #expect(node?.fontSize == 18)
        #expect(node?.fontColor == "#FFFF00")
        // HUD nodes should have no physics body.
        #expect(node?.physicsBody == nil)
    }

    // MARK: - Spawner entity produces frameUpdate with create sprite

    @Test("spawner entity compiles to a frameUpdate with create sprite")
    func spawnerProducesCreateSprite() {
        let enemy = GameEntity(name: "meteor", role: .hazard, size: SizeSpec(width: 48, height: 48))
        let spawnerEnt = GameEntity(
            name: "meteorSpawner",
            role: .spawner,
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "hazard",
                    "interval": "2.0",
                    "fromEdge": "top",
                    "velocity": "0,100",
                    "max": "5"
                ])
            ]
        )
        let recipe = GameRecipe(entities: [enemy, spawnerEnt])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "spawner recipe")
        #expect(result.sceneScript.contains("create sprite"))
        #expect(result.sceneScript.contains("on frameUpdate"))
    }

    // MARK: - recipeOwnedNodeNames is complete

    @Test("recipeOwnedNodeNames contains all compiled node names")
    func ownedNamesComplete() {
        let player = GameEntity(name: "hero", role: .player, size: SizeSpec(width: 64, height: 64))
        let enemy = GameEntity(name: "foe", role: .enemy, size: SizeSpec(width: 48, height: 48), count: 2)
        let recipe = GameRecipe(entities: [player, enemy])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        for node in result.nodes {
            #expect(result.recipeOwnedNodeNames.contains(node.name))
        }
    }
}

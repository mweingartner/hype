import Testing
import Foundation
@testable import HypeCore

// Tests for `GameRecipe`, `Behavior`, and the `SpriteAreaSpec.recipe`
// persistence field introduced in phase 1 of the declarative game-authoring
// system. All decode paths exercise the tolerant `init(from:)` decoders;
// encode/decode round-trips verify `Equatable` identity.

// MARK: - Helpers (file-private free functions so @Test methods can call them)

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

@Suite("GameRecipe codec — round-trip, tolerance, and backward compatibility")
struct GameRecipeCodecTests {

    // MARK: - Full round-trip: GameRecipe

    @Test("fully-populated GameRecipe encodes and decodes back to identical value")
    func fullRecipeRoundTrip() throws {
        let player = GameEntity(
            id: UUID(),
            name: "hero",
            role: .player,
            position: PointSpec(x: 100, y: 200),
            size: SizeSpec(width: 64, height: 64),
            count: 1,
            artRoleRef: "hero_art",
            placeholderColor: "#4488FF",
            zPosition: 10,
            behaviors: [
                Behavior(kind: .platformerMovement, params: ["speed": "240", "jumpForce": "700"]),
                Behavior(kind: .health, params: ["max": "5"]),
                Behavior(kind: .loseOnZeroHealth, params: [:])
            ],
            initialText: nil,
            fontSize: nil,
            fontColor: nil
        )

        let enemy = GameEntity(
            id: UUID(),
            name: "goomba",
            role: .enemy,
            position: PointSpec(x: 400, y: 200),
            size: SizeSpec(width: 48, height: 48),
            count: 3,
            artRoleRef: nil,
            placeholderColor: "#FF4422",
            zPosition: 5,
            behaviors: [
                Behavior(kind: .patrol, params: ["axis": "x", "range": "150"]),
                Behavior(kind: .damageOnContact, params: ["amount": "1", "targetRole": "player"])
            ],
            initialText: nil,
            fontSize: nil,
            fontColor: nil
        )

        let coin = GameEntity(
            id: UUID(),
            name: "coin",
            role: .collectible,
            position: PointSpec(x: 250, y: 300),
            size: SizeSpec(width: 32, height: 32),
            count: 10,
            artRoleRef: "coin_art",
            placeholderColor: "#FFDD00",
            zPosition: 5,
            behaviors: [
                Behavior(kind: .collectible, params: [:]),
                Behavior(kind: .scoreOnCollect, params: ["points": "10"])
            ],
            initialText: nil,
            fontSize: nil,
            fontColor: nil
        )

        let scoreHUD = GameEntity(
            id: UUID(),
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: 50, y: 570),
            size: SizeSpec(width: 200, height: 40),
            count: 1,
            artRoleRef: nil,
            placeholderColor: nil,
            zPosition: 100,
            behaviors: [],
            initialText: "Score: 0",
            fontSize: 24,
            fontColor: "#FFFFFF"
        )

        let contactRule = GameRule(
            id: UUID(),
            trigger: RuleTrigger(
                kind: .onContact,
                roleA: .player,
                roleB: .collectible,
                entityName: nil,
                key: nil,
                seconds: nil,
                scoreThreshold: nil
            ),
            conditions: [
                RuleCondition(kind: .always, stateVar: nil, value: nil)
            ],
            actions: [
                RuleAction(kind: .addScore, amount: 10, entityName: nil, message: nil),
                RuleAction(kind: .destroyOther, amount: nil, entityName: nil, message: nil)
            ]
        )

        let winRule = GameRule(
            id: UUID(),
            trigger: RuleTrigger(kind: .onScoreReached, scoreThreshold: 100),
            conditions: [],
            actions: [RuleAction(kind: .winGame, message: "You Win!")]
        )

        let state = GameState(
            trackScore: true,
            initialScore: 0,
            trackLives: true,
            initialLives: 3,
            trackLevel: false,
            initialLevel: 1,
            trackTimer: false,
            initialTimerSeconds: 60,
            winConditions: [
                WinLoseCondition(kind: .reachScore, scoreThreshold: 100, statusMessage: "Winner!")
            ],
            loseConditions: [
                WinLoseCondition(kind: .zeroLives, statusMessage: "Game Over")
            ],
            scoreHUDEntityName: "scoreLabel",
            livesHUDEntityName: nil,
            statusHUDEntityName: nil
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "ArrowLeft", action: .moveLeft, magnitude: 200),
            ControlBinding(key: "ArrowRight", action: .moveRight, magnitude: 200),
            ControlBinding(key: "Space", action: .jump, magnitude: 620)
        ]

        let artRoles: [ArtRoleBinding] = [
            ArtRoleBinding(role: "hero_art", assetName: "hero_sheet", generate: false),
            ArtRoleBinding(role: "coin_art", assetName: nil, generate: true,
                           generationPrompt: "gold coin pixel art, top-down, transparent bg")
        ]

        let recipe = GameRecipe(
            recipeSchemaVersion: 1,
            presetID: "platformer_basic",
            sceneName: "Level 1",
            sceneSize: SizeSpec(width: 800, height: 600),
            backgroundColor: "#101018",
            gravity: VectorSpec(dx: 0, dy: -9.8),
            entities: [player, enemy, coin, scoreHUD],
            rules: [contactRule, winRule],
            gameState: state,
            controls: controls,
            artRoles: artRoles,
            notes: "Classic platformer recipe"
        )

        let decoded = try roundTrip(recipe)
        #expect(decoded == recipe)
        #expect(decoded.entities.count == 4)
        #expect(decoded.rules.count == 2)
        #expect(decoded.controls.count == 3)
        #expect(decoded.artRoles.count == 2)
        #expect(decoded.gameState.trackScore == true)
        #expect(decoded.gameState.winConditions.count == 1)
        #expect(decoded.gameState.loseConditions.count == 1)
        #expect(decoded.entities[0].behaviors.count == 3)
        #expect(decoded.entities[0].behaviors[0].kind == .platformerMovement)
        #expect(decoded.entities[0].behaviors[0].params["speed"] == "240")
        #expect(decoded.artRoles[1].generate == true)
    }

    // MARK: - Tolerant decode: unknown EntityRole

    @Test("unknown role string decodes to .decoration")
    func unknownRoleDecodesToDecoration() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "mystery",
            "role": "boss_minion",
            "position": {"x": 0, "y": 0},
            "size": {"width": 32, "height": 32},
            "count": 1,
            "zPosition": 0,
            "behaviors": []
        }
        """
        let entity = try JSONDecoder().decode(GameEntity.self, from: json.data(using: .utf8)!)
        #expect(entity.role == .decoration)
        #expect(entity.name == "mystery")
    }

    // MARK: - Tolerant decode: unknown behavior kind dropped

    @Test("unknown behavior kind is dropped; known behaviors on the same entity survive")
    func unknownBehaviorKindIsDropped() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "hero",
            "role": "player",
            "position": {"x": 0, "y": 0},
            "size": {"width": 64, "height": 64},
            "count": 1,
            "zPosition": 0,
            "behaviors": [
                {"kind": "platformerMovement", "params": {"speed": "200"}},
                {"kind": "flyingSquidBehavior", "params": {}},
                {"kind": "health", "params": {"max": "3"}}
            ]
        }
        """
        let entity = try JSONDecoder().decode(GameEntity.self, from: json.data(using: .utf8)!)
        // The unknown "flyingSquidBehavior" must be dropped.
        #expect(entity.behaviors.count == 2)
        #expect(entity.behaviors[0].kind == .platformerMovement)
        #expect(entity.behaviors[1].kind == .health)
    }

    // MARK: - Tolerant decode: missing optional fields use defaults

    @Test("GameRecipe decodes from minimal JSON using all defaults")
    func minimalRecipeDecodesWithDefaults() throws {
        let json = #"{"sceneName":"Mini Game"}"#
        let recipe = try JSONDecoder().decode(GameRecipe.self, from: json.data(using: .utf8)!)
        #expect(recipe.sceneName == "Mini Game")
        #expect(recipe.recipeSchemaVersion == 1)
        #expect(recipe.sceneSize.width == 800)
        #expect(recipe.sceneSize.height == 600)
        #expect(recipe.backgroundColor == "#101018")
        #expect(recipe.gravity.dx == 0)
        #expect(recipe.gravity.dy == 0)
        #expect(recipe.entities.isEmpty)
        #expect(recipe.rules.isEmpty)
        #expect(recipe.controls.isEmpty)
        #expect(recipe.artRoles.isEmpty)
        #expect(recipe.notes == "")
        #expect(recipe.gameState.trackScore == false)
        #expect(recipe.gameState.initialLives == 0)
    }

    @Test("GameEntity decodes from minimal JSON using all defaults")
    func minimalEntityDecodesWithDefaults() throws {
        let json = #"{"name":"blob"}"#
        let entity = try JSONDecoder().decode(GameEntity.self, from: json.data(using: .utf8)!)
        #expect(entity.name == "blob")
        #expect(entity.role == .decoration)
        #expect(entity.count == 1)
        #expect(entity.zPosition == 0)
        #expect(entity.behaviors.isEmpty)
        #expect(entity.initialText == nil)
        #expect(entity.fontSize == nil)
    }

    @Test("ControlBinding with unknown action decodes to .none")
    func unknownControlActionDecodesToNone() throws {
        let json = #"{"key":"Tab","action":"openInventory"}"#
        let binding = try JSONDecoder().decode(ControlBinding.self, from: json.data(using: .utf8)!)
        #expect(binding.key == "Tab")
        #expect(binding.action == .none)
    }

    // MARK: - SpriteAreaSpec with recipe round-trips via toStoredJSON/fromStoredJSON

    @Test("SpriteAreaSpec with a non-nil recipe round-trips via toStoredJSON/fromStoredJSON")
    func spriteAreaSpecWithRecipeRoundTrips() throws {
        let recipe = GameRecipe(
            sceneName: "Arcade Game",
            entities: [
                GameEntity(
                    name: "player",
                    role: .player,
                    behaviors: [Behavior(kind: .topDownMovement, params: ["speed": "200"])]
                )
            ]
        )

        var spec = SpriteAreaSpec(
            defaultSceneNamed: "main",
            fallbackSize: SizeSpec(width: 800, height: 600)
        )
        spec.recipe = recipe

        let json = spec.toStoredJSON()
        let recovered = SpriteAreaSpec.fromJSON(json)
        let recoveredRecipe = try #require(recovered?.recipe)
        #expect(recoveredRecipe == recipe)
        #expect(recoveredRecipe.sceneName == "Arcade Game")
        #expect(recoveredRecipe.entities.count == 1)
        #expect(recoveredRecipe.entities[0].behaviors[0].kind == .topDownMovement)
    }

    // MARK: - Backward compatibility: SpriteAreaSpec JSON without "recipe" key

    @Test("SpriteAreaSpec JSON without 'recipe' key decodes with recipe == nil")
    func legacySpriteAreaSpecHasNilRecipe() throws {
        // Hand-written JSON matching the SpriteAreaSpec format but without
        // the 'recipe' field — simulates a doc written before this feature.
        let sceneID = UUID()
        let sceneEntryID = UUID()
        let legacyJSON = """
        {
            "activeSceneID": "\(sceneID)",
            "scenes": [
                {
                    "id": "\(sceneEntryID)",
                    "scene": {
                        "name": "main",
                        "size": {"width": 400, "height": 300},
                        "backgroundColor": "#FFFFFF",
                        "gravity": {"dx": 0, "dy": -9.8},
                        "nodes": [],
                        "joints": [],
                        "sceneConstraints": [],
                        "fields": [],
                        "script": "",
                        "isPaused": false,
                        "showsPhysics": false,
                        "showsFPS": false,
                        "showsNodeCount": false
                    }
                }
            ],
            "designSize": {"width": 400, "height": 300},
            "scaleMode": "aspectFit",
            "showsPhysics": false,
            "showsFPS": false,
            "showsNodeCount": false
        }
        """

        let spec = try JSONDecoder().decode(SpriteAreaSpec.self, from: legacyJSON.data(using: .utf8)!)
        #expect(spec.recipe == nil)
        #expect(spec.activeScene != nil)

        // Re-encode and re-decode to verify no version bump is introduced.
        let reencoded = spec.toStoredJSON()
        let reDecoded = SpriteAreaSpec.fromJSON(reencoded)
        #expect(reDecoded?.recipe == nil)
        #expect(reDecoded?.activeScene?.name == "main")
    }

    // MARK: - Backward compatibility: legacy single-SceneSpec JSON migrates via Part extension path

    @Test("legacy single-SceneSpec JSON still loads via fromStoredJSON migration path with recipe == nil")
    func legacySingleSceneSpecMigratesViaStoredPath() throws {
        // This is the pre-SpriteAreaSpec format: a bare SceneSpec JSON.
        let legacyJSON = """
        {
            "name": "OldScene",
            "size": {"width": 600, "height": 400},
            "backgroundColor": "#CCCCCC",
            "gravity": {"dx": 0, "dy": -9.8},
            "nodes": [],
            "joints": [],
            "sceneConstraints": [],
            "fields": [],
            "script": "",
            "isPaused": false,
            "showsPhysics": false,
            "showsFPS": false,
            "showsNodeCount": false
        }
        """

        let fallbackSize = SizeSpec(width: 600, height: 400)
        let spec = try #require(SpriteAreaSpec.fromStoredJSON(legacyJSON, fallbackSize: fallbackSize))
        #expect(spec.recipe == nil)
        #expect(spec.activeScene != nil)
        #expect(spec.activeScene?.name == "OldScene")
    }

    // MARK: - Behavior round-trip

    @Test("Behavior with params encodes and decodes correctly")
    func behaviorRoundTrip() throws {
        let behavior = Behavior(kind: .spawner, params: [
            "spawnRole": "enemy",
            "interval": "2.0",
            "fromEdge": "top",
            "max": "5"
        ])
        let decoded = try roundTrip(behavior)
        #expect(decoded == behavior)
        #expect(decoded.kind == .spawner)
        #expect(decoded.params["interval"] == "2.0")
    }

    @Test("Behavior with unknown kind throws during decode")
    func behaviorUnknownKindThrows() throws {
        let json = #"{"kind":"teleportation","params":{}}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Behavior.self, from: json.data(using: .utf8)!)
        }
    }

    // MARK: - WinLoseCondition

    @Test("WinLoseCondition with collectibleRole round-trips")
    func winLoseConditionRoundTrip() throws {
        let condition = WinLoseCondition(
            kind: .allCollected,
            collectibleRole: .collectible,
            statusMessage: "All coins collected!"
        )
        let decoded = try roundTrip(condition)
        #expect(decoded == condition)
        #expect(decoded.collectibleRole == .collectible)
    }

    // MARK: - GameState defaults

    @Test("GameState decodes from empty JSON with all-false defaults")
    func gameStateEmptyDefaults() throws {
        let state = try JSONDecoder().decode(GameState.self, from: "{}".data(using: .utf8)!)
        #expect(state.trackScore == false)
        #expect(state.initialScore == 0)
        #expect(state.trackLives == false)
        #expect(state.initialLives == 0)
        #expect(state.trackLevel == false)
        #expect(state.trackTimer == false)
        #expect(state.winConditions.isEmpty)
        #expect(state.loseConditions.isEmpty)
        #expect(state.scoreHUDEntityName == nil)
    }

    // MARK: - EntityRole decodeTolerant

    @Test("EntityRole.decodeTolerant maps all known raw values correctly")
    func entityRoleDecodeTolerantAllCases() {
        for role in EntityRole.allCases {
            #expect(EntityRole.decodeTolerant(role.rawValue) == role)
        }
        #expect(EntityRole.decodeTolerant("unknown_role") == .decoration)
        #expect(EntityRole.decodeTolerant("") == .decoration)
    }

    // MARK: - BehaviorKind.decodeTolerant

    @Test("BehaviorKind.decodeTolerant returns nil for unknown strings")
    func behaviorKindDecodeTolerantUnknown() {
        #expect(BehaviorKind.decodeTolerant("flyingSquid") == nil)
        #expect(BehaviorKind.decodeTolerant("") == nil)
    }

    @Test("BehaviorKind.decodeTolerant returns correct values for all known kinds")
    func behaviorKindDecodeTolerantAllCases() {
        for kind in BehaviorKind.allCases {
            #expect(BehaviorKind.decodeTolerant(kind.rawValue) == kind)
        }
    }
}

import Foundation
import Testing
@testable import HypeCore

// MARK: - Parse helpers

private func assertScriptParses(_ script: String, _ label: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    var lexer = Lexer(source: script)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    do {
        _ = try parser.parse()
    } catch {
        Issue.record(
            "Script parse failed\(label.isEmpty ? "" : " [\(label)]"): \(error)\n\nScript:\n\(script)",
            sourceLocation: sourceLocation
        )
    }
}

private func isSentinel(_ result: String) -> Bool {
    result.hasPrefix("__HYPE_INTERNAL_DRAFT_REFUSED_v1:")
}

// MARK: - Shared builder

private func freshDoc() -> (HypeDocument, UUID) {
    let doc = HypeDocument.newDocument(name: "GameRecipeTest")
    let cardId = doc.sortedCards[0].id
    return (doc, cardId)
}

private func spriteAreaCount(_ document: HypeDocument) -> Int {
    document.parts.filter { $0.partType == .spriteArea }.count
}

// MARK: - GameRecipeToolTests

@Suite("GameRecipeExecutorBranches — tool execution paths")
struct GameRecipeToolTests {

    // MARK: - start_game_recipe

    @Test("start_game_recipe creates sprite area with honoured scene size")
    func startGameRecipeCreatesArea() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()
        let initialCount = spriteAreaCount(doc)

        let result = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "arena",
                "scene_name": "main",
                "scene_width": "480",
                "scene_height": "640",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(!result.isEmpty)
        #expect(spriteAreaCount(doc) == initialCount + 1)

        let part = doc.parts.first(where: { $0.name == "arena" })
        let recipe = part?.spriteAreaSpecModel?.recipe
        #expect(recipe != nil)
        #expect(recipe?.sceneSize.width == 480)
        #expect(recipe?.sceneSize.height == 640)
        #expect(recipe?.sceneName == "main")
        #expect(recipe?.entities.isEmpty == true)
    }

    @Test("start_game_recipe honours background_color and gravity")
    func startGameRecipeHonoursOptions() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "spaceGame",
                "scene_width": "800",
                "scene_height": "600",
                "background_color": "#000020",
                "gravity": "0,-9.8",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let recipe = doc.parts.first(where: { $0.name == "spaceGame" })?.spriteAreaSpecModel?.recipe
        #expect(recipe?.backgroundColor == "#000020")
        #expect(recipe?.gravity.dx == 0)
        #expect(recipe?.gravity.dy == -9.8)
    }

    @Test("start_game_recipe fail-closed: require_existing_scene=true + no area → error, no mutation")
    func startGameRecipeFailClosed() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()
        let before = spriteAreaCount(doc)

        let result = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "nonexistent",
                "require_existing_scene": "true",
            ],
            document: &doc,
            currentCardId: cardId
        )

        // Should return an error and NOT create a new sprite area.
        #expect(!result.isEmpty)
        #expect(spriteAreaCount(doc) == before)
        // The error message should reference the missing area.
        #expect(result.lowercased().contains("not found") || result.lowercased().contains("require_existing"))
    }

    // MARK: - add_entity

    @Test("add_entity preserves name verbatim and parses behaviors")
    func addEntityPreservesNameAndBehaviors() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: ["sprite_area_name": "arena", "scene_width": "800", "scene_height": "600"],
            document: &doc,
            currentCardId: cardId
        )

        let result = await executor.execute(
            toolName: "add_entity",
            arguments: [
                "sprite_area_name": "arena",
                "name": "my_ship",
                "role": "player",
                "x": "400",
                "y": "100",
                "width": "64",
                "height": "64",
                "behaviors": "topDownMovement:speed=200,constrainToBounds",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(!result.isEmpty)

        let recipe = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe
        let entity = recipe?.entities.first(where: { $0.name == "my_ship" })
        #expect(entity != nil)
        // Name preserved verbatim
        #expect(entity?.name == "my_ship")
        #expect(entity?.role == .player)
        #expect(entity?.position.x == 400)
        #expect(entity?.behaviors.count == 2)
        #expect(entity?.behaviors.first?.kind == .topDownMovement)
        #expect(entity?.behaviors.first?.params["speed"] == "200")
        #expect(entity?.behaviors[1].kind == .constrainToBounds)
    }

    @Test("add_entity parses behavior with multiple params via colon+semicolons")
    func addEntityParsesComplexBehaviorParams() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: ["sprite_area_name": "arena"],
            document: &doc,
            currentCardId: cardId
        )

        _ = await executor.execute(
            toolName: "add_entity",
            arguments: [
                "sprite_area_name": "arena",
                "name": "asteroid",
                "role": "hazard",
                "count": "6",
                "behaviors": "destroyOutsideBounds:margin=80,spawner:interval=1.5;spawnRole=enemy",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let recipe = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe
        let entity = recipe?.entities.first(where: { $0.name == "asteroid" })
        #expect(entity?.count == 6)
        let dob = entity?.behaviors.first(where: { $0.kind == .destroyOutsideBounds })
        #expect(dob?.params["margin"] == "80")
        let spawner = entity?.behaviors.first(where: { $0.kind == .spawner })
        #expect(spawner?.params["interval"] == "1.5")
        #expect(spawner?.params["spawnRole"] == "enemy")
    }

    @Test("add_entity with unknown behavior kind returns error")
    func addEntityUnknownBehaviorReturnsError() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: ["sprite_area_name": "arena"],
            document: &doc,
            currentCardId: cardId
        )

        let result = await executor.execute(
            toolName: "add_entity",
            arguments: [
                "sprite_area_name": "arena",
                "name": "ship",
                "behaviors": "topDownMovement,fliesWithMagic",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.lowercased().contains("unknown behavior") || result.lowercased().contains("valid kinds"))
        // Entity should NOT have been added.
        let recipe = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe
        #expect(recipe?.entities.first(where: { $0.name == "ship" }) == nil)
    }

    @Test("add_entity requires name")
    func addEntityRequiresName() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: ["sprite_area_name": "arena"],
            document: &doc,
            currentCardId: cardId
        )

        let result = await executor.execute(
            toolName: "add_entity",
            arguments: ["sprite_area_name": "arena", "role": "player"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.lowercased().contains("name"))
    }

    // MARK: - attach_behavior / detach_behavior

    @Test("attach_behavior adds behavior to existing entity")
    func attachBehaviorMutatesEntity() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena"], document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "add_entity",
                                   arguments: ["sprite_area_name": "arena", "name": "ship", "role": "player"],
                                   document: &doc, currentCardId: cardId)

        let result = await executor.execute(
            toolName: "attach_behavior",
            arguments: [
                "sprite_area_name": "arena",
                "entity_name": "ship",
                "behavior": "constrainToBounds",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(!result.lowercased().contains("error"))
        let recipe = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe
        let entity = recipe?.entities.first(where: { $0.name == "ship" })
        #expect(entity?.behaviors.contains(where: { $0.kind == .constrainToBounds }) == true)
    }

    @Test("detach_behavior removes behavior from entity")
    func detachBehaviorMutatesEntity() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena"], document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "add_entity",
                                   arguments: ["sprite_area_name": "arena", "name": "ship", "role": "player",
                                               "behaviors": "topDownMovement,constrainToBounds"],
                                   document: &doc, currentCardId: cardId)

        _ = await executor.execute(
            toolName: "detach_behavior",
            arguments: [
                "sprite_area_name": "arena",
                "entity_name": "ship",
                "behavior": "topDownMovement",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let recipe = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe
        let entity = recipe?.entities.first(where: { $0.name == "ship" })
        #expect(entity?.behaviors.contains(where: { $0.kind == .topDownMovement }) == false)
        #expect(entity?.behaviors.contains(where: { $0.kind == .constrainToBounds }) == true)
    }

    @Test("attach_behavior: entity not found returns error")
    func attachBehaviorEntityNotFound() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena"], document: &doc, currentCardId: cardId)

        let result = await executor.execute(
            toolName: "attach_behavior",
            arguments: ["sprite_area_name": "arena", "entity_name": "ghost", "behavior": "constrainToBounds"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.lowercased().contains("not found"))
    }

    // MARK: - build_game

    @Test("build_game: recipe compiles and stored scene script parses")
    func buildGameScriptParses() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena", "scene_width": "800", "scene_height": "600"],
                                   document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "add_entity",
                                   arguments: ["sprite_area_name": "arena", "name": "ship", "role": "player",
                                               "x": "400", "y": "100",
                                               "behaviors": "topDownMovement,constrainToBounds"],
                                   document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "add_entity",
                                   arguments: ["sprite_area_name": "arena", "name": "rock", "role": "hazard",
                                               "x": "200", "y": "500", "count": "3"],
                                   document: &doc, currentCardId: cardId)

        let result = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "arena"],
            document: &doc,
            currentCardId: cardId
        )

        // Should NOT be a sentinel.
        #expect(!isSentinel(result))

        let storedScript = doc.parts.first(where: { $0.name == "arena" })?.activeSceneSpec?.script
        #expect(storedScript != nil)
        if let script = storedScript, !script.isEmpty {
            assertScriptParses(script, "build_game compiled script")
        }
    }

    @Test("build_game: fail-closed with no recipe returns error")
    func buildGameFailClosedNoRecipe() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        // Create a sprite area but no recipe.
        var part = Part(partType: .spriteArea, cardId: cardId, name: "arena",
                        left: 0, top: 0, width: 400, height: 300)
        part.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main",
                                              fallbackSize: SizeSpec(width: 400, height: 300)))
        doc.addPart(part)

        let result = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "arena"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.lowercased().contains("no recipe") || result.lowercased().contains("start_game_recipe"))
    }

    @Test("build_game: fail-closed with 0 sprite areas returns error, no new area created")
    func buildGameFailClosedNoArea() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()
        let before = spriteAreaCount(doc)

        let result = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "nonexistent"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.lowercased().contains("not found"))
        #expect(spriteAreaCount(doc) == before)
    }

    @Test("build_game: result is not a sentinel (script gate passes for compiler-generated script)")
    func buildGameScriptGatePasses() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena"],
                                   document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "add_entity",
                                   arguments: ["sprite_area_name": "arena", "name": "ship", "role": "player",
                                               "behaviors": "topDownMovement"],
                                   document: &doc, currentCardId: cardId)

        let result = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "arena"],
            document: &doc,
            currentCardId: cardId
        )

        // Compiler-generated script is always valid; gate should pass.
        #expect(!isSentinel(result))

        // Stored script should parse.
        let script = doc.parts.first(where: { $0.name == "arena" })?.activeSceneSpec?.script ?? ""
        if !script.isEmpty {
            assertScriptParses(script, "gate-passed script")
        }
    }

    // MARK: - Transaction: start → add_entity → build_game

    @Test("transaction: start + add_entity + build_game leaves recipe and scene present")
    func transactionStartAddBuild() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "game", "scene_width": "480", "scene_height": "640"],
                                   document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "add_entity",
                                   arguments: ["sprite_area_name": "game", "name": "player", "role": "player",
                                               "behaviors": "topDownMovement"],
                                   document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "build_game",
                                   arguments: ["sprite_area_name": "game"],
                                   document: &doc, currentCardId: cardId)

        let part = doc.parts.first(where: { $0.name == "game" })
        #expect(part != nil)
        #expect(part?.spriteAreaSpecModel?.recipe != nil)
        let scene = part?.activeSceneSpec
        #expect(scene != nil)
        #expect(scene?.size.width == 480)
        #expect(scene?.size.height == 640)
        // Node named "player" should appear.
        #expect(scene?.nodes.contains(where: { $0.name == "player" }) == true)
    }

    // MARK: - set_game_state

    @Test("set_game_state updates tracking flags and HUD names")
    func setGameStateUpdates() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena"],
                                   document: &doc, currentCardId: cardId)

        _ = await executor.execute(
            toolName: "set_game_state",
            arguments: [
                "sprite_area_name": "arena",
                "track_score": "true",
                "initial_score": "0",
                "track_lives": "true",
                "initial_lives": "3",
                "win": "reachScore:100",
                "lose": "zeroLives",
                "score_hud": "scoreLabel",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let gs = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe?.gameState
        #expect(gs?.trackScore == true)
        #expect(gs?.initialLives == 3)
        #expect(gs?.winConditions.first?.kind == .reachScore)
        #expect(gs?.winConditions.first?.scoreThreshold == 100)
        #expect(gs?.loseConditions.first?.kind == .zeroLives)
        #expect(gs?.scoreHUDEntityName == "scoreLabel")
    }

    // MARK: - bind_art_role

    @Test("bind_art_role upserts binding, generate=true marks intent only")
    func bindArtRoleUpserts() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena"],
                                   document: &doc, currentCardId: cardId)

        _ = await executor.execute(
            toolName: "bind_art_role",
            arguments: [
                "sprite_area_name": "arena",
                "role": "playerArt",
                "asset_name": "ship_texture",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let artRoles = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe?.artRoles ?? []
        #expect(artRoles.contains(where: { $0.role == "playerArt" && $0.assetName == "ship_texture" }))

        // Re-bind with generate intent — should update in place, not duplicate.
        _ = await executor.execute(
            toolName: "bind_art_role",
            arguments: [
                "sprite_area_name": "arena",
                "role": "playerArt",
                "generate": "true",
                "prompt": "a metallic spaceship",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let updated = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe?.artRoles ?? []
        // Still only one binding for this role.
        #expect(updated.filter { $0.role == "playerArt" }.count == 1)
        #expect(updated.first(where: { $0.role == "playerArt" })?.generate == true)
        // generate=true must NOT trigger any network calls — just a flag.
        // The repository should remain empty (no side effects).
        #expect(doc.assetRepository.assets.isEmpty)
    }

    // MARK: - set_controls

    @Test("set_controls replaces bindings")
    func setControlsReplaces() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena"],
                                   document: &doc, currentCardId: cardId)

        _ = await executor.execute(
            toolName: "set_controls",
            arguments: [
                "sprite_area_name": "arena",
                "bindings": "left=moveLeft,right=moveRight,up=moveUp,down=moveDown,space=jump",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let controls = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe?.controls ?? []
        #expect(controls.count == 5)
        #expect(controls.contains(where: { $0.key == "left" && $0.action == .moveLeft }))
        #expect(controls.contains(where: { $0.key == "space" && $0.action == .jump }))
    }

    // MARK: - add_rule

    @Test("add_rule appends a rule to the recipe")
    func addRuleAppends() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena"],
                                   document: &doc, currentCardId: cardId)

        _ = await executor.execute(
            toolName: "add_rule",
            arguments: [
                "sprite_area_name": "arena",
                "trigger": "onContact",
                "role_a": "player",
                "role_b": "hazard",
                "actions": "loseGame",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let rules = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe?.rules ?? []
        #expect(rules.count == 1)
        #expect(rules.first?.trigger.kind == .onContact)
        #expect(rules.first?.trigger.roleA == .player)
        #expect(rules.first?.trigger.roleB == .hazard)
        #expect(rules.first?.actions.first?.kind == .loseGame)
    }

    // MARK: - describe_game

    @Test("describe_game returns human-readable summary, does not mutate document")
    func describeGameReadOnly() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "arena", "scene_width": "480", "scene_height": "640"],
                                   document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "add_entity",
                                   arguments: ["sprite_area_name": "arena", "name": "ship", "role": "player"],
                                   document: &doc, currentCardId: cardId)

        let partCountBefore = doc.parts.count
        let result = await executor.execute(
            toolName: "describe_game",
            arguments: ["sprite_area_name": "arena"],
            document: &doc,
            currentCardId: cardId
        )

        // Should mention scene size and entity name.
        #expect(result.contains("480"))
        #expect(result.contains("640"))
        #expect(result.contains("ship"))
        #expect(result.contains("player"))
        // No mutation.
        #expect(doc.parts.count == partCountBefore)
    }
}

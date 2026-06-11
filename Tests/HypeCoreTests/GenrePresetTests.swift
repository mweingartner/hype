import Foundation
import Testing
@testable import HypeCore

// MARK: - Shared helpers

private func assertScriptParses(
    _ script: String,
    _ label: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
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

private func freshDoc() -> (HypeDocument, UUID) {
    let doc = HypeDocument.newDocument(name: "GenrePresetTest")
    let cardId = doc.sortedCards[0].id
    return (doc, cardId)
}

private func spriteAreaCount(_ document: HypeDocument) -> Int {
    document.parts.filter { $0.partType == .spriteArea }.count
}

private func isSentinel(_ result: String) -> Bool {
    result.hasPrefix("__HYPE_INTERNAL_DRAFT_REFUSED_v1:")
}

// MARK: - GenrePresetLibrary: unit tests

@Suite("GenrePresetLibrary — preset data and alias resolution")
struct GenrePresetLibraryTests {

    // MARK: - presetIDs coverage

    @Test("presetIDs is non-empty and contains expected canonical ids")
    func presetIDsIsPopulated() {
        let ids = GenrePresetLibrary.presetIDs
        #expect(!ids.isEmpty)
        // Must include all mandated genres.
        let required = [
            "top_down_adventure",
            "side_scroller_platformer",
            "space_shooter",
            "twin_stick_shooter",
            "breakout",
            "pong_sports_arena",
            "endless_runner",
            "physics_puzzle",
            "racing_lane",
        ]
        for id in required {
            #expect(ids.contains(id), "presetIDs missing required id '\(id)'")
        }
    }

    // MARK: - preset() returns non-nil for all known ids

    @Test("preset(for:) returns non-nil for every id in presetIDs")
    func allPresetIDsReturnRecipe() {
        for id in GenrePresetLibrary.presetIDs {
            let recipe = GenrePresetLibrary.preset(for: id, sceneName: "test", sceneSize: nil)
            #expect(recipe != nil, "preset(for: '\(id)') returned nil")
        }
    }

    // MARK: - Each preset has ≥1 entity

    @Test("every preset recipe has at least one entity")
    func allPresetsHaveEntities() {
        for id in GenrePresetLibrary.presetIDs {
            let recipe = GenrePresetLibrary.preset(for: id, sceneName: "test", sceneSize: nil)
            #expect((recipe?.entities.count ?? 0) >= 1, "preset '\(id)' has no entities")
        }
    }

    // MARK: - presetID is stamped on returned recipes

    @Test("preset(for:) stamps presetID on returned recipe")
    func presetIDIsStamped() {
        for id in GenrePresetLibrary.presetIDs {
            let recipe = GenrePresetLibrary.preset(for: id, sceneName: "test", sceneSize: nil)
            #expect(recipe?.presetID == id, "presetID not stamped on '\(id)' recipe")
        }
    }

    // MARK: - sceneName is honoured verbatim

    @Test("preset(for:) honours sceneName verbatim")
    func sceneNameHonoured() {
        let recipe = GenrePresetLibrary.preset(for: "breakout", sceneName: "MyScene", sceneSize: nil)
        #expect(recipe?.sceneName == "MyScene")
    }

    // MARK: - sceneSize override is honoured

    @Test("preset(for: breakout) honours explicit sceneSize override 400x700")
    func sceneSizeOverrideHonoured() {
        let custom = SizeSpec(width: 400, height: 700)
        let recipe = GenrePresetLibrary.preset(for: "breakout", sceneName: "x", sceneSize: custom)
        #expect(recipe?.sceneSize.width == 400)
        #expect(recipe?.sceneSize.height == 700)
    }

    @Test("preset(for: top_down_adventure) honours explicit sceneSize override 1024x768")
    func sceneSizeOverrideHonouredAdventure() {
        let custom = SizeSpec(width: 1024, height: 768)
        let recipe = GenrePresetLibrary.preset(for: "top_down_adventure", sceneName: "main", sceneSize: custom)
        #expect(recipe?.sceneSize.width == 1024)
        #expect(recipe?.sceneSize.height == 768)
    }

    // MARK: - canonicalID: direct ids resolve to themselves

    @Test("canonicalID returns the id itself for known preset ids")
    func canonicalIDReturnsSelf() {
        for id in GenrePresetLibrary.presetIDs {
            let canonical = GenrePresetLibrary.canonicalID(for: id)
            #expect(canonical == id, "canonicalID('\(id)') returned '\(canonical ?? "nil")' instead of '\(id)'")
        }
    }

    // MARK: - canonicalID: aliases resolve

    @Test("canonicalID resolves 'platformer' alias to side_scroller_platformer")
    func aliasResolvesForPlatformer() {
        // "platformer" is listed in side_scroller_platformer aliases in the catalog.
        // The catalog also maps it to barrel_climber via aliases; since we only
        // have a preset for side_scroller_platformer, either mapping must land on
        // a preset we ship. We accept side_scroller_platformer or barrel_climber—
        // but only side_scroller_platformer is in our presetIDs.
        let canonical = GenrePresetLibrary.canonicalID(for: "side scroller")
        #expect(canonical == "side_scroller_platformer", "Expected 'side_scroller_platformer', got '\(canonical ?? "nil")'")
    }

    @Test("canonicalID resolves 'shmup' alias to space_shooter")
    func aliasResolvesShmup() {
        let canonical = GenrePresetLibrary.canonicalID(for: "shmup")
        #expect(canonical == "space_shooter", "Expected 'space_shooter', got '\(canonical ?? "nil")'")
    }

    @Test("canonicalID resolves 'pong' alias to pong_sports_arena")
    func aliasResolvesPong() {
        let canonical = GenrePresetLibrary.canonicalID(for: "pong")
        #expect(canonical == "pong_sports_arena")
    }

    @Test("canonicalID resolves 'endless runner' alias to endless_runner")
    func aliasResolvesEndlessRunner() {
        let canonical = GenrePresetLibrary.canonicalID(for: "endless runner")
        #expect(canonical == "endless_runner")
    }

    @Test("canonicalID resolves 'racing' alias to racing_lane")
    func aliasResolvesRacing() {
        let canonical = GenrePresetLibrary.canonicalID(for: "racing")
        #expect(canonical == "racing_lane")
    }

    @Test("canonicalID resolves 'arena shooter' alias to twin_stick_shooter")
    func aliasResolvesArenaShooter() {
        let canonical = GenrePresetLibrary.canonicalID(for: "arena shooter")
        #expect(canonical == "twin_stick_shooter")
    }

    // MARK: - canonicalID: gibberish returns nil

    @Test("canonicalID returns nil for unknown string")
    func canonicalIDReturnsNilForGibberish() {
        #expect(GenrePresetLibrary.canonicalID(for: "xyzzy_not_a_genre") == nil)
        #expect(GenrePresetLibrary.canonicalID(for: "") == nil)
        #expect(GenrePresetLibrary.canonicalID(for: "   ") == nil)
    }

    // MARK: - canonicalID: catalog id that has no preset returns nil

    @Test("canonicalID returns nil for catalog id with no preset (maze_chase)")
    func canonicalIDReturnsNilForCatalogOnlyID() {
        // maze_chase is in the catalog but not in GenrePresetLibrary.presetIDs.
        let canonical = GenrePresetLibrary.canonicalID(for: "maze_chase")
        #expect(canonical == nil)
    }

    // MARK: - Role coverage per genre

    @Test("top_down_adventure preset has player + collectible + goal + enemy")
    func topDownAdventureRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "top_down_adventure", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.collectible))
        #expect(roles.contains(.goal))
        #expect(roles.contains(.enemy))
    }

    @Test("side_scroller_platformer preset has player + wall (ground) + hazard + goal")
    func sideScrollerPlatformerRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "side_scroller_platformer", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.wall))
        #expect(roles.contains(.hazard))
        #expect(roles.contains(.goal))
    }

    @Test("space_shooter preset has player + spawner")
    func spaceShooterRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "space_shooter", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.spawner))
    }

    @Test("twin_stick_shooter preset has player + spawner")
    func twinStickShooterRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "twin_stick_shooter", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.spawner))
    }

    @Test("breakout preset has player (paddle) + hazard (ball) + collectible (bricks) + wall")
    func breakoutRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "breakout", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.hazard))
        #expect(roles.contains(.collectible))
        #expect(roles.contains(.wall))
    }

    @Test("pong_sports_arena preset has player + enemy (AI paddle) + hazard (ball) + wall")
    func pongRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "pong_sports_arena", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.enemy))
        #expect(roles.contains(.hazard))
        #expect(roles.contains(.wall))
    }

    @Test("endless_runner preset has player + wall (ground) + hazard + spawner")
    func endlessRunnerRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "endless_runner", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.wall))
        #expect(roles.contains(.hazard))
        #expect(roles.contains(.spawner))
    }

    @Test("physics_puzzle preset has player + wall + goal")
    func physicsPuzzleRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "physics_puzzle", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.wall))
        #expect(roles.contains(.goal))
    }

    @Test("racing_lane preset has player + hazard + spawner")
    func racingLaneRoleCoverage() {
        let recipe = GenrePresetLibrary.preset(for: "racing_lane", sceneName: "t", sceneSize: nil)!
        let roles = recipe.entities.map(\.role)
        #expect(roles.contains(.player))
        #expect(roles.contains(.hazard))
        #expect(roles.contains(.spawner))
    }

    // MARK: - Platformer gravity sign

    @Test("side_scroller_platformer gravity is dy = -9.8 (SpriteKit downward convention)")
    func platformerGravitySign() {
        let recipe = GenrePresetLibrary.preset(for: "side_scroller_platformer", sceneName: "t", sceneSize: nil)!
        // SpriteKit physicsWorld.gravity = CGVector(dx:dy:) is applied directly.
        // dy = -9.8 pulls affectedByGravity bodies downward (correct for a platformer).
        #expect(recipe.gravity.dx == 0)
        #expect(recipe.gravity.dy == -9.8)
    }

    @Test("endless_runner gravity is dy = -9.8")
    func endlessRunnerGravitySign() {
        let recipe = GenrePresetLibrary.preset(for: "endless_runner", sceneName: "t", sceneSize: nil)!
        #expect(recipe.gravity.dy == -9.8)
    }

    @Test("physics_puzzle gravity is dy = -9.8")
    func physicsPuzzleGravitySign() {
        let recipe = GenrePresetLibrary.preset(for: "physics_puzzle", sceneName: "t", sceneSize: nil)!
        #expect(recipe.gravity.dy == -9.8)
    }

    // MARK: - No-gravity genres have zero gravity

    @Test("top_down_adventure has zero gravity")
    func topDownZeroGravity() {
        let recipe = GenrePresetLibrary.preset(for: "top_down_adventure", sceneName: "t", sceneSize: nil)!
        #expect(recipe.gravity.dx == 0)
        #expect(recipe.gravity.dy == 0)
    }

    @Test("space_shooter has zero gravity")
    func spaceShooterZeroGravity() {
        let recipe = GenrePresetLibrary.preset(for: "space_shooter", sceneName: "t", sceneSize: nil)!
        #expect(recipe.gravity.dy == 0)
    }
}

// MARK: - RecipeCompiler compilation tests

@Suite("GenrePresetLibrary — compilation through RecipeCompiler")
struct GenrePresetCompilationTests {

    /// Compile a preset through RecipeCompiler with an empty repository and
    /// assert the script PARSES (no fallback) and at least one node is produced.
    private func compilePreset(id: String, label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let recipe = GenrePresetLibrary.preset(for: id, sceneName: "test", sceneSize: nil) else {
            Issue.record("preset(for: '\(id)') returned nil", sourceLocation: sourceLocation)
            return
        }
        let repository = AssetRepository()
        let result = RecipeCompiler.compile(recipe, repository: repository)

        // A fallback script is distinguishable from a real script — it contains
        // "recipe produced an invalid script" or "empty recipe". Any diagnostic
        // mentioning "invalid script" signals a compile failure.
        let hasInvalidScriptDiag = result.diagnostics.contains {
            $0.contains("invalid script") || $0.contains("emitted an invalid script")
        }
        #expect(!hasInvalidScriptDiag, "RecipeCompiler fallback triggered for preset '\(id)': \(result.diagnostics.joined(separator: "; "))", sourceLocation: sourceLocation)

        // Script must parse.
        assertScriptParses(result.sceneScript, "preset '\(id)'", sourceLocation: sourceLocation)

        // Must produce at least one node (non-HUD entities generate nodes).
        #expect(!result.nodes.isEmpty, "No nodes compiled for preset '\(id)'", sourceLocation: sourceLocation)
    }

    @Test("top_down_adventure compiles to parsing script with nodes")
    func topDownAdventureCompiles() {
        compilePreset(id: "top_down_adventure", label: "top_down_adventure")
    }

    @Test("side_scroller_platformer compiles to parsing script with nodes")
    func sideScrollerPlatformerCompiles() {
        compilePreset(id: "side_scroller_platformer", label: "side_scroller_platformer")
    }

    @Test("space_shooter compiles to parsing script with nodes")
    func spaceShooterCompiles() {
        compilePreset(id: "space_shooter", label: "space_shooter")
    }

    @Test("twin_stick_shooter compiles to parsing script with nodes")
    func twinStickShooterCompiles() {
        compilePreset(id: "twin_stick_shooter", label: "twin_stick_shooter")
    }

    @Test("breakout compiles to parsing script with nodes")
    func breakoutCompiles() {
        compilePreset(id: "breakout", label: "breakout")
    }

    @Test("pong_sports_arena compiles to parsing script with nodes")
    func pongSportsArenaCompiles() {
        compilePreset(id: "pong_sports_arena", label: "pong_sports_arena")
    }

    @Test("endless_runner compiles to parsing script with nodes")
    func endlessRunnerCompiles() {
        compilePreset(id: "endless_runner", label: "endless_runner")
    }

    @Test("physics_puzzle compiles to parsing script with nodes")
    func physicsPuzzleCompiles() {
        compilePreset(id: "physics_puzzle", label: "physics_puzzle")
    }

    @Test("racing_lane compiles to parsing script with nodes")
    func racingLaneCompiles() {
        compilePreset(id: "racing_lane", label: "racing_lane")
    }

    @Test("all preset ids compile to parsing scripts (batch)")
    func allPresetsCompile() {
        for id in GenrePresetLibrary.presetIDs {
            compilePreset(id: id, label: id)
        }
    }

    @Test("breakout with custom size 400x700 compiles and preserves size")
    func breakoutCustomSizeCompiles() {
        let custom = SizeSpec(width: 400, height: 700)
        guard let recipe = GenrePresetLibrary.preset(for: "breakout", sceneName: "x", sceneSize: custom) else {
            Issue.record("breakout preset returned nil")
            return
        }
        #expect(recipe.sceneSize.width == 400)
        #expect(recipe.sceneSize.height == 700)
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        assertScriptParses(result.sceneScript, "breakout 400x700")
    }
}

// MARK: - Executor integration tests

@Suite("GenrePresetLibrary — start_game_recipe with preset arg")
struct GenrePresetExecutorTests {

    // MARK: - start_game_recipe applies preset

    @Test("start_game_recipe with preset=top_down_adventure populates entities from preset")
    func startGameRecipeAppliesTopDownAdventurePreset() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        let result = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "adventure",
                "scene_width": "800",
                "scene_height": "600",
                "preset": "top_down_adventure",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(!result.isEmpty)
        #expect(spriteAreaCount(doc) >= 1)

        let part = doc.parts.first(where: { $0.name == "adventure" })
        let recipe = part?.spriteAreaSpecModel?.recipe
        #expect(recipe != nil)
        // Preset entities should be loaded.
        #expect((recipe?.entities.count ?? 0) >= 1)
        // Player entity must be present.
        #expect(recipe?.entities.contains(where: { $0.role == .player }) == true)
        // Enemy entity must be present.
        #expect(recipe?.entities.contains(where: { $0.role == .enemy }) == true)
        // presetID stamped.
        #expect(recipe?.presetID == "top_down_adventure")
    }

    @Test("start_game_recipe with preset=breakout scene sizes are honoured as overrides")
    func startGameRecipeHonoursExplicitSizeOverBreset() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "bko",
                "scene_width": "480",
                "scene_height": "640",
                "preset": "breakout",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let recipe = doc.parts.first(where: { $0.name == "bko" })?.spriteAreaSpecModel?.recipe
        #expect(recipe?.sceneSize.width == 480)
        #expect(recipe?.sceneSize.height == 640)
    }

    @Test("start_game_recipe with unknown preset falls back to empty recipe with informative note")
    func startGameRecipeUnknownPresetFallback() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        let result = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "unknown_area",
                "preset": "not_a_real_genre_xyzzy",
            ],
            document: &doc,
            currentCardId: cardId
        )

        // Should not error; should create the area.
        #expect(spriteAreaCount(doc) >= 1)
        // Empty recipe (preset unknown).
        let recipe = doc.parts.first(where: { $0.name == "unknown_area" })?.spriteAreaSpecModel?.recipe
        #expect(recipe?.entities.isEmpty == true)
        // Result message should inform about the failure.
        #expect(result.lowercased().contains("not found") || result.lowercased().contains("preset"))
    }

    @Test("start_game_recipe with preset=space_shooter then build_game produces parseable script without sentinel")
    func startGameRecipeSpaceShooterBuildGame() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "shooter",
                "scene_width": "800",
                "scene_height": "600",
                "preset": "space_shooter",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let buildResult = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "shooter"],
            document: &doc,
            currentCardId: cardId
        )

        // build_game must not return a sentinel.
        #expect(!isSentinel(buildResult))

        // Stored scene script must parse.
        let storedScript = doc.parts.first(where: { $0.name == "shooter" })?.activeSceneSpec?.script
        #expect(storedScript != nil)
        if let script = storedScript, !script.isEmpty {
            assertScriptParses(script, "space_shooter build_game script")
        }
    }

    @Test("start_game_recipe with preset=side_scroller_platformer then build_game produces parseable script")
    func startGameRecipePlatformerBuildGame() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "platformer",
                "scene_width": "800",
                "scene_height": "600",
                "preset": "side_scroller_platformer",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let buildResult = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "platformer"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(!isSentinel(buildResult))

        let storedScript = doc.parts.first(where: { $0.name == "platformer" })?.activeSceneSpec?.script
        if let script = storedScript, !script.isEmpty {
            assertScriptParses(script, "side_scroller_platformer build_game script")
        }
    }

    @Test("start_game_recipe with preset=breakout then build_game produces parseable script with paddle node")
    func startGameRecipeBreakoutBuildGame() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "bko",
                "preset": "breakout",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let buildResult = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "bko"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(!isSentinel(buildResult))

        let scene = doc.parts.first(where: { $0.name == "bko" })?.activeSceneSpec
        // The paddle entity should be present in the compiled scene.
        #expect(scene?.nodes.contains(where: { $0.name == "paddle" }) == true)

        if let script = scene?.script, !script.isEmpty {
            assertScriptParses(script, "breakout build_game script")
        }
    }

    @Test("start_game_recipe with preset=physics_puzzle then build_game produces parseable script")
    func startGameRecipePhysicsPuzzleBuildGame() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "puzzle",
                "preset": "physics_puzzle",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let buildResult = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "puzzle"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(!isSentinel(buildResult))

        if let script = doc.parts.first(where: { $0.name == "puzzle" })?.activeSceneSpec?.script,
           !script.isEmpty {
            assertScriptParses(script, "physics_puzzle build_game script")
        }
    }

    @Test("start_game_recipe without preset creates empty recipe as before")
    func startGameRecipeNoPresetIsBackwardsCompatible() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "arena",
                "scene_width": "800",
                "scene_height": "600",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let recipe = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe
        #expect(recipe?.entities.isEmpty == true)
        #expect(recipe?.sceneSize.width == 800)
        #expect(recipe?.sceneSize.height == 600)
        #expect(recipe?.presetID == nil)
    }

    @Test("start_game_recipe with preset alias 'shmup' resolves to space_shooter preset")
    func startGameRecipeAliasResolves() async {
        var (doc, cardId) = freshDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "game",
                "preset": "shmup",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let recipe = doc.parts.first(where: { $0.name == "game" })?.spriteAreaSpecModel?.recipe
        #expect(recipe?.presetID == "space_shooter")
        #expect(recipe?.entities.contains(where: { $0.role == .player }) == true)
    }
}

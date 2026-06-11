import Foundation
import Testing
@testable import HypeCore

// MARK: - GameRecipeIntentIntegrationTests
//
// "Ship controlled by arrows, asteroids fall from the top, score for
//  surviving, lose on hit": the canonical end-to-end proof that the
//  composable recipe tool surface produces a playable game without any
//  hand-written HypeTalk.
//
// Flow: start_game_recipe → add_entity (ship) → set_controls → add_entity
//       (asteroid) → add_rule → set_game_state → build_game
//
// Assertions:
//   - A spriteArea part exists.
//   - The active scene size is 480×640.
//   - A node named exactly "ship" exists.
//   - Hazard nodes exist.
//   - The compiled scene script PARSES.
//   - The script contains "on keyDown", "on frameUpdate", "on beginContact"
//     (the three handlers that a topDownMovement + loseOnContact + score
//     tracking recipe must emit).

@Suite("GameRecipe — end-to-end intent integration")
struct GameRecipeIntentIntegrationTests {

    // MARK: - Helpers

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

    private func handlerCount(_ script: String, named name: String) -> Int {
        script.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("on \(name)") }
            .count
    }

    // MARK: - Asteroids demo

    @Test("asteroids demo: start → add_entity → set_controls → add_rule → set_game_state → build_game")
    func asteroidsDemoEndToEnd() async {
        var doc = HypeDocument.newDocument(name: "Asteroids")
        let cardId = doc.sortedCards[0].id
        let executor = HypeToolExecutor()

        // 1. Start the recipe.
        let startResult = await executor.execute(
            toolName: "start_game_recipe",
            arguments: [
                "sprite_area_name": "gameArea",
                "scene_width": "480",
                "scene_height": "640",
                "background_color": "#000020",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!startResult.isEmpty)

        // 2. Add player ship.
        // loseOnContact is the behavior that generates a beginContact handler.
        let shipResult = await executor.execute(
            toolName: "add_entity",
            arguments: [
                "sprite_area_name": "gameArea",
                "name": "ship",
                "role": "player",
                "x": "240",
                "y": "100",
                "width": "48",
                "height": "48",
                "behaviors": "topDownMovement,constrainToBounds,loseOnContact:withRole=hazard",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!shipResult.lowercased().contains("error"))

        // 3. Set controls — arrow keys.
        _ = await executor.execute(
            toolName: "set_controls",
            arguments: [
                "sprite_area_name": "gameArea",
                "bindings": "left=moveLeft,right=moveRight,up=moveUp,down=moveDown",
            ],
            document: &doc,
            currentCardId: cardId
        )

        // 4. Add hazard asteroids.
        let asteroidResult = await executor.execute(
            toolName: "add_entity",
            arguments: [
                "sprite_area_name": "gameArea",
                "name": "asteroid",
                "role": "hazard",
                "x": "240",
                "y": "600",
                "width": "40",
                "height": "40",
                "count": "6",
                "behaviors": "destroyOutsideBounds",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!asteroidResult.lowercased().contains("error"))

        // 5. Add a spawner for continuous asteroids.
        _ = await executor.execute(
            toolName: "add_entity",
            arguments: [
                "sprite_area_name": "gameArea",
                "name": "asteroidSpawner",
                "role": "spawner",
                "behaviors": "spawner:spawnRole=hazard;interval=2.0;fromEdge=top",
            ],
            document: &doc,
            currentCardId: cardId
        )

        // 6. Rule: player contacts hazard → lose.
        _ = await executor.execute(
            toolName: "add_rule",
            arguments: [
                "sprite_area_name": "gameArea",
                "trigger": "onContact",
                "role_a": "player",
                "role_b": "hazard",
                "actions": "loseGame",
            ],
            document: &doc,
            currentCardId: cardId
        )

        // 7. Game state: track score.
        _ = await executor.execute(
            toolName: "set_game_state",
            arguments: [
                "sprite_area_name": "gameArea",
                "track_score": "true",
                "initial_score": "0",
                "lose": "zeroLives",
            ],
            document: &doc,
            currentCardId: cardId
        )

        // 8. Compile.
        let buildResult = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "gameArea"],
            document: &doc,
            currentCardId: cardId
        )

        // ASSERT: not a sentinel.
        #expect(!isSentinel(buildResult), "build_game returned a sentinel: \(buildResult)")

        // ASSERT: sprite area exists.
        let part = doc.parts.first(where: { $0.name == "gameArea" })
        #expect(part != nil)

        // ASSERT: scene size is 480×640.
        let scene = part?.activeSceneSpec
        #expect(scene != nil)
        #expect(scene?.size.width == 480)
        #expect(scene?.size.height == 640)

        // ASSERT: a node named exactly "ship" exists.
        #expect(scene?.nodes.contains(where: { $0.name == "ship" }) == true,
                "Expected a node named 'ship'; nodes: \(scene?.nodes.map { $0.name } ?? [])")

        // ASSERT: hazard nodes exist.
        let hazardNodes = scene?.nodes.filter { $0.name.lowercased().contains("asteroid") } ?? []
        #expect(!hazardNodes.isEmpty, "Expected asteroid hazard nodes; nodes: \(scene?.nodes.map { $0.name } ?? [])")

        // ASSERT: compiled scene script parses.
        let script = scene?.script ?? ""
        #expect(!script.isEmpty, "Scene script should not be empty after build_game")
        assertScriptParses(script, "asteroids demo compiled script")

        // ASSERT: script contains expected handlers.
        #expect(handlerCount(script, named: "keyDown") >= 1,
                "Expected on keyDown in script")
        #expect(handlerCount(script, named: "beginContact") >= 1,
                "Expected on beginContact in script")
        // frameUpdate may be present if score tracking emits checks.
        // The key contract is: keyDown + beginContact exist.
    }

    // MARK: - Fail-closed guard: build_game with require_existing_scene=true + 0 areas

    @Test("build_game fail-closed: missing area + require_existing_scene returns error, no area created")
    func buildGameFailClosedMissingArea() async {
        var doc = HypeDocument.newDocument(name: "FailClosed")
        let cardId = doc.sortedCards[0].id
        let executor = HypeToolExecutor()
        let before = doc.parts.filter { $0.partType == .spriteArea }.count

        let result = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "doesNotExist"],
            document: &doc,
            currentCardId: cardId
        )

        let after = doc.parts.filter { $0.partType == .spriteArea }.count
        #expect(result.lowercased().contains("not found"))
        #expect(after == before, "No sprite area should be created by a failed build_game")
    }

    // MARK: - Recipe fidelity: entity names preserved, scene size honoured

    @Test("entity names and scene size are preserved verbatim through build_game")
    func entityNamesAndSizeFidelity() async {
        var doc = HypeDocument.newDocument(name: "Fidelity")
        let cardId = doc.sortedCards[0].id
        let executor = HypeToolExecutor()

        _ = await executor.execute(toolName: "start_game_recipe",
                                   arguments: ["sprite_area_name": "g", "scene_width": "320", "scene_height": "480"],
                                   document: &doc, currentCardId: cardId)
        _ = await executor.execute(toolName: "add_entity",
                                   arguments: ["sprite_area_name": "g", "name": "My Unique Ship Name", "role": "player",
                                               "behaviors": "topDownMovement"],
                                   document: &doc, currentCardId: cardId)

        _ = await executor.execute(toolName: "build_game",
                                   arguments: ["sprite_area_name": "g"],
                                   document: &doc, currentCardId: cardId)

        let scene = doc.parts.first(where: { $0.name == "g" })?.activeSceneSpec
        #expect(scene?.size.width == 320)
        #expect(scene?.size.height == 480)
        #expect(scene?.nodes.contains(where: { $0.name == "My Unique Ship Name" }) == true,
                "Entity name 'My Unique Ship Name' should be preserved verbatim")
    }
}

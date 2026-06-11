import Foundation
import Testing
@testable import HypeCore

// MARK: - Parse helpers (file-private)

/// Count occurrences of `on <handlerName>` in a script string.
private func handlerCount(_ script: String, named name: String) -> Int {
    script.components(separatedBy: "\n")
        .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("on \(name)") }
        .count
}

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

// MARK: - Shared builders

private func makeTestRecipe(
    entities: [GameEntity],
    sceneSize: SizeSpec = SizeSpec(width: 800, height: 600),
    gameState: GameState = GameState()
) -> GameRecipe {
    GameRecipe(sceneSize: sceneSize, entities: entities, gameState: gameState)
}

// MARK: - RecipeCompositionTests

@Suite("RecipeCompiler — handler composition invariants")
struct RecipeCompositionTests {

    // MARK: Single-handler-per-event

    @Test("multi-behavior entity produces exactly one handler per event")
    func multiBehaviorEntityHasOneHandlerPerEvent() {
        let player = GameEntity(
            name: "ship",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [
                Behavior(kind: .topDownMovement, params: ["speed": "200"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .loseOnContact, params: ["withRole": "hazard"]),
            ]
        )
        let hazard = GameEntity(name: "asteroid", role: .hazard, size: SizeSpec(width: 48, height: 48))
        let recipe = makeTestRecipe(entities: [player, hazard])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "multi-behavior single handler per event")

        // keyDown: exactly one
        #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)
        // frameUpdate: exactly one
        #expect(handlerCount(result.sceneScript, named: "frameUpdate") == 1)
        // beginContact: exactly one
        #expect(handlerCount(result.sceneScript, named: "beginContact") == 1)
    }

    // MARK: Two entities, both contribute frameUpdate → one merged handler

    @Test("two entities both contributing frameUpdate merge into ONE handler")
    func twoEntitiesOneFrameUpdateHandler() {
        let enemy1 = GameEntity(
            name: "ufo",
            role: .enemy,
            size: SizeSpec(width: 48, height: 48),
            behaviors: [Behavior(kind: .wrapAround)]
        )
        let enemy2 = GameEntity(
            name: "asteroid",
            role: .hazard,
            size: SizeSpec(width: 40, height: 40),
            behaviors: [Behavior(kind: .wrapAround)]
        )
        let recipe = makeTestRecipe(entities: [enemy1, enemy2])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "two entities frameUpdate merge")
        #expect(handlerCount(result.sceneScript, named: "frameUpdate") == 1)
        // Both entity names should appear in the single frameUpdate block.
        #expect(result.sceneScript.contains("\"ufo\""))
        #expect(result.sceneScript.contains("\"asteroid\""))
    }

    // MARK: Two behaviors contributing to the same key → one branch

    @Test("two behaviors contributing to key 'space' merge into one branch in keyDown")
    func twoSpaceBehaviorsMergeIntoOneBranch() {
        // Both platformerMovement and another behavior might use "space".
        // We create a scenario where platformerMovement (space=jump) and
        // a second behavior also emit a space key branch.
        let player = GameEntity(
            name: "hero",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [
                Behavior(kind: .platformerMovement, params: ["speed": "200", "jumpForce": "600"]),
                // eightDirection also has up/down but not space; add a second
                // platformerMovement to prove space entries are merged not doubled.
                Behavior(kind: .platformerMovement, params: ["speed": "220", "jumpForce": "620"]),
            ]
        )
        let recipe = makeTestRecipe(entities: [player])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "merged space branches")

        // There should still be exactly one keyDown handler.
        #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)

        // Count how many times `if the key is "space"` appears in the script.
        let spaceCount = result.sceneScript
            .components(separatedBy: "\n")
            .filter { $0.contains("the key is \"space\"") }
            .count
        // Both contributions to "space" should be merged into a single if-branch
        // (one occurrence of the `if the key is "space"` guard).
        #expect(spaceCount == 1)
    }

    // MARK: Script contains all required handler names

    @Test("recipe with movement + contact + frameUpdate produces all three handler types")
    func allThreeHandlerTypesPresent() {
        let player = GameEntity(
            name: "ship",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [
                Behavior(kind: .topDownMovement),
                Behavior(kind: .wrapAround),
                Behavior(kind: .loseOnContact, params: ["withRole": "hazard"]),
            ]
        )
        let hazard = GameEntity(name: "rock", role: .hazard, size: SizeSpec(width: 40, height: 40))
        let recipe = makeTestRecipe(entities: [player, hazard])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "all three handler types")
        #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)
        #expect(handlerCount(result.sceneScript, named: "frameUpdate") == 1)
        #expect(handlerCount(result.sceneScript, named: "beginContact") == 1)
    }

    // MARK: gameOver gate present in keyDown and frameUpdate

    @Test("compiled keyDown includes gameOver gate")
    func keyDownHasGameOverGate() {
        let player = GameEntity(
            name: "ship",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement)]
        )
        let recipe = makeTestRecipe(entities: [player])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "gameOver gate in keyDown")
        // keyDown should include an early exit on gameOver.
        #expect(result.sceneScript.contains("exit keyDown"))
    }

    // MARK: Script is wrapped in HYPE-RECIPE markers

    @Test("compiled script is wrapped in HYPE-RECIPE-BEGIN / HYPE-RECIPE-END markers")
    func scriptWrappedInMarkers() {
        let player = GameEntity(name: "hero", role: .player, size: SizeSpec(width: 64, height: 64))
        let recipe = makeTestRecipe(entities: [player])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        #expect(result.sceneScript.contains("HYPE-RECIPE-BEGIN"))
        #expect(result.sceneScript.contains("HYPE-RECIPE-END"))
    }

    // MARK: sceneDidLoad always present

    @Test("compiled script always includes sceneDidLoad handler")
    func sceneDidLoadAlwaysPresent() {
        let player = GameEntity(name: "hero", role: .player, size: SizeSpec(width: 64, height: 64))
        let recipe = makeTestRecipe(entities: [player])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "sceneDidLoad always present")
        #expect(handlerCount(result.sceneScript, named: "sceneDidLoad") == 1)
    }

    // MARK: Empty recipe diagnostic

    @Test("empty recipe returns diagnostic and parseable minimal script")
    func emptyRecipeDiagnostic() {
        let recipe = makeTestRecipe(entities: [])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        #expect(!result.diagnostics.isEmpty)
        assertScriptParses(result.sceneScript, "empty recipe fallback")
    }
}

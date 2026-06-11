import Foundation
import Testing
@testable import HypeCore

// MARK: - RecipeMergeTests

@Suite("RecipeCompiler.merge — non-destructive scene merging")
struct RecipeMergeTests {

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

    private func makeSimpleRecipe(entityName: String = "ship") -> GameRecipe {
        let entity = GameEntity(
            name: entityName,
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement)]
        )
        return GameRecipe(entities: [entity])
    }

    private func makeScene(extraNodeName: String? = nil) -> SceneSpec {
        var nodes: [HypeNodeSpec] = []
        if let extra = extraNodeName {
            nodes.append(HypeNodeSpec(
                name: extra,
                nodeType: .shape,
                shapeSpec: ShapeNodeSpec(fillColor: "#FF0000")
            ))
        }
        return SceneSpec(nodes: nodes)
    }

    // MARK: Recipe-owned nodes are replaced; hand-added nodes are preserved

    @Test("merge replaces recipe-owned nodes and preserves non-owned nodes")
    func mergePreservesNonOwnedNodes() {
        let recipe = makeSimpleRecipe(entityName: "ship")
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // Build a scene with the recipe node PLUS a hand-added node not owned by the recipe.
        var scene = makeScene(extraNodeName: "handAddedCloud")

        RecipeCompiler.merge(result, into: &scene)

        // Recipe-owned node should be present.
        let shipNode = scene.nodes.first { $0.name == "ship" }
        #expect(shipNode != nil)

        // Hand-added node should still be present.
        let cloudNode = scene.nodes.first { $0.name == "handAddedCloud" }
        #expect(cloudNode != nil)

        // Total nodes = recipe nodes + 1 hand-added.
        #expect(scene.nodes.count == result.nodes.count + 1)
    }

    // MARK: Merge on re-compilation does not duplicate recipe nodes

    @Test("recompiling after adding a behavior does not duplicate nodes")
    func recompileDoesNotDuplicateNodes() {
        let recipe1 = makeSimpleRecipe()
        var result1 = RecipeCompiler.compile(recipe1, repository: AssetRepository())

        var scene = SceneSpec()
        RecipeCompiler.merge(result1, into: &scene)

        let countAfterFirst = scene.nodes.count

        // Recompile with a slightly changed recipe (add wrapAround).
        let entity2 = GameEntity(
            name: "ship",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [
                Behavior(kind: .topDownMovement),
                Behavior(kind: .wrapAround),
            ]
        )
        let recipe2 = GameRecipe(entities: [entity2])
        let result2 = RecipeCompiler.compile(recipe2, repository: AssetRepository())

        RecipeCompiler.merge(result2, into: &scene)

        // Node count should not increase (ship was replaced, not duplicated).
        #expect(scene.nodes.count == countAfterFirst)
        let shipNodes = scene.nodes.filter { $0.name == "ship" }
        #expect(shipNodes.count == 1)
    }

    // MARK: Script merge replaces only the BEGIN..END region

    @Test("merge replaces only the HYPE-RECIPE-BEGIN..END region, preserving user handlers after END")
    func mergeReplacesOnlyRecipeRegion() {
        let recipe = makeSimpleRecipe()
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        let userHandler = """
on myCustomHandler
  -- This is a user-written handler that must survive merge.
  put "hello" into greeting
end myCustomHandler
"""

        // Build an existing script that already has the recipe region + user handler after it.
        let existingScript = result.sceneScript + "\n\n" + userHandler
        var scene = SceneSpec(script: existingScript)

        // Re-run merge (simulating recompile).
        RecipeCompiler.merge(result, into: &scene)

        // The user handler must still be present after merge.
        #expect(scene.script.contains("on myCustomHandler"))
        #expect(scene.script.contains("This is a user-written handler"))

        // The recipe markers must still be present.
        #expect(scene.script.contains("HYPE-RECIPE-BEGIN"))
        #expect(scene.script.contains("HYPE-RECIPE-END"))

        // The full merged script must parse.
        assertScriptParses(scene.script, "merge preserves user handlers")
    }

    // MARK: Merge with no existing markers inserts recipe at top

    @Test("merge into script with no recipe markers inserts recipe at top and preserves existing content")
    func mergeNoExistingMarkersInsertsAtTop() {
        let recipe = makeSimpleRecipe()
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        let legacyScript = """
on sceneDidLoad
  put "legacy" into mode
end sceneDidLoad
"""
        var scene = SceneSpec(script: legacyScript)
        RecipeCompiler.merge(result, into: &scene)

        // Recipe region should be at the top.
        #expect(scene.script.hasPrefix("-- HYPE-RECIPE-BEGIN"))

        // Legacy content should be preserved somewhere below.
        #expect(scene.script.contains("on sceneDidLoad"))

        // Full merged script must parse.
        assertScriptParses(scene.script, "merge into legacy script")
    }

    // MARK: Merge into empty scene

    @Test("merge into empty scene sets script to recipe script")
    func mergeIntoEmptyScene() {
        let recipe = makeSimpleRecipe()
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        var scene = SceneSpec()
        RecipeCompiler.merge(result, into: &scene)

        #expect(scene.script == result.sceneScript)
        assertScriptParses(scene.script, "merge into empty scene")
    }

    // MARK: Merge adds new nodes that didn't exist before

    @Test("merge adds new recipe nodes that were not present in the scene")
    func mergeAddsNewNodes() {
        let entity = GameEntity(name: "powerup", role: .collectible, size: SizeSpec(width: 32, height: 32))
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        var scene = SceneSpec(nodes: [])
        #expect(scene.nodes.isEmpty)

        RecipeCompiler.merge(result, into: &scene)

        let powerupNode = scene.nodes.first { $0.name == "powerup" }
        #expect(powerupNode != nil)
    }

    // MARK: Recipe-owned names tracked correctly after multi-entity compile

    @Test("recipeOwnedNodeNames tracks all generated instance names for multi-count entities")
    func ownedNamesTrackedForMultiCount() {
        let enemy = GameEntity(
            name: "enemy",
            role: .enemy,
            size: SizeSpec(width: 48, height: 48),
            count: 3
        )
        let recipe = GameRecipe(entities: [enemy])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        #expect(result.recipeOwnedNodeNames.contains("enemy_1"))
        #expect(result.recipeOwnedNodeNames.contains("enemy_2"))
        #expect(result.recipeOwnedNodeNames.contains("enemy_3"))
        #expect(!result.recipeOwnedNodeNames.contains("enemy"))  // bare name not used for count>1

        // Non-recipe node in scene is preserved after merge.
        var scene = SceneSpec(nodes: [
            HypeNodeSpec(name: "background_tile", nodeType: .shape, shapeSpec: ShapeNodeSpec())
        ])
        RecipeCompiler.merge(result, into: &scene)

        let bgNode = scene.nodes.first { $0.name == "background_tile" }
        #expect(bgNode != nil)
    }
}

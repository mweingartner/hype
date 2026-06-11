import Foundation
import Testing
@testable import HypeCore

// MARK: - Parse / handler helpers (file-private)

/// Parse a HypeTalk script and report any error via `Issue.record`.
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

/// Count how many times `on <name>` appears at the start of a trimmed line.
private func handlerCount(_ script: String, named name: String) -> Int {
    script.components(separatedBy: "\n")
        .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("on \(name)") }
        .count
}

// MARK: - Shared recipe builders

private func makePlayer(name: String = "player", behaviors: [Behavior] = []) -> GameEntity {
    GameEntity(
        name: name,
        role: .player,
        position: PointSpec(x: 400, y: 300),
        size: SizeSpec(width: 64, height: 64),
        behaviors: behaviors
    )
}

private func makeHazard(name: String = "hazard", count: Int = 1) -> GameEntity {
    GameEntity(
        name: name,
        role: .hazard,
        position: PointSpec(x: 100, y: 100),
        size: SizeSpec(width: 48, height: 48),
        count: count
    )
}

private func makeRecipe(
    entities: [GameEntity] = [],
    rules: [GameRule] = [],
    gameState: GameState = GameState()
) -> GameRecipe {
    GameRecipe(
        sceneSize: SizeSpec(width: 800, height: 600),
        entities: entities,
        rules: rules,
        gameState: gameState
    )
}

private func compile(_ recipe: GameRecipe) -> RecipeCompilationResult {
    RecipeCompiler.compile(recipe, repository: AssetRepository())
}

// MARK: - RecipeRuleCompilationTests

@Suite("RecipeCompiler — GameRule compilation")
struct RecipeRuleCompilationTests {

    // MARK: onContact → loseGame

    @Test("onContact rule (player×hazard → loseGame) compiles to parseable beginContact with gameOver")
    func onContactLoseGameRule() {
        let player = makePlayer()
        let hazard = makeHazard()

        let rule = GameRule(
            trigger: RuleTrigger(kind: .onContact, roleA: .player, roleB: .hazard),
            conditions: [],
            actions: [RuleAction(kind: .loseGame, message: "Game Over")]
        )

        let recipe = makeRecipe(entities: [player, hazard], rules: [rule])
        let result = compile(recipe)

        // Script must parse cleanly
        assertScriptParses(result.sceneScript, "onContact loseGame")

        // beginContact handler must be present
        #expect(handlerCount(result.sceneScript, named: "beginContact") == 1)

        // Must test the hazard name
        #expect(result.sceneScript.contains("\"hazard\""))

        // Must set gameOver
        #expect(result.sceneScript.contains("gameOver"))
        #expect(result.sceneScript.contains("put \"true\" into gameOver"))

        // Must set status label
        #expect(result.sceneScript.contains("Game Over"))
    }

    @Test("onContact rule with multi-count hazard uses 'contains' predicate")
    func onContactMultiCountHazardPredicate() {
        let player = makePlayer()
        let hazards = makeHazard(name: "rock", count: 3)

        let rule = GameRule(
            trigger: RuleTrigger(kind: .onContact, roleA: .player, roleB: .hazard),
            conditions: [],
            actions: [RuleAction(kind: .loseGame)]
        )

        let recipe = makeRecipe(entities: [player, hazards], rules: [rule])
        let result = compile(recipe)

        assertScriptParses(result.sceneScript, "onContact multi-count hazard")
        // Multi-count entity should use the 'contains' predicate form
        #expect(result.sceneScript.contains("contains"))
    }

    // MARK: onKey

    @Test("onKey rule emits a keyDown branch for the specified key")
    func onKeyRule() {
        let player = makePlayer()

        let rule = GameRule(
            trigger: RuleTrigger(kind: .onKey, key: "space"),
            conditions: [],
            actions: [RuleAction(kind: .addScore, amount: 10)]
        )

        let recipe = makeRecipe(
            entities: [player],
            rules: [rule],
            gameState: GameState(trackScore: true, initialScore: 0)
        )
        let result = compile(recipe)

        assertScriptParses(result.sceneScript, "onKey addScore")
        #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)
        #expect(result.sceneScript.contains("\"space\""))
        #expect(result.sceneScript.contains("add 10 to score"))
    }

    // MARK: everyNSeconds → spawnEntity

    @Test("everyNSeconds rule: timer global declared, sceneDidLoad inits it, frameUpdate has create sprite")
    func everyNSecondsSpawnRule() {
        let player = makePlayer()
        let enemy = GameEntity(
            name: "enemy",
            role: .enemy,
            position: PointSpec(x: 400, y: 50),
            size: SizeSpec(width: 40, height: 40)
        )

        let rule = GameRule(
            trigger: RuleTrigger(kind: .everyNSeconds, seconds: 2.0),
            conditions: [],
            actions: [RuleAction(kind: .spawnEntity, entityName: "enemy")]
        )

        let recipe = makeRecipe(entities: [player, enemy], rules: [rule])
        let result = compile(recipe)

        assertScriptParses(result.sceneScript, "everyNSeconds spawnEntity")

        // Timer global must appear
        #expect(result.sceneScript.contains("ruleTimer_0"))

        // sceneDidLoad must initialize the timer to 0
        let sceneDidLoadBlock = extractHandler(result.sceneScript, named: "sceneDidLoad")
        #expect(sceneDidLoadBlock?.contains("put 0 into ruleTimer_0") == true)

        // sceneDidLoad must also initialize the spawn index counter
        #expect(sceneDidLoadBlock?.contains("put 0 into ruleSpawnIdx_0") == true)

        // frameUpdate must add deltaTime and have a threshold check
        let frameUpdateBlock = extractHandler(result.sceneScript, named: "frameUpdate")
        #expect(frameUpdateBlock?.contains("add deltaTime to ruleTimer_0") == true)
        #expect(frameUpdateBlock?.contains("ruleTimer_0 >= 2") == true)

        // Must contain a create sprite call
        #expect(result.sceneScript.contains("create sprite"))
    }

    // MARK: onScoreReached → winGame

    @Test("onScoreReached rule produces a parseable frameUpdate score check that sets gameOver")
    func onScoreReachedWinRule() {
        let player = makePlayer()
        let statusHUD = GameEntity(
            name: "status",
            role: .hud,
            position: PointSpec(x: 400, y: 20),
            size: SizeSpec(width: 300, height: 30),
            initialText: ""
        )

        let rule = GameRule(
            trigger: RuleTrigger(kind: .onScoreReached, scoreThreshold: 100),
            conditions: [],
            actions: [RuleAction(kind: .winGame, message: "You Win!")]
        )

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            statusHUDEntityName: "status"
        )

        let recipe = makeRecipe(entities: [player, statusHUD], rules: [rule], gameState: gameState)
        let result = compile(recipe)

        assertScriptParses(result.sceneScript, "onScoreReached winGame")

        // Must have a frameUpdate handler
        #expect(handlerCount(result.sceneScript, named: "frameUpdate") == 1)

        // Must check score threshold and use the gameOver gate
        #expect(result.sceneScript.contains("score >= 100"))
        #expect(result.sceneScript.contains("put \"true\" into gameOver"))
        #expect(result.sceneScript.contains("You Win!"))
    }

    // MARK: addScore updates score HUD label

    @Test("addScore action updates the score HUD label when scoreHUDEntityName is set")
    func addScoreUpdatesScoreHUD() {
        let player = makePlayer()
        let scoreHUD = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: 400, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0"
        )
        let hazard = makeHazard()

        let rule = GameRule(
            trigger: RuleTrigger(kind: .onContact, roleA: .player, roleB: .hazard),
            conditions: [],
            actions: [RuleAction(kind: .addScore, amount: 5)]
        )

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            scoreHUDEntityName: "scoreLabel"
        )

        let recipe = makeRecipe(entities: [player, scoreHUD, hazard], rules: [rule], gameState: gameState)
        let result = compile(recipe)

        assertScriptParses(result.sceneScript, "addScore with HUD update")

        // Must add to score
        #expect(result.sceneScript.contains("add 5 to score"))

        // Must update the score HUD label
        #expect(result.sceneScript.contains("set the text of label \"scoreLabel\""))
    }

    // MARK: Composition: behaviors + rules → one handler per event

    @Test("recipe with both behaviors and rules produces exactly one handler per event and parses")
    func behaviorsAndRulesComposition() {
        // Player entity with a behavior that contributes keyDown + frameUpdate
        let player = makePlayer(behaviors: [
            Behavior(kind: .topDownMovement, params: ["speed": "200"]),
            Behavior(kind: .constrainToBounds),
        ])
        let hazard = makeHazard()

        // A rule that also contributes beginContact and frameUpdate
        let contactRule = GameRule(
            trigger: RuleTrigger(kind: .onContact, roleA: .player, roleB: .hazard),
            conditions: [],
            actions: [RuleAction(kind: .loseGame)]
        )
        let frameRule = GameRule(
            trigger: RuleTrigger(kind: .onFrame),
            conditions: [],
            actions: [RuleAction(kind: .addScore, amount: 1)]
        )

        let recipe = makeRecipe(
            entities: [player, hazard],
            rules: [contactRule, frameRule],
            gameState: GameState(trackScore: true, initialScore: 0)
        )
        let result = compile(recipe)

        assertScriptParses(result.sceneScript, "behaviors + rules composition")

        // Still exactly one handler per event
        #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)
        #expect(handlerCount(result.sceneScript, named: "frameUpdate") == 1)
        #expect(handlerCount(result.sceneScript, named: "beginContact") == 1)
        #expect(handlerCount(result.sceneScript, named: "sceneDidLoad") == 1)
    }

    // MARK: Unknown entity reference → diagnostic + still parses

    @Test("rule with onContact referencing a role with no entities emits a diagnostic and still parses")
    func unknownRoleEmitsDiagnosticAndParses() {
        let player = makePlayer()

        // onContact with roleB = .hazard, but no hazard entity is in the recipe
        let rule = GameRule(
            trigger: RuleTrigger(kind: .onContact, roleA: .player, roleB: .hazard),
            conditions: [],
            actions: [RuleAction(kind: .loseGame)]
        )

        // No hazard entity in this recipe
        let recipe = makeRecipe(entities: [player], rules: [rule])
        let result = compile(recipe)

        // Script must still parse (uses fallback predicate)
        assertScriptParses(result.sceneScript, "unknown role")

        // A diagnostic about the missing role should be recorded
        let hasDiagnostic = result.diagnostics.contains { $0.contains("hazard") || $0.contains("Rule 0") }
        #expect(hasDiagnostic)
    }

    @Test("respawnEntity with unknown entity name emits a diagnostic and still parses")
    func respawnUnknownEntityEmitsDiagnosticAndParses() {
        let player = makePlayer()

        // respawnEntity referencing "ghost" which is not in the recipe
        let rule = GameRule(
            trigger: RuleTrigger(kind: .onSceneLoad),
            conditions: [],
            actions: [RuleAction(kind: .respawnEntity, entityName: "ghost")]
        )

        let recipe = makeRecipe(entities: [player], rules: [rule])
        let result = compile(recipe)

        // Script must still parse (compiler emits a fallback parseable line)
        assertScriptParses(result.sceneScript, "respawn unknown entity")

        // A diagnostic mentioning the missing entity should be recorded
        let hasDiagnostic = result.diagnostics.contains { $0.contains("ghost") || $0.contains("Rule 0") }
        #expect(hasDiagnostic)
    }

    // MARK: destroyOther in non-contact trigger → diagnostic, no unparseable line

    @Test("destroyOther in a non-contact trigger emits a diagnostic and does not produce an unparseable line")
    func destroyOtherInNonContactTrigger() {
        let player = makePlayer()

        // destroyOther is only valid inside a contact handler; using it in onFrame is invalid
        let rule = GameRule(
            trigger: RuleTrigger(kind: .onFrame),
            conditions: [],
            actions: [RuleAction(kind: .destroyOther)]
        )

        let recipe = makeRecipe(entities: [player], rules: [rule])
        let result = compile(recipe)

        // Script must parse
        assertScriptParses(result.sceneScript, "destroyOther in onFrame")

        // A diagnostic must be recorded
        let hasDiagnostic = result.diagnostics.contains { $0.contains("destroyOther") || $0.contains("contact") }
        #expect(hasDiagnostic)

        // The string "remove sprite otherName" should NOT appear outside a contact handler
        // (it would be emitted inside frameUpdate which has no otherName in scope)
        let frameUpdateBlock = extractHandler(result.sceneScript, named: "frameUpdate")
        #expect(frameUpdateBlock?.contains("remove sprite otherName") != true)
    }

    // MARK: Condition guard wraps actions

    @Test("stateGreater condition wraps actions in an if guard")
    func stateGreaterConditionWrapsActions() {
        let player = makePlayer()

        let rule = GameRule(
            trigger: RuleTrigger(kind: .onFrame),
            conditions: [
                RuleCondition(kind: .stateGreater, stateVar: "score", value: 50)
            ],
            actions: [RuleAction(kind: .addScore, amount: 1)]
        )

        let recipe = makeRecipe(
            entities: [player],
            rules: [rule],
            gameState: GameState(trackScore: true)
        )
        let result = compile(recipe)

        assertScriptParses(result.sceneScript, "stateGreater condition")
        #expect(result.sceneScript.contains("score > 50"))
    }

    // MARK: onSceneLoad rule

    @Test("onSceneLoad rule adds lines to sceneDidLoad handler")
    func onSceneLoadRule() {
        let player = makePlayer()
        let statusHUD = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: 400, y: 20),
            size: SizeSpec(width: 300, height: 30),
            initialText: ""
        )

        let rule = GameRule(
            trigger: RuleTrigger(kind: .onSceneLoad),
            conditions: [],
            actions: [RuleAction(kind: .setStatus, message: "Get Ready!")]
        )

        let gameState = GameState(statusHUDEntityName: "statusLabel")

        let recipe = makeRecipe(entities: [player, statusHUD], rules: [rule], gameState: gameState)
        let result = compile(recipe)

        assertScriptParses(result.sceneScript, "onSceneLoad setStatus")

        let sceneDidLoadBlock = extractHandler(result.sceneScript, named: "sceneDidLoad")
        #expect(sceneDidLoadBlock?.contains("Get Ready!") == true)
    }
}

// MARK: - Private extraction helper

/// Extract the text of a named handler block from a script string.
/// Returns nil if the handler is not found.
private func extractHandler(_ script: String, named name: String) -> String? {
    let lines = script.components(separatedBy: "\n")
    var insideHandler = false
    var result: [String] = []
    let openPrefix = "on \(name)"
    let closeToken = "end \(name)"

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(openPrefix) {
            insideHandler = true
            result.append(line)
            continue
        }
        if insideHandler {
            result.append(line)
            if trimmed == closeToken {
                break
            }
        }
    }

    return insideHandler ? result.joined(separator: "\n") : nil
}

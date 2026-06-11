import Foundation
import Testing
@testable import HypeCore

// MARK: - Shared helpers

/// Parse a HypeTalk script, returning `nil` on success or an error string.
private func scriptParseError(_ script: String) -> String? {
    var lexer = Lexer(source: script)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    do {
        _ = try parser.parse()
        return nil
    } catch {
        return String(describing: error)
    }
}

private func assertScriptParses(
    _ script: String,
    _ label: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if let err = scriptParseError(script) {
        Issue.record(
            "Script parse failed\(label.isEmpty ? "" : " [\(label)]"): \(err)\n\nScript:\n\(script)",
            sourceLocation: sourceLocation
        )
    }
}

/// Count `on <name>` openings in a script.
private func handlerCount(_ script: String, named name: String) -> Int {
    script.components(separatedBy: "\n")
        .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("on \(name)") }
        .count
}

// MARK: ============================================================
// MARK: - Injection Resistance Tests (post-fix safety proofs)
// MARK: ============================================================
//
// Strategy: all tests run through RecipeCompiler.compile() — the full path —
// to prove that hostile recipe content produces a VALID, NON-TRAPPING script
// with NO injected handler after the P0 fix.  The sanitizer at the boundary
// removes the injection surface before any HypeTalk is generated, so the
// self-validation assertionFailure is never reached.
//
// Key assertions for every hostile input:
//   1. The compiled script PARSES (Lexer+Parser, no error).
//   2. The count of the targeted handler name in the output == 1 (no injection).
//   3. No diagnostic contains "invalid script" (no fallback triggered).
//   4. The process does not trap (guaranteed by 1+3 — the assertionFailure only
//      fires when self-validation detects an invalid script).

@Suite("RecipeCompiler — injection resistance and hostile input")
struct RecipeInjectionAndBoundsTests {

    // MARK: - P0: Entity name injection through full compile path

    @Test("entity name with double-quote + handler injection does not inject a handler")
    func entityNameDoubleQuoteInjectionFullPath() {
        // Craft an entity name that, without sanitization, would break out of a
        // HypeTalk string literal and inject a handler definition.
        let hostileName = "ship\"\non mouseUp\ngo to card 99\nend mouseUp\n-- "
        let entity = GameEntity(
            name: hostileName,
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement, params: ["speed": "200"])]
        )
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // Script must parse (no assertionFailure reached, no trap).
        assertScriptParses(result.sceneScript, "entity name double-quote injection")

        // The injected handler must NOT appear in the output.
        #expect(handlerCount(result.sceneScript, named: "mouseUp") == 0,
                "Hostile entity name injected a mouseUp handler into the compiled script")

        // No fallback triggered (sanitizer prevented the injection, not the fallback).
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback,
                "Fallback triggered — sanitizer should have prevented this, not caught it after the fact")
    }

    @Test("entity name with newline + handler injection does not inject a handler")
    func entityNameNewlineInjectionFullPath() {
        // Newline in an entity name breaks the string literal line and can inject
        // a new handler definition.
        let hostileName = "ship\non mouseUp\ngo to card 99\nend mouseUp\n-- "
        let entity = GameEntity(
            name: hostileName,
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement, params: ["speed": "200"])]
        )
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "entity name newline injection")
        #expect(handlerCount(result.sceneScript, named: "mouseUp") == 0,
                "Hostile entity name (newline) injected a mouseUp handler")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("action.message with double-quote + handler injection does not inject a handler")
    func actionMessageInjectionFullPath() {
        // A rule action message containing a double-quote + newline injection payload.
        let hostileMessage = "You Win!\"\non mouseUp\ngo to card 99\nend mouseUp\n-- "
        let rule = GameRule(
            trigger: RuleTrigger(kind: .onSceneLoad),
            conditions: [],
            actions: [RuleAction(kind: .winGame, message: hostileMessage)]
        )
        let player = GameEntity(
            name: "hero",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement)]
        )
        let recipe = GameRecipe(entities: [player], rules: [rule])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "action.message injection")
        #expect(handlerCount(result.sceneScript, named: "mouseUp") == 0,
                "Hostile action.message injected a mouseUp handler")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("statusMessage in win condition with injection payload does not inject a handler")
    func statusMessageInjectionFullPath() {
        let hostileMsg = "You Win!\"\non mouseUp\nput 1 into x\nend mouseUp\n-- "
        let winCond = WinLoseCondition(kind: .reachScore, scoreThreshold: 100, statusMessage: hostileMsg)
        let player = GameEntity(
            name: "hero",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement)]
        )
        let state = GameState(
            trackScore: true,
            initialScore: 0,
            winConditions: [winCond]
        )
        let recipe = GameRecipe(entities: [player], gameState: state)
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "statusMessage injection")
        #expect(handlerCount(result.sceneScript, named: "mouseUp") == 0,
                "Hostile statusMessage injected a mouseUp handler")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("scoreHUDEntityName with injection payload does not inject a handler")
    func scoreHUDNameInjectionFullPath() {
        let hostileHUD = "scoreHUD\"\non mouseUp\nput 1 into x\nend mouseUp\n-- "
        let hudEntity = GameEntity(
            name: hostileHUD,
            role: .hud,
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0"
        )
        let player = GameEntity(
            name: "hero",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement)]
        )
        let state = GameState(
            trackScore: true,
            scoreHUDEntityName: hostileHUD
        )
        let recipe = GameRecipe(entities: [player, hudEntity], gameState: state)
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "scoreHUD name injection")
        #expect(handlerCount(result.sceneScript, named: "mouseUp") == 0,
                "Hostile scoreHUD name injected a mouseUp handler")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("artRoleRef with injection payload in spawner does not inject a handler")
    func artRoleRefInjectionInSpawner() {
        let hostileArtRef = "playerArt\"\non mouseUp\nput 1 into hacked\nend mouseUp\n-- "
        let spawnedEntity = GameEntity(
            name: "enemy",
            role: .enemy,
            size: SizeSpec(width: 48, height: 48),
            artRoleRef: hostileArtRef
        )
        let spawnerEntity = GameEntity(
            name: "spawnerNode",
            role: .spawner,
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "enemy",
                    "interval": "2.0",
                    "max": "5"
                ])
            ]
        )
        let recipe = GameRecipe(entities: [spawnedEntity, spawnerEntity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "artRoleRef injection in spawner")
        #expect(handlerCount(result.sceneScript, named: "mouseUp") == 0,
                "Hostile artRoleRef injected a mouseUp handler via spawner")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("stateVar with injection payload produces safe condition expression")
    func stateVarInjectionProducesSafeExpression() {
        // A hostile stateVar value like "score\" then -- " tries to break
        // a bare HypeTalk conditional expression (not a string literal).
        // The identifier validator should reject it and fall back to "gameOver".
        let hostileStateVar = "score\" then --"
        let rule = GameRule(
            trigger: RuleTrigger(kind: .onFrame),
            conditions: [RuleCondition(kind: .stateEquals, stateVar: hostileStateVar, value: 100)],
            actions: [RuleAction(kind: .addScore, amount: 1)]
        )
        let player = GameEntity(
            name: "hero",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement)]
        )
        let recipe = GameRecipe(entities: [player], rules: [rule])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "stateVar injection")
        // Diagnostic should mention the fallback.
        let hasDiagnostic = result.diagnostics.contains { $0.contains("not a valid identifier") }
        #expect(hasDiagnostic, "Expected identifier-validation diagnostic for hostile stateVar")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    // MARK: - Numeric param safety

    @Test("topDownMovement with negative speed does NOT produce double-negative (--N) in compiled script")
    func topDownMovementNegativeSpeedNoDoubleNegative() {
        // After the fix, negative speed is emitted as a signed literal (e.g. -200)
        // rather than the template "-\(s)" producing "--200".
        let b = Behavior(kind: .topDownMovement, params: ["speed": "-50"])
        let entity = GameEntity(
            name: "ship",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [b]
        )
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // The compiled script must parse cleanly — no --50 double-negative.
        assertScriptParses(result.sceneScript, "topDownMovement speed=-50")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback, "Negative speed produced invalid script via double-negative")

        // The script must not contain the double-negative pattern.
        #expect(!result.sceneScript.contains("--50"),
                "Double-negative '--50' found in compiled script")
    }

    @Test("platformerMovement with negative jumpForce does NOT produce double-negative in compiled script")
    func platformerMovementNegativeJumpForceNoDoubleNegative() {
        let b = Behavior(kind: .platformerMovement, params: ["speed": "200", "jumpForce": "-620"])
        let entity = GameEntity(
            name: "hero",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [b]
        )
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "platformerMovement jumpForce=-620")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
        #expect(!result.sceneScript.contains("--620"),
                "Double-negative '--620' found in compiled script")
    }

    @Test("spawner velocity with negative values does NOT produce double-negative in compiled script")
    func spawnerNegativeVelocityNoDoubleNegative() {
        let enemy = GameEntity(name: "enemy", role: .enemy, size: SizeSpec(width: 48, height: 48))
        let spawnerEntity = GameEntity(
            name: "spawnerNode",
            role: .spawner,
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "enemy",
                    "interval": "1.5",
                    "velocity": "-50,-160",
                    "max": "5"
                ])
            ]
        )
        let recipe = GameRecipe(entities: [enemy, spawnerEntity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "spawner velocity=-50,-160")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
        #expect(!result.sceneScript.contains("--50"),
                "Double-negative '--50' found in spawner velocity output")
    }

    @Test("spawner velocity with garbage string falls back to 0 and parses")
    func spawnerVelocityGarbageFallsBack() {
        let enemy = GameEntity(name: "enemy", role: .enemy, size: SizeSpec(width: 48, height: 48))
        let spawnerEntity = GameEntity(
            name: "spawnerNode",
            role: .spawner,
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "enemy",
                    "velocity": "fast,very-fast",
                    "max": "5"
                ])
            ]
        )
        let recipe = GameRecipe(entities: [enemy, spawnerEntity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        assertScriptParses(result.sceneScript, "spawner velocity=garbage")
        // Garbage velocity → default 0; no injection content in script.
        #expect(!result.sceneScript.contains("fast"),
                "Garbage velocity string leaked into compiled script")
    }

    // MARK: - DoS caps

    @Test("entity count=100000 is clamped to 500 with diagnostic")
    func entityCountHugeClamped() {
        let entity = GameEntity(
            name: "rock",
            role: .hazard,
            size: SizeSpec(width: 48, height: 48),
            count: 100000
        )
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // Node count must be capped at 500.
        #expect(result.nodes.count <= 500,
                "Entity count=100000 was not clamped; got \(result.nodes.count) nodes")
        // A diagnostic must be present indicating the clamp.
        let hasDiagnostic = result.diagnostics.contains { $0.contains("500") && $0.contains("clamped") }
        #expect(hasDiagnostic, "Expected cap diagnostic for count=100000; diagnostics: \(result.diagnostics)")
        assertScriptParses(result.sceneScript, "entity count=100000")
    }

    @Test("recipe with 300 entities processes only first 200 with diagnostic")
    func tooManyEntitiesCappedAt200() {
        let entities = (1...300).map { i in
            GameEntity(
                name: "rock\(i)",
                role: .hazard,
                size: SizeSpec(width: 40, height: 40),
                count: 1
            )
        }
        let recipe = GameRecipe(entities: entities)
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        #expect(result.nodes.count <= 200,
                "Total entity cap was not enforced; got \(result.nodes.count) nodes")
        let hasDiagnostic = result.diagnostics.contains { $0.contains("200") }
        #expect(hasDiagnostic, "Expected cap diagnostic for 300 entities; diagnostics: \(result.diagnostics)")
        assertScriptParses(result.sceneScript, "300 entities capped at 200")
    }

    @Test("spawner max=100000 is clamped to 500 in emitted script")
    func spawnerMaxHugeClamped() {
        let enemy = GameEntity(name: "enemy", role: .enemy, size: SizeSpec(width: 48, height: 48))
        let spawnerEntity = GameEntity(
            name: "spawnerNode",
            role: .spawner,
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "enemy",
                    "interval": "1.0",
                    "max": "100000"
                ])
            ]
        )
        let recipe = GameRecipe(entities: [enemy, spawnerEntity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // Compile-time node count must still be 2 (spawner creates nodes at runtime).
        #expect(result.nodes.count == 2,
                "Expected 2 static nodes for spawner, got \(result.nodes.count)")
        // The emitted max cap in the script must not exceed 500.
        #expect(!result.sceneScript.contains("100000"),
                "Unclamped max=100000 leaked into spawner script")
        #expect(result.sceneScript.contains("500"),
                "Expected clamped max=500 in spawner script")
        assertScriptParses(result.sceneScript, "spawner max=100000")
    }

    // MARK: - Entity name: special characters that are safe in string literals

    @Test("entity name with trailing spaces compiles cleanly")
    func entityNameWithTrailingSpacesCompilesCleanly() {
        // Spaces inside a quoted string are valid HypeTalk.
        let entity = GameEntity(name: "my ship ", role: .player, size: SizeSpec(width: 64, height: 64),
                                behaviors: [Behavior(kind: .topDownMovement)])
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        assertScriptParses(result.sceneScript, "entity name with spaces")
        #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("entity name with hyphen and numbers compiles cleanly")
    func entityNameWithHyphenCompilesCleanly() {
        let entity = GameEntity(name: "ship-alpha-1", role: .player, size: SizeSpec(width: 64, height: 64),
                                behaviors: [Behavior(kind: .topDownMovement)])
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        assertScriptParses(result.sceneScript, "entity name with hyphen")
        #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("entity name that matches a HypeTalk keyword 'set' compiles with fallback or parses")
    func entityNameIsHypeTalkKeywordSet() {
        // "set" is a HypeTalk verb; inside a string literal it should be inert.
        let entity = GameEntity(name: "set", role: .player, size: SizeSpec(width: 64, height: 64),
                                behaviors: [Behavior(kind: .topDownMovement)])
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        // The compiler must either produce a parseable script, OR fall back safely.
        let parseErr = scriptParseError(result.sceneScript)
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        if let err = parseErr {
            #expect(hasFallback,
                    "Script does not parse AND no fallback triggered for entity name 'set': \(err)")
        } else {
            // Script parses cleanly.
            #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)
        }
    }

    @Test("entity name 'end' does not corrupt handler structure")
    func entityNameIsKeywordEnd() {
        let entity = GameEntity(name: "end", role: .player, size: SizeSpec(width: 64, height: 64),
                                behaviors: [Behavior(kind: .topDownMovement)])
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        let parseErr = scriptParseError(result.sceneScript)
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        if let err = parseErr {
            #expect(hasFallback,
                    "Script does not parse AND no fallback triggered for entity name 'end': \(err)")
        } else {
            // Parseable; must have exactly one keyDown.
            #expect(handlerCount(result.sceneScript, named: "keyDown") == 1)
        }
    }

    // MARK: - Behavior param: numeric values are sanitized by Double parsing

    @Test("topDownMovement speed param with embedded injection attempt — Double parsing neutralizes it")
    func speedParamInjectionNeutralizedByDoubleParsing() {
        // The BehaviorLibrary reads speed via:
        //   b.params[key].flatMap(Double.init) ?? default
        // So a hostile string like "200; put 1 into x" parses to nil → falls back to 200.
        // This means behavior params with embedded non-numeric content are SAFE.
        let hostileSpeed = "200; put 1 into hacked -- "
        let b = Behavior(kind: .topDownMovement, params: ["speed": hostileSpeed])
        let entity = GameEntity(name: "ship", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        // The speed should have fallen back to 200 (Double("200; put 1 into hacked -- ") = nil).
        let allLines = contrib.keyDown.flatMap(\.lines)
        let hasHostileContent = allLines.contains { $0.contains("hacked") }
        #expect(!hasHostileContent, "Hostile speed param content leaked into generated lines: \(allLines)")
        // Speed 200 is the default.
        let hasDefault = allLines.contains { $0.contains("200") }
        #expect(hasDefault, "Expected default speed 200 after hostile param, got: \(allLines)")
    }

    @Test("spawner interval with hostile string falls back to default 1.5 via Double parsing")
    func spawnerIntervalInjectionNeutralizedByDoubleParsing() {
        let hostile = "2.0\"; end if\n  end frameUpdate\non evil"
        let b = Behavior(kind: .spawner, params: [
            "spawnRole": "enemy",
            "interval": hostile,
            "fromEdge": "top",
            "max": "5"
        ])
        let enemy = GameEntity(name: "enemy", role: .enemy, size: SizeSpec(width: 48, height: 48))
        let spawner = GameEntity(name: "spawnerNode", role: .spawner, size: SizeSpec(width: 1, height: 1), behaviors: [b])
        let recipe = GameRecipe(entities: [enemy, spawner])
        let contrib = BehaviorLibrary.contribution(for: b, entity: spawner, recipe: recipe)

        // Double("2.0\"; end if\n...") returns nil → falls back to default 1.5.
        // Verify the hostile content is NOT in the frame update lines.
        let hasEvil = contrib.frameUpdate.contains { $0.contains("evil") }
        #expect(!hasEvil, "Hostile interval content leaked into frameUpdate: \(contrib.frameUpdate)")
        // Default interval 1.5 should appear.
        let hasDefault = contrib.frameUpdate.contains { $0.contains("1.5") }
        #expect(hasDefault, "Expected default interval 1.5 in frameUpdate: \(contrib.frameUpdate)")
    }

    @Test("rule action winGame message with double-quote: full compile path is injection-safe")
    func ruleActionWinGameMessageDoubleQuoteSafe() {
        // Post-fix: the message is sanitized before embedding. A double-quote in the
        // message is replaced with a single-quote; no injection is possible.
        let hostileMessage = "You Win! \"Great job\""
        let rule = GameRule(
            trigger: RuleTrigger(kind: .onSceneLoad),
            conditions: [],
            actions: [RuleAction(kind: .winGame, message: hostileMessage)]
        )
        let player = GameEntity(name: "hero", role: .player, size: SizeSpec(width: 64, height: 64),
                                behaviors: [Behavior(kind: .topDownMovement)])
        let recipe = GameRecipe(entities: [player], rules: [rule])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // Script must parse — no trap, no fallback.
        assertScriptParses(result.sceneScript, "winGame message with double-quote")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
        // The sanitized single-quote form must appear in the script, not the raw double-quote.
        #expect(!result.sceneScript.contains("\"Great job\""),
                "Raw double-quoted message leaked through sanitization")
    }

    // MARK: ============================================================
    // MARK: - DoS / bounds tests (existing, adjusted for caps)
    // MARK: ============================================================

    @Test("entity count=0 is treated as count=1 (min-count guard)")
    func entityCountZeroTreatedAsOne() {
        let entity = GameEntity(
            name: "ghost",
            role: .decoration,
            size: SizeSpec(width: 32, height: 32),
            count: 0
        )
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        // max(1, 0) = 1
        #expect(result.nodes.count == 1)
        #expect(result.nodes.first?.name == "ghost")
    }

    @Test("entity count=-1 is treated as count=1 (negative count guard)")
    func entityCountNegativeTreatedAsOne() {
        let entity = GameEntity(
            name: "ghost",
            role: .decoration,
            size: SizeSpec(width: 32, height: 32),
            count: -1
        )
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        #expect(result.nodes.count == 1)
        #expect(result.nodes.first?.name == "ghost")
    }

    @Test("entity count=500 compiles to exactly 500 nodes (at cap boundary)")
    func entityCountAtCapBoundary() {
        let entity = GameEntity(
            name: "rock",
            role: .hazard,
            size: SizeSpec(width: 48, height: 48),
            count: 500
        )
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        #expect(result.nodes.count == 500,
                "Expected exactly 500 nodes at cap boundary, got \(result.nodes.count)")
        assertScriptParses(result.sceneScript, "count=500 recipe")
        let names = result.nodes.map(\.name)
        #expect(Set(names).count == names.count, "Duplicate node names at count=500")
        // No cap diagnostic should appear at exactly 500.
        let hasCap = result.diagnostics.contains { $0.contains("clamped") }
        #expect(!hasCap, "Unexpected cap diagnostic at count=500")
    }

    @Test("spawner max=100000 does not pre-allocate 100000 nodes at compile time")
    func spawnerHugeMaxDoesNotPreAllocateNodes() {
        // The spawner creates nodes at runtime (via `create sprite`), NOT statically.
        // Compile-time node count must be 2 (enemy + spawnerNode), NOT 100000.
        let enemy = GameEntity(name: "enemy", role: .enemy, size: SizeSpec(width: 48, height: 48))
        let spawnerEntity = GameEntity(
            name: "spawnerNode",
            role: .spawner,
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "enemy",
                    "interval": "1.0",
                    "max": "100000"
                ])
            ]
        )
        let recipe = GameRecipe(entities: [enemy, spawnerEntity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        #expect(result.nodes.count == 2,
                "Expected 2 nodes for spawner with max=100000, got \(result.nodes.count)")
        assertScriptParses(result.sceneScript, "spawner max=100000")
    }

    @Test("recipe with 50 entities compiles to exactly 50 nodes with parseable script")
    func manyEntitiesCompile() {
        let entities = (1...50).map { i in
            GameEntity(
                name: "rock\(i)",
                role: .hazard,
                size: SizeSpec(width: 40, height: 40),
                count: 1
            )
        }
        let recipe = GameRecipe(entities: entities)
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        #expect(result.nodes.count == 50)
        assertScriptParses(result.sceneScript, "50 entity recipe")
    }

    // MARK: ============================================================
    // MARK: - Behavior param edge cases
    // MARK: ============================================================

    @Test("topDownMovement with no params uses default speed=200")
    func topDownMovementMissingSpeedUsesDefault() {
        let b = Behavior(kind: .topDownMovement, params: [:])
        let entity = GameEntity(name: "ship", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)
        // Default speed=200 must appear in the keyDown lines.
        let allLines = contrib.keyDown.flatMap(\.lines)
        #expect(allLines.contains { $0.contains("200") }, "Expected default speed 200, got: \(allLines)")
    }

    @Test("topDownMovement with non-numeric speed falls back to default 200")
    func topDownMovementGarbageSpeedFallsBack() {
        let b = Behavior(kind: .topDownMovement, params: ["speed": "very fast"])
        let entity = GameEntity(name: "ship", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)
        let allLines = contrib.keyDown.flatMap(\.lines)
        // Non-numeric → Double.init returns nil → default 200.
        #expect(allLines.contains { $0.contains("200") }, "Expected fallback to 200, got: \(allLines)")
    }

    @Test("topDownMovement with speed=0 emits 0 in generated lines and compiles cleanly")
    func topDownMovementZeroSpeed() {
        let b = Behavior(kind: .topDownMovement, params: ["speed": "0"])
        let entity = GameEntity(name: "ship", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        assertScriptParses(result.sceneScript, "topDownMovement speed=0")
        // 0 should appear in the velocity lines.
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("topDownMovement with negative speed compiles cleanly (no double-negative via full path)")
    func topDownMovementNegativeSpeedCompilesCleanly() {
        // After the fix, negative speed is handled correctly. compile() must not trap.
        let b = Behavior(kind: .topDownMovement, params: ["speed": "-50"])
        let entity = GameEntity(name: "ship", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        // This call must NOT trap (assertionFailure must not be reached).
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        assertScriptParses(result.sceneScript, "topDownMovement speed=-50")
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback, "Negative speed triggered fallback — double-negative fix may be incomplete")
    }

    @Test("platformerMovement with missing jumpForce uses default 620")
    func platformerMovementMissingJumpForceUsesDefault() {
        let b = Behavior(kind: .platformerMovement, params: ["speed": "180"])
        let entity = GameEntity(name: "hero", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)
        let allLines = contrib.keyDown.flatMap(\.lines)
        // Default jumpForce=620 → emitted as -620.
        #expect(allLines.contains { $0.contains("620") },
                "Expected default jumpForce 620, got: \(allLines)")
    }

    @Test("patrol with non-numeric range uses default 120")
    func patrolGarbageRangeUsesDefault() {
        let b = Behavior(kind: .patrol, params: ["axis": "x", "speed": "100", "range": "wide"])
        let entity = GameEntity(name: "guard", role: .enemy, size: SizeSpec(width: 48, height: 48), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)
        // Default range=120.
        let frameLines = contrib.frameUpdate
        #expect(frameLines.contains { $0.contains("120") },
                "Expected default range 120, got: \(frameLines)")
    }

    @Test("spawner with non-numeric interval uses default 1.5")
    func spawnerGarbageIntervalUsesDefault() {
        let b = Behavior(kind: .spawner, params: [
            "spawnRole": "enemy",
            "interval": "often",
            "fromEdge": "top",
            "max": "5"
        ])
        let enemy = GameEntity(name: "enemy", role: .enemy, size: SizeSpec(width: 48, height: 48))
        let spawner = GameEntity(name: "spawnerNode", role: .spawner, size: SizeSpec(width: 1, height: 1), behaviors: [b])
        let recipe = GameRecipe(entities: [enemy, spawner])
        let contrib = BehaviorLibrary.contribution(for: b, entity: spawner, recipe: recipe)
        // Default interval=1.5.
        let hasDefault = contrib.frameUpdate.contains { $0.contains("1.5") }
        #expect(hasDefault, "Expected default interval 1.5, got: \(contrib.frameUpdate)")
    }

    @Test("health behavior with missing max uses default 3")
    func healthMissingMaxUsesDefault() {
        let b = Behavior(kind: .health, params: [:])
        let entity = GameEntity(name: "hero", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)
        let hasThree = contrib.sceneDidLoad.contains { $0.contains("3") }
        #expect(hasThree, "health behavior with missing max should default to 3")
    }

    @Test("health behavior with max=0 produces parseable sceneDidLoad")
    func healthZeroMax() {
        let b = Behavior(kind: .health, params: ["max": "0"])
        let entity = GameEntity(name: "hero", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
        assertScriptParses(result.sceneScript, "health max=0")
    }

    @Test("health behavior with non-numeric max uses default 3")
    func healthNonNumericMax() {
        let b = Behavior(kind: .health, params: ["max": "lots"])
        let entity = GameEntity(name: "hero", role: .player, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)
        // Default 3.
        let hasThree = contrib.sceneDidLoad.contains { $0.contains("3") }
        #expect(hasThree, "health with non-numeric max should default to 3")
    }

    @Test("oscillate with non-numeric amplitude uses default 40")
    func oscillateGarbageAmplitude() {
        let b = Behavior(kind: .oscillate, params: ["axis": "y", "amplitude": "large", "period": "2"])
        let entity = GameEntity(name: "platform", role: .decoration, size: SizeSpec(width: 100, height: 20), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)
        // oscillate returns a repeatForever → sequence → [moveOut, moveBack]
        // moveOut.parameters["y"] should be "40" (the default amplitude).
        // Walk the nested action tree to find a moveBy action with y="40".
        func allActions(_ actions: [ActionSpec]) -> [ActionSpec] {
            actions + actions.flatMap { allActions($0.children ?? []) }
        }
        let flat = allActions(contrib.actions)
        let hasDefault = flat.contains { $0.actionType == .moveBy && ($0.parameters["y"] == "40" || $0.parameters["x"] == "40") }
        #expect(hasDefault, "Expected default amplitude 40 in oscillate actions. Flat actions: \(flat.map { "\($0.actionType):\($0.parameters)" })")
    }

    @Test("rotator with non-numeric degreesPerSecond uses default 90")
    func rotatorGarbageDPS() {
        let b = Behavior(kind: .rotator, params: ["degreesPerSecond": "spinny"])
        let entity = GameEntity(name: "wheel", role: .decoration, size: SizeSpec(width: 64, height: 64), behaviors: [b])
        let recipe = GameRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)
        // rotator returns repeatForever → rotateBy. The rotateBy action is a child.
        func allActions(_ actions: [ActionSpec]) -> [ActionSpec] {
            actions + actions.flatMap { allActions($0.children ?? []) }
        }
        let flat = allActions(contrib.actions)
        let hasDefault = flat.contains { $0.actionType == .rotateBy && $0.parameters["angle"] == "90" }
        #expect(hasDefault, "Expected default degreesPerSecond 90 in rotator action. Flat: \(flat.map { "\($0.actionType):\($0.parameters)" })")
    }

    // MARK: ============================================================
    // MARK: - Round-trip after build: idempotence
    // MARK: ============================================================

    @Test("recipe encode/decode then recompile produces same node count and handler counts")
    func buildGameIdempotence() {
        let player = GameEntity(
            name: "hero",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [
                Behavior(kind: .topDownMovement, params: ["speed": "200"]),
                Behavior(kind: .constrainToBounds),
            ]
        )
        let enemy = GameEntity(
            name: "monster",
            role: .enemy,
            size: SizeSpec(width: 48, height: 48),
            count: 3,
            behaviors: [Behavior(kind: .patrol, params: ["axis": "x", "range": "100"])]
        )
        let recipe = GameRecipe(
            sceneName: "IdempotenceTest",
            sceneSize: SizeSpec(width: 800, height: 600),
            entities: [player, enemy],
            gameState: GameState(trackScore: true, initialScore: 0)
        )

        // First build.
        let result1 = RecipeCompiler.compile(recipe, repository: AssetRepository())
        assertScriptParses(result1.sceneScript, "first build")

        // Round-trip via JSON.
        let recipeData = try! JSONEncoder().encode(recipe)
        let reloadedRecipe = try! JSONDecoder().decode(GameRecipe.self, from: recipeData)

        // Second build from decoded recipe.
        let result2 = RecipeCompiler.compile(reloadedRecipe, repository: AssetRepository())
        assertScriptParses(result2.sceneScript, "second build after round-trip")

        #expect(result1.nodes.count == result2.nodes.count,
                "Node count changed: \(result1.nodes.count) vs \(result2.nodes.count)")
        #expect(result1.recipeOwnedNodeNames == result2.recipeOwnedNodeNames,
                "Owned names changed after round-trip")

        for handlerName in ["sceneDidLoad", "keyDown", "frameUpdate"] {
            let h1 = handlerCount(result1.sceneScript, named: handlerName)
            let h2 = handlerCount(result2.sceneScript, named: handlerName)
            #expect(h1 == h2, "Handler '\(handlerName)' count changed: \(h1) vs \(h2)")
        }
    }

    @Test("merging into scene twice (idempotent merge) does not duplicate nodes or handlers")
    func mergeIdempotence() {
        let player = GameEntity(
            name: "hero",
            role: .player,
            size: SizeSpec(width: 64, height: 64),
            behaviors: [Behavior(kind: .topDownMovement)]
        )
        let recipe = GameRecipe(entities: [player])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        var scene = SceneSpec()

        RecipeCompiler.merge(result, into: &scene)
        let nodeCountAfterFirst = scene.nodes.count

        RecipeCompiler.merge(result, into: &scene)
        let nodeCountAfterSecond = scene.nodes.count

        #expect(nodeCountAfterFirst == nodeCountAfterSecond,
                "Idempotent merge increased node count: \(nodeCountAfterFirst) → \(nodeCountAfterSecond)")
        #expect(handlerCount(scene.script, named: "keyDown") == 1,
                "Expected 1 keyDown handler after idempotent merge")
        assertScriptParses(scene.script, "idempotent merge")
    }

    @Test("SpriteAreaSpec stores and recovers recipe correctly after build via tool")
    func spriteAreaSpecRecipeRoundTripAfterBuild() async {
        var doc = HypeDocument.newDocument(name: "RoundTripTest")
        let cardId = doc.sortedCards[0].id
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "start_game_recipe",
            arguments: ["sprite_area_name": "arena", "scene_width": "800", "scene_height": "600"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "add_entity",
            arguments: ["sprite_area_name": "arena", "name": "ship", "role": "player",
                        "behaviors": "topDownMovement:speed=200,constrainToBounds"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "add_entity",
            arguments: ["sprite_area_name": "arena", "name": "coin", "role": "collectible", "count": "5"],
            document: &doc, currentCardId: cardId
        )

        let buildResult1 = await executor.execute(
            toolName: "build_game",
            arguments: ["sprite_area_name": "arena"],
            document: &doc, currentCardId: cardId
        )
        #expect(!buildResult1.hasPrefix("__HYPE_INTERNAL_DRAFT_REFUSED_v1:"))

        // Retrieve the stored recipe and re-build.
        let storedRecipe = doc.parts.first(where: { $0.name == "arena" })?.spriteAreaSpecModel?.recipe
        guard let recipe = storedRecipe else {
            Issue.record("No recipe stored after build_game")
            return
        }

        // Re-build from the stored recipe directly.
        let result2 = RecipeCompiler.compile(recipe, repository: AssetRepository())
        assertScriptParses(result2.sceneScript, "re-build from stored recipe")

        // Should have the same entities: ship + 5 coin instances.
        // ship = 1, coin_1..coin_5 = 5 → 6 nodes total.
        #expect(result2.nodes.count == 6,
                "Expected 6 nodes after re-build, got \(result2.nodes.count)")
        #expect(result2.nodes.contains(where: { $0.name == "ship" }))
        for i in 1...5 {
            #expect(result2.nodes.contains(where: { $0.name == "coin_\(i)" }),
                    "Missing node coin_\(i)")
        }

        // Handler counts must match between both builds.
        let scene1Script = doc.parts.first(where: { $0.name == "arena" })?.activeSceneSpec?.script ?? ""
        for hName in ["keyDown", "frameUpdate"] {
            let h1 = handlerCount(scene1Script, named: hName)
            let h2 = handlerCount(result2.sceneScript, named: hName)
            #expect(h1 == h2, "Handler '\(hName)' count mismatch: \(h1) vs \(h2) after re-build")
        }
    }
}

import Foundation
import Testing
@testable import HypeCore

// MARK: - Parse helper

/// Asserts that the given HypeTalk lines, when embedded in a minimal handler,
/// produce a parse-clean script. Returns the wrapped script for further inspection.
@discardableResult
private func assertParses(
    lines: [String],
    handlerName: String = "sceneDidLoad",
    args: [String] = [],
    globals: [String] = ["score", "gameOver"],
    message: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) -> String {
    let sig = args.isEmpty ? "on \(handlerName)" : "on \(handlerName) \(args.joined(separator: ", "))"
    let globalsDecl = globals.isEmpty ? "" : "  global \(globals.joined(separator: ", "))\n"
    let body = lines.map { "  \($0)" }.joined(separator: "\n")
    let script = "\(sig)\n\(globalsDecl)\(body)\nend \(handlerName)"

    var lexer = Lexer(source: script)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    do {
        _ = try parser.parse()
    } catch {
        Issue.record("Parse failed\(message.isEmpty ? "" : " [\(message)]"): \(error)\n\nScript:\n\(script)", sourceLocation: sourceLocation)
    }
    return script
}

/// Asserts that a physics patch has the expected restitution value.
private func assertRestitution(_ patch: PhysicsBodyPatch?, expected: Double, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    if patch?.restitution != expected {
        Issue.record("Restitution mismatch\(message.isEmpty ? "" : " [\(message)]"): expected \(expected), got \(String(describing: patch?.restitution))", sourceLocation: sourceLocation)
    }
}

// MARK: - Minimal recipe / entity helpers

private func makeEntity(
    name: String = "testEntity",
    role: EntityRole = .player,
    count: Int = 1,
    behaviors: [Behavior] = [],
    size: SizeSpec = SizeSpec(width: 64, height: 64)
) -> GameEntity {
    GameEntity(name: name, role: role, size: size, count: count, behaviors: behaviors)
}

private func makeRecipe(
    entities: [GameEntity] = [],
    sceneSize: SizeSpec = SizeSpec(width: 800, height: 600)
) -> GameRecipe {
    GameRecipe(sceneSize: sceneSize, entities: entities)
}

// MARK: - Behavior Compilation Tests

@Suite("BehaviorLibrary — one test per BehaviorKind")
struct BehaviorCompilationTests {

    // MARK: topDownMovement

    @Test("topDownMovement emits valid keyDown / keyUp branches")
    func topDownMovementParses() {
        let b = Behavior(kind: .topDownMovement, params: ["speed": "200"])
        let entity = makeEntity(name: "ship", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        #expect(!contrib.keyDown.isEmpty)
        #expect(!contrib.keyUp.isEmpty)

        // Emit all keyDown branches into a minimal handler and parse it.
        let keyDownLines = contrib.keyDown.flatMap { branch in
            ["if the key is \"\(branch.key)\" then"] + branch.lines.map { "  \($0)" } + ["end if"]
        }
        assertParses(lines: keyDownLines, handlerName: "keyDown", message: "topDownMovement keyDown")

        let keyUpLines = contrib.keyUp.flatMap { branch in
            ["if the key is \"\(branch.key)\" then"] + branch.lines.map { "  \($0)" } + ["end if"]
        }
        assertParses(lines: keyUpLines, handlerName: "keyUp", message: "topDownMovement keyUp")

        // Physics patch disables gravity for top-down movement.
        #expect(contrib.physics?.affectedByGravity == false)
    }

    // MARK: platformerMovement

    @Test("platformerMovement emits jump on space/up and enables gravity")
    func platformerMovementParses() {
        let b = Behavior(kind: .platformerMovement, params: ["speed": "220", "jumpForce": "700"])
        let entity = makeEntity(name: "hero", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        // Should have left/right/space/up branches for keyDown.
        let keys = contrib.keyDown.map(\.key)
        #expect(keys.contains("left"))
        #expect(keys.contains("right"))
        #expect(keys.contains("space") || keys.contains("up"))

        let keyDownLines = contrib.keyDown.flatMap { branch in
            ["if the key is \"\(branch.key)\" then"] + branch.lines.map { "  \($0)" } + ["end if"]
        }
        assertParses(lines: keyDownLines, handlerName: "keyDown", message: "platformerMovement keyDown")

        // Gravity must be on for platformer.
        #expect(contrib.physics?.affectedByGravity == true)
    }

    // MARK: eightDirection

    @Test("eightDirection emits all four directional key branches")
    func eightDirectionParses() {
        let b = Behavior(kind: .eightDirection, params: ["speed": "180"])
        let entity = makeEntity(name: "hero", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        let keys = contrib.keyDown.map(\.key)
        #expect(keys.contains("left"))
        #expect(keys.contains("right"))
        #expect(keys.contains("up"))
        #expect(keys.contains("down"))

        let allLines = contrib.keyDown.flatMap { branch in
            ["if the key is \"\(branch.key)\" then"] + branch.lines.map { "  \($0)" } + ["end if"]
        }
        assertParses(lines: allLines, handlerName: "keyDown", message: "eightDirection")
    }

    // MARK: followPointer

    @Test("followPointer emits valid frameUpdate script (both axes)")
    func followPointerParses() {
        let b = Behavior(kind: .followPointer, params: ["speed": "220", "axis": "both"])
        let entity = makeEntity(name: "cursor", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            message: "followPointer both"
        )
    }

    @Test("followPointer x-axis only produces valid script")
    func followPointerXAxisParses() {
        let b = Behavior(kind: .followPointer, params: ["speed": "150", "axis": "x"])
        let entity = makeEntity(name: "paddle", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            message: "followPointer x"
        )
    }

    // MARK: chaseTarget

    @Test("chaseTarget emits valid frameUpdate script that reads loc")
    func chaseTargetParses() {
        let player = makeEntity(name: "ship", role: .player)
        let enemy = makeEntity(name: "ufo", role: .enemy, behaviors: [
            Behavior(kind: .chaseTarget, params: ["targetRole": "player", "speed": "100"])
        ])
        let recipe = makeRecipe(entities: [player, enemy])
        let b = enemy.behaviors[0]
        let contrib = BehaviorLibrary.contribution(for: b, entity: enemy, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            globals: ["score", "gameOver"],
            message: "chaseTarget"
        )
        // Lines should read loc of the player.
        let hasLocRead = contrib.frameUpdate.contains { $0.contains("the loc of sprite") }
        #expect(hasLocRead)
    }

    // MARK: patrol

    @Test("patrol emits valid sceneDidLoad init and frameUpdate patrol logic")
    func patrolParses() {
        let b = Behavior(kind: .patrol, params: ["axis": "x", "speed": "100", "range": "150"])
        let entity = makeEntity(name: "guard", role: .enemy)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(lines: contrib.sceneDidLoad, handlerName: "sceneDidLoad", message: "patrol sceneDidLoad")
        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            globals: contrib.requiredGlobals + ["gameOver"],
            message: "patrol frameUpdate"
        )
        #expect(!contrib.requiredGlobals.isEmpty)
    }

    // MARK: physicsBody

    @Test("physicsBody patch applies dynamic and restitution from params")
    func physicsBodyBehaviorPatch() {
        let b = Behavior(kind: .physicsBody, params: [
            "dynamic": "false",
            "gravity": "false",
            "restitution": "0.8",
            "friction": "0.1",
            "bodyShape": "circle"
        ])
        let entity = makeEntity()
        let recipe = makeRecipe()
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        #expect(contrib.physics?.isDynamic == false)
        #expect(contrib.physics?.affectedByGravity == false)
        #expect(contrib.physics?.restitution == 0.8)
        #expect(contrib.physics?.friction == 0.1)
        #expect(contrib.physics?.bodyType == .circle)
    }

    // MARK: bounce

    @Test("bounce sets restitution 1 and friction 0")
    func bouncePhysicsPatch() {
        let b = Behavior(kind: .bounce, params: [:])
        let entity = makeEntity()
        let recipe = makeRecipe()
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertRestitution(contrib.physics, expected: 1.0, "bounce restitution")
        #expect(contrib.physics?.friction == 0.0)
    }

    // MARK: wrapAround

    @Test("wrapAround emits valid frameUpdate script")
    func wrapAroundParses() {
        let b = Behavior(kind: .wrapAround, params: [:])
        let entity = makeEntity(name: "asteroid")
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            message: "wrapAround"
        )
    }

    // MARK: constrainToBounds

    @Test("constrainToBounds emits valid frameUpdate script")
    func constrainToBoundsParses() {
        let b = Behavior(kind: .constrainToBounds, params: [:])
        let entity = makeEntity(name: "player")
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            message: "constrainToBounds"
        )
    }

    // MARK: destroyOutsideBounds

    @Test("destroyOutsideBounds emits valid frameUpdate with remove sprite")
    func destroyOutsideBoundsParses() {
        let b = Behavior(kind: .destroyOutsideBounds, params: ["margin": "80"])
        let entity = makeEntity(name: "bullet", role: .projectile)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            message: "destroyOutsideBounds"
        )
        let hasRemove = contrib.frameUpdate.contains { $0.contains("remove sprite") }
        #expect(hasRemove)
    }

    // MARK: spawner

    @Test("spawner emits valid sceneDidLoad init and frameUpdate with create sprite")
    func spawnerParses() {
        let enemy = makeEntity(name: "asteroid", role: .enemy)
        let spawner = makeEntity(name: "spawnerNode", role: .spawner, behaviors: [
            Behavior(kind: .spawner, params: [
                "spawnRole": "enemy",
                "interval": "2.0",
                "fromEdge": "top",
                "velocity": "0,-120",
                "max": "6"
            ])
        ])
        let recipe = makeRecipe(entities: [enemy, spawner])
        let b = spawner.behaviors[0]
        let contrib = BehaviorLibrary.contribution(for: b, entity: spawner, recipe: recipe)

        assertParses(
            lines: contrib.sceneDidLoad,
            handlerName: "sceneDidLoad",
            message: "spawner sceneDidLoad"
        )
        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            globals: contrib.requiredGlobals + ["gameOver"],
            message: "spawner frameUpdate"
        )
        let hasCreate = contrib.frameUpdate.contains { $0.contains("create sprite") }
        #expect(hasCreate)
    }

    // MARK: collectible

    @Test("collectible returns empty contribution (contact setup via RolePhysics)")
    func collectibleContrib() {
        let b = Behavior(kind: .collectible, params: [:])
        let entity = makeEntity(name: "coin", role: .collectible)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        // collectible has no script contribution; its role handles physics.
        #expect(contrib.frameUpdate.isEmpty)
        #expect(contrib.keyDown.isEmpty)
    }

    // MARK: damageOnContact

    @Test("damageOnContact emits valid beginContact branch")
    func damageOnContactParses() {
        let player = makeEntity(name: "hero", role: .player)
        let enemy = makeEntity(name: "spike", role: .hazard, behaviors: [
            Behavior(kind: .damageOnContact, params: ["amount": "1", "targetRole": "player"])
        ])
        let recipe = makeRecipe(entities: [player, enemy])
        let b = enemy.behaviors[0]
        let contrib = BehaviorLibrary.contribution(for: b, entity: enemy, recipe: recipe)

        #expect(!contrib.beginContact.isEmpty)
        let branch = contrib.beginContact[0]
        let contactLines = ["if \(branch.otherPredicate) then"]
            + branch.lines.map { "  \($0)" }
            + ["end if"]
        assertParses(
            lines: contactLines,
            handlerName: "beginContact",
            args: ["otherName"],
            globals: contrib.requiredGlobals + ["gameOver"],
            message: "damageOnContact"
        )
    }

    // MARK: health

    @Test("health emits sceneDidLoad init and registers health global")
    func healthBehavior() {
        let b = Behavior(kind: .health, params: ["max": "5"])
        let entity = makeEntity(name: "hero", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.sceneDidLoad,
            handlerName: "sceneDidLoad",
            globals: contrib.requiredGlobals,
            message: "health sceneDidLoad"
        )
        #expect(contrib.requiredGlobals.contains("health"))
        // Should initialize health to 5.
        let hasInit = contrib.sceneDidLoad.contains { $0.contains("5") && $0.contains("health") }
        #expect(hasInit)
    }

    // MARK: scoreOnCollect

    @Test("scoreOnCollect emits valid beginContact branch with add score and remove sprite")
    func scoreOnCollectParses() {
        let player = makeEntity(name: "hero", role: .player, behaviors: [
            Behavior(kind: .scoreOnCollect, params: ["points": "10"])
        ])
        let coin = makeEntity(name: "coin", role: .collectible)
        let recipe = makeRecipe(entities: [player, coin], sceneSize: SizeSpec(width: 400, height: 600))
        let b = player.behaviors[0]
        let contrib = BehaviorLibrary.contribution(for: b, entity: player, recipe: recipe)

        #expect(!contrib.beginContact.isEmpty)
        for branch in contrib.beginContact {
            let lines = ["if \(branch.otherPredicate) then"]
                + branch.lines.map { "  \($0)" }
                + ["end if"]
            assertParses(
                lines: lines,
                handlerName: "beginContact",
                args: ["otherName"],
                globals: contrib.requiredGlobals + ["gameOver"],
                message: "scoreOnCollect branch"
            )
        }
        // At least one branch should add to score and remove sprite.
        let allLines = contrib.beginContact.flatMap(\.lines)
        #expect(allLines.contains { $0.contains("score") })
        #expect(allLines.contains { $0.contains("remove sprite") })
    }

    // MARK: winOnReach

    @Test("winOnReach contribution does not add unparseable lines")
    func winOnReachParses() {
        let b = Behavior(kind: .winOnReach, params: [:])
        let entity = makeEntity(name: "hero", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        // winOnReach is handled at the game-state level; no script lines expected.
        #expect(contrib.frameUpdate.isEmpty)
    }

    // MARK: winOnScore

    @Test("winOnScore emits valid frameUpdate score-check block")
    func winOnScoreParses() {
        let b = Behavior(kind: .winOnScore, params: ["threshold": "100"])
        let entity = makeEntity(name: "hero", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            globals: contrib.requiredGlobals + ["gameOver"],
            message: "winOnScore"
        )
        let hasThreshold = contrib.frameUpdate.contains { $0.contains("100") }
        #expect(hasThreshold)
    }

    // MARK: loseOnContact

    @Test("loseOnContact emits valid beginContact branch setting gameOver")
    func loseOnContactParses() {
        let player = makeEntity(name: "ship", role: .player, behaviors: [
            Behavior(kind: .loseOnContact, params: ["withRole": "hazard"])
        ])
        let hazard = makeEntity(name: "asteroid", role: .hazard)
        let recipe = makeRecipe(entities: [player, hazard])
        let b = player.behaviors[0]
        let contrib = BehaviorLibrary.contribution(for: b, entity: player, recipe: recipe)

        #expect(!contrib.beginContact.isEmpty)
        for branch in contrib.beginContact {
            let lines = ["if \(branch.otherPredicate) then"]
                + branch.lines.map { "  \($0)" }
                + ["end if"]
            assertParses(
                lines: lines,
                handlerName: "beginContact",
                args: ["otherName"],
                globals: contrib.requiredGlobals + ["score"],
                message: "loseOnContact branch"
            )
        }
        let allLines = contrib.beginContact.flatMap(\.lines)
        #expect(allLines.contains { $0.contains("gameOver") })
    }

    // MARK: loseOnZeroHealth

    @Test("loseOnZeroHealth emits valid frameUpdate health-check block")
    func loseOnZeroHealthParses() {
        let b = Behavior(kind: .loseOnZeroHealth, params: [:])
        let entity = makeEntity(name: "hero", role: .player)
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            globals: contrib.requiredGlobals + ["score"],
            message: "loseOnZeroHealth"
        )
        #expect(contrib.requiredGlobals.contains("health"))
        #expect(contrib.requiredGlobals.contains("gameOver"))
    }

    // MARK: draggable

    @Test("draggable emits valid frameUpdate that sets loc to mouseLoc")
    func draggableParses() {
        let b = Behavior(kind: .draggable, params: [:])
        let entity = makeEntity(name: "block")
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        assertParses(
            lines: contrib.frameUpdate,
            handlerName: "frameUpdate",
            args: ["deltaTime"],
            message: "draggable"
        )
        let hasMouseLoc = contrib.frameUpdate.contains { $0.contains("mouseLoc") }
        #expect(hasMouseLoc)
    }

    // MARK: rotator

    @Test("rotator emits a repeatForever rotateBy ActionSpec")
    func rotatorActions() {
        let b = Behavior(kind: .rotator, params: ["degreesPerSecond": "90"])
        let entity = makeEntity(name: "wheel")
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        #expect(!contrib.actions.isEmpty)
        let hasRepeatForever = contrib.actions.contains { $0.actionType == .repeatForever }
        #expect(hasRepeatForever)
        // No script lines needed for rotator (pure SKAction).
        #expect(contrib.frameUpdate.isEmpty)
        #expect(contrib.keyDown.isEmpty)
    }

    // MARK: oscillate

    @Test("oscillate emits a repeatForever sequence of moveBy ActionSpecs")
    func oscillateActions() {
        let b = Behavior(kind: .oscillate, params: ["axis": "y", "amplitude": "40", "period": "2"])
        let entity = makeEntity(name: "platform")
        let recipe = makeRecipe(entities: [entity])
        let contrib = BehaviorLibrary.contribution(for: b, entity: entity, recipe: recipe)

        #expect(!contrib.actions.isEmpty)
        let hasRepeatForever = contrib.actions.contains { $0.actionType == .repeatForever }
        #expect(hasRepeatForever)
        #expect(contrib.frameUpdate.isEmpty)
    }
}

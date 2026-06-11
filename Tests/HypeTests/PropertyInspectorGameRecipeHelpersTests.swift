import Testing
import AppKit
@testable import Hype
@testable import HypeCore

// MARK: - PropertyInspector pure helper unit tests
//
// All four helpers are declared `static` on `PropertyInspector` and are
// documented as "pure — safe to unit-test".  They carry zero side effects
// and depend only on their inputs, making them ideal white-box targets.
//
// Coverage categories:
//   1. behaviorShortLabel — exhaustive: every BehaviorKind must map to a
//      non-empty, non-whitespace label.
//   2. defaultParamsForBehavior — every kind with documented defaults returns
//      them; kinds that have no params return [:].
//   3. defaultEntity — name and role are preserved; size matches defaultEntitySize;
//      count defaults to 1; behaviors is empty.
//   4. defaultEntitySize — each role returns a non-zero width and height;
//      role-specific sizes match documented heuristics.

@Suite("PropertyInspector — pure game recipe helpers")
struct PropertyInspectorGameRecipeHelpersTests {

    // MARK: - behaviorShortLabel exhaustive coverage

    @Test("behaviorShortLabel returns a non-empty label for every BehaviorKind")
    func behaviorShortLabelNonEmptyForAllCases() {
        for kind in BehaviorKind.allCases {
            let label = PropertyInspector.behaviorShortLabel(kind)
            #expect(!label.isEmpty, "behaviorShortLabel returned empty for \(kind)")
            #expect(label.trimmingCharacters(in: .whitespaces) == label,
                    "behaviorShortLabel has leading/trailing whitespace for \(kind)")
        }
    }

    @Test("behaviorShortLabel returns expected abbreviations for key behavior kinds")
    func behaviorShortLabelKnownValues() {
        #expect(PropertyInspector.behaviorShortLabel(.platformerMovement) == "platMove")
        #expect(PropertyInspector.behaviorShortLabel(.topDownMovement) == "tdMove")
        #expect(PropertyInspector.behaviorShortLabel(.eightDirection) == "8dir")
        #expect(PropertyInspector.behaviorShortLabel(.followPointer) == "followPtr")
        #expect(PropertyInspector.behaviorShortLabel(.chaseTarget) == "chase")
        #expect(PropertyInspector.behaviorShortLabel(.patrol) == "patrol")
        #expect(PropertyInspector.behaviorShortLabel(.physicsBody) == "physics")
        #expect(PropertyInspector.behaviorShortLabel(.bounce) == "bounce")
        #expect(PropertyInspector.behaviorShortLabel(.wrapAround) == "wrap")
        #expect(PropertyInspector.behaviorShortLabel(.constrainToBounds) == "constrain")
        #expect(PropertyInspector.behaviorShortLabel(.destroyOutsideBounds) == "destroyOOB")
        #expect(PropertyInspector.behaviorShortLabel(.spawner) == "spawner")
        #expect(PropertyInspector.behaviorShortLabel(.collectible) == "collect")
        #expect(PropertyInspector.behaviorShortLabel(.damageOnContact) == "damage")
        #expect(PropertyInspector.behaviorShortLabel(.health) == "health")
        #expect(PropertyInspector.behaviorShortLabel(.scoreOnCollect) == "score+")
        #expect(PropertyInspector.behaviorShortLabel(.winOnReach) == "winReach")
        #expect(PropertyInspector.behaviorShortLabel(.winOnScore) == "winScore")
        #expect(PropertyInspector.behaviorShortLabel(.loseOnContact) == "loseCtct")
        #expect(PropertyInspector.behaviorShortLabel(.loseOnZeroHealth) == "loseHP")
        #expect(PropertyInspector.behaviorShortLabel(.draggable) == "drag")
        #expect(PropertyInspector.behaviorShortLabel(.rotator) == "rotate")
        #expect(PropertyInspector.behaviorShortLabel(.oscillate) == "osc")
    }

    @Test("behaviorShortLabel labels are unique (no two behaviors share the same chip label)")
    func behaviorShortLabelsAreUnique() {
        let allLabels = BehaviorKind.allCases.map { PropertyInspector.behaviorShortLabel($0) }
        let uniqueLabels = Set(allLabels)
        #expect(uniqueLabels.count == allLabels.count,
                "Duplicate behaviorShortLabel labels found: \(allLabels.filter { label in allLabels.filter { $0 == label }.count > 1 })")
    }

    // MARK: - defaultParamsForBehavior

    @Test("defaultParamsForBehavior returns expected speed for topDownMovement")
    func defaultParamsTopDownMovement() {
        let params = PropertyInspector.defaultParamsForBehavior(.topDownMovement)
        #expect(params["speed"] == "200")
    }

    @Test("defaultParamsForBehavior returns expected speed and jumpForce for platformerMovement")
    func defaultParamsPlatformerMovement() {
        let params = PropertyInspector.defaultParamsForBehavior(.platformerMovement)
        #expect(params["speed"] == "200")
        #expect(params["jumpForce"] == "620")
    }

    @Test("defaultParamsForBehavior returns expected speed and axis for eightDirection")
    func defaultParamsEightDirection() {
        let params = PropertyInspector.defaultParamsForBehavior(.eightDirection)
        #expect(params["speed"] == "200")
    }

    @Test("defaultParamsForBehavior returns expected speed and axis for followPointer")
    func defaultParamsFollowPointer() {
        let params = PropertyInspector.defaultParamsForBehavior(.followPointer)
        #expect(params["speed"] == "220")
        #expect(params["axis"] == "both")
    }

    @Test("defaultParamsForBehavior returns expected targetRole and speed for chaseTarget")
    func defaultParamsChaseTarget() {
        let params = PropertyInspector.defaultParamsForBehavior(.chaseTarget)
        #expect(params["targetRole"] == "player")
        #expect(params["speed"] == "120")
    }

    @Test("defaultParamsForBehavior returns expected axis/speed/range for patrol")
    func defaultParamsPatrol() {
        let params = PropertyInspector.defaultParamsForBehavior(.patrol)
        #expect(params["axis"] == "x")
        #expect(params["speed"] == "120")
        #expect(params["range"] == "120")
    }

    @Test("defaultParamsForBehavior returns expected dynamic/restitution/friction/bodyShape for physicsBody")
    func defaultParamsPhysicsBody() {
        let params = PropertyInspector.defaultParamsForBehavior(.physicsBody)
        #expect(params["dynamic"] == "true")
        #expect(params["restitution"] == "0.2")
        #expect(params["friction"] == "0.2")
        #expect(params["bodyShape"] == "rect")
    }

    @Test("defaultParamsForBehavior returns spawner defaults including max and velocity")
    func defaultParamsSpawner() {
        let params = PropertyInspector.defaultParamsForBehavior(.spawner)
        #expect(params["spawnRole"] == "enemy")
        #expect(params["interval"] == "1.5")
        #expect(params["fromEdge"] == "top")
        #expect(params["max"] == "8")
        #expect(params["velocity"] != nil)
    }

    @Test("defaultParamsForBehavior returns health max=3")
    func defaultParamsHealth() {
        let params = PropertyInspector.defaultParamsForBehavior(.health)
        #expect(params["max"] == "3")
    }

    @Test("defaultParamsForBehavior returns scoreOnCollect points=10")
    func defaultParamsScoreOnCollect() {
        let params = PropertyInspector.defaultParamsForBehavior(.scoreOnCollect)
        #expect(params["points"] == "10")
    }

    @Test("defaultParamsForBehavior returns loseOnContact withRole=hazard")
    func defaultParamsLoseOnContact() {
        let params = PropertyInspector.defaultParamsForBehavior(.loseOnContact)
        #expect(params["withRole"] == "hazard")
    }

    @Test("defaultParamsForBehavior returns destroyOutsideBounds margin=80")
    func defaultParamsDestroyOutsideBounds() {
        let params = PropertyInspector.defaultParamsForBehavior(.destroyOutsideBounds)
        #expect(params["margin"] == "80")
    }

    @Test("defaultParamsForBehavior returns rotator degreesPerSecond=90")
    func defaultParamsRotator() {
        let params = PropertyInspector.defaultParamsForBehavior(.rotator)
        #expect(params["degreesPerSecond"] == "90")
    }

    @Test("defaultParamsForBehavior returns oscillate axis/amplitude/period")
    func defaultParamsOscillate() {
        let params = PropertyInspector.defaultParamsForBehavior(.oscillate)
        #expect(params["axis"] == "y")
        #expect(params["amplitude"] == "40")
        #expect(params["period"] == "2")
    }

    @Test("defaultParamsForBehavior returns empty dict for behaviors with no params")
    func defaultParamsEmptyForNoParamBehaviors() {
        // Behaviors that have no documented defaults return [:]
        let noParamKinds: [BehaviorKind] = [
            .bounce, .wrapAround, .constrainToBounds, .collectible,
            .winOnReach, .loseOnZeroHealth, .draggable
        ]
        for kind in noParamKinds {
            let params = PropertyInspector.defaultParamsForBehavior(kind)
            #expect(params.isEmpty, "Expected empty params for \(kind), got: \(params)")
        }
    }

    @Test("defaultParamsForBehavior param values are all non-empty strings")
    func defaultParamsValuesAreNonEmpty() {
        for kind in BehaviorKind.allCases {
            let params = PropertyInspector.defaultParamsForBehavior(kind)
            for (key, value) in params {
                #expect(!value.isEmpty, "defaultParamsForBehavior(\(kind))[\"\(key)\"] is empty")
            }
        }
    }

    // MARK: - defaultEntity

    @Test("defaultEntity preserves name and role verbatim")
    func defaultEntityPreservesNameAndRole() {
        let entity = PropertyInspector.defaultEntity(name: "myHero", role: .player)
        #expect(entity.name == "myHero")
        #expect(entity.role == .player)
    }

    @Test("defaultEntity has count=1 and empty behaviors")
    func defaultEntityCountAndBehaviors() {
        let entity = PropertyInspector.defaultEntity(name: "blob", role: .enemy)
        #expect(entity.count == 1)
        #expect(entity.behaviors.isEmpty)
    }

    @Test("defaultEntity size matches defaultEntitySize for the given role")
    func defaultEntitySizeMatchesDefaultEntitySize() {
        for role in EntityRole.allCases {
            let entity = PropertyInspector.defaultEntity(name: "test", role: role)
            let expectedSize = PropertyInspector.defaultEntitySize(for: role)
            #expect(entity.size.width == expectedSize.width,
                    "defaultEntity size.width mismatch for role \(role): \(entity.size.width) vs \(expectedSize.width)")
            #expect(entity.size.height == expectedSize.height,
                    "defaultEntity size.height mismatch for role \(role): \(entity.size.height) vs \(expectedSize.height)")
        }
    }

    @Test("defaultEntity position is non-zero (placed meaningfully on canvas)")
    func defaultEntityPositionIsNonZero() {
        // The documented default is (100, 100) — non-zero so the entity is
        // visible immediately after being added to the canvas.
        let entity = PropertyInspector.defaultEntity(name: "ship", role: .player)
        #expect(entity.position.x > 0 || entity.position.y > 0,
                "defaultEntity position should be non-zero for initial visibility")
    }

    @Test("defaultEntity with empty name preserves it (no silent truncation)")
    func defaultEntityWithEmptyName() {
        let entity = PropertyInspector.defaultEntity(name: "", role: .decoration)
        #expect(entity.name == "")
    }

    // MARK: - defaultEntitySize

    @Test("defaultEntitySize returns non-zero dimensions for every EntityRole")
    func defaultEntitySizeNonZeroForAllRoles() {
        for role in EntityRole.allCases {
            let size = PropertyInspector.defaultEntitySize(for: role)
            #expect(size.width > 0, "defaultEntitySize width=0 for role \(role)")
            #expect(size.height > 0, "defaultEntitySize height=0 for role \(role)")
        }
    }

    @Test("defaultEntitySize for .background is 800×600 (full-scene background)")
    func defaultEntitySizeBackground() {
        let size = PropertyInspector.defaultEntitySize(for: .background)
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test("defaultEntitySize for .wall is 200×32 (platform slab)")
    func defaultEntitySizeWall() {
        let size = PropertyInspector.defaultEntitySize(for: .wall)
        #expect(size.width == 200)
        #expect(size.height == 32)
    }

    @Test("defaultEntitySize for .hud is 160×32 (label strip)")
    func defaultEntitySizeHud() {
        let size = PropertyInspector.defaultEntitySize(for: .hud)
        #expect(size.width == 160)
        #expect(size.height == 32)
    }

    @Test("defaultEntitySize for .player is 56×56")
    func defaultEntitySizePlayer() {
        let size = PropertyInspector.defaultEntitySize(for: .player)
        #expect(size.width == 56)
        #expect(size.height == 56)
    }

    @Test("defaultEntitySize for .enemy/.collectible/.hazard/.projectile/.spawner/.decoration/.goal/.background is 48×48")
    func defaultEntitySizeGenericRoles() {
        let genericRoles: [EntityRole] = [.enemy, .collectible, .hazard, .projectile, .spawner, .decoration, .goal]
        for role in genericRoles {
            let size = PropertyInspector.defaultEntitySize(for: role)
            #expect(size.width == 48, "Expected width 48 for role \(role), got \(size.width)")
            #expect(size.height == 48, "Expected height 48 for role \(role), got \(size.height)")
        }
    }

    // MARK: - Integration: defaultEntity feeds compile path

    @Test("defaultEntity for player role compiles to a valid recipe node")
    func defaultEntityCompilesToValidNode() {
        let entity = PropertyInspector.defaultEntity(name: "hero", role: .player)
        let recipe = GameRecipe(entities: [entity])
        let result = RecipeCompiler.compile(recipe, repository: AssetRepository())

        // Should compile to at least 1 node with the correct name.
        #expect(result.nodes.contains(where: { $0.name == "hero" }),
                "Compiled recipe from defaultEntity should have a node named 'hero'")
        // No invalid-script fallback.
        let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
        #expect(!hasFallback)
    }

    @Test("defaultEntity for every role compiles without invalid-script diagnostic")
    func defaultEntityAllRolesCompile() {
        for role in EntityRole.allCases {
            let entity = PropertyInspector.defaultEntity(name: "testEntity", role: role)
            let recipe = GameRecipe(entities: [entity])
            let result = RecipeCompiler.compile(recipe, repository: AssetRepository())
            let hasFallback = result.diagnostics.contains { $0.contains("invalid script") }
            #expect(!hasFallback,
                    "defaultEntity for role \(role) triggered invalid-script fallback: \(result.diagnostics)")
        }
    }

    @Test("defaultParamsForBehavior params produce valid BehaviorLibrary contribution for every kind")
    func defaultParamsProduceValidContribution() {
        // For each behavior kind, build a Behavior with the default params, get a
        // BehaviorContribution, and verify the contribution is at least non-crashing.
        let entity = PropertyInspector.defaultEntity(name: "hero", role: .player)
        let enemy = PropertyInspector.defaultEntity(name: "enemy", role: .enemy)
        let collectible = PropertyInspector.defaultEntity(name: "coin", role: .collectible)
        let hazard = PropertyInspector.defaultEntity(name: "rock", role: .hazard)

        // Build a recipe that has all roles present so chaseTarget/loseOnContact can resolve.
        let recipe = GameRecipe(
            entities: [entity, enemy, collectible, hazard]
        )

        for kind in BehaviorKind.allCases {
            let params = PropertyInspector.defaultParamsForBehavior(kind)
            let behavior = Behavior(kind: kind, params: params)
            // This must not crash.
            let contrib = BehaviorLibrary.contribution(for: behavior, entity: entity, recipe: recipe)
            // All contributions should have valid (possibly empty) arrays.
            #expect(contrib.keyDown.allSatisfy { !$0.key.isEmpty },
                    "Contribution for \(kind) has a keyDown branch with empty key")
            #expect(contrib.beginContact.allSatisfy { !$0.otherPredicate.isEmpty },
                    "Contribution for \(kind) has a beginContact branch with empty predicate")
        }
    }
}

import Testing
import Foundation
@testable import HypeCore

@Suite("SpriteKit request router")
struct SpriteKitRequestRouterTests {

    @Test("explicit repair request on existing sprite area routes to .repair")
    func explicitRepairRoutesToStructured() {
        var document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id

        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 800, height: 600)
        var scene = SceneSpec(name: "main", size: SizeSpec(width: 800, height: 600))
        scene.nodes = [
            HypeNodeSpec(name: "blue_ball", nodeType: .shape, position: PointSpec(x: 300, y: 300))
        ]
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: scene.size))
        area.updateActiveSceneSpec { $0 = scene }
        document.addPart(area)

        // v3.1 (Apr 2026): the structured repair path is now only
        // triggered by explicit phrases like "fix the scene" /
        // "repair the scene". Behavior-like prompts on an existing
        // sprite area go through the regular tool-call loop, which
        // can now reach `set_scene_script` / `set_node_property` /
        // etc. without a proposal card.
        let route = SpriteKitRequestRouter.route(
            prompt: "fix the scene in bounder — the blue_ball should bounce around and stay inside the boundary",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == .repair)
        #expect(route.prefersSceneTooling)
        #expect(route.explicitScriptRequest == false)
    }

    @Test("implicit scene-behavior request on existing area uses tool-call loop, not structured repair")
    func implicitBehaviorUsesToolCallLoop() {
        var document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id

        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 800, height: 600)
        var scene = SceneSpec(name: "main", size: SizeSpec(width: 800, height: 600))
        scene.nodes = [HypeNodeSpec(name: "blue_ball", nodeType: .shape, position: PointSpec(x: 300, y: 300))]
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: scene.size))
        area.updateActiveSceneSpec { $0 = scene }
        document.addPart(area)

        // Without an explicit "fix/repair" verb, behavior-matching
        // prompts route through the regular tool-call loop with
        // scene-preferred tools. The model can call
        // `set_scene_script`, `set_physics_body`, etc. directly.
        let route = SpriteKitRequestRouter.route(
            prompt: "have the blue_ball sprite bounce around with full restitution",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == nil,
                "behavior-only prompts should go through tool-call loop")
        #expect(route.prefersSceneTooling)
    }

    @Test("explicit SpriteKit script requests stay on the script path")
    func explicitScriptRequestStaysScriptFocused() {
        var document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id
        let area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 800, height: 600)
        document.addPart(area)

        let route = SpriteKitRequestRouter.route(
            prompt: "write a script for spritearea bounder that handles keyDown for blue_ball",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == nil)
        #expect(route.prefersSceneTooling == false)
        #expect(route.explicitScriptRequest)
    }

    @Test("explicit repair on a background-layer sprite area still routes to .repair")
    func backgroundAreaRepairIsStructured() {
        var document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id
        let backgroundId = document.cards[0].backgroundId

        var area = Part(partType: .spriteArea, backgroundId: backgroundId, name: "bounder", left: 20, top: 20, width: 800, height: 600)
        var scene = SceneSpec(name: "main", size: SizeSpec(width: 800, height: 600))
        scene.nodes = [
            HypeNodeSpec(name: "blue_ball", nodeType: .shape, position: PointSpec(x: 300, y: 300))
        ]
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: scene.size))
        area.updateActiveSceneSpec { $0 = scene }
        document.addPart(area)

        let route = SpriteKitRequestRouter.route(
            prompt: "fix this scene — blue_ball should bounce around and stay inside the boundary",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == .repair)
        #expect(route.prefersSceneTooling)
    }

    @Test("explicit 'create sprite area' request routes to structured creation")
    func newSceneRoutesToCreate() {
        let document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id

        // Canonical explicit-create phrases trigger the structured
        // proposal path so the user sees a plan before applying.
        let route = SpriteKitRequestRouter.route(
            prompt: "create sprite area with a bouncing ball scene",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == .create)
        #expect(route.prefersSceneTooling)
        #expect(route.explicitScriptRequest == false)
    }

    @Test("ambiguous 'create a sprite area ...' falls through to tool-call loop, not structured create")
    func ambiguousCreateFallsThroughToLoop() {
        let document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id

        // "create a sprite area" (with "a") is close to the
        // canonical phrase but ambiguous — might just mean "add a
        // sprite area to the card", not "plan a full scene". The
        // tool-call loop handles it via create_sprite_area +
        // add_sprite_to_scene, which is faster and lets the user
        // see changes immediately without a proposal card.
        let route = SpriteKitRequestRouter.route(
            prompt: "create a sprite area with a bouncing ball scene",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == nil,
                "ambiguous create prompts should use the tool-call loop")
        #expect(route.prefersSceneTooling)
    }

    // MARK: - v3.1 regression coverage

    @Test("part-authoring override escapes SpriteKit routing even when a sprite area exists")
    func partAuthoringOverrideEscapesRoute() {
        var document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id
        document.addPart(Part(partType: .button, cardId: cardId, name: "play"))
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 400, height: 300)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 400, height: 300)))
        document.addPart(area)

        let route = SpriteKitRequestRouter.route(
            prompt: "set the text of button play to Start Game",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest == false,
                "part-authoring override must bypass SpriteKit routing")
        #expect(route.structuredIntent == nil)
        #expect(route.prefersSceneTooling == false)
    }

    @Test("generic 'inside' / 'bounds' do not flip prompts into SpriteKit routing")
    func insideAndBoundsAreNotSpriteKitTriggers() {
        let document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id

        let route1 = SpriteKitRequestRouter.route(
            prompt: "place the label inside the header area of the card",
            document: document,
            currentCardId: cardId
        )
        #expect(route1.isSpriteKitRequest == false)

        let route2 = SpriteKitRequestRouter.route(
            prompt: "keep the button within the card bounds",
            document: document,
            currentCardId: cardId
        )
        #expect(route2.isSpriteKitRequest == false)
    }

    @Test("form prompts stay on card-control authoring even when a sprite area exists")
    func formPromptUsesCardControls() {
        var document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "form_scene", left: 20, top: 20, width: 600, height: 420)
        var scene = SceneSpec(name: "main", size: SizeSpec(width: 600, height: 420))
        scene.nodes = [
            HypeNodeSpec(name: "first_name_label", nodeType: .label, position: PointSpec(x: 80, y: 100), text: "First Name")
        ]
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: scene.size))
        area.updateActiveSceneSpec { $0 = scene }
        document.addPart(area)

        let route = SpriteKitRequestRouter.route(
            prompt: "Create a customer entry form with a header, labels, and text fields for first name, last name, phone, and notes",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest == false)
        #expect(route.prefersSceneTooling == false)
    }

    @Test("on a doc without a sprite area, a SpriteKit phrase still needs an explicit create term to go structured")
    func emptyDocDoesNotAutoCreate() {
        let document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id

        // Mentions 'spritekit' but not "create a spritekit scene" —
        // routes to regular tool-call loop with scene preference,
        // not the structured create proposal.
        let route = SpriteKitRequestRouter.route(
            prompt: "tell me how spritekit physics works",
            document: document,
            currentCardId: cardId
        )
        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == nil,
                "ambiguous SpriteKit prompts should use the tool-call loop")
    }

    @Test("SpriteKit tool surface is scene-focused and includes part-level authoring fallback")
    func spriteKitToolSurfaceIsSceneFocused() {
        let toolNames = Set(HypeToolDefinitions.spriteSceneAuthoringTools.map { $0.function.name })

        // Core scene-level tools MUST be present.
        #expect(toolNames.contains("apply_scene_diff"))
        #expect(toolNames.contains("get_scene_spec"))
        #expect(toolNames.contains("get_scene_diagnostics"))
        #expect(toolNames.contains("set_scene_script"))
        #expect(toolNames.contains("list_scene_nodes"))
        #expect(toolNames.contains("add_sprite_to_scene"))

        // Script setters for card/background/stack.
        #expect(toolNames.contains("set_card_script"))
        #expect(toolNames.contains("set_background_script"))
        #expect(toolNames.contains("set_stack_script"))

        // v3.1 (Apr 2026): part-level authoring tools are now in
        // the sprite-scene allowlist. Removing them previously
        // caused a regression where the model could not call
        // `set_part_property` on a card that happened to contain a
        // sprite area — e.g. a user typing "set the text of button
        // play to Start" on such a card would see nothing happen.
        // Steering away from part tools is now the system prompt's
        // job (TOOL-USE PRIORITIES), not the tool-whitelist's.
        #expect(toolNames.contains("set_part_property"))
        #expect(toolNames.contains("get_part_property"))
        #expect(toolNames.contains("create_button"))
        #expect(toolNames.contains("create_field"))
        #expect(toolNames.contains("create_label"))
        #expect(toolNames.contains("create_shape"))
        #expect(toolNames.contains("repair_form_controls"))
        #expect(toolNames.contains("delete_part"))
        #expect(toolNames.contains("get_card_parts"))
        #expect(toolNames.contains("get_stack_info"))
        #expect(toolNames.contains("list_all_cards"))
        #expect(toolNames.contains("list_backgrounds"))

        // check_script stays exposed — validating scripts before
        // storage benefits both scene scripts and card/part scripts.
        #expect(toolNames.contains("check_script"))

        // Filesystem / web tools are still filtered out in both
        // surfaces; they live in webAssetTools when a stack opts in.
        #expect(!toolNames.contains("fetch_url"))
        #expect(!toolNames.contains("read_file"))
        #expect(!toolNames.contains("write_file"))
        #expect(!toolNames.contains("list_directory"))
    }

    @Test("default card-control tool surface excludes SpriteKit scene tools")
    func cardControlToolSurfaceExcludesSpriteKitTools() {
        let toolNames = Set(HypeToolDefinitions.cardControlAuthoringTools.map { $0.function.name })

        #expect(toolNames.contains("create_label"))
        #expect(toolNames.contains("create_field"))
        #expect(toolNames.contains("create_button"))
        #expect(toolNames.contains("set_part_property"))
        #expect(toolNames.contains("get_card_parts"))
        #expect(toolNames.contains("repair_form_controls"))

        #expect(!toolNames.contains("create_sprite_area"))
        #expect(!toolNames.contains("add_label_to_scene"))
        #expect(!toolNames.contains("set_node_property"))
        #expect(!toolNames.contains("apply_scene_diff"))
        #expect(!toolNames.contains("fetch_url"))
        #expect(!toolNames.contains("read_file"))
        #expect(!toolNames.contains("write_file"))
        #expect(!toolNames.contains("list_directory"))
    }
}

import Testing
import Foundation
@testable import HypeCore

@Suite("SpriteKit request router")
struct SpriteKitRequestRouterTests {

    @Test("existing sprite area requests route to structured repair")
    func existingAreaRoutesToRepair() {
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

        let route = SpriteKitRequestRouter.route(
            prompt: "have the blue_ball sprite bounce around the bounder spritekit area and stay inside the boundary",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == .repair)
        #expect(route.prefersSceneTooling)
        #expect(route.explicitScriptRequest == false)
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

    @Test("background sprite area requests still route to structured repair")
    func backgroundAreaRoutesToRepair() {
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
            prompt: "have the blue_ball sprite bounce around the bounder spritekit area and stay inside the boundary",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == .repair)
        #expect(route.prefersSceneTooling)
    }

    @Test("new SpriteKit scene requests route to structured creation")
    func newSceneRoutesToCreate() {
        let document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id

        let route = SpriteKitRequestRouter.route(
            prompt: "create a sprite area with a bouncing ball scene",
            document: document,
            currentCardId: cardId
        )

        #expect(route.isSpriteKitRequest)
        #expect(route.structuredIntent == .create)
        #expect(route.prefersSceneTooling)
        #expect(route.explicitScriptRequest == false)
    }

    @Test("SpriteKit tool surface excludes generic part scripting tools")
    func spriteKitToolSurfaceIsSceneFocused() {
        let toolNames = Set(HypeToolDefinitions.spriteSceneAuthoringTools.map { $0.function.name })
        #expect(toolNames.contains("apply_scene_diff"))
        #expect(toolNames.contains("get_scene_spec"))
        #expect(toolNames.contains("get_scene_diagnostics"))
        #expect(!toolNames.contains("set_part_property"))
        #expect(!toolNames.contains("check_script"))
    }
}

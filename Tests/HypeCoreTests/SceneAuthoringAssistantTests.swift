import Testing
import Foundation
@testable import HypeCore

@Suite("Scene authoring assistant")
struct SceneAuthoringAssistantTests {

    @Test("bounce requests are normalized to SpriteKit physics setup")
    func bounceRequestsUsePhysics() {
        let proposal = SceneCreateProposal(
            areaName: "bounder",
            sceneName: "main",
            createSpriteAreaIfMissing: false,
            summary: "Adds a ball to the sprite area.",
            checklist: [],
            scene: SceneBlueprint(
                size: SizeSpec(width: 800, height: 600),
                backgroundColor: "#101820",
                gravity: VectorSpec(dx: 0, dy: -9.8),
                scaleMode: .aspectFit,
                showsPhysics: false,
                showsFPS: false,
                showsNodeCount: false,
                sceneScript: """
                on idle
                  set the loc of sprite "blue_ball" to "100,100"
                end idle
                """,
                nodes: [
                    SceneBlueprintNode(
                        name: "blue_ball",
                        nodeType: .shape,
                        position: PointSpec(x: 400, y: 300),
                        size: SizeSpec(width: 40, height: 40),
                        shapeType: .circle,
                        fillColor: "#4AA8FF",
                        strokeColor: "#1D5FBD",
                        lineWidth: 2,
                        physicsEnabled: false
                    )
                ]
            )
        )

        let normalized = SceneAuthoringAssistant.normalizeCreateProposal(
            proposal,
            for: "Add a sprite to the sprite area, give it physics, and make it bounce around the sprite area."
        )

        #expect(normalized.scene.gravity.dx == 0)
        #expect(normalized.scene.gravity.dy == 0)
        #expect(normalized.scene.sceneScript.isEmpty)

        let ball = normalized.scene.nodes.first(where: { $0.name == "blue_ball" })
        #expect(ball != nil)
        #expect(ball?.physicsEnabled == true)
        #expect(ball?.physicsBodyType == .circle)
        #expect(ball?.dynamic == true)
        #expect(ball?.affectedByGravity == false)
        #expect((ball?.restitution ?? 0) >= 0.95)
        #expect(ball?.velocity?.dx != nil)
        #expect(ball?.velocity?.dy != nil)

        let wallNames = Set(normalized.scene.nodes.map(\.name))
        #expect(wallNames.contains("_leftWall"))
        #expect(wallNames.contains("_rightWall"))
        #expect(wallNames.contains("_topWall"))
        #expect(wallNames.contains("_bottomWall"))
    }

    @Test("non-bounce requests are not rewritten into wall setups")
    func nonBounceRequestsStayFocused() {
        let proposal = SceneCreateProposal(
            areaName: "menuArea",
            sceneName: "title",
            createSpriteAreaIfMissing: false,
            summary: "Adds a title label.",
            checklist: [],
            scene: SceneBlueprint(
                size: SizeSpec(width: 640, height: 480),
                backgroundColor: "#000000",
                gravity: VectorSpec(dx: 0, dy: 0),
                scaleMode: .aspectFit,
                showsPhysics: false,
                showsFPS: false,
                showsNodeCount: false,
                sceneScript: "",
                nodes: [
                    SceneBlueprintNode(
                        name: "title",
                        nodeType: .label,
                        position: PointSpec(x: 320, y: 240),
                        text: "Start"
                    )
                ]
            )
        )

        let normalized = SceneAuthoringAssistant.normalizeCreateProposal(
            proposal,
            for: "Create a title scene with a centered label."
        )

        #expect(normalized.scene.nodes.count == 1)
        #expect(normalized.scene.nodes.first?.name == "title")
        #expect(!normalized.scene.nodes.contains(where: { $0.name == "_leftWall" }))
    }

    @Test("bounce repairs are normalized to scene physics updates")
    func bounceRepairRequestsUsePhysics() {
        let ballId = UUID()
        let scene = SceneSpec(
            name: "main",
            size: SizeSpec(width: 800, height: 600),
            gravity: VectorSpec(dx: 0, dy: -9.8),
            nodes: [
                HypeNodeSpec(
                    id: ballId,
                    name: "blue_ball",
                    nodeType: .shape,
                    position: PointSpec(x: 400, y: 300),
                    size: SizeSpec(width: 40, height: 40),
                    shapeSpec: ShapeNodeSpec(shapeType: .circle, fillColor: "#4AA8FF")
                )
            ],
            script: """
            on idle
              set the loc of sprite "blue_ball" to "100,100"
            end idle
            """
        )

        let proposal = SceneRepairProposal(
            areaName: "bounder",
            summary: "Updates blue_ball movement.",
            issues: [],
            diff: SceneDiff(
                sceneUpdates: SceneUpdate(
                    script: """
                    on idle
                      add 1 to x
                    end idle
                    """
                )
            )
        )

        let normalized = SceneAuthoringAssistant.normalizeRepairProposal(
            proposal,
            for: "have the blue_ball sprite bounce around the bounder spritekit area and not exceed the boundary",
            currentScene: scene
        )

        #expect(normalized.diff.sceneUpdates?.gravity?.dx == 0)
        #expect(normalized.diff.sceneUpdates?.gravity?.dy == 0)
        #expect(normalized.diff.sceneUpdates?.script == "")

        let update = normalized.diff.updateNodes?.first(where: { $0.id == ballId })
        #expect(update != nil)
        #expect(update?.properties["physics.enabled"] == "true")
        #expect(update?.properties["physics.bodyType"] == "circle")
        #expect(update?.properties["physics.velocityX"] == "220")
        #expect(update?.properties["physics.velocityY"] == "170")
        #expect(update?.properties["script"] == "")

        let wallNames = Set((normalized.diff.addNodes ?? []).map { $0.name })
        #expect(wallNames.contains("_leftWall"))
        #expect(wallNames.contains("_rightWall"))
        #expect(wallNames.contains("_topWall"))
        #expect(wallNames.contains("_bottomWall"))
    }
}

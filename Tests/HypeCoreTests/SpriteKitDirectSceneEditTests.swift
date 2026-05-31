import Foundation
import Testing
@testable import HypeCore

@Suite("SpriteKit direct scene edits")
struct SpriteKitDirectSceneEditTests {
    @Test("boundary prompt adds visible static perimeter walls to the named sprite area")
    func boundaryPromptAddsWalls() {
        var document = documentWithSpriteArea()
        let cardId = document.cards[0].id

        let result = SpriteKitDirectSceneEdit.addBoundaryWallsIfRequested(
            prompt: "add shape nodes around the perimiter of the bounder object on the current card that act as barrioers so sprites bounce off them",
            document: &document,
            currentCardId: cardId
        )

        #expect(result?.areaName == "bounder")
        #expect(result?.sceneName == "main")

        let scene = activeScene(named: "bounder", in: document)
        let walls = wallNodes(in: scene)
        #expect(walls.count == 4)
        #expect(Set(walls.map(\.name)) == Set(["_leftWall", "_rightWall", "_topWall", "_bottomWall"]))

        for wall in walls {
            #expect(wall.nodeType == .shape)
            #expect(wall.shapeSpec?.shapeType == .rect)
            #expect(wall.alpha == 1)
            #expect(wall.isHidden == false)
            #expect(wall.script.isEmpty)
            #expect(wall.physicsBody?.bodyType == .rect)
            #expect(wall.physicsBody?.isDynamic == false)
            #expect(wall.physicsBody?.affectedByGravity == false)
            #expect(wall.physicsBody?.allowsRotation == false)
            #expect(wall.physicsBody?.friction == 0)
            #expect(wall.physicsBody?.restitution == 1)
        }

        #expect(scene.node(named: "blue_ball") != nil)
        #expect(scene.script.isEmpty)
    }

    @Test("repeated boundary prompts update existing wall nodes instead of duplicating them")
    func repeatedBoundaryPromptIsIdempotent() {
        var document = documentWithSpriteArea()
        let cardId = document.cards[0].id

        _ = SpriteKitDirectSceneEdit.addBoundaryWallsIfRequested(
            prompt: "add border wall lines to bounder so sprites bounce",
            document: &document,
            currentCardId: cardId
        )
        let firstIds = Set(wallNodes(in: activeScene(named: "bounder", in: document)).map(\.id))

        _ = SpriteKitDirectSceneEdit.addBoundaryWallsIfRequested(
            prompt: "create perimeter barriers around the bounder sprite object",
            document: &document,
            currentCardId: cardId
        )
        let secondWalls = wallNodes(in: activeScene(named: "bounder", in: document))

        #expect(secondWalls.count == 4)
        #expect(Set(secondWalls.map(\.id)) == firstIds)
    }

    @Test("complete game prompt mentioning walls does not shortcut to boundary-only edit")
    func completeGamePromptDoesNotShortcutToBoundaryWalls() {
        var document = documentWithSpriteArea(name: "missile")
        let cardId = document.cards[0].id

        let result = SpriteKitDirectSceneEdit.addBoundaryWallsIfRequested(
            prompt: #"create a missile command style game in the current card within the existing sprite area called "missile". Implement all game logic and use the image generation API to create all needed assets for sprites, walls, etc."#,
            document: &document,
            currentCardId: cardId
        )

        #expect(result == nil)
        #expect(wallNodes(in: activeScene(named: "missile", in: document)).isEmpty)
    }

    @Test("generic card border prompts do not mutate SpriteKit scenes")
    func genericCardBorderPromptDoesNotMutate() {
        var document = documentWithSpriteArea()
        let cardId = document.cards[0].id

        let result = SpriteKitDirectSceneEdit.addBoundaryWallsIfRequested(
            prompt: "add a border around this card",
            document: &document,
            currentCardId: cardId
        )

        #expect(result == nil)
        #expect(wallNodes(in: activeScene(named: "bounder", in: document)).isEmpty)
    }

    @Test("ambiguous multi-area boundary prompts are left for model/tool routing")
    func ambiguousMultiAreaPromptDoesNotGuess() {
        var document = documentWithSpriteArea()
        let cardId = document.cards[0].id
        var second = makeSpriteArea(name: "arena", cardId: cardId, size: SizeSpec(width: 300, height: 200))
        second.updateActiveSceneSpec { scene in
            scene.nodes = [HypeNodeSpec(name: "red_ball", nodeType: .shape)]
        }
        document.addPart(second)

        let result = SpriteKitDirectSceneEdit.addBoundaryWallsIfRequested(
            prompt: "add perimeter barrier lines to the sprite scene",
            document: &document,
            currentCardId: cardId
        )

        #expect(result == nil)
        #expect(wallNodes(in: activeScene(named: "bounder", in: document)).isEmpty)
        #expect(wallNodes(in: activeScene(named: "arena", in: document)).isEmpty)
    }

    private func documentWithSpriteArea(name: String = "bounder") -> HypeDocument {
        var document = HypeDocument.newDocument(name: "Test")
        let cardId = document.cards[0].id
        document.addPart(makeSpriteArea(name: name, cardId: cardId, size: SizeSpec(width: 820, height: 612)))
        return document
    }

    private func makeSpriteArea(name: String, cardId: UUID, size: SizeSpec) -> Part {
        var area = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: name,
            left: 24,
            top: 20,
            width: size.width,
            height: size.height
        )
        var scene = SceneSpec(name: "main", size: size, gravity: VectorSpec(dx: 0, dy: 0))
        scene.nodes = [
            HypeNodeSpec(
                name: "blue_ball",
                nodeType: .shape,
                position: PointSpec(x: 120, y: 100),
                size: SizeSpec(width: 40, height: 40),
                shapeSpec: ShapeNodeSpec(shapeType: .circle),
                physicsBody: PhysicsBodySpec(
                    bodyType: .circle,
                    isDynamic: true,
                    restitution: 1,
                    friction: 0,
                    affectedByGravity: false
                )
            )
        ]
        area.setSpriteAreaSpec(SpriteAreaSpec(scene: scene, fallbackSize: size))
        return area
    }

    private func activeScene(named areaName: String, in document: HypeDocument) -> SceneSpec {
        let area = document.parts.first { $0.name == areaName && $0.partType == .spriteArea }
        return area?.activeSceneSpec ?? SceneSpec()
    }

    private func wallNodes(in scene: SceneSpec) -> [HypeNodeSpec] {
        scene.allNodes.filter { $0.name.hasSuffix("Wall") }
    }
}

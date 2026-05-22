import AppKit
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("Card canvas accessibility")
struct CardCanvasAccessibilityTests {
    @Test("canvas exposes Pac-Man sprite scene and node hierarchy")
    func canvasExposesPacmanSpriteSceneAndNodes() throws {
        var document = HypeDocument.newDocument(name: "Accessibility Pac-Man")
        let cardId = document.sortedCards[0].id

        var scoreField = Part(
            partType: .field,
            cardId: cardId,
            name: "scoreField",
            left: 16,
            top: 16,
            width: 180,
            height: 32
        )
        scoreField.textContent = "Score: 0"
        document.addPart(scoreField)

        let spriteArea = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "pacmanArea",
            left: 16,
            top: 64,
            width: SpriteGameTemplateBuilder.defaultPacmanSceneSize.width,
            height: SpriteGameTemplateBuilder.defaultPacmanSceneSize.height
        )
        document.addPart(spriteArea)

        let areaIndex = try #require(document.parts.firstIndex(where: { $0.id == spriteArea.id }))
        _ = try SpriteGameTemplateBuilder.applyPacmanTemplate(
            to: &document,
            partIndex: areaIndex,
            spriteAreaName: "pacmanArea"
        )
        let resolvedArea = try #require(document.parts.first(where: { $0.id == spriteArea.id }))
        let sceneId = try #require(resolvedArea.spriteAreaSpecModel?.activeSceneID)
        let scene = try #require(resolvedArea.activeSceneSpec)
        let pacman = try #require(scene.node(named: "pacmanPlayer"))
        let maze = try #require(scene.node(named: "maze"))

        let view = CardCanvasNSView(frame: NSRect(x: 0, y: 0, width: 900, height: 680))
        view.document = document
        view.currentCardId = cardId
        view.currentTool = .select
        view.selectedPartIds = [spriteArea.id]

        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityIdentifier() == HypeAccessibilityID.canvas(cardId: cardId))
        #expect((view.accessibilityValue() as? String)?.contains("selected=1") == true)

        let canvasChildren = try #require(view.accessibilityChildren())
        let scoreElement = try #require(canvasChildren.compactMap { $0 as? CardCanvasPartAccessibilityElement }.first { $0.partId == scoreField.id })
        #expect(scoreElement.accessibilityIdentifier() == HypeAccessibilityID.part(scoreField.id))
        #expect(scoreElement.accessibilityRole() == .textField)
        #expect((scoreElement.accessibilityValue() as? String)?.contains("text=Score: 0") == true)

        let areaElement = try #require(canvasChildren.compactMap { $0 as? CardCanvasPartAccessibilityElement }.first { $0.partId == spriteArea.id })
        #expect(areaElement.accessibilityIdentifier() == HypeAccessibilityID.part(spriteArea.id))
        #expect(areaElement.accessibilityLabel()?.contains("pacmanArea") == true)
        #expect((areaElement.accessibilityValue() as? String)?.contains("nodeCount=") == true)
        #expect(areaElement.accessibilityCustomActions()?.map(\.name).contains("Open Script") == true)

        let selectedChildren = try #require(view.accessibilitySelectedChildren())
        #expect(selectedChildren.compactMap { $0 as? CardCanvasPartAccessibilityElement }.map(\.partId) == [spriteArea.id])

        let sceneChildren = try #require(areaElement.accessibilityChildren())
        let sceneElement = try #require(sceneChildren.first as? CardCanvasSpriteSceneAccessibilityElement)
        #expect(sceneElement.accessibilityIdentifier() == HypeAccessibilityID.spriteScene(partId: spriteArea.id, sceneId: sceneId))
        #expect(sceneElement.accessibilityLabel()?.contains(scene.name) == true)
        #expect((sceneElement.accessibilityValue() as? String)?.contains("nodes=") == true)

        let nodeChildren = try #require(sceneElement.accessibilityChildren())
        let nodeElements = nodeChildren.compactMap { $0 as? CardCanvasSpriteNodeAccessibilityElement }
        #expect(nodeElements.contains { $0.nodeId == maze.id })
        #expect(nodeElements.contains { $0.nodeId == pacman.id })

        let pacmanElement = try #require(nodeElements.first { $0.nodeId == pacman.id })
        #expect(pacmanElement.accessibilityIdentifier() == HypeAccessibilityID.spriteNode(partId: spriteArea.id, sceneId: sceneId, nodeId: pacman.id))
        #expect(pacmanElement.accessibilityRole() == .image)
        #expect(pacmanElement.accessibilityLabel()?.contains("pacmanPlayer") == true)
        #expect((pacmanElement.accessibilityValue() as? String)?.contains("type=sprite") == true)
    }
}

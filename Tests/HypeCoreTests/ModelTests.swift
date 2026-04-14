import Testing
import Foundation
@testable import HypeCore

@Suite("HypeDocument Model Tests")
struct ModelTests {

    @Test func newDocumentHasDefaultCardAndBackground() {
        let doc = HypeDocument.newDocument(name: "Test")
        #expect(doc.stack.name == "Test")
        #expect(doc.backgrounds.count == 1)
        #expect(doc.cards.count == 1)
        #expect(doc.parts.isEmpty)
        #expect(doc.cards[0].backgroundId == doc.backgrounds[0].id)
    }

    @Test func sortedCardsReturnsByKey() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addCard()
        let _ = doc.addCard()
        #expect(doc.sortedCards.count == 3)
        for i in 1..<doc.sortedCards.count {
            #expect(doc.sortedCards[i-1].sortKey <= doc.sortedCards[i].sortKey)
        }
    }

    @Test func addPartAndRetrieve() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var part = Part(partType: .button, cardId: cardId)
        part.name = "MyButton"
        doc.addPart(part)

        let found = doc.partsForCard(cardId)
        #expect(found.count == 1)
        #expect(found[0].name == "MyButton")
    }

    @Test func removePartById() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let part = Part(partType: .field, cardId: cardId)
        doc.addPart(part)
        #expect(doc.parts.count == 1)
        doc.removePart(id: part.id)
        #expect(doc.parts.isEmpty)
    }

    @Test func updatePart() {
        var doc = HypeDocument.newDocument()
        let part = Part(partType: .button, cardId: doc.cards[0].id, name: "Original")
        doc.addPart(part)
        doc.updatePart(id: part.id) { $0.name = "Updated" }
        #expect(doc.parts[0].name == "Updated")
    }

    @Test func addBackgroundWithUniqueName() {
        var doc = HypeDocument.newDocument()
        let bg2 = doc.addBackground(name: "Customer")
        #expect(bg2.name == "Customer")
        #expect(doc.backgrounds.count == 2)
        // Duplicate name gets suffixed
        let bg3 = doc.addBackground(name: "Customer")
        #expect(bg3.name == "Customer 2")
        #expect(doc.backgrounds.count == 3)
    }

    @Test func addCardWithBackground() {
        var doc = HypeDocument.newDocument()
        let bg2 = doc.addBackground(name: "Customer")
        let card = doc.addCard(backgroundName: "Customer")
        #expect(card.backgroundId == bg2.id)
    }

    @Test func backgroundByName() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addBackground(name: "Products")
        let found = doc.backgroundByName("products")  // case insensitive
        #expect(found != nil)
        #expect(found?.name == "Products")
    }

    @Test func cardsForBackground() {
        var doc = HypeDocument.newDocument()
        let bg1 = doc.backgrounds[0]
        let bg2 = doc.addBackground(name: "Other")
        let _ = doc.addCard(backgroundId: bg2.id)
        let bg1Cards = doc.cardsForBackground(bg1.id)
        let bg2Cards = doc.cardsForBackground(bg2.id)
        #expect(bg1Cards.count == 1)
        #expect(bg2Cards.count == 1)
    }

    @Test func defaultBackgroundHasName() {
        let doc = HypeDocument.newDocument()
        #expect(doc.backgrounds[0].name == "Background 1")
    }

    @Test func backgroundForCard() {
        let doc = HypeDocument.newDocument()
        let card = doc.cards[0]
        let bg = doc.backgroundForCard(card)
        #expect(bg != nil)
        #expect(bg?.id == card.backgroundId)
    }

    @Test func partsForBackground() {
        var doc = HypeDocument.newDocument()
        let bgId = doc.backgrounds[0].id
        let bgPart = Part(partType: .button, backgroundId: bgId)
        doc.addPart(bgPart)

        let cardPart = Part(partType: .field, cardId: doc.cards[0].id)
        doc.addPart(cardPart)

        let bgParts = doc.partsForBackground(bgId)
        #expect(bgParts.count == 1)
        #expect(bgParts[0].id == bgPart.id)
    }

    @Test func effectivePartsForCardIncludesBackgroundParts() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let bgId = doc.cards[0].backgroundId
        let cardPart = Part(partType: .button, cardId: cardId, name: "Card Button")
        let bgPart = Part(partType: .field, backgroundId: bgId, name: "Background Field")
        doc.addPart(cardPart)
        doc.addPart(bgPart)

        let effective = doc.effectivePartsForCard(cardId)
        #expect(effective.count == 2)
        #expect(effective.contains(where: { $0.name == "Card Button" }))
        #expect(effective.contains(where: { $0.name == "Background Field" }))
    }

    @Test func partDefaultValues() {
        let part = Part(partType: .button)
        #expect(part.visible == true)
        #expect(part.enabled == true)
        #expect(part.hilite == false)
        #expect(part.textFont == "Apple Braille")
        #expect(part.textSize == 14)
        #expect(part.buttonStyle == .roundRect)
        #expect(part.fillColor == "#FFFFFF")
        #expect(part.strokeColor == "#000000")
    }
}

@Suite("CardNavigator Tests")
struct NavigatorTests {

    @Test func navigateFirst() {
        let doc = HypeDocument.newDocument()
        let result = CardNavigator.navigate(direction: .first, currentCardId: doc.cards[0].id, document: doc)
        #expect(result == doc.cards[0].id)
    }

    @Test func navigateLast() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addCard()
        let result = CardNavigator.navigate(direction: .last, currentCardId: doc.cards[0].id, document: doc)
        #expect(result == doc.sortedCards.last?.id)
    }

    @Test func navigateNextAtEnd() {
        let doc = HypeDocument.newDocument()
        let result = CardNavigator.navigate(direction: .next, currentCardId: doc.cards[0].id, document: doc)
        #expect(result == nil)
    }

    @Test func navigatePreviousAtStart() {
        let doc = HypeDocument.newDocument()
        let result = CardNavigator.navigate(direction: .previous, currentCardId: doc.cards[0].id, document: doc)
        #expect(result == nil)
    }

    @Test func cardPosition() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addCard()
        let _ = doc.addCard()
        let (index, count) = CardNavigator.cardPosition(currentCardId: doc.sortedCards[1].id, document: doc)
        #expect(index == 1)
        #expect(count == 3)
    }
}

@Suite("Sprite Area Spec Tests")
struct SpriteAreaSpecTests {

    @Test func legacySceneSpecMigratesToNamedSceneRegistry() {
        let cardId = UUID()
        var area = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "Game Area",
            left: 0,
            top: 0,
            width: 480,
            height: 320
        )
        var legacyScene = SceneSpec(
            name: "Legacy Scene",
            size: SizeSpec(width: 480, height: 320),
            backgroundColor: "#112233",
            gravity: VectorSpec(dx: 0, dy: -4.5),
            script: """
            on openScene
              pass openScene
            end openScene
            """
        )
        legacyScene.nodes = [
            HypeNodeSpec(
                name: "ball",
                nodeType: .sprite,
                position: PointSpec(x: 48, y: 96)
            )
        ]
        area.sceneSpec = legacyScene.toJSON()

        guard let migrated = area.spriteAreaSpecModel else {
            Issue.record("Legacy SceneSpec should migrate into SpriteAreaSpec")
            return
        }

        #expect(migrated.scenes.count == 1)
        #expect(migrated.activeScene?.name == "Legacy Scene")
        #expect(migrated.activeScene?.backgroundColor == "#112233")
        #expect(migrated.activeScene?.gravity.dy == -4.5)
        #expect(migrated.activeScene?.nodes.first?.name == "ball")
        #expect(migrated.activeSceneEntry?.id == migrated.activeSceneID)

        var rewritten = area
        rewritten.setSpriteAreaSpec(migrated)

        #expect(SpriteAreaSpec.fromJSON(rewritten.sceneSpec) != nil)
        #expect(SceneSpec.fromLegacyJSON(rewritten.sceneSpec) == nil)
    }
}

@Suite("SceneDiff Tests")
struct SceneDiffTests {

    @Test func physicsAndShapePropertiesCanBeUpdatedRecursively() {
        let childId = UUID()
        var scene = SceneSpec(
            name: "main",
            size: SizeSpec(width: 800, height: 600),
            nodes: [
                HypeNodeSpec(
                    name: "group",
                    nodeType: .group,
                    children: [
                        HypeNodeSpec(
                            id: childId,
                            name: "blue_ball",
                            nodeType: .shape,
                            position: PointSpec(x: 100, y: 100),
                            size: SizeSpec(width: 40, height: 40),
                            shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: "#FFFFFF"),
                            script: "on idle\n  put 1 into x\nend idle"
                        )
                    ]
                )
            ]
        )

        let diff = SceneDiff(
            updateNodes: [
                NodeUpdate(
                    id: childId,
                    properties: [
                        "script": "",
                        "shape.shapeType": "circle",
                        "shape.fillColor": "#4AA8FF",
                        "physics.enabled": "true",
                        "physics.bodyType": "circle",
                        "physics.isDynamic": "true",
                        "physics.restitution": "0.98",
                        "physics.velocityX": "220",
                        "physics.velocityY": "170"
                    ]
                )
            ]
        )

        diff.apply(to: &scene)

        let ball = scene.node(id: childId)
        #expect(ball?.script == "")
        #expect(ball?.shapeSpec?.shapeType == .circle)
        #expect(ball?.shapeSpec?.fillColor == "#4AA8FF")
        #expect(ball?.physicsBody?.bodyType == .circle)
        #expect(ball?.physicsBody?.isDynamic == true)
        #expect(ball?.physicsBody?.restitution == 0.98)
        #expect(ball?.physicsBody?.velocityX == 220)
        #expect(ball?.physicsBody?.velocityY == 170)
    }
}

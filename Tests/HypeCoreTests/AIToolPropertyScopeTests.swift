import Testing
import Foundation
@testable import HypeCore

@Suite("AI tool properties and scope")
struct AIToolPropertyScopeTests {

    private func docWithTwoCards() -> (HypeDocument, UUID, UUID) {
        var doc = HypeDocument.newDocument(name: "Scope")
        let first = doc.cards[0].id
        doc.cards[0].name = "intro"
        let second = doc.addCard(afterIndex: 0, backgroundName: nil).id
        if let idx = doc.cards.firstIndex(where: { $0.id == second }) {
            doc.cards[idx].name = "other"
        }
        return (doc, first, second)
    }

    @Test("get_stack_property reads width")
    func getStackPropertyWidth() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "width"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result == "800")
    }

    @Test("set_stack_property toggles web asset permission")
    func setStackPropertyWebAssetsAllowed() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "webAssetsAllowed", "value": "true"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result.contains("webAssetsAllowed"))
        #expect(doc.stack.webAssetsAllowed)
    }

    @Test("get_card_property returns the current card background name")
    func getCardPropertyBackgroundName() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_card_property",
            arguments: ["property": "backgroundName"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result == "Background 1")
    }

    @Test("set_card_property marks the current card")
    func setCardPropertyMarked() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_card_property",
            arguments: ["property": "marked", "value": "true"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result.contains("marked"))
        #expect(doc.cards[0].marked)
    }

    @Test("get_background_property uses the current background by default")
    func getBackgroundPropertyCardCount() async {
        var doc = HypeDocument.newDocument(name: "Props")
        _ = doc.addCard(afterIndex: 0, backgroundName: nil)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_background_property",
            arguments: ["property": "cardCount"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result == "2")
    }

    @Test("get_background_parts returns only current background parts")
    func getBackgroundPartsCurrentBackgroundOnly() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let cardId = doc.cards[0].id
        let backgroundId = doc.cards[0].backgroundId
        doc.addPart(Part(partType: .field, backgroundId: backgroundId, name: "shared_status", left: 10, top: 10, width: 100, height: 30))
        doc.addPart(Part(partType: .button, cardId: cardId, name: "card_only", left: 20, top: 20, width: 120, height: 40))

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_background_parts",
            arguments: [:],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.contains("shared_status"))
        #expect(!result.contains("card_only"))
    }

    @Test("create_field applies visual and text properties in one tool call")
    func createFieldAppliesStylingArguments() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()

        let result = await executor.execute(
            toolName: "create_field",
            arguments: [
                "name": "first_name",
                "left": "40",
                "top": "80",
                "width": "220",
                "height": "32",
                "text": "",
                "style": "rectangle",
                "fill_color": "#FFFFFF",
                "stroke_color": "#000000",
                "stroke_width": "2",
                "text_size": "16",
                "text_align": "left",
                "lock_text": "false",
                "show_name": "false",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let field = doc.parts.first(where: { $0.name == "first_name" })
        #expect(result.contains("Created field"))
        #expect(field?.fieldStyle == .rectangle)
        #expect(field?.fillColor == "#FFFFFF")
        #expect(field?.strokeColor == "#000000")
        #expect(field?.strokeWidth == 2)
        #expect(field?.textSize == 16)
        #expect(field?.textAlign == .left)
        #expect(field?.lockText == false)
        #expect(field?.showName == false)
    }

    @Test("create_label creates a locked transparent field label")
    func createLabelCreatesLockedTransparentField() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()

        let result = await executor.execute(
            toolName: "create_label",
            arguments: [
                "name": "customer_header",
                "text": "Customer Entry",
                "left": "60",
                "top": "30",
                "width": "300",
                "height": "40",
                "text_size": "24",
                "text_align": "center",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let label = doc.parts.first(where: { $0.name == "customer_header" })
        #expect(result.contains("Created label"))
        #expect(label?.partType == .field)
        #expect(label?.textContent == "Customer Entry")
        #expect(label?.fieldStyle == .transparent)
        #expect(label?.lockText == true)
        #expect(label?.showName == false)
        #expect(label?.strokeWidth == 0)
        #expect(label?.textSize == 24)
        #expect(label?.textAlign == .center)
    }

    @Test("set_background_property renames the current background")
    func setBackgroundPropertyName() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_background_property",
            arguments: ["property": "name", "value": "shared"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result.contains("shared"))
        #expect(doc.backgrounds[0].name == "shared")
    }

    @Test("set_part_property prefers the current card over same-named parts elsewhere")
    func setPartPropertyRespectsCurrentCardScope() async {
        var (doc, firstCardId, secondCardId) = docWithTwoCards()
        var first = Part(partType: .button, cardId: firstCardId, name: "status", left: 10, top: 10, width: 100, height: 30)
        first.textContent = "First"
        var second = Part(partType: .button, cardId: secondCardId, name: "status", left: 10, top: 10, width: 100, height: 30)
        second.textContent = "Second"
        doc.addPart(first)
        doc.addPart(second)

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "status", "property": "text", "value": "Updated"],
            document: &doc,
            currentCardId: firstCardId
        )

        let firstText = doc.parts.first(where: { $0.cardId == firstCardId && $0.name == "status" })?.textContent
        let secondText = doc.parts.first(where: { $0.cardId == secondCardId && $0.name == "status" })?.textContent
        #expect(firstText == "Updated")
        #expect(secondText == "Second")
    }

    @Test("get_part_property prefers the current card over same-named parts elsewhere")
    func getPartPropertyRespectsCurrentCardScope() async {
        var (doc, firstCardId, secondCardId) = docWithTwoCards()
        var first = Part(partType: .field, cardId: firstCardId, name: "score", left: 10, top: 10, width: 100, height: 30)
        first.textContent = "11"
        var second = Part(partType: .field, cardId: secondCardId, name: "score", left: 10, top: 10, width: 100, height: 30)
        second.textContent = "99"
        doc.addPart(first)
        doc.addPart(second)

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "score", "property": "text"],
            document: &doc,
            currentCardId: secondCardId
        )

        #expect(result == "99")
    }

    @Test("part script property routes sprite areas to the active scene script")
    func partScriptPropertyRoutesSpriteAreasToSceneScript() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 300, height: 200)
        area.script = "on sceneDidLoad\n  -- stale part fallback\nend sceneDidLoad"
        area.setSpriteAreaSpec(
            SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 300, height: 200))
        )
        doc.addPart(area)

        let script = "on frameUpdate\n  set the velocityX of sprite \"blue_ball\" to 150\nend frameUpdate"
        let executor = HypeToolExecutor()
        let setResult = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "bounder", "property": "script", "value": script],
            document: &doc,
            currentCardId: cardId
        )
        let getResult = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "bounder", "property": "script"],
            document: &doc,
            currentCardId: cardId
        )

        let updatedArea = doc.parts.first(where: { $0.name == "bounder" })
        #expect(setResult.contains("routed to the scene"))
        #expect(updatedArea?.script == "on sceneDidLoad\n  -- stale part fallback\nend sceneDidLoad")
        #expect(updatedArea?.activeSceneSpec?.script == script)
        #expect(getResult == script)
    }

    @Test("scene tools prefer the current card's sprite area when names collide")
    func spriteAreaLookupRespectsCurrentCardScope() async {
        var (doc, firstCardId, secondCardId) = docWithTwoCards()

        func makeArea(cardId: UUID, nodeName: String) -> Part {
            var area = Part(partType: .spriteArea, cardId: cardId, name: "arena", left: 20, top: 20, width: 300, height: 200)
            area.setSpriteAreaSpec(
                SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 300, height: 200))
            )
            area.updateActiveSceneSpec { spec in
                var node = HypeNodeSpec(name: nodeName, nodeType: .sprite)
                node.alpha = 1
                node.position = PointSpec(x: 100, y: 100)
                spec.nodes.append(node)
            }
            return area
        }

        doc.addPart(makeArea(cardId: firstCardId, nodeName: "player"))
        doc.addPart(makeArea(cardId: secondCardId, nodeName: "player"))

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_node_property",
            arguments: [
                "sprite_area_name": "arena",
                "node_name": "player",
                "property": "alpha",
                "value": "0.25"
            ],
            document: &doc,
            currentCardId: secondCardId
        )

        let firstArea = doc.parts.first(where: { $0.cardId == firstCardId && $0.name == "arena" })
        let secondArea = doc.parts.first(where: { $0.cardId == secondCardId && $0.name == "arena" })
        #expect(firstArea?.activeSceneSpec?.node(named: "player")?.alpha == 1)
        #expect(abs((secondArea?.activeSceneSpec?.node(named: "player")?.alpha ?? 1) - 0.25) < 0.0001)
    }

    @Test("spriteSceneAuthoringTools includes scene and stack/card/background property tools")
    func spriteCatalogIncludesPropertyTools() {
        let names = Set(HypeToolDefinitions.spriteSceneAuthoringTools.map { $0.function.name })
        #expect(names.contains("set_scene_property"))
        #expect(names.contains("get_stack_property"))
        #expect(names.contains("get_card_property"))
        #expect(names.contains("get_background_property"))
        #expect(names.contains("get_background_parts"))
        #expect(names.contains("set_stack_property"))
        #expect(names.contains("set_card_property"))
        #expect(names.contains("set_background_property"))
        #expect(names.contains("list_scenes"))
        #expect(names.contains("set_active_scene"))
    }

    @Test("repair_form_controls converts SpriteKit label nodes into card field labels")
    func repairFormControlsConvertsLabelNodes() async {
        var doc = HypeDocument.newDocument(name: "Props")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bad_form_labels", left: 100, top: 60, width: 400, height: 300)
        var scene = SceneSpec(name: "main", size: SizeSpec(width: 400, height: 300))
        scene.nodes = [
            HypeNodeSpec(name: "header", nodeType: .label, position: PointSpec(x: 200, y: 35), text: "Customer Entry", fontSize: 24),
            HypeNodeSpec(name: "first_name", nodeType: .label, position: PointSpec(x: 80, y: 100), text: "First Name", fontSize: 14),
        ]
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: scene.size))
        area.updateActiveSceneSpec { $0 = scene }
        doc.addPart(area)

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "repair_form_controls",
            arguments: ["sprite_area_name": "bad_form_labels"],
            document: &doc,
            currentCardId: cardId
        )

        let labels = doc.parts.filter { $0.partType == .field && $0.lockText }
        #expect(result.contains("Converted 2"))
        #expect(doc.parts.contains(where: { $0.name == "bad_form_labels" }) == false)
        #expect(labels.count == 2)
        #expect(labels.contains(where: { $0.textContent == "Customer Entry" }))
        #expect(labels.allSatisfy { $0.fieldStyle == .transparent && $0.strokeWidth == 0 })
    }
}

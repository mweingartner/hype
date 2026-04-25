import Testing
import Foundation
@testable import HypeCore

/// End-to-end verification that the AI tool executor actually mutates
/// the document it receives.
///
/// This suite was written to diagnose a user-reported issue: "setting
/// scripts and properties no longer works" — observed against both the
/// v4 tuned model and gemma4:26b baseline. If the tools here pass in
/// isolation, the regression is in the call chain upstream (prompt
/// construction, tool-call parsing, dispatch) rather than in the
/// executor itself.
@Suite("AI tool chain — setters actually mutate the document")
struct AIToolChainRegressionTests {

    // MARK: - helpers

    private func docWithButton(_ name: String) -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Regression")
        let cardId = doc.cards[0].id
        var b = Part(partType: .button, cardId: cardId, name: name,
                     left: 100, top: 100, width: 120, height: 40)
        b.textContent = ""
        doc.addPart(b)
        return (doc, cardId)
    }

    private func docWithSpriteArea(_ areaName: String, sprites: [String]) -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Regression")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: areaName,
                        left: 20, top: 20, width: 600, height: 400)
        area.setSpriteAreaSpec(
            SpriteAreaSpec(defaultSceneNamed: "main",
                           fallbackSize: SizeSpec(width: 600, height: 400))
        )
        // Seed the active scene with the named sprites
        area.updateActiveSceneSpec { spec in
            for n in sprites {
                var node = HypeNodeSpec(name: n, nodeType: .sprite)
                node.position = PointSpec(x: 100, y: 100)
                node.physicsBody = PhysicsBodySpec()
                spec.nodes.append(node)
            }
        }
        doc.addPart(area)
        return (doc, cardId)
    }

    // MARK: - set_part_property

    @Test("set_part_property writes text to the named button")
    func setPartPropertyWritesText() async {
        var (doc, cardId) = docWithButton("play")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "play", "property": "text", "value": "Start Game"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!result.hasPrefix("Part '"), "unexpected error: \(result)")
        let b = doc.parts.first(where: { $0.name == "play" })
        #expect(b?.textContent == "Start Game",
                "textContent not updated — got \(b?.textContent ?? "nil")")
    }

    @Test("set_part_property is case-insensitive on part_name")
    func setPartPropertyCaseInsensitive() async {
        var (doc, cardId) = docWithButton("Play")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "play", "property": "text", "value": "Start"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.parts.first(where: { $0.name == "Play" })?.textContent == "Start",
                "case-insensitive name match failed: \(result)")
    }

    @Test("set_part_property script is wrapped and parsed")
    func setPartPropertyScript() async {
        var (doc, cardId) = docWithButton("next_btn")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "next_btn", "property": "script", "value": "go next"],
            document: &doc,
            currentCardId: cardId
        )
        let b = doc.parts.first(where: { $0.name == "next_btn" })
        #expect(b?.script.contains("on mouseUp") == true, "script not auto-wrapped: got \(b?.script ?? "nil")")
        #expect(b?.script.contains("go next") == true, "bare command lost")
        #expect(!result.contains("parse error"), "spurious parse error: \(result)")
    }

    @Test("set_part_property refuses to store an invalid script")
    func setPartPropertyRejectsInvalidScript() async {
        var (doc, cardId) = docWithButton("next_btn")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "next_btn", "property": "script", "value": "hype.showNextCard();"],
            document: &doc,
            currentCardId: cardId
        )
        let b = doc.parts.first(where: { $0.name == "next_btn" })
        #expect(result.contains("Refused to store invalid script"))
        #expect(b?.script.isEmpty == true, "invalid script should not be persisted")
    }

    // MARK: - set_card_script (NEW in v3)

    @Test("set_card_script writes to the current card when card_name omitted")
    func setCardScriptCurrentCard() async {
        var (doc, cardId) = docWithButton("play")
        let executor = HypeToolExecutor()
        let script = "on openCard\n  answer \"hello\"\nend openCard"
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!result.lowercased().contains("not found"), "executor reported missing card: \(result)")
        let card = doc.cards.first(where: { $0.id == cardId })!
        #expect(card.script.contains("on openCard"),
                "card script not persisted — got: '\(card.script)'")
        #expect(card.script.contains("answer"))
    }

    @Test("set_card_script targets a specific card by name")
    func setCardScriptByName() async {
        var doc = HypeDocument.newDocument(name: "Regression")
        let first = doc.cards[0].id
        let second = doc.addCard(afterIndex: 0, backgroundName: nil).id
        doc.cards[doc.cards.firstIndex(where: { $0.id == second })!].name = "intro"

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["card_name": "intro", "script": "on mouseUp\n  beep\nend mouseUp"],
            document: &doc,
            currentCardId: first
        )
        #expect(!result.lowercased().contains("not found"), "card-by-name lookup failed: \(result)")
        let intro = doc.cards.first(where: { $0.name == "intro" })!
        let untouched = doc.cards.first(where: { $0.id == first })!
        #expect(intro.script.contains("beep"),
                "intro card script not persisted: '\(intro.script)'")
        #expect(untouched.script.isEmpty,
                "wrong card was modified: first card script = '\(untouched.script)'")
    }

    @Test("set_card_script refuses to store an invalid script")
    func setCardScriptRejectsInvalidScript() async {
        var (doc, cardId) = docWithButton("play")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_card_script",
            arguments: ["script": "hype.showNextCard();"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.contains("Refused to store invalid script"))
        #expect(doc.cards.first(where: { $0.id == cardId })?.script.isEmpty == true)
    }

    // MARK: - set_background_script

    @Test("set_background_script writes to a named background")
    func setBackgroundScriptByName() async {
        var doc = HypeDocument.newDocument(name: "Regression")
        let bgName = doc.backgrounds[0].name
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_background_script",
            arguments: ["background_name": bgName,
                        "script": "on openBackground\n  play \"sosumi\"\nend openBackground"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(!result.lowercased().contains("not found"), "executor: \(result)")
        let bg = doc.backgrounds.first(where: { $0.name == bgName })!
        #expect(bg.script.contains("openBackground"),
                "background script not persisted: '\(bg.script)'")
    }

    // MARK: - set_stack_script

    @Test("set_stack_script writes to the stack")
    func setStackScript() async {
        var doc = HypeDocument.newDocument(name: "Regression")
        let executor = HypeToolExecutor()
        let script = "on openStack\n  global score\n  put 0 into score\nend openStack"
        _ = await executor.execute(
            toolName: "set_stack_script",
            arguments: ["script": script],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(doc.stack.script.contains("global score"),
                "stack script not persisted: '\(doc.stack.script)'")
    }

    // MARK: - set_node_property on sprite areas

    @Test("set_node_property on a sprite sets alpha in the active scene")
    func setNodePropertyAlpha() async {
        var (doc, cardId) = docWithSpriteArea("arena", sprites: ["player"])
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_node_property",
            arguments: ["sprite_area_name": "arena",
                        "node_name": "player",
                        "property": "alpha",
                        "value": "0.5"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!result.lowercased().contains("not found"), "executor: \(result)")

        let area = doc.parts.first(where: { $0.name == "arena" })!
        let node = area.activeSceneSpec?.node(named: "player")
        #expect(node != nil, "player node disappeared")
        #expect(abs((node?.alpha ?? 1) - 0.5) < 0.0001,
                "alpha not updated — got \(node?.alpha ?? 1)")
    }

    @Test("set_physics_body updates restitution without overwriting other fields")
    func setPhysicsBodyRestitution() async {
        var (doc, cardId) = docWithSpriteArea("arena", sprites: ["ball"])
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_physics_body",
            arguments: ["sprite_area_name": "arena",
                        "node_name": "ball",
                        "restitution": "1.0",
                        "friction": "0"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!result.lowercased().contains("not found"), "executor: \(result)")

        let area = doc.parts.first(where: { $0.name == "arena" })!
        let node = area.activeSceneSpec?.node(named: "ball")
        #expect(abs((node?.physicsBody?.restitution ?? 0) - 1.0) < 0.0001,
                "restitution not updated — got \(node?.physicsBody?.restitution ?? 0)")
        #expect(abs((node?.physicsBody?.friction ?? 1) - 0.0) < 0.0001,
                "friction not updated — got \(node?.physicsBody?.friction ?? 1)")
    }

    // MARK: - set_scene_script

    @Test("set_scene_script writes to the active scene of the sprite area")
    func setSceneScriptActiveScene() async {
        var (doc, cardId) = docWithSpriteArea("arena", sprites: ["player"])
        let executor = HypeToolExecutor()
        let script = """
        on sceneDidLoad
          set the restitution of sprite "player" to 1
        end sceneDidLoad
        """
        let result = await executor.execute(
            toolName: "set_scene_script",
            arguments: ["sprite_area_name": "arena", "script": script],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!result.lowercased().contains("not found"), "executor: \(result)")

        let area = doc.parts.first(where: { $0.name == "arena" })!
        let sceneScript = area.activeSceneSpec?.script ?? ""
        #expect(sceneScript.contains("sceneDidLoad"),
                "scene script not persisted: '\(sceneScript)'")
        #expect(sceneScript.contains("sprite \"player\""))
    }

    @Test("set_scene_script refuses to store an invalid script")
    func setSceneScriptRejectsInvalidScript() async {
        var (doc, cardId) = docWithSpriteArea("arena", sprites: ["player"])
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_scene_script",
            arguments: ["sprite_area_name": "arena", "script": "hype.showNextCard();"],
            document: &doc,
            currentCardId: cardId
        )
        let area = doc.parts.first(where: { $0.name == "arena" })!
        #expect(result.contains("Refused to store invalid script"))
        #expect(area.activeSceneSpec?.script.isEmpty == true)
    }

    // MARK: - add_label_to_scene (NEW in v3)

    @Test("add_label_to_scene creates a label node in the active scene")
    func addLabelToScene() async {
        var (doc, cardId) = docWithSpriteArea("game", sprites: [])
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "add_label_to_scene",
            arguments: ["sprite_area_name": "game",
                        "label_name": "score_label",
                        "text": "Score: 0",
                        "x": "20",
                        "y": "20",
                        "font_size": "24",
                        "font_color": "#FFFFFF"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!result.lowercased().contains("not found"), "executor: \(result)")

        let area = doc.parts.first(where: { $0.name == "game" })!
        let node = area.activeSceneSpec?.node(named: "score_label")
        #expect(node?.nodeType == .label,
                "label_to_scene did not create a label: \(node?.nodeType.rawValue ?? "nil")")
        #expect(node?.text == "Score: 0",
                "label text not persisted — got \(node?.text ?? "nil")")
    }

    // MARK: - get_part_property (NEW in v3)

    @Test("get_part_property reads text back from a named button")
    func getPartProperty() async {
        var (doc, cardId) = docWithButton("play")
        doc.parts[doc.parts.firstIndex(where: { $0.name == "play" })!].textContent = "Start Game"
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "play", "property": "text"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.contains("Start Game"),
                "get_part_property didn't return the stored text — got '\(result)'")
    }

    // MARK: - list_scene_nodes (NEW in v3)

    @Test("list_scene_nodes enumerates every node in the active scene")
    func listSceneNodes() async {
        var (doc, cardId) = docWithSpriteArea("arena",
                                               sprites: ["blue_ball", "yellow_ball", "green_ball"])
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "list_scene_nodes",
            arguments: ["sprite_area_name": "arena"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.contains("blue_ball"))
        #expect(result.contains("yellow_ball"))
        #expect(result.contains("green_ball"))
    }

    // MARK: - hypothetical regression — delete_part must target correct card

    @Test("delete_part only removes a part by exact name match")
    func deletePartExactMatch() async {
        var doc = HypeDocument.newDocument(name: "Regression")
        let cardId = doc.cards[0].id
        doc.addPart(Part(partType: .button, cardId: cardId, name: "keep"))
        doc.addPart(Part(partType: .button, cardId: cardId, name: "remove"))
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "delete_part",
            arguments: ["part_name": "remove"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.parts.contains(where: { $0.name == "keep" }),
                "delete_part removed wrong part — 'keep' disappeared")
        #expect(!doc.parts.contains(where: { $0.name == "remove" }),
                "delete_part failed — 'remove' still present")
    }
}

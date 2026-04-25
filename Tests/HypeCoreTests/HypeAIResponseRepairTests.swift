import Testing
import Foundation
@testable import HypeCore

@Suite("AI response repair")
struct HypeAIResponseRepairTests {
    @Test("validatedToolCalls drops empty function names from Ollama")
    func dropsEmptyFunctionName() {
        let bogus = OllamaToolCall(function: OllamaToolCallFunction(name: "", arguments: [:]))
        #expect(HypeAIResponseRepair.validatedToolCalls([bogus]) == nil)
    }

    @Test("extracts XML-ish start_function tool call and normalizes script argument")
    func extractsStartFunctionCall() throws {
        let content = """
        <start_function>set_background_script</start_function>
        <parameters>
          <property>script</property>
          <value>on openBackground
          answer "hi"
        end openBackground</value>
        </parameters>
        """

        let call = try #require(HypeAIResponseRepair.extractToolCalls(from: content)?.first)
        #expect(call.function.name == "set_background_script")
        #expect(call.function.arguments["script"]?.contains("openBackground") == true)
        #expect(call.function.arguments["property"] == "script")
    }

    @Test("extracts escaped Gemma function syntax")
    func extractsEscapedFunctionCall() throws {
        let content = #"<escape>get_part_property{part_name:<escape>score<escape>, property:<escape>text<escape>}<escape>"#

        let call = try #require(HypeAIResponseRepair.extractToolCalls(from: content)?.first)
        #expect(call.function.name == "get_part_property")
        #expect(call.function.arguments["part_name"] == "score")
        #expect(call.function.arguments["property"] == "text")
    }

    @Test("script attachment fallback stores Sprite Area scripts on active scene")
    func spriteAreaScriptAttachmentFallback() async throws {
        var doc = HypeDocument.newDocument(name: "Repair")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 500, height: 320)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 500, height: 320)))
        area.updateActiveSceneSpec { scene in
            scene.nodes.append(HypeNodeSpec(name: "blue_ball", nodeType: .sprite))
            scene.nodes.append(HypeNodeSpec(name: "red_ball", nodeType: .sprite))
        }
        doc.addPart(area)

        let prompt = "Create the script on the bounder object on this card with one that sets all sprites in motion with physics, bouncing off the perimeter of the scene and each other. Have the script look for if the mouse intersects the location of the blue_ball sprite and, if it ever does, increase the velocity of the blue_ball by 50% each time."
        let call = try #require(HypeAIResponseRepair.scriptAttachmentToolCall(
            userMessage: prompt,
            modelContent: "I can do that.",
            document: doc,
            currentCardId: cardId
        ))

        #expect(call.function.name == "set_scene_script")
        #expect(call.function.arguments["sprite_area_name"] == "bounder")
        let script = try #require(call.function.arguments["script"])
        #expect(script.contains("the hoveredSprite"))
        #expect(script.contains("blue_ball"))
        #expect(script.contains("red_ball"))
        #expect(script.contains("contactTestBitmask"))
        #expect(!script.contains("on idle"))

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: call.function.name,
            arguments: call.function.arguments,
            document: &doc,
            currentCardId: cardId
        )
        #expect(!result.contains("Refused"), "script should validate: \(result)")
        let stored = doc.parts.first(where: { $0.name == "bounder" })?.activeSceneSpec?.script ?? ""
        #expect(stored.contains("frameUpdate"))
        #expect(stored.contains("velocityX of sprite \"blue_ball\""))
    }

    @Test("structured part script call to Sprite Area is repaired to scene script")
    func structuredSpriteAreaPartScriptRepair() throws {
        var doc = HypeDocument.newDocument(name: "Repair")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 500, height: 320)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 500, height: 320)))
        area.updateActiveSceneSpec { scene in
            scene.nodes.append(HypeNodeSpec(name: "blue_ball", nodeType: .sprite))
        }
        doc.addPart(area)

        let misrouted = OllamaToolCall(function: OllamaToolCallFunction(
            name: "set_part_property",
            arguments: [
                "part_name": "bounder",
                "property": "script",
                "value": "on mouseOver\n  setNodeProperty(\"blue_ball\", \"velocityX\", \"50%\")\nend mouseOver"
            ]
        ))

        let repaired = try #require(HypeAIResponseRepair.repairedToolCalls(
            [misrouted],
            userMessage: "Create the script on the bounder object on this card that uses the hoveredSprite to detect blue_ball and increases its velocity by 50 percent when hovered.",
            document: doc,
            currentCardId: cardId
        )?.first)

        #expect(repaired.function.name == "set_scene_script")
        #expect(repaired.function.arguments["sprite_area_name"] == "bounder")
        #expect(repaired.function.arguments["script"]?.contains("the hoveredSprite") == true)
        #expect(repaired.function.arguments["script"]?.contains("blue_ball") == true)
        #expect(repaired.function.arguments["script"]?.contains("setNodeProperty") == false)
    }

    @Test("structured background object prompt is repaired to background parts")
    func structuredBackgroundPartsRepair() throws {
        let doc = HypeDocument.newDocument(name: "Repair")
        let cardId = doc.cards[0].id
        let misrouted = OllamaToolCall(function: OllamaToolCallFunction(
            name: "get_card_parts",
            arguments: [:]
        ))

        let repaired = try #require(HypeAIResponseRepair.repairedToolCalls(
            [misrouted],
            userMessage: "List the background objects on this card.",
            document: doc,
            currentCardId: cardId
        )?.first)

        #expect(repaired.function.name == "get_background_parts")
    }

    @Test("structured scene script physics prompt is replaced with valid HypeTalk")
    func structuredSceneScriptPhysicsRepair() throws {
        var doc = HypeDocument.newDocument(name: "Repair")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 500, height: 320)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 500, height: 320)))
        area.updateActiveSceneSpec { scene in
            scene.nodes.append(HypeNodeSpec(name: "blue_ball", nodeType: .sprite))
            scene.nodes.append(HypeNodeSpec(name: "red_ball", nodeType: .sprite))
        }
        doc.addPart(area)

        let badSceneCall = OllamaToolCall(function: OllamaToolCallFunction(
            name: "set_scene_script",
            arguments: [
                "sprite_area_name": "bounder",
                "script": "on sceneDidLoad\n  set physicsWorld.gravity to (0,-9.8)\nend sceneDidLoad"
            ]
        ))

        let repaired = try #require(HypeAIResponseRepair.repairedToolCalls(
            [badSceneCall],
            userMessage: "Create the script on the bounder object on this card with one that sets all sprites in motion with physics, bouncing off the perimeter of the scene and each other. Have the script look for if the mouse intersects the location of the blue_ball sprite and, if it ever does, increase the velocity of the blue_ball by 50% each time.",
            document: doc,
            currentCardId: cardId
        )?.first)

        #expect(repaired.function.name == "set_scene_script")
        #expect(repaired.function.arguments["script"]?.contains("the hoveredSprite") == true)
        #expect(repaired.function.arguments["script"]?.contains("contactTestBitmask") == true)
        #expect(repaired.function.arguments["script"]?.contains("physicsWorld") == false)
    }

    @Test("structured check_script physics prompt is replaced with scene setter")
    func structuredCheckScriptPhysicsRepair() throws {
        var doc = HypeDocument.newDocument(name: "Repair")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 20, top: 20, width: 500, height: 320)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 500, height: 320)))
        area.updateActiveSceneSpec { scene in
            scene.nodes.append(HypeNodeSpec(name: "blue_ball", nodeType: .sprite))
            scene.nodes.append(HypeNodeSpec(name: "red_ball", nodeType: .sprite))
        }
        doc.addPart(area)

        let badCheck = OllamaToolCall(function: OllamaToolCallFunction(
            name: "check_script",
            arguments: ["script": "on sceneDidLoad\n  set physicsWorld.gravity to (0,-9.8)\nend sceneDidLoad"]
        ))

        let repaired = try #require(HypeAIResponseRepair.repairedToolCalls(
            [badCheck],
            userMessage: "Create the script on the bounder object on this card with one that sets all sprites in motion with physics, bouncing off the perimeter of the scene and each other. Have the script look for if the mouse intersects the location of the blue_ball sprite and, if it ever does, increase the velocity of the blue_ball by 50% each time.",
            document: doc,
            currentCardId: cardId
        )?.first)

        #expect(repaired.function.name == "set_scene_script")
        #expect(repaired.function.arguments["script"]?.contains("the hoveredSprite") == true)
        #expect(repaired.function.arguments["script"]?.contains("contactTestBitmask") == true)
    }

    @Test("script attachment fallback can attach plain model script to a button")
    func buttonScriptAttachmentFallback() async throws {
        var doc = HypeDocument.newDocument(name: "Repair")
        let cardId = doc.cards[0].id
        doc.addPart(Part(partType: .button, cardId: cardId, name: "next", left: 20, top: 20, width: 120, height: 40))

        let modelScript = """
        on mouseUp
          go next
        end mouseUp
        """
        let call = try #require(HypeAIResponseRepair.scriptAttachmentToolCall(
            userMessage: "Write the script of button next so it goes to the next card",
            modelContent: modelScript,
            document: doc,
            currentCardId: cardId
        ))
        #expect(call.function.name == "set_part_property")
        #expect(call.function.arguments["part_name"] == "next")
        #expect(call.function.arguments["property"] == "script")

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: call.function.name,
            arguments: call.function.arguments,
            document: &doc,
            currentCardId: cardId
        )
        let button = doc.parts.first(where: { $0.name == "next" })
        #expect(button?.script.contains("go next") == true)
    }

    @Test("script attachment fallback uses quoted command when model tool call is empty")
    func buttonScriptAttachmentFromQuotedCommand() throws {
        var doc = HypeDocument.newDocument(name: "Repair")
        let cardId = doc.cards[0].id
        doc.addPart(Part(partType: .button, cardId: cardId, name: "next", left: 20, top: 20, width: 120, height: 40))

        let call = try #require(HypeAIResponseRepair.scriptAttachmentToolCall(
            userMessage: "Set the script of button next to 'go next' so clicking it advances to the next card.",
            modelContent: nil,
            document: doc,
            currentCardId: cardId
        ))
        #expect(call.function.name == "set_part_property")
        #expect(call.function.arguments["part_name"] == "next")
        #expect(call.function.arguments["value"] == "go next")
    }
}

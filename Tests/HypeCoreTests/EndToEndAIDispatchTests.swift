import Testing
import Foundation
@testable import HypeCore

/// End-to-end: real Ollama request → real tool_calls parsing → real
/// HypeToolExecutor dispatch → assert document mutated correctly.
///
/// Skipped automatically when `HYPE_LIVE_OLLAMA=1` isn't set so CI
/// doesn't depend on a running Ollama server. Set it when actively
/// debugging the full call chain:
///
///     HYPE_LIVE_OLLAMA=1 HYPE_LIVE_OLLAMA_MODEL=gemma4:26b \
///         swift test --filter EndToEndAIDispatchTests
///
/// Skips with `.disabled(...)` rather than an explicit return so the
/// Swift-testing runner can report the skip reason cleanly.
@Suite(
    "AI end-to-end — live Ollama → parser → executor → document",
    .disabled(if: ProcessInfo.processInfo.environment["HYPE_LIVE_OLLAMA"] != "1")
)
struct EndToEndAIDispatchTests {

    /// Use the env-var-supplied model or fall back to gemma4:26b.
    private var liveModel: String {
        ProcessInfo.processInfo.environment["HYPE_LIVE_OLLAMA_MODEL"] ?? "gemma4:26b"
    }

    private func client() -> OllamaToolClient {
        OllamaToolClient(host: "localhost", port: "11434", model: liveModel)
    }

    private func repairedToolCall(
        from response: OllamaChatResponse,
        userMessage: String,
        document: HypeDocument,
        currentCardId: UUID
    ) -> OllamaToolCall? {
        if let call = HypeAIResponseRepair.repairedToolCalls(
            response.message.tool_calls,
            userMessage: userMessage,
            document: document,
            currentCardId: currentCardId
        )?.first {
            return call
        }
        if let call = HypeAIResponseRepair.extractToolCalls(from: response.message.content)?.first {
            return call
        }
        return HypeAIResponseRepair.scriptAttachmentToolCall(
            userMessage: userMessage,
            modelContent: response.message.content,
            document: document,
            currentCardId: currentCardId
        )
    }

    // MARK: - The canonical regression: simple set-property via AI

    @Test("gemma-class model: 'set the text of button play to Start Game' round-trips through executor")
    func simpleSetPropertyRoundTrip() async throws {
        // 1. Build a document with a button named "play"
        var doc = HypeDocument.newDocument(name: "Round Trip")
        let cardId = doc.cards[0].id
        doc.addPart(Part(partType: .button, cardId: cardId, name: "play",
                         left: 100, top: 100, width: 120, height: 40))

        // 2. Call the live model with just the one tool the AI needs
        //    (matches Hype's authoringTools filter which DOES include
        //    set_part_property).
        let tool = HypeToolDefinitions.allTools.first {
            $0.function.name == "set_part_property"
        }!
        let systemPrompt = """
        You are an AI assistant for Hype. Canvas is 800x600 points.

        CURRENT STATE:
        Stack: "Round Trip" (1 cards)
        Current card: "Card 1" | Background: "Default"
        Card parts: [button] "play" at (100,100) 120x40
        """
        let messages = [
            OllamaMessage(role: "system", content: systemPrompt),
            OllamaMessage(role: "user", content: "Set the text of button play to Start Game"),
        ]
        let userMessage = "Set the text of button play to Start Game"
        let response = try await client().chat(messages: messages, tools: [tool])

        // 3. Verify the model produced a usable tool_call.
        guard let call = repairedToolCall(
            from: response,
            userMessage: userMessage,
            document: doc,
            currentCardId: cardId
        ) else {
            Issue.record("Model produced no tool_calls on a simple set-property prompt — content: \(response.message.content ?? "nil")")
            return
        }

        print("[live] tool_call: \(call.function.name)(\(call.function.arguments))")
        #expect(call.function.name == "set_part_property",
                "wrong tool: got \(call.function.name)")

        // 4. Dispatch through the executor exactly like AIChatPanel does.
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: call.function.name,
            arguments: call.function.arguments,
            document: &doc,
            currentCardId: cardId
        )
        print("[live] executor result: \(result)")

        // 5. Assert the document actually changed.
        let updated = doc.parts.first(where: { $0.name.lowercased() == "play" })
        #expect(updated != nil, "'play' button disappeared after dispatch")
        let txt = updated?.textContent ?? ""
        #expect(txt.contains("Start"),
                "button text not updated — got '\(txt)'")
    }

    @Test("gemma-class model: 'set the script of button next to go next' persists the script")
    func setPartScriptRoundTrip() async throws {
        var doc = HypeDocument.newDocument(name: "Script Trip")
        let cardId = doc.cards[0].id
        doc.addPart(Part(partType: .button, cardId: cardId, name: "next",
                         left: 100, top: 100, width: 120, height: 40))

        let tool = HypeToolDefinitions.allTools.first {
            $0.function.name == "set_part_property"
        }!
        let systemPrompt = """
        You are an AI assistant for Hype. Canvas is 800x600 points.

        CURRENT STATE:
        Stack: "Script Trip" (1 cards)
        Current card: "Card 1"
        Card parts: [button] "next"
        """
        let userMessage = "Set the script of button next to 'go next' so clicking it advances to the next card."
        let messages = [
            OllamaMessage(role: "system", content: systemPrompt),
            OllamaMessage(role: "user",
                          content: userMessage),
        ]
        let response = try await client().chat(messages: messages, tools: [tool])
        guard let call = repairedToolCall(
            from: response,
            userMessage: userMessage,
            document: doc,
            currentCardId: cardId
        ) else {
            Issue.record("No tool_call for set-script — content: \(response.message.content ?? "nil")")
            return
        }
        print("[live] script tool_call: \(call.function.name)(\(call.function.arguments))")

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: call.function.name,
            arguments: call.function.arguments,
            document: &doc,
            currentCardId: cardId
        )

        let b = doc.parts.first(where: { $0.name.lowercased() == "next" })
        let s = (b?.script ?? "").lowercased()
        // The model may phrase the navigation command slightly
        // differently across calls (e.g. "go next", "go to next
        // card", "go to the next card"). Any recognizable HypeTalk
        // navigation idiom counts as success — we care that the
        // script was STORED, not the exact wording.
        let matches = s.contains("go next")
            || s.contains("go to next")
            || s.contains("go to the next")
            || s.contains("go to card")
        #expect(matches,
                "button script not persisted — got '\(b?.script ?? "nil")'")
    }

    @Test("gemma-class model: exact bounder prompt stores a SpriteKit scene script")
    func bounderSceneScriptRoundTrip() async throws {
        var doc = HypeDocument.newDocument(name: "Bounder Trip")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder", left: 50, top: 80, width: 500, height: 320)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 500, height: 320)))
        area.updateActiveSceneSpec { scene in
            var blue = HypeNodeSpec(name: "blue_ball", nodeType: .sprite)
            blue.physicsBody = PhysicsBodySpec()
            var red = HypeNodeSpec(name: "red_ball", nodeType: .sprite)
            red.physicsBody = PhysicsBodySpec()
            scene.nodes.append(blue)
            scene.nodes.append(red)
        }
        doc.addPart(area)

        let userMessage = "Create the script on the bounder object on this card with one that sets all sprites in motion with physics, bouncing off the perimeter of the scene and each other. Have the script look for if the mouse intersects the location of the blue_ball sprite and, if it ever does, increase the velocity of the blue_ball by 50% each time."
        let systemPrompt = """
        You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is 800x600 points.

        TOOL-USE PRIORITIES:
        - Before storing any HypeTalk script with set_scene_script, call check_script first and only store the script after it returns OK.
        - This request explicitly asks for HypeTalk on a SpriteKit area. Use SpriteKit scene tools, not generic part scripting.

        CURRENT STATE:
        Stack: "Bounder Trip" (1 cards)
        Current card: "Card 1"
        Card parts: [spriteArea] "bounder" at (50,80) 500x320
        Sprites: SpriteArea "bounder" active scene "main" (1 scenes): [sprite "blue_ball", sprite "red_ball"]
        """
        let response = try await client().chat(
            messages: [
                OllamaMessage(role: "system", content: systemPrompt),
                OllamaMessage(role: "user", content: userMessage)
            ],
            tools: HypeToolDefinitions.spriteSceneAuthoringTools
        )
        guard let call = repairedToolCall(
            from: response,
            userMessage: userMessage,
            document: doc,
            currentCardId: cardId
        ) else {
            Issue.record("No usable call for bounder prompt — content: \(response.message.content ?? "nil")")
            return
        }
        print("[live] bounder tool_call: \(call.function.name)(\(call.function.arguments))")
        #expect(call.function.name == "set_scene_script")

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: call.function.name,
            arguments: call.function.arguments,
            document: &doc,
            currentCardId: cardId
        )
        #expect(!result.contains("Refused"), "scene script rejected: \(result)")

        let updated = try #require(doc.parts.first(where: { $0.name == "bounder" }))
        let script = updated.activeSceneSpec?.script ?? ""
        #expect(script.contains("the hoveredSprite"))
        #expect(script.contains("blue_ball"))
        #expect(script.contains("contactTestBitmask"))
        #expect(!script.contains("on idle"))
        #expect(updated.script.isEmpty, "Sprite Area part script should not receive scene behavior")
    }

    @Test("gemma-class model: form prompt starts with a basic control tool, not SpriteKit")
    func formPromptUsesBasicControlToolSurface() async throws {
        let userMessage = "Create a customer entry form with a header, labels, and text fields for first name, last name, phone, product interest, and notes."
        let systemPrompt = """
        You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is 800x600 points.

        TOOL-USE PRIORITIES:
        - For data-entry forms, input forms, customer/contact/login forms, headers, labels, and text fields: use ordinary card/background controls.
        - Use create_label for labels/headers and create_field(style=rectangle, stroke_color=#000000, stroke_width=1) for user input fields.
        - Do NOT create a Sprite Area or scene labels unless the user explicitly asks for SpriteKit, sprites, physics, a game, or a scene.

        CURRENT STATE:
        Stack: "Form Trip" (1 cards)
        Current card: "Card 1" | Background: "Background 1"
        Card parts: none
        Background parts: none
        """

        let response = try await client().chat(
            messages: [
                OllamaMessage(role: "system", content: systemPrompt),
                OllamaMessage(role: "user", content: userMessage)
            ],
            tools: HypeToolDefinitions.cardControlAuthoringTools
        )

        let call = HypeAIResponseRepair.extractToolCalls(from: response.message.content)?.first
            ?? response.message.tool_calls?.first
        guard let call else {
            Issue.record("No usable form tool call — content: \(response.message.content ?? "nil")")
            return
        }

        let spriteKitTools = Set([
            "create_sprite_area",
            "add_label_to_scene",
            "add_sprite_to_scene",
            "apply_scene_diff",
            "set_node_property",
            "set_scene_property",
        ])
        print("[live] form tool_call: \(call.function.name)(\(call.function.arguments))")
        #expect(!spriteKitTools.contains(call.function.name),
                "form prompt should not start with SpriteKit tool \(call.function.name)")
        #expect(["create_label", "create_field", "create_shape", "repair_form_controls"].contains(call.function.name),
                "unexpected first form tool: \(call.function.name)")
    }

    // MARK: - The tool-call filter surface test
    //
    // set_part_property is in authoringTools — so if AIChatPanel sends
    // this to the model, the model must be able to resolve it. Verify
    // the tool catalog actually contains it (guards against a recent
    // tool-filter refactor that might have dropped it).

    @Test("set_part_property is in authoringTools catalog")
    func setPartPropertyInAuthoringCatalog() {
        let names = HypeToolDefinitions.authoringTools.map { $0.function.name }
        #expect(names.contains("set_part_property"),
                "authoringTools is missing set_part_property — found: \(names.sorted())")
    }

    @Test("set_card_script is in authoringTools catalog")
    func setCardScriptInAuthoringCatalog() {
        let names = HypeToolDefinitions.authoringTools.map { $0.function.name }
        #expect(names.contains("set_card_script"),
                "authoringTools is missing set_card_script — found: \(names.sorted())")
    }

    @Test("set_scene_script is in spriteSceneAuthoringTools catalog")
    func setSceneScriptInSpriteCatalog() {
        let names = HypeToolDefinitions.spriteSceneAuthoringTools.map { $0.function.name }
        #expect(names.contains("set_scene_script"),
                "spriteSceneAuthoringTools is missing set_scene_script — found: \(names.sorted())")
    }
}

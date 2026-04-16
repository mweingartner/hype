import Testing
import Foundation
@testable import HypeCore

// Regression tests for `OllamaToolClient.decodeStructuredResponse` and
// the lenient `SceneBlueprint` / `SceneBlueprintNode` decoders. The
// original bug: when a user asked "add a red square, blue triangle,
// and yellow circle... with physics", the `structuredChat` call to
// Ollama came back with a response that strict Swift Codable refused
// to decode — the model named a "triangle" (not in the SpriteShapeType
// enum), omitted some bool flags, or wrapped its JSON in a markdown
// code fence. The resulting error was the opaque "The data couldn't
// be read because it isn't in the correct format".
//
// These tests pin down the specific shapes we must now tolerate.
@Suite("Structured Ollama response decoding — robustness")
struct StructuredChatDecodingTests {

    // Minimal well-formed blueprint JSON used as a base — tests mutate
    // one field at a time to isolate the tolerant behavior.
    private static let canonicalSceneJSON = """
    {
        "areaName": "bounder",
        "sceneName": "main",
        "createSpriteAreaIfMissing": true,
        "summary": "",
        "checklist": [],
        "scene": {
            "size": { "width": 640, "height": 480 },
            "backgroundColor": "#EEEEEE",
            "gravity": { "dx": 0, "dy": 0 },
            "scaleMode": "aspectFit",
            "showsPhysics": false,
            "showsFPS": false,
            "showsNodeCount": false,
            "sceneScript": "",
            "nodes": []
        }
    }
    """

    // MARK: - Lenient SceneBlueprint decoding

    @Test("unknown shapeType 'triangle' promotes node to shape+path instead of failing")
    func triangleShapePromotesToPath() throws {
        let json = """
        {
            "areaName": "bounder",
            "sceneName": "main",
            "createSpriteAreaIfMissing": true,
            "summary": "",
            "checklist": [],
            "scene": {
                "size": { "width": 400, "height": 300 },
                "backgroundColor": "#EEEEEE",
                "gravity": { "dx": 0, "dy": 0 },
                "scaleMode": "aspectFit",
                "showsPhysics": false,
                "showsFPS": false,
                "showsNodeCount": false,
                "sceneScript": "",
                "nodes": [
                    {
                        "name": "tri",
                        "nodeType": "sprite",
                        "position": { "x": 50, "y": 50 },
                        "shapeType": "triangle",
                        "physicsEnabled": true
                    }
                ]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let proposal = try JSONDecoder().decode(SceneCreateProposal.self, from: data)
        let node = proposal.scene.nodes[0]
        #expect(node.shapeType == .path)
        // Heuristic: "sprite" + explicit shapeType promotes to shape
        #expect(node.nodeType == .shape)
    }

    @Test("unknown shapeType 'square' maps to rect")
    func squareShapeMapsToRect() throws {
        let fragment = """
        { "name": "box", "nodeType": "shape", "position": {"x":0,"y":0}, "shapeType": "square", "physicsEnabled": false }
        """
        let data = fragment.data(using: .utf8)!
        let node = try JSONDecoder().decode(SceneBlueprintNode.self, from: data)
        #expect(node.shapeType == .rect)
    }

    @Test("SceneBlueprint decodes when optional flag fields are missing")
    func missingBoolFlagsUseDefaults() throws {
        // No `showsPhysics` / `showsFPS` / `showsNodeCount` / `sceneScript`.
        let json = """
        {
            "areaName": "a",
            "sceneName": "s",
            "createSpriteAreaIfMissing": true,
            "summary": "x",
            "checklist": [],
            "scene": {
                "size": { "width": 100, "height": 100 },
                "backgroundColor": "#000000",
                "gravity": { "dx": 0, "dy": 0 },
                "scaleMode": "aspectFit",
                "nodes": []
            }
        }
        """
        let data = json.data(using: .utf8)!
        let proposal = try JSONDecoder().decode(SceneCreateProposal.self, from: data)
        #expect(proposal.scene.showsPhysics == false)
        #expect(proposal.scene.sceneScript == "")
    }

    @Test("unknown scaleMode falls back to aspectFit instead of failing")
    func unknownScaleModeFallsBack() throws {
        let json = """
        {
            "areaName": "a",
            "sceneName": "s",
            "createSpriteAreaIfMissing": true,
            "summary": "",
            "checklist": [],
            "scene": {
                "size": { "width": 100, "height": 100 },
                "backgroundColor": "#000",
                "gravity": { "dx": 0, "dy": 0 },
                "scaleMode": "stretch-to-fit",
                "showsPhysics": false,
                "showsFPS": false,
                "showsNodeCount": false,
                "sceneScript": "",
                "nodes": []
            }
        }
        """
        let data = json.data(using: .utf8)!
        let proposal = try JSONDecoder().decode(SceneCreateProposal.self, from: data)
        #expect(proposal.scene.scaleMode == .aspectFit)
    }

    @Test("SceneBlueprintNode nodeType 'text' is interpreted as label")
    func nodeTypeSynonymsMap() throws {
        let json = #"{ "name": "greeting", "nodeType": "text", "position": {"x":0,"y":0}, "physicsEnabled": false }"#
        let node = try JSONDecoder().decode(SceneBlueprintNode.self, from: json.data(using: .utf8)!)
        #expect(node.nodeType == .label)
    }

    @Test("SceneBlueprintNode nodeType 'particles' maps to emitter")
    func particlesSynonymMapsToEmitter() throws {
        let json = #"{ "name": "sparks", "nodeType": "particles", "position": {"x":0,"y":0}, "physicsEnabled": false }"#
        let node = try JSONDecoder().decode(SceneBlueprintNode.self, from: json.data(using: .utf8)!)
        #expect(node.nodeType == .emitter)
    }

    @Test("SceneBlueprintNode with missing physicsEnabled defaults to false")
    func physicsEnabledDefault() throws {
        let json = #"{ "name": "foo", "nodeType": "shape", "position": {"x":0,"y":0} }"#
        let node = try JSONDecoder().decode(SceneBlueprintNode.self, from: json.data(using: .utf8)!)
        #expect(node.physicsEnabled == false)
    }

    @Test("unknown physicsBodyType 'octagon' falls back to .rect (AABB approximation)")
    func unknownPhysicsBodyTypeFallsBackToRect() throws {
        let json = """
        {
            "name": "x",
            "nodeType": "shape",
            "position": { "x": 0, "y": 0 },
            "physicsEnabled": true,
            "physicsBodyType": "octagon"
        }
        """
        let node = try JSONDecoder().decode(SceneBlueprintNode.self, from: json.data(using: .utf8)!)
        // Polygon-ish body types map to .rect so SpriteKit has a usable
        // body shape (its AABB) instead of dropping physics entirely.
        #expect(node.physicsBodyType == .rect)
    }

    // MARK: - Lenient top-level proposal decoding

    @Test("SceneCreateProposal decodes when areaName / sceneName / summary are missing")
    func missingProposalMetadataDecodes() throws {
        let json = """
        {
            "createSpriteAreaIfMissing": true,
            "checklist": [],
            "scene": {
                "size": { "width": 100, "height": 100 },
                "backgroundColor": "#000",
                "gravity": { "dx": 0, "dy": 0 },
                "scaleMode": "aspectFit",
                "showsPhysics": false,
                "showsFPS": false,
                "showsNodeCount": false,
                "sceneScript": "",
                "nodes": []
            }
        }
        """
        let data = json.data(using: .utf8)!
        let proposal = try JSONDecoder().decode(SceneCreateProposal.self, from: data)
        // areaName falls back to empty string (not "main") so callers
        // can detect the miss and substitute real context via
        // `applyUserRequestOverrides` or the apply-step resolver.
        #expect(proposal.areaName.isEmpty)
        #expect(proposal.summary == "")       // fallback
    }

    @Test("SceneChecklistItem with unknown status value maps to .recommended")
    func checklistUnknownStatusDefault() throws {
        let json = #"{ "key": "physics", "title": "Physics", "status": "partial", "detail": "mid" }"#
        let item = try JSONDecoder().decode(SceneChecklistItem.self, from: json.data(using: .utf8)!)
        #expect(item.status == .recommended)
    }

    @Test("SceneChecklistItem with 'done' status maps to .complete")
    func checklistDoneMapsToComplete() throws {
        let json = #"{ "key": "k", "title": "t", "status": "done", "detail": "" }"#
        let item = try JSONDecoder().decode(SceneChecklistItem.self, from: json.data(using: .utf8)!)
        #expect(item.status == .complete)
    }

    @Test("SceneDiagnosticIssue with 'warn' severity maps to .warning")
    func diagnosticWarnMapsToWarning() throws {
        let json = #"{ "severity": "warn", "message": "foo" }"#
        let issue = try JSONDecoder().decode(SceneDiagnosticIssue.self, from: json.data(using: .utf8)!)
        #expect(issue.severity == .warning)
    }

    // MARK: - structuredChat fallback extraction

    private func chatResponse(withContent content: String) -> OllamaChatResponse {
        OllamaChatResponse(
            message: OllamaMessage(role: "assistant", content: content, tool_calls: nil),
            done: true
        )
    }

    @Test("decodeStructuredResponse handles plain JSON content")
    func plainJSONDecodes() throws {
        let r = chatResponse(withContent: Self.canonicalSceneJSON)
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(
            SceneCreateProposal.self,
            from: r
        )
        #expect(decoded.areaName == "bounder")
    }

    @Test("decodeStructuredResponse strips ```json code fences")
    func codeFencedJSONDecodes() throws {
        let fenced = "```json\n" + Self.canonicalSceneJSON + "\n```"
        let r = chatResponse(withContent: fenced)
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(
            SceneCreateProposal.self,
            from: r
        )
        #expect(decoded.areaName == "bounder")
    }

    @Test("decodeStructuredResponse strips plain ``` fences")
    func plainFencedJSONDecodes() throws {
        let fenced = "```\n" + Self.canonicalSceneJSON + "\n```"
        let r = chatResponse(withContent: fenced)
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(
            SceneCreateProposal.self,
            from: r
        )
        #expect(decoded.sceneName == "main")
    }

    @Test("decodeStructuredResponse extracts JSON embedded in prose")
    func embeddedJSONDecodes() throws {
        let wrapped = "Sure thing! Here is your scene plan:\n\(Self.canonicalSceneJSON)\nLet me know if you'd like to tweak anything."
        let r = chatResponse(withContent: wrapped)
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(
            SceneCreateProposal.self,
            from: r
        )
        #expect(decoded.areaName == "bounder")
    }

    @Test("decodeStructuredResponse finds JSON inside markdown with prose")
    func fencedWithProseDecodes() throws {
        let mix = """
        Here's the plan:

        ```json
        \(Self.canonicalSceneJSON)
        ```

        Ready to apply it?
        """
        let r = chatResponse(withContent: mix)
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(
            SceneCreateProposal.self,
            from: r
        )
        #expect(decoded.areaName == "bounder")
    }

    @Test("decodeStructuredResponse falls back to tool_calls when content is empty")
    func toolCallsFallback() throws {
        // Simulate a server that placed the structured JSON inside a
        // single tool_call. The decoder should reconstruct the
        // object-shaped payload from the flat arguments map.
        let toolCall = OllamaToolCall(
            function: OllamaToolCallFunction(
                name: "scene_plan",
                arguments: [
                    "areaName": "bounder",
                    "sceneName": "main",
                    "createSpriteAreaIfMissing": "true",
                    "summary": "",
                    "checklist": "[]",
                    "scene": ##"{"size":{"width":100,"height":100},"backgroundColor":"#000","gravity":{"dx":0,"dy":0},"scaleMode":"aspectFit","showsPhysics":false,"showsFPS":false,"showsNodeCount":false,"sceneScript":"","nodes":[]}"##
                ]
            )
        )
        let response = OllamaChatResponse(
            message: OllamaMessage(role: "assistant", content: "", tool_calls: [toolCall]),
            done: true
        )
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(
            SceneCreateProposal.self,
            from: response
        )
        #expect(decoded.areaName == "bounder")
    }

    @Test("decodeStructuredResponse throws with preview snippet when nothing parses")
    func unrecoverableErrorIncludesPreview() {
        let r = chatResponse(withContent: "I refuse to do that, Dave.")
        do {
            _ = try OllamaToolClient.decodeStructuredResponse(
                SceneCreateProposal.self,
                from: r
            )
            Issue.record("Expected throw")
        } catch let OllamaError.structuredDecodeFailed(reason) {
            #expect(reason.contains("model said"))
            #expect(reason.contains("refuse"))
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("decodeStructuredResponse throws noStructuredContent when content and tool_calls are nil")
    func noContentNoToolCalls() {
        let r = OllamaChatResponse(
            message: OllamaMessage(role: "assistant", content: nil, tool_calls: nil),
            done: true
        )
        do {
            _ = try OllamaToolClient.decodeStructuredResponse(
                SceneCreateProposal.self,
                from: r
            )
            Issue.record("Expected throw")
        } catch OllamaError.noStructuredContent {
            // expected
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    // MARK: - extractFirstJSONObject balanced-brace walker

    @Test("extractFirstJSONObject finds nested objects correctly")
    func extractorFindsNested() {
        let s = "blah blah {\"a\":{\"b\":1},\"c\":2} trailing"
        let r = OllamaToolClient.extractFirstJSONObject(from: s)
        #expect(r == #"{"a":{"b":1},"c":2}"#)
    }

    @Test("extractFirstJSONObject respects string-literal braces")
    func extractorRespectsStrings() {
        let s = #"{"greeting":"hi {there}!","n":3}"#
        let r = OllamaToolClient.extractFirstJSONObject(from: s)
        #expect(r == s)
    }

    @Test("extractFirstJSONObject returns nil when no braces present")
    func extractorReturnsNilOnPlainText() {
        #expect(OllamaToolClient.extractFirstJSONObject(from: "hello world") == nil)
    }

    @Test("stripCodeFences returns nil for unfenced content")
    func stripReturnsNilForPlain() {
        #expect(OllamaToolClient.stripCodeFences(#"{"k":1}"#) == nil)
    }

    @Test("stripCodeFences removes ```json fence")
    func stripRemovesJSONFence() {
        #expect(OllamaToolClient.stripCodeFences("```json\n{\"k\":1}\n```") == "{\"k\":1}")
    }

    @Test("stripCodeFences removes bare ``` fence")
    func stripRemovesBareFence() {
        #expect(OllamaToolClient.stripCodeFences("```\n{\"k\":1}\n```") == "{\"k\":1}")
    }

    // MARK: - Real-world failure reproduction from the bug report

    // MARK: - Area-name confusion (the "Could not find sprite area 'main'" bug)

    @Test("lenient decoder leaves empty areaName when model omits it, not 'main'")
    func lenientDecoderAreaNameEmptyByDefault() throws {
        // Strip `areaName` from an otherwise-valid proposal. The previous
        // fallback was "main" — which the applyRepairProposal step then
        // treated as a real area name and couldn't find. The correct
        // behavior is an empty string so downstream logic can detect the
        // miss and substitute the caller's known target.
        let json = """
        {
            "sceneName": "main",
            "createSpriteAreaIfMissing": false,
            "summary": "",
            "checklist": [],
            "scene": {
                "size": { "width": 100, "height": 100 },
                "backgroundColor": "#000",
                "gravity": { "dx": 0, "dy": 0 },
                "scaleMode": "aspectFit",
                "showsPhysics": false,
                "showsFPS": false,
                "showsNodeCount": false,
                "sceneScript": "",
                "nodes": []
            }
        }
        """
        let proposal = try JSONDecoder().decode(
            SceneCreateProposal.self,
            from: json.data(using: .utf8)!
        )
        #expect(proposal.areaName.isEmpty)
    }

    @Test("lenient decoder leaves empty repair areaName when model omits it")
    func lenientDecoderRepairAreaNameEmptyByDefault() throws {
        let json = """
        { "summary": "fix", "issues": [], "diff": {} }
        """
        let proposal = try JSONDecoder().decode(
            SceneRepairProposal.self,
            from: json.data(using: .utf8)!
        )
        #expect(proposal.areaName.isEmpty)
    }

    @Test("applyUserRequestOverrides locks areaName to prompt-mentioned sprite area")
    func overridesLockToPromptMentionedArea() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder")
        let spec = SpriteAreaSpec(
            defaultSceneNamed: "main",
            fallbackSize: SizeSpec(width: 400, height: 300)
        )
        area.setSpriteAreaSpec(spec)
        doc.addPart(area)

        var proposal = SceneCreateProposal(
            areaName: "main",  // wrong — model confused scene name with area name
            sceneName: "",
            createSpriteAreaIfMissing: false,
            summary: "",
            checklist: [],
            scene: SceneBlueprint(
                size: SizeSpec(width: 400, height: 300),
                backgroundColor: "#FFF",
                gravity: VectorSpec(dx: 0, dy: 0),
                scaleMode: .aspectFit,
                showsPhysics: false,
                showsFPS: false,
                showsNodeCount: false,
                sceneScript: "",
                nodes: []
            )
        )
        SceneAuthoringAssistant.applyUserRequestOverrides(
            to: &proposal,
            userRequest: "add sprites to the bounder Spritearea. Scene name is main.",
            document: doc,
            currentCardId: cardId
        )
        #expect(proposal.areaName == "bounder")
        #expect(proposal.sceneName == "main")
    }

    @Test("applyUserRequestOverrides picks lone sprite area when prompt names none")
    func overridesPickLoneArea() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "playground")
        let spec = SpriteAreaSpec(
            defaultSceneNamed: "level1",
            fallbackSize: SizeSpec(width: 400, height: 300)
        )
        area.setSpriteAreaSpec(spec)
        doc.addPart(area)

        var proposal = SceneCreateProposal(
            areaName: "",  // empty after lenient decode
            sceneName: "",
            createSpriteAreaIfMissing: false,
            summary: "",
            checklist: [],
            scene: SceneBlueprint(
                size: SizeSpec(width: 400, height: 300),
                backgroundColor: "#FFF",
                gravity: VectorSpec(dx: 0, dy: 0),
                scaleMode: .aspectFit,
                showsPhysics: false,
                showsFPS: false,
                showsNodeCount: false,
                sceneScript: "",
                nodes: []
            )
        )
        SceneAuthoringAssistant.applyUserRequestOverrides(
            to: &proposal,
            userRequest: "just add some sprites",
            document: doc,
            currentCardId: cardId
        )
        #expect(proposal.areaName == "playground")
        #expect(proposal.sceneName == "level1")
    }

    @Test("applyUserRequestOverrides respects user-mentioned scene alongside area")
    func overridesPickMentionedScene() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "bounder")
        var spec = SpriteAreaSpec(
            defaultSceneNamed: "main",
            fallbackSize: SizeSpec(width: 400, height: 300)
        )
        _ = spec.addScene(named: "bonus", basedOn: nil)
        area.setSpriteAreaSpec(spec)
        doc.addPart(area)

        var proposal = SceneCreateProposal(
            areaName: "",
            sceneName: "",
            createSpriteAreaIfMissing: false,
            summary: "",
            checklist: [],
            scene: SceneBlueprint(
                size: SizeSpec(width: 400, height: 300),
                backgroundColor: "#FFF",
                gravity: VectorSpec(dx: 0, dy: 0),
                scaleMode: .aspectFit,
                showsPhysics: false,
                showsFPS: false,
                showsNodeCount: false,
                sceneScript: "",
                nodes: []
            )
        )
        SceneAuthoringAssistant.applyUserRequestOverrides(
            to: &proposal,
            userRequest: "put sprites in the bonus scene of the bounder area",
            document: doc,
            currentCardId: cardId
        )
        #expect(proposal.areaName == "bounder")
        #expect(proposal.sceneName == "bonus")
    }

    @Test("real-world bug: triangle-with-physics response decodes via full fallback chain")
    func triangleBugRepro() throws {
        // The user asked for "red square, blue triangle, yellow circle, all
        // 100x100, with physics, bouncing". A model might emit this:
        //   * Prose intro before the JSON
        //   * JSON inside a ```json fence
        //   * shapeType "triangle" (not in SpriteShapeType)
        //   * Missing some showsX bool flags
        //   * The "triangle" node may mistakenly use nodeType "sprite"
        // Before this commit the strict decoder failed on any ONE of these.
        // Now the whole response decodes.
        let modelReply = """
        Sure! Here's a scene that bounces three shapes around a bounder area:

        ```json
        {
            "areaName": "bounder",
            "sceneName": "main",
            "createSpriteAreaIfMissing": false,
            "summary": "Three shapes bouncing inside the bounder sprite area.",
            "checklist": [
                { "key": "physics", "title": "Physics", "status": "done", "detail": "all three use dynamic bodies" }
            ],
            "scene": {
                "size": { "width": 640, "height": 480 },
                "backgroundColor": "#FFFFFF",
                "gravity": { "dx": 0, "dy": 0 },
                "scaleMode": "aspectFit",
                "nodes": [
                    {
                        "name": "red_square",
                        "nodeType": "shape",
                        "position": { "x": 120, "y": 120 },
                        "size": { "width": 100, "height": 100 },
                        "shapeType": "rect",
                        "fillColor": "#FF0000",
                        "physicsEnabled": true,
                        "physicsBodyType": "rect",
                        "dynamic": true,
                        "restitution": 0.95,
                        "velocity": { "dx": 180, "dy": 120 }
                    },
                    {
                        "name": "blue_triangle",
                        "nodeType": "sprite",
                        "position": { "x": 300, "y": 240 },
                        "size": { "width": 100, "height": 100 },
                        "shapeType": "triangle",
                        "fillColor": "#0055FF",
                        "physicsEnabled": true,
                        "dynamic": true,
                        "restitution": 0.9,
                        "velocity": { "dx": -140, "dy": 160 }
                    },
                    {
                        "name": "yellow_circle",
                        "nodeType": "shape",
                        "position": { "x": 480, "y": 360 },
                        "size": { "width": 100, "height": 100 },
                        "shapeType": "circle",
                        "fillColor": "#FFEE00",
                        "physicsEnabled": true,
                        "physicsBodyType": "circle",
                        "dynamic": true,
                        "restitution": 0.95,
                        "velocity": { "dx": 200, "dy": -140 }
                    }
                ]
            }
        }
        ```

        Let me know if you'd like a different color palette or different initial velocities.
        """
        let response = OllamaChatResponse(
            message: OllamaMessage(role: "assistant", content: modelReply),
            done: true
        )
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(
            SceneCreateProposal.self,
            from: response
        )
        #expect(decoded.areaName == "bounder")
        #expect(decoded.scene.nodes.count == 3)
        // The triangle was promoted to shape with a path shapeType.
        let triangle = decoded.scene.nodes[1]
        #expect(triangle.name == "blue_triangle")
        #expect(triangle.nodeType == .shape)
        #expect(triangle.shapeType == .path)
        // Red square kept its rect shape.
        #expect(decoded.scene.nodes[0].shapeType == .rect)
        // Yellow circle kept its circle shape.
        #expect(decoded.scene.nodes[2].shapeType == .circle)
        // Missing showsPhysics/FPS/NodeCount/sceneScript all defaulted to safe values.
        #expect(decoded.scene.showsPhysics == false)
        #expect(decoded.scene.sceneScript == "")
    }
}

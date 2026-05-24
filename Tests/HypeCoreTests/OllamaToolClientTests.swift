import Testing
import Foundation
@testable import HypeCore

/// Regression tests for OllamaToolCallFunction decoding.
///
/// Background: the original `arguments: [String: String]` typing caused
/// `JSONDecoder` to fail with `DecodingError.typeMismatch` ("The data
/// couldn't be read because it isn't in the correct format") whenever a
/// model returned a tool call with any non-string argument value. These
/// tests pin down the tolerant wire shapes we need to accept.
@Suite("OllamaToolCallFunction decoding")
struct OllamaToolCallFunctionDecodingTests {

    private func decode(_ json: String) throws -> OllamaToolCallFunction {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(OllamaToolCallFunction.self, from: data)
    }

    // MARK: - Happy path

    @Test("decodes the classic all-string arguments shape")
    func allStringArguments() throws {
        let json = """
        {
            "name": "create_button",
            "arguments": {
                "name": "OK",
                "left": "100",
                "top": "50",
                "width": "120",
                "height": "40"
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.name == "create_button")
        #expect(fn.arguments["name"] == "OK")
        #expect(fn.arguments["left"] == "100")
        #expect(fn.arguments["top"] == "50")
        #expect(fn.arguments["width"] == "120")
        #expect(fn.arguments["height"] == "40")
    }

    @Test("decodes an arguments map with no entries")
    func emptyArgumentsObject() throws {
        let json = """
        { "name": "get_stack_info", "arguments": {} }
        """
        let fn = try decode(json)
        #expect(fn.name == "get_stack_info")
        #expect(fn.arguments.isEmpty)
    }

    @Test("decodes with no arguments key at all")
    func missingArgumentsKey() throws {
        let json = """
        { "name": "get_stack_info" }
        """
        let fn = try decode(json)
        #expect(fn.name == "get_stack_info")
        #expect(fn.arguments.isEmpty)
    }

    @Test("decodes with an explicit null arguments value")
    func nullArgumentsValue() throws {
        let json = """
        { "name": "get_stack_info", "arguments": null }
        """
        let fn = try decode(json)
        #expect(fn.name == "get_stack_info")
        #expect(fn.arguments.isEmpty)
    }

    // MARK: - The original bug: mixed-type argument values

    @Test("decodes integer coordinates into integer strings (no .0 suffix)")
    func integerCoordinates() throws {
        // This is the shape Ollama actually emits for tools whose schema
        // declares string params but whose downstream intent is numeric.
        // Before the fix, this failed with DecodingError.typeMismatch.
        let json = """
        {
            "name": "add_sprite_to_scene",
            "arguments": {
                "sprite_area_name": "game_area",
                "sprite_name": "player",
                "x": 400,
                "y": 300,
                "width": 20,
                "height": 20
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.name == "add_sprite_to_scene")
        #expect(fn.arguments["sprite_area_name"] == "game_area")
        #expect(fn.arguments["sprite_name"] == "player")
        #expect(fn.arguments["x"] == "400")
        #expect(fn.arguments["y"] == "300")
        #expect(fn.arguments["width"] == "20")
        #expect(fn.arguments["height"] == "20")
        // And the downstream executor pattern — Double(arguments["x"] ?? "0")
        // — should still work on the stringified form.
        #expect(Double(fn.arguments["x"] ?? "0") == 400)
    }

    @Test("decodes fractional doubles losslessly")
    func fractionalDoubleArguments() throws {
        let json = """
        {
            "name": "set_part_property",
            "arguments": {
                "part_name": "Hero",
                "property": "alpha",
                "value": 0.75
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.arguments["value"] == "0.75")
    }

    @Test("decodes boolean flags into 'true'/'false' strings")
    func booleanArguments() throws {
        let json = """
        {
            "name": "create_button",
            "arguments": {
                "name": "Shared",
                "left": "10",
                "top": "10",
                "width": "100",
                "height": "30",
                "on_background": true
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.arguments["on_background"] == "true")
    }

    @Test("decodes nested objects as compact JSON strings")
    func nestedObjectArgument() throws {
        // This is exactly the catch-the-dot game failure mode: the model
        // decides to emit `diff_json` as a nested JSON object instead of
        // a JSON-encoded string. Our decoder should flatten the object
        // into a JSON string so `apply_scene_diff` can re-parse it.
        let json = """
        {
            "name": "apply_scene_diff",
            "arguments": {
                "sprite_area_name": "game_area",
                "diff_json": {
                    "sceneUpdates": { "backgroundColor": "#000000" },
                    "addNodes": []
                }
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.arguments["sprite_area_name"] == "game_area")
        let diffStr = fn.arguments["diff_json"] ?? ""
        // Should be valid JSON we can re-parse.
        let reparsed = try JSONSerialization.jsonObject(
            with: diffStr.data(using: .utf8)!
        ) as? [String: Any]
        #expect(reparsed != nil)
        // With sortedKeys encoding, addNodes comes before sceneUpdates.
        #expect((reparsed?["sceneUpdates"] as? [String: Any])?["backgroundColor"] as? String == "#000000")
        // And it should actually round-trip through SceneDiff's own decoder.
        let diff = try JSONDecoder().decode(
            SceneDiff.self,
            from: diffStr.data(using: .utf8)!
        )
        #expect(diff.sceneUpdates?.backgroundColor == "#000000")
    }

    @Test("decodes nested arrays as compact JSON strings")
    func nestedArrayArgument() throws {
        let json = """
        {
            "name": "create_chart",
            "arguments": {
                "name": "Sales",
                "chart_type": "bar",
                "left": "20",
                "top": "20",
                "width": "400",
                "height": "300",
                "data_json": [
                    { "name": "Jan", "value": 120 },
                    { "name": "Feb", "value": 150 }
                ]
            }
        }
        """
        let fn = try decode(json)
        let raw = fn.arguments["data_json"] ?? ""
        // Should parse as a JSON array.
        let reparsed = try JSONSerialization.jsonObject(
            with: raw.data(using: .utf8)!
        ) as? [[String: Any]]
        #expect(reparsed?.count == 2)
        #expect(reparsed?[0]["name"] as? String == "Jan")
    }

    @Test("decodes arguments when a model incorrectly wraps them under properties")
    func argumentsWrappedUnderPropertiesKey() throws {
        let json = """
        {
            "name": "get_stack_property",
            "arguments": {
                "properties": {
                    "property": "width"
                }
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.name == "get_stack_property")
        #expect(fn.arguments["property"] == "width")
        #expect(fn.arguments["properties"] == nil)
    }

    @Test("decodes arguments when each field is incorrectly wrapped under value")
    func argumentsWrappedUnderValuePerField() throws {
        let json = """
        {
            "name": "set_part_property",
            "arguments": {
                "part_name": { "value": "play" },
                "property": { "value": "text" },
                "value": { "value": "Start Game" }
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.arguments["part_name"] == "play")
        #expect(fn.arguments["property"] == "text")
        #expect(fn.arguments["value"] == "Start Game")
    }

    @Test("decodes integer values with a literal decimal (100.0 → '100')")
    func wholeNumberDoubleBecomesInteger() throws {
        let json = """
        {
            "name": "add_sprite_to_scene",
            "arguments": {
                "sprite_area_name": "game_area",
                "sprite_name": "dot",
                "x": 100.0,
                "y": 200.0
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.arguments["x"] == "100")
        #expect(fn.arguments["y"] == "200")
    }

    @Test("decodes null values as empty strings")
    func nullValueBecomesEmptyString() throws {
        let json = """
        {
            "name": "create_shape",
            "arguments": {
                "name": "Box",
                "shape_type": "rectangle",
                "left": "0",
                "top": "0",
                "width": "10",
                "height": "10",
                "fill_color": null
            }
        }
        """
        let fn = try decode(json)
        #expect(fn.arguments["fill_color"] == "")
    }

    // MARK: - OpenAI-compatible "arguments is a JSON-encoded string" shape

    @Test("decodes arguments when the whole map is a JSON-encoded string")
    func argumentsAsEncodedJSONString() throws {
        // Some OpenAI-compatible servers wrap the arguments object as a JSON
        // string rather than an inline object. Our decoder should re-parse
        // the inner payload and project it into [String: String].
        let inner = #"{"name":"OK","left":100,"top":50,"width":120,"height":40,"on_background":true}"#
        let json = """
        {
            "name": "create_button",
            "arguments": \(escapedJSONString(inner))
        }
        """
        let fn = try decode(json)
        #expect(fn.name == "create_button")
        #expect(fn.arguments["name"] == "OK")
        #expect(fn.arguments["left"] == "100")
        #expect(fn.arguments["top"] == "50")
        #expect(fn.arguments["width"] == "120")
        #expect(fn.arguments["height"] == "40")
        #expect(fn.arguments["on_background"] == "true")
    }

    @Test("garbage string arguments do not crash — empty dict fallback")
    func garbageStringArguments() throws {
        let json = """
        { "name": "noop", "arguments": "this is not json" }
        """
        let fn = try decode(json)
        #expect(fn.name == "noop")
        #expect(fn.arguments.isEmpty)
    }

    // MARK: - Round-trip through OllamaChatResponse (full envelope)

    @Test("full OllamaChatResponse with mixed-type tool call arguments decodes")
    func fullChatResponseRoundTrip() throws {
        // This is the exact failure path from the bug report — a chat
        // response containing a tool call with numeric arguments. Before
        // the fix, JSONDecoder.decode(OllamaChatResponse.self, ...) threw
        // with "The data couldn't be read because it isn't in the correct
        // format".
        let json = """
        {
            "done": false,
            "message": {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {
                        "function": {
                            "name": "add_sprite_to_scene",
                            "arguments": {
                                "sprite_area_name": "game_area",
                                "sprite_name": "player",
                                "x": 400,
                                "y": 300,
                                "width": 20,
                                "height": 20
                            }
                        }
                    },
                    {
                        "function": {
                            "name": "apply_scene_diff",
                            "arguments": {
                                "sprite_area_name": "game_area",
                                "diff_json": {
                                    "sceneUpdates": { "backgroundColor": "#000000" }
                                }
                            }
                        }
                    }
                ]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        #expect(response.done == false)
        let calls = response.message.tool_calls ?? []
        #expect(calls.count == 2)

        let first = calls[0].function
        #expect(first.name == "add_sprite_to_scene")
        #expect(first.arguments["x"] == "400")
        #expect(first.arguments["y"] == "300")

        let second = calls[1].function
        #expect(second.name == "apply_scene_diff")
        // The nested diff should round-trip as JSON that SceneDiff can decode.
        let diffStr = second.arguments["diff_json"] ?? ""
        let diff = try JSONDecoder().decode(
            SceneDiff.self,
            from: diffStr.data(using: .utf8)!
        )
        #expect(diff.sceneUpdates?.backgroundColor == "#000000")
    }

    @Test("full OllamaChatResponse decodes adapter-style top-level tool calls")
    func fullChatResponseWithTopLevelToolCalls() throws {
        let json = """
        {
            "message": {
                "content": "",
                "tool_calls": [
                    {
                        "id": "call_1",
                        "name": "set_card_property",
                        "arguments": {
                            "property": "name",
                            "value": "Home"
                        }
                    }
                ]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        #expect(response.done)
        #expect(response.message.role == "assistant")

        let call = try #require(response.message.tool_calls?.first)
        #expect(call.id == "call_1")
        #expect(call.function.name == "set_card_property")
        #expect(call.function.arguments["property"] == "name")
        #expect(call.function.arguments["value"] == "Home")
    }

    @Test("full OllamaChatResponse decodes OpenAI-compatible choices envelope")
    func fullChatResponseWithOpenAICompatibleChoices() throws {
        let json = """
        {
            "choices": [
                {
                    "finish_reason": "tool_calls",
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "",
                        "tool_calls": [
                            {
                                "type": "function",
                                "function": {
                                    "name": "set_card_property",
                                    "arguments": "{\\"property\\":\\"name\\",\\"value\\":\\"Home\\"}"
                                },
                                "id": "qwum4rAKt0MekZsk5ZjX441v6MfSWlKy"
                            }
                        ]
                    }
                }
            ],
            "created": 1779580969,
            "model": "qwen3-coder-next-iq4xs",
            "object": "chat.completion"
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        #expect(response.done)
        #expect(response.message.role == "assistant")

        let call = try #require(response.message.tool_calls?.first)
        #expect(call.id == "qwum4rAKt0MekZsk5ZjX441v6MfSWlKy")
        #expect(call.function.name == "set_card_property")
        #expect(call.function.arguments["property"] == "name")
        #expect(call.function.arguments["value"] == "Home")
    }

    @Test("full OllamaChatResponse preserves OpenAI-compatible reasoning content")
    func fullChatResponseWithReasoningContent() throws {
        let json = """
        {
            "choices": [
                {
                    "finish_reason": "tool_calls",
                    "message": {
                        "role": "assistant",
                        "reasoning_content": "I should rename the current card before summarizing.",
                        "content": "",
                        "tool_calls": [
                            {
                                "type": "function",
                                "function": {
                                    "name": "set_card_property",
                                    "arguments": "{\\"property\\":\\"name\\",\\"value\\":\\"Home\\"}"
                                }
                            }
                        ]
                    }
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        #expect(response.message.thinking == "I should rename the current card before summarizing.")
        #expect(response.message.content == nil)
        #expect(response.message.tool_calls?.first?.function.name == "set_card_property")
    }

    @Test("OllamaMessage extracts literal think blocks from content")
    func messageExtractsThinkBlocksFromContent() throws {
        let json = """
        {
            "role": "assistant",
            "content": "<think>Plan the tool call first.</think>Done."
        }
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(OllamaMessage.self, from: data)
        #expect(message.thinking == "Plan the tool call first.")
        #expect(message.content == "Done.")
    }

    @Test("full OllamaChatResponse decodes null function name without failing the whole turn")
    func fullChatResponseWithNullToolName() throws {
        let json = """
        {
            "done": true,
            "message": {
                "role": null,
                "content": null,
                "tool_calls": [
                    {
                        "function": {
                            "name": null,
                            "arguments": null
                        }
                    }
                ]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        #expect(response.message.role == "assistant")
        let call = try #require(response.message.tool_calls?.first)
        #expect(call.function.name == "")
        #expect(call.function.arguments.isEmpty)
    }

    @Test("assistant tool call history encodes OpenAI-compatible type")
    func assistantToolCallHistoryEncodesType() throws {
        let message = OllamaMessage(
            role: "assistant",
            content: "",
            tool_calls: [
                OllamaToolCall(
                    id: "uw4slDEcUyIOIQXqxfyTDNFtiCehiUuq",
                    function: OllamaToolCallFunction(
                        name: "create_sprite_area",
                        arguments: [
                            "left": "0",
                            "height": "600",
                            "top": "0",
                            "name": "bouncerArea",
                            "width": "800",
                            "scene_name": "main"
                        ]
                    )
                )
            ]
        )

        let data = try JSONEncoder().encode(message)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let toolCalls = try #require(object["tool_calls"] as? [[String: Any]])
        let call = try #require(toolCalls.first)

        #expect(call["type"] as? String == "function")
        #expect(call["id"] as? String == "uw4slDEcUyIOIQXqxfyTDNFtiCehiUuq")
        let function = try #require(call["function"] as? [String: Any])
        #expect(function["name"] as? String == "create_sprite_area")
    }

    // MARK: - Helpers

    /// JSON-encode a raw string so it can be embedded as the value of a
    /// JSON field. Avoids hand-escaping and matches what a real server
    /// would emit on the wire.
    private func escapedJSONString(_ s: String) -> String {
        let data = try! JSONSerialization.data(
            withJSONObject: [s],
            options: [.fragmentsAllowed]
        )
        let arrayString = String(data: data, encoding: .utf8)!
        // arrayString looks like `["..."]`; strip the outer brackets.
        return String(arrayString.dropFirst().dropLast())
    }
}

@Suite("Ollama format request body")
struct OllamaFormatRequestBodyTests {

    @Test("request body includes schema-driven format")
    func requestBodyIncludesSchemaFormat() throws {
        let messages = [OllamaMessage(role: "user", content: "plan a scene")]
        let schema = OllamaJSONSchema(object: [
            "type": "object",
            "properties": [
                "summary": ["type": "string"]
            ],
            "required": ["summary"]
        ])

        let body = try OllamaToolClient.requestBodyObject(
            model: "llama3.2",
            messages: messages,
            tools: [],
            format: .schema(schema)
        )

        let format = body["format"] as? [String: Any]
        #expect(format?["type"] as? String == "object")
        let properties = format?["properties"] as? [String: Any]
        let summary = properties?["summary"] as? [String: Any]
        #expect(summary?["type"] as? String == "string")
    }

    @Test("request body includes json shorthand format")
    func requestBodyIncludesJSONFormat() throws {
        let body = try OllamaToolClient.requestBodyObject(
            model: "llama3.2",
            messages: [OllamaMessage(role: "user", content: "hello")],
            tools: [],
            format: .json
        )

        #expect(body["format"] as? String == "json")
    }
}

/// Regression tests for the request-timeout policy.
///
/// Background: with a 120s idle timeout and Ollama's non-streaming
/// `/api/chat` response (the server buffers every generated token
/// and sends them as one blob when done), any structured
/// generation that ran longer than two minutes killed the socket
/// with NSURLErrorTimedOut. The Scene Authoring flow hit this
/// routinely on cold-start or with 14B+ models. We now default to
/// 10-minute request + resource timeouts for structured chat and
/// surface a richly-formatted `OllamaError.requestTimedOut` so
/// callers can show something actionable instead of the bare
/// "The request timed out."
@Suite("Ollama timeout policy")
struct OllamaTimeoutPolicyTests {

    @Test("structured timeouts default to 600s request + resource")
    func structuredDefault() {
        let timeouts = OllamaToolClient.Timeouts.structured
        #expect(timeouts.request == 600)
        #expect(timeouts.resource == 600)
    }

    @Test("quick timeouts stay short for availableModels listings")
    func quickDefault() {
        let timeouts = OllamaToolClient.Timeouts.quick
        #expect(timeouts.request == 30)
        #expect(timeouts.resource == 60)
    }

    @Test("chat timeouts sit between quick and structured")
    func chatDefault() {
        let timeouts = OllamaToolClient.Timeouts.chat
        #expect(timeouts.request == 300)
        #expect(timeouts.resource == 300)
    }

    @Test("Timeouts is constructible with custom request/resource values")
    func customTimeouts() {
        let t = OllamaToolClient.Timeouts(request: 45, resource: 90)
        #expect(t.request == 45)
        #expect(t.resource == 90)
    }

    @Test("OllamaError.requestTimedOut localized description names model, endpoint, and seconds")
    func timeoutErrorDescriptionIsActionable() {
        let err = OllamaError.requestTimedOut(
            endpoint: "/api/chat",
            model: "qwen2.5:14b",
            seconds: 600
        )
        let msg = err.errorDescription ?? ""
        #expect(msg.contains("/api/chat"))
        #expect(msg.contains("qwen2.5:14b"))
        #expect(msg.contains("600s"))
        // The remedies section names concrete steps.
        #expect(msg.contains("cold start") || msg.contains("smaller model"))
    }

    @Test("OllamaToolClient initializer accepts custom Timeouts without throwing")
    func clientInitializesWithTimeouts() {
        // The actor init runs the URLSessionConfiguration path — smoke
        // test that a caller-provided timeouts value flows through.
        let client = OllamaToolClient(
            host: "localhost",
            port: "11434",
            model: "llama3.2",
            timeouts: OllamaToolClient.Timeouts(request: 30, resource: 30)
        )
        let base = client.baseURL
        #expect(base == "http://localhost:11434")
    }
}

/// Regression tests for the format-unsupported-model fallback.
///
/// Background: some Ollama models (Gemma family, older fine-tunes)
/// ship without the tokenizer metadata needed for server-side
/// grammar-constrained decoding. Sending a `format` schema to one
/// of those models fails with HTTP 500 and a body containing
/// `failed to load model vocabulary required for format`. Instead
/// of surfacing that to the user as a dead-end, we now:
///   1. detect that specific error
///   2. retry without the `format` field
///   3. embed the JSON schema in a synthetic system prompt
///   4. feed the free-form response through the existing tolerant
///      decoder cascade (markdown fences, prose extraction, etc.)
///
/// These tests pin the detection predicate and schema-embedding
/// logic so the path can't regress silently.
@Suite("Ollama format-unsupported fallback")
struct OllamaFormatUnsupportedFallbackTests {

    @Test("isFormatUnsupportedError matches the canonical Ollama message")
    func detectsCanonicalMessage() {
        let err = OllamaError.requestFailed(
            #"{"error":"failed to load model vocabulary required for format"}"#
        )
        #expect(OllamaToolClient.isFormatUnsupportedError(err))
    }

    @Test("isFormatUnsupportedError matches a close variant phrasing")
    func detectsVariantPhrasing() {
        // Future Ollama wording tweaks shouldn't silently break the
        // fallback — we match on a few known substrings.
        let err = OllamaError.requestFailed("format is not supported by this model")
        #expect(OllamaToolClient.isFormatUnsupportedError(err))
    }

    @Test("isFormatUnsupportedError ignores unrelated request failures")
    func ignoresUnrelatedErrors() {
        let err = OllamaError.requestFailed("connection refused")
        #expect(!OllamaToolClient.isFormatUnsupportedError(err))
    }

    @Test("isFormatUnsupportedError ignores timeout errors")
    func ignoresTimeoutErrors() {
        let err = OllamaError.requestTimedOut(
            endpoint: "/api/chat",
            model: "gemma4:26b",
            seconds: 600
        )
        #expect(!OllamaToolClient.isFormatUnsupportedError(err))
    }

    @Test("renderSchemaPrompt describes a schema object as pretty JSON with instructions")
    func renderSchemaPromptIncludesSchema() {
        let schema = OllamaJSONSchema(object: [
            "type": "object",
            "properties": [
                "summary": ["type": "string"]
            ],
            "required": ["summary"]
        ])
        let rendered = OllamaToolClient.renderSchemaPrompt(.schema(schema))
        #expect(rendered.contains("summary"))
        #expect(rendered.contains("schema"))
        // The rendered prompt must tell the model not to wrap the
        // response in markdown fences — that's a real failure mode
        // for models without server-side format enforcement.
        #expect(rendered.lowercased().contains("code fence")
                || rendered.lowercased().contains("markdown"))
    }

    @Test("renderSchemaPrompt handles .json shorthand with a generic instruction")
    func renderSchemaPromptJSONShorthand() {
        let rendered = OllamaToolClient.renderSchemaPrompt(.json)
        #expect(rendered.contains("JSON"))
        #expect(rendered.lowercased().contains("markdown") ||
                rendered.lowercased().contains("code fence") ||
                rendered.lowercased().contains("prose"))
    }

    @Test("messagesWithSchemaPrompt merges schema text into an existing system message")
    func schemaMergesIntoExistingSystem() {
        let original = [
            OllamaMessage(role: "system", content: "You are a scene planner.", tool_calls: nil),
            OllamaMessage(role: "user", content: "Plan a scene", tool_calls: nil)
        ]
        let schema = OllamaJSONSchema(object: [
            "type": "object",
            "properties": ["summary": ["type": "string"]]
        ])
        let retry = OllamaToolClient.messagesWithSchemaPrompt(
            original: original,
            format: .schema(schema)
        )
        #expect(retry.count == 2)
        #expect(retry[0].role == "system")
        // System prompt starts with the original content...
        #expect(retry[0].content?.hasPrefix("You are a scene planner.") == true)
        // ...and now also contains the schema text.
        #expect(retry[0].content?.contains("summary") == true)
        // User message is untouched.
        #expect(retry[1].role == "user")
        #expect(retry[1].content == "Plan a scene")
    }

    @Test("messagesWithSchemaPrompt prepends a fresh system message when none exists")
    func schemaPrependsWhenNoSystem() {
        let original = [
            OllamaMessage(role: "user", content: "Plan a scene", tool_calls: nil)
        ]
        let schema = OllamaJSONSchema(object: [
            "type": "object",
            "properties": ["summary": ["type": "string"]]
        ])
        let retry = OllamaToolClient.messagesWithSchemaPrompt(
            original: original,
            format: .schema(schema)
        )
        #expect(retry.count == 2)
        #expect(retry[0].role == "system")
        #expect(retry[0].content?.contains("summary") == true)
        #expect(retry[1].role == "user")
    }
}

@Suite("OllamaToolClient native API smoke", .serialized)
struct OllamaToolClientNativeAPITests {
    @Test("model query, pull, and tool chat use native Ollama endpoints")
    func modelQueryPullAndToolChatUseNativeEndpoints() async throws {
        defer { MockURLProtocolOllamaToolNative.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOllamaToolNative.self]
        let session = URLSession(configuration: config)
        var observedPaths: [String] = []

        MockURLProtocolOllamaToolNative.requestHandler = { request in
            let path = request.url?.path ?? ""
            observedPaths.append(path)

            switch path {
            case "/api/tags":
                let payload = """
                { "models": [ { "name": "existing-model" } ] }
                """
                return (Self.response(for: request), Data(payload.utf8))
            case "/api/pull":
                let body = try #require(Self.bodyData(from: request))
                let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(object["name"] as? String == "missing-model")
                #expect(object["stream"] as? Bool == false)
                return (Self.response(for: request), Data(#"{ "status": "success" }"#.utf8))
            case "/api/chat":
                let body = try #require(Self.bodyData(from: request))
                let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(object["model"] as? String == "missing-model")
                #expect(object["stream"] as? Bool == false)
                let tools = try #require(object["tools"] as? [[String: Any]])
                let function = try #require(tools.first?["function"] as? [String: Any])
                #expect(function["name"] as? String == "report_status")
                let payload = """
                {
                  "message": {
                    "role": "assistant",
                    "content": "",
                    "tool_calls": [
                      {
                        "function": {
                          "name": "report_status",
                          "arguments": { "status": "OK" }
                        }
                      }
                    ]
                  },
                  "done": true
                }
                """
                return (Self.response(for: request), Data(payload.utf8))
            default:
                Issue.record("unexpected path: \(path)")
                return (Self.response(for: request, status: 404), Data())
            }
        }

        let client = OllamaToolClient(
            host: "localhost",
            port: "11434",
            model: "missing-model",
            session: session,
            logger: HypeLogger(setupFileLogging: false)
        )
        let models = try await client.availableModels()
        let pullStatus = try await client.pullModel()
        let response = try await client.chat(
            messages: [OllamaMessage(role: "user", content: "Call report_status")],
            tools: [Self.reportStatusTool]
        )

        #expect(models == ["existing-model"])
        #expect(pullStatus == "success")
        #expect(response.message.tool_calls?.first?.function.name == "report_status")
        #expect(response.message.tool_calls?.first?.function.arguments["status"] == "OK")
        #expect(observedPaths == ["/api/tags", "/api/pull", "/api/chat"])
    }

    private static var reportStatusTool: OllamaTool {
        OllamaTool(
            type: "function",
            function: OllamaFunction(
                name: "report_status",
                description: "Report status.",
                parameters: OllamaParameters(
                    type: "object",
                    properties: [
                        "status": OllamaProperty(type: "string", description: "Status")
                    ],
                    required: ["status"]
                )
            )
        )
    }

    private static func response(for request: URLRequest, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}

@Suite("OllamaToolClient console logging", .serialized)
struct OllamaToolClientConsoleLoggingTests {

    @Test("chat logs request messages and response tool calls")
    func chatLogsRequestAndResponse() async throws {
        // Test-local logger so parallel sibling tests writing to
        // `HypeLogger.shared` cannot pollute or wipe the entries
        // we're about to assert on. The injected logger does not
        // open the on-disk log file, keeping the test purely
        // in-memory.
        let testLogger = HypeLogger(setupFileLogging: false)
        defer { MockURLProtocolOllamaToolLogging.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOllamaToolLogging.self]
        let session = URLSession(configuration: config)

        MockURLProtocolOllamaToolLogging.requestHandler = { request in
            #expect(request.url?.path == "/api/chat")

            let payload = """
            {
              "message": {
                "role": "assistant",
                "content": "I'll update the card.",
                "tool_calls": [
                  {
                    "function": {
                      "name": "set_card_property",
                      "arguments": {
                        "property": "name",
                        "value": "Home"
                      }
                    }
                  }
                ]
              },
              "done": true
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }

        let client = OllamaToolClient(
            host: "localhost",
            port: "11434",
            model: "test-model",
            session: session,
            logger: testLogger
        )
        let tool = OllamaTool(
            type: "function",
            function: OllamaFunction(
                name: "set_card_property",
                description: "Set a card property",
                parameters: OllamaParameters(
                    type: "object",
                    properties: [
                        "property": OllamaProperty(type: "string", description: "Property name"),
                        "value": OllamaProperty(type: "string", description: "Property value"),
                    ],
                    required: ["property", "value"]
                )
            )
        )

        _ = try await client.chat(
            messages: [
                OllamaMessage(role: "system", content: "You are Hype."),
                OllamaMessage(role: "user", content: "Create a button"),
            ],
            tools: [tool]
        )

        let entries = testLogger.entries
        #expect(entries.contains { $0.source == "Ollama" && $0.message.contains("POST /api/chat") && $0.message.contains("Create a button") })
        #expect(entries.contains { $0.source == "Ollama" && $0.message.contains("I'll update the card.") && $0.message.contains("set_card_property") })
    }
}

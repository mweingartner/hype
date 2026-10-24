import Foundation
import Testing
@testable import HypeCore

@Suite("OpenAI Responses client", .serialized)
struct OpenAIResponsesClientTests {
    @Test("model discovery fetches fresh authenticated text models and excludes other modalities")
    func discoversLiveTextModels() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIResponses.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocolOpenAIResponses.requestHandler = nil }
        MockURLProtocolOpenAIResponses.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer catalog-token")
            #expect(request.timeoutInterval == 30)
            let ids = [
                "gpt-9-new", "gpt-4.1-mini", "o3", "o4-mini", "gpt-9-new", " gpt-5-mini ",
                "ft:gpt-4.1:example:custom:123", "gpt-image-1", "gpt-4o-audio-preview",
                "gpt-4o-realtime-preview", "gpt-4o-mini-transcribe", "gpt-4o-mini-tts",
                "gpt-4o-search-preview", "text-embedding-3-large", "whisper-1", "dall-e-3",
                "gpt-3.5-turbo-instruct", "gpt-4-turbo", "o1-preview", "o1-mini", "o3-deep-research", ""
            ]
            let data = try JSONSerialization.data(withJSONObject: ["data": ids.map { ["id": $0] }])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = OpenAIResponsesClient(apiKey: " catalog-token \n", session: session)
        #expect(try await client.availableModels() == [
            "ft:gpt-4.1:example:custom:123", "gpt-4.1-mini", "gpt-5-mini", "gpt-9-new", "o3", "o4-mini"
        ])

        // A second request must consult the server rather than reuse a bundled/cached list.
        MockURLProtocolOpenAIResponses.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"data":[{"id":"gpt-9-newer"}]}"#.utf8))
        }
        #expect(try await client.availableModels() == ["gpt-9-newer"])
    }

    @Test("one live catalog refresh separates current image models and text models")
    func discoversImageAndTextCatalogTogether() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIResponses.self]
        defer { MockURLProtocolOpenAIResponses.requestHandler = nil }
        MockURLProtocolOpenAIResponses.requestHandler = { request in
            #expect(request.url?.path == "/v1/models")
            let ids = [
                "gpt-image-2.5-sunburst", "gpt-image-2.5-sunburst-2026-09-08",
                "gpt-image-2.5-flare", "gpt-image-2.5-flare-2026-09-08",
                "gpt-image-2", "gpt-image-2-2026-04-21", "gpt-image-1.5",
                "gpt-image-1-mini", "chatgpt-image-latest", "gpt-image-9-future",
                "gpt-image-2", "gpt-image-1", "dall-e-2", "dall-e-3", "gpt-9-new",
                "text-embedding-3-large", "gpt-4o-audio-preview"
            ]
            var entries = ids.map { ["id": $0] }
            entries.append(["id": "gpt-image-expired", "shutdown_date": "2000-01-01"])
            entries.append(["id": "gpt-9-expired", "shutdown_date": "2000-01-01"])
            entries.append(["id": "gpt-9-active", "shutdown_date": "2999-01-01"])
            let data = try JSONSerialization.data(withJSONObject: ["data": entries])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = OpenAIResponsesClient(apiKey: "token", session: URLSession(configuration: config))
        let catalog = try await client.availableModelCatalog()
        #expect(catalog.textModels == ["gpt-9-active", "gpt-9-new"])
        #expect(catalog.imageModels == [
            "chatgpt-image-latest", "gpt-image-1-mini", "gpt-image-1.5",
            "gpt-image-2", "gpt-image-2-2026-04-21", "gpt-image-2.5-flare",
            "gpt-image-2.5-flare-2026-09-08", "gpt-image-2.5-sunburst",
            "gpt-image-2.5-sunburst-2026-09-08", "gpt-image-9-future"
        ])
        #expect(Set(HypeAIConfiguration.openAIImageModels) == Set(catalog.imageModels.filter { $0 != "gpt-image-9-future" }))
    }

    @Test("model discovery rejects missing keys before sending a request")
    func modelDiscoveryRequiresKey() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIResponses.self]
        defer { MockURLProtocolOpenAIResponses.requestHandler = nil }
        MockURLProtocolOpenAIResponses.requestHandler = { _ in
            Issue.record("A blank API key must never cause a network request")
            throw URLError(.badServerResponse)
        }
        let client = OpenAIResponsesClient(apiKey: " \n", session: URLSession(configuration: config))
        do {
            _ = try await client.availableModels()
            Issue.record("Expected missing key error")
        } catch {
            guard case OpenAIClientError.noAPIKey = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("model discovery rejects HTTP errors without leaking server payloads", arguments: [401, 403, 429, 500])
    func modelDiscoveryRejectsHTTPErrors(statusCode: Int) async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIResponses.self]
        defer { MockURLProtocolOpenAIResponses.requestHandler = nil }
        MockURLProtocolOpenAIResponses.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":{"message":"private-provider-payload"}}"#.utf8))
        }
        let client = OpenAIResponsesClient(apiKey: "token", session: URLSession(configuration: config))
        do {
            _ = try await client.availableModels()
            Issue.record("Expected HTTP failure")
        } catch {
            #expect(error.localizedDescription == "OpenAI error: Model list request failed (HTTP \(statusCode)).")
        }
    }

    @Test("model discovery rejects malformed payloads instead of returning fallback models")
    func modelDiscoveryRejectsMalformedData() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIResponses.self]
        defer { MockURLProtocolOpenAIResponses.requestHandler = nil }
        MockURLProtocolOpenAIResponses.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"data":[{"name":"gpt-9-new"}]}"#.utf8))
        }
        let client = OpenAIResponsesClient(apiKey: "token", session: URLSession(configuration: config))
        await #expect(throws: DecodingError.self) { try await client.availableModels() }
    }

    @Test("model discovery returns an empty catalog when only non-text models are available")
    func modelDiscoveryHandlesEmptyTextCatalog() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIResponses.self]
        defer { MockURLProtocolOpenAIResponses.requestHandler = nil }
        MockURLProtocolOpenAIResponses.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"data":[{"id":"text-embedding-3-small"}]}"#.utf8))
        }
        let client = OpenAIResponsesClient(apiKey: "token", session: URLSession(configuration: config))
        #expect(try await client.availableModels() == [])
    }

    @Test("model discovery maps network timeouts to its bounded request timeout")
    func modelDiscoveryTimeout() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIResponses.self]
        defer { MockURLProtocolOpenAIResponses.requestHandler = nil }
        MockURLProtocolOpenAIResponses.requestHandler = { _ in throw URLError(.timedOut) }
        let client = OpenAIResponsesClient(apiKey: "token", session: URLSession(configuration: config))
        do {
            _ = try await client.availableModels()
            Issue.record("Expected timeout")
        } catch {
            guard case OpenAIClientError.requestTimedOut(let endpoint, _, let seconds) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(endpoint == "/v1/models")
            #expect(seconds == 30)
        }
    }

    @Test("request body maps Hype tools and tool outputs to Responses API shape")
    func requestBodyMapsToolsAndToolOutputs() throws {
        let tool = OllamaTool(
            type: "function",
            function: OllamaFunction(
                name: "set_part_property",
                description: "Set a part property.",
                parameters: OllamaParameters(
                    type: "object",
                    properties: [
                        "part_name": OllamaProperty(type: "string", description: "Part name"),
                        "property": OllamaProperty(type: "string", description: "Property"),
                        "value": OllamaProperty(type: "string", description: "Value")
                    ],
                    required: ["part_name", "property", "value"]
                )
            )
        )

        let body = try OpenAIResponsesClient.requestBodyObject(
            model: "gpt-5.2",
            messages: [
                OllamaMessage(role: "system", content: "System rules"),
                OllamaMessage(role: "user", content: "Rename the button"),
                OllamaMessage(
                    role: "assistant",
                    tool_calls: [
                        OllamaToolCall(
                            id: "call_test",
                            function: OllamaToolCallFunction(
                                name: "set_part_property",
                                arguments: [
                                    "part_name": "button 1",
                                    "property": "name",
                                    "value": "Start"
                                ]
                            )
                        )
                    ]
                ),
                OllamaMessage(role: "tool", content: "Updated button.")
            ],
            tools: [tool],
            format: nil
        )

        #expect(body["model"] as? String == "gpt-5.2")
        #expect((body["instructions"] as? String)?.contains("System rules") == true)

        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.contains { $0["type"] as? String == "function_call" && $0["call_id"] as? String == "call_test" })
        #expect(input.contains { $0["type"] as? String == "function_call_output" && $0["call_id"] as? String == "call_test" })

        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.first?["type"] as? String == "function")
        #expect(tools.first?["name"] as? String == "set_part_property")
    }

    @Test("decodeResponse preserves assistant text and function call arguments")
    func decodeResponsePreservesTextAndToolCalls() throws {
        let json = """
        {
          "output": [
            {
              "type": "message",
              "role": "assistant",
              "content": [
                { "type": "output_text", "text": "I will update it." }
              ]
            },
            {
              "type": "function_call",
              "call_id": "call_123",
              "name": "set_part_property",
              "arguments": "{\\"part_name\\":\\"button 1\\",\\"property\\":\\"width\\",\\"value\\":120}"
            }
          ]
        }
        """

        let response = try OpenAIResponsesClient.decodeResponse(Data(json.utf8))

        #expect(response.message.content == "I will update it.")
        let call = try #require(response.message.tool_calls?.first)
        #expect(call.id == "call_123")
        #expect(call.function.name == "set_part_property")
        #expect(call.function.arguments["part_name"] == "button 1")
        #expect(call.function.arguments["value"] == "120")
    }

    @Test("structured format becomes Responses json_schema text format")
    func structuredFormatUsesJSONSchemaTextFormat() throws {
        let schema = OllamaJSONSchema(object: [
            "type": "object",
            "properties": [
                "answer": [
                    "type": "string"
                ]
            ],
            "required": ["answer"]
        ])

        let body = try OpenAIResponsesClient.requestBodyObject(
            model: "gpt-5.2",
            messages: [OllamaMessage(role: "user", content: "answer")],
            tools: [],
            format: .schema(schema)
        )

        let text = try #require(body["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "hype_structured_response")
        #expect(format["strict"] as? Bool == false)
    }

    @Test("request body can enable Responses streaming and reasoning summaries")
    func requestBodyEnablesStreamingAndReasoning() throws {
        let body = try OpenAIResponsesClient.requestBodyObject(
            model: "gpt-5.2",
            messages: [OllamaMessage(role: "user", content: "Think carefully, then answer.")],
            tools: [],
            format: nil,
            stream: true,
            reasoning: .init(effort: "medium", summary: "auto")
        )

        #expect(body["stream"] as? Bool == true)
        let reasoning = try #require(body["reasoning"] as? [String: Any])
        #expect(reasoning["effort"] as? String == "medium")
        #expect(reasoning["summary"] as? String == "auto")
    }

    @Test("decodeResponse exposes reasoning summary as thinking")
    func decodeResponseExposesReasoningSummaryAsThinking() throws {
        let json = """
        {
          "output": [
            {
              "type": "reasoning",
              "summary": [
                { "type": "summary_text", "text": "Checked the request and selected a safe tool path." }
              ]
            },
            {
              "type": "message",
              "role": "assistant",
              "content": [
                { "type": "output_text", "text": "Done." }
              ]
            }
          ]
        }
        """

        let response = try OpenAIResponsesClient.decodeResponse(Data(json.utf8))

        #expect(response.message.content == "Done.")
        #expect(response.message.thinking == "Checked the request and selected a safe tool path.")
    }

    @Test("chatStream posts to Responses API with bearer auth, streaming, and reasoning")
    func chatStreamPostsResponsesRequestWithBearerAuthStreamingAndReasoning() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIResponses.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocolOpenAIResponses.requestHandler = nil }

        MockURLProtocolOpenAIResponses.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")

            let bodyData = try #require(Self.bodyData(from: request))
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["model"] as? String == "gpt-5.2")
            #expect(body["stream"] as? Bool == true)
            let reasoning = try #require(body["reasoning"] as? [String: Any])
            #expect(reasoning["effort"] as? String == "medium")
            #expect(reasoning["summary"] as? String == "auto")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let stream = """
            data: {"type":"response.created"}

            data: {"type":"response.output_text.delta","delta":"O"}

            data: {"type":"response.output_text.delta","delta":"K"}

            data: {"type":"response.completed"}

            """
            return (response, Data(stream.utf8))
        }

        let client = OpenAIResponsesClient(
            apiKey: "  openai-token \n",
            model: "gpt-5.2",
            session: session
        )

        var streamed = ""
        for await token in client.chatStream(messages: [OllamaMessage(role: "user", content: "Reply OK")], tools: []) {
            streamed += token
        }

        #expect(streamed == "OK")
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
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

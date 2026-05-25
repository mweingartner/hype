import Foundation
import Testing
@testable import HypeCore

@Suite("OpenAI Responses client", .serialized)
struct OpenAIResponsesClientTests {
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

import Foundation
import Testing
@testable import HypeCore

@Suite("OpenAI Responses client")
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
}

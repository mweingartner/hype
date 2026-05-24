import Foundation
import Testing
@testable import HypeCore

@Suite("OpenAI-compatible chat completions client", .serialized)
struct OpenAIChatCompletionsClientTests {
    @Test("Ollama configuration posts chat to v1 chat completions")
    func ollamaConfigurationUsesChatCompletionsEndpoint() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/v1/chat/completions")

            let bodyData = try #require(Self.bodyData(from: request))
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["model"] as? String == "qwen3-coder-next-iq4xs")
            #expect(body["keep_alive"] as? String == "30m")
            #expect(body["tool_choice"] as? String == "auto")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
              "choices": [
                {
                  "finish_reason": "tool_calls",
                  "message": {
                    "role": "assistant",
                    "content": "",
                    "tool_calls": [
                      {
                        "id": "call_1",
                        "type": "function",
                        "function": {
                          "name": "create_button",
                          "arguments": "{\\"name\\":\\"OK\\",\\"left\\":\\"10\\"}"
                        }
                      }
                    ]
                  }
                }
              ]
            }
            """
            return (response, Data(json.utf8))
        }

        let client = OpenAIChatCompletionsClient(
            configuration: .ollama(host: "localhost", port: "11434", model: "qwen3-coder-next-iq4xs"),
            session: session
        )

        let tool = OllamaTool(
            type: "function",
            function: OllamaFunction(
                name: "create_button",
                description: "Create a button.",
                parameters: OllamaParameters(
                    type: "object",
                    properties: [
                        "name": OllamaProperty(type: "string", description: "Button name")
                    ],
                    required: ["name"]
                )
            )
        )
        let result = try await client.chat(
            messages: [OllamaMessage(role: "user", content: "create a button")],
            tools: [tool]
        )

        let call = try #require(result.message.tool_calls?.first)
        #expect(call.id == "call_1")
        #expect(call.function.name == "create_button")
        #expect(call.function.arguments["name"] == "OK")
        #expect(call.function.arguments["left"] == "10")
    }

    @Test("selected Ollama provider creates chat completions client")
    func selectedOllamaProviderCreatesChatCompletionsClient() throws {
        let defaults = try #require(UserDefaults(suiteName: "OpenAIChatCompletionsClientTests.\(UUID().uuidString)"))
        defaults.set(HypeAIProvider.ollama.rawValue, forKey: HypeAIConfiguration.providerKey)
        defaults.set("qwen3-coder-next-iq4xs", forKey: "ollamaModel")

        let client = try HypeAIConfiguration.makeClient(defaults: defaults)

        #expect(client is OpenAIChatCompletionsClient)
        #expect(client.providerName == "ollama")
        #expect(client.modelName == "qwen3-coder-next-iq4xs")
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

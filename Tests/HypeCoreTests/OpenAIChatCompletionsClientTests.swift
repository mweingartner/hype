import Foundation
import Testing
@testable import HypeCore

@Suite("OpenAI-compatible chat completions client", .serialized)
struct OpenAIChatCompletionsClientTests {
    @Test("Ollama configuration posts chat to v1 chat completions")
    func ollamaConfigurationUsesChatCompletionsEndpoint() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIChatCompletions.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocolOpenAIChatCompletions.requestHandler = nil }

        MockURLProtocolOpenAIChatCompletions.requestHandler = { request in
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

    @Test("chat responses split literal think tags out of assistant content")
    func chatResponseSplitsLiteralThinkTags() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIChatCompletions.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocolOpenAIChatCompletions.requestHandler = nil }

        MockURLProtocolOpenAIChatCompletions.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = #"""
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "<think>Plan the field first.</think>Created the text box."
                  }
                }
              ]
            }
            """#
            return (response, Data(json.utf8))
        }

        let client = OpenAIChatCompletionsClient(
            configuration: .ollama(host: "localhost", port: "11434", model: "qwen3-coder-next-iq4xs"),
            session: session
        )

        let result = try await client.chat(
            messages: [OllamaMessage(role: "user", content: "create a text box")],
            tools: []
        )

        #expect(result.message.thinking == "Plan the field first.")
        #expect(result.message.content == "Created the text box.")
    }

    @Test("Z.ai model query uses configured OpenAI-compatible models endpoint")
    func zAIModelQueryUsesConfiguredModelsEndpoint() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIChatCompletions.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocolOpenAIChatCompletions.requestHandler = nil }

        MockURLProtocolOpenAIChatCompletions.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.z.ai/api/paas/v4/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer z-token")
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{ "data": [ { "id": "glm-5.1" }, { "id": "glm-4.5" } ] }"#.utf8))
        }

        let client = OpenAIChatCompletionsClient(
            configuration: .openAICompatible(
                baseURL: URL(string: "https://api.z.ai/api/paas/v4")!,
                apiKey: "z-token",
                model: "glm-5.1",
                providerName: HypeAIProvider.zAI.rawValue,
                chatCompletionsPath: "chat/completions",
                modelListPath: "models"
            ),
            session: session
        )

        #expect(try await client.availableModels() == ["glm-5.1", "glm-4.5"])
    }

    @Test("llama.cpp posts standard OpenAI-compatible chat without Ollama keep_alive")
    func llamaCppUsesStandardOpenAICompatibleChatEndpoint() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIChatCompletions.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocolOpenAIChatCompletions.requestHandler = nil }

        MockURLProtocolOpenAIChatCompletions.requestHandler = { request in
            #expect(request.url?.absoluteString == "http://localhost:8001/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let bodyData = try #require(Self.bodyData(from: request))
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["model"] as? String == "qwen2.5")
            #expect(body["stream"] as? Bool == false)
            #expect(body["keep_alive"] == nil)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = #"{ "choices": [ { "message": { "role": "assistant", "content": "OK" } } ] }"#
            return (response, Data(payload.utf8))
        }

        let client = OpenAIChatCompletionsClient(
            configuration: .openAICompatible(
                baseURL: URL(string: "http://localhost:8001")!,
                model: "qwen2.5",
                providerName: HypeAIProvider.llamaCpp.rawValue,
                modelListPath: "v1/models"
            ),
            session: session
        )

        let result = try await client.chat(messages: [OllamaMessage(role: "user", content: "Hello")], tools: [])
        #expect(result.message.content == "OK")
    }

    @Test("Z.ai chat uses paas chat completions path and required headers")
    func zAIChatUsesPaaSChatCompletionsPathAndHeaders() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIChatCompletions.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocolOpenAIChatCompletions.requestHandler = nil }

        MockURLProtocolOpenAIChatCompletions.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.z.ai/api/paas/v4/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer z-token")
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en")
            let bodyData = try #require(Self.bodyData(from: request))
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["model"] as? String == "glm-5.1")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = #"{ "choices": [ { "message": { "role": "assistant", "content": "OK" } } ] }"#
            return (response, Data(payload.utf8))
        }

        let client = OpenAIChatCompletionsClient(
            configuration: .openAICompatible(
                baseURL: URL(string: "https://api.z.ai/api/paas/v4/")!,
                apiKey: "z-token",
                model: "glm-5.1",
                providerName: HypeAIProvider.zAI.rawValue,
                chatCompletionsPath: "chat/completions",
                modelListPath: "models"
            ),
            session: session
        )

        let result = try await client.chat(messages: [OllamaMessage(role: "user", content: "Hello")], tools: [])
        #expect(result.message.content == "OK")
    }

    @Test("MiniMax model query avoids double v1 prefix")
    func miniMaxModelQueryAvoidsDoubleV1Prefix() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolOpenAIChatCompletions.self]
        let session = URLSession(configuration: config)
        defer { MockURLProtocolOpenAIChatCompletions.requestHandler = nil }

        MockURLProtocolOpenAIChatCompletions.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.minimax.io/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer minimax-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{ "data": [ { "id": "MiniMax-M2" } ] }"#.utf8))
        }

        let client = OpenAIChatCompletionsClient(
            configuration: .openAICompatible(
                baseURL: URL(string: "https://api.minimax.io/v1")!,
                apiKey: "minimax-token",
                model: "MiniMax-M2",
                providerName: HypeAIProvider.miniMax.rawValue,
                modelListPath: "v1/models"
            ),
            session: session
        )

        #expect(try await client.availableModels() == ["MiniMax-M2"])
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

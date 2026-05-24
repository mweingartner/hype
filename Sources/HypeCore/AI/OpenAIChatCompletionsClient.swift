import Foundation

public actor OpenAIChatCompletionsClient: HypeAIClient {
    public struct Configuration: Sendable, Equatable {
        public var baseURL: URL
        public var apiKey: String?
        public var model: String
        public var providerName: String
        public var chatCompletionsPath: String
        public var modelListPath: String?
        public var keepAlive: String?
        public var requestTimeout: TimeInterval
        public var resourceTimeout: TimeInterval

        public init(
            baseURL: URL,
            apiKey: String? = nil,
            model: String,
            providerName: String? = nil,
            chatCompletionsPath: String = "v1/chat/completions",
            modelListPath: String? = nil,
            keepAlive: String? = nil,
            requestTimeout: TimeInterval = 120,
            resourceTimeout: TimeInterval = 180
        ) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.model = model
            self.providerName = providerName ?? (apiKey == nil ? "ollama" : "openai")
            self.chatCompletionsPath = chatCompletionsPath
            self.modelListPath = modelListPath
            self.keepAlive = keepAlive
            self.requestTimeout = requestTimeout
            self.resourceTimeout = resourceTimeout
        }

        public static let openAI = Configuration(
            baseURL: URL(string: "https://api.openai.com")!,
            model: HypeAIConfiguration.defaultOpenAIModel
        )

        public static func ollama(host: String, port: String, model: String) -> Configuration {
            let baseURL = URL(string: "http://\(host):\(port)")!
            return Configuration(
                baseURL: baseURL,
                apiKey: nil,
                model: model,
                providerName: "ollama",
                keepAlive: "30m"
            )
        }

        public static func openAICompatible(
            baseURL: URL,
            apiKey: String? = nil,
            model: String,
            providerName: String,
            chatCompletionsPath: String = "v1/chat/completions",
            modelListPath: String? = nil,
            keepAlive: String? = nil
        ) -> Configuration {
            Configuration(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                providerName: providerName,
                chatCompletionsPath: chatCompletionsPath,
                modelListPath: modelListPath,
                keepAlive: keepAlive
            )
        }
    }

    public enum StreamingError: Error, LocalizedError, Sendable {
        case noAPIKey
        case invalidResponse
        case requestFailed(String)
        case parsingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noAPIKey: return "API key is required"
            case .invalidResponse: return "Invalid response from server"
            case .requestFailed(let message): return message
            case .parsingFailed(let message): return "Parse error: \(message)"
            }
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let logger: HypeLogger

    public init(
        configuration: Configuration,
        session: URLSession? = nil,
        logger: HypeLogger = .shared
    ) {
        self.configuration = configuration
        self.logger = logger

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = configuration.requestTimeout
        config.timeoutIntervalForResource = configuration.resourceTimeout
        config.waitsForConnectivity = false
        self.session = session ?? URLSession(configuration: config)
    }

    public nonisolated var providerName: String {
        configuration.providerName
    }

    public nonisolated var modelName: String {
        configuration.model
    }

    public nonisolated var supportsChatStreaming: Bool { true }

    public func availableModels() async throws -> [String] {
        if let modelListPath = configuration.modelListPath {
            return try await fetchOpenAICompatibleModels(path: modelListPath)
        }

        switch configuration.providerName {
        case "openai":
            return HypeAIConfiguration.openAITextModels
        case "z.ai":
            return HypeAIConfiguration.zAITextModels
        case "minimax":
            return HypeAIConfiguration.miniMaxTextModels
        default:
            break
        }
        return try await fetchOllamaModels()
    }

    private func fetchOpenAICompatibleModels(path: String) async throws -> [String] {
        let url = Self.endpoint(path, baseURL: configuration.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyProviderHeaders(to: &request, configuration: configuration)
        if let apiKey = HypeAIConfiguration.normalized(configuration.apiKey) {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Model list request failed: \(Self.describeFailure(response: response, data: data))", source: providerName)
            throw StreamingError.requestFailed(errorText)
        }

        struct ModelListResponse: Decodable {
            struct Model: Decodable {
                let id: String
            }
            let data: [Model]
        }
        return try JSONDecoder().decode(ModelListResponse.self, from: data).data.map(\.id)
    }

    private func fetchOllamaModels() async throws -> [String] {
        let url = Self.endpoint("api/tags", baseURL: configuration.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StreamingError.requestFailed("Failed to fetch Ollama models")
        }

        struct TagsResponse: Decodable { let models: [ModelInfo] }
        struct ModelInfo: Decodable { let name: String }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map { $0.name }
    }

    public func generate(prompt: String, model overrideModel: String?, system: String?) async throws -> String {
        let messages: [OllamaMessage] = [
            system.map { OllamaMessage(role: "system", content: $0) },
            OllamaMessage(role: "user", content: prompt)
        ].compactMap { $0 }

        let requestModel = overrideModel ?? configuration.model
        let url = Self.endpoint(configuration.chatCompletionsPath, baseURL: configuration.baseURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyProviderHeaders(to: &request, configuration: configuration)
        if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": requestModel,
            "messages": try Self.messagesToOpenAIFormat(from: messages),
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let failure = Self.describeFailure(response: response, data: data)
            logger.error("Generate request failed: \(failure)", source: providerName)
            throw StreamingError.requestFailed(failure)
        }

        let decoded = try decodeChatCompletionsResponse(data)
        return decoded.message.content ?? ""
    }

    public func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?
    ) async throws -> OllamaChatResponse {
        let url = Self.endpoint(configuration.chatCompletionsPath, baseURL: configuration.baseURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyProviderHeaders(to: &request, configuration: configuration)
        if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = try chatCompletionBody(model: configuration.model, messages: messages, tools: tools, stream: false)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.aiInput(describeChatRequest(url: url, model: configuration.model, messages: messages, tools: tools), source: providerName)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Chat request failed: \(Self.describeFailure(response: response, data: data))", source: providerName)
            throw StreamingError.requestFailed(errorText)
        }

        let decoded = try decodeChatCompletionsResponse(data)
        logger.aiOutput(describeChatResponse(decoded), source: providerName)
        return decoded
    }

    public nonisolated func chatStream(messages: [OllamaMessage], tools: [OllamaTool]) -> AsyncStream<String> {
        let config = self.configuration
        return AsyncStream { continuation in
            Task {
                do {
                    let url = Self.endpoint(config.chatCompletionsPath, baseURL: config.baseURL)

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    Self.applyProviderHeaders(to: &request, configuration: config)
                    if let apiKey = config.apiKey {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    var body: [String: Any] = [
                        "model": config.model,
                        "stream": true,
                        "messages": (try? Self.messagesToOpenAIFormat(from: messages)) ?? []
                    ]

                    if let keepAlive = config.keepAlive {
                        body["keep_alive"] = keepAlive
                    }

                    if !tools.isEmpty {
                        body["tools"] = Self.buildToolsPayload(tools)
                        body["tool_choice"] = "auto"
                    }

                    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                    let sessionConfig = URLSessionConfiguration.ephemeral
                    sessionConfig.timeoutIntervalForRequest = 120
                    let session = URLSession(configuration: sessionConfig)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode) else {
                        continuation.finish()
                        return
                    }

                    var buffer = Data()
                    for try await byteChunk in bytes {
                        buffer.append(byteChunk)

                        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                            let lineData = Data(buffer[..<newlineIndex])
                            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                            guard let line = String(data: lineData, encoding: .utf8),
                                  line.hasPrefix("data: ") else { continue }

                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            if let token = Self.parseSSEDataStatic(jsonString) {
                                continuation.yield(token)
                            }
                        }
                    }

                    if !buffer.isEmpty, let remaining = String(data: buffer, encoding: .utf8) {
                        for line in remaining.components(separatedBy: "\n") {
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" { break }
                            if let token = Self.parseSSEDataStatic(jsonString) {
                                continuation.yield(token)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    private static func parseSSEDataStatic(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            if let choices = json?["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let delta = firstChoice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                return content
            }
        } catch {
        }

        return nil
    }

    private func chatCompletionBody(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaTool],
        stream: Bool
    ) throws -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "stream": stream
        ]

        if let keepAlive = configuration.keepAlive {
            body["keep_alive"] = keepAlive
        }

        body["messages"] = try Self.messagesToOpenAIFormat(from: messages)

        if !tools.isEmpty {
            body["tools"] = Self.buildToolsPayload(tools)
            body["tool_choice"] = "auto"
        }

        return body
    }

    private static func buildToolsPayload(_ tools: [OllamaTool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "type": tool.type,
                "function": [
                    "name": tool.function.name,
                    "description": tool.function.description,
                    "parameters": [
                        "type": tool.function.parameters.type,
                        "properties": tool.function.parameters.properties.mapValues { prop in
                            var obj: [String: Any] = [
                                "type": prop.type,
                                "description": prop.description
                            ]
                            if let enumValues = prop.enum {
                                obj["enum"] = enumValues
                            }
                            return obj
                        },
                        "required": tool.function.parameters.required
                    ]
                ]
            ]
        }
    }

    private static func messagesToOpenAIFormat(from ollamaMessages: [OllamaMessage]) throws -> [[String: Any]] {
        var messages: [[String: Any]] = []
        var pendingFunctionCalls: [(id: String, name: String, arguments: String)] = []

        for message in ollamaMessages {
            switch message.role {
            case "system":
                messages.append(["role": "system", "content": message.content ?? ""])

            case "assistant":
                var assistantMessage: [String: Any] = ["role": "assistant"]
                if let content = message.content, !content.isEmpty {
                    assistantMessage["content"] = content
                }

                if let toolCalls = message.tool_calls {
                    var calls: [[String: Any]] = []
                    for call in toolCalls {
                        let callId = call.id ?? "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                        let argumentSummary = call.function.arguments
                            .map { "\($0.key): \($0.value)" }
                            .joined(separator: ", ")
                        pendingFunctionCalls.append((callId, call.function.name, argumentSummary.isEmpty ? "{}" : argumentSummary))
                        calls.append([
                            "id": callId,
                            "type": "function",
                            "function": [
                                "name": call.function.name,
                                "arguments": call.function.arguments.jsonString ?? "{}"
                            ]
                        ])
                    }
                    if !calls.isEmpty {
                        assistantMessage["tool_calls"] = calls
                    }
                }

                messages.append(assistantMessage)

            case "tool":
                guard let content = message.content, !content.isEmpty else { continue }
                if let first = pendingFunctionCalls.first {
                    pendingFunctionCalls.removeFirst()
                    messages.append([
                        "role": "tool",
                        "tool_call_id": first.id,
                        "content": content
                    ])
                } else {
                    messages.append(["role": "user", "content": "Tool result: \(content)"])
                }

            default:
                var userMessage: [String: Any] = ["role": message.role == "assistant" ? "user" : message.role]

                if let images = message.images, !images.isEmpty {
                    var parts: [[String: Any]] = []
                    if let content = message.content, !content.isEmpty {
                        parts.append(["type": "text", "text": content])
                    }
                    for image in images {
                        parts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:image/png;base64,\(image)"]
                        ])
                    }
                    userMessage["content"] = parts
                } else {
                    userMessage["content"] = message.content ?? ""
                }

                messages.append(userMessage)
            }
        }

        if messages.isEmpty {
            messages.append(["role": "user", "content": ""])
        }

        return messages
    }

    private func decodeChatCompletionsResponse(_ data: Data) throws -> OllamaChatResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamingError.invalidResponse
        }

        guard let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first else {
            throw StreamingError.invalidResponse
        }

        var content: String?
        var thinking: String?
        var toolCalls: [OllamaToolCall] = []

        if let message = firstChoice["message"] as? [String: Any] {
            content = message["content"] as? String
            let taggedThinking = content.map(Self.extractThinkingBlocks)
            if let taggedThinking {
                content = taggedThinking.content
            }
            let explicitThinking = ["reasoning_content", "thinking", "reasoning"]
                .compactMap { message[$0] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            let thinkingText = [explicitThinking, taggedThinking?.thinking]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            thinking = thinkingText.isEmpty ? nil : thinkingText

            if let calls = message["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    guard let function = call["function"] as? [String: Any],
                          let name = function["name"] as? String else { continue }
                    let arguments = (function["arguments"] as? String) ?? "{}"
                    let callId = call["id"] as? String
                    toolCalls.append(OllamaToolCall(
                        id: callId,
                        function: OllamaToolCallFunction(name: name, arguments: parseArguments(arguments))
                    ))
                }
            }
        }

        return OllamaChatResponse(
            message: OllamaMessage(
                role: "assistant",
                content: content,
                thinking: thinking,
                tool_calls: toolCalls.isEmpty ? nil : toolCalls
            ),
            done: true
        )
    }

    private func parseArguments(_ jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in json {
            if let str = value as? String {
                result[key] = str
            } else if let num = value as? NSNumber {
                result[key] = String(describing: num)
            } else if let dict = value as? [String: Any],
                      let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                      let str = String(data: jsonData, encoding: .utf8) {
                result[key] = str
            }
        }
        return result
    }

    private static func extractThinkingBlocks(from content: String) -> (content: String?, thinking: String?) {
        var remaining = content
        var blocks: [String] = []

        while let openRange = remaining.range(of: "<think>", options: [.caseInsensitive]),
              let closeRange = remaining.range(of: "</think>", options: [.caseInsensitive], range: openRange.upperBound..<remaining.endIndex) {
            let block = String(remaining[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty {
                blocks.append(block)
            }
            remaining.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }

        let trimmedContent = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedThinking = blocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            content: trimmedContent.isEmpty ? nil : trimmedContent,
            thinking: trimmedThinking.isEmpty ? nil : trimmedThinking
        )
    }

    public func preloadModel() async throws {
        if configuration.apiKey != nil { return }

        let url = Self.endpoint("api/generate", baseURL: configuration.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": configuration.model,
            "prompt": "",
            "keep_alive": "30m",
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = max(configuration.requestTimeout, 300)

        _ = try await session.data(for: request)
    }

    public func structuredChat<Response: Decodable & Sendable>(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response) {
        let response = try await chat(messages: messages, tools: tools, format: format)
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(Response.self, from: response)
        return (response, decoded)
    }

    private func describeChatRequest(model: String, messages: [OllamaMessage], tools: [OllamaTool]) -> String {
        describeChatRequest(url: Self.endpoint(configuration.chatCompletionsPath, baseURL: configuration.baseURL), model: model, messages: messages, tools: tools)
    }

    private func describeChatRequest(url: URL, model: String, messages: [OllamaMessage], tools: [OllamaTool]) -> String {
        var lines = [
            "POST \(url.absoluteString)",
            "model=\(model)",
            "messages=\(messages.count)",
            "tools=\(tools.map { $0.function.name }.joined(separator: ", "))"
        ]
        for (index, message) in messages.enumerated() {
            lines.append("MESSAGE \(index) \(message.role.uppercased()): \(message.content ?? "(empty)")")
        }
        return lines.joined(separator: "\n")
    }

    private static func describeFailure(response: URLResponse?, data: Data) -> String {
        let status = (response as? HTTPURLResponse).map { "HTTP \($0.statusCode)" } ?? "No HTTP response"
        let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(800) ?? ""
        return body.isEmpty ? status : "\(status): \(body)"
    }

    private func describeChatResponse(_ response: OllamaChatResponse) -> String {
        var lines = ["model=\(modelName)", "done=\(response.done)", "CONTENT: \(response.message.content ?? "(empty)")"]
        if let toolCalls = response.message.tool_calls {
            lines.append("TOOL CALLS: \(toolCalls.map { $0.function.name }.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private static func endpoint(_ path: String, baseURL: URL) -> URL {
        var components = path.split(separator: "/").map(String.init)
        if baseURL.path.split(separator: "/").last == "v1", components.first == "v1" {
            components.removeFirst()
        }
        return components.reduce(baseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private static func applyProviderHeaders(to request: inout URLRequest, configuration: Configuration) {
        if configuration.providerName == HypeAIProvider.zAI.rawValue {
            request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    var jsonString: String? {
        guard let data = try? JSONSerialization.data(withJSONObject: self as [String: Any], options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

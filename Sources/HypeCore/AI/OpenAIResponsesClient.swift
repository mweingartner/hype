import Foundation

public enum OpenAIClientError: Error, LocalizedError, Sendable {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case requestFailed(String)
    case requestTimedOut(endpoint: String, model: String, seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key is not configured."
        case .invalidURL:
            return "OpenAI request URL is invalid."
        case .invalidResponse:
            return "OpenAI returned an unexpected response."
        case .requestFailed(let message):
            return "OpenAI error: \(message)"
        case .requestTimedOut(let endpoint, let model, let seconds):
            return "OpenAI \(endpoint) timed out after \(Int(seconds.rounded()))s talking to model \"\(model)\"."
        }
    }
}

public actor OpenAIResponsesClient: HypeAIClient {
    public struct Timeouts: Sendable, Equatable {
        public var request: TimeInterval
        public var resource: TimeInterval

        public init(request: TimeInterval = 120, resource: TimeInterval = 180) {
            self.request = request
            self.resource = resource
        }
    }

    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let session: URLSession
    private let timeouts: Timeouts
    private let logger: HypeLogger

    public init(
        apiKey: String,
        model: String = HypeAIConfiguration.defaultOpenAIModel,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        timeouts: Timeouts = Timeouts(),
        logger: HypeLogger = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.timeouts = timeouts
        self.logger = logger

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeouts.request
        config.timeoutIntervalForResource = timeouts.resource
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    init(
        apiKey: String,
        model: String = HypeAIConfiguration.defaultOpenAIModel,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        timeouts: Timeouts = Timeouts(),
        session: URLSession,
        logger: HypeLogger = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.timeouts = timeouts
        self.session = session
        self.logger = logger
    }

    public nonisolated var providerName: String { "openai" }
    public nonisolated var modelName: String { model }

    public func availableModels() async throws -> [String] {
        HypeAIConfiguration.openAITextModels
    }

    public func preloadModel() async throws {
        // OpenAI-hosted models do not need a local warm-up step.
    }

    public func generate(prompt: String, model overrideModel: String? = nil, system: String? = nil) async throws -> String {
        let messages: [OllamaMessage] = [
            system.map { OllamaMessage(role: "system", content: $0) },
            OllamaMessage(role: "user", content: prompt)
        ].compactMap { $0 }
        let response = try await chat(
            messages: messages,
            tools: [],
            format: nil,
            modelOverride: overrideModel
        )
        return response.message.content ?? ""
    }

    public func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat? = nil
    ) async throws -> OllamaChatResponse {
        try await chat(
            messages: messages,
            tools: tools,
            format: format,
            modelOverride: nil
        )
    }

    public func structuredChat<Response: Decodable & Sendable>(
        messages: [OllamaMessage],
        tools: [OllamaTool] = [],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response) {
        let response = try await chat(messages: messages, tools: tools, format: format)
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(Response.self, from: response)
        return (response, decoded)
    }

    private func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?,
        modelOverride: String?
    ) async throws -> OllamaChatResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.noAPIKey
        }
        let requestModel = HypeAIConfiguration.normalized(modelOverride) ?? model
        let endpoint = "/v1/responses"
        let url = baseURL.appendingPathComponent("v1").appendingPathComponent("responses")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeouts.request

        let body = try Self.requestBodyObject(
            model: requestModel,
            messages: messages,
            tools: tools,
            format: format
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.aiInput(
            Self.describeRequest(model: requestModel, messages: messages, tools: tools, format: format),
            source: "OpenAI"
        )

        do {
            let (data, response) = try await sessionData(for: request, endpoint: endpoint, model: requestModel)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw OpenAIClientError.requestFailed(Self.errorMessage(from: data))
            }

            let decoded = try Self.decodeResponse(data)
            logger.aiOutput(
                Self.describeResponse(model: requestModel, response: decoded),
                source: "OpenAI"
            )
            return decoded
        } catch {
            logger.error(
                "\(endpoint) model=\(requestModel) failed: \(error.localizedDescription)",
                source: "OpenAI"
            )
            throw error
        }
    }

    private func sessionData(for request: URLRequest, endpoint: String, model: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OpenAIClientError.requestTimedOut(endpoint: endpoint, model: model, seconds: timeouts.request)
        } catch {
            throw error
        }
    }

    static func requestBodyObject(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?
    ) throws -> [String: Any] {
        let converted = try responsesInput(from: messages)
        var body: [String: Any] = [
            "model": model,
            "input": converted.input,
            "store": false
        ]
        if !converted.instructions.isEmpty {
            body["instructions"] = converted.instructions.joined(separator: "\n\n")
        }
        if !tools.isEmpty {
            body["tools"] = tools.map(responsesTool)
            body["tool_choice"] = "auto"
        }
        if let format {
            body["text"] = [
                "format": responseTextFormat(format)
            ]
        }
        return body
    }

    private static func responsesInput(from messages: [OllamaMessage]) throws -> (instructions: [String], input: [[String: Any]]) {
        var instructions: [String] = []
        var input: [[String: Any]] = []
        var pendingCallIds: [String] = []

        for message in messages {
            switch message.role {
            case "system":
                if let content = message.content, !content.isEmpty {
                    instructions.append(content)
                }

            case "assistant":
                if let content = message.content, !content.isEmpty {
                    input.append([
                        "role": "assistant",
                        "content": content
                    ])
                }
                if let toolCalls = message.tool_calls {
                    for call in toolCalls {
                        let callId = call.id ?? "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                        pendingCallIds.append(callId)
                        input.append([
                            "type": "function_call",
                            "call_id": callId,
                            "name": call.function.name,
                            "arguments": try jsonString(from: call.function.arguments)
                        ])
                    }
                }

            case "tool":
                let output = message.content ?? ""
                if pendingCallIds.isEmpty {
                    input.append([
                        "role": "user",
                        "content": "Tool result:\n\(output)"
                    ])
                } else {
                    input.append([
                        "type": "function_call_output",
                        "call_id": pendingCallIds.removeFirst(),
                        "output": output
                    ])
                }

            default:
                input.append(messageInput(role: message.role, content: message.content ?? "", images: message.images))
            }
        }

        if input.isEmpty {
            input.append(["role": "user", "content": ""])
        }
        return (instructions, input)
    }

    private static func messageInput(role: String, content: String, images: [String]?) -> [String: Any] {
        let mappedRole = role == "assistant" ? "assistant" : "user"
        guard let images, !images.isEmpty else {
            return [
                "role": mappedRole,
                "content": content
            ]
        }

        var parts: [[String: Any]] = []
        if !content.isEmpty {
            parts.append([
                "type": "input_text",
                "text": content
            ])
        }
        for image in images {
            parts.append([
                "type": "input_image",
                "image_url": "data:image/png;base64,\(image)"
            ])
        }
        return [
            "role": mappedRole,
            "content": parts
        ]
    }

    private static func responsesTool(_ tool: OllamaTool) -> [String: Any] {
        var parameters: [String: Any] = [
            "type": tool.function.parameters.type,
            "properties": tool.function.parameters.properties.mapValues { property in
                propertyObject(property)
            },
            "required": tool.function.parameters.required
        ]
        if parameters["additionalProperties"] == nil {
            parameters["additionalProperties"] = false
        }
        return [
            "type": "function",
            "name": tool.function.name,
            "description": tool.function.description,
            "parameters": parameters
        ]
    }

    private static func propertyObject(_ property: OllamaProperty) -> [String: Any] {
        var object: [String: Any] = [
            "type": property.type,
            "description": property.description
        ]
        if let values = property.enum {
            object["enum"] = values
        }
        return object
    }

    private static func responseTextFormat(_ format: OllamaResponseFormat) -> [String: Any] {
        switch format {
        case .json:
            return ["type": "json_object"]
        case .schema(let schema):
            return [
                "type": "json_schema",
                "name": "hype_structured_response",
                "schema": schema.object,
                "strict": false
            ]
        }
    }

    static func decodeResponse(_ data: Data) throws -> OllamaChatResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIClientError.invalidResponse
        }
        guard let output = json["output"] as? [[String: Any]] else {
            throw OpenAIClientError.invalidResponse
        }

        var textParts: [String] = []
        var toolCalls: [OllamaToolCall] = []

        for item in output {
            let type = item["type"] as? String
            switch type {
            case "message":
                if let content = item["content"] as? [[String: Any]] {
                    for part in content {
                        if let text = part["text"] as? String {
                            textParts.append(text)
                        } else if let text = part["output_text"] as? String {
                            textParts.append(text)
                        }
                    }
                }
            case "function_call":
                guard let name = item["name"] as? String else { continue }
                let arguments = item["arguments"] as? String ?? "{}"
                let callId = item["call_id"] as? String
                let function = try decodeFunctionCall(name: name, arguments: arguments)
                toolCalls.append(OllamaToolCall(id: callId, function: function))
            default:
                continue
            }
        }

        let content = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return OllamaChatResponse(
            message: OllamaMessage(
                role: "assistant",
                content: content.isEmpty ? nil : content,
                tool_calls: toolCalls.isEmpty ? nil : toolCalls
            ),
            done: true
        )
    }

    private static func decodeFunctionCall(name: String, arguments: String) throws -> OllamaToolCallFunction {
        let object: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(OllamaToolCallFunction.self, from: data)
    }

    private static func jsonString(from arguments: [String: String]) throws -> String {
        let object = arguments.reduce(into: [String: Any]()) { partialResult, pair in
            partialResult[pair.key] = OllamaToolClient.parseScalarJSONValue(pair.value)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "Unknown error"
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(300))
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "Unknown error"
    }

    private static func describeRequest(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?
    ) -> String {
        var lines = [
            "POST /v1/responses",
            "model=\(model)",
            "messages=\(messages.count)",
            "tools=\(tools.map { $0.function.name }.joined(separator: ", "))",
            "format=\(formatDescription(format))"
        ]
        for (index, message) in messages.enumerated() {
            lines.append("MESSAGE \(index) \(message.role.uppercased()):\n\(message.content ?? "(empty content)")")
            if let images = message.images, !images.isEmpty {
                lines.append("IMAGES ATTACHED: \(images.count) (\(images.map { "\($0.count) chars" }.joined(separator: ", ")))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describeResponse(model: String, response: OllamaChatResponse) -> String {
        var lines = [
            "POST /v1/responses",
            "model=\(model)",
            "done=\(response.done)",
            "MESSAGE ASSISTANT:",
            response.message.content ?? "(empty content)"
        ]
        if let toolCalls = response.message.tool_calls, !toolCalls.isEmpty {
            lines.append("TOOL CALLS:")
            for call in toolCalls {
                let args = call.function.arguments
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                lines.append("\(call.function.name)(\(args))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func formatDescription(_ format: OllamaResponseFormat?) -> String {
        guard let format else { return "none" }
        switch format {
        case .json: return "json"
        case .schema: return "schema"
        }
    }
}

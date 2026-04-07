import Foundation

/// A tool definition for Ollama's tool-use API.
public struct OllamaTool: Codable, Sendable {
    public let type: String  // "function"
    public let function: OllamaFunction

    public init(type: String, function: OllamaFunction) {
        self.type = type
        self.function = function
    }
}

/// A function definition within an Ollama tool.
public struct OllamaFunction: Codable, Sendable {
    public let name: String
    public let description: String
    public let parameters: OllamaParameters

    public init(name: String, description: String, parameters: OllamaParameters) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Parameter schema for an Ollama function.
public struct OllamaParameters: Codable, Sendable {
    public let type: String  // "object"
    public let properties: [String: OllamaProperty]
    public let required: [String]

    public init(type: String, properties: [String: OllamaProperty], required: [String]) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// A single property in an Ollama parameter schema.
public struct OllamaProperty: Codable, Sendable {
    public let type: String
    public let description: String
    public var `enum`: [String]?

    public init(type: String, description: String, `enum`: [String]? = nil) {
        self.type = type
        self.description = description
        self.`enum` = `enum`
    }
}

/// A message in the Ollama chat.
public struct OllamaMessage: Codable, Sendable {
    public let role: String
    public let content: String?
    public let tool_calls: [OllamaToolCall]?

    public init(role: String, content: String? = nil, tool_calls: [OllamaToolCall]? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
    }
}

/// A tool call returned by the model.
public struct OllamaToolCall: Codable, Sendable {
    public let function: OllamaToolCallFunction

    public init(function: OllamaToolCallFunction) {
        self.function = function
    }
}

/// The function name and arguments within a tool call.
public struct OllamaToolCallFunction: Codable, Sendable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

/// Ollama chat response.
public struct OllamaChatResponse: Codable, Sendable {
    public let message: OllamaMessage
    public let done: Bool
}

/// Client for Ollama's chat API with tool support.
public actor OllamaToolClient {
    private let host: String
    private let port: String
    private let model: String

    public init(host: String = "localhost", port: String = "11434", model: String = "llama3.2") {
        self.host = host
        self.port = port
        self.model = model
    }

    /// The base URL for the Ollama server.
    public var baseURL: String { "http://\(host):\(port)" }

    /// Send a chat request with tools.
    public func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool]
    ) async throws -> OllamaChatResponse {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw OllamaError.requestFailed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": model,
            "stream": false,
        ]

        // Encode messages
        let encodedMessages = try JSONEncoder().encode(messages)
        body["messages"] = try JSONSerialization.jsonObject(with: encodedMessages)

        // Encode tools if provided
        if !tools.isEmpty {
            let encodedTools = try JSONEncoder().encode(tools)
            body["tools"] = try JSONSerialization.jsonObject(with: encodedTools)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.requestFailed(errorText)
        }

        return try JSONDecoder().decode(OllamaChatResponse.self, from: data)
    }
}

/// Errors specific to Ollama communication.
public enum OllamaError: Error, LocalizedError {
    case requestFailed(String)
    case noResponse

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let msg): return "Ollama error: \(msg)"
        case .noResponse: return "No response from Ollama"
        }
    }
}

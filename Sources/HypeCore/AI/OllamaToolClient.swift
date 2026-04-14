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
///
/// `arguments` is exposed downstream as a flat `[String: String]` map so the
/// `HypeToolExecutor` can pull values with simple `Double(arguments["x"] ?? …)`
/// lookups. The wire format, however, is *not* guaranteed to be a string/string
/// object — Ollama, OpenAI, and most OpenAI-compatible servers return a JSON
/// object whose values can be any JSON type (number, bool, nested object,
/// array), and some servers wrap the whole thing in a JSON-encoded *string*.
///
/// The custom `init(from:)` below accepts any of those shapes and flattens
/// each value to a canonical string, so a model that emits e.g.
/// `{"x": 100, "diff_json": {"addNodes": [...]}}` no longer crashes decoding
/// with `DecodingError.typeMismatch` ("The data couldn't be read because it
/// isn't in the correct format").
public struct OllamaToolCallFunction: Sendable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

extension OllamaToolCallFunction: Codable {
    private enum CodingKeys: String, CodingKey { case name, arguments }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)

        // Missing arguments is valid — some tool calls take no parameters.
        guard container.contains(.arguments),
              try !container.decodeNil(forKey: .arguments) else {
            self.arguments = [:]
            return
        }

        // Decode as a generic JSON value. JSONFlexibleValue can represent any
        // JSON type, so this decode step never fails on well-formed JSON.
        let raw = try container.decode(JSONFlexibleValue.self, forKey: .arguments)

        // Normalize to a [String: JSONFlexibleValue] object we can walk.
        var object: [String: JSONFlexibleValue] = [:]
        switch raw {
        case .object(let dict):
            // Standard Ollama shape: arguments is a JSON object. Each value
            // may itself be a scalar, nested object, or array — all handled
            // by JSONFlexibleValue.canonicalString below.
            object = dict

        case .string(let s):
            // Some OpenAI-compatible servers wrap the entire arguments map
            // as a JSON-encoded string, e.g.
            //   "arguments": "{\"x\": 100, \"y\": 200}"
            // Re-parse the inner JSON and extract its object form.
            if let data = s.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(JSONFlexibleValue.self, from: data),
               case .object(let inner) = parsed {
                object = inner
            }
            // If the string isn't valid JSON or isn't an object, arguments
            // stays empty — the executor will fall through to its defaults.

        default:
            // null / bool / number / array in the top-level slot is nonsense
            // for a tool call arguments object. Leave the dictionary empty
            // so the executor runs with defaults instead of crashing.
            break
        }

        var result: [String: String] = [:]
        result.reserveCapacity(object.count)
        for (key, value) in object {
            result[key] = value.canonicalString
        }
        self.arguments = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
    }
}

/// A minimal JSON-value wrapper used to decode tool-call argument payloads
/// whose leaf values can be any JSON type. Each value is projected to a
/// canonical `String` before reaching the executor so downstream code can
/// keep its simple `[String: String]` interface.
///
/// Nested objects and arrays round-trip as their compact JSON form, which
/// means complex payloads like `diff_json` can be passed through as a string
/// even when the model chose to emit them as a nested JSON object.
fileprivate indirect enum JSONFlexibleValue: Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([JSONFlexibleValue])
    case object([String: JSONFlexibleValue])
}

extension JSONFlexibleValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        // Bool must come before Int/Double — Swift's JSON parser treats `true`
        // and `false` as both Bool and (on some platforms) Int(1)/Int(0), and
        // we want the richer Bool representation.
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        // Prefer Int64 over Double so whole-number coordinates survive the
        // round trip without picking up a ".0" suffix.
        if let i = try? container.decode(Int64.self) {
            self = .integer(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        if let o = try? container.decode([String: JSONFlexibleValue].self) {
            self = .object(o)
            return
        }
        if let a = try? container.decode([JSONFlexibleValue].self) {
            self = .array(a)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value in tool-call arguments"
        )
    }

    /// Canonical `String` form suitable for the executor's flat argument map.
    ///
    /// - `null` → empty string (executor treats this the same as "missing")
    /// - `bool` → "true" / "false"
    /// - `integer` → no decimal point (keeps coordinates tidy)
    /// - `double` → shortest lossless form
    /// - `string` → passed through verbatim
    /// - `object` / `array` → compact JSON encoding
    var canonicalString: String {
        switch self {
        case .null:
            return ""
        case .bool(let b):
            return b ? "true" : "false"
        case .integer(let i):
            return String(i)
        case .double(let d):
            // Whole-number doubles get the integer form, which matches what a
            // tool author would hand-write in a JSON schema.
            if d.isFinite, d.rounded() == d, abs(d) < 1e15 {
                return String(Int64(d))
            }
            return String(d)
        case .string(let s):
            return s
        case .array, .object:
            let any = self.toFoundationJSON
            if JSONSerialization.isValidJSONObject(any),
               let data = try? JSONSerialization.data(
                   withJSONObject: any,
                   options: [.sortedKeys]
               ),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            return ""
        }
    }

    /// Convert to a Foundation-friendly value tree so `JSONSerialization` can
    /// encode nested objects/arrays back into a compact JSON string.
    fileprivate var toFoundationJSON: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .integer(let i):
            return NSNumber(value: i)
        case .double(let d):
            return NSNumber(value: d)
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map(\.toFoundationJSON)
        case .object(let obj):
            var out: [String: Any] = [:]
            out.reserveCapacity(obj.count)
            for (k, v) in obj { out[k] = v.toFoundationJSON }
            return out
        }
    }
}

/// Ollama chat response.
public struct OllamaChatResponse: Codable, Sendable {
    public let message: OllamaMessage
    public let done: Bool
}

public struct OllamaGenerateResponse: Codable, Sendable {
    public let response: String
    public let done: Bool
}

private struct OllamaModelTagsResponse: Codable, Sendable {
    let models: [OllamaModelTag]
}

private struct OllamaModelTag: Codable, Sendable {
    let name: String
}

/// JSON schema payload for Ollama's `format` field.
///
/// We keep the schema as a raw JSON object because response-format schemas
/// are naturally recursive (`$defs` / `$ref`) and much easier to express as
/// ordinary JSON than as a giant tree of bespoke Swift types.
public struct OllamaJSONSchema: @unchecked Sendable {
    public let object: [String: Any]

    public init(object: [String: Any]) {
        self.object = object
    }
}

public enum OllamaResponseFormat: @unchecked Sendable {
    case json
    case schema(OllamaJSONSchema)
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

    public func availableModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaError.requestFailed("Invalid URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.requestFailed(errorText)
        }
        let tags = try JSONDecoder().decode(OllamaModelTagsResponse.self, from: data)
        return tags.models.map(\.name)
    }

    public func generate(
        prompt: String,
        model overrideModel: String? = nil,
        system: String? = nil
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.requestFailed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": overrideModel ?? model,
            "prompt": prompt,
            "stream": false,
        ]
        if let system {
            body["system"] = system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.requestFailed(errorText)
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return decoded.response
    }

    /// Send a chat request with tools.
    public func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat? = nil
    ) async throws -> OllamaChatResponse {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw OllamaError.requestFailed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body = try Self.requestBodyObject(
            model: model,
            messages: messages,
            tools: tools,
            format: format
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.requestFailed(errorText)
        }

        return try JSONDecoder().decode(OllamaChatResponse.self, from: data)
    }

    public func structuredChat<Response: Decodable>(
        messages: [OllamaMessage],
        tools: [OllamaTool] = [],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response) {
        let response = try await chat(messages: messages, tools: tools, format: format)
        guard let content = response.message.content,
              let data = content.data(using: .utf8) else {
            throw OllamaError.noStructuredContent
        }
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return (response, decoded)
        } catch {
            throw OllamaError.structuredDecodeFailed(error.localizedDescription)
        }
    }

    static func requestBodyObject(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?
    ) throws -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "stream": false,
        ]

        let encodedMessages = try JSONEncoder().encode(messages)
        body["messages"] = try JSONSerialization.jsonObject(with: encodedMessages)

        if !tools.isEmpty {
            let encodedTools = try JSONEncoder().encode(tools)
            body["tools"] = try JSONSerialization.jsonObject(with: encodedTools)
        }

        if let format {
            switch format {
            case .json:
                body["format"] = "json"
            case .schema(let schema):
                body["format"] = schema.object
            }
        }

        return body
    }
}

/// Errors specific to Ollama communication.
public enum OllamaError: Error, LocalizedError {
    case requestFailed(String)
    case noResponse
    case noStructuredContent
    case structuredDecodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let msg): return "Ollama error: \(msg)"
        case .noResponse: return "No response from Ollama"
        case .noStructuredContent: return "Ollama response did not include structured content"
        case .structuredDecodeFailed(let msg): return "Could not decode structured Ollama response: \(msg)"
        }
    }
}

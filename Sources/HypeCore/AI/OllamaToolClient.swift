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
///
/// The `images` field carries base64-encoded PNG strings for vision-capable models.
/// Custom `init(from:)` and `encode(to:)` implementations ensure that `images: nil`
/// serialises as an absent key rather than JSON `null`, which some Ollama vision
/// pipeline versions misinterpret as an empty array.
public struct OllamaMessage: Codable, Sendable {
    public let role: String
    public let content: String?
    public let tool_calls: [OllamaToolCall]?
    /// Base64-encoded PNG strings attached to this message for vision models.
    /// Nil means no images; use `encodeIfPresent` so the key is omitted entirely.
    public let images: [String]?

    public init(role: String, content: String? = nil, tool_calls: [OllamaToolCall]? = nil, images: [String]? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
        self.images = images
    }

    private enum CodingKeys: String, CodingKey { case role, content, tool_calls, images }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        tool_calls = try c.decodeIfPresent([OllamaToolCall].self, forKey: .tool_calls)
        images = try c.decodeIfPresent([String].self, forKey: .images)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(tool_calls, forKey: .tool_calls)
        try c.encodeIfPresent(images, forKey: .images)
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
        func unwrapSchemaPropertiesWrapper(
            _ dict: [String: JSONFlexibleValue]
        ) -> [String: JSONFlexibleValue] {
            // Some fine-tuned models leak the tool-schema shape into
            // the call itself and emit:
            //   "arguments": { "properties": { "property": "width" } }
            // instead of the real payload:
            //   "arguments": { "property": "width" }
            // Unwrap that single-key wrapper so the executor still
            // sees the intended flat argument map.
            if dict.count == 1, case .object(let inner)? = dict["properties"] {
                return inner
            }
            return dict
        }
        switch raw {
        case .object(let dict):
            // Standard Ollama shape: arguments is a JSON object. Each value
            // may itself be a scalar, nested object, or array — all handled
            // by JSONFlexibleValue.canonicalString below.
            object = unwrapSchemaPropertiesWrapper(dict)

        case .string(let s):
            // Some OpenAI-compatible servers wrap the entire arguments map
            // as a JSON-encoded string, e.g.
            //   "arguments": "{\"x\": 100, \"y\": 200}"
            // Re-parse the inner JSON and extract its object form.
            if let data = s.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(JSONFlexibleValue.self, from: data),
               case .object(let inner) = parsed {
                object = unwrapSchemaPropertiesWrapper(inner)
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
        case .array:
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
        case .object(let object):
            // Some tuned models emit each individual argument as an
            // object-wrapped scalar, e.g.
            //   "part_name": { "value": "play" }
            // instead of:
            //   "part_name": "play"
            // Unwrap that single-key shape so downstream executor
            // lookups still see the intended flat string.
            if object.count == 1, let inner = object["value"] {
                return inner.canonicalString
            }
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

    /// Timeout policy for Ollama requests.
    ///
    /// URLSession applies two timeouts:
    ///   * `request` — the idle timeout; reset whenever bytes
    ///     arrive. Ollama's `/api/chat` with `stream: false`
    ///     buffers the full generation and sends it all at once, so
    ///     with a 120s idle timeout and a 3-minute model generation
    ///     the connection gets killed with `NSURLErrorTimedOut`
    ///     before any bytes arrive.
    ///   * `resource` — the total end-to-end time. Caps the total
    ///     wall clock regardless of idle resets.
    ///
    /// The defaults here are *generous* because local models on a
    /// laptop (especially 14B+ class models, or any model loading
    /// cold from disk) routinely need several minutes to produce a
    /// recursive structured JSON response. Callers that want
    /// tighter limits can set `.fast(...)` or provide a custom
    /// `Timeouts`.
    public struct Timeouts: Sendable, Equatable {
        public var request: TimeInterval
        public var resource: TimeInterval

        public init(request: TimeInterval, resource: TimeInterval) {
            self.request = request
            self.resource = resource
        }

        /// Short end-to-end operations: listing available models, etc.
        public static let quick = Timeouts(request: 30, resource: 60)
        /// Free-form single-shot generation or chat.
        public static let chat = Timeouts(request: 300, resource: 300)
        /// Structured / schema-constrained generation — much slower
        /// because the server runs token-by-token grammar checks and
        /// recursive JSON schemas are O(tokens × depth).
        public static let structured = Timeouts(request: 600, resource: 600)
    }

    private let timeouts: Timeouts
    private let session: URLSession

    public init(
        host: String = "localhost",
        port: String = "11434",
        model: String = "llama3.2",
        timeouts: Timeouts = .structured
    ) {
        self.host = host
        self.port = port
        self.model = model
        self.timeouts = timeouts

        // A dedicated URLSession so the resource timeout lines up
        // with the structured-chat budget. `URLSession.shared` has
        // different defaults that the per-request timeoutInterval
        // can't override.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeouts.request
        config.timeoutIntervalForResource = timeouts.resource
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    init(
        host: String = "localhost",
        port: String = "11434",
        model: String = "llama3.2",
        timeouts: Timeouts = .structured,
        session: URLSession
    ) {
        self.host = host
        self.port = port
        self.model = model
        self.timeouts = timeouts
        self.session = session
    }

    /// The base URL for the Ollama server.
    public var baseURL: String { "http://\(host):\(port)" }

    public func availableModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaError.requestFailed("Invalid URL")
        }
        let (data, response) = try await sessionData(from: url, endpoint: "/api/tags")
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.requestFailed(errorText)
        }
        let tags = try JSONDecoder().decode(OllamaModelTagsResponse.self, from: data)
        return tags.models.map(\.name)
    }

    /// Wrap `session.data(from:)` to catch `URLError.timedOut` and
    /// re-throw as our richer `OllamaError.requestTimedOut` so
    /// callers (and the chat UI) can distinguish a timeout from a
    /// generic transport failure and suggest concrete next steps.
    private func sessionData(from url: URL, endpoint: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OllamaError.requestTimedOut(
                endpoint: endpoint,
                model: model,
                seconds: timeouts.request
            )
        } catch {
            throw error
        }
    }

    private func sessionData(for request: URLRequest, endpoint: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OllamaError.requestTimedOut(
                endpoint: endpoint,
                model: model,
                seconds: timeouts.request
            )
        } catch {
            throw error
        }
    }

    public func generate(
        prompt: String,
        model overrideModel: String? = nil,
        system: String? = nil
    ) async throws -> String {
        let requestModel = overrideModel ?? model
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.requestFailed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeouts.request

        var body: [String: Any] = [
            "model": requestModel,
            "prompt": prompt,
            "stream": false,
        ]
        if let system {
            body["system"] = system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        HypeLogger.shared.aiInput(
            Self.describeGenerateRequest(model: requestModel, prompt: prompt, system: system),
            source: "Ollama"
        )

        do {
            let (data, response) = try await sessionData(for: request, endpoint: "/api/generate")
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw OllamaError.requestFailed(errorText)
            }

            let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            HypeLogger.shared.aiOutput(
                Self.describeGenerateResponse(model: requestModel, response: decoded),
                source: "Ollama"
            )
            return decoded.response
        } catch {
            HypeLogger.shared.error(
                "/api/generate model=\(requestModel) failed: \(error.localizedDescription)",
                source: "Ollama"
            )
            throw error
        }
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
        request.timeoutInterval = timeouts.request

        let body = try Self.requestBodyObject(
            model: model,
            messages: messages,
            tools: tools,
            format: format
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        HypeLogger.shared.aiInput(
            Self.describeChatRequest(
                model: model,
                messages: messages,
                tools: tools,
                format: format
            ),
            source: "Ollama"
        )

        do {
            let (data, response) = try await sessionData(for: request, endpoint: "/api/chat")
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw OllamaError.requestFailed(errorText)
            }

            let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
            HypeLogger.shared.aiOutput(
                Self.describeChatResponse(model: model, response: decoded),
                source: "Ollama"
            )
            return decoded
        } catch {
            HypeLogger.shared.error(
                "/api/chat model=\(model) failed: \(error.localizedDescription)",
                source: "Ollama"
            )
            throw error
        }
    }

    /// Send a chat request and decode the model's reply into a typed
    /// `Response`. Local models frequently return JSON in ways that
    /// break naive decoding, so this function is intentionally
    /// tolerant and walks through a series of fallbacks before
    /// giving up:
    ///
    /// 1. Try decoding `message.content` as-is.
    /// 2. Strip markdown code fences (```json / ```) and try again.
    /// 3. Extract the first balanced `{...}` JSON object embedded in
    ///    any surrounding prose and try again.
    /// 4. If `content` is empty or still fails, read any JSON payload
    ///    attached to a single `tool_calls` entry (some
    ///    OpenAI-compatible servers return structured output that
    ///    way when they see a `format` hint).
    ///
    /// When every pass fails, the thrown error carries both the
    /// original `DecodingError` description AND a short preview of
    /// the raw response so callers can surface something useful to
    /// the user instead of Swift's opaque "data couldn't be read"
    /// localizedDescription.
    ///
    /// ## Server-side format fallback
    ///
    /// Some Ollama models ship without the tokenizer metadata
    /// required for grammar-constrained decoding (the "failed to
    /// load model vocabulary required for format" error). The
    /// canonical examples are various Gemma variants and older
    /// fine-tunes. When the initial request fails with that
    /// specific error we automatically retry *without* the `format`
    /// field, but inject the expected JSON schema into a synthetic
    /// system prompt so the model still gets structural guidance.
    /// The tolerant extraction cascade above then recovers the JSON
    /// from whatever free-form response the model produces.
    public func structuredChat<Response: Decodable>(
        messages: [OllamaMessage],
        tools: [OllamaTool] = [],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response) {
        do {
            let response = try await chat(messages: messages, tools: tools, format: format)
            let (decoded, _) = try Self.decodeStructuredResponse(Response.self, from: response)
            return (response, decoded)
        } catch let error as OllamaError where Self.isFormatUnsupportedError(error) {
            // Fallback: the server said this model can't do
            // grammar-constrained output. Retry without `format` but
            // nudge the model toward the right shape with a
            // synthetic system message describing the schema.
            HypeLogger.shared.warn(
                "/api/chat model=\(model) does not support server-side structured output; retrying with schema prompt",
                source: "Ollama"
            )
            let retryMessages = Self.messagesWithSchemaPrompt(
                original: messages,
                format: format
            )
            let response = try await chat(
                messages: retryMessages,
                tools: tools,
                format: nil
            )
            let (decoded, _) = try Self.decodeStructuredResponse(Response.self, from: response)
            return (response, decoded)
        }
    }

    /// Recognize the Ollama server-side error that fires when the
    /// selected model doesn't carry the tokenizer metadata needed
    /// for grammar-constrained decoding.
    ///
    /// The exact text was added to Ollama around the time grammar
    /// support shipped; we match on both the canonical and a few
    /// close variants so a future wording tweak doesn't silently
    /// break the fallback.
    static func isFormatUnsupportedError(_ error: OllamaError) -> Bool {
        guard case .requestFailed(let msg) = error else { return false }
        let m = msg.lowercased()
        return m.contains("failed to load model vocabulary")
            || m.contains("vocabulary required for format")
            || m.contains("format is not supported")
            || m.contains("model does not support structured output")
    }

    /// Build a new message list that embeds the JSON schema in a
    /// synthetic system message. Used by the format-unsupported
    /// retry path so the model still has structural guidance even
    /// without server-side grammar constraints.
    static func messagesWithSchemaPrompt(
        original: [OllamaMessage],
        format: OllamaResponseFormat
    ) -> [OllamaMessage] {
        let schemaText = renderSchemaPrompt(format)
        guard !schemaText.isEmpty else { return original }

        // If the first message is a system prompt, concatenate the
        // schema guidance onto it. Otherwise prepend a fresh system
        // message. This keeps the model's role directive intact.
        if let first = original.first, first.role == "system" {
            let merged = (first.content ?? "") + "\n\n" + schemaText
            var rest = original
            rest[0] = OllamaMessage(role: "system", content: merged, tool_calls: nil)
            return rest
        }
        var messages = original
        messages.insert(OllamaMessage(role: "system", content: schemaText, tool_calls: nil), at: 0)
        return messages
    }

    /// Render the `OllamaResponseFormat` as a compact, human-readable
    /// schema description that the model can read and follow even
    /// without server-side grammar enforcement.
    static func renderSchemaPrompt(_ format: OllamaResponseFormat) -> String {
        switch format {
        case .json:
            return "Respond with a single valid JSON value and nothing else. Do not wrap it in markdown code fences. Do not include prose before or after the JSON."
        case .schema(let schema):
            guard JSONSerialization.isValidJSONObject(schema.object),
                  let data = try? JSONSerialization.data(
                      withJSONObject: schema.object,
                      options: [.prettyPrinted, .sortedKeys]
                  ),
                  let rendered = String(data: data, encoding: .utf8)
            else {
                return ""
            }
            return """
            IMPORTANT: the server running you does not enforce structured output for this model. Follow this JSON schema strictly. Respond with one JSON object that matches the schema exactly — no prose, no markdown code fences, no leading / trailing comments. Unknown enum values will be rejected; use only the values the schema lists.

            \(rendered)
            """
        }
    }

    /// Internal, pure, testable decoder. Handles the fallback
    /// cascade described on `structuredChat` above. Returns the
    /// decoded value and the raw JSON blob it came from (the latter
    /// is useful for telemetry / error-surfacing).
    static func decodeStructuredResponse<Response: Decodable>(
        _ responseType: Response.Type,
        from response: OllamaChatResponse
    ) throws -> (decoded: Response, rawJSON: String) {
        let decoder = JSONDecoder()
        var lastDecodeError: Error?
        var previewSource: String?

        // Gather every candidate JSON string the model might have
        // produced, in descending order of likelihood.
        var candidates: [String] = []

        if let content = response.message.content {
            previewSource = content

            // 1) content as-is
            candidates.append(content)

            // 2) content with markdown code fences stripped
            if let stripped = Self.stripCodeFences(content), stripped != content {
                candidates.append(stripped)
            }

            // 3) first balanced {...} object embedded in prose
            if let extracted = Self.extractFirstJSONObject(from: content),
               extracted != content {
                candidates.append(extracted)
            }
        }

        // 4) tool_calls payload — some servers return structured output there
        if let toolCalls = response.message.tool_calls, !toolCalls.isEmpty {
            // Rebuild the arguments map as a compact JSON object.
            let call = toolCalls[0]
            var obj: [String: Any] = [:]
            for (k, v) in call.function.arguments {
                obj[k] = Self.parseScalarJSONValue(v)
            }
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
               let s = String(data: data, encoding: .utf8) {
                candidates.append(s)
                previewSource = previewSource ?? s
            }
        }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                let decoded = try decoder.decode(Response.self, from: data)
                return (decoded, candidate)
            } catch {
                lastDecodeError = error
            }
        }

        if candidates.isEmpty {
            throw OllamaError.noStructuredContent
        }

        let reason = Self.describeDecodeFailure(lastDecodeError, preview: previewSource)
        throw OllamaError.structuredDecodeFailed(reason)
    }

    /// Strip a single pair of markdown code fences around a JSON
    /// payload. Recognizes ```json, ```JSON, or a bare ``` fence.
    /// Returns nil when the input doesn't look fenced, so callers can
    /// skip the extra decode attempt.
    static func stripCodeFences(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return nil }

        var body = trimmed
        // Drop the opening fence up through the first newline.
        if let firstNewline = body.firstIndex(of: "\n") {
            body = String(body[body.index(after: firstNewline)...])
        } else {
            // Single-line ```{...}``` is weird but supported.
            body = String(body.dropFirst(3))
        }

        // Drop the closing ``` if present.
        if let closeRange = body.range(of: "```", options: .backwards) {
            body = String(body[..<closeRange.lowerBound])
        }

        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Walk `content` character-by-character to find the first
    /// balanced JSON object (starting with `{`) and return it as a
    /// substring. Respects string literals so a `{` or `}` inside a
    /// quoted string doesn't throw off the depth counter. Returns
    /// nil when no balanced object is found.
    static func extractFirstJSONObject(from content: String) -> String? {
        guard let start = content.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        let scalars = content[start...]
        var index = start

        for ch in scalars {
            if escape {
                escape = false
            } else if inString {
                if ch == "\\" { escape = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        let end = content.index(after: index)
                        return String(content[start..<end])
                    }
                default: break
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    /// Turn a flat `[String: String]` argument map (as produced by
    /// OllamaToolCallFunction's canonical decoder) back into a
    /// loosely-typed Foundation-JSON value: JSON strings stay
    /// strings, but "true"/"false"/numbers/nested-JSON become their
    /// native types. This lets the tool_calls fallback feed back
    /// into strict `JSONDecoder` cleanly.
    static func parseScalarJSONValue(_ s: String) -> Any {
        if s == "true" { return true }
        if s == "false" { return false }
        if s == "null" { return NSNull() }
        if let i = Int64(s) { return NSNumber(value: i) }
        if let d = Double(s), !d.isNaN { return NSNumber(value: d) }
        // If the argument looks like nested JSON (object or array),
        // parse it so the outer JSONSerialization produces a nested
        // object instead of a re-quoted string.
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
            (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
        }
        return s
    }

    /// Build a user-facing error description that keeps Swift's
    /// "codingPath" context when available (far more actionable than
    /// "The data couldn't be read…") and tacks on a short preview of
    /// the raw content so the caller / log / UI can tell *what* the
    /// model actually sent.
    static func describeDecodeFailure(_ error: Error?, preview: String?) -> String {
        var detail = "unknown"
        if let error = error as? DecodingError {
            switch error {
            case .typeMismatch(let type, let ctx):
                detail = "type mismatch for \(type) at \(Self.formatCodingPath(ctx.codingPath)) — \(ctx.debugDescription)"
            case .valueNotFound(let type, let ctx):
                detail = "missing value for \(type) at \(Self.formatCodingPath(ctx.codingPath)) — \(ctx.debugDescription)"
            case .keyNotFound(let key, let ctx):
                detail = "missing key '\(key.stringValue)' at \(Self.formatCodingPath(ctx.codingPath))"
            case .dataCorrupted(let ctx):
                detail = "data corrupted at \(Self.formatCodingPath(ctx.codingPath)) — \(ctx.debugDescription)"
            @unknown default:
                detail = error.localizedDescription
            }
        } else if let error {
            detail = error.localizedDescription
        }

        if let preview, !preview.isEmpty {
            let snippet = Self.previewSnippet(preview)
            return "\(detail) — model said: \(snippet)"
        }
        return detail
    }

    private static func formatCodingPath(_ path: [CodingKey]) -> String {
        if path.isEmpty { return "<root>" }
        return path.map { $0.stringValue }.joined(separator: ".")
    }

    private static func previewSnippet(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespaces)
        let maxLen = 180
        if trimmed.count <= maxLen { return "\"\(trimmed)\"" }
        let prefix = trimmed.prefix(maxLen)
        return "\"\(prefix)…\" (+\(trimmed.count - maxLen) more chars)"
    }

    private static func describeGenerateRequest(
        model: String,
        prompt: String,
        system: String?
    ) -> String {
        var lines = [
            "POST /api/generate",
            "model=\(model)",
        ]
        if let system, !system.isEmpty {
            lines.append("SYSTEM:\n\(system)")
        }
        lines.append("PROMPT:\n\(prompt)")
        return lines.joined(separator: "\n")
    }

    private static func describeGenerateResponse(
        model: String,
        response: OllamaGenerateResponse
    ) -> String {
        """
        POST /api/generate
        model=\(model)
        done=\(response.done)
        RESPONSE:
        \(response.response)
        """
    }

    private static func describeChatRequest(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?
    ) -> String {
        var lines = [
            "POST /api/chat",
            "model=\(model)",
            "messages=\(messages.count)",
            "tools=\(tools.map { $0.function.name }.joined(separator: ", "))",
            "format=\(formatDescription(format))",
        ]
        for (index, message) in messages.enumerated() {
            lines.append(renderMessage(message, index: index))
        }
        return lines.joined(separator: "\n")
    }

    private static func describeChatResponse(
        model: String,
        response: OllamaChatResponse
    ) -> String {
        """
        POST /api/chat
        model=\(model)
        done=\(response.done)
        \(renderMessage(response.message, index: nil))
        """
    }

    private static func formatDescription(_ format: OllamaResponseFormat?) -> String {
        guard let format else { return "none" }
        switch format {
        case .json:
            return "json"
        case .schema:
            return "schema"
        }
    }

    private static func renderMessage(_ message: OllamaMessage, index: Int?) -> String {
        let prefix: String
        if let index {
            prefix = "MESSAGE \(index) \(message.role.uppercased()):"
        } else {
            prefix = "MESSAGE \(message.role.uppercased()):"
        }

        var parts = [prefix]
        if let content = message.content, !content.isEmpty {
            parts.append(content)
        } else {
            parts.append("(empty content)")
        }
        if let toolCalls = message.tool_calls, !toolCalls.isEmpty {
            let calls = toolCalls
                .map { call -> String in
                    let args = call.function.arguments
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: ", ")
                    return "\(call.function.name)(\(args))"
                }
                .joined(separator: "\n")
            parts.append("TOOL CALLS:\n\(calls)")
        }
        if let images = message.images, !images.isEmpty {
            parts.append("IMAGES ATTACHED: \(images.count) (\(images.map { "\($0.count) chars" }.joined(separator: ", ")))")
        }
        return parts.joined(separator: "\n")
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
            // Keep the model resident in GPU memory between chat
            // turns. Ollama's default is 5 minutes of idle before
            // it unloads the weights — for a 56 GB tuned model
            // that translates into 10-40 s of cold-load penalty
            // on the next user message, on top of generation time.
            // A 30-minute keep-alive covers typical interactive
            // sessions without permanently pinning the model.
            //
            // Note: if multiple models need to share VRAM, raise
            // this lower-bound or pass an explicit shorter value
            // at call time. For a single tuned model on an M5 Max
            // with 128 GB unified memory, 30 m is cheap.
            "keep_alive": "30m",
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

    /// Preload the current `model` into the Ollama server's memory
    /// with a zero-token generation so the FIRST real chat request
    /// doesn't also pay the 40 s cold-load penalty. Fire-and-forget
    /// at app startup (or when the user swaps models in Preferences).
    /// Returns once the model reports loaded, or throws on error.
    public func preloadModel() async throws {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.requestFailed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Give the preload its own (long) budget — the same
        // `timeouts.request` might be shorter than a real cold-load
        // on a very large model.
        request.timeoutInterval = max(timeouts.request, 300)

        let body: [String: Any] = [
            "model": model,
            // Empty prompt + `keep_alive` triggers a pure load.
            "prompt": "",
            "keep_alive": "30m",
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        _ = try await sessionData(for: request, endpoint: "/api/generate")
    }
}

/// Errors specific to Ollama communication.
public enum OllamaError: Error, LocalizedError {
    case requestFailed(String)
    case noResponse
    case noStructuredContent
    case structuredDecodeFailed(String)
    /// The request exceeded its configured idle or resource timeout.
    ///
    /// Far more common than a real hang: local model servers take
    /// minutes when generating constrained JSON, running 14B+ models,
    /// or cold-loading a model from disk. The message reports the
    /// model, endpoint, and configured timeout so the caller can
    /// suggest a smaller model, a warm restart, or a longer budget.
    case requestTimedOut(endpoint: String, model: String, seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let msg): return "Ollama error: \(msg)"
        case .noResponse: return "No response from Ollama"
        case .noStructuredContent: return "Ollama response did not include structured content"
        case .structuredDecodeFailed(let msg): return "Could not decode structured Ollama response: \(msg)"
        case .requestTimedOut(let endpoint, let model, let seconds):
            let s = Int(seconds.rounded())
            return "Ollama \(endpoint) timed out after \(s)s talking to model \"\(model)\". "
                 + "Either the model is still loading (cold start), the generation is "
                 + "genuinely slow for this prompt, or the server is unreachable. "
                 + "Try: (1) wait a moment and retry, (2) switch to a smaller model, "
                 + "(3) pre-load the model with `ollama run \(model) ''`, "
                 + "(4) confirm `curl http://localhost:11434/api/tags` responds."
        }
    }
}

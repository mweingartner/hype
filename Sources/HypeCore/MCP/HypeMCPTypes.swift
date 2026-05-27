import Foundation

public enum HypeMCPJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([HypeMCPJSONValue])
    case object([String: HypeMCPJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([HypeMCPJSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: HypeMCPJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public var objectValue: [String: HypeMCPJSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    public var arrayValue: [HypeMCPJSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    public var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var flattenedString: String {
        switch self {
        case .null:
            return ""
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .string(let value):
            return value
        case .array, .object:
            return jsonString(pretty: false)
        }
    }

    public func jsonString(pretty: Bool = true) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}

public struct HypeMCPRequest: Codable, Sendable {
    public var jsonrpc: String?
    public var id: HypeMCPJSONValue?
    public var method: String
    public var params: HypeMCPJSONValue?
}

public struct HypeMCPError: Codable, Sendable {
    public var code: Int
    public var message: String
    public var data: HypeMCPJSONValue?

    public init(code: Int, message: String, data: HypeMCPJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct HypeMCPResponse: Codable, Sendable {
    public var jsonrpc = "2.0"
    public var id: HypeMCPJSONValue?
    public var result: HypeMCPJSONValue?
    public var error: HypeMCPError?
}

public struct HypeMCPTool: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: HypeMCPJSONValue

    public init(name: String, description: String, inputSchema: HypeMCPJSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct HypeMCPResource: Codable, Equatable, Sendable {
    public var uri: String
    public var name: String
    public var description: String
    public var mimeType: String

    public init(uri: String, name: String, description: String, mimeType: String = "application/json") {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }
}

public struct HypeMCPPrompt: Codable, Equatable, Sendable {
    public struct Argument: Codable, Equatable, Sendable {
        public var name: String
        public var description: String
        public var required: Bool
    }

    public var name: String
    public var description: String
    public var arguments: [Argument]
}

@MainActor
public protocol HypeMCPBackend {
    func listTools() async -> [HypeMCPTool]
    func callTool(name: String, arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue
    func listResources() async -> [HypeMCPResource]
    func readResource(uri: String) async -> HypeMCPJSONValue
    func listPrompts() async -> [HypeMCPPrompt]
    func getPrompt(name: String, arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue
}

@MainActor
public struct HypeMCPProcessor {
    public let backend: any HypeMCPBackend
    public let serverName: String
    public let serverVersion: String

    public init(
        backend: any HypeMCPBackend,
        serverName: String = "Hype",
        serverVersion: String = "1.0"
    ) {
        self.backend = backend
        self.serverName = serverName
        self.serverVersion = serverVersion
    }

    public func handle(data: Data) async -> Data? {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if let requests = try? decoder.decode([HypeMCPRequest].self, from: data) {
            var responses: [HypeMCPResponse] = []
            for request in requests {
                if let response = await handle(request) {
                    responses.append(response)
                }
            }
            guard !responses.isEmpty else { return nil }
            return try? encoder.encode(responses)
        }

        guard let request = try? decoder.decode(HypeMCPRequest.self, from: data) else {
            let response = HypeMCPResponse(
                id: nil,
                result: nil,
                error: HypeMCPError(code: -32700, message: "Parse error")
            )
            return try? encoder.encode(response)
        }

        guard let response = await handle(request) else { return nil }
        return try? encoder.encode(response)
    }

    private func handle(_ request: HypeMCPRequest) async -> HypeMCPResponse? {
        if request.method.hasPrefix("notifications/") {
            return nil
        }

        do {
            let result = try await result(for: request)
            return HypeMCPResponse(id: request.id, result: result, error: nil)
        } catch let error as HypeMCPProcessorError {
            return HypeMCPResponse(id: request.id, result: nil, error: error.mcpError)
        } catch {
            return HypeMCPResponse(
                id: request.id,
                result: nil,
                error: HypeMCPError(code: -32603, message: error.localizedDescription)
            )
        }
    }

    private func result(for request: HypeMCPRequest) async throws -> HypeMCPJSONValue {
        switch request.method {
        case "initialize":
            return [
                "protocolVersion": "2025-06-18",
                "capabilities": [
                    "tools": ["listChanged": false],
                    "resources": ["subscribe": false, "listChanged": false],
                    "prompts": ["listChanged": false]
                ],
                "serverInfo": [
                    "name": serverName,
                    "version": serverVersion
                ]
            ].mcp
        case "ping":
            return .object([:])
        case "tools/list":
            return .object([
                "tools": .array(await backend.listTools().map { $0.mcpJSON })
            ])
        case "tools/call":
            let params = request.params?.objectValue ?? [:]
            guard let name = params["name"]?.stringValue else {
                throw HypeMCPProcessorError.invalidParams("tools/call requires params.name")
            }
            let args = params["arguments"]?.objectValue ?? [:]
            let result = await backend.callTool(name: name, arguments: args)
            return .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(result.jsonString())
                    ])
                ]),
                "isError": .bool(false)
            ])
        case "resources/list":
            return .object([
                "resources": .array(await backend.listResources().map { $0.mcpJSON })
            ])
        case "resources/read":
            let params = request.params?.objectValue ?? [:]
            guard let uri = params["uri"]?.stringValue else {
                throw HypeMCPProcessorError.invalidParams("resources/read requires params.uri")
            }
            let result = await backend.readResource(uri: uri)
            return .object([
                "contents": .array([
                    .object([
                        "uri": .string(uri),
                        "mimeType": .string("application/json"),
                        "text": .string(result.jsonString())
                    ])
                ])
            ])
        case "prompts/list":
            return .object([
                "prompts": .array(await backend.listPrompts().map { $0.mcpJSON })
            ])
        case "prompts/get":
            let params = request.params?.objectValue ?? [:]
            guard let name = params["name"]?.stringValue else {
                throw HypeMCPProcessorError.invalidParams("prompts/get requires params.name")
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            return await backend.getPrompt(name: name, arguments: arguments)
        default:
            throw HypeMCPProcessorError.methodNotFound(request.method)
        }
    }
}

private enum HypeMCPProcessorError: Error {
    case invalidParams(String)
    case methodNotFound(String)

    var mcpError: HypeMCPError {
        switch self {
        case .invalidParams(let message):
            return HypeMCPError(code: -32602, message: message)
        case .methodNotFound(let method):
            return HypeMCPError(code: -32601, message: "Method not found: \(method)")
        }
    }
}

public extension Dictionary where Key == String, Value == HypeMCPJSONValue {
    var mcp: HypeMCPJSONValue { .object(self) }
}

public extension Dictionary where Key == String, Value == Any {
    var mcp: HypeMCPJSONValue {
        HypeMCPJSONValue(any: self)
    }
}

public extension Array where Element == HypeMCPJSONValue {
    var mcp: HypeMCPJSONValue { .array(self) }
}

public extension HypeMCPJSONValue {
    init(any: Any) {
        switch any {
        case let value as HypeMCPJSONValue:
            self = value
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as Float:
            self = .number(Double(value))
        case let value as [Any]:
            self = .array(value.map(HypeMCPJSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(HypeMCPJSONValue.init(any:)))
        default:
            self = .null
        }
    }
}

private extension HypeMCPTool {
    var mcpJSON: HypeMCPJSONValue {
        [
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema
        ].mcp
    }
}

private extension HypeMCPResource {
    var mcpJSON: HypeMCPJSONValue {
        [
            "uri": .string(uri),
            "name": .string(name),
            "description": .string(description),
            "mimeType": .string(mimeType)
        ].mcp
    }
}

private extension HypeMCPPrompt {
    var mcpJSON: HypeMCPJSONValue {
        [
            "name": .string(name),
            "description": .string(description),
            "arguments": .array(arguments.map {
                [
                    "name": .string($0.name),
                    "description": .string($0.description),
                    "required": .bool($0.required)
                ].mcp
            })
        ].mcp
    }
}

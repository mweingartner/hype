import Foundation

/// Uses an installed app's credential-owning bridge. Hype never reads its token.
public struct MCPStdioBridgeClient: Sendable {
    public var executableURL: URL
    public var timeout: TimeInterval
    public init(executableURL: URL, timeout: TimeInterval = 30) { self.executableURL = executableURL; self.timeout = timeout }

    public func callTool(_ name: String, arguments: [String: HypeMCPJSONValue]) async throws -> HypeMCPJSONValue {
        #if os(macOS)
        let id = UUID().uuidString
        let requests: [HypeMCPJSONValue] = [
            .object(["jsonrpc": .string("2.0"), "id": .string("init"), "method": .string("initialize"), "params": .object([
                "protocolVersion": .string("2025-11-25"), "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("Hype"), "version": .string("1")])
            ])]),
            .object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]),
            .object(["jsonrpc": .string("2.0"), "id": .string(id), "method": .string("tools/call"), "params": .object(["name": .string(name), "arguments": .object(arguments)])])
        ]
        let data = Data((requests.map { $0.jsonString(pretty: false) }.joined(separator: "\n") + "\n").utf8)
        let runner = MCPBridgeProcess()
        let reply = try await runner.execute(executableURL: executableURL, input: data, timeout: timeout)
        guard let text = String(data: reply, encoding: .utf8) else { throw ScriptSpeechError.failed("Chatter returned invalid UTF-8.") }
        for line in text.split(separator: "\n") {
            guard let value = try? JSONDecoder().decode(HypeMCPJSONValue.self, from: Data(line.utf8)),
                  let object = value.objectValue else { throw ScriptSpeechError.failed("Chatter returned invalid MCP JSON.") }
            if let error = object["error"]?.objectValue { throw ScriptSpeechError.failed(error["message"]?.stringValue ?? "Chatter connection failed.") }
            guard object["id"] == .string(id), let result = object["result"] else { continue }
            if result.objectValue?["isError"] == .bool(true) {
                let message = result.objectValue?["content"]?.arrayValue?.compactMap { $0.objectValue?["text"]?.stringValue }.joined(separator: "\n")
                throw ScriptSpeechError.failed(message ?? "Chatter rejected the request.")
            }
            if let structured = result.objectValue?["structuredContent"] { return structured }
            if let text = result.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue,
               let decoded = try? JSONDecoder().decode(HypeMCPJSONValue.self, from: Data(text.utf8)) { return decoded }
            throw ScriptSpeechError.failed("Chatter omitted the tool result.")
        }
        throw ScriptSpeechError.failed("Chatter returned no matching MCP reply.")
        #else
        throw ScriptSpeechError.unavailable("The local Chatter bridge is available in Hype for macOS only.")
        #endif
    }
}

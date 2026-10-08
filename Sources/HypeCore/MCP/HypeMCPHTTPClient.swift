import Foundation

/// Narrow outbound Streamable HTTP client for request/response tools. Supports
/// JSON and POST SSE responses; no subprocess, auth, cookies, or disk cache.
public actor HypeMCPHTTPClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let endpoint: URL
    private let transport: Transport
    private let timeout: TimeInterval
    private var sessionID: String?
    private var protocolVersion: String?
    private static let maxResponseBytes = 4 * 1024 * 1024

    public init(endpoint: URL, timeout: TimeInterval = 30, transport: Transport? = nil) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.transport = transport ?? Self.liveTransport(timeout: timeout)
    }

    public func request(method: String, params: HypeMCPJSONValue = .object([:])) async throws -> HypeMCPJSONValue {
        try Task.checkCancellation()
        if protocolVersion == nil { try await initialize() }
        do {
            return try await send(method: method, params: params)
        } catch BraveSearchError.http(404) where sessionID != nil {
            // An expired session was rejected before execution. Establish a new
            // one, but never retry ambiguous network failures/billable calls.
            sessionID = nil
            protocolVersion = nil
            try await initialize()
            return try await send(method: method, params: params)
        }
    }

    private func initialize() async throws {
        let result = try await send(method: "initialize", params: .object([
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("Hype"), "version": .string("1.0")])
        ]))
        guard let version = result.objectValue?["protocolVersion"]?.stringValue,
              ["2025-06-18", "2025-03-26"].contains(version),
              result.objectValue?["capabilities"]?.objectValue?["tools"] != nil else {
            throw BraveSearchError.protocolError("The endpoint did not initialize a supported MCP tools server.")
        }
        protocolVersion = version
        do {
            _ = try await send(method: "notifications/initialized", params: nil, notification: true)
        } catch {
            sessionID = nil
            protocolVersion = nil
            throw error
        }
    }

    private func send(method: String, params: HypeMCPJSONValue?, notification: Bool = false) async throws -> HypeMCPJSONValue {
        let id = HypeMCPJSONValue.string(UUID().uuidString)
        var payload: [String: HypeMCPJSONValue] = ["jsonrpc": .string("2.0"), "method": .string(method)]
        if !notification { payload["id"] = id }
        if let params { payload["params"] = params }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if let protocolVersion { request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
        request.httpBody = try JSONEncoder().encode(HypeMCPJSONValue.object(payload))
        do {
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            guard (200..<300).contains(response.statusCode) else {
                throw BraveSearchError.http(response.statusCode)
            }
            guard data.count <= Self.maxResponseBytes else { throw BraveSearchError.responseTooLarge }
            if notification { return .null }
            let result = try Self.decodeResponse(data, contentType: response.value(forHTTPHeaderField: "Content-Type") ?? "", id: id)
            if method == "initialize" {
                sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id")
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            if error.code == .timedOut { throw BraveSearchError.timedOut }
            throw BraveSearchError.unavailable
        }
    }

    /// Decode SSE frames independently: notifications may precede the matching
    /// reply, data lines may be split, and CRLF is legal. Never parse snippets.
    static func decodeResponse(_ data: Data, contentType: String, id: HypeMCPJSONValue) throws -> HypeMCPJSONValue {
        guard data.count <= maxResponseBytes else { throw BraveSearchError.responseTooLarge }
        let messages: [Data]
        if contentType.lowercased().contains("text/event-stream") {
            guard let text = String(data: data, encoding: .utf8) else {
                throw BraveSearchError.protocolError("Invalid UTF-8 response.")
            }
            messages = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n\n").compactMap { frame in
                    let lines = frame.components(separatedBy: "\n").compactMap { line -> String? in
                        guard line.hasPrefix("data:") else { return nil }
                        let value = String(line.dropFirst(5))
                        return value.hasPrefix(" ") ? String(value.dropFirst()) : value
                    }
                    return lines.isEmpty ? nil : lines.joined(separator: "\n").data(using: .utf8)
                }
        } else if contentType.lowercased().contains("application/json") {
            messages = [data]
        } else {
            throw BraveSearchError.protocolError("Expected application/json or text/event-stream.")
        }
        for message in messages {
            guard let value = try? JSONDecoder().decode(HypeMCPJSONValue.self, from: message),
                  let object = value.objectValue, object["jsonrpc"] == .string("2.0") else {
                throw BraveSearchError.protocolError("Invalid JSON-RPC response.")
            }
            guard object["id"] == id else { continue }
            if let error = object["error"]?.objectValue {
                throw BraveSearchError.protocolError(error["message"]?.stringValue ?? "Request rejected.")
            }
            if let result = object["result"] { return result }
        }
        throw BraveSearchError.protocolError("No matching response from the bridge.")
    }

    private static func liveTransport(timeout: TimeInterval) -> Transport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: HypeMCPHTTPRedirectDelegate(), delegateQueue: nil)
        return { request in
            // Byte streaming bounds memory before buffering a large MCP result.
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw BraveSearchError.protocolError("Invalid HTTP response.")
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maxResponseBytes else { throw BraveSearchError.responseTooLarge }
                data.append(byte)
            }
            return (data, response)
        }
    }
}

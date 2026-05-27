import Foundation
import HypeCore
import Network

@MainActor
final class HypeMCPAppServer {
    static let shared = HypeMCPAppServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.hype.mcp.loopback")
    private let backend = HypeLiveMCPBackend()

    func startIfNeeded() {
        guard listener == nil else { return }
        if UserDefaults.standard.object(forKey: HypeMCPConfiguration.enabledKey) != nil,
           !UserDefaults.standard.bool(forKey: HypeMCPConfiguration.enabledKey) {
            return
        }

        let portText = UserDefaults.standard.string(forKey: HypeMCPConfiguration.portKey) ?? HypeMCPConfiguration.defaultPort
        let port = NWEndpoint.Port(rawValue: UInt16(portText) ?? UInt16(HypeMCPConfiguration.defaultPort)!)!

        do {
            let parameters = NWParameters.tcp
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            HypeLogger.shared.info("MCP server listening on 127.0.0.1:\(port)", source: "MCP")
        } catch {
            HypeLogger.shared.warn("Could not start MCP server: \(error.localizedDescription)", source: "MCP")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private nonisolated func accept(_ connection: NWConnection) {
        guard Self.isLoopback(endpoint: connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(connection: connection, buffer: Data())
    }

    private nonisolated static func isLoopback(endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return address == IPv4Address("127.0.0.1")
        case .ipv6(let address):
            return address == IPv6Address("::1")
        case .name(let name, _):
            let normalized = name.lowercased()
            return normalized == "localhost" || normalized == "localhost."
        @unknown default:
            return false
        }
    }

    private nonisolated func receive(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var next = buffer
            if let data { next.append(data) }
            if error != nil || isComplete {
                self.respondBadRequest(connection)
                return
            }
            if let request = HTTPRequest(data: next), request.isComplete(in: next) {
                Task { @MainActor in
                    await self.handle(request: request, connection: connection)
                }
            } else {
                self.receive(connection: connection, buffer: next)
            }
        }
    }

    private func handle(request: HTTPRequest, connection: NWConnection) async {
        guard request.path == "/mcp" || request.path == "/health" else {
            send(status: 404, body: #"{"error":"not found"}"#.data(using: .utf8)!, connection: connection)
            return
        }
        guard request.originIsAllowed else {
            send(status: 403, body: #"{"error":"origin rejected"}"#.data(using: .utf8)!, connection: connection)
            return
        }
        guard request.path == "/health" || request.isAuthorized else {
            send(status: 401, body: #"{"error":"unauthorized"}"#.data(using: .utf8)!, connection: connection)
            return
        }
        if request.path == "/health" {
            let body = #"{"ok":true,"server":"Hype MCP"}"#.data(using: .utf8)!
            send(status: 200, body: body, connection: connection)
            return
        }
        guard request.method == "POST" else {
            send(status: 405, body: #"{"error":"method not allowed"}"#.data(using: .utf8)!, connection: connection)
            return
        }
        let processor = HypeMCPProcessor(backend: backend, serverName: "Hype", serverVersion: "1.0")
        guard let response = await processor.handle(data: request.body) else {
            send(status: 204, body: Data(), connection: connection)
            return
        }
        send(status: 200, body: response, connection: connection)
    }

    private nonisolated func respondBadRequest(_ connection: NWConnection) {
        send(status: 400, body: #"{"error":"bad request"}"#.data(using: .utf8)!, connection: connection)
    }

    private nonisolated func send(status: Int, body: Data, connection: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        default: reason = "Error"
        }
        var headers = "HTTP/1.1 \(status) \(reason)\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        headers += "Content-Type: application/json\r\n"
        headers += "Connection: close\r\n\r\n"
        var payload = Data(headers.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
    var contentLength: Int

    init?(data: Data) {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ").map(String.init)
        guard requestParts.count >= 2 else { return nil }
        method = requestParts[0]
        path = requestParts[1]
        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            parsedHeaders[key] = value
        }
        headers = parsedHeaders
        contentLength = Int(parsedHeaders["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        if data.count >= bodyStart + contentLength {
            body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        } else {
            body = Data()
        }
    }

    func isComplete(in data: Data) -> Bool {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
        return data.count >= headerRange.upperBound + contentLength
    }

    var isAuthorized: Bool {
        let token = HypeMCPPreferenceStore.ensureMCPToken()
        if headers["x-hype-mcp-token"] == token { return true }
        if headers["authorization"] == "Bearer \(token)" { return true }
        return false
    }

    var originIsAllowed: Bool {
        guard let origin = headers["origin"], !origin.isEmpty else { return true }
        return origin == "null"
            || origin.hasPrefix("http://127.0.0.1")
            || origin.hasPrefix("http://localhost")
            || origin.hasPrefix("https://127.0.0.1")
            || origin.hasPrefix("https://localhost")
    }
}

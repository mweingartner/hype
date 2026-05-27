import Foundation
import HypeCore

@main
struct HypeMCPBridge {
    static func main() async {
        let port = ProcessInfo.processInfo.environment["HYPE_MCP_PORT"] ?? HypeMCPConfiguration.defaultPort
        let token = HypeMCPPreferenceStore.ensureMCPToken(defaults: HypeMCPPreferenceStore.hypeAppDefaults())

        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let requestData = Data(line.utf8)
            do {
                let response = try await post(requestData, port: port, token: token)
                if !response.isEmpty, let text = String(data: response, encoding: .utf8) {
                    print(text)
                    fflush(stdout)
                }
            } catch {
                let fallback = errorResponse(for: requestData, message: "Hype MCP bridge could not reach the running app on 127.0.0.1:\(port): \(error.localizedDescription)")
                print(fallback)
                fflush(stdout)
            }
        }
    }

    private static func post(_ data: Data, port: String, token: String?) async throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(port)/mcp") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 204 {
            return Data()
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NSError(domain: "HypeMCPBridge", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return responseData
    }

    private static func errorResponse(for requestData: Data, message: String) -> String {
        let id: Any
        if let object = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
           let requestId = object["id"] {
            id = requestId
        } else {
            id = NSNull()
        }
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": -32000,
                "message": message
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32000,"message":"Hype MCP bridge error"}}"#
        }
        return text
    }
}

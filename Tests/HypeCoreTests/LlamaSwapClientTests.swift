import Foundation
import Testing
@testable import HypeCore

private final class LlamaSwapMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "LlamaSwapMockProtocol", code: -1))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("LlamaSwapClient", .serialized)
struct LlamaSwapClientTests {
    @Test("availableModels calls /v1/models and decodes OpenAI-compatible ids")
    func availableModelsDecodesModelIDs() async throws {
        defer { LlamaSwapMockProtocol.requestHandler = nil }
        let session = Self.makeSession()
        LlamaSwapMockProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "http://localhost:8080/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            let body = """
            {
              "object": "list",
              "data": [
                { "id": "qwen3-8b", "object": "model" },
                { "id": "hypetalk-qwen3:8b-v1", "object": "model" }
              ]
            }
            """
            return (Self.response(for: request, status: 200), Data(body.utf8))
        }

        let client = try LlamaSwapClient(
            host: "localhost",
            port: "8080",
            model: "qwen3-8b",
            apiKey: "test-key",
            session: session,
            logger: HypeLogger(setupFileLogging: false)
        )

        let models = try await client.availableModels()
        #expect(models == ["qwen3-8b", "hypetalk-qwen3:8b-v1"])
    }

    @Test("generate sends /v1/responses with selected model and no Authorization when no key is set")
    func generateUsesResponsesEndpointAndSelectedModel() async throws {
        defer { LlamaSwapMockProtocol.requestHandler = nil }
        let session = Self.makeSession()
        LlamaSwapMockProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "http://localhost:8080/v1/responses")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try #require(Self.bodyData(from: request))
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["model"] as? String == "hypetalk-qwen3:8b-v1")
            #expect(object["store"] as? Bool == false)

            let response = """
            {
              "output": [
                {
                  "type": "message",
                  "content": [
                    { "type": "output_text", "text": "OK" }
                  ]
                }
              ]
            }
            """
            return (Self.response(for: request, status: 200), Data(response.utf8))
        }

        let client = try LlamaSwapClient(
            host: "localhost",
            port: "8080",
            model: "hypetalk-qwen3:8b-v1",
            session: session,
            logger: HypeLogger(setupFileLogging: false)
        )

        let text = try await client.generate(prompt: "Reply OK")
        #expect(text == "OK")
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LlamaSwapMockProtocol.self]
        return URLSession(configuration: config)
    }

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}

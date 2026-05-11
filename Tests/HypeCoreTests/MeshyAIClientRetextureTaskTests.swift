import Foundation
import Testing
@testable import HypeCore

// MARK: - Mock URLProtocol

private final class RetextureMockProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = RetextureMockProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

// MARK: - Helpers

private func makeMockClient(
    apiKey: String = "msy_test",
    handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)
) -> MeshyAIClient {
    RetextureMockProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RetextureMockProtocol.self]
    let session = URLSession(configuration: config)
    return MeshyAIClient(
        apiKey: apiKey,
        baseURL: URL(string: "http://localhost:9999")!,
        timeouts: .init(request: 10, resource: 30),
        session: session,
        logger: HypeLogger(setupFileLogging: false)
    )
}

private func response200(url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

// MARK: - Tests

@Suite("MeshyAIClient — retexture endpoint", .serialized)
struct MeshyAIClientRetextureTaskTests {

    // MARK: (a) POST /openapi/v1/retexture sends correct request

    @Test("createRetextureTask sends POST to /openapi/v1/retexture with Bearer token")
    func createRetextureTaskPostsWithBearer() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        let resp = #"{"result":"retex_task_001"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedRequest = req
            return (resp, response200(url: req.url!))
        }

        let taskId = try await client.createRetextureTask(
            MeshyRetextureRequest(inputTaskId: "source_task_abc", textStylePrompt: "rusty iron")
        )

        #expect(taskId == "retex_task_001")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer msy_test")
        #expect(capturedRequest?.url?.path.contains("/retexture") == true)
    }

    // MARK: (b) rejects empty inputTaskId

    @Test("createRetextureTask with empty inputTaskId throws validationFailed")
    func createRetextureTaskRejectsEmptyInputTaskId() async throws {
        let client = makeMockClient { req in
            Issue.record("Network request must not be made")
            return (Data(), response200(url: req.url!))
        }

        do {
            _ = try await client.createRetextureTask(
                MeshyRetextureRequest(inputTaskId: "", textStylePrompt: "wood")
            )
            Issue.record("Expected validationFailed to be thrown")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "input_task_id")
        }
    }

    // MARK: (c) rejects empty textStylePrompt

    @Test("createRetextureTask with empty textStylePrompt throws validationFailed")
    func createRetextureTaskRejectsEmptyPrompt() async throws {
        let client = makeMockClient { req in
            Issue.record("Network request must not be made")
            return (Data(), response200(url: req.url!))
        }

        do {
            _ = try await client.createRetextureTask(
                MeshyRetextureRequest(inputTaskId: "task_1", textStylePrompt: "")
            )
            Issue.record("Expected validationFailed to be thrown")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "text_style_prompt")
        }
    }

    @Test("createRetextureTask with whitespace-only textStylePrompt throws validationFailed")
    func createRetextureTaskRejectsWhitespacePrompt() async throws {
        let client = makeMockClient { req in
            Issue.record("Network request must not be made")
            return (Data(), response200(url: req.url!))
        }

        do {
            _ = try await client.createRetextureTask(
                MeshyRetextureRequest(inputTaskId: "task_1", textStylePrompt: "   ")
            )
            Issue.record("Expected validationFailed to be thrown")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "text_style_prompt")
        }
    }

    // MARK: (d) truncates textStylePrompt to 600 chars

    @Test("createRetextureTask truncates textStylePrompt to 600 chars in the encoded body")
    func createRetextureTaskTruncatesPrompt() async throws {
        nonisolated(unsafe) var capturedBody: [String: Any]?
        let resp = #"{"result":"retex_trunc"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            var bodyData: Data?
            if let direct = req.httpBody {
                bodyData = direct
            } else if let stream = req.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 4096)
                var accum = Data()
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n > 0 { accum.append(contentsOf: buffer[0..<n]) }
                }
                stream.close()
                bodyData = accum.isEmpty ? nil : accum
            }
            if let body = bodyData {
                capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return (resp, response200(url: req.url!))
        }

        let longPrompt = String(repeating: "a", count: 700)
        _ = try await client.createRetextureTask(
            MeshyRetextureRequest(inputTaskId: "task_1", textStylePrompt: longPrompt)
        )

        let sentPrompt = capturedBody?["text_style_prompt"] as? String
        #expect((sentPrompt?.count ?? 0) <= 600, "Prompt must be truncated to 600 chars (C6)")
    }

    // MARK: (e) cancelTask routes correctly

    @Test("cancelTask(.retexture) sends DELETE to /openapi/v1/retexture/<id>")
    func cancelTaskRetextureRoutes() async throws {
        nonisolated(unsafe) var capturedURL: URL?
        nonisolated(unsafe) var capturedMethod: String?

        let client = makeMockClient { req in
            capturedURL = req.url
            capturedMethod = req.httpMethod
            return (Data(), response200(url: req.url!))
        }

        try await client.cancelTask(taskId: "retex_abc", kind: .retexture)

        #expect(capturedMethod == "DELETE")
        #expect(capturedURL?.path.contains("/retexture/retex_abc") == true)
    }

    // MARK: (f) fetchTaskFact(.retexture) hits correct path

    @Test("fetchTaskFact(.retexture) hits /openapi/v1/retexture/<id>")
    func fetchTaskFactRetextureHitsCorrectPath() async throws {
        nonisolated(unsafe) var capturedPath: String?
        let pollResponse = """
        {
          "id": "retex_fetch_001",
          "status": "SUCCEEDED",
          "progress": 100,
          "model_urls": {
            "glb": "https://assets.meshy.ai/retex/001.glb"
          }
        }
        """.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedPath = req.url?.path
            return (pollResponse, response200(url: req.url!))
        }

        let fact = try await client.fetchTaskFact(taskId: "retex_fetch_001", kind: .retexture)

        #expect(capturedPath?.contains("/retexture/retex_fetch_001") == true)
        #expect(fact.taskId == "retex_fetch_001")
        #expect(fact.status == .succeeded)
    }
}

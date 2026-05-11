import Foundation
import Testing
@testable import HypeCore

// MARK: - Mock URLProtocol

private final class RemeshMockProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = RemeshMockProtocol.handler else {
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
    RemeshMockProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RemeshMockProtocol.self]
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

@Suite("MeshyAIClient — remesh endpoint", .serialized)
struct MeshyAIClientRemeshTaskTests {

    // MARK: (a) POST /openapi/v1/remesh sends Bearer + JSON

    @Test("createRemeshTask sends POST to /openapi/v1/remesh with Bearer token")
    func createRemeshTaskPostsWithBearer() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        let resp = #"{"result":"remesh_task_001"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedRequest = req
            return (resp, response200(url: req.url!))
        }

        let taskId = try await client.createRemeshTask(
            MeshyRemeshRequest(inputTaskId: "source_task_abc", targetPolycount: 5_000)
        )

        #expect(taskId == "remesh_task_001")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer msy_test")
        #expect(capturedRequest?.url?.path.contains("/remesh") == true)
    }

    // MARK: (b) rejects empty inputTaskId

    @Test("createRemeshTask with empty inputTaskId throws validationFailed")
    func createRemeshTaskRejectsEmptyInputTaskId() async throws {
        let client = makeMockClient { req in
            Issue.record("Network request must not be made for empty inputTaskId")
            return (Data(), response200(url: req.url!))
        }

        do {
            _ = try await client.createRemeshTask(
                MeshyRemeshRequest(inputTaskId: "", targetPolycount: 5_000)
            )
            Issue.record("Expected validationFailed to be thrown")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "input_task_id")
        }
    }

    @Test("createRemeshTask with whitespace-only inputTaskId throws validationFailed")
    func createRemeshTaskRejectsWhitespaceInputTaskId() async throws {
        let client = makeMockClient { req in
            Issue.record("Network request must not be made")
            return (Data(), response200(url: req.url!))
        }

        do {
            _ = try await client.createRemeshTask(
                MeshyRemeshRequest(inputTaskId: "   ", targetPolycount: 5_000)
            )
            Issue.record("Expected validationFailed to be thrown")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "input_task_id")
        }
    }

    // MARK: (c) rejects targetPolycount outside 100…300_000

    @Test("createRemeshTask rejects targetPolycount below 100")
    func createRemeshTaskRejectsPolycountTooLow() async throws {
        let client = makeMockClient { req in
            Issue.record("Network request must not be made")
            return (Data(), response200(url: req.url!))
        }

        do {
            _ = try await client.createRemeshTask(
                MeshyRemeshRequest(inputTaskId: "task_1", targetPolycount: 50)
            )
            Issue.record("Expected validationFailed or invalidPolycount to be thrown")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "target_polycount")
        } catch MeshyError.invalidPolycount {
            // Also acceptable.
        }
    }

    @Test("createRemeshTask rejects targetPolycount above 300_000")
    func createRemeshTaskRejectsPolycountTooHigh() async throws {
        let client = makeMockClient { req in
            Issue.record("Network request must not be made")
            return (Data(), response200(url: req.url!))
        }

        do {
            _ = try await client.createRemeshTask(
                MeshyRemeshRequest(inputTaskId: "task_1", targetPolycount: 400_000)
            )
            Issue.record("Expected validationFailed or invalidPolycount to be thrown")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "target_polycount")
        } catch MeshyError.invalidPolycount {
            // Also acceptable.
        }
    }

    @Test("createRemeshTask accepts boundary polycounts 100 and 300_000")
    func createRemeshTaskAcceptsBoundaryPolycounts() async throws {
        let resp = #"{"result":"remesh_task_ok"}"#.data(using: .utf8)!
        let client100 = makeMockClient { req in (resp, response200(url: req.url!)) }
        let id100 = try await client100.createRemeshTask(
            MeshyRemeshRequest(inputTaskId: "t1", targetPolycount: 100)
        )
        #expect(id100 == "remesh_task_ok")

        let client300k = makeMockClient { req in (resp, response200(url: req.url!)) }
        let id300k = try await client300k.createRemeshTask(
            MeshyRemeshRequest(inputTaskId: "t2", targetPolycount: 300_000)
        )
        #expect(id300k == "remesh_task_ok")
    }

    // MARK: (d) cancelTask routes to /openapi/v1/remesh/<id> DELETE

    @Test("cancelTask(.remesh) sends DELETE to /openapi/v1/remesh/<id>")
    func cancelTaskRemeshRoutes() async throws {
        nonisolated(unsafe) var capturedURL: URL?
        nonisolated(unsafe) var capturedMethod: String?

        let client = makeMockClient { req in
            capturedURL = req.url
            capturedMethod = req.httpMethod
            return (Data(), response200(url: req.url!))
        }

        try await client.cancelTask(taskId: "remesh_abc", kind: .remesh)

        #expect(capturedMethod == "DELETE")
        #expect(capturedURL?.path.contains("/remesh/remesh_abc") == true)
    }

    // MARK: (e) fetchTaskFact(.remesh) hits /openapi/v1/remesh/<id>

    @Test("fetchTaskFact(.remesh) hits /openapi/v1/remesh/<id> and maps to MeshyPolledFact")
    func fetchTaskFactRemeshHitsCorrectPath() async throws {
        nonisolated(unsafe) var capturedPath: String?
        let pollResponse = """
        {
          "id": "remesh_fetch_001",
          "status": "SUCCEEDED",
          "progress": 100,
          "model_urls": {
            "glb": "https://assets.meshy.ai/remesh/001.glb"
          }
        }
        """.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedPath = req.url?.path
            return (pollResponse, response200(url: req.url!))
        }

        let fact = try await client.fetchTaskFact(taskId: "remesh_fetch_001", kind: .remesh)

        #expect(capturedPath?.contains("/remesh/remesh_fetch_001") == true)
        #expect(fact.taskId == "remesh_fetch_001")
        #expect(fact.status == .succeeded)
        #expect(fact.primaryModelUrl?.absoluteString == "https://assets.meshy.ai/remesh/001.glb")
    }
}

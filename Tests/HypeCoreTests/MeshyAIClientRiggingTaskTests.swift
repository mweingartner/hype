import Foundation
import Testing
@testable import HypeCore

// MARK: - Mock URLProtocol

private final class RiggingMockProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = RiggingMockProtocol.handler else {
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
    RiggingMockProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RiggingMockProtocol.self]
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

private func response404(url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
}

// MARK: - Tests

@Suite("MeshyAIClient — rigging endpoint", .serialized)
struct MeshyAIClientRiggingTaskTests {

    // MARK: (a) POST /openapi/v1/rigging sends Bearer + JSON

    @Test("createRiggingTask sends POST to /openapi/v1/rigging with Bearer token")
    func createRiggingTaskPostsWithBearer() async throws {
        var capturedRequest: URLRequest?
        let resp = #"{"result":"rig_task_001"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedRequest = req
            return (resp, response200(url: req.url!))
        }

        let request = MeshyRiggingRequest(inputTaskId: "base_task_123")
        let taskId = try await client.createRiggingTask(request)

        #expect(taskId == "rig_task_001")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer msy_test")
        #expect(capturedRequest?.url?.path.contains("/rigging") == true)
    }

    @Test("createRiggingTask encodes input_task_id in request body")
    func createRiggingTaskEncodesBody() async throws {
        nonisolated(unsafe) var capturedBody: [String: Any]?
        let resp = #"{"result":"rig_task_002"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            // URLSession may deliver the body via httpBodyStream rather than httpBody.
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

        let request = MeshyRiggingRequest(inputTaskId: "source_task_xyz", heightMeters: 1.75)
        _ = try await client.createRiggingTask(request)

        #expect(capturedBody?["input_task_id"] as? String == "source_task_xyz")
        #expect(capturedBody?["height_meters"] as? Double == 1.75)
        #expect(capturedBody?["model_url"] == nil, "model_url must never be sent (SSRF prevention H2)")
    }

    // MARK: (b) response parsed

    @Test("createRiggingTask parses result task id from 200 response")
    func createRiggingTaskParsesResult() async throws {
        let resp = #"{"result":"rig_task_parsed"}"#.data(using: .utf8)!
        let client = makeMockClient { req in (resp, response200(url: req.url!)) }

        let taskId = try await client.createRiggingTask(
            MeshyRiggingRequest(inputTaskId: "base_task_1")
        )
        #expect(taskId == "rig_task_parsed")
    }

    // MARK: (c) createRiggingTask rejects empty inputTaskId with validationFailed

    @Test("createRiggingTask with empty inputTaskId throws validationFailed")
    func createRiggingTaskWithEmptyInputTaskId() async throws {
        // MeshyAIClient validates inputTaskId before issuing the network request.
        let client = makeMockClient { req in
            Issue.record("Network request must not be made for empty inputTaskId")
            return (Data(), response200(url: req.url!))
        }

        do {
            _ = try await client.createRiggingTask(MeshyRiggingRequest(inputTaskId: ""))
            Issue.record("Expected validationFailed to be thrown")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "input_task_id")
        }
    }

    // MARK: (d) cancellation routes to /openapi/v1/rigging/<id> DELETE

    @Test("cancelTask(.rigging) sends DELETE to /openapi/v1/rigging/<id>")
    func cancelTaskRiggingRoutes() async throws {
        var capturedURL: URL?
        var capturedMethod: String?

        let client = makeMockClient { req in
            capturedURL = req.url
            capturedMethod = req.httpMethod
            return (Data(), response200(url: req.url!))
        }

        try await client.cancelTask(taskId: "rig_task_cancel_01", kind: .rigging)

        #expect(capturedMethod == "DELETE")
        let path = capturedURL?.path ?? ""
        #expect(path.contains("/rigging/rig_task_cancel_01"),
                "DELETE must hit /openapi/v1/rigging/<id> for .rigging kind, got: \(path)")
    }

    @Test("cancelTask(.animation) sends DELETE to /openapi/v1/animations/<id>")
    func cancelTaskAnimationRoutes() async throws {
        var capturedURL: URL?
        var capturedMethod: String?

        let client = makeMockClient { req in
            capturedURL = req.url
            capturedMethod = req.httpMethod
            return (Data(), response200(url: req.url!))
        }

        try await client.cancelTask(taskId: "anim_task_cancel_01", kind: .animation)

        #expect(capturedMethod == "DELETE")
        let path = capturedURL?.path ?? ""
        #expect(path.contains("/animations/anim_task_cancel_01"),
                "DELETE must hit /openapi/v1/animations/<id> for .animation kind, got: \(path)")
    }
}

import Foundation
import Testing
@testable import HypeCore

// MARK: - Mock URLProtocol

private final class AnimTaskMockProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = AnimTaskMockProtocol.handler else {
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
    AnimTaskMockProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AnimTaskMockProtocol.self]
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

@Suite("MeshyAIClient — animation endpoint", .serialized)
struct MeshyAIClientAnimationTaskTests {

    // MARK: (a) POST /openapi/v1/animations

    @Test("createAnimationTask sends POST to /openapi/v1/animations with Bearer token")
    func createAnimationTaskPostsWithBearer() async throws {
        var capturedRequest: URLRequest?
        let resp = #"{"result":"anim_task_001"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedRequest = req
            return (resp, response200(url: req.url!))
        }

        let request = MeshyAnimationRequest(rigTaskId: "rig_task_001", actionId: 42)
        let taskId = try await client.createAnimationTask(request)

        #expect(taskId == "anim_task_001")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer msy_test")
        #expect(capturedRequest?.url?.path.contains("/animations") == true)
    }

    // MARK: (b) rig_task_id and action_id encoded

    @Test("createAnimationTask encodes rig_task_id and action_id in request body")
    func createAnimationTaskEncodesBody() async throws {
        nonisolated(unsafe) var capturedBody: [String: Any]?
        let resp = #"{"result":"anim_task_002"}"#.data(using: .utf8)!

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

        let request = MeshyAnimationRequest(rigTaskId: "rig_task_abc", actionId: 99)
        _ = try await client.createAnimationTask(request)

        #expect(capturedBody?["rig_task_id"] as? String == "rig_task_abc")
        #expect(capturedBody?["action_id"] as? Int == 99)
    }

    // MARK: (c) cancel routes to /openapi/v1/animations/<id>

    @Test("cancelTask(.animation) sends DELETE to /openapi/v1/animations/<id>")
    func cancelTaskAnimationDeleteRoute() async throws {
        var capturedURL: URL?
        var capturedMethod: String?

        let client = makeMockClient { req in
            capturedURL = req.url
            capturedMethod = req.httpMethod
            return (Data(), response200(url: req.url!))
        }

        try await client.cancelTask(taskId: "anim_task_xyz", kind: .animation)

        #expect(capturedMethod == "DELETE")
        let path = capturedURL?.path ?? ""
        #expect(path.contains("/animations/anim_task_xyz"),
                "DELETE must target /openapi/v1/animations/<id>, got: \(path)")
    }
}

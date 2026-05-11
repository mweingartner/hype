import Foundation
import Testing
@testable import HypeCore

// MARK: - Mock URLProtocol

private final class FetchKindMockProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = FetchKindMockProtocol.handler else {
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

private func makeMockClient(
    handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)
) -> MeshyAIClient {
    FetchKindMockProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FetchKindMockProtocol.self]
    let session = URLSession(configuration: config)
    return MeshyAIClient(
        apiKey: "msy_test",
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

@Suite("MeshyAIClient — fetchTaskFact kind routing (H1)", .serialized)
struct MeshyAIClientFetchTaskKindRoutingTests {

    // MARK: (a) .textTo3D → /openapi/v2/text-to-3d/<id>

    @Test("fetchTaskFact(.textTo3D) requests /openapi/v2/text-to-3d/<id>")
    func fetchTextTo3DRoutesCorrectly() async throws {
        var capturedURL: URL?

        let body = #"{"id":"task_001","status":"IN_PROGRESS","progress":50}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedURL = req.url
            return (body, response200(url: req.url!))
        }

        _ = try await client.fetchTaskFact(taskId: "task_001", kind: .textTo3D)

        let path = capturedURL?.path ?? ""
        #expect(path.contains("/v2/text-to-3d/task_001"),
                ".textTo3D must route to /openapi/v2/text-to-3d/<id>, got: \(path)")
    }

    // MARK: (b) .imageTo3D → /openapi/v1/image-to-3d/<id>

    @Test("fetchTaskFact(.imageTo3D) requests /openapi/v1/image-to-3d/<id>")
    func fetchImageTo3DRoutesCorrectly() async throws {
        var capturedURL: URL?

        let body = #"{"id":"img_task_001","status":"IN_PROGRESS","progress":30}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedURL = req.url
            return (body, response200(url: req.url!))
        }

        _ = try await client.fetchTaskFact(taskId: "img_task_001", kind: .imageTo3D)

        let path = capturedURL?.path ?? ""
        #expect(path.contains("/v1/image-to-3d/img_task_001"),
                ".imageTo3D must route to /openapi/v1/image-to-3d/<id>, got: \(path)")
    }

    // MARK: (c) .rigging → /openapi/v1/rigging/<id>

    @Test("fetchTaskFact(.rigging) requests /openapi/v1/rigging/<id>")
    func fetchRiggingRoutesCorrectly() async throws {
        var capturedURL: URL?

        let body = #"{"id":"rig_001","status":"IN_PROGRESS","progress":60}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedURL = req.url
            return (body, response200(url: req.url!))
        }

        _ = try await client.fetchTaskFact(taskId: "rig_001", kind: .rigging)

        let path = capturedURL?.path ?? ""
        #expect(path.contains("/v1/rigging/rig_001"),
                ".rigging must route to /openapi/v1/rigging/<id>, got: \(path)")
    }

    // MARK: (d) .animation → /openapi/v1/animations/<id>

    @Test("fetchTaskFact(.animation) requests /openapi/v1/animations/<id>")
    func fetchAnimationRoutesCorrectly() async throws {
        var capturedURL: URL?

        let body = #"{"id":"anim_001","status":"IN_PROGRESS","progress":70}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedURL = req.url
            return (body, response200(url: req.url!))
        }

        _ = try await client.fetchTaskFact(taskId: "anim_001", kind: .animation)

        let path = capturedURL?.path ?? ""
        #expect(path.contains("/v1/animations/anim_001"),
                ".animation must route to /openapi/v1/animations/<id>, got: \(path)")
    }
}

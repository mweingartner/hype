import Foundation
import Testing
@testable import HypeCore

// MARK: - Mock URLProtocol (local to this file)

private final class ImageTaskMockProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = ImageTaskMockProtocol.handler else {
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
    ImageTaskMockProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ImageTaskMockProtocol.self]
    let session = URLSession(configuration: config)
    return MeshyAIClient(
        apiKey: apiKey,
        baseURL: URL(string: "http://localhost:9999")!,
        timeouts: .init(request: 10, resource: 30),
        session: session,
        logger: HypeLogger(setupFileLogging: false)
    )
}

private func response200(url: URL = URL(string: "http://localhost:9999")!) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

// MARK: - Tests

@Suite("MeshyAIClient — image endpoints", .serialized)
struct MeshyAIClientImageTaskTests {

    // MARK: (a) POST /openapi/v1/image-to-3d sends Bearer + JSON

    @Test("createImageTo3DTask posts to /openapi/v1/image-to-3d with Bearer")
    func imageTaskPostsWithBearer() async throws {
        var capturedRequest: URLRequest?
        let resp = #"{"result":"img_task_001"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedRequest = req
            return (resp, response200(url: req.url!))
        }

        let dataURI = "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())"
        let request = MeshyImageTo3DRequest(imageData: dataURI)
        _ = try await client.createImageTo3DTask(request)

        #expect(capturedRequest?.url?.path == "/openapi/v1/image-to-3d")
        let auth = capturedRequest?.value(forHTTPHeaderField: "Authorization") ?? ""
        #expect(auth == "Bearer msy_test")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // MARK: (b) Response parsed as MeshyCreateTaskResponse

    @Test("createImageTo3DTask returns parsed task id")
    func imageTaskReturnsTaskId() async throws {
        let resp = #"{"result":"img_task_abc"}"#.data(using: .utf8)!
        let client = makeMockClient { req in (resp, response200(url: req.url!)) }

        let dataURI = "data:image/png;base64,abc123"
        let request = MeshyImageTo3DRequest(imageData: dataURI)
        let taskId = try await client.createImageTo3DTask(request)
        #expect(taskId == "img_task_abc")
    }

    // MARK: (c) POST /openapi/v1/multi-image-to-3d likewise

    @Test("createMultiImageTo3DTask posts to /openapi/v1/multi-image-to-3d")
    func multiImageTaskPosts() async throws {
        var capturedPath: String?
        let resp = #"{"result":"multi_task_001"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            capturedPath = req.url?.path
            return (resp, response200(url: req.url!))
        }

        let uris = ["data:image/png;base64,aaa", "data:image/png;base64,bbb"]
        let request = MeshyMultiImageTo3DRequest(imageData: uris)
        let taskId = try await client.createMultiImageTo3DTask(request)
        #expect(capturedPath == "/openapi/v1/multi-image-to-3d")
        #expect(taskId == "multi_task_001")
    }

    // MARK: (d) multi-image with 1 image throws validationFailed

    @Test("createMultiImageTo3DTask with 1 image throws validationFailed")
    func multiImageWith1Throws() async throws {
        let client = makeMockClient { req in (Data(), response200(url: req.url!)) }
        let request = MeshyMultiImageTo3DRequest(imageData: ["data:image/png;base64,only_one"])
        do {
            _ = try await client.createMultiImageTo3DTask(request)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_urls")
        }
    }

    // MARK: (e) multi-image with 5 images throws validationFailed

    @Test("createMultiImageTo3DTask with 5 images throws validationFailed")
    func multiImageWith5Throws() async throws {
        let client = makeMockClient { req in (Data(), response200(url: req.url!)) }
        let uris = (0..<5).map { "data:image/png;base64,img\($0)" }
        let request = MeshyMultiImageTo3DRequest(imageData: uris)
        do {
            _ = try await client.createMultiImageTo3DTask(request)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_urls")
        }
    }

    // MARK: (e2) Phase 2 Defect 2 — client-layer combined size cap (defense in depth)

    @Test("createMultiImageTo3DTask rejects combined-body size > 57 MB (Phase 2 Defect 2)")
    func multiImageCombinedSizeCapEnforced() async throws {
        let client = makeMockClient { req in (Data(), response200(url: req.url!)) }
        // Build 3 data URIs each ~20 MB of encoded text → ~60 MB combined,
        // safely over the 57 MB cap.
        let oneURI = "data:image/png;base64," + String(repeating: "A", count: 20 * 1024 * 1024)
        let uris = [oneURI, oneURI, oneURI]
        let request = MeshyMultiImageTo3DRequest(imageData: uris)
        do {
            _ = try await client.createMultiImageTo3DTask(request)
            Issue.record("Expected validationFailed for combined cap")
        } catch MeshyError.validationFailed(let field, let reason) {
            #expect(field == "image_urls")
            #expect(reason.contains("40 MB") || reason.contains("limit"))
        }
    }

    // MARK: (f) image data URI is reflected verbatim in the request body

    @Test("createImageTo3DTask encodes image_url verbatim in request body")
    func imageDataVerbatimInBody() async throws {
        let specificURI = "data:image/png;base64,VGVzdERhdGE="
        nonisolated(unsafe) var capturedBody: [String: Any]?
        let resp = #"{"result":"task_f"}"#.data(using: .utf8)!

        let client = makeMockClient { req in
            // URLSession may deliver body via httpBodyStream instead of httpBody.
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

        let request = MeshyImageTo3DRequest(imageData: specificURI)
        _ = try await client.createImageTo3DTask(request)
        // Wire field must be `image_url` (NOT `image_data`) per Meshy v1
        // image-to-3D spec; sending `image_data` returns "Either image_url
        // or input_task_id must be provided".
        #expect(capturedBody?["image_url"] as? String == specificURI)
        #expect(capturedBody?["image_data"] == nil, "image_data must NOT appear on the wire")
    }

    // MARK: (g) createImageTo3DTask with non-data-URI throws validationFailed

    @Test("createImageTo3DTask with non-data-URI throws validationFailed")
    func imageTaskRejectsNonDataURI() async throws {
        let client = makeMockClient { req in (Data(), response200(url: req.url!)) }
        let request = MeshyImageTo3DRequest(imageData: "https://example.com/image.png")
        do {
            _ = try await client.createImageTo3DTask(request)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_url")
        }
    }

    // MARK: (h) cancelTask routes to correct v1 path for .imageTo3D

    @Test("cancelTask with kind .imageTo3D routes to /openapi/v1/image-to-3d")
    func cancelTaskRoutesImageTo3D() async throws {
        var capturedPath: String?
        let client = makeMockClient { req in
            capturedPath = req.url?.path
            return (Data(), response200(url: req.url!))
        }
        try await client.cancelTask(taskId: "task_img_001", kind: .imageTo3D)
        #expect(capturedPath?.hasPrefix("/openapi/v1/image-to-3d/") == true)
    }

    // MARK: (i) cancelTask routes to correct v1 path for .multiImageTo3D

    @Test("cancelTask with kind .multiImageTo3D routes to /openapi/v1/multi-image-to-3d")
    func cancelTaskRoutesMultiImageTo3D() async throws {
        var capturedPath: String?
        let client = makeMockClient { req in
            capturedPath = req.url?.path
            return (Data(), response200(url: req.url!))
        }
        try await client.cancelTask(taskId: "task_multi_001", kind: .multiImageTo3D)
        #expect(capturedPath?.hasPrefix("/openapi/v1/multi-image-to-3d/") == true)
    }

    // MARK: (j) cancelTask routes to v2 path for .textTo3D

    @Test("cancelTask with kind .textTo3D routes to /openapi/v2/text-to-3d")
    func cancelTaskRoutesTextTo3D() async throws {
        var capturedPath: String?
        let client = makeMockClient { req in
            capturedPath = req.url?.path
            return (Data(), response200(url: req.url!))
        }
        try await client.cancelTask(taskId: "task_text_001", kind: .textTo3D)
        #expect(capturedPath?.hasPrefix("/openapi/v2/text-to-3d/") == true)
    }

    // MARK: (k) v1-style {"id":"..."} response is decoded correctly (OQ-B2)

    @Test("createImageTo3DTask decodes v1-style {id:} response")
    func imageTaskDecodesIdField() async throws {
        let resp = #"{"id":"v1_task_xyz"}"#.data(using: .utf8)!
        let client = makeMockClient { req in (resp, response200(url: req.url!)) }
        let request = MeshyImageTo3DRequest(imageData: "data:image/png;base64,abc")
        let taskId = try await client.createImageTo3DTask(request)
        #expect(taskId == "v1_task_xyz")
    }
}

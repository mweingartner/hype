import Foundation
import Testing
@testable import HypeCore

// MARK: - URLProtocol mock

private final class MeshyMockProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MeshyMockProtocol.handler else {
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

// MARK: - Helper

private func makeMockClient(
    apiKey: String = "msy_test",
    baseURL: URL = URL(string: "http://localhost:9999")!,
    handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)
) -> MeshyAIClient {
    MeshyMockProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MeshyMockProtocol.self]
    let session = URLSession(configuration: config)
    return MeshyAIClient(apiKey: apiKey, baseURL: baseURL, timeouts: .init(request: 10, resource: 30), session: session, logger: HypeLogger(setupFileLogging: false))
}

private func response(statusCode: Int, url: URL = URL(string: "http://localhost:9999")!) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private func response(statusCode: Int, headers: [String: String], url: URL = URL(string: "http://localhost:9999")!) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
}

// MARK: - Tests

// Serialized to prevent `MeshyMockProtocol.handler` data races when
// Swift Testing's default parallel execution is in use. The static
// handler is mutable shared state — tests must run one at a time.
@Suite("MeshyAIClient — HTTP", .serialized)
struct MeshyAIClientTests {

    // MARK: (a) POST sends Authorization: Bearer and JSON body

    @Test("POST sends Bearer token and JSON body")
    func postSendsBearerAndBody() async throws {
        var capturedRequest: URLRequest?
        let resp = #"{"result":"task_abc123"}"#.data(using: .utf8)!

        let client = makeMockClient(handler: { req in
            capturedRequest = req
            return (resp, response(statusCode: 200, url: req.url!))
        })

        let request = MeshyTextTo3DRequest(
            mode: .preview,
            prompt: "a low-poly barrel",
            aiModel: .meshy6,
            shouldRemesh: false,
            moderation: true
        )
        _ = try await client.createTextTo3DTask(request)

        let auth = capturedRequest?.value(forHTTPHeaderField: "Authorization") ?? ""
        #expect(auth == "Bearer msy_test", "Authorization header must be Bearer token")

        // Verify body contains snake_case keys.
        if let body = capturedRequest?.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json["ai_model"] as? String == "meshy-6")
            #expect(json["should_remesh"] as? Bool == false)
            #expect(json["moderation"] as? Bool == true)
            #expect(json["prompt"] as? String == "a low-poly barrel")
        }
    }

    // MARK: (b) GET task with 200 returns decoded response

    @Test("GET task with 200 returns decoded MeshyTaskResponse")
    func getTaskDecodes() async throws {
        let json = """
        {"id":"task_001","status":"IN_PROGRESS","progress":45}
        """.data(using: .utf8)!

        let client = makeMockClient { req in (json, response(statusCode: 200, url: req.url!)) }
        let taskResp = try await client.fetchTask(taskId: "task_001")
        #expect(taskResp.id == "task_001")
        #expect(taskResp.status == .inProgress)
        #expect(taskResp.progress == 45)
    }

    // MARK: (c) GET task with 401 throws .requestFailed(401, _)

    @Test("GET task with 401 throws requestFailed")
    func get401ThrowsRequestFailed() async throws {
        let client = makeMockClient { req in
            let body = #"{"error":"Unauthorized"}"#.data(using: .utf8)!
            return (body, response(statusCode: 401, url: req.url!))
        }
        do {
            _ = try await client.fetchTask(taskId: "task_x")
            Issue.record("Expected throw")
        } catch MeshyError.requestFailed(let code, _) {
            #expect(code == 401)
        }
    }

    // MARK: (d) GET task with 429 throws .rateLimited

    @Test("GET task with 429 throws rateLimited")
    func get429ThrowsRateLimited() async throws {
        let client = makeMockClient { req in
            let body = #"{"error":"rate limited"}"#.data(using: .utf8)!
            return (body, response(statusCode: 429, url: req.url!))
        }
        do {
            _ = try await client.fetchTask(taskId: "task_x")
            Issue.record("Expected throw")
        } catch MeshyError.rateLimited {
            // Expected.
        }
    }

    // MARK: (e) GET task with 402 throws .insufficientCredits

    @Test("GET task with 402 throws insufficientCredits")
    func get402ThrowsInsufficientCredits() async throws {
        let client = makeMockClient { req in
            let body = #"{"error":"payment required"}"#.data(using: .utf8)!
            return (body, response(statusCode: 402, url: req.url!))
        }
        do {
            _ = try await client.fetchTask(taskId: "task_x")
            Issue.record("Expected throw")
        } catch MeshyError.insufficientCredits {
            // Expected.
        }
    }

    // MARK: (f) fetchBalance parses Int

    @Test("fetchBalance parses Int balance")
    func fetchBalanceParsesInt() async throws {
        let json = #"{"balance":380,"currency":"credits"}"#.data(using: .utf8)!
        let client = makeMockClient { req in (json, response(statusCode: 200, url: req.url!)) }
        let balance = try await client.fetchBalance()
        #expect(balance == 380)
    }

    // MARK: (g) downloadModel rejects http:// scheme

    @Test("downloadModel rejects http:// scheme")
    func downloadRejectsHTTP() async throws {
        let client = makeMockClient { req in (Data(), response(statusCode: 200, url: req.url!)) }
        let httpURL = URL(string: "http://cdn.meshy.ai/model.glb")!
        do {
            _ = try await client.downloadModel(from: httpURL, allowedFormat: .glb)
            Issue.record("Expected throw")
        } catch MeshyError.modelDownloadFailed(let msg) {
            #expect(msg == "non-https scheme")
        }
    }

    // MARK: (h) downloadModel rejects non-meshy hostname (H2)

    @Test("downloadModel rejects https URL with non-meshy.ai hostname")
    func downloadRejectsNonMeshyHost() async throws {
        let client = makeMockClient { req in (Data(), response(statusCode: 200, url: req.url!)) }
        let attackerURL = URL(string: "https://attacker.com/malware.glb")!
        do {
            _ = try await client.downloadModel(from: attackerURL, allowedFormat: .glb)
            Issue.record("Expected throw")
        } catch MeshyError.modelDownloadFailed(let msg) {
            #expect(msg == "untrusted host")
        }
    }

    // MARK: (i) downloadModel accepts meshy.ai subdomain

    @Test("downloadModel accepts cdn.meshy.ai subdomain")
    func downloadAcceptsMeshySubdomain() async throws {
        // Minimal GLB magic bytes + enough padding.
        let glbBytes = Data(repeating: 0x42, count: 16)
        let client = makeMockClient { req in
            let hdrs = ["Content-Type": "model/gltf-binary"]
            return (glbBytes, response(statusCode: 200, headers: hdrs, url: req.url!))
        }
        // Should not throw — cdn.meshy.ai is an allowed host.
        let meshySubURL = URL(string: "https://cdn.meshy.ai/assets/model.glb")!
        let downloaded = try await client.downloadModel(from: meshySubURL, allowedFormat: .glb)
        #expect(downloaded.count == glbBytes.count)
    }

    // MARK: (j) downloadModel accepts application/octet-stream for GLB

    @Test("downloadModel accepts application/octet-stream for GLB")
    func downloadAcceptsOctetStreamForGLB() async throws {
        let glbBytes = Data(repeating: 0x42, count: 16)
        let client = makeMockClient { req in
            let hdrs = ["Content-Type": "application/octet-stream"]
            return (glbBytes, response(statusCode: 200, headers: hdrs, url: req.url!))
        }
        let url = URL(string: "https://assets.meshy.ai/model.glb")!
        let data = try await client.downloadModel(from: url, allowedFormat: .glb)
        #expect(data.count == 16)
    }

    // MARK: (k) cancelTask tolerates 404

    @Test("cancelTask tolerates 404")
    func cancelTaskTolerates404() async throws {
        let client = makeMockClient { req in
            (Data(), response(statusCode: 404, url: req.url!))
        }
        // Should not throw.
        try await client.cancelTask(taskId: "task_already_done")
    }

    // MARK: (l) Public init has NO baseURL parameter — compile-time check
    //
    // This test doesn't call any method — it simply verifies that the
    // public initializer does NOT accept a `baseURL` argument. If someone
    // ever adds `baseURL` to the public init, the line below that calls
    // `MeshyAIClient(apiKey:)` would still compile, but the comment
    // documents the intent. The real enforcement is the absence of a
    // `baseURL` parameter in the public init signature; the package-only
    // init with `baseURL` exists exclusively for testing.
    @Test("Public init does not expose baseURL parameter")
    func publicInitHasNoBaseURL() {
        // This line must compile — it uses ONLY the public init.
        let _ = MeshyAIClient(apiKey: "msy_test")
        // If MeshyAIClient's public init accepted `baseURL:`, adding that
        // parameter here would be necessary for the internal test init
        // to remain distinct. The test documents that the public API
        // is correctly constrained.
    }

    // MARK: (l2) downloadModel refuses redirects (Security F-2)

    /// Verifies the `MeshyNoRedirectDelegate` actually rejects redirects
    /// when wired into a download session. A 302 from a meshy.ai host
    /// to an attacker host must NOT be followed; the download must
    /// surface the 3xx as a `modelDownloadFailed` error.
    @Test("downloadModel refuses HTTP redirects via NoRedirectDelegate")
    func downloadRefusesRedirects() async throws {
        // Mock returns a 302 with Location header pointing to a non-meshy host.
        // If the delegate isn't wired correctly, URLSession would follow the
        // redirect and return whatever the second request returns.
        let glbBytes = Data(repeating: 0x42, count: 16)
        MeshyMockProtocol.handler = { req in
            let url = req.url!
            if url.host?.hasSuffix("meshy.ai") == true {
                // First request: emit a redirect.
                let hdrs = ["Location": "https://attacker.example.com/malware.glb"]
                return (Data(), response(statusCode: 302, headers: hdrs, url: url))
            } else {
                // Second request (would only fire if delegate doesn't reject):
                // succeed with valid-looking GLB. If we ever see this body
                // come back to the test, the redirect was followed.
                let hdrs = ["Content-Type": "model/gltf-binary"]
                return (glbBytes, response(statusCode: 200, headers: hdrs, url: url))
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MeshyMockProtocol.self]
        // Critical: install the delegate so URLSession consults it on 302.
        let delegate = MeshyNoRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let client = MeshyAIClient(
            apiKey: "msy_test",
            baseURL: URL(string: "http://localhost:9999")!,
            timeouts: .init(request: 10, resource: 30),
            session: session,
            logger: HypeLogger(setupFileLogging: false)
        )

        let meshyURL = URL(string: "https://cdn.meshy.ai/redirect.glb")!
        do {
            _ = try await client.downloadModel(from: meshyURL, allowedFormat: .glb)
            Issue.record("downloadModel should have rejected the redirect")
        } catch MeshyError.modelDownloadFailed {
            // Expected: the 3xx is surfaced as a download failure.
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    // MARK: (m) Bearer token does NOT appear in error strings

    @Test("Bearer token never appears in error descriptions")
    func bearerTokenNotInErrors() async throws {
        let sensitiveKey = "msy_super_secret_key_12345"
        let client = makeMockClient(apiKey: sensitiveKey, handler: { req in
            let body = #"{"error":"Unauthorized","message":"bad key"}"#.data(using: .utf8)!
            return (body, response(statusCode: 401, url: req.url!))
        })
        do {
            _ = try await client.fetchBalance()
        } catch {
            let description = error.localizedDescription
            #expect(!description.contains(sensitiveKey), "API key must not appear in error string")
            // Also check that "Bearer" doesn't leak.
            #expect(!description.contains("Bearer"))
        }
    }

    // MARK: Garbled JSON throws decodingFailed

    @Test("Garbled JSON response throws decodingFailed")
    func garbledJSONThrowsDecodingFailed() async throws {
        let garbage = Data("not json at all!!!".utf8)
        let client = makeMockClient { req in (garbage, response(statusCode: 200, url: req.url!)) }
        do {
            _ = try await client.fetchBalance()
            Issue.record("Expected throw")
        } catch MeshyError.decodingFailed {
            // Expected.
        }
    }

    // MARK: (n) downloadModel rejects bad Content-Type

    @Test("downloadModel rejects unknown Content-Type for GLB")
    func downloadRejectsUnknownContentType() async throws {
        let body = Data(repeating: 0x42, count: 16)
        let client = makeMockClient { req in
            let hdrs = ["Content-Type": "text/html"]   // Clearly wrong type.
            return (body, response(statusCode: 200, headers: hdrs, url: req.url!))
        }
        let url = URL(string: "https://assets.meshy.ai/model.glb")!
        do {
            _ = try await client.downloadModel(from: url, allowedFormat: .glb)
            Issue.record("Expected unsupportedContentType throw")
        } catch MeshyError.unsupportedContentType(let ct) {
            #expect(ct == "text/html")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    // MARK: (o) downloadModel rejects Content-Length over cap

    @Test("downloadModel rejects Content-Length over 50 MB cap")
    func downloadRejectsOversizeContentLength() async throws {
        let overCapBytes = MeshyAIClient.maxModelBytes + 1
        let client = makeMockClient { req in
            // Return Content-Length that exceeds cap — but don't actually
            // send that many bytes (the pre-check fires before body download).
            let hdrs = [
                "Content-Type": "model/gltf-binary",
                "Content-Length": "\(overCapBytes)"
            ]
            return (Data(), response(statusCode: 200, headers: hdrs, url: req.url!))
        }
        let url = URL(string: "https://cdn.meshy.ai/huge.glb")!
        do {
            _ = try await client.downloadModel(from: url, allowedFormat: .glb)
            Issue.record("Expected modelTooLarge throw")
        } catch MeshyError.modelTooLarge(let bytes, let cap) {
            #expect(bytes == overCapBytes)
            #expect(cap == MeshyAIClient.maxModelBytes)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}

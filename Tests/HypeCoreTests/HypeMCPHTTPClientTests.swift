import Foundation
import Testing
@testable import HypeCore

@Suite("Outbound MCP Streamable HTTP codec")
struct HypeMCPHTTPClientTests {
    @Test("JSON, multiline SSE, CRLF, and preceding notifications")
    func responseFormats() throws {
        let id = HypeMCPJSONValue.string("abc")
        let json = #"{"jsonrpc":"2.0","id":"abc","result":{"sources":["https://example.org/"]}}"#
        let expected: HypeMCPJSONValue = .object(["sources": .array([.string("https://example.org/")])])
        #expect(try HypeMCPHTTPClient.decodeResponse(Data(json.utf8), contentType: "application/json; charset=utf-8", id: id) == expected)
        let sse = ": keepalive\r\n\r\nevent: message\r\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\r\n\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":\"abc\",\r\ndata: \"result\":{\"sources\":[\"https://example.org/\"]}}\r\n\r\n"
        #expect(try HypeMCPHTTPClient.decodeResponse(Data(sse.utf8), contentType: "text/event-stream", id: id) == expected)
    }

    @Test("Mismatched IDs, malformed messages, and JSON-RPC errors fail clearly")
    func rejectsMalformed() {
        for json in [#"{"jsonrpc":"2.0","id":"other","result":{}}"#, #"{"jsonrpc":"2.0","id":"abc","error":{"code":-32602,"message":"Invalid query"}}"#, "{}", "[]", "not json"] {
            #expect(throws: BraveSearchError.self) {
                try HypeMCPHTTPClient.decodeResponse(Data(json.utf8), contentType: "application/json", id: .string("abc"))
            }
        }
        #expect(throws: BraveSearchError.self) {
            try HypeMCPHTTPClient.decodeResponse(Data("{}".utf8), contentType: "text/html", id: .string("abc"))
        }
    }

    @Test("Seeded arbitrary protocol bytes never crash or masquerade as a reply")
    func malformedProperty() {
        var seed: UInt64 = 0xB4A7E
        for length in 0..<512 {
            let bytes = (0..<length).map { _ -> UInt8 in
                seed = seed &* 6364136223846793005 &+ 1
                return UInt8(truncatingIfNeeded: seed >> 32)
            }
            for type in ["application/json", "text/event-stream"] {
                #expect(throws: BraveSearchError.self) {
                    try HypeMCPHTTPClient.decodeResponse(Data(bytes), contentType: type, id: .string("property-test"))
                }
            }
        }
    }

    @Test("Oversized responses are bounded")
    func responseLimit() {
        #expect(throws: BraveSearchError.self) {
            try HypeMCPHTTPClient.decodeResponse(Data(repeating: 32, count: 4 * 1024 * 1024 + 1), contentType: "application/json", id: .string("test"))
        }
    }

    @Test("Real HTTP deadlines, cancellation, redirects, and expired sessions", .enabled(if: ProcessInfo.processInfo.environment["HYPE_BRAVE_FIXTURE_URL"] != nil))
    func realTransport() async throws {
        let base = try #require(ProcessInfo.processInfo.environment["HYPE_BRAVE_FIXTURE_URL"])
        let stalled = HypeMCPHTTPClient(endpoint: try #require(URL(string: base + "/stall")), timeout: 0.3)
        let start = ContinuousClock.now
        do {
            _ = try await stalled.request(method: "tools/list")
            Issue.record("Stalled server should time out")
        } catch BraveSearchError.timedOut {
            #expect(start.duration(to: .now) < .seconds(3))
        }

        let cancelled = HypeMCPHTTPClient(endpoint: try #require(URL(string: base + "/stall")), timeout: 30)
        let task = Task { try await cancelled.request(method: "tools/list") }
        try await Task.sleep(for: .milliseconds(150))
        let cancelStart = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Stalled request should cancel")
        } catch is CancellationError {
            #expect(cancelStart.duration(to: .now) < .seconds(3))
        }

        let redirected = HypeMCPHTTPClient(endpoint: try #require(URL(string: base + "/redirect")))
        do {
            _ = try await redirected.request(method: "tools/list")
            Issue.record("Bridge redirects should be refused")
        } catch BraveSearchError.http(let status) {
            #expect(status == 307)
        }

        let expired = HypeMCPHTTPClient(endpoint: try #require(URL(string: base + "/expired")))
        let result = try await expired.request(method: "tools/list")
        #expect(result.objectValue?["tools"]?.arrayValue == [])
    }
}

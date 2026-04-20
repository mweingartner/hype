import Testing
import Foundation
@testable import HypeCore
@_spi(Testing) import HypeCore

/// Tests for `PexelsProvider` JSON response parsing.
/// Verifies that HTTP errors do NOT forward the response body (Security Finding N-4).
///
/// These tests run serially because `MockURLProtocolPexels.requestHandler` is a
/// global mutable variable shared across the test process.
@Suite("PexelsProvider — response parsing and error handling", .serialized)
struct PexelsProviderTests {

    private func makeFactory() -> WebAssetURLSessionFactory {
        WebAssetURLSessionFactory(testProtocolClasses: [MockURLProtocolPexels.self])
    }

    // MARK: - Canonical response parsing

    private static let canonicalResponse = """
    {
        "photos": [
            {
                "id": 12345,
                "photographer": "John Smith",
                "photographer_url": "https://www.pexels.com/@johnsmith",
                "alt": "A colorful landscape",
                "width": 4288,
                "height": 2848,
                "src": {
                    "original": "https://images.pexels.com/photos/12345/photo.jpg",
                    "medium": "https://images.pexels.com/photos/12345/photo_medium.jpg"
                }
            }
        ]
    }
    """

    @Test("parses canonical Pexels response — ID, title, URL, license, attribution")
    func parsesCanonicalResponse() async throws {
        // Set up the Keychain with a test API key in a test service
        // Since PexelsProvider hardcodes KeychainStore.pexelsAPIKeyAccount,
        // we need to seed it in the real keychain.
        try KeychainStore.setSecret("test-pexels-key", account: KeychainStore.pexelsAPIKeyAccount)
        defer {
            try? KeychainStore.deleteSecret(account: KeychainStore.pexelsAPIKeyAccount)
        }

        MockURLProtocolPexels.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Self.canonicalResponse.data(using: .utf8)!)
        }
        defer { MockURLProtocolPexels.requestHandler = nil }

        let provider = PexelsProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "landscape", maxResults: 5))

        #expect(results.count == 1)
        let r = results[0]

        // Title from alt text
        #expect(r.title == "A colorful landscape")
        // Download URL (original src)
        #expect(r.downloadURL.absoluteString == "https://images.pexels.com/photos/12345/photo.jpg")
        // Thumbnail from medium src
        #expect(r.thumbnailURL?.absoluteString == "https://images.pexels.com/photos/12345/photo_medium.jpg")
        // Dimensions
        #expect(r.width == 4288)
        #expect(r.height == 2848)
        // MIME type inferred from URL extension
        #expect(r.mimeType == "image/jpeg")
        // License — always Pexels License
        #expect(r.license.name == "Pexels License")
        #expect(r.license.identifier == "pexels")
        #expect(r.license.isShareable == true)
        // Attribution
        #expect(r.attribution.creator == "John Smith")
        #expect(r.attribution.sourceURL == "https://www.pexels.com/@johnsmith")
        #expect(r.attribution.providerName == "Pexels")
        #expect(r.attribution.providerIdentifier == "pexels")
        // Provider
        #expect(r.providerRaw == .pexels)
    }

    // MARK: - Security Finding N-4: error body not forwarded

    @Test("HTTP 401 returns status-code-only error, not the response body (Finding N-4)")
    func http401DoesNotForwardBody() async throws {
        try KeychainStore.setSecret("test-key", account: KeychainStore.pexelsAPIKeyAccount)
        defer { try? KeychainStore.deleteSecret(account: KeychainStore.pexelsAPIKeyAccount) }

        let sensitiveBody = "API key is invalid: Bearer sk-SUPER_SECRET_KEY_12345"
        MockURLProtocolPexels.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, sensitiveBody.data(using: .utf8)!)
        }
        defer { MockURLProtocolPexels.requestHandler = nil }

        let provider = PexelsProvider(sessionFactory: makeFactory())
        do {
            _ = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))
            Issue.record("Expected providerRejected error but search succeeded")
        } catch let error as WebAssetSearchError {
            if case .providerRejected(let msg) = error {
                // The message must be status-code-only — NEVER the sensitive body
                #expect(msg == "Pexels HTTP 401")
                #expect(!msg.contains("SUPER_SECRET_KEY"))
                #expect(!msg.contains("Bearer"))
                #expect(!msg.contains("invalid"))
            } else {
                Issue.record("Expected providerRejected, got \(error)")
            }
        }
    }

    @Test("HTTP 403 returns status-code-only error, not the response body (Finding N-4)")
    func http403DoesNotForwardBody() async throws {
        try KeychainStore.setSecret("test-key", account: KeychainStore.pexelsAPIKeyAccount)
        defer { try? KeychainStore.deleteSecret(account: KeychainStore.pexelsAPIKeyAccount) }

        let sensitiveBody = "Forbidden: API key sk-SUPER_SECRET_KEY_67890 has been revoked"
        MockURLProtocolPexels.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, sensitiveBody.data(using: .utf8)!)
        }
        defer { MockURLProtocolPexels.requestHandler = nil }

        let provider = PexelsProvider(sessionFactory: makeFactory())
        do {
            _ = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))
            Issue.record("Expected error")
        } catch let error as WebAssetSearchError {
            if case .providerRejected(let msg) = error {
                #expect(msg == "Pexels HTTP 403")
                #expect(!msg.contains("SUPER_SECRET_KEY"))
            } else {
                Issue.record("Expected providerRejected, got \(error)")
            }
        }
    }

    // MARK: - notConfigured when no API key

    @Test("search throws notConfigured when no Pexels API key is set")
    func searchThrowsNotConfiguredWhenNoKey() async throws {
        // Ensure no key is in the keychain
        try? KeychainStore.deleteSecret(account: KeychainStore.pexelsAPIKeyAccount)

        let provider = PexelsProvider(sessionFactory: makeFactory())
        do {
            _ = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))
            Issue.record("Expected notConfigured error but search succeeded")
        } catch let error as WebAssetSearchError {
            if case .notConfigured = error { /* correct */ } else {
                Issue.record("Expected notConfigured, got \(error)")
            }
        }
    }

    // MARK: - Empty results

    @Test("returns empty array when photos array is empty")
    func emptyPhotosArray() async throws {
        try KeychainStore.setSecret("test-key", account: KeychainStore.pexelsAPIKeyAccount)
        defer { try? KeychainStore.deleteSecret(account: KeychainStore.pexelsAPIKeyAccount) }

        MockURLProtocolPexels.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, #"{"photos": []}"#.data(using: .utf8)!)
        }
        defer { MockURLProtocolPexels.requestHandler = nil }

        let provider = PexelsProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "nothing", maxResults: 5))
        #expect(results.isEmpty)
    }

    // MARK: - Alt text fallback

    @Test("photo without alt text uses 'Photo by <photographer>' as title")
    func photoWithoutAltTextUsesFallbackTitle() async throws {
        try KeychainStore.setSecret("test-key", account: KeychainStore.pexelsAPIKeyAccount)
        defer { try? KeychainStore.deleteSecret(account: KeychainStore.pexelsAPIKeyAccount) }

        let responseWithoutAlt = """
        {
            "photos": [
                {
                    "id": 99999,
                    "photographer": "Jane Smith",
                    "photographer_url": "https://www.pexels.com/@janesmith",
                    "alt": "",
                    "width": 800,
                    "height": 600,
                    "src": {
                        "original": "https://images.pexels.com/photos/99999/photo.jpg"
                    }
                }
            ]
        }
        """
        MockURLProtocolPexels.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, responseWithoutAlt.data(using: .utf8)!)
        }
        defer { MockURLProtocolPexels.requestHandler = nil }

        let provider = PexelsProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))

        #expect(results.count == 1)
        #expect(results[0].title == "Photo by Jane Smith")
    }

    // MARK: - HTTP-only download URLs filtered

    @Test("HTTP-only download URL in src.original is filtered out")
    func httpDownloadURLFilteredOut() async throws {
        try KeychainStore.setSecret("test-key", account: KeychainStore.pexelsAPIKeyAccount)
        defer { try? KeychainStore.deleteSecret(account: KeychainStore.pexelsAPIKeyAccount) }

        let responseWithHTTP = """
        {
            "photos": [
                {
                    "id": 11111,
                    "photographer": "Test",
                    "photographer_url": "https://www.pexels.com/@test",
                    "alt": "Test photo",
                    "width": 100,
                    "height": 100,
                    "src": {
                        "original": "http://images.pexels.com/photos/11111/photo.jpg"
                    }
                }
            ]
        }
        """
        MockURLProtocolPexels.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, responseWithHTTP.data(using: .utf8)!)
        }
        defer { MockURLProtocolPexels.requestHandler = nil }

        let provider = PexelsProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))
        // HTTP URLs should be filtered (provider checks `downloadURL.scheme?.lowercased() == "https"`)
        #expect(results.isEmpty)
    }
}

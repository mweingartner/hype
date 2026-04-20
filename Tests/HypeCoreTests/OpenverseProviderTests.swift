import Testing
import Foundation
@testable import HypeCore
@_spi(Testing) import HypeCore

/// Tests for `OpenverseProvider` JSON response parsing.
/// Uses `MockURLProtocol` to intercept network calls without real I/O.
///
/// These tests run serially because `MockURLProtocolOpenverse.requestHandler` is a
/// global mutable variable shared across the test process.
@Suite("OpenverseProvider — response parsing", .serialized)
struct OpenverseProviderTests {

    // MARK: - Canonical response parsing

    private static let canonicalResponse = """
    {
        "results": [
            {
                "id": "native-id-001",
                "title": "A Beautiful Sunset",
                "url": "https://cdn.openverse.org/img/sunset.jpg",
                "thumbnail": "https://cdn.openverse.org/thumb/sunset_thumb.jpg",
                "creator": "Jane Doe",
                "foreign_landing_url": "https://flickr.com/photos/janedoe/001",
                "width": 1920,
                "height": 1080,
                "filesize": 512000,
                "filetype": "jpg",
                "license": "by",
                "license_version": "4.0",
                "license_url": "https://creativecommons.org/licenses/by/4.0/"
            }
        ]
    }
    """

    private func makeFactory() -> WebAssetURLSessionFactory {
        WebAssetURLSessionFactory(testProtocolClasses: [MockURLProtocolOpenverse.self])
    }

    @Test("parses canonical Openverse response — ID, title, URL, license, attribution")
    func parsesCanonicalResponse() async throws {
        MockURLProtocolOpenverse.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Self.canonicalResponse.data(using: .utf8)!)
        }
        defer { MockURLProtocolOpenverse.requestHandler = nil }

        let provider = OpenverseProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "sunset", maxResults: 5))

        #expect(results.count == 1)
        let r = results[0]

        // Title
        #expect(r.title == "A Beautiful Sunset")
        // Download URL
        #expect(r.downloadURL.absoluteString == "https://cdn.openverse.org/img/sunset.jpg")
        // Thumbnail
        #expect(r.thumbnailURL?.absoluteString == "https://cdn.openverse.org/thumb/sunset_thumb.jpg")
        // Dimensions
        #expect(r.width == 1920)
        #expect(r.height == 1080)
        // MIME type from filetype
        #expect(r.mimeType == "image/jpeg")
        // License
        #expect(r.license.identifier == "by-4.0")
        #expect(r.license.name == "BY-4.0")
        #expect(r.license.isShareable == true)
        // Attribution
        #expect(r.attribution.creator == "Jane Doe")
        #expect(r.attribution.providerName == "Openverse")
        #expect(r.attribution.providerIdentifier == "openverse")
        #expect(r.attribution.sourceURL == "https://flickr.com/photos/janedoe/001")
        // Provider
        #expect(r.providerRaw == .openverse)
        // ID is a stable SHA-256 derived candidate ID
        #expect(!r.id.isEmpty)
        #expect(r.id.count == 16)  // 8 bytes × 2 hex chars
    }

    @Test("parses response with missing optional fields gracefully")
    func parsesMissingOptionalFields() async throws {
        let minimalResponse = """
        {
            "results": [
                {
                    "id": "minimal-001",
                    "title": "Minimal Image",
                    "url": "https://cdn.openverse.org/minimal.png"
                }
            ]
        }
        """
        MockURLProtocolOpenverse.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, minimalResponse.data(using: .utf8)!)
        }
        defer { MockURLProtocolOpenverse.requestHandler = nil }

        let provider = OpenverseProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))

        #expect(results.count == 1)
        let r = results[0]
        #expect(r.title == "Minimal Image")
        #expect(r.width == nil)
        #expect(r.height == nil)
        #expect(r.mimeType == "image/png")  // inferred from URL extension
        #expect(r.thumbnailURL == nil)
    }

    @Test("returns empty array for empty results array")
    func emptyResultsArray() async throws {
        let emptyResponse = #"{"results": []}"#
        MockURLProtocolOpenverse.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, emptyResponse.data(using: .utf8)!)
        }
        defer { MockURLProtocolOpenverse.requestHandler = nil }

        let provider = OpenverseProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "nonexistent", maxResults: 5))
        #expect(results.isEmpty)
    }

    @Test("throws providerRejected on HTTP 500")
    func http500ThrowsProviderRejected() async throws {
        MockURLProtocolOpenverse.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }
        defer { MockURLProtocolOpenverse.requestHandler = nil }

        let provider = OpenverseProvider(sessionFactory: makeFactory())
        do {
            _ = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))
            Issue.record("Expected providerRejected error but search succeeded")
        } catch let error as WebAssetSearchError {
            if case .providerRejected = error { /* correct */ } else {
                Issue.record("Expected providerRejected, got \(error)")
            }
        }
    }

    @Test("CC0 license results have isShareable=true")
    func cc0LicenseIsShareable() async throws {
        let response = """
        {
            "results": [
                {
                    "id": "cc0-001",
                    "url": "https://cdn.openverse.org/cc0.jpg",
                    "license": "cc0",
                    "license_version": "1.0"
                }
            ]
        }
        """
        MockURLProtocolOpenverse.requestHandler = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (httpResponse, response.data(using: .utf8)!)
        }
        defer { MockURLProtocolOpenverse.requestHandler = nil }

        let provider = OpenverseProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "free", maxResults: 5))
        #expect(results.count == 1)
        #expect(results[0].license.isShareable == true)
    }

    @Test("SVG filetype maps to image/svg+xml MIME type")
    func svgFiletypeMapsToSVGMime() async throws {
        let response = """
        {
            "results": [
                {
                    "id": "svg-001",
                    "url": "https://cdn.openverse.org/icon.svg",
                    "filetype": "svg"
                }
            ]
        }
        """
        MockURLProtocolOpenverse.requestHandler = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (httpResponse, response.data(using: .utf8)!)
        }
        defer { MockURLProtocolOpenverse.requestHandler = nil }

        let provider = OpenverseProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "svg", maxResults: 5))
        #expect(results.count == 1)
        #expect(results[0].mimeType == "image/svg+xml")
    }
}

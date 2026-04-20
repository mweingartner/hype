import Testing
import Foundation
@testable import HypeCore
@_spi(Testing) import HypeCore

/// Tests for `WikimediaProvider` JSON response parsing.
/// Uses `MockURLProtocol` to intercept network calls without real I/O.
///
/// These tests run serially because `MockURLProtocolWikimedia.requestHandler` is a
/// global mutable variable shared across the test process.
@Suite("WikimediaProvider — response parsing and stripHTML", .serialized)
struct WikimediaProviderTests {

    private func makeFactory() -> WebAssetURLSessionFactory {
        WebAssetURLSessionFactory(testProtocolClasses: [MockURLProtocolWikimedia.self])
    }

    // MARK: - Canonical imageinfo response

    private static let searchResponse = """
    {
        "query": {
            "search": [
                { "title": "File:Sunset at the beach.jpg" }
            ]
        }
    }
    """

    private static let imageInfoResponse = """
    {
        "query": {
            "pages": {
                "12345": {
                    "title": "File:Sunset at the beach.jpg",
                    "imageinfo": [
                        {
                            "url": "https://upload.wikimedia.org/wikipedia/commons/sunset.jpg",
                            "descriptionurl": "https://commons.wikimedia.org/wiki/File:Sunset_at_the_beach.jpg",
                            "width": 2048,
                            "height": 1365,
                            "mime": "image/jpeg",
                            "extmetadata": {
                                "LicenseShortName": { "value": "CC BY-SA 4.0" },
                                "LicenseUrl": { "value": "https://creativecommons.org/licenses/by-sa/4.0/" },
                                "Artist": { "value": "<a href=\\"https://en.wikipedia.org/wiki/User:JaneDoe\\">Jane Doe</a>" }
                            }
                        }
                    ]
                }
            }
        }
    }
    """

    @Test("parses canonical Wikimedia imageinfo response")
    func parsesCanonicalResponse() async throws {
        var callCount = 0
        MockURLProtocolWikimedia.requestHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            // First call is the search, second is imageinfo
            let body = callCount == 1 ? Self.searchResponse : Self.imageInfoResponse
            return (response, body.data(using: .utf8)!)
        }
        defer { MockURLProtocolWikimedia.requestHandler = nil }

        let provider = WikimediaProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "sunset", maxResults: 5))

        #expect(results.count == 1)
        let r = results[0]

        // Title (File: prefix removed)
        #expect(r.title == "Sunset at the beach.jpg")
        // Download URL
        #expect(r.downloadURL.absoluteString == "https://upload.wikimedia.org/wikipedia/commons/sunset.jpg")
        // Dimensions
        #expect(r.width == 2048)
        #expect(r.height == 1365)
        // MIME
        #expect(r.mimeType == "image/jpeg")
        // License
        #expect(r.license.name == "CC BY-SA 4.0")
        #expect(r.license.isShareable == true)
        // Attribution — artist HTML stripped to plain text (Security Finding N-2)
        #expect(r.attribution.creator == "Jane Doe")
        #expect(r.attribution.providerName == "Wikimedia Commons")
        #expect(r.attribution.providerIdentifier == "wikimedia")
        // Provider
        #expect(r.providerRaw == .wikimedia)
    }

    // MARK: - stripHTML correctness (Security Finding N-2)

    @Test("stripHTML removes <a href> tags and returns plain text")
    func stripHTMLRemovesAnchorTag() async throws {
        // We verify stripHTML behavior by constructing an artist field with HTML
        // and checking the parsed result's attribution.creator field.
        let htmlArtist = """
        {
            "query": {
                "pages": {
                    "1": {
                        "title": "File:Test.jpg",
                        "imageinfo": [
                            {
                                "url": "https://upload.wikimedia.org/test.jpg",
                                "descriptionurl": "https://commons.wikimedia.org/wiki/File:Test.jpg",
                                "width": 100,
                                "height": 100,
                                "mime": "image/jpeg",
                                "extmetadata": {
                                    "LicenseShortName": { "value": "CC0" },
                                    "Artist": {
                                        "value": "<a href=\\"https://en.wikipedia.org/wiki/User:JaneDoe\\">Jane Doe</a>"
                                    }
                                }
                            }
                        ]
                    }
                }
            }
        }
        """
        var callCount = 0
        MockURLProtocolWikimedia.requestHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            let body = callCount == 1 ? Self.searchResponse : htmlArtist
            return (response, body.data(using: .utf8)!)
        }
        defer { MockURLProtocolWikimedia.requestHandler = nil }

        let provider = WikimediaProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))

        // Artist HTML is stripped to plain text — no angle brackets in output
        let creator = results.first?.attribution.creator ?? ""
        #expect(creator == "Jane Doe")
        #expect(!creator.contains("<"))
        #expect(!creator.contains(">"))
        #expect(!creator.contains("href"))
    }

    @Test("stripHTML handles multiple nested HTML tags")
    func stripHTMLHandlesMultipleNestedTags() async throws {
        let htmlArtist = """
        {
            "query": {
                "pages": {
                    "1": {
                        "title": "File:Test.jpg",
                        "imageinfo": [
                            {
                                "url": "https://upload.wikimedia.org/test.jpg",
                                "descriptionurl": "https://commons.wikimedia.org",
                                "width": 50,
                                "height": 50,
                                "mime": "image/jpeg",
                                "extmetadata": {
                                    "LicenseShortName": { "value": "CC0" },
                                    "Artist": {
                                        "value": "<span class=\\"artist\\"><a href=\\"/wiki/Jane\\">Jane <b>Doe</b></a></span>"
                                    }
                                }
                            }
                        ]
                    }
                }
            }
        }
        """
        var callCount = 0
        MockURLProtocolWikimedia.requestHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            let body = callCount == 1 ? Self.searchResponse : htmlArtist
            return (response, body.data(using: .utf8)!)
        }
        defer { MockURLProtocolWikimedia.requestHandler = nil }

        let provider = WikimediaProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))

        let creator = results.first?.attribution.creator ?? ""
        #expect(!creator.contains("<"))
        #expect(!creator.contains(">"))
        #expect(creator.contains("Jane"))
        #expect(creator.contains("Doe"))
    }

    @Test("HTTP-only download URLs are filtered out")
    func httpDownloadURLsFilteredOut() async throws {
        let imageInfoWithHTTP = """
        {
            "query": {
                "pages": {
                    "1": {
                        "title": "File:HTTP.jpg",
                        "imageinfo": [
                            {
                                "url": "http://upload.wikimedia.org/http_image.jpg",
                                "descriptionurl": "https://commons.wikimedia.org",
                                "width": 100,
                                "height": 100,
                                "mime": "image/jpeg",
                                "extmetadata": {
                                    "LicenseShortName": { "value": "CC0" }
                                }
                            }
                        ]
                    }
                }
            }
        }
        """
        var callCount = 0
        MockURLProtocolWikimedia.requestHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            let body = callCount == 1 ? Self.searchResponse : imageInfoWithHTTP
            return (response, body.data(using: .utf8)!)
        }
        defer { MockURLProtocolWikimedia.requestHandler = nil }

        let provider = WikimediaProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))

        // HTTP download URLs must be filtered out for security
        #expect(results.isEmpty)
    }

    @Test("returns empty for malformed imageinfo response")
    func malformedImageInfoReturnsEmpty() async throws {
        var callCount = 0
        MockURLProtocolWikimedia.requestHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            let body = callCount == 1 ? Self.searchResponse : "not json"
            return (response, body.data(using: .utf8)!)
        }
        defer { MockURLProtocolWikimedia.requestHandler = nil }

        let provider = WikimediaProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "test", maxResults: 5))
        #expect(results.isEmpty)
    }

    @Test("empty search results short-circuit to empty array")
    func emptySearchResultsShortCircuit() async throws {
        let emptySearch = """
        {
            "query": {
                "search": []
            }
        }
        """
        MockURLProtocolWikimedia.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, emptySearch.data(using: .utf8)!)
        }
        defer { MockURLProtocolWikimedia.requestHandler = nil }

        let provider = WikimediaProvider(sessionFactory: makeFactory())
        let results = try await provider.search(WebAssetSearchQuery(query: "nonexistent", maxResults: 5))
        #expect(results.isEmpty)
    }
}

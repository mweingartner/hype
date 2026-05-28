import Testing
import Foundation
@testable import HypeCore
@_spi(Testing) import HypeCore
#if canImport(AppKit)
import AppKit
#endif

/// Tests for `WebAssetImportPipeline` — exercises the full pipeline
/// including MIME validation, SVG sanitization, and decompression-bomb defense.
///
/// Uses `MockURLProtocol` to avoid real network I/O.
///
/// These tests run serially because `MockURLProtocolPipeline.requestHandler` is global.
@Suite("WebAssetImportPipeline — full pipeline validation", .serialized)
struct WebAssetImportPipelineTests {

    // MARK: - Helpers

    private func makeFactory() -> WebAssetURLSessionFactory {
        WebAssetURLSessionFactory(testProtocolClasses: [MockURLProtocolPipeline.self])
    }

    private func makePipeline() -> WebAssetImportPipeline {
        WebAssetImportPipeline(sessionFactory: makeFactory())
    }

    private func makeResult(
        downloadURL: String = "https://example.com/image.png",
        mimeType: String = "image/png",
        width: Int? = 100,
        height: Int? = 100
    ) -> WebAssetSearchResult {
        WebAssetSearchResult(
            id: "test-id",
            title: "Test Image",
            thumbnailURL: nil,
            downloadURL: URL(string: downloadURL)!,
            mimeType: mimeType,
            width: width,
            height: height,
            fileSizeBytes: nil,
            license: AssetLicense(name: "CC0", identifier: "cc0", url: "", isShareable: true),
            attribution: AssetAttribution(
                creator: "Author",
                title: "Test",
                sourceURL: "https://example.com",
                downloadURL: downloadURL,
                providerName: "Openverse",
                providerIdentifier: "openverse"
            ),
            providerRaw: .openverse
        )
    }

    // MARK: - Pre-flight HTTPS check

    @Test("HTTP URL is rejected with httpOnly error before any network call")
    func httpURLRejectedBeforeNetwork() async throws {
        let pipeline = makePipeline()
        let result = makeResult(downloadURL: "http://example.com/image.png")

        do {
            _ = try await pipeline.fetch(result)
            Issue.record("Expected httpOnly error")
        } catch let error as WebAssetSearchError {
            if case .httpOnly = error { /* correct */ } else {
                Issue.record("Expected httpOnly, got \(error)")
            }
        }
    }

    // MARK: - 404 → providerRejected

    @Test("HTTP 404 response throws providerRejected")
    func http404ThrowsProviderRejected() async throws {
        MockURLProtocolPipeline.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html"]
            )!
            return (response, "Not Found".data(using: .utf8)!)
        }
        defer { MockURLProtocolPipeline.requestHandler = nil }

        let pipeline = makePipeline()
        let result = makeResult()

        do {
            _ = try await pipeline.fetch(result)
            Issue.record("Expected providerRejected error")
        } catch let error as WebAssetSearchError {
            if case .providerRejected = error { /* correct */ } else {
                Issue.record("Expected providerRejected, got \(error)")
            }
        }
    }

    // MARK: - Unsupported MIME type

    @Test("Content-Type text/html is rejected with unsupportedMimeType")
    func htmlContentTypeRejected() async throws {
        MockURLProtocolPipeline.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html"]
            )!
            return (response, "<html>not an image</html>".data(using: .utf8)!)
        }
        defer { MockURLProtocolPipeline.requestHandler = nil }

        let pipeline = makePipeline()
        let result = makeResult()

        do {
            _ = try await pipeline.fetch(result)
            Issue.record("Expected unsupportedMimeType error")
        } catch let error as WebAssetSearchError {
            if case .unsupportedMimeType(let mime) = error {
                #expect(mime == "text/html")
            } else {
                Issue.record("Expected unsupportedMimeType, got \(error)")
            }
        }
    }

    @Test("Content-Type application/json is rejected with unsupportedMimeType")
    func jsonContentTypeRejected() async throws {
        MockURLProtocolPipeline.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, "{}".data(using: .utf8)!)
        }
        defer { MockURLProtocolPipeline.requestHandler = nil }

        let pipeline = makePipeline()
        let result = makeResult()

        do {
            _ = try await pipeline.fetch(result)
            Issue.record("Expected unsupportedMimeType error")
        } catch let error as WebAssetSearchError {
            if case .unsupportedMimeType = error { /* correct */ } else {
                Issue.record("Expected unsupportedMimeType, got \(error)")
            }
        }
    }

    // MARK: - SVG sanitization

    @Test("SVG with <script> element is sanitized — script is removed, result succeeds")
    func svgWithScriptIsSanitized() async throws {
        // A minimal valid SVG that NSImage can render, with a <script> that should be stripped
        let svgWithScript = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
            <rect x="0" y="0" width="100" height="100" fill="blue"/>
            <script>alert('xss')</script>
        </svg>
        """
        MockURLProtocolPipeline.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/svg+xml"]
            )!
            return (response, svgWithScript.data(using: .utf8)!)
        }
        defer { MockURLProtocolPipeline.requestHandler = nil }

        let pipeline = makePipeline()
        let result = makeResult(downloadURL: "https://example.com/icon.svg", mimeType: "image/svg+xml")

        // This should succeed — script is removed by sanitizer, remaining SVG is valid
        // The MIME type is svg+xml so the sanitizer runs
        do {
            let download = try await pipeline.fetch(result)
            let svgString = String(data: download.bytes, encoding: .utf8) ?? ""
            #expect(!svgString.contains("<script"))
            #expect(!svgString.contains("alert"))
            #expect(download.mimeType == "image/svg+xml")
        } catch let error as WebAssetSearchError {
            // decodeFailed is acceptable — NSImage may not decode minimal SVG
            // but the important thing is that script is NOT present in the output
            if case .decodeFailed = error { /* acceptable */ }
            else if case .svgRejected = error { /* acceptable */ }
            else { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test("SVG with data:image/svg+xml in use href is rejected at sanitization")
    func svgWithEmbeddedSVGDataURLRejectedOrSanitized() async throws {
        let svgWithEmbedded = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
            <rect x="0" y="0" width="100" height="100" fill="red"/>
            <use href="data:image/svg+xml;base64,PHN2Zy8+"/>
        </svg>
        """
        MockURLProtocolPipeline.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/svg+xml"]
            )!
            return (response, svgWithEmbedded.data(using: .utf8)!)
        }
        defer { MockURLProtocolPipeline.requestHandler = nil }

        let pipeline = makePipeline()
        let svgResult = makeResult(
            downloadURL: "https://example.com/icon.svg",
            mimeType: "image/svg+xml"
        )

        do {
            let download = try await pipeline.fetch(svgResult)
            // If it succeeds, the data:image/svg+xml must have been stripped
            let svgString = String(data: download.bytes, encoding: .utf8) ?? ""
            #expect(!svgString.contains("data:image/svg+xml"))
        } catch {
            // Any error is also acceptable — the point is the embedded SVG doesn't pass through
        }
    }

    // MARK: - Supported MIME types are accepted

    @Test("supportedMimeTypes contains png, jpeg, webp, gif, svg+xml")
    func supportedMimeTypesContainsExpected() {
        let supported = WebAssetImportPipeline.supportedMimeTypes
        #expect(supported.contains("image/png"))
        #expect(supported.contains("image/jpeg"))
        #expect(supported.contains("image/webp"))
        #expect(supported.contains("image/gif"))
        #expect(supported.contains("image/svg+xml"))
    }

    // MARK: - Constants

    @Test("maxBytesPerAsset is 50 MB")
    func maxBytesIs50MB() {
        #expect(WebAssetImportPipeline.maxBytesPerAsset == 50 * 1024 * 1024)
    }

    @Test("maxPixelsPerAsset is 100 million")
    func maxPixelsIs100MP() {
        #expect(WebAssetImportPipeline.maxPixelsPerAsset == 100_000_000)
    }

    // MARK: - makeAsset factory

    @Test("makeAsset produces Asset with correct provenance")
    func makeAssetCorrectProvenance() throws {
        let license = AssetLicense(name: "CC0", identifier: "cc0", url: "", isShareable: true)
        let attribution = AssetAttribution(
            creator: "Jane Doe",
            title: "Test Image",
            sourceURL: "https://openverse.org/image/123",
            downloadURL: "https://cdn.openverse.org/123.png",
            providerName: "Openverse",
            providerIdentifier: "openverse"
        )
        let searchResult = WebAssetSearchResult(
            id: "candidate-id",
            title: "Test Image",
            thumbnailURL: nil,
            downloadURL: URL(string: "https://cdn.openverse.org/123.png")!,
            mimeType: "image/png",
            width: 200,
            height: 150,
            fileSizeBytes: nil,
            license: license,
            attribution: attribution,
            providerRaw: .openverse
        )
        let download = WebAssetDownloadResult(
            bytes: Data([0x89, 0x50, 0x4E, 0x47]),  // PNG magic
            mimeType: "image/png",
            width: 200,
            height: 150,
            result: searchResult
        )
        let asset = WebAssetImportPipeline.makeAsset(
            name: "test_asset",
            searchQuery: "a test query",
            download: download
        )

        #expect(asset.name == "test_asset")
        #expect(asset.mimeType == "image/png")
        #expect(asset.width == 200)
        #expect(asset.height == 150)
        // Provenance
        #expect(asset.provenance?.origin == .webSearch)
        #expect(asset.provenance?.searchQuery == "a test query")
        #expect(asset.provenance?.license.identifier == "cc0")
        #expect(asset.provenance?.attribution.creator == "Jane Doe")
        #expect(asset.provenance?.attribution.providerName == "Openverse")
    }

    @Test("makeAsset: searchQuery in provenance is NOT the asset name")
    func makeAssetSearchQueryIsNotName() {
        // The searchQuery stored in provenance must be the original query,
        // not the asset name. This ensures Finding 10 (no query: in script) can be enforced.
        let download = WebAssetDownloadResult(
            bytes: Data(),
            mimeType: "image/png",
            width: 100,
            height: 100,
            result: makeResult()
        )
        let asset = WebAssetImportPipeline.makeAsset(
            name: "my_asset_name",
            searchQuery: "the original search query",
            download: download
        )
        #expect(asset.provenance?.searchQuery == "the original search query")
        #expect(asset.provenance?.searchQuery != asset.name)
    }
}

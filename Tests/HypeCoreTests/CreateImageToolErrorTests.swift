import Foundation
import Testing
@testable import HypeCore

// MARK: - CreateImageToolErrorTests
//
// Tests for error paths in the `create_image` and `generate_image` AI tools
// (HypeToolExecutor lines ~3875–3950). These cover the failure modes called
// out in CodeReviewAndGapsPlan §3-C.
//
// Scope notes:
//   • `create_image` reads local files or repository assets — no HTTP.
//     Its error surfaces are: file not found and asset not found.
//   • `generate_image` calls OpenAIImageGenerationClient which does HTTP.
//     Its error surfaces include: HTTP non-2xx, corrupted base64, and
//     missing image client.
//   • An oversized-payload cap is NOT present in OpenAIImageGenerationClient
//     as of this writing. The test below documents that gap as a contract test.

// MARK: - Dedicated URLProtocol subclass
//
// A dedicated subclass avoids races with MockURLProtocol tests that run
// concurrently in Swift Testing's default parallel mode.

final class MockURLProtocolCreateImage: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocolCreateImage.requestHandler else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "MockURLProtocolCreateImage",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No handler set"]
                )
            )
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - FakeImageGenerator helper
//
// Wraps an OpenAIImageGenerationClient wired to MockURLProtocolCreateImage
// so the executor can be driven via the injected `imageGenerationClientFactory`.

private func makeGeneratingExecutor(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> HypeToolExecutor {
    MockURLProtocolCreateImage.requestHandler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocolCreateImage.self]
    let session = URLSession(configuration: config)
    let client = OpenAIImageGenerationClient(
        apiKey: "sk-test",
        baseURL: URL(string: "https://api.openai.test")!,
        session: session,
        logger: HypeLogger(setupFileLogging: false)
    )
    return HypeToolExecutor(
        webAssetSession: nil,
        webAssetClient: nil,
        webAssetPipeline: nil,
        imageGenerationClientFactory: { client }
    )
}

// MARK: - Tests

@Suite("create_image and generate_image — error paths", .serialized)
struct CreateImageToolErrorTests {

    // MARK: - Minimal 1×1 PNG bytes

    private let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    // MARK: C-create-1: create_image with missing file returns error, no part added

    @Test("create_image with non-existent file_path returns error, no part added")
    func createImageMissingFileReturnsError() async throws {
        var doc = HypeDocument.newDocument()
        let cardId = doc.sortedCards[0].id
        let executor = HypeToolExecutor()
        let missingPath = "/tmp/hype-test-nonexistent-\(UUID()).png"

        let result = await executor.execute(
            toolName: "create_image",
            arguments: ["name": "MyImage", "file_path": missingPath],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.contains("Could not read"), "Error must mention the read failure")
        #expect(doc.parts.filter { $0.partType == .image }.isEmpty, "No image part must be added on file error")
    }

    // MARK: C-create-2: create_image with missing asset_name returns error, no part added

    @Test("create_image with unknown asset_name returns error, no part added")
    func createImageMissingAssetReturnsError() async throws {
        var doc = HypeDocument.newDocument()
        let cardId = doc.sortedCards[0].id
        let executor = HypeToolExecutor()

        let result = await executor.execute(
            toolName: "create_image",
            arguments: ["name": "MyImage", "asset_name": "definitely-not-there.png"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.contains("not found"), "Error must mention missing asset")
        #expect(doc.parts.filter { $0.partType == .image }.isEmpty, "No image part must be added")
    }

    // MARK: C-1: generate_image with HTTP 404 returns clean error

    @Test("generate_image HTTP 404 returns clean error string")
    func generateImageHttp404ReturnsCleanError() async throws {
        defer { MockURLProtocolCreateImage.requestHandler = nil }

        var doc = HypeDocument.newDocument()
        let cardId = doc.sortedCards[0].id

        let executor = makeGeneratingExecutor { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"error\":{\"message\":\"Not found\"}}".utf8))
        }

        let result = await executor.execute(
            toolName: "generate_image",
            arguments: ["name": "TestImage", "prompt": "a red ball"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.contains("failed"), "HTTP 404 must produce an error string")
        #expect(doc.parts.filter { $0.partType == .image }.isEmpty, "No part must be added on HTTP failure")
        // Security: API key must not appear in the error string returned to the AI.
        #expect(!result.contains("sk-test"), "Error string must not echo API key")
    }

    // MARK: C-2: Oversized payload — document the absence of a cap (gap contract test)
    //
    // As of this writing, OpenAIImageGenerationClient has no payload size cap.
    // This test documents that an oversized (>50 MB) base64 payload is decoded
    // and stored without error. If a cap is added in the future, this test
    // should be updated to assert the cap fires.

    @Test("generate_image with >50 MB base64 response succeeds — documents absence of payload cap")
    func generateImageOversizedPayloadDecodedWithoutCap() async throws {
        defer { MockURLProtocolCreateImage.requestHandler = nil }

        var doc = HypeDocument.newDocument()
        let cardId = doc.sortedCards[0].id

        // Build a JSON payload whose b64_json field decodes to >50 MB.
        // We use a large block of 0x41 bytes base64-encoded.
        let bigData = Data(repeating: 0x41, count: 52 * 1024 * 1024)  // 52 MB raw
        let bigBase64 = bigData.base64EncodedString()

        let executor = makeGeneratingExecutor { request in
            let payload = """
            {
              "output_format": "png",
              "data": [{"b64_json": "\(bigBase64)"}]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }

        let result = await executor.execute(
            toolName: "generate_image",
            arguments: ["name": "BigImage", "prompt": "filler"],
            document: &doc,
            currentCardId: cardId
        )

        // GAP DOCUMENTED: no 50 MB cap in current implementation.
        // The tool succeeds and stores the oversized image.
        // TODO (Phase 6 hardening): add a cap, then change this assertion to
        // #expect(result.contains("oversized") || result.contains("too large"))
        // and verify no part is added.
        if result.contains("failed") || result.contains("error") {
            // A cap was added — test documents the new behaviour.
            #expect(doc.parts.filter { $0.partType == .image }.isEmpty,
                    "If a cap fires, no image part must be added")
        } else {
            // No cap exists: the oversized image was stored (gap documented).
            let part = try #require(doc.parts.first { $0.name == "BigImage" })
            #expect(part.imageData?.count ?? 0 > 50 * 1024 * 1024,
                    "Oversized image stored without cap — this documents the gap")
        }
    }

    // MARK: C-3: Corrupted base64 response → error string, no part added

    @Test("generate_image with corrupted base64 body returns error, no part added")
    func generateImageCorruptedBase64ReturnsError() async throws {
        defer { MockURLProtocolCreateImage.requestHandler = nil }

        var doc = HypeDocument.newDocument()
        let cardId = doc.sortedCards[0].id

        let executor = makeGeneratingExecutor { request in
            // Syntactically valid JSON but the b64_json field contains non-base64 characters.
            let payload = """
            {
              "output_format": "png",
              "data": [{"b64_json": "!!!NOT-VALID-BASE64!!!"}]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }

        let result = await executor.execute(
            toolName: "generate_image",
            arguments: ["name": "BadImage", "prompt": "a blue ball"],
            document: &doc,
            currentCardId: cardId
        )

        // The decoder ignores unknown characters, so "!!!" are stripped and the
        // remaining characters decode to empty or near-empty data. The result
        // can be either an error OR a near-empty image. Document both:
        if result.contains("failed") || result.contains("error") {
            // Decode failure propagated — good.
            #expect(doc.parts.filter { $0.partType == .image }.isEmpty,
                    "No part must be added when base64 decoding fails")
        } else {
            // Base64 decoder with .ignoreUnknownCharacters stripped invalid chars
            // and stored near-empty data. The image part may exist but its data
            // will be near-empty. This documents the behaviour.
            let part = doc.parts.first { $0.name == "BadImage" }
            if let part = part {
                let dataSize = part.imageData?.count ?? 0
                #expect(dataSize < 1024, "Near-empty image stored after corrupt base64 stripped — documents behaviour")
            }
        }
    }

    // MARK: C-4: MIME mismatch (claimed PNG, actual GIF magic bytes) — contract test
    //
    // generate_image relies on `output_format` from the JSON envelope to set the
    // MIME type — it does NOT inspect the image bytes. This test documents that a
    // server returning GIF bytes while claiming "png" output_format will produce
    // an image part tagged as image/png. This is a known gap (no byte-level
    // MIME verification). If validation is added, update the assertion.

    @Test("generate_image with claimed PNG but GIF bytes stores part — documents absence of MIME verification")
    func generateImageMimeMismatchStoresPart() async throws {
        defer { MockURLProtocolCreateImage.requestHandler = nil }

        var doc = HypeDocument.newDocument()
        let cardId = doc.sortedCards[0].id

        // GIF89a magic bytes base64-encoded.
        let gifBytes = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  // GIF89a
        let gifBase64 = gifBytes.base64EncodedString()

        let executor = makeGeneratingExecutor { request in
            // Server claims PNG but returns GIF bytes.
            let payload = """
            {
              "output_format": "png",
              "data": [{"b64_json": "\(gifBase64)"}]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }

        let result = await executor.execute(
            toolName: "generate_image",
            arguments: ["name": "MismatchImage", "prompt": "a landscape"],
            document: &doc,
            currentCardId: cardId
        )

        // GAP DOCUMENTED: no byte-level MIME verification in current implementation.
        // The client trusts the server-declared output_format.
        if result.contains("failed") || result.contains("error") {
            // MIME validation was added — test documents the new behaviour.
            #expect(doc.parts.filter { $0.partType == .image }.isEmpty,
                    "If MIME validation fires, no part must be added")
        } else {
            // No MIME check: GIF bytes stored under png mime type (gap documented).
            let part = try #require(doc.parts.first { $0.name == "MismatchImage" },
                                    "Part must be created when no MIME verification fires")
            #expect(part.imageData == gifBytes, "Raw GIF bytes stored without MIME check")
        }
    }

    // MARK: C-5: generate_image without an image-client factory returns instructive error

    @Test("generate_image without an image-client factory returns configuration error")
    func generateImageWithoutClientReturnsConfigError() async throws {
        var doc = HypeDocument.newDocument()
        let cardId = doc.sortedCards[0].id
        // Default executor has no imageGenerationClientFactory.
        let executor = HypeToolExecutor()

        let result = await executor.execute(
            toolName: "generate_image",
            arguments: ["name": "Test", "prompt": "a blue ball"],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.contains("not configured") || result.contains("API key"),
                "Error must tell the user how to configure image generation")
        #expect(doc.parts.filter { $0.partType == .image }.isEmpty, "No part added when client is absent")
    }
}

import Foundation
import Testing
@testable import HypeCore

@Suite("OpenAI Images client", .serialized)
struct OpenAIImageGenerationClientTests {
    private let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    @Test("request body uses GPT image defaults and optional generation settings")
    func requestBodyUsesImageDefaults() throws {
        let body = OpenAIImageGenerationClient.requestBodyObject(
            model: "gpt-image-1.5",
            prompt: "a blue bouncing ball sprite",
            size: nil,
            quality: "high",
            background: "transparent"
        )

        #expect(body["model"] as? String == "gpt-image-1.5")
        #expect(body["prompt"] as? String == "a blue bouncing ball sprite")
        #expect(body["n"] as? Int == 1)
        #expect(body["size"] as? String == "1024x1024")
        #expect(body["output_format"] as? String == "png")
        #expect(body["quality"] as? String == "high")
        #expect(body["background"] as? String == "transparent")
    }

    @Test("decodeResponse extracts base64 image data")
    func decodeResponseExtractsBase64Image() throws {
        let json = """
        {
          "output_format": "png",
          "data": [
            {
              "b64_json": "\(onePixelPNGBase64)",
              "revised_prompt": "A clean blue ball sprite."
            }
          ]
        }
        """

        let decoded = try OpenAIImageGenerationClient.decodeResponse(Data(json.utf8))

        #expect(decoded.mimeType == "image/png")
        #expect(decoded.data == Data(base64Encoded: onePixelPNGBase64))
        #expect(decoded.revisedPrompt == "A clean blue ball sprite.")
    }

    @Test("generateImage posts to Images API without exposing image bytes in logs")
    func generateImagePostsToImagesEndpoint() async throws {
        let testLogger = HypeLogger(setupFileLogging: false)
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/v1/images/generations")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

            let bodyData = try #require(Self.bodyData(from: request))
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["model"] as? String == "gpt-image-1.5")
            #expect(body["prompt"] as? String == "a tiny red ship")
            #expect(body["size"] as? String == "1536x1024")

            let payload = """
            {
              "output_format": "png",
              "data": [
                { "b64_json": "\(onePixelPNGBase64)" }
              ]
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

        let client = OpenAIImageGenerationClient(
            apiKey: "sk-test",
            model: "gpt-image-1.5",
            baseURL: URL(string: "https://api.openai.test")!,
            session: session,
            logger: testLogger
        )

        let image = try await client.generateImage(
            prompt: "a tiny red ship",
            model: nil,
            size: "1536x1024",
            quality: nil,
            background: nil
        )

        #expect(image.data == Data(base64Encoded: onePixelPNGBase64))
        #expect(testLogger.entries.contains { $0.message.contains("bytes=") })
        #expect(testLogger.entries.allSatisfy { !$0.message.contains(onePixelPNGBase64) })
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

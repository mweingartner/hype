import Foundation

public struct HypeGeneratedImage: Sendable, Equatable {
    public var data: Data
    public var mimeType: String
    public var revisedPrompt: String?

    public init(data: Data, mimeType: String = "image/png", revisedPrompt: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.revisedPrompt = revisedPrompt
    }
}

public protocol HypeImageGenerating: Sendable {
    func generateImage(
        prompt: String,
        model: String?,
        size: String?,
        quality: String?,
        background: String?
    ) async throws -> HypeGeneratedImage
}

public actor OpenAIImageGenerationClient: HypeImageGenerating {
    public struct Timeouts: Sendable, Equatable {
        public var request: TimeInterval
        public var resource: TimeInterval

        public init(request: TimeInterval = 180, resource: TimeInterval = 240) {
            self.request = request
            self.resource = resource
        }
    }

    private let apiKey: String?
    private let model: String
    private let baseURL: URL
    private let session: URLSession
    private let timeouts: Timeouts
    private let logger: HypeLogger

    public init(
        apiKey: String,
        model: String = HypeAIConfiguration.defaultOpenAIImageModel,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        timeouts: Timeouts = Timeouts(),
        logger: HypeLogger = .shared
    ) {
        self.apiKey = HypeAIConfiguration.normalized(apiKey)
        self.model = model
        self.baseURL = baseURL
        self.timeouts = timeouts
        self.logger = logger

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeouts.request
        config.timeoutIntervalForResource = timeouts.resource
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    init(
        apiKey: String,
        model: String = HypeAIConfiguration.defaultOpenAIImageModel,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        timeouts: Timeouts = Timeouts(),
        session: URLSession,
        logger: HypeLogger = .shared
    ) {
        self.apiKey = HypeAIConfiguration.normalized(apiKey)
        self.model = model
        self.baseURL = baseURL
        self.timeouts = timeouts
        self.session = session
        self.logger = logger
    }

    public func generateImage(
        prompt: String,
        model overrideModel: String? = nil,
        size: String? = nil,
        quality: String? = nil,
        background: String? = nil
    ) async throws -> HypeGeneratedImage {
        guard let apiKey else {
            throw OpenAIClientError.noAPIKey
        }

        let requestModel = HypeAIConfiguration.normalized(overrideModel) ?? model
        let endpoint = "/v1/images/generations"
        let url = baseURL.appendingPathComponent("v1").appendingPathComponent("images").appendingPathComponent("generations")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeouts.request

        let body = Self.requestBodyObject(
            model: requestModel,
            prompt: prompt,
            size: size,
            quality: quality,
            background: background
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.aiInput(
            Self.describeRequest(
                model: requestModel,
                prompt: prompt,
                size: body["size"] as? String,
                quality: body["quality"] as? String,
                background: body["background"] as? String
            ),
            source: "OpenAI Image"
        )

        do {
            let (data, response) = try await sessionData(for: request, endpoint: endpoint, model: requestModel)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw OpenAIClientError.requestFailed(Self.errorMessage(from: data))
            }

            let decoded = try Self.decodeResponse(data)
            logger.aiOutput(
                Self.describeResponse(model: requestModel, image: decoded),
                source: "OpenAI Image"
            )
            return decoded
        } catch {
            logger.error(
                "\(endpoint) model=\(requestModel) failed: \(error.localizedDescription)",
                source: "OpenAI Image"
            )
            throw error
        }
    }

    private func sessionData(for request: URLRequest, endpoint: String, model: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OpenAIClientError.requestTimedOut(endpoint: endpoint, model: model, seconds: timeouts.request)
        } catch {
            throw error
        }
    }

    static func requestBodyObject(
        model: String,
        prompt: String,
        size: String?,
        quality: String?,
        background: String?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": HypeAIConfiguration.normalized(size) ?? "1024x1024",
            "output_format": "png"
        ]
        if let quality = HypeAIConfiguration.normalized(quality) {
            body["quality"] = quality
        }
        if let background = HypeAIConfiguration.normalized(background) {
            body["background"] = background
        }
        return body
    }

    static func decodeResponse(_ data: Data) throws -> HypeGeneratedImage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]],
              let first = items.first
        else {
            throw OpenAIClientError.invalidResponse
        }

        guard let base64 = first["b64_json"] as? String,
              let imageData = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
        else {
            throw OpenAIClientError.invalidResponse
        }

        let format = (json["output_format"] as? String)
            ?? (first["output_format"] as? String)
            ?? "png"
        return HypeGeneratedImage(
            data: imageData,
            mimeType: mimeType(for: format),
            revisedPrompt: first["revised_prompt"] as? String
        )
    }

    private static func mimeType(for outputFormat: String) -> String {
        switch outputFormat.lowercased() {
        case "webp": return "image/webp"
        case "jpeg", "jpg": return "image/jpeg"
        default: return "image/png"
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "Unknown error"
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(300))
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "Unknown error"
    }

    private static func describeRequest(
        model: String,
        prompt: String,
        size: String?,
        quality: String?,
        background: String?
    ) -> String {
        var lines = [
            "POST /v1/images/generations",
            "model=\(model)",
            "size=\(size ?? "1024x1024")"
        ]
        if let quality {
            lines.append("quality=\(quality)")
        }
        if let background {
            lines.append("background=\(background)")
        }
        lines.append("prompt:\n\(prompt)")
        return lines.joined(separator: "\n")
    }

    private static func describeResponse(model: String, image: HypeGeneratedImage) -> String {
        var lines = [
            "POST /v1/images/generations",
            "model=\(model)",
            "mimeType=\(image.mimeType)",
            "bytes=\(image.data.count)"
        ]
        if let revisedPrompt = image.revisedPrompt, !revisedPrompt.isEmpty {
            lines.append("revisedPrompt:\n\(revisedPrompt)")
        }
        return lines.joined(separator: "\n")
    }
}

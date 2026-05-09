import Foundation

public actor OpenAISpeechClient {
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let logger: HypeLogger

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        logger: HypeLogger = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.logger = logger

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    public func transcribe(audioFileURL: URL, model: String = HypeAIConfiguration.defaultOpenAITranscriptionModel) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.noAPIKey
        }
        let url = baseURL.appendingPathComponent("v1").appendingPathComponent("audio").appendingPathComponent("transcriptions")
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.multipartBody(
            fileURL: audioFileURL,
            fileField: "file",
            fileName: audioFileURL.lastPathComponent,
            mimeType: "audio/mp4",
            fields: ["model": model],
            boundary: boundary
        )

        logger.aiInput(
            "POST /v1/audio/transcriptions\nmodel=\(model)\naudioFile=\(audioFileURL.lastPathComponent)",
            source: "OpenAI Speech"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenAIClientError.requestFailed(Self.errorMessage(from: data))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw OpenAIClientError.invalidResponse
        }
        logger.aiOutput(
            "POST /v1/audio/transcriptions\nmodel=\(model)\nTRANSCRIPT:\n\(text)",
            source: "OpenAI Speech"
        )
        return text
    }

    public func speech(
        text: String,
        model: String = HypeAIConfiguration.defaultOpenAITTSModel,
        voice: String = HypeAIConfiguration.defaultOpenAIVoice
    ) async throws -> Data {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.noAPIKey
        }
        let url = baseURL.appendingPathComponent("v1").appendingPathComponent("audio").appendingPathComponent("speech")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "voice": voice,
            "input": text,
            "response_format": "mp3"
        ])

        logger.aiInput(
            "POST /v1/audio/speech\nmodel=\(model)\nvoice=\(voice)\nchars=\(text.count)",
            source: "OpenAI Speech"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenAIClientError.requestFailed(Self.errorMessage(from: data))
        }
        logger.aiOutput(
            "POST /v1/audio/speech\nmodel=\(model)\nvoice=\(voice)\nbytes=\(data.count)",
            source: "OpenAI Speech"
        )
        return data
    }

    private static func multipartBody(
        fileURL: URL,
        fileField: String,
        fileName: String,
        mimeType: String,
        fields: [String: String],
        boundary: String
    ) throws -> Data {
        var data = Data()
        for (name, value) in fields {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            data.append("\(value)\r\n")
        }
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        data.append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n")
        data.append("--\(boundary)--\r\n")
        return data
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
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

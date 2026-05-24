import Foundation

public enum LlamaSwapClientError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case requestFailed(String)
    case requestTimedOut(endpoint: String, model: String, seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "llama-swap URL is invalid."
        case .invalidResponse:
            return "llama-swap returned an unexpected response."
        case .requestFailed(let message):
            return "llama-swap error: \(message)"
        case .requestTimedOut(let endpoint, let model, let seconds):
            return "llama-swap \(endpoint) timed out after \(Int(seconds.rounded()))s talking to model \"\(model)\"."
        }
    }
}

/// OpenAI-compatible client for a local llama-swap proxy.
///
/// llama-swap selects and loads the target upstream model from the `model`
/// field in OpenAI-compatible requests. Hype therefore treats model selection
/// as a normal provider preference and sends text/tool/schema calls through the
/// same Responses API bridge used for OpenAI, while model discovery uses
/// llama-swap's `GET /v1/models` endpoint.
public actor LlamaSwapClient: HypeAIClient {
    public struct Timeouts: Sendable, Equatable {
        public var request: TimeInterval
        public var resource: TimeInterval

        public init(request: TimeInterval = 600, resource: TimeInterval = 600) {
            self.request = request
            self.resource = resource
        }
    }

    private struct ModelListResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    private let host: String
    private let port: String
    private let model: String
    private let apiKey: String?
    private let baseURL: URL
    private let timeouts: Timeouts
    private let session: URLSession
    private let logger: HypeLogger

    public init(
        host: String = "localhost",
        port: String = "8080",
        model: String = "model1",
        apiKey: String? = nil,
        timeouts: Timeouts = Timeouts(),
        logger: HypeLogger = .shared
    ) throws {
        guard let baseURL = Self.makeBaseURL(host: host, port: port) else {
            throw LlamaSwapClientError.invalidURL
        }
        self.host = host
        self.port = port
        self.model = model
        self.apiKey = apiKey
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
        host: String = "localhost",
        port: String = "8080",
        model: String = "model1",
        apiKey: String? = nil,
        timeouts: Timeouts = Timeouts(),
        session: URLSession,
        logger: HypeLogger = .shared
    ) throws {
        guard let baseURL = Self.makeBaseURL(host: host, port: port) else {
            throw LlamaSwapClientError.invalidURL
        }
        self.host = host
        self.port = port
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeouts = timeouts
        self.session = session
        self.logger = logger
    }

    public nonisolated var providerName: String { "llama-swap" }
    public nonisolated var modelName: String { model }

    public func availableModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("v1").appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeouts.request
        if let header = authorizationHeaderValue {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw LlamaSwapClientError.requestFailed(Self.errorMessage(from: data))
            }
            return try JSONDecoder().decode(ModelListResponse.self, from: data).data.map(\.id)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw LlamaSwapClientError.requestTimedOut(endpoint: "/v1/models", model: model, seconds: timeouts.request)
        } catch let error as LlamaSwapClientError {
            throw error
        } catch {
            throw LlamaSwapClientError.requestFailed(error.localizedDescription)
        }
    }

    public func generate(prompt: String, model overrideModel: String? = nil, system: String? = nil) async throws -> String {
        try await wrap {
            try await responsesClient().generate(prompt: prompt, model: overrideModel, system: system)
        }
    }

    public func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat? = nil
    ) async throws -> OllamaChatResponse {
        try await wrap {
            try await responsesClient().chat(messages: messages, tools: tools, format: format)
        }
    }

    public func structuredChat<Response: Decodable & Sendable>(
        messages: [OllamaMessage],
        tools: [OllamaTool] = [],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response) {
        try await wrap {
            try await responsesClient().structuredChat(messages: messages, tools: tools, format: format)
        }
    }

    public func preloadModel() async throws {
        // Model selection/loading is request-driven in llama-swap: the `model`
        // value on generate/chat is the selection signal. Avoid issuing a hidden
        // prompt just to warm a local model.
    }

    private var authorizationHeaderValue: String? {
        guard let trimmed = HypeAIConfiguration.normalized(apiKey) else { return nil }
        return "Bearer \(trimmed)"
    }

    private func responsesClient() -> OpenAIResponsesClient {
        OpenAIResponsesClient(
            apiKey: HypeAIConfiguration.normalized(apiKey),
            model: model,
            baseURL: baseURL,
            timeouts: OpenAIResponsesClient.Timeouts(request: timeouts.request, resource: timeouts.resource),
            session: session,
            logger: logger,
            requiresAPIKey: false,
            providerName: "llama-swap"
        )
    }

    private func wrap<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as OpenAIClientError {
            throw Self.llamaSwapError(from: error, model: model)
        } catch {
            throw error
        }
    }

    private static func makeBaseURL(host: String, port: String) -> URL? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        if trimmedHost.hasPrefix("http://") || trimmedHost.hasPrefix("https://") {
            return URL(string: trimmedHost)
        }
        guard !trimmedPort.isEmpty else { return nil }
        return URL(string: "http://\(trimmedHost):\(trimmedPort)")
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "Unknown error"
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(300))
        }
        if let error = json["error"] as? String {
            return String(error.prefix(300))
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "Unknown error"
    }

    private static func llamaSwapError(from error: OpenAIClientError, model: String) -> LlamaSwapClientError {
        switch error {
        case .invalidURL:
            return .invalidURL
        case .invalidResponse:
            return .invalidResponse
        case .requestFailed(let message):
            return .requestFailed(message)
        case .requestTimedOut(let endpoint, _, let seconds):
            return .requestTimedOut(endpoint: endpoint, model: model, seconds: seconds)
        case .noAPIKey:
            return .requestFailed("API key is required by this llama-swap instance.")
        }
    }
}

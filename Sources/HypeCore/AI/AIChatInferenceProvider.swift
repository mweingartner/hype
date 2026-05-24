import Foundation

public struct AIChatInferenceRequest: Sendable {
    public var messages: [OllamaMessage]
    public var tools: [OllamaTool]
    public var format: OllamaResponseFormat?

    public init(
        messages: [OllamaMessage],
        tools: [OllamaTool] = [],
        format: OllamaResponseFormat? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.format = format
    }
}

public protocol AIChatInferenceProviding: Sendable {
    var providerName: String { get }
    var modelName: String { get }
    var supportsStreaming: Bool { get }

    func availableModels() async throws -> [String]
    func generate(prompt: String, model: String?, system: String?) async throws -> String
    func chat(_ request: AIChatInferenceRequest) async throws -> OllamaChatResponse
    func chatStream(_ request: AIChatInferenceRequest) -> AsyncStream<String>
    func preloadModel() async throws
}

public extension AIChatInferenceProviding {
    func chat(messages: [OllamaMessage], tools: [OllamaTool] = []) async throws -> OllamaChatResponse {
        try await chat(AIChatInferenceRequest(messages: messages, tools: tools))
    }

    func chatStream(messages: [OllamaMessage], tools: [OllamaTool] = []) -> AsyncStream<String> {
        chatStream(AIChatInferenceRequest(messages: messages, tools: tools))
    }
}

public struct HypeAIClientChatInferenceProvider: AIChatInferenceProviding {
    private let client: any HypeAIClient

    public init(client: any HypeAIClient) {
        self.client = client
    }

    public var providerName: String { client.providerName }
    public var modelName: String { client.modelName }
    public var supportsStreaming: Bool { client.supportsChatStreaming }

    public func availableModels() async throws -> [String] {
        try await client.availableModels()
    }

    public func generate(prompt: String, model: String?, system: String?) async throws -> String {
        try await client.generate(prompt: prompt, model: model, system: system)
    }

    public func chat(_ request: AIChatInferenceRequest) async throws -> OllamaChatResponse {
        try await client.chat(messages: request.messages, tools: request.tools, format: request.format)
    }

    public func chatStream(_ request: AIChatInferenceRequest) -> AsyncStream<String> {
        guard supportsStreaming else {
            return AsyncStream { continuation in continuation.finish() }
        }
        return client.chatStream(messages: request.messages, tools: request.tools)
    }

    public func preloadModel() async throws {
        try await client.preloadModel()
    }
}

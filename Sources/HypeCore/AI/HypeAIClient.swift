import Foundation

public enum HypeAIProvider: String, CaseIterable, Sendable, Identifiable {
    case ollama
    case llamaSwap = "llama-swap"
    case llamaCpp = "llama.cpp"
    case openAI = "openai"
    case zAI = "z.ai"
    case miniMax = "minimax"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .llamaSwap: return "llama-swap"
        case .llamaCpp: return "llama.cpp"
        case .openAI: return "OpenAI"
        case .zAI: return "Z.ai"
        case .miniMax: return "MiniMax"
        }
    }
}

public enum HypeSpeechInputProvider: String, CaseIterable, Sendable, Identifiable {
    case apple
    case openAI = "openai"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apple: return "Apple Speech"
        case .openAI: return "OpenAI Speech"
        }
    }
}

public protocol HypeAIClient: Sendable {
    var providerName: String { get }
    var modelName: String { get }
    var supportsChatStreaming: Bool { get }

    func availableModels() async throws -> [String]
    func generate(prompt: String, model: String?, system: String?) async throws -> String
    func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?
    ) async throws -> OllamaChatResponse
    func structuredChat<Response: Decodable & Sendable>(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response)
    func preloadModel() async throws
    func chatStream(messages: [OllamaMessage], tools: [OllamaTool]) -> AsyncStream<String>
}

public extension HypeAIClient {
    var supportsChatStreaming: Bool { false }

    func generate(prompt: String, model: String? = nil) async throws -> String {
        try await generate(prompt: prompt, model: model, system: nil)
    }

    func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool]
    ) async throws -> OllamaChatResponse {
        try await chat(messages: messages, tools: tools, format: nil)
    }
}

public enum HypeAIConfiguration {
    public static let providerKey = "hype.ai.provider"
    public static let llamaSwapHostKey = "hype.llamaSwap.host"
    public static let llamaSwapPortKey = "hype.llamaSwap.port"
    public static let llamaSwapModelKey = "hype.llamaSwap.model"
    public static let llamaCppHostKey = "hype.llamaCpp.host"
    public static let llamaCppPortKey = "hype.llamaCpp.port"
    public static let llamaCppModelKey = "hype.llamaCpp.model"
    public static let openAIModelKey = "hype.openai.model"
    public static let zAIBaseURLKey = "hype.zai.baseURL"
    public static let zAIModelKey = "hype.zai.model"
    public static let miniMaxBaseURLKey = "hype.minimax.baseURL"
    public static let miniMaxModelKey = "hype.minimax.model"
    public static let openAIImageModelKey = "hype.openai.imageModel"
    public static let openAITranscriptionModelKey = "hype.openai.transcriptionModel"
    public static let openAITTSModelKey = "hype.openai.ttsModel"
    public static let openAIVoiceKey = "hype.openai.voice"
    public static let speechInputProviderKey = "hype.speech.inputProvider"
    public static let speakAssistantResponsesKey = "hype.openai.speech.speakAssistantResponses"

    public static let defaultOpenAIModel = "gpt-5.2"
    public static let defaultLlamaSwapHost = "localhost"
    public static let defaultLlamaSwapPort = "8080"
    public static let defaultLlamaSwapModel = "model1"
    public static let defaultLlamaCppHost = "localhost"
    public static let defaultLlamaCppPort = "8001"
    public static let defaultLlamaCppModel = "model"
    public static let defaultZAIBaseURL = "https://api.z.ai/api/paas/v4"
    public static let defaultZAIModel = "glm-5.1"
    public static let defaultMiniMaxBaseURL = "https://api.minimax.io/v1"
    public static let defaultMiniMaxModel = "MiniMax-M2"
    public static let defaultOpenAIImageModel = "gpt-image-1.5"
    public static let defaultOpenAITranscriptionModel = "gpt-4o-mini-transcribe"
    public static let defaultOpenAITTSModel = "gpt-4o-mini-tts"
    public static let defaultOpenAIVoice = "coral"

    public static let openAITextModels = [
        "gpt-5.2",
        "gpt-5.2-pro",
        "gpt-5.1",
        "gpt-5",
        "gpt-5-mini",
        "gpt-5-nano",
        "gpt-4.1",
        "gpt-4.1-mini",
        "gpt-4.1-nano",
        "gpt-4o",
        "gpt-4o-mini"
    ]

    public static let zAITextModels = [
        "glm-5.1",
        "glm-4.5",
        "glm-4.5-air",
        "glm-4.5-x",
        "glm-4.5-airx",
        "glm-4.5-flash"
    ]

    public static let miniMaxTextModels = [
        "MiniMax-M2",
        "MiniMax-Text-01"
    ]

    public static let openAIImageModels = [
        "gpt-image-1.5",
        "gpt-image-1",
        "gpt-image-1-mini"
    ]

    public static let openAITranscriptionModels = [
        "gpt-4o-mini-transcribe",
        "gpt-4o-transcribe",
        "whisper-1"
    ]

    public static let openAITTSModels = [
        "gpt-4o-mini-tts",
        "tts-1",
        "tts-1-hd"
    ]

    public static let openAIVoices = [
        "alloy",
        "ash",
        "ballad",
        "coral",
        "echo",
        "fable",
        "nova",
        "onyx",
        "sage",
        "shimmer"
    ]

    public static func selectedProvider(defaults: UserDefaults = .standard) -> HypeAIProvider {
        let raw = defaults.string(forKey: providerKey) ?? HypeAIProvider.ollama.rawValue
        return HypeAIProvider(rawValue: raw) ?? .ollama
    }

    public static func selectedSpeechInputProvider(defaults: UserDefaults = .standard) -> HypeSpeechInputProvider {
        let raw = defaults.string(forKey: speechInputProviderKey) ?? HypeSpeechInputProvider.apple.rawValue
        return HypeSpeechInputProvider(rawValue: raw) ?? .apple
    }

    public static func openAIModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: openAIModelKey)) ?? defaultOpenAIModel
    }

    public static func zAIBaseURL(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: zAIBaseURLKey)) ?? defaultZAIBaseURL
    }

    public static func zAIModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: zAIModelKey)) ?? defaultZAIModel
    }

    public static func miniMaxBaseURL(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: miniMaxBaseURLKey)) ?? defaultMiniMaxBaseURL
    }

    public static func miniMaxModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: miniMaxModelKey)) ?? defaultMiniMaxModel
    }

    public static func llamaSwapHost(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaSwapHostKey)) ?? defaultLlamaSwapHost
    }

    public static func llamaSwapPort(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaSwapPortKey)) ?? defaultLlamaSwapPort
    }

    public static func llamaSwapModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaSwapModelKey)) ?? defaultLlamaSwapModel
    }

    public static func llamaCppHost(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaCppHostKey)) ?? defaultLlamaCppHost
    }

    public static func llamaCppPort(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaCppPortKey)) ?? defaultLlamaCppPort
    }

    public static func llamaCppModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaCppModelKey)) ?? defaultLlamaCppModel
    }

    public static func openAIImageModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: openAIImageModelKey)) ?? defaultOpenAIImageModel
    }

    public static func openAITranscriptionModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: openAITranscriptionModelKey)) ?? defaultOpenAITranscriptionModel
    }

    public static func openAITTSModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: openAITTSModelKey)) ?? defaultOpenAITTSModel
    }

    public static func openAIVoice(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: openAIVoiceKey)) ?? defaultOpenAIVoice
    }

    public static func makeClient(defaults: UserDefaults = .standard) throws -> any HypeAIClient {
        switch selectedProvider(defaults: defaults) {
        case .ollama:
            return OpenAIChatCompletionsClient(
                configuration: .ollama(
                    host: normalized(defaults.string(forKey: "ollamaHost")) ?? "localhost",
                    port: normalized(defaults.string(forKey: "ollamaPort")) ?? "11434",
                    model: normalized(defaults.string(forKey: "ollamaModel")) ?? "llama3.2"
                )
            )
        case .llamaSwap:
            let apiKey = try? KeychainStore.getSecret(account: KeychainStore.llamaSwapAPIKeyAccount)
            return try LlamaSwapClient(
                host: llamaSwapHost(defaults: defaults),
                port: llamaSwapPort(defaults: defaults),
                model: llamaSwapModel(defaults: defaults),
                apiKey: apiKey
            )
        case .llamaCpp:
            guard let baseURL = localOpenAICompatibleBaseURL(
                host: llamaCppHost(defaults: defaults),
                port: llamaCppPort(defaults: defaults)
            ) else {
                throw OpenAIChatCompletionsClient.StreamingError.invalidResponse
            }
            return OpenAIChatCompletionsClient(
                configuration: .openAICompatible(
                    baseURL: baseURL,
                    model: llamaCppModel(defaults: defaults),
                    providerName: HypeAIProvider.llamaCpp.rawValue,
                    modelListPath: "v1/models"
                )
            )
        case .openAI:
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.openAIAPIKeyAccount)
            return OpenAIChatCompletionsClient(
                configuration: .init(
                    baseURL: URL(string: "https://api.openai.com")!,
                    apiKey: apiKey,
                    model: openAIModel(defaults: defaults)
                )
            )
        case .zAI:
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.zAIAPIKeyAccount)
            guard let baseURL = URL(string: zAIBaseURL(defaults: defaults)) else {
                throw OpenAIChatCompletionsClient.StreamingError.invalidResponse
            }
            return OpenAIChatCompletionsClient(
                configuration: .openAICompatible(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: zAIModel(defaults: defaults),
                    providerName: HypeAIProvider.zAI.rawValue,
                    chatCompletionsPath: "chat/completions",
                    modelListPath: "models"
                )
            )
        case .miniMax:
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.miniMaxAPIKeyAccount)
            guard let baseURL = URL(string: miniMaxBaseURL(defaults: defaults)) else {
                throw OpenAIChatCompletionsClient.StreamingError.invalidResponse
            }
            return OpenAIChatCompletionsClient(
                configuration: .openAICompatible(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: miniMaxModel(defaults: defaults),
                    providerName: HypeAIProvider.miniMax.rawValue,
                    modelListPath: "v1/models"
                )
            )
        }
    }

    public static func makeChatInferenceProvider(defaults: UserDefaults = .standard) throws -> any AIChatInferenceProviding {
        HypeAIClientChatInferenceProvider(client: try makeClient(defaults: defaults))
    }

    public static func makeImageGenerationClient(defaults: UserDefaults = .standard) throws -> any HypeImageGenerating {
        let apiKey = try KeychainStore.getSecret(account: KeychainStore.openAIAPIKeyAccount)
        return OpenAIImageGenerationClient(
            apiKey: apiKey,
            model: openAIImageModel(defaults: defaults)
        )
    }

    static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public static func localOpenAICompatibleBaseURL(host: String, port: String) -> URL? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        if trimmedHost.hasPrefix("http://") || trimmedHost.hasPrefix("https://") {
            return URL(string: trimmedHost)
        }
        guard !trimmedPort.isEmpty else { return nil }
        return URL(string: "http://\(trimmedHost):\(trimmedPort)")
    }
}

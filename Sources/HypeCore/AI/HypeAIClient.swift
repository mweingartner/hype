import Foundation

public enum HypeAIProvider: String, CaseIterable, Sendable, Identifiable {
    case ollama
    case llamaSwap = "llama-swap"
    case openAI = "openai"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .llamaSwap: return "llama-swap"
        case .openAI: return "OpenAI"
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
}

public extension HypeAIClient {
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
    public static let openAIModelKey = "hype.openai.model"
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

    public static func llamaSwapHost(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaSwapHostKey)) ?? defaultLlamaSwapHost
    }

    public static func llamaSwapPort(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaSwapPortKey)) ?? defaultLlamaSwapPort
    }

    public static func llamaSwapModel(defaults: UserDefaults = .standard) -> String {
        normalized(defaults.string(forKey: llamaSwapModelKey)) ?? defaultLlamaSwapModel
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
            return OllamaToolClient(
                host: normalized(defaults.string(forKey: "ollamaHost")) ?? "localhost",
                port: normalized(defaults.string(forKey: "ollamaPort")) ?? "11434",
                model: normalized(defaults.string(forKey: "ollamaModel")) ?? "llama3.2"
            )
        case .llamaSwap:
            let apiKey = try? KeychainStore.getSecret(account: KeychainStore.llamaSwapAPIKeyAccount)
            return try LlamaSwapClient(
                host: llamaSwapHost(defaults: defaults),
                port: llamaSwapPort(defaults: defaults),
                model: llamaSwapModel(defaults: defaults),
                apiKey: apiKey
            )
        case .openAI:
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.openAIAPIKeyAccount)
            return OpenAIResponsesClient(
                apiKey: apiKey,
                model: openAIModel(defaults: defaults)
            )
        }
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
}

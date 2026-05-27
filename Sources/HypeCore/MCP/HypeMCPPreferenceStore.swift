import Foundation

public enum HypeMCPConfiguration {
    public static let enabledKey = "hype.mcp.enabled"
    public static let allowMutationsKey = "hype.mcp.allowMutations"
    public static let portKey = "hype.mcp.port"
    public static let tokenKey = "hype.mcp.token"
    public static let defaultPort = "47891"
}

public extension KeychainStore {
    static let hypeMCPTokenAccount = "hype.mcp.token"
}

public struct HypeMCPPreferenceDescriptor: Sendable, Equatable {
    public var name: String
    public var key: String
    public var defaultValue: String
    public var allowedValues: [String]?
    public var description: String

    public init(
        name: String,
        key: String,
        defaultValue: String,
        allowedValues: [String]? = nil,
        description: String
    ) {
        self.name = name
        self.key = key
        self.defaultValue = defaultValue
        self.allowedValues = allowedValues
        self.description = description
    }
}

public enum HypeMCPPreferenceStore {
    public static let descriptors: [HypeMCPPreferenceDescriptor] = [
        .init(name: "mcp.enabled", key: HypeMCPConfiguration.enabledKey, defaultValue: "true", allowedValues: ["true", "false"], description: "Enable the local Hype MCP server."),
        .init(name: "mcp.allowMutations", key: HypeMCPConfiguration.allowMutationsKey, defaultValue: "true", allowedValues: ["true", "false"], description: "Allow MCP tools to mutate the active stack."),
        .init(name: "mcp.port", key: HypeMCPConfiguration.portKey, defaultValue: HypeMCPConfiguration.defaultPort, description: "Loopback port for the Hype MCP Streamable HTTP endpoint."),
        .init(name: "ai.provider", key: HypeAIConfiguration.providerKey, defaultValue: HypeAIProvider.ollama.rawValue, allowedValues: HypeAIProvider.allCases.map(\.rawValue), description: "Selected Hype AI provider."),
        .init(name: "ollama.host", key: "ollamaHost", defaultValue: "localhost", description: "Ollama host."),
        .init(name: "ollama.port", key: "ollamaPort", defaultValue: "11434", description: "Ollama port."),
        .init(name: "ollama.model", key: "ollamaModel", defaultValue: "llama3.2", description: "Ollama model."),
        .init(name: "llama-swap.host", key: HypeAIConfiguration.llamaSwapHostKey, defaultValue: HypeAIConfiguration.defaultLlamaSwapHost, description: "llama-swap host."),
        .init(name: "llama-swap.port", key: HypeAIConfiguration.llamaSwapPortKey, defaultValue: HypeAIConfiguration.defaultLlamaSwapPort, description: "llama-swap port."),
        .init(name: "llama-swap.model", key: HypeAIConfiguration.llamaSwapModelKey, defaultValue: HypeAIConfiguration.defaultLlamaSwapModel, description: "llama-swap model."),
        .init(name: "llama.cpp.host", key: HypeAIConfiguration.llamaCppHostKey, defaultValue: HypeAIConfiguration.defaultLlamaCppHost, description: "llama.cpp OpenAI-compatible host."),
        .init(name: "llama.cpp.port", key: HypeAIConfiguration.llamaCppPortKey, defaultValue: HypeAIConfiguration.defaultLlamaCppPort, description: "llama.cpp OpenAI-compatible port."),
        .init(name: "llama.cpp.model", key: HypeAIConfiguration.llamaCppModelKey, defaultValue: HypeAIConfiguration.defaultLlamaCppModel, description: "llama.cpp model."),
        .init(name: "openai.model", key: HypeAIConfiguration.openAIModelKey, defaultValue: HypeAIConfiguration.defaultOpenAIModel, allowedValues: HypeAIConfiguration.openAITextModels, description: "OpenAI text model."),
        .init(name: "openai.imageModel", key: HypeAIConfiguration.openAIImageModelKey, defaultValue: HypeAIConfiguration.defaultOpenAIImageModel, allowedValues: HypeAIConfiguration.openAIImageModels, description: "OpenAI image model."),
        .init(name: "openai.transcriptionModel", key: HypeAIConfiguration.openAITranscriptionModelKey, defaultValue: HypeAIConfiguration.defaultOpenAITranscriptionModel, allowedValues: HypeAIConfiguration.openAITranscriptionModels, description: "OpenAI transcription model."),
        .init(name: "openai.ttsModel", key: HypeAIConfiguration.openAITTSModelKey, defaultValue: HypeAIConfiguration.defaultOpenAITTSModel, allowedValues: HypeAIConfiguration.openAITTSModels, description: "OpenAI speech model."),
        .init(name: "openai.voice", key: HypeAIConfiguration.openAIVoiceKey, defaultValue: HypeAIConfiguration.defaultOpenAIVoice, allowedValues: HypeAIConfiguration.openAIVoices, description: "OpenAI speech voice."),
        .init(name: "speech.inputProvider", key: HypeAIConfiguration.speechInputProviderKey, defaultValue: HypeSpeechInputProvider.apple.rawValue, allowedValues: HypeSpeechInputProvider.allCases.map(\.rawValue), description: "Speech input provider."),
        .init(name: "speech.speakAssistantResponses", key: HypeAIConfiguration.speakAssistantResponsesKey, defaultValue: "false", allowedValues: ["true", "false"], description: "Speak AI assistant responses through OpenAI speech output."),
        .init(name: "z.ai.baseURL", key: HypeAIConfiguration.zAIBaseURLKey, defaultValue: HypeAIConfiguration.defaultZAIBaseURL, description: "Z.ai OpenAI-compatible base URL."),
        .init(name: "z.ai.model", key: HypeAIConfiguration.zAIModelKey, defaultValue: HypeAIConfiguration.defaultZAIModel, allowedValues: HypeAIConfiguration.zAITextModels, description: "Z.ai model."),
        .init(name: "minimax.baseURL", key: HypeAIConfiguration.miniMaxBaseURLKey, defaultValue: HypeAIConfiguration.defaultMiniMaxBaseURL, description: "MiniMax OpenAI-compatible base URL."),
        .init(name: "minimax.model", key: HypeAIConfiguration.miniMaxModelKey, defaultValue: HypeAIConfiguration.defaultMiniMaxModel, allowedValues: HypeAIConfiguration.miniMaxTextModels, description: "MiniMax model."),
        .init(name: "webAssets.provider", key: "hype.webAssets.provider", defaultValue: "openverse", allowedValues: ["openverse", "pexels", "wikimedia"], description: "Web asset search provider."),
        .init(name: "appleMusic.enabled", key: AppleMusicConfiguration.enabledKey, defaultValue: "false", allowedValues: ["true", "false"], description: "Enable MusicKit-backed Apple Music controls."),
        .init(name: "appleMusic.playbackEngine", key: AppleMusicConfiguration.playbackEngineKey, defaultValue: AppleMusicConfiguration.defaultPlaybackEngine.rawValue, allowedValues: AppleMusicPlaybackEngine.allCases.map(\.rawValue), description: "MusicKit playback engine.")
    ]

    public static let secretAccounts: [String: String] = [
        "openai": KeychainStore.openAIAPIKeyAccount,
        "llama-swap": KeychainStore.llamaSwapAPIKeyAccount,
        "z.ai": KeychainStore.zAIAPIKeyAccount,
        "minimax": KeychainStore.miniMaxAPIKeyAccount,
        "meshy": KeychainStore.meshyAPIKeyAccount,
        "pexels": KeychainStore.pexelsAPIKeyAccount
    ]

    public static func hypeAppDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.hype.app") ?? .standard
    }

    public static func snapshot(defaults: UserDefaults = .standard) -> HypeMCPJSONValue {
        var preferences: [HypeMCPJSONValue] = []
        for descriptor in descriptors {
            let value = defaults.object(forKey: descriptor.key).map(String.init(describing:)) ?? descriptor.defaultValue
            preferences.append(.object([
                "name": .string(descriptor.name),
                "key": .string(descriptor.key),
                "value": .string(value),
                "defaultValue": .string(descriptor.defaultValue),
                "description": .string(descriptor.description),
                "allowedValues": .array((descriptor.allowedValues ?? []).map { .string($0) })
            ]))
        }

        var secrets: [HypeMCPJSONValue] = []
        for (name, account) in secretAccounts.sorted(by: { $0.key < $1.key }) {
            secrets.append(.object([
                "name": .string(name),
                "account": .string(account),
                "isSet": .bool(KeychainStore.hasSecret(account: account))
            ]))
        }
        secrets.append(.object([
            "name": .string("mcp-token"),
            "account": .string(HypeMCPConfiguration.tokenKey),
            "isSet": .bool(!(defaults.string(forKey: HypeMCPConfiguration.tokenKey) ?? "").isEmpty)
        ]))

        return .object([
            "preferences": .array(preferences),
            "secrets": .array(secrets)
        ])
    }

    public static func setPreference(name: String, value: String, defaults: UserDefaults = .standard) -> String {
        guard let descriptor = descriptors.first(where: { $0.name == name }) else {
            return "Unknown preference '\(name)'"
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let allowed = descriptor.allowedValues, !allowed.contains(normalized) {
            return "Invalid value '\(value)' for \(name). Allowed values: \(allowed.joined(separator: ", "))"
        }

        if ["true", "false"].contains(descriptor.defaultValue), ["true", "false"].contains(normalized) {
            defaults.set(normalized == "true", forKey: descriptor.key)
        } else {
            defaults.set(normalized, forKey: descriptor.key)
        }
        return "Set preference \(name)"
    }

    public static func setSecret(name: String, value: String, defaults: UserDefaults = .standard) -> String {
        if name == "mcp-token" {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "Refused to store an empty secret for \(name)"
            }
            defaults.set(trimmed, forKey: HypeMCPConfiguration.tokenKey)
            return "Stored secret \(name)"
        }
        guard let account = secretAccounts[name] else {
            return "Unknown secret '\(name)'"
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Refused to store an empty secret for \(name)"
        }
        do {
            try KeychainStore.setSecret(trimmed, account: account)
            return "Stored secret \(name)"
        } catch {
            return "Could not store secret \(name): \(error)"
        }
    }

    public static func deleteSecret(name: String, defaults: UserDefaults = .standard) -> String {
        if name == "mcp-token" {
            defaults.removeObject(forKey: HypeMCPConfiguration.tokenKey)
            return "Deleted secret \(name)"
        }
        guard let account = secretAccounts[name] else {
            return "Unknown secret '\(name)'"
        }
        do {
            try KeychainStore.deleteSecret(account: account)
            return "Deleted secret \(name)"
        } catch KeychainStoreError.itemNotFound {
            return "Secret \(name) was not set"
        } catch {
            return "Could not delete secret \(name): \(error)"
        }
    }

    public static func ensureMCPToken(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: HypeMCPConfiguration.tokenKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        let token = UUID().uuidString + "-" + UUID().uuidString
        defaults.set(token, forKey: HypeMCPConfiguration.tokenKey)
        return token
    }
}

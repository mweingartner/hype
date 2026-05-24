import Foundation

public protocol AIScriptingProvider: Sendable {
    func currentModel() -> String
    func availableModels() async throws -> [String]
    func generate(prompt: String, model: String?) async throws -> String
}

public enum AIScriptingProviderError: Error, LocalizedError, Sendable {
    case requestTimedOut

    public var errorDescription: String? {
        switch self {
        case .requestTimedOut:
            return "Timed out waiting for the AI provider"
        }
    }
}

public struct StubAIScriptingProvider: AIScriptingProvider, Sendable {
    public var model: String
    public var models: [String]
    public var response: String

    public init(model: String = "", models: [String] = [], response: String = "") {
        self.model = model
        self.models = models
        self.response = response
    }

    public func currentModel() -> String { model }
    public func availableModels() async throws -> [String] { models }
    public func generate(prompt: String, model: String?) async throws -> String { response }
}

public struct OllamaAIScriptingProvider: AIScriptingProvider, Sendable {
    private let hostOverride: String?
    private let portOverride: String?
    private let modelOverride: String?
    private let timeout: TimeInterval

    public init(
        host: String? = nil,
        port: String? = nil,
        model: String? = nil,
        timeout: TimeInterval = 120
    ) {
        self.hostOverride = host
        self.portOverride = port
        self.modelOverride = model
        self.timeout = timeout
    }

    public func currentModel() -> String {
        resolvedModel()
    }

    public func availableModels() async throws -> [String] {
        let client = makeClient()
        return try await client.availableModels()
    }

    public func generate(prompt: String, model: String?) async throws -> String {
        let resolved = normalized(model) ?? resolvedModel()
        let client = makeClient()
        return try await client.generate(prompt: prompt, model: resolved)
    }

    private func makeClient() -> OllamaToolClient {
        OllamaToolClient(
            host: resolvedHost(),
            port: resolvedPort(),
            model: resolvedModel()
        )
    }

    private func resolvedHost() -> String {
        normalized(hostOverride)
            ?? normalized(UserDefaults.standard.string(forKey: "ollamaHost"))
            ?? "localhost"
    }

    private func resolvedPort() -> String {
        normalized(portOverride)
            ?? normalized(UserDefaults.standard.string(forKey: "ollamaPort"))
            ?? "11434"
    }

    private func resolvedModel() -> String {
        normalized(modelOverride)
            ?? normalized(UserDefaults.standard.string(forKey: "ollamaModel"))
            ?? "llama3.2"
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

}

public struct SelectedAIScriptingProvider: AIScriptingProvider, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func currentModel() -> String {
        switch HypeAIConfiguration.selectedProvider(defaults: defaults) {
        case .ollama:
            return HypeAIConfiguration.normalized(defaults.string(forKey: "ollamaModel")) ?? "llama3.2"
        case .llamaSwap:
            return HypeAIConfiguration.llamaSwapModel(defaults: defaults)
        case .llamaCpp:
            return HypeAIConfiguration.llamaCppModel(defaults: defaults)
        case .openAI:
            return HypeAIConfiguration.openAIModel(defaults: defaults)
        case .zAI:
            return HypeAIConfiguration.zAIModel(defaults: defaults)
        case .miniMax:
            return HypeAIConfiguration.miniMaxModel(defaults: defaults)
        }
    }

    public func availableModels() async throws -> [String] {
        let client = try HypeAIConfiguration.makeClient(defaults: defaults)
        return try await client.availableModels()
    }

    public func generate(prompt: String, model: String?) async throws -> String {
        let client = try HypeAIConfiguration.makeClient(defaults: defaults)
        return try await client.generate(prompt: prompt, model: model, system: nil)
    }
}

public extension AIScriptingProvider {
    func availableModelsSync(timeout: TimeInterval = 120) throws -> [String] {
        try blockingWait(timeout: timeout) {
            try await availableModels()
        }
    }

    func generateSync(prompt: String, model: String?, timeout: TimeInterval = 120) throws -> String {
        try blockingWait(timeout: timeout) {
            try await generate(prompt: prompt, model: model)
        }
    }

    private func blockingWait<T: Sendable>(
        timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = _AIScriptingResultBox<T>()
        Task.detached {
            defer { semaphore.signal() }
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw AIScriptingProviderError.requestTimedOut
        }
        guard let result = box.result else {
            throw AIScriptingProviderError.requestTimedOut
        }
        return try result.get()
    }
}

private final class _AIScriptingResultBox<T: Sendable>: @unchecked Sendable {
    var result: Result<T, Error>?
}

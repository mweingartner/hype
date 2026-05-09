import Foundation

/// AI routing modes.
public enum AIRoutingMode: String, Sendable, CaseIterable {
    case auto, local, cloud
}

/// Result from an AI request.
public struct AIResponse: Sendable {
    public var text: String
    public var provider: String
    public var tokensUsed: Int

    public init(text: String, provider: String, tokensUsed: Int = 0) {
        self.text = text
        self.provider = provider
        self.tokensUsed = tokensUsed
    }
}

/// Manages simple AI integration — routes between local Ollama and cloud OpenAI.
public actor AIService {
    private var apiKey: String?
    private var routingMode: AIRoutingMode = .auto
    private var dailyTokensUsed: Int = 0
    private var dailyLimit: Int = 100_000
    private var conversations: [String: [(role: String, content: String)]] = [:]

    public init() {}

    public func setApiKey(_ key: String) { apiKey = key }
    public func setRoutingMode(_ mode: AIRoutingMode) { routingMode = mode }
    public func hasApiKey() -> Bool { apiKey != nil && !(apiKey?.isEmpty ?? true) }
    public func getDailyUsage() -> Int { dailyTokensUsed }
    public func getDailyLimit() -> Int { dailyLimit }

    /// Ask the AI a question with optional context.
    public func ask(prompt: String, context: String? = nil, system: String? = nil) async throws -> AIResponse {
        // Check budget
        let estimatedTokens = (prompt.count + (context?.count ?? 0)) / 4
        guard dailyTokensUsed + estimatedTokens <= dailyLimit else {
            throw AIError.budgetExceeded(used: dailyTokensUsed, limit: dailyLimit)
        }

        let mode = routingMode

        switch mode {
        case .local:
            return try await askLocal(prompt: prompt, context: context)
        case .cloud:
            return try await askCloud(prompt: prompt, context: context, system: system)
        case .auto:
            // Try cloud first if API key is set, otherwise local
            if hasApiKey() {
                return try await askCloud(prompt: prompt, context: context, system: system)
            }
            return try await askLocal(prompt: prompt, context: context)
        }
    }

    private func askLocal(prompt: String, context: String?) async throws -> AIResponse {
        let host = (UserDefaults.standard.string(forKey: "ollamaHost")?.isEmpty == false)
            ? (UserDefaults.standard.string(forKey: "ollamaHost") ?? "localhost")
            : "localhost"
        let port = (UserDefaults.standard.string(forKey: "ollamaPort")?.isEmpty == false)
            ? (UserDefaults.standard.string(forKey: "ollamaPort") ?? "11434")
            : "11434"
        let model = (UserDefaults.standard.string(forKey: "ollamaModel")?.isEmpty == false)
            ? (UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2")
            : "llama3.2"
        let client = OllamaToolClient(host: host, port: port, model: model)

        let composedPrompt: String
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            composedPrompt = "Context:\n\(context)\n\nPrompt:\n\(prompt)"
        } else {
            composedPrompt = prompt
        }

        let response = try await client.generate(prompt: composedPrompt)
        return AIResponse(text: response, provider: "ollama", tokensUsed: 0)
    }

    private func askCloud(prompt: String, context: String?, system: String?) async throws -> AIResponse {
        guard let key = apiKey, !key.isEmpty else {
            throw AIError.noApiKey
        }
        let estimatedTokens = (prompt.count + (context?.count ?? 0)) / 4

        var messages: [[String: String]] = []
        if let ctx = context {
            messages.append(["role": "user", "content": "Context:\n\(ctx)"])
        }
        messages.append(["role": "user", "content": prompt])

        var logLines = [
            "POST /v1/responses",
            "provider=openai",
            "model=\(HypeAIConfiguration.defaultOpenAIModel)",
        ]
        if let system, !system.isEmpty {
            logLines.append("SYSTEM:\n\(system)")
        }
        logLines.append("MESSAGES:\n\(messages.map { "\($0["role"] ?? "unknown"):\n\($0["content"] ?? "")" }.joined(separator: "\n"))")
        HypeLogger.shared.aiInput(logLines.joined(separator: "\n"), source: "AI Service")

        do {
            let client = OpenAIResponsesClient(apiKey: key, model: HypeAIConfiguration.defaultOpenAIModel)
            let composedPrompt = context.map { "Context:\n\($0)\n\nPrompt:\n\(prompt)" } ?? prompt
            let content = try await client.generate(prompt: composedPrompt, model: nil, system: system)
            let outputTokens = max(1, content.count / 4)

            dailyTokensUsed += estimatedTokens + outputTokens
            HypeLogger.shared.aiOutput(
                """
                POST /v1/responses
                provider=openai
                model=\(HypeAIConfiguration.defaultOpenAIModel)
                inputTokens≈\(estimatedTokens)
                outputTokens=\(outputTokens)
                RESPONSE:
                \(content)
                """,
                source: "AI Service"
            )

            return AIResponse(text: content, provider: "openai", tokensUsed: estimatedTokens + outputTokens)
        } catch {
            HypeLogger.shared.error(
                "OpenAI request failed: \(error.localizedDescription)",
                source: "AI Service"
            )
            throw error
        }
    }

    /// Add to conversation history.
    public func addToConversation(id: String, role: String, content: String) {
        if conversations[id] == nil { conversations[id] = [] }
        conversations[id]?.append((role: role, content: content))
        if let count = conversations[id]?.count, count > 200 {
            conversations[id]?.removeFirst()
        }
        if conversations.count > 100 {
            if let oldest = conversations.keys.first { conversations.removeValue(forKey: oldest) }
        }
    }
}

/// AI-specific errors.
public enum AIError: Error, Sendable {
    case noApiKey
    case budgetExceeded(used: Int, limit: Int)
    case apiError(String)
    case localModelUnavailable
}

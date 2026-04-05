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

/// Manages AI integration — routes between local (Foundation Models) and cloud (Claude).
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
        // Placeholder for Apple Foundation Models (on-device)
        // In production, this would use the Foundation Models framework
        return AIResponse(text: "[Local AI not configured — install a model to use local inference]", provider: "local", tokensUsed: 0)
    }

    private func askCloud(prompt: String, context: String?, system: String?) async throws -> AIResponse {
        guard let key = apiKey, !key.isEmpty else {
            throw AIError.noApiKey
        }

        var messages: [[String: String]] = []
        if let ctx = context {
            messages.append(["role": "user", "content": "Context:\n\(ctx)"])
        }
        messages.append(["role": "user", "content": prompt])

        var body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": messages,
        ]
        if let sys = system {
            body["system"] = sys
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(String(errorText.prefix(200)))
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = (json?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        let usage = json?["usage"] as? [String: Any]
        let inputTokens = (usage?["input_tokens"] as? Int) ?? 0
        let outputTokens = (usage?["output_tokens"] as? Int) ?? 0

        dailyTokensUsed += inputTokens + outputTokens

        return AIResponse(text: content, provider: "claude", tokensUsed: inputTokens + outputTokens)
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

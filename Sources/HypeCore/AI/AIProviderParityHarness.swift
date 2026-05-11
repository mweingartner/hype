import Foundation

public struct AIProviderParityScenario: Sendable {
    public var name: String
    public var prompt: String
    public var systemPrompt: String?
    public var tools: [OllamaTool]
    public var requiredToolNames: [String]

    public init(
        name: String,
        prompt: String,
        systemPrompt: String? = HypeTalkGuide.llmContext,
        tools: [OllamaTool] = [],
        requiredToolNames: [String] = []
    ) {
        self.name = name
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.requiredToolNames = requiredToolNames
    }
}

public struct AIProviderParityResult: Sendable, Equatable {
    public var providerName: String
    public var modelName: String
    public var availableModels: [String]
    public var generatedText: String?
    public var toolCallNames: [String]
    public var errors: [String]

    public init(
        providerName: String,
        modelName: String,
        availableModels: [String],
        generatedText: String?,
        toolCallNames: [String],
        errors: [String]
    ) {
        self.providerName = providerName
        self.modelName = modelName
        self.availableModels = availableModels
        self.generatedText = generatedText
        self.toolCallNames = toolCallNames
        self.errors = errors
    }

    public var passed: Bool {
        errors.isEmpty
    }
}

public struct AIProviderMediaParityResult: Sendable, Equatable {
    public var capability: String
    public var providerName: String
    public var passed: Bool
    public var detail: String

    public init(capability: String, providerName: String, passed: Bool, detail: String) {
        self.capability = capability
        self.providerName = providerName
        self.passed = passed
        self.detail = detail
    }
}

/// Provider-neutral regression harness for chat/tool/image/speech behavior.
///
/// CI tests use fake clients. Local/live tests can provide real OpenAI/Ollama
/// clients when credentials and services are available.
public struct AIProviderParityHarness: Sendable {
    public init() {}

    public func runTextScenario(
        _ scenario: AIProviderParityScenario,
        clients: [any HypeAIClient]
    ) async -> [AIProviderParityResult] {
        var results: [AIProviderParityResult] = []
        for client in clients {
            results.append(await runTextScenario(scenario, client: client))
        }
        return results
    }

    public func runTextScenario(
        _ scenario: AIProviderParityScenario,
        client: any HypeAIClient
    ) async -> AIProviderParityResult {
        var errors: [String] = []
        var models: [String] = []
        var generated: String?
        var toolCallNames: [String] = []

        do {
            models = try await client.availableModels()
            if models.isEmpty {
                errors.append("availableModels returned no models")
            }
        } catch {
            errors.append("availableModels failed: \(error.localizedDescription)")
        }

        do {
            generated = try await client.generate(prompt: scenario.prompt, model: nil, system: scenario.systemPrompt)
            if generated?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                errors.append("generate returned empty text")
            }
        } catch {
            errors.append("generate failed: \(error.localizedDescription)")
        }

        do {
            var messages: [OllamaMessage] = []
            if let systemPrompt = scenario.systemPrompt {
                messages.append(OllamaMessage(role: "system", content: systemPrompt))
            }
            messages.append(OllamaMessage(role: "user", content: scenario.prompt))
            let response = try await client.chat(messages: messages, tools: scenario.tools)
            toolCallNames = response.message.tool_calls?.map(\.function.name) ?? []
            for required in scenario.requiredToolNames where !toolCallNames.contains(required) {
                errors.append("missing required tool call: \(required)")
            }
            if scenario.requiredToolNames.isEmpty,
               response.message.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
               toolCallNames.isEmpty {
                errors.append("chat returned no content and no tool calls")
            }
        } catch {
            errors.append("chat failed: \(error.localizedDescription)")
        }

        return AIProviderParityResult(
            providerName: client.providerName,
            modelName: client.modelName,
            availableModels: models,
            generatedText: generated,
            toolCallNames: toolCallNames,
            errors: errors
        )
    }

    public func runImageScenario(
        providerName: String,
        prompt: String,
        client: any HypeImageGenerating
    ) async -> AIProviderMediaParityResult {
        do {
            let image = try await client.generateImage(prompt: prompt, model: nil, size: "1024x1024", quality: nil, background: nil)
            guard !image.data.isEmpty else {
                return AIProviderMediaParityResult(capability: "image", providerName: providerName, passed: false, detail: "generated image data was empty")
            }
            return AIProviderMediaParityResult(capability: "image", providerName: providerName, passed: true, detail: image.mimeType)
        } catch {
            return AIProviderMediaParityResult(capability: "image", providerName: providerName, passed: false, detail: error.localizedDescription)
        }
    }

    public func runSpeechOutputScenario(
        providerName: String,
        text: String,
        provider: SpeechOutputProvider
    ) async -> AIProviderMediaParityResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIProviderMediaParityResult(capability: "speechOutput", providerName: providerName, passed: false, detail: "text was empty")
        }
        await provider.speakAIResponse(text, source: "ProviderParity")
        return AIProviderMediaParityResult(capability: "speechOutput", providerName: providerName, passed: true, detail: "speakAIResponse completed")
    }
}

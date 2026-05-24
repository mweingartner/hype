import Foundation
import Testing
@testable import HypeCore

@Suite("AI provider parity harness")
struct AIProviderParityHarnessTests {
    @Test("text scenario validates all clients against the same tool contract")
    func textScenarioValidatesToolContract() async {
        let harness = AIProviderParityHarness()
        let scenario = AIProviderParityScenario(
            name: "Create button",
            prompt: "Create a button named Start",
            systemPrompt: "Use Hype tools.",
            requiredToolNames: ["create_button"]
        )
        let clients: [any HypeAIClient] = [
            FakeParityAIClient(providerName: "Ollama", modelName: "qwen3:8b", toolName: "create_button"),
            FakeParityAIClient(providerName: "OpenAI", modelName: "gpt-test", toolName: "create_button")
        ]

        let results = await harness.runTextScenario(scenario, clients: clients)

        #expect(results.count == 2)
        #expect(results.map { $0.passed } == [true, true])
        #expect(results.map(\.providerName) == ["Ollama", "OpenAI"])
        #expect(results.allSatisfy { $0.toolCallNames == ["create_button"] })
    }

    @Test("text scenario reports missing required tool call")
    func textScenarioReportsMissingTool() async {
        let harness = AIProviderParityHarness()
        let scenario = AIProviderParityScenario(
            name: "Create button",
            prompt: "Create a button",
            systemPrompt: "Use Hype tools.",
            requiredToolNames: ["create_button"]
        )

        let result = await harness.runTextScenario(
            scenario,
            client: FakeParityAIClient(providerName: "Ollama", modelName: "bad", toolName: "create_field")
        )

        #expect(!result.passed)
        #expect(result.errors.contains { $0.contains("missing required tool call") })
    }

    @Test("image and speech scenarios are covered without live providers")
    func mediaScenariosUseProviderContracts() async {
        let harness = AIProviderParityHarness()
        let imageResult = await harness.runImageScenario(
            providerName: "OpenAI Image",
            prompt: "blue ball",
            client: FakeImageGenerator()
        )
        let speech = RecordingSpeechOutputProvider()
        let speechResult = await harness.runSpeechOutputScenario(
            providerName: "OpenAI Speech",
            text: "Hello",
            provider: speech
        )

        #expect(imageResult.passed)
        #expect(imageResult.detail == "image/png")
        #expect(speechResult.passed)
        #expect(await speech.spokenTexts() == ["Hello"])
    }
}

private struct FakeParityAIClient: HypeAIClient {
    var providerName: String
    var modelName: String
    var toolName: String

    func availableModels() async throws -> [String] {
        [modelName]
    }

    func generate(prompt: String, model: String?, system: String?) async throws -> String {
        "generated: \(prompt)"
    }

    func chat(messages: [OllamaMessage], tools: [OllamaTool], format: OllamaResponseFormat?) async throws -> OllamaChatResponse {
        let call = OllamaToolCall(function: OllamaToolCallFunction(name: toolName, arguments: ["name": "Start"]))
        return OllamaChatResponse(message: OllamaMessage(role: "assistant", content: nil, tool_calls: [call]), done: true)
    }

    func structuredChat<Response: Decodable & Sendable>(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response) {
        throw HarnessError.notImplemented
    }

    func preloadModel() async throws {}

    func chatStream(messages: [OllamaMessage], tools: [OllamaTool]) -> AsyncStream<String> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private struct FakeImageGenerator: HypeImageGenerating {
    func generateImage(
        prompt: String,
        model: String?,
        size: String?,
        quality: String?,
        background: String?
    ) async throws -> HypeGeneratedImage {
        HypeGeneratedImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
    }
}

private actor RecordingSpeechOutputProvider: SpeechOutputProvider {
    private var values: [String] = []

    func speakAIResponse(_ text: String, source: String) async {
        values.append(text)
    }

    func spokenTexts() -> [String] {
        values
    }
}

private enum HarnessError: Error {
    case notImplemented
}

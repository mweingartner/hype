import Foundation
import Testing
@testable import HypeCore

@Suite("Ollama provider diagnostics")
struct OllamaProviderDiagnosticsTests {
    @Test("diagnostics validate native tools, OpenAI-compatible inference, and streaming")
    func diagnosticsValidateAllOllamaPaths() async throws {
        let result = try await OllamaProviderDiagnostics().run(
            nativeClient: FakeNativeOllamaClient(models: ["other-model"]),
            inferenceProvider: FakeStreamingInferenceProvider(),
            modelName: "test-model"
        )

        #expect(result.models == ["other-model"])
        #expect(result.pullStatus == "success")
        #expect(result.nativeToolDetail == "tool_calls=report_status")
        #expect(result.inferenceText == "OK")
        #expect(result.streamingText == "OK streamed")
        #expect(result.passed)
        #expect(result.summary.contains("native tools OK"))
        #expect(result.summary.contains("streaming OK"))
    }

    @Test("diagnostics skip pull when model already exists")
    func diagnosticsSkipPullWhenModelExists() async throws {
        let result = try await OllamaProviderDiagnostics().run(
            nativeClient: FakeNativeOllamaClient(models: ["test-model"]),
            inferenceProvider: FakeStreamingInferenceProvider(),
            modelName: "test-model"
        )

        #expect(result.pullStatus == nil)
        #expect(result.summary.contains("pull skipped"))
    }
}

private struct FakeNativeOllamaClient: OllamaNativeToolAPIProviding {
    var models: [String]
    var modelName: String { "test-model" }

    func availableModels() async throws -> [String] {
        models
    }

    func pullModel(_ modelName: String?) async throws -> String {
        "success"
    }

    func chat(messages: [OllamaMessage], tools: [OllamaTool], format: OllamaResponseFormat?) async throws -> OllamaChatResponse {
        let call = OllamaToolCall(function: OllamaToolCallFunction(name: "report_status", arguments: ["status": "OK"]))
        return OllamaChatResponse(message: OllamaMessage(role: "assistant", content: "", tool_calls: [call]), done: true)
    }
}

private struct FakeStreamingInferenceProvider: AIChatInferenceProviding {
    var providerName: String { "fake-openai-compatible" }
    var modelName: String { "test-model" }
    var supportsStreaming: Bool { true }

    func availableModels() async throws -> [String] {
        [modelName]
    }

    func generate(prompt: String, model: String?, system: String?) async throws -> String {
        "OK"
    }

    func chat(_ request: AIChatInferenceRequest) async throws -> OllamaChatResponse {
        OllamaChatResponse(message: OllamaMessage(role: "assistant", content: "OK"), done: true)
    }

    func chatStream(_ request: AIChatInferenceRequest) -> AsyncStream<String> {
        AsyncStream { continuation in
            continuation.yield("OK")
            continuation.yield(" streamed")
            continuation.finish()
        }
    }

    func preloadModel() async throws {}
}

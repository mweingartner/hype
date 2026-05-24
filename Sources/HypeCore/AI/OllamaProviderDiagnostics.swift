import Foundation

public protocol OllamaNativeToolAPIProviding: Sendable {
    var modelName: String { get }

    func availableModels() async throws -> [String]
    func pullModel(_ modelName: String?) async throws -> String
    func chat(messages: [OllamaMessage], tools: [OllamaTool], format: OllamaResponseFormat?) async throws -> OllamaChatResponse
}

extension OllamaToolClient: OllamaNativeToolAPIProviding {}

public struct OllamaProviderDiagnosticResult: Sendable, Equatable {
    public var models: [String]
    public var pullStatus: String?
    public var nativeToolDetail: String
    public var inferenceText: String
    public var streamingText: String

    public init(
        models: [String],
        pullStatus: String?,
        nativeToolDetail: String,
        inferenceText: String,
        streamingText: String
    ) {
        self.models = models
        self.pullStatus = pullStatus
        self.nativeToolDetail = nativeToolDetail
        self.inferenceText = inferenceText
        self.streamingText = streamingText
    }

    public var passed: Bool {
        !nativeToolDetail.isEmpty
            && !inferenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var summary: String {
        let pull = pullStatus.map { ", pull \($0)" } ?? ", pull skipped"
        return "OK: \(models.count) model(s)\(pull), native tools OK, OpenAI-compatible chat OK, streaming OK."
    }
}

public struct OllamaProviderDiagnostics: Sendable {
    public init() {}

    public func run(
        nativeClient: any OllamaNativeToolAPIProviding,
        inferenceProvider: any AIChatInferenceProviding,
        modelName: String
    ) async throws -> OllamaProviderDiagnosticResult {
        let models = try await nativeClient.availableModels()
        let pullStatus = models.contains(modelName) ? nil : try await nativeClient.pullModel(modelName)

        let nativeTool = Self.statusTool
        let nativeResponse = try await nativeClient.chat(
            messages: [
                OllamaMessage(role: "system", content: "Use the provided tool when possible."),
                OllamaMessage(role: "user", content: "Call report_status with status OK.")
            ],
            tools: [nativeTool],
            format: nil
        )
        let nativeToolDetail = Self.nativeToolDetail(from: nativeResponse)
        guard !nativeToolDetail.isEmpty else {
            throw OllamaError.requestFailed("Native Ollama tool chat returned no content and no tool calls.")
        }

        let inferenceResponse = try await inferenceProvider.chat(AIChatInferenceRequest(
            messages: [OllamaMessage(role: "user", content: "Reply with exactly: OK")],
            tools: []
        ))
        let inferenceText = inferenceResponse.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !inferenceText.isEmpty else {
            throw OllamaError.requestFailed("OpenAI-compatible Ollama chat returned empty text.")
        }

        guard inferenceProvider.supportsStreaming else {
            throw OllamaError.requestFailed("OpenAI-compatible Ollama client does not advertise streaming support.")
        }
        var streamingText = ""
        for await token in inferenceProvider.chatStream(AIChatInferenceRequest(
            messages: [OllamaMessage(role: "user", content: "Reply with exactly: OK")],
            tools: []
        )) {
            streamingText += token
        }
        streamingText = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !streamingText.isEmpty else {
            throw OllamaError.requestFailed("OpenAI-compatible Ollama streaming returned no text.")
        }

        return OllamaProviderDiagnosticResult(
            models: models,
            pullStatus: pullStatus,
            nativeToolDetail: nativeToolDetail,
            inferenceText: inferenceText,
            streamingText: streamingText
        )
    }

    private static var statusTool: OllamaTool {
        OllamaTool(
            type: "function",
            function: OllamaFunction(
                name: "report_status",
                description: "Report a short smoke-test status.",
                parameters: OllamaParameters(
                    type: "object",
                    properties: [
                        "status": OllamaProperty(type: "string", description: "Short status, for example OK")
                    ],
                    required: ["status"]
                )
            )
        )
    }

    private static func nativeToolDetail(from response: OllamaChatResponse) -> String {
        if let names = response.message.tool_calls?.map(\.function.name), !names.isEmpty {
            return "tool_calls=\(names.joined(separator: ","))"
        }
        return response.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

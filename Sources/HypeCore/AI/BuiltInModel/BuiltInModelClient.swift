import Foundation

/// What this Mac can offer a Built-in model.
public struct BuiltInDeviceProfile: Sendable, Equatable {
    public var physicalMemoryBytes: Int64
    /// Metal's recommended working set, when the engine has reported it.
    public var recommendedWorkingSetBytes: Int64?

    public init(physicalMemoryBytes: Int64, recommendedWorkingSetBytes: Int64? = nil) {
        self.physicalMemoryBytes = physicalMemoryBytes
        self.recommendedWorkingSetBytes = recommendedWorkingSetBytes
    }

    public static var current: BuiltInDeviceProfile {
        BuiltInDeviceProfile(physicalMemoryBytes: Int64(ProcessInfo.processInfo.physicalMemory))
    }

    public var physicalMemoryGB: Int {
        Int((Double(physicalMemoryBytes) / Double(1 << 30)).rounded())
    }
}

/// `HypeAIClient` backed by a model running inside the Hype process.
///
/// This is the Anticorruption Layer between Hype's chat vocabulary
/// (`OllamaMessage`, `OllamaTool`, …) and the inference engine: it resolves which
/// variant to run and where its weights are, applies the memory-fit policy, and
/// translates results. Because every AI surface talks to `HypeAIClient`, the
/// chat panel, the Script Editor, scene planning, the MCP bridge and HypeTalk's
/// `ask ai` all work with the Built-in model unchanged.
public struct BuiltInModelClient: HypeAIClient {
    public let providerName = HypeAIProvider.builtIn.rawValue
    public let modelName: String
    public let supportsChatStreaming = true

    public let variant: BuiltInModelVariant
    private let engine: any BuiltInModelEngine
    private let store: BuiltInModelStore
    private let device: BuiltInDeviceProfile
    private let thinkingEnabled: Bool
    private let contextLimitOverride: Int?

    public init(
        variant: BuiltInModelVariant,
        engine: any BuiltInModelEngine,
        store: BuiltInModelStore = BuiltInModelStore(),
        device: BuiltInDeviceProfile = .current,
        thinkingEnabled: Bool = false,
        contextLimitOverride: Int? = nil
    ) {
        self.variant = variant
        self.modelName = variant.id
        self.engine = engine
        self.store = store
        self.device = device
        self.thinkingEnabled = thinkingEnabled
        self.contextLimitOverride = contextLimitOverride
    }

    /// Builds the client for the current settings. Cheap and synchronous: the
    /// model itself loads lazily on first use, inside the engine.
    public static func make(
        defaults: UserDefaults = .standard,
        engine: (any BuiltInModelEngine)? = BuiltInModelRuntime.engine,
        store: BuiltInModelStore = BuiltInModelStore(),
        device: BuiltInDeviceProfile = .current
    ) throws -> BuiltInModelClient {
        guard let engine else { throw BuiltInModelError.engineUnavailable }
        let variant = try resolveVariant(
            id: BuiltInModelSettings.selectedVariantID(defaults: defaults),
            store: store,
            device: device
        )
        return BuiltInModelClient(
            variant: variant,
            engine: engine,
            store: store,
            device: device,
            thinkingEnabled: BuiltInModelSettings.thinkingEnabled(defaults: defaults),
            contextLimitOverride: BuiltInModelSettings.contextLimitOverride(defaults: defaults)
        )
    }

    /// "Automatic" prefers the best variant for this Mac that is already
    /// installed, so a machine that fits Max but has only downloaded Standard
    /// still works; with nothing installed it names the variant to download.
    public static func resolveVariant(
        id: String,
        store: BuiltInModelStore,
        device: BuiltInDeviceProfile
    ) throws -> BuiltInModelVariant {
        if id != BuiltInModelCatalog.automaticVariantID {
            guard let variant = BuiltInModelCatalog.variant(id: id) else {
                throw BuiltInModelError.unknownVariant(id)
            }
            return variant
        }
        let usable = BuiltInModelCatalog.variants.filter { variant in
            BuiltInMemoryFitPolicy.evaluate(
                variant: variant,
                physicalMemoryBytes: device.physicalMemoryBytes,
                recommendedWorkingSetBytes: device.recommendedWorkingSetBytes
            ).verdict != .insufficient
        }
        let installed = usable.filter { store.location(of: $0) != nil }
        let pool = installed.isEmpty ? usable : installed
        if let choice = BuiltInMemoryFitPolicy.automaticVariant(
            among: pool,
            physicalMemoryBytes: device.physicalMemoryBytes,
            recommendedWorkingSetBytes: device.recommendedWorkingSetBytes
        ) {
            return choice
        }
        let smallest = BuiltInModelCatalog.variants.min { $0.minimumPhysicalMemoryGB < $1.minimumPhysicalMemoryGB }
        throw BuiltInModelError.insufficientMemory(
            variantName: smallest?.displayName ?? "The Built-in model",
            requiredGB: smallest?.minimumPhysicalMemoryGB ?? 32,
            physicalGB: device.physicalMemoryGB
        )
    }

    // MARK: - HypeAIClient

    public func availableModels() async throws -> [String] {
        store.installedVariants().map(\.id)
    }

    public func generate(prompt: String, model: String?, system: String?) async throws -> String {
        var messages: [OllamaMessage] = []
        if let system = HypeAIConfiguration.normalized(system) {
            messages.append(OllamaMessage(role: "system", content: system))
        }
        messages.append(OllamaMessage(role: "user", content: prompt))
        // `ask ai … with model "<id>"` may name another installed variant.
        let client = try overriding(model: model)
        return try await client.run(messages: messages, tools: [], onText: nil).text
    }

    public func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?
    ) async throws -> OllamaChatResponse {
        let prompt = format.map { OllamaToolClient.messagesWithSchemaPrompt(original: messages, format: $0) } ?? messages
        let result = try await run(messages: prompt, tools: tools, onText: nil)
        return Self.response(from: result)
    }

    public func structuredChat<Response: Decodable & Sendable>(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response) {
        let response = try await chat(messages: messages, tools: tools, format: format)
        let (decoded, _) = try OllamaToolClient.decodeStructuredResponse(Response.self, from: response)
        return (response, decoded)
    }

    public func preloadModel() async throws {
        let directory = try verifiedDirectory()
        _ = try fit()
        try await engine.load(variant: variant, from: directory)
    }

    /// The variant's directory, with its weight files hashed against the catalog
    /// (once — see `BuiltInModelStore.verifyWeights`).
    private func verifiedDirectory() throws -> URL {
        let directory = try store.installedDirectory(of: variant)
        if !store.weightsAreVerified(of: variant, at: directory) {
            BuiltInModelActivity.shared.report(.verifyingModel(name: variant.displayName))
            defer { BuiltInModelActivity.shared.report(.idle) }
            try store.verifyWeights(of: variant, at: directory)
        }
        return directory
    }

    public func chatStream(messages: [OllamaMessage], tools: [OllamaTool]) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    _ = try await run(messages: messages, tools: tools) { chunk in
                        continuation.yield(chunk)
                    }
                } catch is CancellationError {
                    // The consumer went away; nothing to report.
                } catch {
                    // AsyncStream cannot throw: surface the failure as text so
                    // the author sees why the reply stopped.
                    continuation.yield("\n[Built-in model error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internals

    func fit() throws -> BuiltInMemoryFit {
        let fit = BuiltInMemoryFitPolicy.evaluate(
            variant: variant,
            physicalMemoryBytes: device.physicalMemoryBytes,
            recommendedWorkingSetBytes: device.recommendedWorkingSetBytes,
            contextLimitOverride: contextLimitOverride
        )
        guard fit.verdict != .insufficient else {
            throw BuiltInModelError.insufficientMemory(
                variantName: variant.displayName,
                requiredGB: variant.minimumPhysicalMemoryGB,
                physicalGB: device.physicalMemoryGB
            )
        }
        return fit
    }

    private func overriding(model: String?) throws -> BuiltInModelClient {
        guard let id = HypeAIConfiguration.normalized(model), id != variant.id else { return self }
        guard let other = BuiltInModelCatalog.variant(id: id) else {
            // Scripts written for another provider name models we do not have
            // ("llama3.2"); the selected Built-in variant answers instead.
            return self
        }
        return BuiltInModelClient(
            variant: other,
            engine: engine,
            store: store,
            device: device,
            thinkingEnabled: thinkingEnabled,
            contextLimitOverride: contextLimitOverride
        )
    }

    private func run(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        onText: (@Sendable (String) -> Void)?
    ) async throws -> BuiltInGenerationResult {
        let directory = try verifiedDirectory()
        let fit = try fit()
        let request = BuiltInGenerationRequest(
            variant: variant,
            modelDirectory: directory,
            messages: messages,
            tools: tools,
            enableThinking: thinkingEnabled,
            contextTokenLimit: fit.contextTokenLimit,
            kvCacheBits: fit.kvCacheBits,
            kvQuantizationStartTokens: fit.kvQuantizationStartTokens
        )
        return try await engine.generate(request, onText: onText)
    }

    /// Hype's chat vocabulary for one engine result.
    public static func response(from result: BuiltInGenerationResult) -> OllamaChatResponse {
        let calls = result.toolCalls.map { call in
            OllamaToolCall(function: OllamaToolCallFunction(name: call.name, arguments: call.arguments))
        }
        return OllamaChatResponse(
            message: OllamaMessage(
                role: "assistant",
                content: result.text,
                thinking: HypeAIConfiguration.normalized(result.thinking),
                tool_calls: calls.isEmpty ? nil : calls
            ),
            done: true
        )
    }
}

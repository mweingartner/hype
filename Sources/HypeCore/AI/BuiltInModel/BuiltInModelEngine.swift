import Foundation

/// One generation request handed to the in-process inference engine.
///
/// This is the boundary between Hype's chat vocabulary and whatever runtime
/// executes the model. HypeCore never imports that runtime (MLX needs Metal and
/// must not leak into the portable interpreter kernel); the app registers a
/// concrete `BuiltInModelEngine` at launch.
public struct BuiltInGenerationRequest: Sendable {
    public var variant: BuiltInModelVariant
    /// Directory holding the variant's verified weight files.
    public var modelDirectory: URL
    public var messages: [OllamaMessage]
    public var tools: [OllamaTool]
    public var maxTokens: Int
    public var temperature: Double
    public var topP: Double
    public var enableThinking: Bool
    /// Hard cap on prompt + generated tokens, from `BuiltInMemoryFitPolicy`.
    public var contextTokenLimit: Int
    /// Quantize the growing attention KV cache to this many bits (nil = 16-bit)…
    public var kvCacheBits: Int?
    /// …but only once the cache holds at least this many tokens.
    public var kvQuantizationStartTokens: Int
    /// Text markers that start per-turn sections of an otherwise static prompt
    /// (Hype's system prompt ends with a `CURRENT STATE:` block). The engine
    /// checkpoints its prompt cache just before the first marker so that the
    /// tools + rules + guide prefix is prefilled once, not once per message.
    public var cacheBoundaryMarkers: [String]

    public init(
        variant: BuiltInModelVariant,
        modelDirectory: URL,
        messages: [OllamaMessage],
        tools: [OllamaTool],
        maxTokens: Int = BuiltInModelSettings.defaultMaxTokens,
        temperature: Double = BuiltInModelSettings.defaultTemperature,
        topP: Double = BuiltInModelSettings.defaultTopP,
        enableThinking: Bool = false,
        contextTokenLimit: Int,
        kvCacheBits: Int? = nil,
        kvQuantizationStartTokens: Int = 0,
        cacheBoundaryMarkers: [String] = BuiltInModelSettings.promptCacheBoundaryMarkers
    ) {
        self.variant = variant
        self.modelDirectory = modelDirectory
        self.messages = messages
        self.tools = tools
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.enableThinking = enableThinking
        self.contextTokenLimit = contextTokenLimit
        self.kvCacheBits = kvCacheBits
        self.kvQuantizationStartTokens = kvQuantizationStartTokens
        self.cacheBoundaryMarkers = cacheBoundaryMarkers
    }
}

/// What the engine produced for one request.
public struct BuiltInGenerationResult: Sendable, Equatable {
    public var text: String
    public var thinking: String?
    public var toolCalls: [BuiltInToolCall]
    public var promptTokens: Int
    /// Prompt tokens served from the reused prompt cache (not re-prefilled).
    public var cachedPromptTokens: Int
    public var generatedTokens: Int
    public var promptSeconds: Double
    public var generationSeconds: Double
    /// True when generation stopped because `maxTokens` or the context cap hit.
    public var truncated: Bool

    public init(
        text: String,
        thinking: String? = nil,
        toolCalls: [BuiltInToolCall] = [],
        promptTokens: Int = 0,
        cachedPromptTokens: Int = 0,
        generatedTokens: Int = 0,
        promptSeconds: Double = 0,
        generationSeconds: Double = 0,
        truncated: Bool = false
    ) {
        self.text = text
        self.thinking = thinking
        self.toolCalls = toolCalls
        self.promptTokens = promptTokens
        self.cachedPromptTokens = cachedPromptTokens
        self.generatedTokens = generatedTokens
        self.promptSeconds = promptSeconds
        self.generationSeconds = generationSeconds
        self.truncated = truncated
    }

    public var tokensPerSecond: Double {
        generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0
    }
}

/// A tool call parsed by the engine. Arguments are strings because every Hype
/// authoring tool takes string-typed arguments (`OllamaToolCallFunction`).
public struct BuiltInToolCall: Sendable, Equatable {
    public var name: String
    public var arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

/// What the engine currently holds in memory.
public struct BuiltInEngineStatus: Sendable, Equatable {
    public var loadedVariantID: String?
    /// Bytes of GPU memory the engine reports as active, when known.
    public var activeMemoryBytes: Int64?
    /// Metal's recommended working-set ceiling for this device, when known.
    public var recommendedWorkingSetBytes: Int64?

    public init(
        loadedVariantID: String? = nil,
        activeMemoryBytes: Int64? = nil,
        recommendedWorkingSetBytes: Int64? = nil
    ) {
        self.loadedVariantID = loadedVariantID
        self.activeMemoryBytes = activeMemoryBytes
        self.recommendedWorkingSetBytes = recommendedWorkingSetBytes
    }
}

/// The in-process inference runtime behind the Built-in model.
///
/// Contract:
/// - One model is resident at a time; asking for a different variant unloads
///   the previous one first.
/// - Requests are served strictly one at a time, in arrival order. Concurrent
///   GPU submission is a documented macOS kernel-panic trigger.
/// - `onText` receives visible assistant text as it is decoded (never tool-call
///   markup or thinking text).
/// - Cancelling the calling task stops generation at the next token.
public protocol BuiltInModelEngine: Sendable {
    func load(variant: BuiltInModelVariant, from directory: URL) async throws
    func generate(
        _ request: BuiltInGenerationRequest,
        onText: (@Sendable (String) -> Void)?
    ) async throws -> BuiltInGenerationResult
    func unload() async
    func status() async -> BuiltInEngineStatus
}

public enum BuiltInModelError: Error, LocalizedError, Equatable {
    case engineUnavailable
    case notInstalled(variantName: String)
    case insufficientMemory(variantName: String, requiredGB: Int, physicalGB: Int)
    case unknownVariant(String)
    case promptTooLong(promptTokens: Int, limit: Int)
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "The Built-in model is not available in this build of Hype."
        case .notInstalled(let name):
            return "The Built-in model \(name) is not installed. Download it in Settings → AI."
        case .insufficientMemory(let name, let required, let physical):
            return "\(name) needs a Mac with at least \(required) GB of memory (this Mac has \(physical) GB)."
        case .unknownVariant(let id):
            return "Unknown Built-in model \"\(id)\"."
        case .promptTooLong(let promptTokens, let limit):
            return "The request is \(promptTokens) tokens, over the \(limit)-token limit the Built-in model can hold in memory on this Mac. Start a new chat or reduce the AI context."
        case .generationFailed(let message):
            return "The Built-in model failed: \(message)"
        }
    }
}

/// Process-wide registration point for the inference engine.
///
/// `HypeAIConfiguration.makeClient` is synchronous and lives in HypeCore, which
/// cannot name the MLX-backed engine. The Hype app registers it once at launch;
/// the CLI and tests leave it unset (or register a fake).
public enum BuiltInModelRuntime {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registeredEngine: (any BuiltInModelEngine)?

    public static func register(engine: (any BuiltInModelEngine)?) {
        lock.lock()
        defer { lock.unlock() }
        registeredEngine = engine
    }

    public static var engine: (any BuiltInModelEngine)? {
        lock.lock()
        defer { lock.unlock() }
        return registeredEngine
    }
}

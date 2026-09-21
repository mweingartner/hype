#if canImport(MLXLLM)
import Foundation
import HypeCore
import MLX
import MLXLLM
import MLXLMCommon

/// Runs Hype's Built-in model in-process on Apple's MLX.
///
/// One model is resident at a time and requests are served strictly one at a
/// time, in arrival order: concurrent GPU submission and load/unload churn are
/// documented triggers of an unfixed macOS IOGPU kernel panic. For the same
/// reason the engine never raises MLX's wired-memory limit.
public actor MLXBuiltInModelEngine: BuiltInModelEngine {
    public static let shared = MLXBuiltInModelEngine()

    private struct Loaded {
        let variantID: String
        let directory: URL
        let container: ModelContainer
        let session: PromptCacheSession
    }

    private var loaded: Loaded?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    // MARK: - BuiltInModelEngine

    public func load(variant: BuiltInModelVariant, from directory: URL) async throws {
        await acquire()
        defer {
            BuiltInModelActivity.shared.report(.idle)
            release()
        }
        _ = try await loadIfNeeded(variant: variant, directory: directory)
    }

    public func generate(
        _ request: BuiltInGenerationRequest,
        onText: (@Sendable (String) -> Void)?
    ) async throws -> BuiltInGenerationResult {
        await acquire()
        defer {
            BuiltInModelActivity.shared.report(.idle)
            release()
        }
        try Task.checkCancellation()
        let model = try await loadIfNeeded(variant: request.variant, directory: request.modelDirectory)
        let session = model.session
        do {
            return try await model.container.perform { context in
                try await Self.run(request, context: context, session: session, onText: onText)
            }
        } catch let error as BuiltInModelError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The cache may be half-written; start clean next time.
            session.reset()
            throw BuiltInModelError.generationFailed(Self.describe(error))
        }
    }

    public func unload() async {
        await acquire()
        defer { release() }
        loaded = nil
        Memory.clearCache()
    }

    public func status() async -> BuiltInEngineStatus {
        BuiltInEngineStatus(
            loadedVariantID: loaded?.variantID,
            activeMemoryBytes: Int64(Memory.activeMemory),
            recommendedWorkingSetBytes: GPU.maxRecommendedWorkingSetBytes().map(Int64.init)
        )
    }

    /// Metal's recommended working set for this Mac, without loading a model.
    public nonisolated static func recommendedWorkingSetBytes() -> Int64? {
        GPU.maxRecommendedWorkingSetBytes().map(Int64.init)
    }

    // MARK: - Loading

    private func loadIfNeeded(variant: BuiltInModelVariant, directory: URL) async throws -> Loaded {
        if let loaded, loaded.variantID == variant.id, loaded.directory == directory {
            return loaded
        }
        BuiltInModelActivity.shared.report(.loadingModel(name: variant.displayName))
        // Release the previous model before allocating the next one.
        loaded = nil
        Memory.clearCache()
        // MLX's buffer cache defaults to its memory limit; keep recycled buffers
        // from growing into the headroom left for the author's other apps.
        Memory.cacheLimit = variant.tier == .max ? 4 << 30 : 1 << 30

        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                from: directory,
                using: LocalTokenizerLoader()
            )
            let model = Loaded(
                variantID: variant.id,
                directory: directory,
                container: container,
                session: PromptCacheSession()
            )
            loaded = model
            return model
        } catch {
            throw BuiltInModelError.generationFailed("could not load \(variant.displayName): \(Self.describe(error))")
        }
    }

    // MARK: - One request (runs inside the container's isolation)

    private static func run(
        _ request: BuiltInGenerationRequest,
        context: ModelContext,
        session: PromptCacheSession,
        onText: (@Sendable (String) -> Void)?
    ) async throws -> BuiltInGenerationResult {
        guard let tokenizer = context.tokenizer as? LocalTokenizer else {
            throw BuiltInModelError.generationFailed("unexpected tokenizer type")
        }
        let tools = request.tools.isEmpty ? nil : ChatRendering.templateTools(from: request.tools)
        var additionalContext: [String: any Sendable] = [:]
        if case .templateFlag(let key) = request.variant.thinkingControl {
            additionalContext[key] = request.enableThinking
        }
        let templateContext = additionalContext.isEmpty ? nil : additionalContext

        // Keep everything up to the first user turn static, whatever order the
        // model's template renders system text and tool schemas in.
        var promptMessages = request.messages
        if let tools, toolsFollowSystemText(tools: tools, templateContext: templateContext, tokenizer: tokenizer, session: session) {
            promptMessages = ChatRendering.relocatingPerTurnBlock(
                in: promptMessages, markers: request.cacheBoundaryMarkers)
        }
        let messages = ChatRendering.templateMessages(from: promptMessages)

        let tokens = try tokenizer.render(
            messages: messages, tools: tools, additionalContext: templateContext, addGenerationPrompt: true)
        let reserve = 64
        guard tokens.count + reserve <= request.contextTokenLimit else {
            throw BuiltInModelError.promptTooLong(promptTokens: tokens.count, limit: request.contextTokenLimit)
        }
        let maxNewTokens = max(1, min(request.maxTokens, request.contextTokenLimit - tokens.count))

        let turnBoundary = try Self.turnBoundary(
            tokens: tokens, messages: messages, tools: tools, templateContext: templateContext,
            thinking: request.enableThinking, tokenizer: tokenizer, session: session)
        let staticBoundary = try Self.staticBoundary(
            tokens: tokens, systemMessage: promptMessages.first, markers: request.cacheBoundaryMarkers,
            tools: tools, templateContext: templateContext, tokenizer: tokenizer, session: session)

        let parameters = GenerateParameters(
            maxTokens: maxNewTokens,
            temperature: Float(request.temperature),
            topP: Float(request.topP),
            prefillStepSize: request.variant.tier == .max ? 2048 : 1024
        )

        if ProcessInfo.processInfo.environment["HYPE_BUILTIN_DEBUG"] != nil {
            let staticTokens = staticBoundary.map { Array(tokens[..<$0]) } ?? []
            let digest = staticTokens.reduce(into: UInt64(1469598103934665603)) { $0 = ($0 ^ UInt64(truncatingIfNeeded: $1)) &* 1099511628211 }
            FileHandle.standardError.write(Data(
                "[built-in] prompt=\(tokens.count) static=\(staticBoundary ?? -1) turn=\(turnBoundary) staticDigest=\(String(digest, radix: 16))\n".utf8))
        }

        let prefillStart = Date()
        let preparation = try session.prepare(
            tokens: tokens,
            staticBoundary: staticBoundary,
            turnBoundary: turnBoundary,
            model: context.model,
            parameters: parameters,
            kvCacheBits: request.kvCacheBits,
            kvQuantizationStart: request.kvQuantizationStartTokens,
            // HYPE_BUILTIN_NO_DISK_CACHE is a troubleshooting switch.
            diskCache: ProcessInfo.processInfo.environment["HYPE_BUILTIN_NO_DISK_CACHE"] != nil
                ? nil
                : PromptPrefixDiskCache(
                    variantID: request.variant.id,
                    revision: request.variant.revision,
                    kvCacheBits: request.kvCacheBits,
                    kvQuantizationStart: request.kvQuantizationStartTokens),
            onPrefillProgress: { processed, total in
                BuiltInModelActivity.shared.report(.readingPrompt(processedTokens: processed, totalTokens: total))
            }
        )
        BuiltInModelActivity.shared.report(.generating)
        let manualPrefillSeconds = Date().timeIntervalSince(prefillStart)

        let input = LMInput(tokens: MLXArray(preparation.remaining.map(Int32.init)))
        let iterator = try TokenIterator(
            input: input, model: context.model, cache: session.cache, parameters: parameters)
        // The runtime infers the tool-call markup from the architecture name and
        // falls back to JSON; a variant that knows better says so.
        var configuration = context.configuration
        if request.variant.toolCallSyntax == .xmlFunction {
            configuration.toolCallFormat = .xmlFunction
        }
        let (stream, task) = generateTask(
            promptTokenCount: tokens.count,
            modelConfiguration: configuration,
            tokenizer: context.tokenizer,
            iterator: iterator,
            tools: tools
        )

        // With thinking on, Qwen-style templates open the <think> block in the
        // generation prompt, so the reply starts inside it.
        let promptTail = tokenizer.decode(tokenIds: Array(tokens.suffix(8)), skipSpecialTokens: false)
        var filter = ThinkingFilter(
            startsInsideThinking: promptTail.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("<think>"))
        var text = ""
        var toolCalls: [BuiltInToolCall] = []
        var info: GenerateCompletionInfo?

        await withTaskCancellationHandler {
            for await event in stream {
                switch event {
                case .chunk(let chunk):
                    let visible = filter.consume(chunk)
                    if !visible.isEmpty {
                        text += visible
                        onText?(visible)
                    }
                case .toolCall(let call):
                    toolCalls.append(ChatRendering.toolCall(from: call))
                case .info(let completion):
                    info = completion
                }
            }
            // The cache is shared with the next request: wait until the
            // generation task has really stopped touching it.
            await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()

        let tail = filter.finish()
        if !tail.isEmpty {
            text += tail
            onText?(tail)
        }

        return BuiltInGenerationResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            thinking: filter.thinking.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: toolCalls,
            promptTokens: tokens.count,
            cachedPromptTokens: preparation.reusedTokens,
            generatedTokens: info?.generationTokenCount ?? 0,
            promptSeconds: manualPrefillSeconds + (info?.promptTime ?? 0),
            generationSeconds: info?.generateTime ?? 0,
            truncated: info?.stopReason == .length
        )
    }

    /// Token index where the last rendered message ends and the generation
    /// prompt begins. The generation prompt differs from how the same assistant
    /// turn is rendered as history (e.g. an empty `<think>` block), so a
    /// checkpoint taken after it would never be reusable.
    private static func turnBoundary(
        tokens: [Int],
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        templateContext: [String: any Sendable]?,
        thinking: Bool,
        tokenizer: LocalTokenizer,
        session: PromptCacheSession
    ) throws -> Int {
        if let length = session.generationPromptLength[thinking], length < tokens.count {
            return tokens.count - length
        }
        let withoutPrompt = try tokenizer.render(
            messages: messages, tools: tools, additionalContext: templateContext, addGenerationPrompt: false)
        let shared = commonPrefixLength(tokens, withoutPrompt)
        let boundary = min(max(shared, 0), tokens.count - 1)
        let length = tokens.count - boundary
        if (1...64).contains(length) {
            session.generationPromptLength[thinking] = length
        }
        return boundary
    }

    /// Token index just before the first per-turn section of the system prompt.
    private static func staticBoundary(
        tokens: [Int],
        systemMessage: OllamaMessage?,
        markers: [String],
        tools: [[String: any Sendable]]?,
        templateContext: [String: any Sendable]?,
        tokenizer: LocalTokenizer,
        session: PromptCacheSession
    ) throws -> Int? {
        if let checkpoint = session.staticCheckpoint, tokens.starts(with: checkpoint.tokens) {
            return checkpoint.tokens.count
        }
        guard let system = systemMessage, system.role == "system", let content = system.content else { return nil }
        // A relocated per-turn block leaves a system message that is static
        // throughout; otherwise the static part ends at the first marker.
        let staticText: String
        if let cut = staticPrefixEnd(of: content, markers: markers) {
            staticText = String(content[..<cut])
        } else if markers.isEmpty {
            return nil
        } else {
            staticText = content
        }
        let staticOnly = OllamaMessage(role: "system", content: staticText)
        // Some templates (Qwen3.5) refuse to render without a user turn; the
        // placeholder lies past the point where the two renders diverge.
        let placeholder = OllamaMessage(role: "user", content: "-")
        let rendered = try tokenizer.render(
            messages: ChatRendering.templateMessages(from: [staticOnly, placeholder]),
            tools: tools,
            additionalContext: templateContext,
            addGenerationPrompt: false
        )
        let shared = commonPrefixLength(tokens, rendered)
        // Not worth a checkpoint unless it saves a meaningful prefill.
        return shared >= 512 ? shared : nil
    }

    /// Does this model's template put the tool schemas after the system text?
    /// Asked once per loaded model, by rendering a two-line conversation.
    private static func toolsFollowSystemText(
        tools: [[String: any Sendable]],
        templateContext: [String: any Sendable]?,
        tokenizer: LocalTokenizer,
        session: PromptCacheSession
    ) -> Bool {
        if let known = session.toolsFollowSystemText { return known }
        let sentinel = "HYPE-LAYOUT-PROBE-SYSTEM-TEXT"
        let probeTool: [String: any Sendable] = [
            "type": "function",
            "function": [
                "name": "hype_layout_probe_tool",
                "description": "probe",
                "parameters": ["type": "object", "properties": [String: any Sendable](), "required": [String]()] as [String: any Sendable],
            ] as [String: any Sendable],
        ]
        var answer = false
        if let rendered = try? tokenizer.render(
            messages: ChatRendering.templateMessages(from: [
                OllamaMessage(role: "system", content: sentinel), OllamaMessage(role: "user", content: "-"),
            ]),
            tools: [probeTool], additionalContext: templateContext, addGenerationPrompt: false) {
            let text = tokenizer.decode(tokenIds: rendered, skipSpecialTokens: false)
            if let system = text.range(of: sentinel), let tool = text.range(of: "hype_layout_probe_tool") {
                answer = tool.lowerBound > system.lowerBound
            }
        }
        session.toolsFollowSystemText = answer
        return answer
    }

    /// Third-party errors (Jinja, tokenizers) rarely localize; keep their detail.
    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    /// Where the static part of a system prompt ends: the FIRST occurrence of any
    /// marker, deliberately. Everything before it is prompt text Hype authored
    /// (rules, guide). A later occurrence could come from a part name or an AI
    /// Context note, and cutting there would pull per-document state into the
    /// persisted "static" prefix.
    static func staticPrefixEnd(of content: String, markers: [String]) -> String.Index? {
        markers.compactMap { content.range(of: $0)?.lowerBound }.min()
    }

    private static func commonPrefixLength(_ lhs: [Int], _ rhs: [Int]) -> Int {
        var index = 0
        let limit = min(lhs.count, rhs.count)
        while index < limit, lhs[index] == rhs[index] { index += 1 }
        return index
    }

    // MARK: - Strict FIFO admission

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Registers the MLX engine as Hype's Built-in model runtime. Call once at launch.
public enum HypeMLXRuntime {
    public static func registerEngine() {
        BuiltInModelRuntime.register(engine: MLXBuiltInModelEngine.shared)
    }

    /// Metal's recommended working set for this Mac (no model needs to be loaded).
    public static func recommendedWorkingSetBytes() -> Int64? {
        MLXBuiltInModelEngine.recommendedWorkingSetBytes()
    }
}
#else
import HypeCore

/// MLX is macOS-only; elsewhere the Built-in model is simply unavailable.
public enum HypeMLXRuntime {
    public static func registerEngine() {}
    public static func recommendedWorkingSetBytes() -> Int64? { nil }
}
#endif

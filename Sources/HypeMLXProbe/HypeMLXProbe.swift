import ArgumentParser
import Foundation
import HypeCore
import HypeMLX

/// Headless end-to-end probe for the Built-in model: the real engine, the real
/// HypeTalk guide, the real authoring tool catalog and the real tool executor —
/// without the GUI. Used to verify tool loops, prompt-cache reuse, speed and
/// memory on a given Mac.
@main
struct HypeMLXProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hype-mlx-probe",
        abstract: "Run Hype's Built-in model against a headless stack."
    )

    @Option(help: "Built-in model variant id, or 'auto'.")
    var variant: String = BuiltInModelCatalog.automaticVariantID

    @Option(help: "Use an arbitrary local MLX model directory instead of an installed variant.")
    var modelDirectory: String?

    @Flag(help: "With --model-directory: the model wraps tool calls in <function=…> XML (Granite 4.2, Qwen3-Coder).")
    var xmlToolCalls = false

    @Option(help: "With --model-directory: attention KV-cache bytes per token at 16-bit (layers x KV heads x head dim x 4).")
    var kvBytesPerToken: Int?

    @Option(help: "The author's request.")
    var prompt: String = "Add a button named \"Hello\" that puts \"Hello, world\" into a new field named \"Greeting\" when clicked."

    @Option(help: "Maximum tool-loop rounds.")
    var rounds: Int = 8

    @Flag(help: "Send a short prompt with no guide and no tools (plain `ask ai` path).")
    var plain = false

    @Flag(help: "Let the model think before answering.")
    var thinking = false

    @Option(help: "Pretend this Mac has this many GB of memory (tests the fit policy).")
    var pretendMemoryGB: Int?

    @Option(help: "Force 8-bit KV once the cache holds this many tokens (tests the 16-bit → 8-bit hand-over).")
    var kvQuantizationStart: Int?

    @Option(help: "Run this many separate chats, each on a fresh stack (tests checkpoint reuse across chats).")
    var chats: Int = 1

    @Option(help: "Run the authoring tournament: a prompts JSONL (scripts/ai-training/eval/comprehensive_prompts.jsonl).")
    var tournament: String?

    @Option(help: "Tournament: write one JSON line per prompt (grade, rounds, transcript) to this file.")
    var tournamentOut: String?

    @Option(help: "Tournament: only the first N prompts.")
    var limit: Int?

    @Flag(help: "Tournament: build the test stack, print how it was seeded and its CURRENT STATE, then exit.")
    var seedOnly = false

    mutating func run() async throws {
        if seedOnly {
            let seeded = await TournamentStack.make()
            seeded.log.forEach { print($0) }
            let prompt = TournamentStack.systemPrompt(for: seeded.document, cardId: seeded.currentCardId)
            print(prompt[(prompt.range(of: "CURRENT STATE:")?.lowerBound ?? prompt.startIndex)...])
            return
        }
        HypeMLXRuntime.registerEngine()
        guard let engine = BuiltInModelRuntime.engine else {
            throw ValidationError("The MLX engine is not available on this platform.")
        }

        let store = BuiltInModelStore()
        var device = BuiltInDeviceProfile.current
        device.recommendedWorkingSetBytes = (await engine.status()).recommendedWorkingSetBytes
        if let pretendMemoryGB {
            device = BuiltInDeviceProfile(physicalMemoryBytes: Int64(pretendMemoryGB) << 30)
        }

        var selected = try BuiltInModelClient.resolveVariant(id: variant, store: store, device: device)
        var probeStore = store
        if let modelDirectory {
            // Register the directory as an ad-hoc variant through a throwaway
            // defaults suite, leaving the user's settings untouched.
            selected = Self.adHocVariant(
                basedOn: selected, directory: modelDirectory,
                toolCallSyntax: xmlToolCalls ? .xmlFunction : selected.toolCallSyntax,
                kvBytesPerToken: kvBytesPerToken ?? selected.kvBytesPerToken)
            let suite = "hype.mlx.probe.\(UUID().uuidString)"
            UserDefaults(suiteName: suite)?.set(modelDirectory, forKey: BuiltInModelSettings.modelDirectoryKeyPrefix + selected.id)
            probeStore = BuiltInModelStore(defaultsSuiteName: suite, integrity: .sizesOnly)
        }

        let client = BuiltInModelClient(
            variant: selected, engine: engine, store: probeStore, device: device, thinkingEnabled: thinking)
        var fit = BuiltInMemoryFitPolicy.evaluate(
            variant: selected,
            physicalMemoryBytes: device.physicalMemoryBytes,
            recommendedWorkingSetBytes: device.recommendedWorkingSetBytes)
        if let kvQuantizationStart {
            fit.kvCacheBits = 8
            fit.kvQuantizationStartTokens = kvQuantizationStart
        }
        print("variant: \(selected.id)  location: \(probeStore.location(of: selected).map { "\($0)" } ?? "not installed")")
        print("device: \(device.physicalMemoryGB) GB  fit: \(fit.verdict.rawValue)  context cap: \(fit.contextTokenLimit)  kv bits: \(fit.kvCacheBits.map { "16, then \($0) after \(fit.kvQuantizationStartTokens) tokens" } ?? "16")")

        let loadStart = Date()
        try await client.preloadModel()
        print(String(format: "load: %.1fs  active memory: %.2f GB", Date().timeIntervalSince(loadStart), Self.activeGB(await engine.status())))

        if plain {
            let start = Date()
            let answer = try await client.generate(prompt: prompt, model: nil, system: "Answer in one short sentence.")
            print(String(format: "ask ai (%.1fs): %@", Date().timeIntervalSince(start), answer))
            return
        }
        let directory = try probeStore.installedDirectory(of: selected)
        if let tournament {
            try await runTournament(
                promptsPath: tournament, engine: engine, directory: directory, fit: fit, variant: selected)
            return
        }
        for chat in 1...max(chats, 1) {
            if chats > 1 { print("=== chat \(chat) ===") }
            try await runAuthoringLoop(client: client, engine: engine, directory: directory, fit: fit, variant: selected)
        }
    }

    private func runAuthoringLoop(
        client: BuiltInModelClient,
        engine: any BuiltInModelEngine,
        directory: URL,
        fit: BuiltInMemoryFit,
        variant: BuiltInModelVariant
    ) async throws {
        var document = HypeDocument.newDocument(name: "Probe Stack")
        var currentCardId = document.sortedCards[0].id
        let executor = HypeToolExecutor()
        let tools = HypeToolDefinitions.cardControlAuthoringTools
        var messages = [
            OllamaMessage(role: "system", content: Self.systemPrompt(for: document, cardId: currentCardId)),
            OllamaMessage(role: "user", content: prompt),
        ]
        print("tools: \(tools.count)  system prompt: \(messages[0].content?.count ?? 0) chars")

        for round in 1...max(rounds, 1) {
            let request = BuiltInGenerationRequest(
                variant: variant, modelDirectory: directory, messages: messages, tools: tools,
                enableThinking: thinking, contextTokenLimit: fit.contextTokenLimit, kvCacheBits: fit.kvCacheBits,
                kvQuantizationStartTokens: fit.kvQuantizationStartTokens)
            let start = Date()
            let result = try await engine.generate(request, onText: nil)
            let elapsed = Date().timeIntervalSince(start)
            print(String(
                format: "round %d: %.1fs  prompt %d tok (%d cached, prefill %.1fs)  gen %d tok @ %.1f tok/s  mem %.2f GB",
                round, elapsed, result.promptTokens, result.cachedPromptTokens, result.promptSeconds,
                result.generatedTokens, result.tokensPerSecond, Self.activeGB(await engine.status())))

            let response = BuiltInModelClient.response(from: result)
            messages.append(response.message)
            guard !result.toolCalls.isEmpty else {
                print("assistant: \(result.text)")
                break
            }
            for call in result.toolCalls {
                let output = await executor.execute(
                    toolName: call.name, arguments: call.arguments, document: &document, currentCardId: currentCardId)
                if output.hasPrefix("CREATED_CARD:"), let id = UUID(uuidString: String(output.dropFirst("CREATED_CARD:".count))) {
                    currentCardId = id
                }
                print("  tool \(call.name)(\(call.arguments.keys.sorted().joined(separator: ", "))) -> \(output.prefix(160))")
                messages.append(OllamaMessage(role: "tool", content: output))
            }
        }

        print("--- resulting card ---")
        for part in document.parts where part.cardId == currentCardId {
            print("\(part.partType) \"\(part.name)\"" + (part.script.isEmpty ? "" : "\n" + part.script.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")))
        }
    }

    /// One fresh stack and one fresh chat per prompt, as the chat panel would run
    /// it: the loop ends when the model answers without calling a tool.
    private func runTournament(
        promptsPath: String,
        engine: any BuiltInModelEngine,
        directory: URL,
        fit: BuiltInMemoryFit,
        variant: BuiltInModelVariant
    ) async throws {
        var prompts = try TournamentPrompt.load(from: promptsPath)
        if let limit { prompts = Array(prompts.prefix(limit)) }
        // The chat panel gives SpriteKit requests the scene tool surface. Each
        // surface is its own static prompt prefix, so run them back to back.
        let reference = await TournamentStack.make()
        let routed = prompts.map { prompt in
            (prompt, SpriteKitRequestRouter.route(
                prompt: prompt.prompt, document: reference.document, currentCardId: reference.currentCardId
            ).isSpriteKitRequest)
        }
        let ordered = routed.filter { !$0.1 } + routed.filter { $0.1 }
        print("tool surfaces: \(routed.filter { !$0.1 }.count) card-control prompts, \(routed.filter { $0.1 }.count) sprite-scene prompts")
        let executor = HypeToolExecutor()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var outcomes: [TournamentOutcome] = []
        var sink: FileHandle?
        if let tournamentOut {
            let path = (tournamentOut as NSString).expandingTildeInPath
            FileManager.default.createFile(atPath: path, contents: nil)
            sink = FileHandle(forWritingAtPath: path)
        }
        defer { try? sink?.close() }
        let started = Date()

        for (index, (prompt, isSpriteKitRequest)) in ordered.enumerated() {
            let tools = isSpriteKitRequest
                ? HypeToolDefinitions.spriteSceneAuthoringTools
                : HypeToolDefinitions.cardControlAuthoringTools
            var seeded = await TournamentStack.make()
            var messages = [
                OllamaMessage(role: "system", content: TournamentStack.systemPrompt(for: seeded.document, cardId: seeded.currentCardId)),
                OllamaMessage(role: "user", content: prompt.prompt),
            ]
            var transcript: [String] = []
            var ending = "round_cap"
            var usedRounds = 0
            var generated = 0
            let promptStart = Date()

            roundLoop: for round in 1...max(rounds, 1) {
                usedRounds = round
                let request = BuiltInGenerationRequest(
                    variant: variant, modelDirectory: directory, messages: messages, tools: tools,
                    enableThinking: thinking, contextTokenLimit: fit.contextTokenLimit, kvCacheBits: fit.kvCacheBits,
                    kvQuantizationStartTokens: fit.kvQuantizationStartTokens)
                let result: BuiltInGenerationResult
                do {
                    result = try await engine.generate(request, onText: nil)
                } catch {
                    transcript.append("[engine error: \(error.localizedDescription)]")
                    ending = "error"
                    break roundLoop
                }
                generated += result.generatedTokens
                transcript.append(TournamentGrader.transcriptLine(text: result.text, toolCalls: result.toolCalls))
                messages.append(BuiltInModelClient.response(from: result).message)
                guard !result.toolCalls.isEmpty else {
                    ending = "answered"
                    break roundLoop
                }
                for call in result.toolCalls {
                    var output = await executor.execute(
                        toolName: call.name, arguments: call.arguments,
                        document: &seeded.document, currentCardId: seeded.currentCardId)
                    // What the chat panel does with the executor's two control results.
                    if output.hasPrefix("CREATED_CARD:") {
                        if let id = UUID(uuidString: String(output.dropFirst(13))) { seeded.currentCardId = id }
                        output = "Created new card. Now working on the new card."
                    } else if output.hasPrefix("NAVIGATE:") {
                        let destination = String(output.dropFirst(9))
                        if let card = seeded.document.cards.first(where: { $0.name.lowercased() == destination.lowercased() }) {
                            seeded.currentCardId = card.id
                        }
                        output = "Navigated to card \(destination)."
                    }
                    messages.append(OllamaMessage(role: "tool", content: output))
                }
            }

            let output = transcript.joined(separator: "\n---\n")
            let grade = TournamentGrader.grade(prompt, output: output)
            let outcome = TournamentOutcome(
                id: prompt.id, category: prompt.category,
                passed: grade.missing.isEmpty && grade.forbidden.isEmpty,
                missingRequired: grade.missing, presentForbidden: grade.forbidden,
                rounds: usedRounds, terminatedBy: ending,
                seconds: Date().timeIntervalSince(promptStart), generatedTokens: generated, output: output)
            outcomes.append(outcome)
            if let sink, let line = try? encoder.encode(outcome) {
                sink.write(line)
                sink.write(Data("\n".utf8))
            }
            print(String(
                format: "  [%d/%d] %@  %@  [%d rounds, %@] (%.1fs)",
                index + 1, prompts.count, outcome.passed ? "PASS" : "FAIL", prompt.id, usedRounds, ending, outcome.seconds))
            fflush(stdout)
        }

        print(String(format: "--- %.1f min, %.2f GB active ---", Date().timeIntervalSince(started) / 60, Self.activeGB(await engine.status())))
        print(TournamentGrader.report(outcomes, label: variant.id))
    }

    /// The authoring prompt's shape: static rules + the full HypeTalk guide,
    /// then the per-message CURRENT STATE block (mirrors AIChatPanel).
    static func systemPrompt(for document: HypeDocument, cardId: UUID) -> String {
        let parts = document.parts.filter { $0.cardId == cardId }.map { "\($0.partType) \"\($0.name)\"" }
        return """
        You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is \(document.stack.width)x\(document.stack.height) points.

        RULES:
        - Call the needed tools to fulfill the user's request, then STOP and respond with a brief summary.
        - Do NOT repeat tool calls you have already made.
        - When CURRENT STATE shows a part already exists with the requested name, MODIFY it with `set_part_property` instead of creating a duplicate.
        - Before storing any HypeTalk script, call `check_script` and fix what it reports.
        - For button scripts, just provide the HypeTalk command (e.g. "go next"). It will be auto-wrapped in on mouseUp/end mouseUp.
        - When writing HypeTalk scripts, use ONLY valid HypeTalk syntax as described in the guide below.

        \(HypeTalkGuide.llmContext)

        CURRENT STATE:
        Stack: "\(document.stack.name)" (\(document.cards.count) cards)
        Card parts: \(parts.isEmpty ? "none" : parts.joined(separator: ", "))
        """
    }

    static func activeGB(_ status: BuiltInEngineStatus) -> Double {
        Double(status.activeMemoryBytes ?? 0) / 1_000_000_000
    }

    /// A stand-in variant for `--model-directory`: every safetensors/json file
    /// in the directory, sized as found, so the store accepts it as complete.
    static func adHocVariant(
        basedOn base: BuiltInModelVariant,
        directory: String,
        toolCallSyntax: BuiltInToolCallSyntax,
        kvBytesPerToken: Int
    ) -> BuiltInModelVariant {
        let url = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let files = names.sorted().compactMap { name -> BuiltInModelFile? in
            guard name.hasSuffix(".safetensors") || name.hasSuffix(".json") || name.hasSuffix(".jinja") else { return nil }
            let resolved = url.appendingPathComponent(name).resolvingSymlinksInPath()
            guard let size = (try? FileManager.default.attributesOfItem(atPath: resolved.path))?[.size] as? NSNumber else { return nil }
            return BuiltInModelFile(path: name, size: size.int64Value, sha256: String(repeating: "0", count: 64))
        }
        return BuiltInModelVariant(
            id: "probe-" + url.lastPathComponent,
            displayName: url.lastPathComponent,
            summary: "ad-hoc probe model",
            tier: base.tier,
            huggingFaceRepo: "local/probe",
            revision: String(repeating: "0", count: 40),
            files: files,
            license: "unknown",
            licenseURL: "",
            kvBytesPerToken: kvBytesPerToken,
            fixedOverheadBytes: base.fixedOverheadBytes,
            nativeContextTokens: base.nativeContextTokens,
            minimumPhysicalMemoryGB: 8,
            recommendedPhysicalMemoryGB: 8,
            supportsVision: false,
            thinkingControl: base.thinkingControl,
            toolCallSyntax: toolCallSyntax
        )
    }
}

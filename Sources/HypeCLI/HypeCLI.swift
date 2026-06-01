import Foundation
import HypeCore
import ArgumentParser
import Darwin
import CryptoKit

@main
struct HypeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hypetalk",
        abstract: "HypeTalk interpreter CLI"
    )

    @Argument(help: "HypeTalk script to execute. Omit with --benchmark to run the built-in suite.")
    var script: String?

    @Option(help: "Path to a .hype document to load")
    var document: String?

    @Option(help: "Handler name to invoke (default: main)")
    var handler: String = "main"

    @Flag(help: "Run scripts in benchmark mode and print timing plus execution diagnostics")
    var benchmark = false

    @Option(help: "Benchmark iterations per case")
    var benchmarkIterations = 10

    @Option(help: "Benchmark output format: text or json")
    var benchmarkFormat: HypeTalkBenchmarkFormat = .text

    @Flag(help: "Run an OpenAI-compatible inference smoke test instead of a HypeTalk script")
    var inferenceSmoke = false

    @Option(help: "Inference smoke provider: openai or openai-compatible")
    var inferenceProvider: InferenceSmokeProvider = .openAICompatible

    @Option(help: "OpenAI-compatible inference base URL, for example http://localhost:8001/v1")
    var inferenceBaseURL: String?

    @Option(help: "Model name to send in the inference smoke test")
    var inferenceModel = HypeAIConfiguration.defaultLlamaSwapModel

    @Option(help: "Prompt to send in the inference smoke test")
    var inferencePrompt = "Reply with OK."

    @Option(help: "Bearer token for inference smoke tests. For OpenAI, this overrides Keychain only for the CLI smoke test.")
    var inferenceAPIKey: String?

    @Option(help: "Environment variable that contains the bearer token for inference smoke tests")
    var inferenceAPIKeyEnv: String?

    @Flag(help: "Print non-secret endpoint and header diagnostics before sending the inference smoke request")
    var inferencePrintDiagnostics = false

    @Flag(help: "Run an Ollama tool API smoke test: model query, pull, and tool chat")
    var ollamaToolSmoke = false

    @Option(help: "Ollama host for --ollama-tool-smoke")
    var ollamaHost = "localhost"

    @Option(help: "Ollama port for --ollama-tool-smoke")
    var ollamaPort = "11434"

    @Option(help: "Ollama model for --ollama-tool-smoke query/pull/chat")
    var ollamaModel = "llama3.2"

    @Option(name: .customLong("import-hypercard"), help: "Import one classic HyperCard stack and print a tab-separated summary")
    var importHyperCard: String?

    @Option(help: "Scan a directory of classic stacks/archives and print tab-separated import summaries")
    var importCorpus: String?

    @Option(help: "Write a single --import-hypercard result to this .hype package path")
    var output: String?

    @Option(help: "Write --import-corpus successful imports as .hype packages in this directory")
    var outputDir: String?

    @Option(help: "Automation import target platforms, comma-separated: macOS, iPhone, iPad, tvOS. Defaults to macOS.")
    var targetPlatforms: String?

    @Option(help: "Automation import primary target platform. Defaults to the first selected target.")
    var primaryTargetPlatform: String?

    @Option(help: "Maximum source files to scan with --import-corpus")
    var importLimit: Int?

    @Option(help: "Minimum candidate file size for --import-corpus")
    var importMinBytes = 4096

    @Flag(help: "Print failed import attempts during --import-corpus")
    var importShowFailures = false

    @Option(help: "unar executable for extracting .sit/.hqx corpus inputs")
    var unarPath = "/opt/homebrew/bin/unar"

    @Option(help: "Validate every stored script in a .hype package or JSON HypeDocument without executing handlers")
    var validateScripts: String?

    @Option(help: "Validate one .hype package's SQLite storage and print a tab-separated diagnostic row")
    var validatePackage: String?

    @Option(help: "With --validate-scripts, export each stored script as a standalone .hypetalk file in this directory")
    var exportScripts: String?

    mutating func run() async throws {
        if output != nil && importHyperCard == nil {
            throw ValidationError("--output requires --import-hypercard")
        }
        if outputDir != nil && importCorpus == nil {
            throw ValidationError("--output-dir requires --import-corpus")
        }
        if outputDir != nil && importHyperCard != nil {
            throw ValidationError("--output-dir requires --import-corpus")
        }
        if output != nil && importCorpus != nil {
            throw ValidationError("--output requires --import-hypercard")
        }
        if exportScripts != nil && validateScripts == nil {
            throw ValidationError("--export-scripts requires --validate-scripts")
        }
        if validatePackage != nil && validateScripts != nil {
            throw ValidationError("--validate-package cannot be combined with --validate-scripts")
        }

        if let validatePackage {
            let report = try validatePackageFile(at: URL(fileURLWithPath: validatePackage))
            print(report.tsvHeader)
            print(report.tsvLine)
            if !report.isHealthy {
                throw HypeCLIError.validationFailed(1)
            }
            return
        }

        if let validateScripts {
            let document = try loadDocument(at: URL(fileURLWithPath: validateScripts))
            let exportURL = exportScripts.map { URL(fileURLWithPath: $0) }
            let report = try validateStoredScripts(in: document, exportDirectory: exportURL)
            print(report.tsvHeader)
            for row in report.results {
                print(row.tsvLine)
            }
            if report.failureCount > 0 {
                throw HypeCLIError.validationFailed(report.failureCount)
            }
            return
        }

        if let importHyperCard {
            let summary = try importOneHyperCardStack(URL(fileURLWithPath: importHyperCard))
            if let output {
                try saveImportedDocument(summary.document, to: URL(fileURLWithPath: output))
            }
            print(summary.tsvHeader)
            print(summary.tsvLine)
            return
        }

        if let importCorpus {
            try runImportCorpus(URL(fileURLWithPath: importCorpus))
            return
        }

        if ollamaToolSmoke {
            try await runOllamaToolSmoke()
            return
        }

        if inferenceSmoke {
            try await runInferenceSmoke()
            return
        }

        if benchmark {
            let cases: [HypeTalkBenchmarkSuite.Case]
            if let script, script != "suite" {
                cases = [
                    HypeTalkBenchmarkSuite.Case(
                        name: URL(fileURLWithPath: script).lastPathComponent,
                        script: try loadScript(script),
                        handler: handler
                    )
                ]
            } else {
                cases = HypeTalkBenchmarkSuite.cases
            }
            let report = try HypeTalkBenchmarkRunner(iterations: benchmarkIterations)
                .run(cases: cases, documentPath: document)
            try printBenchmarkReport(report, format: benchmarkFormat)
            return
        }

        guard let scriptSource = script else {
            throw ValidationError("Missing expected argument '<script>'")
        }

        let script = try loadScript(scriptSource)

        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let ast = try parser.parse()

        let targetHandler: Handler
        if let h = ast.handlers.first(where: { $0.name.lowercased() == handler.lowercased() }) {
            targetHandler = h
        } else if let h = ast.handlers.first {
            targetHandler = h
        } else {
            throw HypeCLIError.noHandlerFound
        }

        var doc: HypeDocument
        if let docPath = document {
            let data = try Data(contentsOf: URL(fileURLWithPath: docPath))
            doc = try JSONDecoder().decode(HypeDocument.self, from: data)
        } else {
            doc = HypeDocument.newDocument()
        }

        let context = ExecutionContext(
            targetId: doc.cards[0].id,
            currentCardId: doc.cards[0].id,
            document: doc,
            dialogProvider: StubDialogProvider(),
            drawingProvider: StubDrawingProvider(),
            systemProvider: StubSystemProvider(),
            aiProvider: StubAIScriptingProvider(),
            speechOutputProvider: StubSpeechOutputProvider()
        )

        let interpreter = Interpreter()
        let result = interpreter.execute(handler: targetHandler, params: [], context: context)

        switch result.status {
        case .completed:
            if let rv = result.returnValue, !rv.isEmpty {
                print(rv)
            }
        case .passed:
            print("OK")
        case .cancelled:
            fputs("cancelled\n", stderr)
            throw HypeCLIError.executionFailed
        case .error:
            if let err = result.error {
                fputs("error: \(err.message) (line \(err.line))\n", stderr)
            } else {
                fputs("error: unknown\n", stderr)
            }
            throw HypeCLIError.executionFailed
        }
    }

    private func runInferenceSmoke() async throws {
        let inference: any AIChatInferenceProviding
        switch inferenceProvider {
        case .openAI:
            let apiKey: String
            if let smokeKey = resolvedInferenceAPIKey {
                apiKey = smokeKey
            } else {
                apiKey = try KeychainStore.getSecret(account: KeychainStore.openAIAPIKeyAccount)
            }
            let model = resolvedOpenAIInferenceModel
            if inferencePrintDiagnostics {
                printOpenAIDiagnostics(apiKey: apiKey, model: model)
                fflush(stdout)
            }
            let client = OpenAIResponsesClient(apiKey: apiKey, model: model)
            inference = HypeAIClientChatInferenceProvider(client: client)

        case .openAICompatible:
            guard let inferenceBaseURL,
                  let baseURL = URL(string: inferenceBaseURL) else {
                throw ValidationError("--inference-base-url is required for --inference-provider openai-compatible, for example http://localhost:8001/v1")
            }
            let configuration = OpenAIChatCompletionsClient.Configuration.openAICompatible(
                baseURL: baseURL,
                apiKey: resolvedInferenceAPIKey,
                model: inferenceModel,
                providerName: "cli-openai-compatible"
            )
            if inferencePrintDiagnostics {
                printOpenAICompatibleDiagnostics(configuration)
                fflush(stdout)
            }
            let client = OpenAIChatCompletionsClient(configuration: configuration)
            inference = HypeAIClientChatInferenceProvider(client: client)
        }

        var content = ""
        for await token in inference.chatStream(AIChatInferenceRequest(
            messages: [OllamaMessage(role: "user", content: inferencePrompt)],
            tools: []
        )) {
            content += token
        }

        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            throw ValidationError("Inference response was empty")
        }
        print(content)
    }

    private var resolvedOpenAIInferenceModel: String {
        inferenceModel == HypeAIConfiguration.defaultLlamaSwapModel
            ? HypeAIConfiguration.defaultOpenAIModel
            : inferenceModel
    }

    private var resolvedInferenceAPIKey: String? {
        if let key = normalized(inferenceAPIKey) {
            return key
        }
        if let envName = normalized(inferenceAPIKeyEnv),
           let value = normalized(ProcessInfo.processInfo.environment[envName]) {
            return value
        }
        return nil
    }

    private func printOpenAICompatibleDiagnostics(_ configuration: OpenAIChatCompletionsClient.Configuration) {
        let endpoint = Self.endpoint(configuration.chatCompletionsPath, baseURL: configuration.baseURL)
        let authState = normalized(configuration.apiKey) == nil ? "none" : "Bearer <redacted>"
        print("provider: \(configuration.providerName)")
        print("endpoint: POST \(endpoint.absoluteString)")
        print("headers: Content-Type=application/json; Authorization=\(authState)")
        print("model: \(configuration.model)")
    }

    private func printOpenAIDiagnostics(apiKey: String?, model: String) {
        let authState = normalized(apiKey) == nil ? "none" : "Bearer <redacted>"
        let reasoning = OpenAIResponsesClient.reasoningOptions(for: model)
        print("provider: openai")
        print("endpoint: POST https://api.openai.com/v1/responses")
        print("headers: Content-Type=application/json; Accept=text/event-stream; Authorization=\(authState)")
        print("stream: true")
        print("model: \(model)")
        if let reasoning {
            print("reasoning: effort=\(reasoning.effort); summary=\(reasoning.summary)")
        } else {
            print("reasoning: unsupported for model")
        }
    }

    private static func endpoint(_ path: String, baseURL: URL) -> URL {
        var components = path.split(separator: "/").map(String.init)
        if baseURL.path.split(separator: "/").last == "v1", components.first == "v1" {
            components.removeFirst()
        }
        return components.reduce(baseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func runOllamaToolSmoke() async throws {
        let client = OllamaToolClient(
            host: ollamaHost,
            port: ollamaPort,
            model: ollamaModel,
            timeouts: .chat
        )

        let models = try await client.availableModels()
        if !models.contains(ollamaModel) {
            let status = try await client.pullModel(ollamaModel)
            print("pull: \(status)")
        } else {
            print("pull: skipped (model already present)")
        }

        let tool = OllamaTool(
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
        let response = try await client.chat(
            messages: [
                OllamaMessage(role: "system", content: "Use the provided tool when possible."),
                OllamaMessage(role: "user", content: "Call report_status with status OK.")
            ],
            tools: [tool]
        )
        let toolNames = response.message.tool_calls?.map(\.function.name) ?? []
        print("models: \(models.count)")
        print("chat: \(toolNames.isEmpty ? (response.message.content ?? "no tool calls") : toolNames.joined(separator: ","))")
    }

    private func loadScript(_ source: String) throws -> String {
        let script: String
        if source == "/dev/stdin" || source == "-" {
            script = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } else if FileManager.default.fileExists(atPath: source) {
            script = try String(contentsOfFile: source, encoding: .utf8)
        } else {
            script = source
        }
        return script
    }

    private func importOneHyperCardStack(_ url: URL) throws -> ImportSummary {
        let result = try StackImportCImporter(
            options: HyperCardImportOptions(deploymentTargets: try automationDeploymentTargets())
        ).importStack(at: url)
        return ImportSummary(sourceURL: url, document: result.document)
    }

    private func automationDeploymentTargets() throws -> StackDeploymentTargets {
        let selected = try parseTargetPlatforms(targetPlatforms)
        let primary = try parsePrimaryTargetPlatform(primaryTargetPlatform, selectedPlatforms: selected)
        return .automationDefault(selectedPlatforms: selected.isEmpty ? [.macOS] : selected, primaryPlatform: primary)
    }

    private func parseTargetPlatforms(_ value: String?) throws -> [HypeTargetPlatform] {
        guard let value = normalized(value) else { return [] }
        let components = value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let platforms = components.compactMap(HypeTargetPlatform.parse)
        guard platforms.count == components.count else {
            throw ValidationError("--target-platforms must contain only: macOS, iPhone, iPad, tvOS")
        }
        return platforms
    }

    private func parsePrimaryTargetPlatform(
        _ value: String?,
        selectedPlatforms: [HypeTargetPlatform]
    ) throws -> HypeTargetPlatform? {
        guard let value = normalized(value) else { return nil }
        guard let platform = HypeTargetPlatform.parse(value) else {
            throw ValidationError("--primary-target-platform must be one of: macOS, iPhone, iPad, tvOS")
        }
        let selected = selectedPlatforms.isEmpty ? [HypeTargetPlatform.macOS] : selectedPlatforms
        guard selected.contains(platform) else {
            throw ValidationError("--primary-target-platform must be included in --target-platforms")
        }
        return platform
    }

    private func runImportCorpus(_ rootURL: URL) throws {
        let fileManager = FileManager.default
        let unarURL = URL(fileURLWithPath: unarPath)
        let canExtractArchives = fileManager.isExecutableFile(atPath: unarURL.path)
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("hype-cli-import-corpus-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let sources = corpusSourceFiles(rootURL)
        var scanned = 0
        var attempted = 0
        var imported = 0
        var archiveSkipped = 0
        var failures = 0
        var printedHeader = false

        for source in sources {
            if let importLimit, scanned >= importLimit { break }
            scanned += 1

            let candidates: [URL]
            if isArchive(source) {
                guard canExtractArchives else {
                    archiveSkipped += 1
                    continue
                }
                candidates = extractArchive(source, into: workspace)
            } else {
                candidates = [source]
            }

            for candidate in candidates {
                guard candidateFileSize(candidate) >= importMinBytes else { continue }
                attempted += 1
                do {
                    let summary = try importOneHyperCardStack(candidate)
                    if let outputDir {
                        let packageURL = try nextCorpusOutputURL(
                            for: summary,
                            in: URL(fileURLWithPath: outputDir)
                        )
                        try saveImportedDocument(summary.document, to: packageURL)
                    }
                    if !printedHeader {
                        print(summary.tsvHeader)
                        printedHeader = true
                    }
                    print(summary.tsvLine)
                    imported += 1
                } catch {
                    failures += 1
                    if importShowFailures {
                        fputs("failed\t\(candidate.path)\t\(error.localizedDescription)\n", stderr)
                    }
                }
            }
        }

        fputs("summary\tscanned=\(scanned)\tattempted=\(attempted)\timported=\(imported)\tfailed=\(failures)\tarchiveSkipped=\(archiveSkipped)\n", stderr)
    }

    private func corpusSourceFiles(_ rootURL: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { return nil }
            let name = url.lastPathComponent
            guard name != ".mirror-manifest.tsv", name != ".mirror.log" else { return nil }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    private func extractArchive(_ source: URL, into workspace: URL) -> [URL] {
        let output = workspace.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: unarPath)
        process.arguments = ["-quiet", "-force-overwrite", "-output-directory", output.path, source.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        return corpusSourceFiles(output)
    }

    private func isArchive(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        return lower.hasSuffix(".sit") || lower.hasSuffix(".hqx")
    }

    private func candidateFileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func saveImportedDocument(_ document: HypeDocument, to packageURL: URL) throws {
        try HypeSQLiteStackStore().save(document, toPackageAt: packageURL)
    }

    private func loadDocument(at url: URL) throws -> HypeDocument {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent(HypeSQLiteStackStore.manifestFileName).path) {
            return try HypeSQLiteStackStore().load(fromPackageAt: url)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(HypeDocument.self, from: data)
    }

    private func validatePackageFile(at packageURL: URL) throws -> PackageValidationReport {
        let store = HypeSQLiteStackStore()
        let diagnostics = try store.validate(packageURL: packageURL)
        let document = try store.load(fromPackageAt: packageURL)
        return PackageValidationReport(
            path: packageURL.path,
            stackName: document.stack.name,
            documentVersion: document.documentVersion,
            cardCount: document.cards.count,
            backgroundCount: document.backgrounds.count,
            partCount: document.parts.count,
            assetCount: document.assetRepository.assets.count,
            integrityCheck: diagnostics.integrityCheck,
            foreignKeyViolationCount: diagnostics.foreignKeyViolationCount,
            missingAssetReferenceCount: diagnostics.missingAssetReferenceCount,
            searchEntryCount: diagnostics.searchEntryCount,
            isHealthy: diagnostics.isHealthy
        )
    }

    private func validateStoredScripts(in document: HypeDocument, exportDirectory: URL?) throws -> ScriptValidationReport {
        let scripts = storedScripts(in: document)
        if let exportDirectory {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }

        var results: [ScriptValidationResult] = []
        for (index, script) in scripts.enumerated() {
            let fileName = exportDirectory.map { _ in exportedScriptFileName(index: index, script: script) }
            if let exportDirectory, let fileName {
                try normalizedScriptText(script.source).write(
                    to: exportDirectory.appendingPathComponent(fileName),
                    atomically: true,
                    encoding: .utf8
                )
            }

            results.append(validate(script: script, document: document, fileName: fileName))
        }

        let report = ScriptValidationReport(results: results)
        if let exportDirectory {
            try writeScriptValidationArtifacts(report, to: exportDirectory)
        }

        return report
    }

    private func storedScripts(in document: HypeDocument) -> [StoredScript] {
        var scripts: [StoredScript] = []
        scripts.append(StoredScript(
            ownerType: "stack",
            ownerId: document.stack.id,
            ownerName: document.stack.name,
            ownerPath: "stack \(document.stack.name)",
            currentCardId: document.cards.first?.id,
            source: document.stack.script
        ))
        scripts.append(contentsOf: document.backgrounds.enumerated().map { index, background in
            StoredScript(
                ownerType: "background",
                ownerId: background.id,
                ownerName: background.name,
                ownerPath: "background \(index + 1) \(background.name)",
                currentCardId: document.cards.first(where: { $0.backgroundId == background.id })?.id ?? document.cards.first?.id,
                source: background.script
            )
        })
        scripts.append(contentsOf: document.cards.enumerated().map { index, card in
            StoredScript(
                ownerType: "card",
                ownerId: card.id,
                ownerName: card.name,
                ownerPath: "card \(index + 1) \(card.name)",
                currentCardId: card.id,
                source: card.script
            )
        })
        scripts.append(contentsOf: document.parts.map { part in
            StoredScript(
                ownerType: part.partType.rawValue,
                ownerId: part.id,
                ownerName: part.name,
                ownerPath: ownerPath(for: part, in: document),
                currentCardId: currentCardId(for: part, in: document),
                source: part.script
            )
        })
        return scripts.filter { !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func validate(script: StoredScript, document: HypeDocument, fileName: String?) -> ScriptValidationResult {
        do {
            var lexer = Lexer(source: script.source)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            let parsed = try parser.parse()
            let semanticIssues = ScriptSemanticValidator(document: document).validate(parsed: parsed, owner: script)
            return ScriptValidationResult(
                script: script,
                status: semanticIssues.isEmpty ? "ok" : "warning",
                handlerCount: parsed.handlers.count,
                line: nil,
                message: semanticIssues.map(\.message).joined(separator: " | "),
                fileName: fileName,
                failureFileName: semanticIssues.isEmpty ? nil : failureDiagnosticFileName(fileName: fileName, script: script),
                semanticIssues: semanticIssues
            )
        } catch {
            let message = error.localizedDescription
            return ScriptValidationResult(
                script: script,
                status: "error",
                handlerCount: 0,
                line: parseErrorLine(from: message),
                message: message,
                fileName: fileName,
                failureFileName: failureDiagnosticFileName(fileName: fileName, script: script),
                semanticIssues: []
            )
        }
    }

    private func currentCardId(for part: Part, in document: HypeDocument) -> UUID? {
        if let cardId = part.cardId {
            return cardId
        }
        if let backgroundId = part.backgroundId,
           let card = document.cards.first(where: { $0.backgroundId == backgroundId }) {
            return card.id
        }
        return document.cards.first?.id
    }

    private func ownerPath(for part: Part, in document: HypeDocument) -> String {
        if let cardId = part.cardId,
           let index = document.cards.firstIndex(where: { $0.id == cardId }) {
            return "card \(index + 1) \(document.cards[index].name) / \(part.partType.rawValue) \(part.name)"
        }
        if let backgroundId = part.backgroundId,
           let index = document.backgrounds.firstIndex(where: { $0.id == backgroundId }) {
            return "background \(index + 1) \(document.backgrounds[index].name) / \(part.partType.rawValue) \(part.name)"
        }
        return "\(part.partType.rawValue) \(part.name)"
    }

    private func exportedScriptFileName(index: Int, script: StoredScript) -> String {
        let ownerName = safePackageBaseName(script.ownerName, fallback: script.ownerType)
        return String(format: "%04d-%@-%@.hypetalk", index + 1, script.ownerType, ownerName)
    }

    private func normalizedScriptText(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func writeScriptValidationArtifacts(_ report: ScriptValidationReport, to exportDirectory: URL) throws {
        let manifest = ([ScriptValidationResult.tsvHeader] + report.results.map(\.tsvLine)).joined(separator: "\n") + "\n"
        try manifest.write(
            to: exportDirectory.appendingPathComponent("scripts.tsv"),
            atomically: true,
            encoding: .utf8
        )

        let summary = [
            "scripts\t\(report.results.count)",
            "ok\t\(report.successCount)",
            "warning\t\(report.warningCount)",
            "error\t\(report.failureCount)",
            "exportedAt\t\(ISO8601DateFormatter().string(from: Date()))",
        ].joined(separator: "\n") + "\n"
        try summary.write(
            to: exportDirectory.appendingPathComponent("summary.txt"),
            atomically: true,
            encoding: .utf8
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let records = report.results.map(ScriptValidationRecord.init(result:))
        try encoder.encode(records).write(to: exportDirectory.appendingPathComponent("scripts.json"), options: [.atomic])

        let failureDirectory = exportDirectory.appendingPathComponent("failures", isDirectory: true)
        for result in report.results where result.status != "ok" {
            guard let failureFileName = result.failureFileName else { continue }
            try FileManager.default.createDirectory(at: failureDirectory, withIntermediateDirectories: true)
            try failureDiagnosticText(for: result).write(
                to: failureDirectory.appendingPathComponent(failureFileName),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func failureDiagnosticFileName(fileName: String?, script: StoredScript) -> String {
        if let fileName {
            return URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent + ".error.txt"
        }
        return safePackageBaseName("\(script.ownerType)-\(script.ownerName)", fallback: "script") + ".error.txt"
    }

    private func failureDiagnosticText(for result: ScriptValidationResult) -> String {
        let normalized = normalizedScriptText(result.script.source)
        let lines = normalized.components(separatedBy: "\n")
        let errorLine = result.line ?? 1
        let start = max(1, errorLine - 3)
        let end = min(lines.count, errorLine + 3)
        let context = (start...max(start, end)).compactMap { lineNumber -> String? in
            guard lineNumber >= 1, lineNumber <= lines.count else { return nil }
            let marker = lineNumber == errorLine ? ">" : " "
            return "\(marker) \(lineNumber): \(lines[lineNumber - 1])"
        }.joined(separator: "\n")

        return """
        ownerType: \(result.script.ownerType)
        ownerName: \(result.script.ownerName)
        ownerPath: \(result.script.ownerPath)
        ownerId: \(result.script.ownerId.uuidString)
        file: \(result.fileName ?? "")
        line: \(result.line.map(String.init) ?? "")
        message: \(result.message)
        semanticIssues:
        \(result.semanticIssues.map { "- \($0.message)" }.joined(separator: "\n"))

        \(context)
        """
    }

    private func parseErrorLine(from message: String) -> Int? {
        guard message.hasPrefix("Line ") else { return nil }
        let remainder = message.dropFirst("Line ".count)
        let digits = remainder.prefix { $0.isNumber }
        return Int(digits)
    }

    private func nextCorpusOutputURL(for summary: ImportSummary, in outputDir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let baseName = safePackageBaseName(summary.document.stack.name, fallback: summary.sourceURL.deletingPathExtension().lastPathComponent)
        var candidate = outputDir.appendingPathComponent("\(baseName).hype", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = outputDir.appendingPathComponent("\(baseName)-\(suffix).hype", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private func safePackageBaseName(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        let filtered = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(filtered)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- \t\r\n"))
        if collapsed.isEmpty {
            return safePackageBaseName(fallback, fallback: "Imported HyperCard Stack")
        }
        return collapsed
    }
}

private struct StoredScript {
    var ownerType: String
    var ownerId: UUID
    var ownerName: String
    var ownerPath: String
    var currentCardId: UUID?
    var source: String
}

private struct ScriptValidationReport {
    var results: [ScriptValidationResult]

    var tsvHeader: String {
        ScriptValidationResult.tsvHeader
    }

    var failureCount: Int {
        results.filter { $0.status == "error" }.count
    }

    var warningCount: Int {
        results.filter { $0.status == "warning" }.count
    }

    var successCount: Int {
        results.filter { $0.status == "ok" }.count
    }
}

private struct ScriptSemanticIssue: Codable {
    var kind: String
    var message: String
}

private struct ScriptValidationResult {
    var script: StoredScript
    var status: String
    var handlerCount: Int
    var line: Int?
    var message: String
    var fileName: String?
    var failureFileName: String?
    var semanticIssues: [ScriptSemanticIssue]

    static let tsvHeader = "status\townerType\townerName\townerPath\townerId\thandlers\tline\tfile\tfailureFile\tsourceBytes\tnormalizedBytes\tsha256\tlineEndings\tmessage"

    var tsvLine: String {
        [
            status,
            sanitize(script.ownerType),
            sanitize(script.ownerName),
            sanitize(script.ownerPath),
            script.ownerId.uuidString,
            "\(handlerCount)",
            line.map(String.init) ?? "",
            sanitize(fileName ?? ""),
            sanitize(failureFileName ?? ""),
            "\(sourceBytes)",
            "\(normalizedBytes)",
            sourceSHA256,
            sanitize(lineEndingSummary),
            sanitize(message),
        ].joined(separator: "\t")
    }

    var normalizedSource: String {
        script.source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    var sourceBytes: Int {
        script.source.data(using: .utf8)?.count ?? 0
    }

    var normalizedBytes: Int {
        normalizedSource.data(using: .utf8)?.count ?? 0
    }

    var sourceSHA256: String {
        guard let data = script.source.data(using: .utf8) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var lineEndingSummary: String {
        var crlf = 0
        var cr = 0
        var lf = 0
        let characters = Array(script.source)
        var index = 0
        while index < characters.count {
            if characters[index] == "\r" {
                if index + 1 < characters.count, characters[index + 1] == "\n" {
                    crlf += 1
                    index += 2
                } else {
                    cr += 1
                    index += 1
                }
            } else if characters[index] == "\n" {
                lf += 1
                index += 1
            } else {
                index += 1
            }
        }
        return "crlf=\(crlf),cr=\(cr),lf=\(lf)"
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

private struct ScriptValidationRecord: Encodable {
    var status: String
    var ownerType: String
    var ownerName: String
    var ownerPath: String
    var ownerId: String
    var handlers: Int
    var line: Int?
    var file: String?
    var failureFile: String?
    var message: String
    var sourceBytes: Int
    var normalizedBytes: Int
    var sha256: String
    var lineEndings: String
    var semanticIssues: [ScriptSemanticIssue]

    init(result: ScriptValidationResult) {
        status = result.status
        ownerType = result.script.ownerType
        ownerName = result.script.ownerName
        ownerPath = result.script.ownerPath
        ownerId = result.script.ownerId.uuidString
        handlers = result.handlerCount
        line = result.line
        file = result.fileName
        failureFile = result.failureFileName
        message = result.message
        sourceBytes = result.sourceBytes
        normalizedBytes = result.normalizedBytes
        sha256 = result.sourceSHA256
        lineEndings = result.lineEndingSummary
        semanticIssues = result.semanticIssues
    }
}

private struct ScriptSemanticValidator {
    var document: HypeDocument

    func validate(parsed: Script, owner: StoredScript) -> [ScriptSemanticIssue] {
        var issues: [ScriptSemanticIssue] = []
        let handlerNames = Set(parsed.handlers.map { $0.name.lowercased() })
        let functionNames = Set(parsed.handlers.filter { $0.handlerType == .function }.map { $0.name.lowercased() })
        let messageNames = Set(parsed.handlers.filter { $0.handlerType == .message }.map { $0.name.lowercased() })

        issues += sourceCompatibilityIssues(owner.source)
        for handler in parsed.handlers {
            issues += hookIssues(handler: handler, owner: owner)
            for statement in handler.body {
                issues += statementIssues(
                    statement,
                    owner: owner,
                    handlerNames: handlerNames,
                    messageNames: messageNames,
                    functionNames: functionNames
                )
            }
        }
        return stableUnique(issues)
    }

    private func sourceCompatibilityIssues(_ source: String) -> [ScriptSemanticIssue] {
        var issues: [ScriptSemanticIssue] = []
        if matches(source, pattern: #"(?im)^\s*visual\s+effect\s+.+\b(?:fast|slow|very fast|very slow)\b"#) {
            issues.append(issue("visual-speed", "HyperCard visual-effect speed words such as `fast`/`slow` are not translated to Hype transition durations."))
        }
        return issues
    }

    private func hookIssues(handler: Handler, owner: StoredScript) -> [ScriptSemanticIssue] {
        guard handler.handlerType == .message else { return [] }
        let name = handler.name.lowercased()
        guard Self.knownRuntimeHooks.contains(name) else { return [] }
        guard !allowedHooks(for: owner.ownerType).contains(name) else { return [] }
        return [issue("hook-context", "`on \(handler.name)` is a known runtime hook, but it is not normally dispatched for \(owner.ownerType) scripts.")]
    }

    private func statementIssues(
        _ statement: Statement,
        owner: StoredScript,
        handlerNames: Set<String>,
        messageNames: Set<String>,
        functionNames: Set<String>
    ) -> [ScriptSemanticIssue] {
        var issues: [ScriptSemanticIssue] = []
        switch statement {
        case .expressionStatement(.variable(let name)):
            if messageNames.contains(name.lowercased()) {
                issues.append(issue("bare-handler-call", "`\(name)` is a local handler name, but a bare line is evaluated as a variable in Hype. Use `send \"\(name)\" to me`."))
            }
        case .expressionStatement(let expression):
            issues += expressionIssues(expression, owner: owner, functionNames: functionNames)
        case .send(let message, let target):
            issues += expressionIssues(message, owner: owner, functionNames: functionNames)
            if let target {
                issues += expressionIssues(target, owner: owner, functionNames: functionNames)
            }
            if case .literal(let name) = message,
               target.map(isMeLike) == true,
               !handlerNames.contains(name.lowercased()) {
                issues.append(issue("send-handler", "`send \"\(name)\" to me` has no matching handler in this script."))
            }
        case .visual(let effect, let duration):
            issues += expressionIssues(effect, owner: owner, functionNames: functionNames)
            if let duration { issues += expressionIssues(duration, owner: owner, functionNames: functionNames) }
            if let effectName = staticString(effect) {
                let resolved = VisualEffect.fromName(effectName)
                if resolved == .none && !Self.noneEffectNames.contains(effectName.lowercased()) {
                    issues.append(issue("visual-effect", "`visual effect \(effectName)` resolves to no transition in Hype."))
                }
            }
        case .playSound(let sound, let notes, let tempo):
            issues += expressionIssues(sound, owner: owner, functionNames: functionNames)
            if let notes { issues += expressionIssues(notes, owner: owner, functionNames: functionNames) }
            if let tempo { issues += expressionIssues(tempo, owner: owner, functionNames: functionNames) }
            if let soundName = staticString(sound), !soundIsResolvable(soundName) {
                issues.append(issue("sound-asset", "`play \"\(soundName)\"` has no embedded audio asset and is not a known system/HyperCard sound mapping."))
            }
        case .externalCommand(let name, let arguments):
            for argument in arguments {
                issues += expressionIssues(argument, owner: owner, functionNames: functionNames)
            }
            let status = HyperCardExternalRegistry.default.status(for: name, kind: .xcmd)
            switch status {
            case .emulated:
                break
            case .knownUnsupported:
                issues.append(issue("xcmd-unsupported", "XCMD `\(name)` is known but not emulated yet."))
            case .unknown:
                issues.append(issue("xcmd-unknown", "XCMD `\(name)` is not available in Hype."))
            }
        case .put(let source, _, let target):
            issues += expressionIssues(source, owner: owner, functionNames: functionNames)
            issues += expressionIssues(target, owner: owner, functionNames: functionNames)
        case .get(let expression), .go(let expression), .returnValue(let expression),
             .say(let expression), .activateListener(let expression), .waitDuration(let expression, _),
             .waitCondition(let expression, _), .deleteObject(let expression), .findText(let expression),
             .selectObject(let expression), .sortCards(let expression), .hideObject(let expression),
             .showObject(let expression), .openStack(let expression), .editScriptOf(let expression),
             .startUsing(let expression), .stopUsing(let expression), .startAnimation(let expression),
             .stopAnimation(let expression), .exportPaint(let expression), .importPaint(let expression):
            issues += expressionIssues(expression, owner: owner, functionNames: functionNames)
        case .set(_, let ofExpression, let toExpression):
            if let ofExpression { issues += expressionIssues(ofExpression, owner: owner, functionNames: functionNames) }
            issues += expressionIssues(toExpression, owner: owner, functionNames: functionNames)
        case .ifThenElse(let condition, let thenBlock, let elseBlock):
            issues += expressionIssues(condition, owner: owner, functionNames: functionNames)
            issues += statementsIssues(thenBlock, owner: owner, handlerNames: handlerNames, messageNames: messageNames, functionNames: functionNames)
            if let elseBlock {
                issues += statementsIssues(elseBlock, owner: owner, handlerNames: handlerNames, messageNames: messageNames, functionNames: functionNames)
            }
        case .repeatCount(let count, let body):
            issues += expressionIssues(count, owner: owner, functionNames: functionNames)
            issues += statementsIssues(body, owner: owner, handlerNames: handlerNames, messageNames: messageNames, functionNames: functionNames)
        case .repeatWhile(let condition, let body):
            issues += expressionIssues(condition, owner: owner, functionNames: functionNames)
            issues += statementsIssues(body, owner: owner, handlerNames: handlerNames, messageNames: messageNames, functionNames: functionNames)
        case .repeatWith(_, let from, let to, let body):
            issues += expressionIssues(from, owner: owner, functionNames: functionNames)
            issues += expressionIssues(to, owner: owner, functionNames: functionNames)
            issues += statementsIssues(body, owner: owner, handlerNames: handlerNames, messageNames: messageNames, functionNames: functionNames)
        default:
            break
        }
        return issues
    }

    private func statementsIssues(
        _ statements: [Statement],
        owner: StoredScript,
        handlerNames: Set<String>,
        messageNames: Set<String>,
        functionNames: Set<String>
    ) -> [ScriptSemanticIssue] {
        statements.flatMap {
            statementIssues($0, owner: owner, handlerNames: handlerNames, messageNames: messageNames, functionNames: functionNames)
        }
    }

    private func expressionIssues(
        _ expression: HypeCore.Expression,
        owner: StoredScript,
        functionNames: Set<String>
    ) -> [ScriptSemanticIssue] {
        var issues: [ScriptSemanticIssue] = []
        switch expression {
        case .functionCall(let name, let arguments):
            for argument in arguments {
                issues += expressionIssues(argument, owner: owner, functionNames: functionNames)
            }
            let lower = name.lowercased()
            if !functionNames.contains(lower) && !Self.knownBuiltInFunctions.contains(lower) {
                let status = HyperCardExternalRegistry.default.status(for: name, kind: .xfcn)
                switch status {
                case .emulated:
                    break
                case .knownUnsupported:
                    issues.append(issue("xfcn-unsupported", "XFCN/function `\(name)` is known but not emulated yet."))
                case .unknown:
                    issues.append(issue("function-unknown", "Function `\(name)` is not a local function, built-in Hype function, or known emulated XFCN."))
                }
            }
        case .objectRef(let ref):
            issues += objectReferenceIssues(ref, owner: owner)
            issues += expressionIssues(ref.identifier, owner: owner, functionNames: functionNames)
        case .scopedObjectRef(let object, let ownerRef):
            issues += expressionIssues(object.identifier, owner: owner, functionNames: functionNames)
            issues += expressionIssues(ownerRef.identifier, owner: owner, functionNames: functionNames)
        case .propertyAccess(_, let target):
            if let target { issues += expressionIssues(target, owner: owner, functionNames: functionNames) }
        case .binary(let left, _, let right), .contains(let left, let right), .stringConcat(let left, let right),
             .spacedConcat(let left, let right), .isIn(let left, let right), .isNotIn(let left, let right),
             .isWithin(let left, let right), .isNotWithin(let left, let right):
            issues += expressionIssues(left, owner: owner, functionNames: functionNames)
            issues += expressionIssues(right, owner: owner, functionNames: functionNames)
        case .unary(_, let inner), .await(let inner), .chunk(_, _, let inner), .not(let inner),
             .isA(let inner, _), .isNotA(let inner, _):
            issues += expressionIssues(inner, owner: owner, functionNames: functionNames)
        case .headerAccess(let header, let target):
            issues += expressionIssues(header, owner: owner, functionNames: functionNames)
            issues += expressionIssues(target, owner: owner, functionNames: functionNames)
        case .chartDataPointRef(let chart, let series, let point):
            issues += expressionIssues(chart, owner: owner, functionNames: functionNames)
            issues += expressionIssues(series, owner: owner, functionNames: functionNames)
            issues += expressionIssues(point, owner: owner, functionNames: functionNames)
        case .tileAt(let column, let row, let tilemap):
            issues += expressionIssues(column, owner: owner, functionNames: functionNames)
            issues += expressionIssues(row, owner: owner, functionNames: functionNames)
            issues += expressionIssues(tilemap, owner: owner, functionNames: functionNames)
        case .thereIsA(_, let target), .thereIsNo(_, let target):
            issues += expressionIssues(target, owner: owner, functionNames: functionNames)
        case .askMeshy(let prompt, let style):
            issues += expressionIssues(prompt, owner: owner, functionNames: functionNames)
            if let style { issues += expressionIssues(style, owner: owner, functionNames: functionNames) }
        default:
            break
        }
        return issues
    }

    private func objectReferenceIssues(_ ref: ObjectRefExpr, owner: StoredScript) -> [ScriptSemanticIssue] {
        guard let name = staticString(ref.identifier)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
              !name.isEmpty else { return [] }
        let lowerType = ref.objectType.lowercased()
        let lowerName = name.lowercased()
        switch lowerType {
        case "button", "btn", "field", "fld":
            guard let cardId = owner.currentCardId,
                  let card = document.cards.first(where: { $0.id == cardId }) else { return [] }
            let expectedType: PartType = lowerType == "field" || lowerType == "fld" ? .field : .button
            let found = document.parts.contains { part in
                part.partType == expectedType &&
                part.name.lowercased() == lowerName &&
                (part.cardId == card.id || part.backgroundId == card.backgroundId)
            }
            if !found {
                return [issue("object-reference", "`\(ref.objectType) \"\(name)\"` does not resolve on \(owner.ownerPath)'s card/background context.")]
            }
        case "card":
            let found = document.cards.contains { card in
                card.name.lowercased() == lowerName || String(document.cards.firstIndex(where: { $0.id == card.id }).map { $0 + 1 } ?? -1) == lowerName
            }
            if !found {
                return [issue("object-reference", "`card \"\(name)\"` does not resolve in this stack.")]
            }
        case "background", "bg":
            let found = document.backgrounds.contains { $0.name.lowercased() == lowerName }
            if !found {
                return [issue("object-reference", "`background \"\(name)\"` does not resolve in this stack.")]
            }
        default:
            break
        }
        return []
    }

    private func soundIsResolvable(_ name: String) -> Bool {
        let lower = name.lowercased()
        if Self.knownSystemOrHyperCardSounds.contains(lower) { return true }
        return document.assetRepository.assets.contains { asset in
            asset.kind == .audioClip && asset.name.lowercased() == lower
        }
    }

    private func allowedHooks(for ownerType: String) -> Set<String> {
        switch ownerType.lowercased() {
        case "button":
            return Self.buttonHooks
        case "field":
            return Self.fieldHooks
        case "card":
            return Self.cardHooks
        case "background":
            return Self.backgroundHooks
        case "stack":
            return Self.stackHooks
        default:
            return Self.commonHooks
        }
    }

    private func isMeLike(_ expression: HypeCore.Expression) -> Bool {
        switch expression {
        case .me, .this:
            return true
        case .literal(let value):
            return value.lowercased() == "me" || value.lowercased() == "this"
        default:
            return false
        }
    }

    private func staticString(_ expression: HypeCore.Expression) -> String? {
        switch expression {
        case .literal(let value), .variable(let value):
            return value
        default:
            return nil
        }
    }

    private func issue(_ kind: String, _ message: String) -> ScriptSemanticIssue {
        ScriptSemanticIssue(kind: kind, message: message)
    }

    private func stableUnique(_ issues: [ScriptSemanticIssue]) -> [ScriptSemanticIssue] {
        var seen = Set<String>()
        var unique: [ScriptSemanticIssue] = []
        for issue in issues {
            let key = "\(issue.kind)\t\(issue.message)"
            if seen.insert(key).inserted {
                unique.append(issue)
            }
        }
        return unique
    }

    private func matches(_ source: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)) != nil
    }

    private static let commonHooks: Set<String> = [
        "mouseup", "mousedown", "mouseenter", "mouseleave", "mousemove",
        "opencard", "closecard", "openbackground", "closebackground",
        "openstack", "closestack", "idle", "keydown", "keyup",
        "returninfield", "enterkey", "tabinfield",
    ]
    private static let buttonHooks: Set<String> = ["mouseup", "mousedown", "mouseenter", "mouseleave", "mousemove", "idle"]
    private static let fieldHooks: Set<String> = ["mouseup", "mousedown", "mouseenter", "mouseleave", "mousemove", "openfield", "closefield", "returninfield", "enterkey", "tabinfield", "keydown", "keyup", "idle"]
    private static let cardHooks: Set<String> = ["opencard", "closecard", "openbackground", "closebackground", "idle", "keydown", "keyup", "mouseup", "mousedown", "mouseenter", "mouseleave", "mousemove"]
    private static let backgroundHooks: Set<String> = ["openbackground", "closebackground", "opencard", "closecard", "idle", "keydown", "keyup", "mouseup", "mousedown"]
    private static let stackHooks: Set<String> = ["openstack", "closestack", "idle", "keydown", "keyup", "mouseup", "mousedown"]
    private static let knownRuntimeHooks = commonHooks
    private static let noneEffectNames: Set<String> = ["none", "plain", "cut"]
    private static let knownBuiltInFunctions: Set<String> = [
        "offset", "random", "abs", "round", "trunc", "min", "max",
        "sin", "cos", "tan", "atan", "sqrt", "exp", "ln", "log2",
        "chartonum", "numtochar", "value", "date", "time", "ticks", "seconds", "number",
        "ollama", "aimodel", "ollamamodel", "aimodels", "ollamamodels",
        "mouse", "mouseclick", "mouseh", "mousev", "mouseloc",
        "shiftkey", "commandkey", "optionkey", "target", "result", "param", "paramcount", "params",
        "sum", "average", "annuity", "compound", "exp1", "exp2", "ln1",
        "screenrect", "diskspace", "systemversion", "version", "heapspace", "stackspace",
        "environment", "tool", "windows", "clickchunk", "clickh", "clickv", "clickline", "clickloc", "clicktext",
        "foundchunk", "foundfield", "foundline", "foundtext",
        "selectedbutton", "selectedchunk", "selectedfield", "selectedline", "selectedloc", "selectedtext",
        "sound", "musicstate", "musicpatterns", "musicinstruments", "programs", "menus", "destination", "stacks",
        "meshy_parse_webhook",
    ]
    private static let knownSystemOrHyperCardSounds: Set<String> = [
        "basso", "blow", "bottle", "frog", "funk", "glass", "hero", "morse", "ping", "pop", "purr", "sosumi", "submarine", "tink",
        "boing", "harpsichord", "flute",
    ]
}

private struct ImportSummary {
    var sourceURL: URL
    var document: HypeDocument

    var tsvHeader: String {
        "status\tcards\tbackgrounds\tparts\timages\timageBytes\tscripts\twidth\theight\tsourceBytes\tstackName\tpath"
    }

    var tsvLine: String {
        [
            "ok",
            "\(document.cards.count)",
            "\(document.backgrounds.count)",
            "\(document.parts.count)",
            "\(imageParts.count)",
            "\(imageBytes)",
            "\(scriptCount)",
            "\(document.stack.width)",
            "\(document.stack.height)",
            "\(sourceBytes)",
            sanitize(document.stack.name),
            sanitize(sourceURL.path),
        ].joined(separator: "\t")
    }

    private var imageParts: [Part] {
        document.parts.filter { $0.partType == .image && $0.imageData != nil }
    }

    private var imageBytes: Int {
        imageParts.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
    }

    private var scriptCount: Int {
        [document.stack.script].filter { !$0.isEmpty }.count +
            document.backgrounds.filter { !$0.script.isEmpty }.count +
            document.cards.filter { !$0.script.isEmpty }.count +
            document.parts.filter { !$0.script.isEmpty }.count
    }

    private var sourceBytes: Int {
        (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

private struct PackageValidationReport {
    var path: String
    var stackName: String
    var documentVersion: Int
    var cardCount: Int
    var backgroundCount: Int
    var partCount: Int
    var assetCount: Int
    var integrityCheck: String
    var foreignKeyViolationCount: Int
    var missingAssetReferenceCount: Int
    var searchEntryCount: Int
    var isHealthy: Bool

    var tsvHeader: String {
        "status\tstackName\tdocumentVersion\tcards\tbackgrounds\tparts\tassets\tintegrityCheck\tforeignKeyViolations\tmissingAssetReferences\tsearchEntries\tpath"
    }

    var tsvLine: String {
        [
            isHealthy ? "ok" : "error",
            sanitize(stackName),
            "\(documentVersion)",
            "\(cardCount)",
            "\(backgroundCount)",
            "\(partCount)",
            "\(assetCount)",
            sanitize(integrityCheck),
            "\(foreignKeyViolationCount)",
            "\(missingAssetReferenceCount)",
            "\(searchEntryCount)",
            sanitize(path),
        ].joined(separator: "\t")
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

enum InferenceSmokeProvider: String, ExpressibleByArgument {
    case openAI = "openai"
    case openAICompatible = "openai-compatible"
}

enum HypeCLIError: Error, CustomStringConvertible {
    case noHandlerFound
    case executionFailed
    case benchmarkFailed(String, String)
    case validationFailed(Int)

    var description: String {
        switch self {
        case .noHandlerFound: return "No handler found in script"
        case .executionFailed: return "Script execution failed"
        case .benchmarkFailed(let name, let message): return "Benchmark '\(name)' failed: \(message)"
        case .validationFailed(let count): return "\(count) script validation failure(s)"
        }
    }
}

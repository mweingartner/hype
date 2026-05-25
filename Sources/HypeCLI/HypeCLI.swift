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
        let result = try StackImportCImporter().importStack(at: url)
        return ImportSummary(sourceURL: url, document: result.document)
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

            results.append(validate(script: script, fileName: fileName))
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
            source: document.stack.script
        ))
        scripts.append(contentsOf: document.backgrounds.enumerated().map { index, background in
            StoredScript(
                ownerType: "background",
                ownerId: background.id,
                ownerName: background.name,
                ownerPath: "background \(index + 1) \(background.name)",
                source: background.script
            )
        })
        scripts.append(contentsOf: document.cards.enumerated().map { index, card in
            StoredScript(
                ownerType: "card",
                ownerId: card.id,
                ownerName: card.name,
                ownerPath: "card \(index + 1) \(card.name)",
                source: card.script
            )
        })
        scripts.append(contentsOf: document.parts.map { part in
            StoredScript(
                ownerType: part.partType.rawValue,
                ownerId: part.id,
                ownerName: part.name,
                ownerPath: ownerPath(for: part, in: document),
                source: part.script
            )
        })
        return scripts.filter { !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func validate(script: StoredScript, fileName: String?) -> ScriptValidationResult {
        do {
            var lexer = Lexer(source: script.source)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            let parsed = try parser.parse()
            return ScriptValidationResult(
                script: script,
                status: "ok",
                handlerCount: parsed.handlers.count,
                line: nil,
                message: "",
                fileName: fileName,
                failureFileName: nil
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
                failureFileName: failureDiagnosticFileName(fileName: fileName, script: script)
            )
        }
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
    var source: String
}

private struct ScriptValidationReport {
    var results: [ScriptValidationResult]

    var tsvHeader: String {
        ScriptValidationResult.tsvHeader
    }

    var failureCount: Int {
        results.filter { $0.status != "ok" }.count
    }

    var successCount: Int {
        results.count - failureCount
    }
}

private struct ScriptValidationResult {
    var script: StoredScript
    var status: String
    var handlerCount: Int
    var line: Int?
    var message: String
    var fileName: String?
    var failureFileName: String?

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
    }
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

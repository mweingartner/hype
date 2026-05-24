import Foundation
import HypeCore
import ArgumentParser

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

    @Option(help: "OpenAI-compatible inference base URL, for example http://localhost:8001/v1")
    var inferenceBaseURL: String?

    @Option(help: "Model name to send in the inference smoke test")
    var inferenceModel = HypeAIConfiguration.defaultLlamaSwapModel

    @Option(help: "Prompt to send in the inference smoke test")
    var inferencePrompt = "Reply with OK."

    @Flag(help: "Run an Ollama tool API smoke test: model query, pull, and tool chat")
    var ollamaToolSmoke = false

    @Option(help: "Ollama host for --ollama-tool-smoke")
    var ollamaHost = "localhost"

    @Option(help: "Ollama port for --ollama-tool-smoke")
    var ollamaPort = "11434"

    @Option(help: "Ollama model for --ollama-tool-smoke query/pull/chat")
    var ollamaModel = "llama3.2"

    mutating func run() async throws {
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
        guard let inferenceBaseURL,
              let baseURL = URL(string: inferenceBaseURL) else {
            throw ValidationError("--inference-base-url is required, for example http://localhost:8001/v1")
        }

        let client = OpenAIChatCompletionsClient(
            configuration: .openAICompatible(
                baseURL: baseURL,
                apiKey: nil,
                model: inferenceModel,
                providerName: "cli-openai-compatible"
            )
        )
        let inference = HypeAIClientChatInferenceProvider(client: client)
        let response = try await inference.chat(AIChatInferenceRequest(
            messages: [OllamaMessage(role: "user", content: inferencePrompt)],
            tools: []
        ))

        let content = response.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.isEmpty {
            throw ValidationError("Inference response was empty")
        }
        print(content)
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
}

enum HypeCLIError: Error, CustomStringConvertible {
    case noHandlerFound
    case executionFailed
    case benchmarkFailed(String, String)

    var description: String {
        switch self {
        case .noHandlerFound: return "No handler found in script"
        case .executionFailed: return "Script execution failed"
        case .benchmarkFailed(let name, let message): return "Benchmark '\(name)' failed: \(message)"
        }
    }
}

import Foundation
import HypeCore
import ArgumentParser

struct HypeCLI: ParsableCommand {
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

    mutating func run() throws {
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

HypeCLI.main()

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

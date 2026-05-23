import Foundation
import HypeCore
import ArgumentParser

@main
struct HypeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hypetalk",
        abstract: "HypeTalk interpreter CLI"
    )

    @Argument(help: "HypeTalk script to execute")
    var script: String

    @Option(help: "Path to a .hype document to load")
    var document: String?

    @Option(help: "Handler name to invoke (default: main)")
    var handler: String = "main"

    mutating func run() throws {
        let script: String
        if self.script == "/dev/stdin" || self.script == "-" {
            script = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } else if FileManager.default.fileExists(atPath: self.script) {
            script = try String(contentsOfFile: self.script, encoding: .utf8)
        } else {
            script = self.script
        }

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
}

enum HypeCLIError: Error, CustomStringConvertible {
    case noHandlerFound
    case executionFailed

    var description: String {
        switch self {
        case .noHandlerFound: return "No handler found in script"
        case .executionFailed: return "Script execution failed"
        }
    }
}
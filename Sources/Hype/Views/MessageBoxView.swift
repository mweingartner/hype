import SwiftUI
import HypeCore

struct MessageBoxView: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var history: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Message Box")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))

            TextField("Type a HypeTalk expression...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(4)
                .onSubmit { evaluate() }

            if !outputText.isEmpty {
                Text(outputText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(outputText.hasPrefix("Error:") ? .red : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .frame(height: 80)
    }

    private func evaluate() {
        let source = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        history.append(source)
        if history.count > 500 { history.removeFirst() }

        // Wrap in a handler for execution
        let wrapped = "on __eval\n  \(source)\nend __eval"
        var lexer = Lexer(source: wrapped)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)

        do {
            let script = try parser.parse()
            guard let handler = script.handlers.first else {
                outputText = "Error: No handler found"
                return
            }
            let context = ExecutionContext(
                targetId: document.document.stack.id,
                currentCardId: currentCardId ?? UUID(),
                document: document.document
            )
            let interpreter = Interpreter()
            let result = interpreter.execute(handler: handler, params: [], context: context)

            if let err = result.error {
                outputText = "Error: \(err.message)"
            } else {
                outputText = result.returnValue ?? ""
            }
        } catch {
            outputText = "Error: \(error.localizedDescription)"
        }

        inputText = ""
    }
}

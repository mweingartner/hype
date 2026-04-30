import SwiftUI
import HypeCore

struct MessageBoxView: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var history: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header — themed as a toolbar surface so the title bar
            // reads as part of the chrome.
            HStack {
                Text("Message Box")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(hypeTheme.toolbarBackground.swiftUIColor)
            .environment(\.colorScheme, hypeTheme.toolbarColorScheme)

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
        // Body surface tinted with the inspector-background token so
        // the message box stays readable on themed backgrounds.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so the input field and result
        // text resolve to a contrasting color against the themed bg.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
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
            let snapshot = document.document
            let cardId = currentCardId ?? snapshot.sortedCards.first?.id ?? snapshot.stack.id
            Task {
                let runtime = await StackRuntimeRegistry.shared.runtime(
                    for: snapshot,
                    configuration: StackRuntimeConfiguration(aiProvider: OllamaAIScriptingProvider())
                )
                let liveDocument = await runtime.currentDocument()
                let context = ExecutionContext(
                    targetId: liveDocument.stack.id,
                    currentCardId: cardId,
                    document: liveDocument,
                    aiProvider: OllamaAIScriptingProvider(),
                    runtimeProvider: runtime
                )
                let interpreter = Interpreter()
                let result = await interpreter.executeAsync(handler: handler, params: [], context: context)
                if let modified = result.modifiedDocument {
                    await runtime.syncDocument(modified)
                }
                await MainActor.run {
                    if let modified = result.modifiedDocument {
                        document.document = modified
                    }
                    if let err = result.error {
                        HypeLogger.shared.scriptError(err, source: "Message Box", context: "Evaluation")
                        outputText = "Error: \(err.message)"
                    } else {
                        outputText = result.returnValue ?? ""
                    }
                }
            }
        } catch {
            let scriptError = ScriptError(
                message: error.localizedDescription,
                line: 0,
                handler: "__eval"
            )
            HypeLogger.shared.scriptError(scriptError, source: "Message Box", context: "Parse")
            outputText = "Error: \(error.localizedDescription)"
        }

        inputText = ""
    }
}

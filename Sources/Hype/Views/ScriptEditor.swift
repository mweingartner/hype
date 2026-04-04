import SwiftUI
import HypeCore

struct ScriptEditor: View {
    @Binding var document: HypeDocumentWrapper
    let partId: UUID?
    @State private var scriptText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Script Editor")
                    .font(.headline)
                Spacer()
                Button("Check Syntax") { checkSyntax() }
                Button("Apply") { applyScript() }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            // Editor
            TextEditor(text: $scriptText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)

            // Error display
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 11))
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .onAppear { loadScript() }
        .onChange(of: partId) { _, _ in loadScript() }
    }

    private func loadScript() {
        guard let id = partId,
              let part = document.document.parts.first(where: { $0.id == id }) else {
            scriptText = ""
            return
        }
        scriptText = part.script
    }

    private func checkSyntax() {
        var lexer = Lexer(source: scriptText)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            let _ = try parser.parse()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyScript() {
        checkSyntax()
        guard errorMessage == nil, let id = partId else { return }
        document.document.updatePart(id: id) { $0.script = scriptText }
    }
}

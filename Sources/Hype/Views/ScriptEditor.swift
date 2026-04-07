import SwiftUI
import HypeCore

// MARK: - Script Command Templates

/// A template snippet for the command palette sidebar.
struct ScriptTemplate: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let code: String
}

/// All available script templates grouped by category.
private let scriptTemplates: [ScriptTemplate] = [
    // Event Handlers
    ScriptTemplate(name: "on mouseUp", category: "Events",
        code: "on mouseUp\n  \nend mouseUp"),
    ScriptTemplate(name: "on mouseDown", category: "Events",
        code: "on mouseDown\n  \nend mouseDown"),
    ScriptTemplate(name: "on mouseEnter", category: "Events",
        code: "on mouseEnter\n  \nend mouseEnter"),
    ScriptTemplate(name: "on mouseLeave", category: "Events",
        code: "on mouseLeave\n  \nend mouseLeave"),
    ScriptTemplate(name: "on openCard", category: "Events",
        code: "on openCard\n  \nend openCard"),
    ScriptTemplate(name: "on closeCard", category: "Events",
        code: "on closeCard\n  \nend closeCard"),
    ScriptTemplate(name: "on openField", category: "Events",
        code: "on openField\n  \nend openField"),
    ScriptTemplate(name: "on closeField", category: "Events",
        code: "on closeField\n  \nend closeField"),
    ScriptTemplate(name: "on enterKey", category: "Events",
        code: "on enterKey\n  \nend enterKey"),
    ScriptTemplate(name: "on idle", category: "Events",
        code: "on idle\n  \nend idle"),

    // Navigation
    ScriptTemplate(name: "go next", category: "Navigation",
        code: "go next"),
    ScriptTemplate(name: "go previous", category: "Navigation",
        code: "go previous"),
    ScriptTemplate(name: "go back", category: "Navigation",
        code: "go back"),
    ScriptTemplate(name: "go first", category: "Navigation",
        code: "go first"),
    ScriptTemplate(name: "go last", category: "Navigation",
        code: "go last"),
    ScriptTemplate(name: "go to card", category: "Navigation",
        code: "go to card \"Card Name\""),
    ScriptTemplate(name: "show all cards", category: "Navigation",
        code: "show all cards"),
    ScriptTemplate(name: "create card", category: "Navigation",
        code: "create a new card"),
    ScriptTemplate(name: "create card (bg)", category: "Navigation",
        code: "create a new card with background \"Background 1\""),

    // Variables & Data
    ScriptTemplate(name: "put into variable", category: "Variables",
        code: "put \"value\" into myVar"),
    ScriptTemplate(name: "put into field", category: "Variables",
        code: "put \"Hello\" into field \"Name\""),
    ScriptTemplate(name: "get field value", category: "Variables",
        code: "get field \"Name\""),
    ScriptTemplate(name: "add to variable", category: "Variables",
        code: "add 1 to counter"),
    ScriptTemplate(name: "subtract from", category: "Variables",
        code: "subtract 1 from counter"),
    ScriptTemplate(name: "multiply by", category: "Variables",
        code: "multiply price by 1.08"),
    ScriptTemplate(name: "divide by", category: "Variables",
        code: "divide total by count"),
    ScriptTemplate(name: "global variable", category: "Variables",
        code: "global gMyGlobal"),

    // Control Flow
    ScriptTemplate(name: "if / then / else", category: "Control",
        code: "if condition then\n  \nelse\n  \nend if"),
    ScriptTemplate(name: "repeat N times", category: "Control",
        code: "repeat 10\n  \nend repeat"),
    ScriptTemplate(name: "repeat with counter", category: "Control",
        code: "repeat with i = 1 to 10\n  \nend repeat"),
    ScriptTemplate(name: "repeat while", category: "Control",
        code: "repeat while condition\n  \nend repeat"),
    ScriptTemplate(name: "exit repeat", category: "Control",
        code: "exit repeat"),
    ScriptTemplate(name: "next repeat", category: "Control",
        code: "next repeat"),

    // Dialogs
    ScriptTemplate(name: "answer (alert)", category: "Dialogs",
        code: "answer \"Hello, World!\""),
    ScriptTemplate(name: "ask (input dialog)", category: "Dialogs",
        code: "ask \"What is your name?\""),

    // Object Commands
    ScriptTemplate(name: "set property", category: "Objects",
        code: "set the name of button 1 to \"New Name\""),
    ScriptTemplate(name: "set style", category: "Objects",
        code: "set the style of button \"btn\" to \"default\""),
    ScriptTemplate(name: "set url of webpage", category: "Objects",
        code: "set the url of webpage \"web\" to \"https://example.com\""),
    ScriptTemplate(name: "hide part", category: "Objects",
        code: "hide field \"secret\""),
    ScriptTemplate(name: "show part", category: "Objects",
        code: "show field \"secret\""),
    ScriptTemplate(name: "delete part", category: "Objects",
        code: "delete button \"old\""),
    ScriptTemplate(name: "mark card", category: "Objects",
        code: "mark this card"),

    // Commands
    ScriptTemplate(name: "beep", category: "Commands",
        code: "beep"),
    ScriptTemplate(name: "wait seconds", category: "Commands",
        code: "wait 2"),
    ScriptTemplate(name: "visual effect", category: "Commands",
        code: "visual effect dissolve"),
    ScriptTemplate(name: "pass message", category: "Commands",
        code: "pass mouseUp"),
    ScriptTemplate(name: "send message", category: "Commands",
        code: "send \"mouseUp\" to button \"other\""),
    ScriptTemplate(name: "do expression", category: "Commands",
        code: "do field \"script\""),

    // Functions
    ScriptTemplate(name: "custom function", category: "Functions",
        code: "function myFunction param1\n  return param1 & \" processed\"\nend myFunction"),
    ScriptTemplate(name: "length()", category: "Functions",
        code: "length(\"hello\")"),
    ScriptTemplate(name: "offset()", category: "Functions",
        code: "offset(\"needle\", \"haystack\")"),
    ScriptTemplate(name: "random()", category: "Functions",
        code: "random(100)"),
    ScriptTemplate(name: "sqrt()", category: "Functions",
        code: "sqrt(16)"),
    ScriptTemplate(name: "the number of", category: "Functions",
        code: "the number of cards"),

    // Operators
    ScriptTemplate(name: "is in", category: "Operators",
        code: "\"abc\" is in \"xabcx\""),
    ScriptTemplate(name: "is a number", category: "Operators",
        code: "x is a number"),
    ScriptTemplate(name: "there is a", category: "Operators",
        code: "there is a button \"OK\""),
    ScriptTemplate(name: "contains", category: "Operators",
        code: "field \"data\" contains \"search\""),

    // AI
    ScriptTemplate(name: "ask AI", category: "AI",
        code: "ask ai \"Summarize this text\""),
]

/// Grouped categories in display order.
private let categoryOrder = ["Events", "Navigation", "Variables", "Control", "Dialogs", "Objects", "Commands", "Functions", "Operators", "AI"]

// MARK: - Script Editor View

struct ScriptEditor: View {
    @Binding var document: HypeDocumentWrapper
    let partId: UUID?
    var onDone: (() -> Void)? = nil
    @State private var scriptText: String = ""
    @State private var errorMessage: String?
    @State private var selectedCategory: String = "Events"

    var body: some View {
        HSplitView {
            // Left: Command palette
            commandPalette
                .frame(width: 180)

            // Right: Code editor
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text("Script Editor")
                        .font(.headline)
                    Spacer()
                    Button("Check Syntax") { checkSyntax() }
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
                        .background(Color.red.opacity(0.1))
                }
            }
        }
        .onAppear { loadScript() }
        .onChange(of: partId) { _, _ in loadScript() }
        .onDisappear { applyScript() }
    }

    // MARK: - Command Palette

    private var commandPalette: some View {
        VStack(spacing: 0) {
            Text("Commands")
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

            List {
                ForEach(categoryOrder, id: \.self) { category in
                    Section(header: Text(category).font(.system(size: 10, weight: .bold))) {
                        ForEach(templatesForCategory(category)) { template in
                            Button(action: { insertTemplate(template) }) {
                                Text(template.name)
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func templatesForCategory(_ category: String) -> [ScriptTemplate] {
        scriptTemplates.filter { $0.category == category }
    }

    private func insertTemplate(_ template: ScriptTemplate) {
        // If the editor is empty and the template is a handler block, replace entirely
        let trimmed = scriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && template.code.hasPrefix("on ") {
            scriptText = template.code
        } else if trimmed.isEmpty {
            scriptText = template.code
        } else {
            // Insert at end with a newline
            if !scriptText.hasSuffix("\n") {
                scriptText += "\n"
            }
            scriptText += "  " + template.code
        }
    }

    // MARK: - Script Operations

    private func loadScript() {
        guard let id = partId,
              let part = document.document.parts.first(where: { $0.id == id }) else {
            scriptText = ""
            return
        }
        scriptText = part.script
    }

    private func checkSyntax() {
        let trimmed = scriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = nil
            return
        }
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

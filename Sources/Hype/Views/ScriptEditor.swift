import SwiftUI
import HypeCore

// MARK: - Script Target

/// Identifies what object a script editor is editing.
enum ScriptTarget: Equatable {
    case part(UUID)
    case card(UUID)
    case background(UUID)
    case scene(partId: UUID, sceneId: UUID)
    case node(partId: UUID, nodeId: UUID)
    case stack
    case hype  // app-level script stored in UserDefaults

    /// Stable string key used to dedupe open script editor windows
    /// in `openScriptEditorWindow`. Two `ScriptTarget` values with
    /// the same identity key represent the same on-screen
    /// "thing being edited" — the same part, card, background,
    /// stack, or app script. Used as the dictionary key for
    /// `activeScriptWindows` so we can find an existing window for
    /// a given target instead of stacking duplicates on every
    /// runtime error.
    ///
    /// The format is `"<kind>:<id>"` (or just `"<kind>"` for the
    /// singletons) so it's both human-readable for debugging and
    /// guaranteed-stable across calls — UUID's `uuidString` is
    /// canonical.
    var identityKey: String {
        switch self {
        case .part(let id): return "part:\(id.uuidString)"
        case .card(let id): return "card:\(id.uuidString)"
        case .background(let id): return "background:\(id.uuidString)"
        case .scene(let partId, let sceneId): return "scene:\(partId.uuidString):\(sceneId.uuidString)"
        case .node(let partId, let nodeId): return "node:\(partId.uuidString):\(nodeId.uuidString)"
        case .stack: return "stack"
        case .hype: return "hype"
        }
    }
}

func scriptEditorResolvedTarget(
    in document: HypeDocument,
    target: ScriptTarget?,
    partId: UUID?
) -> ScriptTarget? {
    target ?? partId.map { .part($0) }
}

func scriptEditorDisplayedScriptText(storedScript: String) -> String {
    storedScript
}

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
    ScriptTemplate(name: "on mouseWithin", category: "Events",
        code: "on mouseWithin\n  -- the mouseLoc returns \"x,y\"\n  put the mouseLoc into pos\nend mouseWithin"),
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

    // Speech
    ScriptTemplate(name: "say text", category: "Speech",
        code: "say \"this is a test of the speech support in Hype!\""),
    ScriptTemplate(name: "activate listener", category: "Speech",
        code: "set activateListener to true"),
    ScriptTemplate(name: "deactivate listener", category: "Speech",
        code: "set activateListener to false"),
    ScriptTemplate(name: "on listen", category: "Speech",
        code: "on listen spokenText\n  put spokenText into field \"lastSpeech\"\n  pass listen\nend listen"),

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
        code: "ask ai \"Summarize the current scene and suggest one improvement\"\nput it into field \"output\""),
    ScriptTemplate(name: "ask AI with model", category: "AI",
        code: "ask ai \"Write a title screen tagline\" with model \"llama3.2\"\nput it into field \"output\""),
    ScriptTemplate(name: "ollama()", category: "AI",
        code: "put ollama(\"Write one line of dialog for the shopkeeper\") into field \"output\""),
    ScriptTemplate(name: "ollama(model,prompt)", category: "AI",
        code: "put ollama(\"llama3.2\", \"Generate a short quest hook\") into field \"output\""),
    ScriptTemplate(name: "the aiModel", category: "AI",
        code: "put the aiModel into field \"output\""),
    ScriptTemplate(name: "the aiModels", category: "AI",
        code: "put the aiModels into field \"output\""),
    ScriptTemplate(name: "await ollama()", category: "AI",
        code: "put await ollama(\"Summarize the current card\") into field \"output\""),
    ScriptTemplate(name: "ask AI callback", category: "AI",
        code: "on mouseUp\n  ask ai \"Write a short mission briefing\" with message \"aiFinished\"\nend mouseUp\n\non aiFinished requestId, eventName\n  if eventName is \"completed\" then\n    put the body of request requestId into field \"output\"\n  end if\nend aiFinished"),

    // SpriteKit Events
    ScriptTemplate(name: "on sceneDidLoad", category: "SpriteKit",
        code: "on sceneDidLoad\n  \nend sceneDidLoad"),
    ScriptTemplate(name: "on openScene", category: "SpriteKit",
        code: "on openScene\n  \nend openScene"),
    ScriptTemplate(name: "on closeScene", category: "SpriteKit",
        code: "on closeScene\n  \nend closeScene"),
    ScriptTemplate(name: "on frameUpdate", category: "SpriteKit",
        code: "on frameUpdate\n  -- Called every frame\n  -- Use sparingly!\nend frameUpdate"),
    ScriptTemplate(name: "on beginContact", category: "SpriteKit",
        code: "on beginContact\n  -- Physics contact started\nend beginContact"),
    ScriptTemplate(name: "on endContact", category: "SpriteKit",
        code: "on endContact\n  -- Physics contact ended\nend endContact"),
    ScriptTemplate(name: "on actionFinished", category: "SpriteKit",
        code: "on actionFinished\n  -- Action completed\nend actionFinished"),
    ScriptTemplate(name: "on keyDown", category: "SpriteKit",
        code: "on keyDown\n  -- Arrow keys arrive as \"up\", \"down\", \"left\", \"right\"\nend keyDown"),
    ScriptTemplate(name: "on keyUp", category: "SpriteKit",
        code: "on keyUp\n  -- the key is the released key name\nend keyUp"),

    // SpriteKit Commands
    ScriptTemplate(name: "create sprite", category: "SpriteKit",
        code: "create sprite \"name\" with asset \"assetName\""),
    ScriptTemplate(name: "create scene", category: "SpriteKit",
        code: "create scene \"name\" in spritearea \"areaName\" with size 400,300"),
    ScriptTemplate(name: "create spritearea", category: "SpriteKit",
        code: "create spritearea \"name\" at rect 20,20,760,560"),
    ScriptTemplate(name: "HTTP request", category: "Networking",
        code: "put request \"http://localhost:8080/health\" into reqId\nput the body of request reqId into field \"output\""),
    ScriptTemplate(name: "HTTP request callback", category: "Networking",
        code: "on mouseUp\n  request \"http://localhost:8080/score\" with message \"requestFinished\"\nend mouseUp\n\non requestFinished requestId, eventName\n  if eventName is \"completed\" then\n    put the body of request requestId into field \"output\"\n  else\n    put the error of request requestId into field \"output\"\n  end if\nend requestFinished"),
    ScriptTemplate(name: "HTTP listener", category: "Networking",
        code: "on openStack\n  listen for http on port 8080 host \"127.0.0.1\" with message \"networkRequest\"\nend openStack\n\non networkRequest requestId, eventName\n  if eventName is \"request\" then\n    reply to request requestId with status 200 body \"hello from Hype\"\n  end if\nend networkRequest"),
    ScriptTemplate(name: "TCP connect", category: "Networking",
        code: "on mouseUp\n  connect to host \"127.0.0.1\" on port 9000 with message \"socketEvent\"\nend mouseUp\n\non socketEvent connectionId, eventName\n  if eventName is \"connected\" then\n    send \"ping\" to connection connectionId\n  end if\nend socketEvent"),
    ScriptTemplate(name: "set sprite property", category: "SpriteKit",
        code: "set the loc of sprite \"name\" to \"200,200\""),
    ScriptTemplate(name: "set sprite text", category: "SpriteKit",
        code: "set the text of sprite \"label1\" to \"Score: 100\""),
    ScriptTemplate(name: "set sprite color", category: "SpriteKit",
        code: "set the fillColor of sprite \"shape1\" to \"#FF0000\""),
    ScriptTemplate(name: "set sprite alpha", category: "SpriteKit",
        code: "set the alpha of sprite \"player\" to 0.5"),
    ScriptTemplate(name: "set sprite rotation", category: "SpriteKit",
        code: "set the rotation of sprite \"player\" to 45"),
    ScriptTemplate(name: "set sprite hidden", category: "SpriteKit",
        code: "set the hidden of sprite \"enemy\" to true"),
    ScriptTemplate(name: "set sprite size", category: "SpriteKit",
        code: "set the width of sprite \"player\" to 64"),
    ScriptTemplate(name: "remove sprite", category: "SpriteKit",
        code: "remove sprite \"name\""),
    ScriptTemplate(name: "pause scene", category: "SpriteKit",
        code: "pause scene \"main\""),
    ScriptTemplate(name: "resume scene", category: "SpriteKit",
        code: "resume scene \"main\""),
]

/// Grouped categories in display order.
private let categoryOrder = ["Events", "SpriteKit", "Navigation", "Variables", "Control", "Dialogs", "Speech", "Objects", "Commands", "Functions", "Operators", "AI"]

func scriptEditorTemplateNames(for category: String) -> [String] {
    scriptTemplates
        .filter { $0.category == category }
        .map(\.name)
}

// MARK: - Script Editor View

struct ScriptEditor: View {
    @Binding var document: HypeDocumentWrapper
    @Environment(\.hypeTheme) private var hypeTheme
    let partId: UUID?  // backward compat — maps to .part(id)
    var target: ScriptTarget? = nil  // preferred; overrides partId
    /// Optional 1-based line number to highlight as a runtime error
    /// location when the editor first appears. Passed through from
    /// `openScriptEditorWindow` after a `.showScriptError`
    /// notification fires. `nil` means no highlight.
    var initialErrorLine: Int? = nil
    /// Optional error message to display in the red banner at the
    /// bottom of the editor when it opens from a runtime failure.
    var initialErrorMessage: String? = nil
    /// Stable identity key for the target this editor is editing,
    /// matching `ScriptTarget.identityKey`. Used to filter
    /// `.refreshScriptError` broadcasts so a script editor for one
    /// part doesn't react to error refreshes intended for another.
    /// Optional for backward compatibility with the in-place
    /// (`.sheet`-based) usage in `PropertyInspector` — when `nil`,
    /// the editor doesn't subscribe to refreshes at all.
    var identityKey: String? = nil
    var onDone: (() -> Void)? = nil
    @AppStorage("hypeAppScript") private var hypeAppScript: String = ""
    @State private var scriptText: String = ""
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var errorMessage: String?
    @State private var selectedCategory: String = "Events"
    /// The 1-based line number currently highlighted as an error. When
    /// set, `HypeTalkTextView` draws a red background on that line and
    /// scrolls it into view. Cleared when the user edits the script.
    @State private var errorHighlightLine: Int? = nil

    private var resolvedTarget: ScriptTarget? {
        scriptEditorResolvedTarget(in: document.document, target: target, partId: partId)
    }

    private var partNames: [String] {
        document.document.parts.map { $0.name }.filter { !$0.isEmpty }
    }

    var body: some View {
        HSplitView {
            // Left: Command palette
            commandPalette
                .frame(width: 180)

            // Right: Code editor
            VStack(spacing: 0) {
                // Toolbar — themed so swapping themes also retints
                // the script editor's top bar to match the rest of
                // the chrome.
                HStack {
                    Text("Script Editor")
                        .font(.headline)
                    Spacer()
                    Button("Comment") { toggleComment() }
                        .accessibilityIdentifier(HypeAccessibilityID.toolbar("script.comment"))
                    Button("Check Syntax") { checkSyntax() }
                        .accessibilityIdentifier(HypeAccessibilityID.toolbar("script.checkSyntax"))
                    Button("Format") { reformatScript() }
                        .accessibilityIdentifier(HypeAccessibilityID.toolbar("script.format"))
                }
                .padding(8)
                .background(hypeTheme.toolbarBackground.swiftUIColor)
                .environment(\.colorScheme, hypeTheme.toolbarColorScheme)

                // Editor — picks up the active theme's script
                // sub-palette via the cascade-resolved hypeTheme
                // environment value injected by MainContentView.
                HypeTalkTextView(
                    text: $scriptText,
                    selectedRange: $selectedRange,
                    partNames: partNames,
                    errorHighlightLine: $errorHighlightLine,
                    accessibilityIdentifier: HypeAccessibilityID.scriptEditorText,
                    scriptTheme: hypeTheme.scriptTheme
                )
                    .frame(minHeight: 200)

                // Error display — kept semantically red but pulls
                // the tint from the active script theme so the
                // banner blends with whatever script-editor palette
                // the user has chosen.
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(hypeTheme.scriptTheme.error.swiftUIColor.opacity(0.15))
                }
            }

            ScriptEditorAIView(
                document: $document,
                scriptText: $scriptText,
                selectedRange: $selectedRange,
                target: resolvedTarget
            )
            .frame(width: 300)
            .accessibilityIdentifier(HypeAccessibilityID.scriptEditorAI)
        }
        .onAppear {
            loadScript()
            // Seed the runtime-error highlight and banner from the
            // values passed in by `openScriptEditorWindow`. We only
            // read these on first appearance — subsequent edits
            // clear the highlight via `onChange(of: scriptText)`.
            if let line = initialErrorLine, line > 0 {
                errorHighlightLine = line
            }
            if let msg = initialErrorMessage, !msg.isEmpty {
                errorMessage = msg
            }
        }
        .onChange(of: partId) { _, _ in loadScript() }
        .onChange(of: resolvedTarget?.identityKey) { _, _ in loadScript() }
        .onChange(of: scriptText) { _, _ in
            // Once the user starts editing, the runtime error
            // location is no longer reliable — clear the highlight
            // and banner so they don't mislead the user into
            // thinking the red line is still the problem.
            errorHighlightLine = nil
            errorMessage = nil
            applyScript()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshScriptError)) { notification in
            // A repeated runtime error fired for the same target
            // while this editor is already on screen. Refresh our
            // highlight and banner instead of letting
            // openScriptEditorWindow open a duplicate window.
            // The identityKey filter prevents a stale editor for
            // some other part from being repurposed.
            guard let myKey = identityKey else { return }
            let info = notification.userInfo ?? [:]
            guard let theirKey = info["identityKey"] as? String,
                  theirKey == myKey else { return }
            if let line = info["line"] as? Int, line > 0 {
                errorHighlightLine = line
            }
            if let msg = info["message"] as? String, !msg.isEmpty {
                errorMessage = msg
            }
        }
        .onDisappear { applyScript() }
        // Outer surface — paint the chrome with the inspector
        // background token so the whole editor window picks up
        // theme swaps (split-view background, list background).
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so command-palette labels and
        // toolbar text remain readable against the themed bg.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
        .accessibilityLabel("Script Editor")
        .accessibilityIdentifier(HypeAccessibilityID.scriptEditor)
    }

    // MARK: - Command Palette

    private var commandPalette: some View {
        VStack(spacing: 0) {
            Text("Commands")
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(hypeTheme.toolbarBackground.swiftUIColor)
                .environment(\.colorScheme, hypeTheme.toolbarColorScheme)

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
                            .accessibilityIdentifier(HypeAccessibilityID.scriptTemplate(template.name))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier(HypeAccessibilityID.scriptEditorCommands)
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

    private func sceneScript(partId: UUID, sceneId: UUID) -> String {
        guard let part = document.document.parts.first(where: { $0.id == partId }),
              let areaSpec = part.spriteAreaSpecModel,
              let entry = areaSpec.scenes.first(where: { $0.id == sceneId }) else {
            return ""
        }
        return entry.scene.script
    }

    private func nodeScript(partId: UUID, nodeId: UUID) -> String {
        guard let part = document.document.parts.first(where: { $0.id == partId }),
              let areaSpec = part.spriteAreaSpecModel else {
            return ""
        }
        for entry in areaSpec.scenes {
            if let node = entry.scene.node(id: nodeId) {
                return node.script
            }
        }
        return ""
    }

    private func nodeInfo(partId: UUID, nodeId: UUID) -> (sceneId: UUID, node: HypeNodeSpec)? {
        guard let part = document.document.parts.first(where: { $0.id == partId }),
              let areaSpec = part.spriteAreaSpecModel else {
            return nil
        }
        for entry in areaSpec.scenes {
            if let node = entry.scene.node(id: nodeId) {
                return (entry.id, node)
            }
        }
        return nil
    }

    private func updateSceneScript(partId: UUID, sceneId: UUID, script: String) {
        document.document.updatePart(id: partId) { part in
            part.updateSpriteAreaSpec { areaSpec in
                guard let index = areaSpec.scenes.firstIndex(where: { $0.id == sceneId }) else { return }
                areaSpec.scenes[index].scene.script = script
                if areaSpec.scenes[index].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[index].scene)
                }
            }
        }
    }

    private func updateNodeScript(partId: UUID, nodeId: UUID, script: String) {
        document.document.updatePart(id: partId) { part in
            part.updateSpriteAreaSpec { areaSpec in
                for index in areaSpec.scenes.indices {
                    var scene = areaSpec.scenes[index].scene
                    if scene.updateNode(id: nodeId, { $0.script = script }) {
                        areaSpec.scenes[index].scene = scene
                        return
                    }
                }
            }
        }
    }

    private func loadScript() {
        guard let t = resolvedTarget else { scriptText = ""; return }
        switch t {
        case .part(let id):
            scriptText = document.document.parts.first(where: { $0.id == id })?.script ?? ""
        case .card(let id):
            scriptText = document.document.cards.first(where: { $0.id == id })?.script ?? ""
        case .background(let id):
            scriptText = document.document.backgrounds.first(where: { $0.id == id })?.script ?? ""
        case .scene(let partId, let sceneId):
            scriptText = sceneScript(partId: partId, sceneId: sceneId)
        case .node(let partId, let nodeId):
            scriptText = nodeScript(partId: partId, nodeId: nodeId)
        case .stack:
            scriptText = document.document.stack.script
        case .hype:
            scriptText = hypeAppScript
        }
        scriptText = scriptEditorDisplayedScriptText(storedScript: scriptText)
    }

    private func toggleComment() {
        let nsString = scriptText as NSString
        let totalLength = nsString.length

        // Determine which lines are affected by the selection
        let selRange: NSRange
        if selectedRange.length > 0 {
            // Use selected range
            selRange = selectedRange
        } else if selectedRange.location <= totalLength {
            // No selection — use the line the cursor is on
            selRange = nsString.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        } else {
            return
        }

        // Expand selection to full lines
        let lineRange = nsString.lineRange(for: selRange)
        let selectedText = nsString.substring(with: lineRange)
        let lines = selectedText.components(separatedBy: "\n")

        // Check if all non-empty selected lines are commented
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allCommented = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("--")
        }

        let newLines: [String]
        if allCommented {
            // Uncomment: remove "-- " or "--" from each line
            newLines = lines.map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("--") else { return line }
                if let range = line.range(of: "-- ") {
                    var m = line; m.removeSubrange(range); return m
                } else if let range = line.range(of: "--") {
                    var m = line; m.removeSubrange(range); return m
                }
                return line
            }
        } else {
            // Comment: add "-- " after leading whitespace
            newLines = lines.map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return line }
                let indent = String(line.prefix(while: { $0 == " " }))
                return indent + "-- " + trimmed
            }
        }

        let replacement = newLines.joined(separator: "\n")
        scriptText = nsString.replacingCharacters(in: lineRange, with: replacement)
    }

    private func reformatScript() {
        let lines = scriptText.components(separatedBy: "\n")
        var result: [String] = []
        var indentLevel = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { result.append(""); continue }
            let lower = trimmed.lowercased()
            // Decrease indent BEFORE writing: end, else
            if lower.hasPrefix("end ") || lower == "else" {
                indentLevel = max(0, indentLevel - 1)
            }
            result.append(String(repeating: "  ", count: indentLevel) + trimmed)
            // Increase indent AFTER writing: on, repeat, function, if...then (multiline), else
            if lower.hasPrefix("on ") || lower.hasPrefix("repeat") || lower.hasPrefix("function ") || lower == "else" || (lower.hasPrefix("if ") && lower.hasSuffix("then")) {
                indentLevel += 1
            }
        }
        scriptText = result.joined(separator: "\n")
    }

    private func defaultTemplate(for target: ScriptTarget?) -> String {
        guard let t = target else { return "" }
        switch t {
        case .part(let id):
            let part = document.document.parts.first(where: { $0.id == id })
            if part?.partType == .button {
                return "on mouseUp\n  \n  pass mouseUp\nend mouseUp"
            } else if part?.partType == .field {
                return "on enterKey\n  \nend enterKey"
            } else if part?.partType == .spriteArea {
                return "on sceneDidLoad\n  \nend sceneDidLoad"
            }
            return ""
        case .card:
            return "on openCard\n  \n  pass openCard\nend openCard"
        case .background:
            return "on openCard\n  \n  pass openCard\nend openCard"
        case .scene:
            return "on sceneDidLoad\n  \nend sceneDidLoad"
        case .node(let partId, let nodeId):
            let type = nodeInfo(partId: partId, nodeId: nodeId)?.node.nodeType
            switch type {
            case .sprite, .shape, .label:
                return "on mouseDown\n  \n  pass mouseDown\nend mouseDown"
            case .audio, .video:
                return "on openScene\n  \nend openScene"
            default:
                return "on mouseDown\n  \nend mouseDown"
            }
        case .stack:
            return "on openStack\n  \nend openStack"
        case .hype:
            return "-- Global Hype app-level script\n-- Stored in this Mac's app preferences, not in the current stack.\n-- For portable stack behavior, put handlers in this stack's script instead.\n"
        }
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
        guard let t = resolvedTarget else { return }
        switch t {
        case .part(let id):
            document.document.updatePart(id: id) { $0.script = scriptText }
        case .card(let id):
            if let idx = document.document.cards.firstIndex(where: { $0.id == id }) {
                document.document.cards[idx].script = scriptText
            }
        case .background(let id):
            if let idx = document.document.backgrounds.firstIndex(where: { $0.id == id }) {
                document.document.backgrounds[idx].script = scriptText
            }
        case .scene(let partId, let sceneId):
            updateSceneScript(partId: partId, sceneId: sceneId, script: scriptText)
        case .node(let partId, let nodeId):
            updateNodeScript(partId: partId, nodeId: nodeId, script: scriptText)
        case .stack:
            document.document.stack.script = scriptText
        case .hype:
            hypeAppScript = scriptText
        }
    }
}

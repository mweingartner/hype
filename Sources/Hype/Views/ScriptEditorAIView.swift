import SwiftUI
import HypeCore

struct ScriptEditorAIView: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var scriptText: String
    @Binding var selectedRange: NSRange
    let target: ScriptTarget?

    @Environment(\.hypeTheme) private var hypeTheme
    @StateObject private var speechCapture = AISpeechCapture()
    @State private var prompt = ""
    @State private var promptContentHeight: CGFloat = 18
    @State private var messages: [ScriptAIMessage] = []
    @State private var isProcessing = false
    @State private var activeRequestTask: Task<Void, Never>?
    @State private var historyIndex: Int = -1
    @FocusState private var isPromptFocused: Bool

    private struct ScriptAIMessage: Identifiable, Equatable {
        let id = UUID()
        let role: String
        let content: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wand.and.sparkles")
                Text("Script AI")
                    .font(.headline)
                Spacer()
                if !messages.isEmpty {
                    Button {
                        messages.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Script AI chat")
                }
            }
            .padding(8)
            .background(hypeTheme.toolbarBackground.swiftUIColor)
            .environment(\.colorScheme, hypeTheme.toolbarColorScheme)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role.capitalized)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text(message.content)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(bubbleColor(for: message.role))
                                    .cornerRadius(8)
                            }
                            .id(message.id)
                        }
                        if isProcessing {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Working...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: messages) { _, _ in
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if let lastAssistant = messages.last(where: { $0.role == "assistant" }) {
                HStack {
                    Button("Insert") { insert(lastAssistant.content) }
                    Button("Replace Script") { scriptText = cleanScript(lastAssistant.content) }
                    Spacer()
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            HStack(alignment: .bottom, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("Ask Script AI for HypeTalk help...")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                            .padding(8)
                            .allowsHitTesting(false)
                    }

                    AIChatInputView(
                        text: $prompt,
                        contentHeight: $promptContentHeight,
                        isEnabled: !isProcessing,
                        onSubmit: { sendPrompt() },
                        onHistoryUp: { recallHistory(direction: .up) },
                        onHistoryDown: { recallHistory(direction: .down) }
                    )
                    .padding(8)
                    .focused($isPromptFocused)
                }
                .frame(height: min(max(promptContentHeight + 16, 32), 320))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )

                HStack(spacing: 4) {
                    if isProcessing {
                        Button("Stop") { haltCurrentTask() }
                            .foregroundColor(.red)
                            .help("Stop the current model request")
                    } else {
                        Button("Submit") { sendPrompt() }
                            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Submit to Script AI (Return)")
                    }

                    Button {
                        speechCapture.toggle()
                    } label: {
                        Image(systemName: speechCapture.isTranscribing ? "waveform.circle" : (speechCapture.isListening ? "mic.fill" : "mic"))
                            .foregroundColor(speechCapture.isListening ? .red : .primary)
                    }
                    .buttonStyle(.borderless)
                    .help(speechCapture.isTranscribing ? "Transcribing..." : "Voice prompt")
                }
                .padding(.bottom, 6)
            }
            .padding(8)
            .onAppear {
                isPromptFocused = true
            }
            .onChange(of: speechCapture.transcript) { _, newValue in
                if speechCapture.isListening {
                    prompt = newValue
                }
            }
            .onReceive(speechCapture.transcriptDidFinalize) { finalText in
                let cleaned = finalText
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cancelPhrases = ["cancel operation", "cancel the operation", "stop", "halt"]
                if isProcessing && cancelPhrases.contains(where: { cleaned.contains($0) }) {
                    haltCurrentTask()
                    prompt = ""
                    return
                }
                guard !cleaned.isEmpty else { return }
                prompt = finalText
                sendPrompt()
            }
            .onDisappear {
                speechCapture.stop()
                haltCurrentTask(appendStoppedMessage: false)
            }
        }
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
    }

    private func bubbleColor(for role: String) -> Color {
        role == "user"
            ? hypeTheme.accent.swiftUIColor.opacity(0.15)
            : hypeTheme.inspectorBackground.swiftUIColor.opacity(0.8)
    }

    private func sendPrompt() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isProcessing else { return }

        document.document.aiPromptHistory = AIChatPromptHistory.appending(
            request,
            to: document.document.aiPromptHistory
        )
        historyIndex = -1

        messages.append(ScriptAIMessage(role: "user", content: request))
        prompt = ""
        isProcessing = true

        activeRequestTask = Task {
            do {
                let client = try HypeAIConfiguration.makeClient()
                let answer = try await client.generate(
                    prompt: userPrompt(for: request),
                    model: nil,
                    system: ScriptEditorAIPrompts.systemPrompt
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    messages.append(ScriptAIMessage(role: "assistant", content: answer))
                    finishProcessing()
                }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else {
                    await MainActor.run { finishProcessing() }
                    return
                }
                await MainActor.run {
                    messages.append(ScriptAIMessage(role: "assistant", content: "Error: \(error.localizedDescription)"))
                    finishProcessing()
                }
            }
        }
    }

    private func haltCurrentTask(appendStoppedMessage: Bool = true) {
        guard isProcessing || activeRequestTask != nil else { return }
        activeRequestTask?.cancel()
        activeRequestTask = nil
        isProcessing = false
        isPromptFocused = true
        speechCapture.stop()
        if appendStoppedMessage {
            messages.append(ScriptAIMessage(role: "assistant", content: "Stopped."))
        }
    }

    private func finishProcessing() {
        isProcessing = false
        activeRequestTask = nil
        isPromptFocused = true
    }

    private func recallHistory(direction: AIChatPromptHistoryDirection) {
        if let recalled = AIChatPromptHistory.recall(
            direction: direction,
            from: document.document.aiPromptHistory,
            index: &historyIndex
        ) {
            prompt = recalled
        }
    }

    private func userPrompt(for request: String) -> String {
        ScriptEditorAIPrompts.userPrompt(
            request: request,
            targetDescription: targetDescription,
            selectedText: selectedText,
            scriptText: scriptText
        )
    }

    private var selectedText: String {
        let ns = scriptText as NSString
        guard selectedRange.location >= 0,
              selectedRange.location <= ns.length,
              selectedRange.location + selectedRange.length <= ns.length,
              selectedRange.length > 0 else {
            return ""
        }
        return ns.substring(with: selectedRange)
    }

    private var targetDescription: String {
        guard let target else { return "Unknown target" }
        switch target {
        case .part(let id):
            if let part = document.document.parts.first(where: { $0.id == id }) {
                return "\(part.partType.rawValue) \"\(part.name)\""
            }
            return "Part \(id.uuidString)"
        case .card(let id):
            let name = document.document.cards.first(where: { $0.id == id })?.name ?? id.uuidString
            return "Card \"\(name)\""
        case .background(let id):
            let name = document.document.backgrounds.first(where: { $0.id == id })?.name ?? id.uuidString
            return "Background \"\(name)\""
        case .scene(let partId, let sceneId):
            let partName = document.document.parts.first(where: { $0.id == partId })?.name ?? partId.uuidString
            return "Sprite scene \(sceneId.uuidString) in sprite area \"\(partName)\""
        case .node(let partId, let nodeId):
            let partName = document.document.parts.first(where: { $0.id == partId })?.name ?? partId.uuidString
            return "Sprite node \(nodeId.uuidString) in sprite area \"\(partName)\""
        case .stack:
            return "Stack \"\(document.document.stack.name)\""
        case .hype:
            return "Hype application script"
        }
    }

    private func insert(_ text: String) {
        let replacement = cleanScript(text)
        let ns = scriptText as NSString
        if selectedRange.location >= 0,
           selectedRange.location <= ns.length,
           selectedRange.location + selectedRange.length <= ns.length {
            scriptText = ns.replacingCharacters(in: selectedRange, with: replacement)
        } else {
            if !scriptText.hasSuffix("\n"), !scriptText.isEmpty {
                scriptText += "\n"
            }
            scriptText += replacement
        }
    }

    private func cleanScript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var body = trimmed
        if let firstNewline = body.firstIndex(of: "\n") {
            body = String(body[body.index(after: firstNewline)...])
        } else {
            body = String(body.dropFirst(3))
        }
        if let closeRange = body.range(of: "```", options: .backwards) {
            body = String(body[..<closeRange.lowerBound])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ScriptEditorAIPrompts {
    static var systemPrompt: String {
        """
        You are Hype's Script Editor AI. Help write and revise HypeTalk only.
        HypeTalk is not JavaScript, Swift, Python, or Lua.
        If the user asks for code, return only the complete HypeTalk script or snippet, with no Markdown fence.
        If the user asks a question, answer concisely and include HypeTalk examples only when useful.

        \(HypeTalkGuide.llmContext)
        """
    }

    static func userPrompt(
        request: String,
        targetDescription: String,
        selectedText: String,
        scriptText: String
    ) -> String {
        """
        TARGET:
        \(targetDescription)

        SELECTED TEXT:
        \(selectedText.isEmpty ? "(none)" : selectedText)

        CURRENT SCRIPT:
        \(scriptText.isEmpty ? "(empty)" : scriptText)

        USER REQUEST:
        \(request)
        """
    }
}

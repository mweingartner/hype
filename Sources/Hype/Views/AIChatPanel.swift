import SwiftUI
import HypeCore

struct AIChatPanel: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var inputText = ""
    @State private var messages: [ChatBubble] = []
    @State private var conversationMessages: [OllamaMessage] = []  // Full context for model
    @State private var isProcessing = false
    /// Set when sendMessage launches `processWithTools` so the user
    /// can interrupt it via the Stop button (or via "cancel
    /// operation" voice command). Cleared when the task completes
    /// or is cancelled.
    @State private var activeChatTask: Task<Void, Never>? = nil
    /// Speech-to-text controller. Lazily initialized — its
    /// `start()` requests mic + speech-recognition authorization.
    @StateObject private var speechCapture = AISpeechCapture()
    @State private var lastFinalizedTranscript: String? = nil
    @State private var historyIndex: Int = -1
    @State private var pendingSceneProposal: PendingSceneProposal?
    @State private var lastStructuredUndoDocument: HypeDocument?
    @FocusState private var isInputFocused: Bool

    @AppStorage("ollamaHost") private var ollamaHost = "localhost"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("hype.webAssets.provider") private var webAssetProviderRaw = "openverse"

    // MARK: - Chat bubble model

    /// A single chat message bubble, optionally carrying a captured card image for display.
    private struct ChatBubble: Identifiable, Equatable {
        let id: UUID = UUID()
        let role: String
        let content: String
        let imageBase64: String?
        let imagePixelWidth: Int?
        let imagePixelHeight: Int?
        let imageCaption: String?

        init(
            role: String,
            content: String,
            imageBase64: String? = nil,
            imagePixelWidth: Int? = nil,
            imagePixelHeight: Int? = nil,
            imageCaption: String? = nil
        ) {
            self.role = role
            self.content = content
            self.imageBase64 = imageBase64
            self.imagePixelWidth = imagePixelWidth
            self.imagePixelHeight = imagePixelHeight
            self.imageCaption = imageCaption
        }

        // Equatable ignores `id` so two bubbles with same content compare equal.
        static func == (lhs: ChatBubble, rhs: ChatBubble) -> Bool {
            lhs.role == rhs.role &&
            lhs.content == rhs.content &&
            lhs.imageBase64 == rhs.imageBase64 &&
            lhs.imagePixelWidth == rhs.imagePixelWidth &&
            lhs.imagePixelHeight == rhs.imagePixelHeight &&
            lhs.imageCaption == rhs.imageCaption
        }
    }

    // MARK: - Web Asset Search state

    /// One session per chat panel — lives for the panel's lifetime, cleared by clearChat().
    @State private var webAssetSession = WebAssetSession()
    /// Set to true while a web-asset search or download is in progress.
    @State private var isSearchingWeb = false

    // MARK: - Script validation iteration state

    /// Coordinator for the host-side script validation iteration loop.
    @State private var scriptDraftCoordinator = ScriptDraftCoordinator()

    /// Non-nil while the coordinator is retrying a refused script draft.
    /// Drives the iteration status indicator in the chat area.
    @State private var iterationStatus: IterationStatus?

    /// Status displayed during a script draft iteration loop.
    private struct IterationStatus: Equatable {
        var attemptNumber: Int
        let maxAttempts: Int
        let toolName: String
        let targetDescription: String
    }

    // MARK: - Visual capture state

    /// Coordinator for `capture_card_image` tool result classification and message building.
    @State private var captureCoordinator = CardCaptureCoordinator()

    /// Tracks how many card captures have been made this session and this turn.
    @State private var captureBudget = CardCaptureBudget()

    /// Non-nil while a card capture is in progress. Drives the status indicator.
    @State private var captureStatus: CaptureStatus?

    /// Temp PNG files written for Quick Look / tap-to-open. Cleaned up on clear and disappear.
    @State private var captureTempFiles: [URL] = []

    /// Status displayed while a card capture is in progress.
    private struct CaptureStatus: Equatable {
        let cardName: String
    }

    private enum PendingSceneProposal {
        case create(SceneCreateProposal)
        case repair(SceneRepairProposal)

        var title: String {
            switch self {
            case .create: return "Scene Plan Ready"
            case .repair: return "Scene Repair Ready"
            }
        }

        var summary: String {
            switch self {
            case .create(let proposal): return proposal.summary
            case .repair(let proposal): return proposal.summary
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                Text("AI Assistant").font(.headline)
                Spacer()
                if !messages.isEmpty {
                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Chat")
                }
                Text(ollamaModel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            // AI Chat header bar — themed to match the toolbar.
            .background(hypeTheme.toolbarBackground.swiftUIColor)
            // Force header text to contrast with the themed
            // background regardless of macOS appearance.
            .environment(\.colorScheme, hypeTheme.toolbarColorScheme)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { idx, msg in
                            HStack(alignment: .top) {
                                if msg.role == "user" { Spacer() }
                                VStack(alignment: msg.role == "user" ? .trailing : .leading) {
                                    Text(msg.content)
                                        .font(.system(size: 13))
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .background(bubbleColor(for: msg.role))
                                        .cornerRadius(8)
                                    // Thumbnail for captured card images.
                                    if let b64 = msg.imageBase64,
                                       let pngData = Data(base64Encoded: b64),
                                       let nsImage = NSImage(data: pngData) {
                                        let aspectRatio = nsImage.size.height > 0
                                            ? nsImage.size.width / nsImage.size.height
                                            : 1.0
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: 140, maxHeight: 140 / aspectRatio)
                                            .cornerRadius(4)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                                            )
                                            .onTapGesture {
                                                openCapturePNG(b64, suggestedName: msg.content)
                                            }
                                        if let caption = msg.imageCaption {
                                            Text(caption)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: 140, alignment: .leading)
                                        }
                                    }
                                }
                                if msg.role != "user" { Spacer() }
                            }
                            .id(idx)
                        }
                        if let captureStatus {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text(captureStatus.cardName.isEmpty
                                    ? "Capturing card for AI review…"
                                    : "Capturing card '\(captureStatus.cardName)' for AI review…")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        } else if let iterationStatus {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Validating script (attempt \(iterationStatus.attemptNumber) of \(iterationStatus.maxAttempts))…")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        } else if isSearchingWeb {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Searching the web…")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        } else if isProcessing {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: messages.count) { _, _ in
                    if !messages.isEmpty {
                        proxy.scrollTo(messages.count - 1, anchor: .bottom)
                    }
                }
            }

            if let pendingSceneProposal {
                pendingProposalView(pendingSceneProposal)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            } else if lastStructuredUndoDocument != nil {
                HStack {
                    Text("Last structured scene change is undoable.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Undo") {
                        undoStructuredSceneApply()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }

            // Input area — zero-inset NSTextView wrapper so the live
            // cursor sits at the same pixel position as the placeholder.
            // SwiftUI's TextEditor inherits ~10pt of NSTextView text-
            // container insets that aren't accounted for by sibling
            // Text padding — the visible bug was a few-pixel jump on
            // focus. AIChatInputView zeroes those insets so a single
            // SwiftUI .padding(8) on both this and the placeholder
            // makes them coincide exactly.
            HStack(alignment: .bottom, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Ask AI to build something...")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                    AIChatInputView(
                        text: $inputText,
                        isEnabled: !isProcessing,
                        onSubmit: { sendMessage() },
                        onHistoryUp: { recallHistory(direction: .up) },
                        onHistoryDown: { recallHistory(direction: .down) }
                    )
                    .padding(8)
                    .focused($isInputFocused)
                }
                .frame(minHeight: 32, maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

                // Trailing button column: Send (or Stop while
                // processing) + Mic. Voice + halt sit next to the
                // text entry, right-aligned per the spec.
                HStack(spacing: 4) {
                    if isProcessing {
                        Button(action: haltCurrentTask) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop the AI (or say 'cancel operation')")
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.borderless)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send (Return)")
                    }

                    Button(action: { speechCapture.toggle() }) {
                        Image(systemName: speechCapture.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 14))
                            .foregroundColor(speechCapture.isListening ? .red : .primary)
                    }
                    .buttonStyle(.borderless)
                    .help(speechCapture.isListening ? "Stop listening" : "Start voice input")
                }
                .padding(.bottom, 6)
            }
            .padding(8)
            // Mirror the live transcript into the input field while
            // listening, so the user sees what's being recognized.
            .onChange(of: speechCapture.transcript) { _, newValue in
                if speechCapture.isListening {
                    inputText = newValue
                }
            }
            // When the recognizer finalizes an utterance, treat it
            // like the user pressed Return — but first check for
            // the "cancel operation" voice command, which halts an
            // in-flight model call instead of submitting a message.
            .onReceive(speechCapture.transcriptDidFinalize) { finalText in
                let cleaned = finalText
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cancelPhrases = ["cancel operation", "cancel the operation", "stop", "halt"]
                if isProcessing && cancelPhrases.contains(where: { cleaned.contains($0) }) {
                    haltCurrentTask()
                    inputText = ""
                    return
                }
                if !cleaned.isEmpty {
                    lastFinalizedTranscript = finalText
                    inputText = finalText
                    sendMessage()
                }
            }
            .onAppear {
                isInputFocused = true
                preloadModelIfNeeded()
            }
            .onChange(of: ollamaModel) { _ in
                preloadModelIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .haltAIChat)) { _ in
                if isProcessing {
                    haltCurrentTask()
                }
            }
            .onDisappear {
                // Stop voice capture if the panel is closed mid-listen
                // — otherwise the audio engine and recognition task
                // keep running in the background.
                speechCapture.stop()
            }
        }
        .frame(width: 350)
        // AI panel surface — pulls the inspector-background token
        // so the chat panel matches the rest of the side chrome
        // regardless of theme.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so message text, input field, and
        // assistant labels resolve against the panel bg luminance
        // rather than the macOS appearance.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
        .onDisappear {
            // Remove temp PNG files created for Quick Look when the panel closes.
            for url in captureTempFiles {
                try? FileManager.default.removeItem(at: url)
            }
            captureTempFiles.removeAll()
        }
    }

    // MARK: - History

    private enum HistoryDirection { case up, down }

    /// Warm up the currently selected Ollama model in the background
    /// so the first user message doesn't pay a cold-load penalty.
    ///
    /// A 56 GB tuned model (hypetalk-gemma4:27b-v1) takes ~10-40 s
    /// to load into unified memory on first use. Ollama's default
    /// keep-alive is 5 minutes of idle before it unloads the
    /// weights — meaning every chat session that opens after a
    /// 5-minute gap from the previous one hits that cold-load
    /// penalty on top of generation time, occasionally pushing
    /// past Hype's 600 s per-request budget on long prompts.
    ///
    /// This fires a zero-token `/api/generate` with
    /// `keep_alive: 30m` against the current model as soon as the
    /// AI panel becomes visible (and again when the user swaps
    /// models in Preferences). Fire-and-forget — a failure here
    /// shouldn't block the UI; the actual chat request will
    /// surface its own error if the model is genuinely
    /// unreachable.
    private func preloadModelIfNeeded() {
        let host = ollamaHost
        let port = ollamaPort
        let model = ollamaModel
        Task.detached {
            let client = OllamaToolClient(host: host, port: port, model: model)
            try? await client.preloadModel()
        }
    }

    private func recallHistory(direction: HistoryDirection) {
        let history = document.document.aiPromptHistory
        guard !history.isEmpty else { return }

        switch direction {
        case .up:
            if historyIndex < 0 {
                historyIndex = history.count - 1
            } else if historyIndex > 0 {
                historyIndex -= 1
            }
            inputText = history[historyIndex]
        case .down:
            if historyIndex >= 0 && historyIndex < history.count - 1 {
                historyIndex += 1
                inputText = history[historyIndex]
            } else {
                historyIndex = -1
                inputText = ""
            }
        }
    }

    private func clearChat() {
        messages.removeAll()
        conversationMessages.removeAll()
        pendingSceneProposal = nil
        iterationStatus = nil
        Task { await webAssetSession.reset() }
        captureBudget.resetSession()
        captureStatus = nil
        // Clean up any temp PNG files written for thumbnail Quick Look.
        for url in captureTempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        captureTempFiles.removeAll()
    }

    private func appendMessage(
        role: String,
        content: String,
        imageBase64: String? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        imageCaption: String? = nil
    ) {
        messages.append(ChatBubble(
            role: role,
            content: content,
            imageBase64: imageBase64,
            imagePixelWidth: imagePixelWidth,
            imagePixelHeight: imagePixelHeight,
            imageCaption: imageCaption
        ))
        // For logging: if this bubble carries a capture image, the caller is
        // responsible for using HypeLogger directly with a redacted string.
        // Plain bubbles (no image) are safe to log as-is.
        if imageBase64 == nil {
            HypeLogger.shared.aiDialog(role: role, content: content, source: "AI Chat")
        }
    }

    // MARK: - Bubble Color

    /// Bubble background per role — themed so swapping themes also
    /// retints chat bubbles.
    /// - user: theme accent at 15% so the accent color reads as a
    ///   subtle wash, matching the inspector's selected-row tint.
    /// - tool: kept semantically green at low opacity so tool-call
    ///   results remain visually distinct from chat content.
    /// - assistant (default): the theme's inspector-background tone
    ///   so assistant bubbles sit one elevation above the panel bg.
    private func bubbleColor(for role: String) -> Color {
        switch role {
        case "user": return hypeTheme.accent.swiftUIColor.opacity(0.15)
        case "tool": return Color.green.opacity(0.1)
        default: return hypeTheme.inspectorBackground.swiftUIColor
        }
    }

    // MARK: - Capture PNG Quick Look

    /// Write a base64-encoded PNG to a temp file and open it with the system default viewer.
    ///
    /// The temp file URL is appended to `captureTempFiles` so it gets cleaned up
    /// when the chat is cleared or the panel disappears.
    private func openCapturePNG(_ base64: String, suggestedName: String) {
        guard let data = Data(base64Encoded: base64) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-capture-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            captureTempFiles.append(url)
            NSWorkspace.shared.open(url)
        } catch {
            HypeLogger.shared.warn("Failed to write capture PNG for Quick Look: \(error.localizedDescription)", source: "AI Chat")
        }
    }

    @ViewBuilder
    private func pendingProposalView(_ proposal: PendingSceneProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(proposal.title)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button("Dismiss") {
                    pendingSceneProposal = nil
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }

            Text(proposal.summary)
                .font(.system(size: 12))

            switch proposal {
            case .create(let create):
                Text("Target: \(create.areaName) / \(create.sceneName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                ForEach(create.checklist) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: checklistIcon(for: item.status))
                            .foregroundColor(checklistColor(for: item.status))
                            .font(.system(size: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 11, weight: .medium))
                            Text(item.detail).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
            case .repair(let repair):
                ForEach(repair.issues.prefix(5)) { issue in
                    Text("\(issue.severity.rawValue.uppercased()): \(issue.message)")
                        .font(.system(size: 10))
                        .foregroundColor(issue.severity == .error ? .red : (issue.severity == .warning ? .orange : .secondary))
                }
            }

            HStack {
                Button("Apply") {
                    applyPendingSceneProposal()
                }
                .buttonStyle(.borderedProminent)

                if lastStructuredUndoDocument != nil {
                    Button("Undo Last") {
                        undoStructuredSceneApply()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(10)
        // Themed proposal card — uses the inspector-background tone
        // so it blends with the rest of the AI panel's chrome under
        // any theme.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        .cornerRadius(10)
    }

    private func checklistIcon(for status: SceneChecklistStatus) -> String {
        switch status {
        case .complete: return "checkmark.circle.fill"
        case .recommended: return "exclamationmark.circle"
        case .missing: return "xmark.circle"
        }
    }

    private func checklistColor(for status: SceneChecklistStatus) -> Color {
        switch status {
        case .complete: return .green
        case .recommended: return .orange
        case .missing: return .red
        }
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Save to prompt history (in document for persistence)
        if document.document.aiPromptHistory.last != text {
            document.document.aiPromptHistory.append(text)
            // Keep last 100 prompts
            if document.document.aiPromptHistory.count > 100 {
                document.document.aiPromptHistory.removeFirst(document.document.aiPromptHistory.count - 100)
            }
        }
        historyIndex = -1

        appendMessage(role: "user", content: text)
        inputText = ""
        isProcessing = true

        // Track the task so the Stop button (and the "cancel
        // operation" voice command) can interrupt mid-flight. Hype
        // structured concurrency: the cancellation propagates into
        // the underlying URLSession requests via Task.isCancelled
        // checks scattered through processWithTools / iterateScript
        // / OllamaToolClient.chat().
        activeChatTask = Task {
            await processWithTools(userMessage: text)
            await MainActor.run {
                isProcessing = false
                isInputFocused = true
                activeChatTask = nil
            }
        }
    }

    /// Cancel the currently-running AI chat round, if any.
    /// Wired to: the on-screen Stop button, the "cancel operation"
    /// voice phrase, and the `.haltAIChat` notification (so a
    /// keyboard shortcut can be added later without touching this
    /// view).
    private func haltCurrentTask() {
        activeChatTask?.cancel()
        activeChatTask = nil
        isProcessing = false
        iterationStatus = nil
        captureStatus = nil
        appendMessage(role: "assistant", content: "Stopped.")
        isInputFocused = true
    }

    private func applyPendingSceneProposal() {
        guard let pendingSceneProposal else { return }
        lastStructuredUndoDocument = document.document

        switch pendingSceneProposal {
        case .create(let proposal):
            applyCreateProposal(proposal)
            appendMessage(role: "assistant", content: "Applied scene plan to \(proposal.areaName) / \(proposal.sceneName).")
        case .repair(let proposal):
            applyRepairProposal(proposal)
            appendMessage(role: "assistant", content: "Applied scene repair to \(proposal.areaName).")
        }

        self.pendingSceneProposal = nil
    }

    private func undoStructuredSceneApply() {
        guard let snapshot = lastStructuredUndoDocument else { return }
        document.document = snapshot
        lastStructuredUndoDocument = nil
        appendMessage(role: "assistant", content: "Undid the last structured scene change.")
    }

    private func applyCreateProposal(_ proposal: SceneCreateProposal) {
        guard let cardId = currentCardId ?? document.document.sortedCards.first?.id else { return }
        let partIndex = ensureSpriteAreaPartIndex(named: proposal.areaName, cardId: cardId, sceneSize: proposal.scene.size)

        guard let partIndex else { return }
        document.document.updatePart(id: document.document.parts[partIndex].id) { part in
            part.updateSpriteAreaSpec { areaSpec in
                areaSpec.designSize = proposal.scene.size
                areaSpec.scaleMode = proposal.scene.scaleMode
                areaSpec.showsPhysics = proposal.scene.showsPhysics
                areaSpec.showsFPS = proposal.scene.showsFPS
                areaSpec.showsNodeCount = proposal.scene.showsNodeCount

                let targetSceneId: UUID
                if let existing = areaSpec.scenes.first(where: { $0.scene.name.lowercased() == proposal.sceneName.lowercased() }) {
                    targetSceneId = existing.id
                } else {
                    targetSceneId = areaSpec.addScene(named: proposal.sceneName, basedOn: nil).id
                }

                guard let index = areaSpec.scenes.firstIndex(where: { $0.id == targetSceneId }) else { return }
                var scene = areaSpec.scenes[index].scene
                scene.name = proposal.sceneName
                scene.size = proposal.scene.size
                scene.backgroundColor = proposal.scene.backgroundColor
                scene.gravity = proposal.scene.gravity
                scene.scaleMode = proposal.scene.scaleMode
                scene.showsPhysics = proposal.scene.showsPhysics
                scene.showsFPS = proposal.scene.showsFPS
                scene.showsNodeCount = proposal.scene.showsNodeCount
                scene.script = proposal.scene.sceneScript
                scene.nodes = buildBlueprintNodes(proposal.scene.nodes)
                areaSpec.scenes[index].scene = scene
                areaSpec.activeSceneID = targetSceneId
            }
        }

        // Auto-resolve missing assets from the web when the stack has web assets enabled.
        if document.document.stack.webAssetsAllowed {
            let snap = proposal
            Task {
                isSearchingWeb = true
                defer { isSearchingWeb = false }
                // Reset the per-turn soft cap before dispatching asset-
                // resolution imports. Without this, the counter from the
                // prior `processWithTools` turn carries over and can
                // silently skip some or all resolutions — if a user's
                // last chat turn already used 18 web-asset calls, only
                // 2 resolutions would succeed and the remainder would
                // be dropped without a clear signal. `resolveMissingAssets`
                // is a fresh user-initiated operation, so treating it as
                // a new turn is correct. (Security Finding N-3.)
                await webAssetSession.beginTurn()
                let client = WebAssetSearchClientFactory.make(
                    provider: WebAssetSearchProvider(rawValue: webAssetProviderRaw) ?? .openverse
                )
                let pipeline = WebAssetImportPipeline()
                let ollamaClient = OllamaToolClient(host: ollamaHost, port: ollamaPort, model: ollamaModel)
                let assistant = SceneAuthoringAssistant(client: ollamaClient)
                var doc = document.document
                let report = await assistant.resolveMissingAssets(
                    proposal: snap,
                    document: &doc,
                    session: webAssetSession,
                    client: client,
                    pipeline: pipeline
                )
                document.document = doc
                if !report.resolvedAssets.isEmpty {
                    appendMessage(role: "assistant", content: "Auto-imported \(report.resolvedAssets.count) asset(s): \(report.resolvedAssets.joined(separator: ", ")).")
                }
            }
        }
    }

    private func applyRepairProposal(_ proposal: SceneRepairProposal) {
        // Try the exact name the proposal carries. If the model (or the
        // lenient decoder fallback) produced a bad name, fall through
        // to the first sprite area on the current card — that's what
        // `preferredRepairSpriteArea` already handed to the assistant
        // as the repair target, so the applied diff still lands on the
        // intended part. This prevents the classic "Could not find
        // sprite area 'main' to repair" error when the model confuses
        // a scene name with an area name.
        let resolvedIndex = resolveSpriteAreaIndex(named: proposal.areaName)
        guard let index = resolvedIndex else {
            appendMessage(role: "assistant", content: "Could not find sprite area '\(proposal.areaName)' to repair.")
            return
        }
        document.document.updatePart(id: document.document.parts[index].id) { part in
            part.updateActiveSceneSpec { scene in
                proposal.diff.apply(to: &scene)
            }
        }
    }

    /// Find a sprite area Part by name, falling back to the first
    /// sprite area visible on the current card when the lookup fails.
    /// Used by both repair and create apply paths so off-name proposals
    /// from the model don't abort the whole operation.
    private func resolveSpriteAreaIndex(named name: String) -> Int? {
        let target = name.lowercased()
        if let exact = document.document.parts.firstIndex(where: {
            $0.partType == .spriteArea && $0.name.lowercased() == target
        }) {
            return exact
        }
        guard let cardId = currentCardId ?? document.document.sortedCards.first?.id else {
            return nil
        }
        // Visible-on-current-card sprite areas (card-level + background).
        let visible = document.document.effectivePartsForCard(cardId).filter {
            $0.partType == .spriteArea
        }
        // Prefer a single card-level sprite area when there's no ambiguity.
        if let only = visible.first, visible.count == 1 {
            return document.document.parts.firstIndex(where: { $0.id == only.id })
        }
        // Otherwise, any sprite area in the document — better than aborting.
        return document.document.parts.firstIndex(where: { $0.partType == .spriteArea })
    }

    private func ensureSpriteAreaPartIndex(named name: String, cardId: UUID, sceneSize: SizeSpec) -> Int? {
        if let existing = document.document.parts.firstIndex(where: {
            $0.partType == .spriteArea && $0.cardId == cardId && $0.name.lowercased() == name.lowercased()
        }) {
            return existing
        }

        let stackWidth = Double(document.document.stack.width)
        let stackHeight = Double(document.document.stack.height)
        let maxWidth = Swift.max(240.0, Swift.min(sceneSize.width, stackWidth - 40))
        let maxHeight = Swift.max(180.0, Swift.min(sceneSize.height, stackHeight - 80))
        var part = Part(
            partType: .spriteArea,
            cardId: cardId,
            backgroundId: nil,
            name: name,
            left: 20,
            top: 20,
            width: maxWidth,
            height: maxHeight
        )
        part.setSpriteAreaSpec(
            SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: sceneSize)
        )
        document.document.addPart(part)
        return document.document.parts.firstIndex(where: { $0.id == part.id })
    }

    private func buildBlueprintNodes(_ blueprints: [SceneBlueprintNode]) -> [HypeNodeSpec] {
        let built = blueprints.map(makeNode)
        var roots: [HypeNodeSpec] = []
        for (blueprint, node) in zip(blueprints, built) {
            if let parentName = blueprint.parentName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !parentName.isEmpty,
               addNode(node, toParentNamed: parentName, in: &roots) {
                continue
            }
            roots.append(node)
        }
        return roots
    }

    private func addNode(_ node: HypeNodeSpec, toParentNamed parentName: String, in nodes: inout [HypeNodeSpec]) -> Bool {
        for index in nodes.indices {
            if nodes[index].name.lowercased() == parentName.lowercased() {
                nodes[index].children.append(node)
                return true
            }
            if addNode(node, toParentNamed: parentName, in: &nodes[index].children) {
                return true
            }
        }
        return false
    }

    private func makeNode(from blueprint: SceneBlueprintNode) -> HypeNodeSpec {
        var node = HypeNodeSpec(
            name: blueprint.name,
            nodeType: blueprint.nodeType,
            position: blueprint.position,
            size: blueprint.size,
            text: blueprint.text,
            fontName: blueprint.fontName,
            fontSize: blueprint.fontSize,
            fontColor: blueprint.fontColor,
            script: blueprint.script ?? ""
        )
        node.alpha = blueprint.alpha ?? 1
        node.isHidden = blueprint.isHidden ?? false

        if let assetName = blueprint.assetName,
           let asset = document.document.spriteRepository.asset(byName: assetName) {
            node.assetRef = document.document.spriteRepository.assetRef(for: asset)
        }
        if let audioAssetName = blueprint.audioAssetName,
           let asset = document.document.spriteRepository.asset(byName: audioAssetName) {
            node.assetRef = document.document.spriteRepository.assetRef(for: asset)
        }
        if let videoAssetName = blueprint.videoAssetName,
           let asset = document.document.spriteRepository.asset(byName: videoAssetName) {
            node.assetRef = document.document.spriteRepository.assetRef(for: asset)
        }

        switch blueprint.nodeType {
        case .shape:
            node.shapeSpec = ShapeNodeSpec(
                shapeType: blueprint.shapeType ?? .rect,
                fillColor: blueprint.fillColor ?? "#D6EAF8",
                strokeColor: blueprint.strokeColor ?? "#2E86C1",
                lineWidth: blueprint.lineWidth ?? 2,
                cornerRadius: blueprint.cornerRadius ?? 0
            )
        case .camera:
            node.cameraTarget = blueprint.cameraTarget
        case .tileMap:
            var tileSetRef: AssetRef?
            var tileSetColumns = 1
            if let tileSetAssetName = blueprint.tileSetAssetName,
               let asset = document.document.spriteRepository.asset(byName: tileSetAssetName) {
                tileSetRef = document.document.spriteRepository.assetRef(for: asset)
                tileSetColumns = max(asset.tileColumns, 1)
            }
            node.tileMapSpec = TileMapSpec(
                columns: blueprint.tileMapColumns ?? 12,
                rows: blueprint.tileMapRows ?? 8,
                tileWidth: blueprint.tileWidth ?? 32,
                tileHeight: blueprint.tileHeight ?? 32,
                tileSetAssetRef: tileSetRef,
                tileSetColumns: tileSetColumns,
                tileData: []
            )
        case .emitter:
            node.emitterSpec = EmitterSpec(
                particleColor: blueprint.particleColor ?? "#FFFFFF"
            )
        default:
            break
        }

        if blueprint.physicsEnabled {
            node.physicsBody = PhysicsBodySpec(
                bodyType: blueprint.physicsBodyType ?? defaultPhysicsBodyType(for: blueprint),
                isDynamic: blueprint.dynamic ?? true,
                restitution: blueprint.restitution ?? 0.1,
                friction: blueprint.friction ?? 0.4,
                affectedByGravity: blueprint.affectedByGravity ?? false,
                allowsRotation: blueprint.allowsRotation ?? false,
                linearDamping: blueprint.linearDamping,
                velocityX: blueprint.velocity?.dx,
                velocityY: blueprint.velocity?.dy
            )
        }

        return node
    }

    private func defaultPhysicsBodyType(for blueprint: SceneBlueprintNode) -> PhysicsBodyType {
        if blueprint.nodeType == .shape, blueprint.shapeType == .circle {
            return .circle
        }
        if let size = blueprint.size, abs(size.width - size.height) < 0.5 {
            return .circle
        }
        return .rect
    }

    @MainActor
    private func processStructuredScenePrompt(_ userMessage: String, intent: SpriteKitStructuredIntent) async -> Bool {
        let client = OllamaToolClient(host: ollamaHost, port: ollamaPort, model: ollamaModel)
        let assistant = SceneAuthoringAssistant(client: client)

        do {
            switch intent {
            case .create:
                let proposal = try await assistant.createProposal(
                    userRequest: userMessage,
                    document: document.document,
                    currentCardId: currentCardId ?? document.document.sortedCards.first?.id ?? UUID()
                )
                pendingSceneProposal = .create(proposal)
                appendMessage(role: "assistant", content: "Prepared a structured SpriteKit scene plan. Review it below before applying.")
                return true
            case .repair:
                guard let area = preferredRepairSpriteArea(from: userMessage) else { return false }
                let proposal = try await assistant.repairProposal(
                    userRequest: userMessage,
                    spriteAreaName: area.name,
                    scene: area.scene,
                    repository: document.document.spriteRepository
                )
                pendingSceneProposal = .repair(proposal)
                appendMessage(role: "assistant", content: "Prepared a structured scene repair plan. Review the issues and apply it if it looks right.")
                return true
            }
        } catch {
            // Include the selected model in the error so users know
            // whether to switch to a bigger model or simplify the
            // prompt. `OllamaError.structuredDecodeFailed` already
            // carries a short preview of what the model actually
            // said, but the model name itself comes from here.
            let localized = error.localizedDescription
            let hint: String
            if case OllamaError.structuredDecodeFailed = error {
                hint = "\n\nThe model \"\(ollamaModel)\" sent back a response that didn't match the scene schema. Try a larger model (e.g. qwen2.5:14b, llama3.1:70b) or simplify the request — the JSON fallback extractor already strips markdown fences, prose, and unknown enum values, so the issue is with the raw shape of the response."
            } else if case OllamaError.noStructuredContent = error {
                hint = "\n\nThe model \"\(ollamaModel)\" returned an empty response. Make sure Ollama is running and the model is loaded."
            } else if case OllamaError.requestTimedOut = error {
                // `OllamaError.requestTimedOut` already includes a
                // detailed actionable message; no need to append
                // more boilerplate.
                hint = ""
            } else if case OllamaError.requestFailed(let msg) = error {
                // A handful of Ollama models (Gemma family, older
                // fine-tunes) lack the tokenizer metadata needed for
                // grammar-constrained decoding. The server returns
                // that specific error BEFORE we even get a response,
                // so the auto-retry-without-format path in
                // OllamaToolClient.structuredChat already fires. If
                // the retry also fails we end up here with the
                // original message still in hand — surface it.
                let lower = msg.lowercased()
                if lower.contains("failed to load model vocabulary")
                    || lower.contains("vocabulary required for format") {
                    hint = "\n\nThe model \"\(ollamaModel)\" doesn't support server-side structured output on this Ollama build. Hype already retried without the `format` field and with the schema embedded as a prompt instruction, but that also failed. Try a model that supports structured output: `llama3.1`, `llama3.2`, `qwen2.5`, or `mistral`. Gemma models and some older fine-tunes often lack the required tokenizer metadata."
                } else {
                    hint = "\n\nCheck that Ollama is running at \(ollamaHost):\(ollamaPort) and the model \"\(ollamaModel)\" is installed (`ollama pull \(ollamaModel)`)."
                }
            } else {
                hint = ""
            }
            appendMessage(role: "assistant", content: "Structured scene planning failed: \(localized)\(hint)")
            return true
        }
    }

    private func preferredRepairSpriteArea(from userMessage: String) -> (name: String, scene: SceneSpec)? {
        let lower = userMessage.lowercased()
        let currentCard = currentCardId ?? document.document.sortedCards.first?.id
        let candidateParts: [Part]
        if let currentCard {
            let visible = document.document.effectivePartsForCard(currentCard)
            let currentAreas = visible.filter { $0.partType == .spriteArea }
            candidateParts = currentAreas.isEmpty
                ? document.document.parts.filter { $0.partType == .spriteArea }
                : currentAreas
        } else {
            candidateParts = document.document.parts.filter { $0.partType == .spriteArea }
        }
        if let named = candidateParts.first(where: { lower.contains($0.name.lowercased()) }),
           let scene = named.activeSceneSpec {
            return (named.name, scene)
        }
        if let byNode = candidateParts.first(where: {
            guard let scene = $0.activeSceneSpec else { return false }
            return scene.allNodes.contains(where: { !$0.name.isEmpty && lower.contains($0.name.lowercased()) })
        }), let scene = byNode.activeSceneSpec {
            return (byNode.name, scene)
        }
        if let first = candidateParts.first,
           let scene = first.activeSceneSpec {
            return (first.name, scene)
        }
        return nil
    }

    // MARK: - AI Processing

    @MainActor
    private func processWithTools(userMessage: String) async {
        let spriteKitRoute = SpriteKitRequestRouter.route(
            prompt: userMessage,
            document: document.document,
            currentCardId: currentCardId
        )

        if spriteKitRoute.isSpriteKitRequest && !spriteKitRoute.explicitScriptRequest {
            var updatedDocument = document.document
            if let directEdit = SpriteKitDirectSceneEdit.addBoundaryWallsIfRequested(
                prompt: userMessage,
                document: &updatedDocument,
                currentCardId: currentCardId ?? document.document.sortedCards.first?.id
            ) {
                lastStructuredUndoDocument = document.document
                document.document = updatedDocument
                appendMessage(
                    role: "assistant",
                    content: """
                    Added four static SpriteKit boundary wall nodes to \(directEdit.areaName) / \(directEdit.sceneName): \(directEdit.nodeNames.joined(separator: ", ")).
                    """
                )
                return
            }
        }

        if let intent = spriteKitRoute.structuredIntent,
           await processStructuredScenePrompt(userMessage, intent: intent) {
            return
        }

        // Reset the per-turn web-asset soft cap at the start of each processWithTools call.
        await webAssetSession.beginTurn()
        // Reset the per-turn capture budget counter. Session budget (consumed) is preserved.
        captureBudget.beginTurn()

        let client = OllamaToolClient(host: ollamaHost, port: ollamaPort, model: ollamaModel)

        // Build executor with web-asset dependencies when the stack has them enabled.
        let webAssetClient: (any WebAssetSearchClient)? = document.document.stack.webAssetsAllowed
            ? WebAssetSearchClientFactory.make(
                provider: WebAssetSearchProvider(rawValue: webAssetProviderRaw) ?? .openverse
              )
            : nil
        let webAssetPipeline: WebAssetImportPipeline? = document.document.stack.webAssetsAllowed
            ? WebAssetImportPipeline()
            : nil
        let executor = HypeToolExecutor(
            webAssetSession: document.document.stack.webAssetsAllowed ? webAssetSession : nil,
            webAssetClient: webAssetClient,
            webAssetPipeline: webAssetPipeline
        )

        // Get current stack context
        let cardId = currentCardId ?? document.document.sortedCards.first?.id ?? UUID()
        let currentCard = document.document.cards.first(where: { $0.id == cardId })
        let cardName = currentCard?.name ?? "Card 1"
        let bgName = currentCard.flatMap { document.document.backgroundForCard($0)?.name } ?? "unknown"
        let cardCount = document.document.cards.count

        // Card parts
        let currentParts = document.document.partsForCard(cardId)
            .map { "[\($0.partType.rawValue)] \"\($0.name)\" at (\(Int($0.left)),\(Int($0.top))) \(Int($0.width))x\(Int($0.height))" }
            .joined(separator: ", ")

        // Background parts
        let bgParts = currentCard.map { document.document.partsForBackground($0.backgroundId) } ?? []
        let bgPartsDesc = bgParts.map { "[\($0.partType.rawValue)] \"\($0.name)\"" }.joined(separator: ", ")

        // Sprite area summaries
        let spriteAreaParts = document.document.effectivePartsForCard(cardId).filter { $0.partType == .spriteArea }
        let spriteInfo = spriteAreaParts.compactMap { part -> String? in
            guard let areaSpec = part.spriteAreaSpecModel,
                  let spec = areaSpec.activeScene else { return nil }
            let nodes = spec.nodes.map { "\($0.nodeType.rawValue) \"\($0.name)\"" }.joined(separator: ", ")
            return "SpriteArea \"\(part.name)\" active scene \"\(spec.name)\" (\(areaSpec.scenes.count) scenes): [\(nodes.isEmpty ? "empty" : nodes)]"
        }.joined(separator: ". ")

        // Repository assets
        let repoAssets = document.document.spriteRepository.assets
            .map { "\($0.kind.rawValue) \"\($0.name)\"" }
            .joined(separator: ", ")

        let spriteKitPromptRules: String
        if spriteKitRoute.isSpriteKitRequest {
            if spriteKitRoute.explicitScriptRequest {
                spriteKitPromptRules = """
                - This request explicitly asks for HypeTalk on a SpriteKit area, scene, or node. Keep the script valid HypeTalk, but still think in SpriteKit terms: update velocity, physics, actions, contacts, or scene state. Do NOT simulate motion, bouncing, gravity, or bounds with `on idle` or `on frameUpdate` unless the user explicitly asks for manual frame-by-frame movement.
                """
            } else {
                spriteKitPromptRules = """
                - This request touches a SpriteKit area. Treat it as scene and node authoring first, not generic part scripting.
                - Use SpriteKit scene tools such as `get_scene_script`, `list_scene_nodes`, `set_scene_property`, `add_scene`, `set_active_scene`, and `apply_scene_diff`, and prefer nodes, physics bodies, actions, cameras, tile maps, and scene diagnostics over `set_part_property`.
                - Do NOT solve SpriteKit motion, bouncing, gravity, collisions, or staying inside bounds with `on idle` or `on frameUpdate` scripts.
                - If keyboard input is requested, use event handlers only to adjust velocity, forces, or actions on SpriteKit nodes.
                """
            }
        } else {
            spriteKitPromptRules = ""
        }

        // Build system prompt: authoring rules + (conditionally) the
        // canonical HypeTalk language guide + the current stack
        // state snapshot.
        //
        // The guide is normally silently injected on every request so
        // non-tuned base models have the full HypeTalk language surface
        // in context. For our HypeTalk-tuned model
        // (`hypetalk-gemma4:*`), the guide is ALREADY baked into the
        // Modelfile's SYSTEM block at package time — sending it again
        // here would duplicate ~6 k tokens of reference material in
        // every request, halve the usable context, and confuse the
        // model because its training data had a minimal system prompt
        // rather than the full guide. We detect the tuned model by tag
        // prefix and skip the injection when present.
        let isTunedHypeTalkModel = ollamaModel.lowercased().hasPrefix("hypetalk-")
        // Inline the guide as literal text only for untrained models.
        // The tuned model already has the guide in its Modelfile SYSTEM
        // block (see scripts/ai-training/src/package.sh) so adding it
        // here would double the token footprint and risk confusing
        // the model since its training data had only a minimal system
        // prompt.
        let hypeTalkGuideBlock = isTunedHypeTalkModel ? "" : HypeTalkGuide.llmContext
        let guideReferenceWord = isTunedHypeTalkModel ? "you were trained on" : "below"
        // The runtime system prompt is intentionally slim for the
        // tuned hypetalk-* model: the rules the model has already
        // learned from training (HypeTalk syntax, tool calling
        // conventions, SpriteKit routing) are omitted, leaving only
        // inference-time variables and the tool-use priorities that
        // can't be baked into weights because they depend on the
        // catalog at runtime. Non-tuned models still see the full
        // HypeTalkGuide.llmContext via \(hypeTalkGuideBlock).
        let systemPrompt: String
        if isTunedHypeTalkModel {
            systemPrompt = """
                You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is \(document.document.stack.width)x\(document.document.stack.height) points.

                TOOL-USE PRIORITIES:
                - To READ a property: prefer get_part_property / get_node_property / get_stack_property / get_card_property / get_background_property / get_scene_script / list_scene_nodes / list_all_cards / get_card_parts over get_scene_spec (which is 10k+ tokens).
                - To MODIFY one property: prefer set_part_property / set_node_property / set_scene_property / set_stack_property / set_card_property / set_background_property / set_physics_body / set_card_script / set_background_script / set_stack_script over apply_scene_diff.
                - To CREATE a single node: prefer add_sprite_to_scene / add_label_to_scene / add_shape_to_scene / add_emitter_to_scene / add_joint_to_scene over apply_scene_diff.
                - Use apply_scene_diff ONLY for multi-node batch edits.
                - For data-entry forms, input forms, customer/contact/login forms, headers, labels, and text fields: use ordinary card/background controls. Use create_label for labels/headers and create_field(style=rectangle, stroke_color=#000000, stroke_width=1) for user input fields. Do NOT create a Sprite Area or scene labels unless the user explicitly asks for SpriteKit, sprites, physics, a game, or a scene.
                - When the user says "background", set on_background to "true" in create tools.
                - If the user asks to create, set, attach, install, replace, or update a script on the stack, card, background, button, field, sprite area, scene, or node, use the appropriate setter tool. Do not answer with bare HypeTalk unless the user explicitly asks only to write or explain code.
                - Before storing any HypeTalk script with create_button, create_field, set_part_property(property=script), set_node_script, set_scene_script, set_card_script, set_background_script, or set_stack_script, call check_script first and only store the script after it returns OK. If a storage tool returns a result starting with `__HYPE_INTERNAL_DRAFT_REFUSED_v1:`, the host has rejected your script. Read the failure list, fix the script, and call the SAME storage tool again with the corrected script — the host iterates with you automatically.
                - For button scripts, just provide the HypeTalk command (e.g. "go next"). It will be auto-wrapped in on mouseUp/end mouseUp.\(spriteKitPromptRules.isEmpty ? "" : "\n" + spriteKitPromptRules)

                CURRENT STATE:
                Stack: "\(document.document.stack.name)" (\(cardCount) cards)
                Current card: "\(cardName)" | Background: "\(bgName)"
                Card parts: \(currentParts.isEmpty ? "none" : currentParts)
                Background parts: \(bgPartsDesc.isEmpty ? "none" : bgPartsDesc)
                \(spriteInfo.isEmpty ? "" : "Sprites: \(spriteInfo)")
                \(repoAssets.isEmpty ? "" : "Repository assets: \(repoAssets)")
                """
        } else {
            // Untuned models still get the full rules + guide block so
            // they behave as before. These models have not internalised
            // HypeTalk syntax or tool conventions, so the guide is load-
            // bearing.
            systemPrompt = """
                You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is \(document.document.stack.width)x\(document.document.stack.height) points.

                RULES:
                - Call the needed tools to fulfill the user's request, then STOP and respond with a brief summary.
                - Do NOT repeat tool calls you have already made.
                - Do NOT delete parts unless the user specifically asks you to.
                - Stay inside Hype stack-authoring tools. Do not assume filesystem or arbitrary web access is available.
                - Create well-spaced, visually appealing layouts.
                - Use descriptive names for all parts.
                - For data-entry forms, input forms, customer/contact/login forms, headers, labels, and text fields: use ordinary card/background controls. Use create_label for labels/headers and create_field(style=rectangle, stroke_color=#000000, stroke_width=1) for user input fields. Do NOT create a Sprite Area or scene labels unless the user explicitly asks for SpriteKit, sprites, physics, a game, or a scene.
                - For SpriteKit requests involving bouncing, gravity, collisions, or objects staying inside a sprite area, prefer native scene nodes, physics bodies, restitution, and velocity. Do NOT solve those with `on idle` or `on frameUpdate` scripts unless the user explicitly asks for custom scripting.
                \(spriteKitPromptRules)
                - When the user says "background", set on_background to "true" in create tools.
                  Background parts are shared across ALL cards that use that background.
                - To READ one property on the stack, card, or background, prefer get_stack_property / get_card_property / get_background_property over broad summaries.
                - To MODIFY one property on the stack, card, or background, prefer set_stack_property / set_card_property / set_background_property over unrelated part tools.
                - If the user asks to create, set, attach, install, replace, or update a script on the stack, card, background, button, field, sprite area, scene, or node, use the appropriate setter tool. Do not answer with bare HypeTalk unless the user explicitly asks only to write or explain code.
                - Before storing any HypeTalk script with create_button, create_field, set_part_property(property=script), set_node_script, set_scene_script, set_card_script, set_background_script, or set_stack_script, call check_script first and only store the script after it returns OK. If a storage tool returns a result starting with `__HYPE_INTERNAL_DRAFT_REFUSED_v1:`, the host has rejected your script. Read the failure list, fix the script, and call the SAME storage tool again with the corrected script — the host iterates with you automatically.
                - For button scripts, just provide the HypeTalk command (e.g. "go next"). It will be auto-wrapped in on mouseUp/end mouseUp.
                - When writing HypeTalk scripts, use ONLY valid HypeTalk syntax as described in the guide \(guideReferenceWord).

                \(hypeTalkGuideBlock)

                CURRENT STATE:
                Stack: "\(document.document.stack.name)" (\(cardCount) cards)
                Current card: "\(cardName)" | Background: "\(bgName)"
                Card parts: \(currentParts.isEmpty ? "none" : currentParts)
                Background parts: \(bgPartsDesc.isEmpty ? "none" : bgPartsDesc)
                \(spriteInfo.isEmpty ? "" : "Sprites: \(spriteInfo)")
                \(repoAssets.isEmpty ? "" : "Repository assets: \(repoAssets)")
                """
        }

        // Build message list: system + conversation history + new user message
        // If this is the first message, start fresh. Otherwise, carry forward.
        if conversationMessages.isEmpty {
            conversationMessages = [
                OllamaMessage(role: "system", content: systemPrompt)
            ]
        } else {
            // Update system prompt with latest state
            if !conversationMessages.isEmpty && conversationMessages[0].role == "system" {
                conversationMessages[0] = OllamaMessage(role: "system", content: systemPrompt)
            }
        }

        // Add user message to conversation
        conversationMessages.append(OllamaMessage(role: "user", content: userMessage))

        // Trim the conversation to the configured 128k-token prompt
        // budget (see AIPromptBudget in HypeCore). The trim preserves
        // the system prompt at index 0 and the message we just
        // appended, and drops older middle messages as needed.
        conversationMessages = AIPromptBudget.trimToFit(conversationMessages)

        // Track the "active" card ID — updates when AI creates a new card
        var activeCardId = cardId

        // Tool-use loop (max 5 rounds)
        var rounds = 0
        while rounds < 5 {
            rounds += 1

            // Re-trim before every chat call. A single very large tool
            // result (e.g. a full scene-spec dump or a directory
            // listing) can balloon `conversationMessages` inside the
            // loop; trimming here ensures we never exceed the prompt
            // budget on the next request even if a prior round added
            // a lot of bytes.
            conversationMessages = AIPromptBudget.trimToFit(conversationMessages)

            do {
                let baseTools = spriteKitRoute.isSpriteKitRequest
                    ? HypeToolDefinitions.spriteSceneAuthoringTools
                    : HypeToolDefinitions.cardControlAuthoringTools
                let tools = HypeToolDefinitions.withWebAssetTools(
                    baseTools,
                    enabled: document.document.stack.webAssetsAllowed
                )
                let response = try await client.chat(
                    messages: conversationMessages,
                    tools: tools
                )

                // Ollama's gemma4 parser extracts structured tool_calls
                // from a narrow set of output shapes. Our fine-tuned
                // HypeTalk model emits tool calls in slightly-off shapes
                // the parser misses — specifically tool_code code fences
                // containing JSON or python-style function call syntax.
                // Salvage those at the Hype layer so the fine-tuned
                // model's tool-use works end-to-end regardless of
                // Ollama's parse result. Structured tool calls still
                // get a narrow document-aware repair pass for known
                // local-model misroutes (e.g. Sprite Area scene script
                // stored as a generic part script).
                let effectiveToolCalls: [OllamaToolCall]? = {
                    if let existing = HypeAIResponseRepair.repairedToolCalls(
                        response.message.tool_calls,
                        userMessage: userMessage,
                        document: document.document,
                        currentCardId: activeCardId
                    ),
                       !existing.isEmpty {
                        return existing
                    }
                    return HypeAIResponseRepair.extractToolCalls(from: response.message.content)
                }()

                if let toolCalls = effectiveToolCalls, !toolCalls.isEmpty {
                    conversationMessages.append(response.message)

                    // Per-loop accumulator for the synthetic user message carrying the capture image.
                    // SECURITY FINDING 2: defer injection until AFTER the loop so we never interleave
                    // a `user` message between assistant tool_calls and tool results.
                    var pendingCapture: CardCaptureResult? = nil

                    toolCallLoop: for call in toolCalls {
                        let argsDesc = call.function.arguments
                            .map { "\($0.key): \($0.value)" }
                            .joined(separator: ", ")
                        let toolMsg = "Tool: \(call.function.name)(\(argsDesc))"
                        appendMessage(role: "tool", content: toolMsg)

                        // MARK: - capture_card_image pre-flight
                        // Handle separately: enforce budget, inject remaining hint, redact log output.
                        if call.function.name == "capture_card_image" {
                            if !captureBudget.tryConsume() {
                                let reason = captureBudget.exhaustedReason()
                                appendMessage(role: "tool", content: "Tool: capture_card_image (refused: \(reason))")
                                conversationMessages.append(OllamaMessage(role: "tool", content: reason))
                                continue
                            }
                            let displayName = call.function.arguments["card_name"] ?? ""
                            captureStatus = CaptureStatus(cardName: displayName)

                            // Inject the host-computed remaining hint as a private argument.
                            var augmented = call.function.arguments
                            augmented["__captures_remaining_hint"] = String(captureBudget.remaining)

                            var doc = document.document
                            let result = await executor.execute(
                                toolName: call.function.name,
                                arguments: augmented,
                                document: &doc,
                                currentCardId: activeCardId
                            )
                            document.document = doc
                            captureStatus = nil

                            // SECURITY FINDING 1: redact base64 from logger — never write image bytes to disk log.
                            let captureOutcome = captureCoordinator.classify(toolResult: result)
                            switch captureOutcome {
                            case .captured(let captured):
                                let redacted = captureCoordinator.makeRedactedLogString(for: captured)
                                HypeLogger.shared.aiDialog(role: "tool_result", content: redacted, source: "AI Tool")
                                // Surface a thumbnail bubble in the chat.
                                let caption = "\(captured.cardName.isEmpty ? "current card" : "card '\(captured.cardName)'")"
                                    + " · \(captured.pixelWidth)×\(captured.pixelHeight)"
                                    + " · captures remaining: \(captureBudget.remaining)"
                                appendMessage(
                                    role: "tool",
                                    content: captured.compactDisplaySummary,
                                    imageBase64: captured.imageBase64,
                                    imagePixelWidth: captured.pixelWidth,
                                    imagePixelHeight: captured.pixelHeight,
                                    imageCaption: caption
                                )
                                // Append acknowledgment to the model conversation.
                                conversationMessages.append(
                                    captureCoordinator.makeAcknowledgmentMessage(for: captured, remaining: captureBudget.remaining)
                                )
                                // Defer the synthetic user message — record for post-loop injection.
                                pendingCapture = captured

                            case .decodeFailed(let raw):
                                // Budget was consumed at pre-flight (tryConsume above)
                                // but no image was actually delivered. Refund the slot
                                // so a flaky encoder doesn't silently drain the
                                // per-session budget. See CardCaptureBudget.refundOne()
                                // for the full rationale.
                                captureBudget.refundOne()
                                HypeLogger.shared.warn("Capture sentinel decode failed: \(raw.prefix(200))", source: "AI Tool")
                                appendMessage(role: "tool", content: "Capture failed: internal error reading host capture response.")
                                conversationMessages.append(OllamaMessage(role: "tool", content: "Capture failed; proceed without an image."))

                            case .notACapture:
                                // Result is a plain error string (e.g. "Card 'X' not found").
                                HypeLogger.shared.aiDialog(role: "tool_result", content: result, source: "AI Tool")
                                appendMessage(role: "tool", content: result)
                                conversationMessages.append(OllamaMessage(role: "tool", content: result))
                            }
                            continue
                        }

                        // Show searching indicator for web-asset tools.
                        let isWebAssetTool = ["search_web_for_sprite", "import_web_asset", "find_and_import_sprite"]
                            .contains(call.function.name)
                        if isWebAssetTool { isSearchingWeb = true }

                        var doc = document.document
                        let result = await executor.execute(
                            toolName: call.function.name,
                            arguments: call.function.arguments,
                            document: &doc,
                            currentCardId: activeCardId
                        )
                        document.document = doc
                        HypeLogger.shared.aiDialog(role: "tool_result", content: result, source: "AI Tool")

                        if isWebAssetTool { isSearchingWeb = false }

                        // Host-side script gate: check BEFORE CREATED_CARD:/NAVIGATE: prefixes.
                        let gateOutcome = scriptDraftCoordinator.classify(toolResult: result)
                        switch gateOutcome {
                        case .refused(let refusal):
                            iterationStatus = IterationStatus(
                                attemptNumber: 1,
                                maxAttempts: scriptDraftCoordinator.configuration.maxAttempts,
                                toolName: refusal.toolName,
                                targetDescription: refusal.targetDescription
                            )
                            appendMessage(role: "tool", content: refusal.compactDisplaySummary)
                            let loopResult = await iterateScriptDraft(
                                initialRefusal: refusal,
                                executor: executor,
                                client: client,
                                tools: tools,
                                activeCardId: activeCardId
                            )
                            iterationStatus = nil
                            appendMessage(role: "assistant", content: loopResult.finalToolResultString)
                            conversationMessages.append(OllamaMessage(role: "tool", content: loopResult.finalToolResultString))
                            continue

                        case .decodeFailed(let raw):
                            // A sentinel-prefix-but-bad-JSON result indicates the
                            // host gate corrupted its handoff. We can't trust
                            // anything else from this batch — subsequent tool
                            // results may also be confused — so abort the entire
                            // tool-call iteration for this round (break, NOT
                            // continue) and surface a generic error to the user.
                            HypeLogger.shared.warn(
                                "Script gate sentinel decode failed: \(raw.prefix(200))",
                                source: "AI Tool"
                            )
                            iterationStatus = nil
                            appendMessage(role: "assistant", content: "Script rejected — internal error reading host gate response. Please try again.")
                            break toolCallLoop

                        case .passed, .other:
                            // Fall through to the normal CREATED_CARD:/NAVIGATE: handling below.
                            break
                        }

                        if result.hasPrefix("CREATED_CARD:") {
                            let newIdStr = String(result.dropFirst(13))
                            if let newId = UUID(uuidString: newIdStr) {
                                activeCardId = newId
                                currentCardId = newId
                            }
                            let toolResult = OllamaMessage(role: "tool", content: "Created new card. Now working on the new card.")
                            conversationMessages.append(toolResult)
                            continue
                        }

                        if result.hasPrefix("NAVIGATE:") {
                            let dest = String(result.dropFirst(9))
                            let doc = document.document
                            if let targetCard = doc.cards.first(where: { $0.name.lowercased() == dest.lowercased() }) {
                                activeCardId = targetCard.id
                                currentCardId = targetCard.id
                            } else if let num = Int(dest), num > 0, num <= doc.sortedCards.count {
                                let card = doc.sortedCards[num - 1]
                                activeCardId = card.id
                                currentCardId = card.id
                            } else {
                                let direction: NavigationDirection?
                                switch dest.lowercased() {
                                case "next": direction = .next
                                case "previous", "prev": direction = .previous
                                case "first": direction = .first
                                case "last": direction = .last
                                default: direction = nil
                                }
                                if let dir = direction,
                                   let newId = CardNavigator.navigate(direction: dir, currentCardId: activeCardId, document: doc) {
                                    activeCardId = newId
                                    currentCardId = newId
                                }
                            }
                            let toolResult = OllamaMessage(role: "tool", content: "Navigated to card \(dest).")
                            conversationMessages.append(toolResult)
                            continue
                        }

                        let toolResult = OllamaMessage(role: "tool", content: result)
                        conversationMessages.append(toolResult)
                    }

                    // Post-loop: inject the synthetic user message for any captured image.
                    // Deferred to maintain Ollama's expected message ordering:
                    // assistant(tool_calls) → tool → tool → … → user(image) → next assistant.
                    if let captured = pendingCapture {
                        conversationMessages.append(captureCoordinator.makeSyntheticUserMessage(for: captured))
                    }

                    continue
                }

                // No tool calls. Some tuned local models return a
                // HypeTalk script as plain text even though the user
                // explicitly asked to attach it. If the target can be
                // resolved from the current stack, synthesize the
                // corresponding setter tool call and let the normal
                // executor validate/store it.
                if let repairedCall = HypeAIResponseRepair.scriptAttachmentToolCall(
                    userMessage: userMessage,
                    modelContent: response.message.content,
                    document: document.document,
                    currentCardId: activeCardId
                ) {
                    conversationMessages.append(response.message)

                    let argsDesc = repairedCall.function.arguments
                        .map { "\($0.key): \($0.value)" }
                        .joined(separator: ", ")
                    appendMessage(role: "tool", content: "Tool: \(repairedCall.function.name)(\(argsDesc))")

                    var doc = document.document
                    let result = await executor.execute(
                        toolName: repairedCall.function.name,
                        arguments: repairedCall.function.arguments,
                        document: &doc,
                        currentCardId: activeCardId
                    )
                    document.document = doc
                    HypeLogger.shared.warn(
                        "Repaired unstructured model output into tool call \(repairedCall.function.name)",
                        source: "AI Tool"
                    )
                    HypeLogger.shared.aiDialog(role: "tool_result", content: result, source: "AI Tool")

                    // Route the repair-path result through the same script gate
                    // as the structured tool-call path. Otherwise a model that
                    // emits unstructured output can bypass iteration entirely
                    // (the raw `__HYPE_INTERNAL_DRAFT_REFUSED_v1:` sentinel
                    // would land in the chat as a "tool" bubble of JSON, and
                    // the host wouldn't loop the model for a fix). See
                    // ScriptDraftCoordinator + iterateScriptDraft above.
                    let repairOutcome = scriptDraftCoordinator.classify(toolResult: result)
                    switch repairOutcome {
                    case .refused(let refusal):
                        iterationStatus = IterationStatus(
                            attemptNumber: 1,
                            maxAttempts: scriptDraftCoordinator.configuration.maxAttempts,
                            toolName: refusal.toolName,
                            targetDescription: refusal.targetDescription
                        )
                        appendMessage(role: "tool", content: refusal.compactDisplaySummary)
                        let loopResult = await iterateScriptDraft(
                            initialRefusal: refusal,
                            executor: executor,
                            client: client,
                            tools: tools,
                            activeCardId: activeCardId
                        )
                        iterationStatus = nil
                        appendMessage(role: "assistant", content: loopResult.finalToolResultString)
                        conversationMessages.append(OllamaMessage(role: "tool", content: loopResult.finalToolResultString))
                    case .decodeFailed(let raw):
                        HypeLogger.shared.warn(
                            "Script gate sentinel decode failed (repair path): \(raw.prefix(200))",
                            source: "AI Tool"
                        )
                        iterationStatus = nil
                        appendMessage(role: "assistant", content: "Script rejected — internal error reading host gate response. Please try again.")
                    case .passed, .other:
                        conversationMessages.append(OllamaMessage(role: "tool", content: result))
                        appendMessage(role: "assistant", content: result)
                    }
                    break
                }

                // No tool calls and no safe repair — model is done.
                let text = response.message.content ?? "(no response)"
                appendMessage(role: "assistant", content: text)
                conversationMessages.append(OllamaMessage(role: "assistant", content: text))
                break

            } catch {
                appendMessage(role: "assistant", content: "Error: \(error.localizedDescription)")
                break
            }
        }
    }

    // MARK: - Script draft iteration loop

    /// Iterate a refused script draft with the model until it passes or the attempt
    /// budget is exhausted.
    ///
    /// This method is the inner engine of the host-side script validation gate. It:
    /// 1. Appends a retry envelope (structured DRAFT_REFUSED message) to the conversation.
    /// 2. Calls the model for each subsequent attempt.
    /// 3. Dispatches `check_script` cycles without consuming the attempt counter.
    /// 4. Exits when the script passes, the budget is exhausted, or the model gives up.
    ///
    /// - Parameters:
    ///   - initialRefusal: The refusal produced by attempt #1 (the one that triggered iteration).
    ///   - executor: The tool executor already configured for this turn.
    ///   - client: The Ollama client already configured for this turn.
    ///   - tools: The tool list used in this turn.
    ///   - activeCardId: The current card UUID (read-only snapshot from the parent loop).
    /// - Returns: A `LoopResult` describing the final state of the iteration.
    @MainActor
    private func iterateScriptDraft(
        initialRefusal: ScriptDraftRefusal,
        executor: HypeToolExecutor,
        client: OllamaToolClient,
        tools: [OllamaTool],
        activeCardId: UUID
    ) async -> ScriptDraftCoordinator.LoopResult {
        let cfg = scriptDraftCoordinator.configuration
        var lastRefusal = initialRefusal

        // Append the first retry envelope as a tool result the model will read.
        let firstEnvelope = scriptDraftCoordinator.makeRetryEnvelope(
            for: lastRefusal,
            attemptNumber: 1,
            maxAttempts: cfg.maxAttempts
        )
        conversationMessages.append(firstEnvelope)

        // Attempt loop starts at 2 because attempt 1 is the one that produced `initialRefusal`.
        for attempt in 2...cfg.maxAttempts {
            iterationStatus?.attemptNumber = attempt
            conversationMessages = AIPromptBudget.trimToFit(conversationMessages)

            let response: OllamaChatResponse
            do {
                response = try await client.chat(messages: conversationMessages, tools: tools)
            } catch {
                let errorMsg = "Error during script iteration: \(error.localizedDescription)"
                return ScriptDraftCoordinator.LoopResult(
                    finalAttempts: attempt,
                    didPass: false,
                    lastDraftRawScript: lastRefusal.rawScript,
                    lastFailures: lastRefusal.failures,
                    finalToolResultString: errorMsg
                )
            }

            // Normalise tool calls the same way the parent loop does.
            let effectiveToolCalls: [OllamaToolCall]? = {
                if let existing = response.message.tool_calls, !existing.isEmpty { return existing }
                return HypeAIResponseRepair.extractToolCalls(from: response.message.content)
            }()

            guard let toolCalls = effectiveToolCalls, !toolCalls.isEmpty else {
                // Model gave up or produced a plain text response.
                let text = response.message.content ?? "(no response)"
                return ScriptDraftCoordinator.LoopResult(
                    finalAttempts: attempt,
                    didPass: false,
                    lastDraftRawScript: lastRefusal.rawScript,
                    lastFailures: lastRefusal.failures,
                    finalToolResultString: text
                )
            }

            conversationMessages.append(response.message)

            for call in toolCalls {
                if call.function.name == "check_script" {
                    // Self-validation cycle — dispatch, append result, but DON'T count as an attempt.
                    var doc = document.document
                    let checkResult = await executor.execute(
                        toolName: call.function.name,
                        arguments: call.function.arguments,
                        document: &doc,
                        currentCardId: activeCardId
                    )
                    document.document = doc
                    HypeLogger.shared.aiDialog(role: "tool_result", content: checkResult, source: "AI Tool")
                    conversationMessages.append(OllamaMessage(role: "tool", content: checkResult))
                    continue
                }

                if call.function.name == "capture_card_image" {
                    // Capture is not supported during the script iteration loop —
                    // the model should fix the script first, then capture afterwards if needed.
                    let msg = "Capture is not available during script iteration. Fix the script first, then capture afterwards if needed."
                    conversationMessages.append(OllamaMessage(role: "tool", content: msg))
                    continue
                }

                if call.function.name == lastRefusal.toolName {
                    // The model is retrying the refused tool — dispatch and classify.
                    var doc = document.document
                    let result = await executor.execute(
                        toolName: call.function.name,
                        arguments: call.function.arguments,
                        document: &doc,
                        currentCardId: activeCardId
                    )
                    document.document = doc
                    HypeLogger.shared.aiDialog(role: "tool_result", content: result, source: "AI Tool")

                    let outcome = scriptDraftCoordinator.classify(toolResult: result)
                    switch outcome {
                    case .passed(let committed):
                        return ScriptDraftCoordinator.LoopResult(
                            finalAttempts: attempt,
                            didPass: true,
                            lastDraftRawScript: nil,
                            lastFailures: [],
                            finalToolResultString: committed
                        )

                    case .refused(let newRefusal):
                        lastRefusal = newRefusal
                        let envelope = scriptDraftCoordinator.makeRetryEnvelope(
                            for: newRefusal,
                            attemptNumber: attempt,
                            maxAttempts: cfg.maxAttempts
                        )
                        conversationMessages.append(envelope)
                        // Continue outer attempt loop.

                    case .decodeFailed(let raw):
                        HypeLogger.shared.warn(
                            "Script gate sentinel decode failed during iteration: \(raw.prefix(200))",
                            source: "AI Tool"
                        )
                        return ScriptDraftCoordinator.LoopResult(
                            finalAttempts: attempt,
                            didPass: false,
                            lastDraftRawScript: lastRefusal.rawScript,
                            lastFailures: lastRefusal.failures,
                            finalToolResultString: "Script rejected — internal error reading host gate response. Please try again."
                        )

                    case .other(let str):
                        // A different kind of error from the executor — stop iterating.
                        return ScriptDraftCoordinator.LoopResult(
                            finalAttempts: attempt,
                            didPass: false,
                            lastDraftRawScript: lastRefusal.rawScript,
                            lastFailures: lastRefusal.failures,
                            finalToolResultString: str
                        )
                    }
                } else {
                    // Model chose a different tool entirely — dispatch and exit iteration.
                    var doc = document.document
                    let result = await executor.execute(
                        toolName: call.function.name,
                        arguments: call.function.arguments,
                        document: &doc,
                        currentCardId: activeCardId
                    )
                    document.document = doc
                    HypeLogger.shared.aiDialog(role: "tool_result", content: result, source: "AI Tool")
                    return ScriptDraftCoordinator.LoopResult(
                        finalAttempts: attempt - 1,
                        didPass: false,
                        lastDraftRawScript: lastRefusal.rawScript,
                        lastFailures: lastRefusal.failures,
                        finalToolResultString: result
                    )
                }
            }
        }

        // Budget exhausted.
        return ScriptDraftCoordinator.LoopResult(
            finalAttempts: cfg.maxAttempts,
            didPass: false,
            lastDraftRawScript: lastRefusal.rawScript,
            lastFailures: lastRefusal.failures,
            finalToolResultString: scriptDraftCoordinator.makeAbandonedDraftMessage(
                lastRefusal,
                maxAttempts: cfg.maxAttempts
            )
        )
    }

}

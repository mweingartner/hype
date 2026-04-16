import SwiftUI
import HypeCore

struct AIChatPanel: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @State private var inputText = ""
    @State private var messages: [(role: String, content: String)] = []
    @State private var conversationMessages: [OllamaMessage] = []  // Full context for model
    @State private var isProcessing = false
    @State private var historyIndex: Int = -1
    @State private var pendingSceneProposal: PendingSceneProposal?
    @State private var lastStructuredUndoDocument: HypeDocument?
    @FocusState private var isInputFocused: Bool

    @AppStorage("ollamaHost") private var ollamaHost = "localhost"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"

    private let executor = HypeToolExecutor()

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
            .background(Color(NSColor.controlBackgroundColor))

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
                                }
                                if msg.role != "user" { Spacer() }
                            }
                            .id(idx)
                        }
                        if isProcessing {
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

            // Input area — dynamic height TextEditor
            HStack(alignment: .bottom, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    // Placeholder
                    if inputText.isEmpty {
                        Text("Ask AI to build something...")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .focused($isInputFocused)
                        .disabled(isProcessing)
                        .onKeyPress(.upArrow) { recallHistory(direction: .up); return .handled }
                        .onKeyPress(.downArrow) { recallHistory(direction: .down); return .handled }
                        .onChange(of: inputText) { oldVal, newVal in
                            // Detect Enter key (newline inserted) — send on plain Enter
                            if newVal.hasSuffix("\n") && !NSEvent.modifierFlags.contains(.shift) {
                                inputText = String(newVal.dropLast()) // remove the newline
                                sendMessage()
                            }
                        }
                }
                .frame(minHeight: 32, maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                .padding(.bottom, 6)
            }
            .padding(8)
            .onAppear { isInputFocused = true }
        }
        .frame(width: 350)
    }

    // MARK: - History

    private enum HistoryDirection { case up, down }

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
    }

    // MARK: - Bubble Color

    private func bubbleColor(for role: String) -> Color {
        switch role {
        case "user": return Color.accentColor.opacity(0.2)
        case "tool": return Color.green.opacity(0.1)
        default: return Color(NSColor.controlBackgroundColor)
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
        .background(Color(NSColor.controlBackgroundColor))
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

        messages.append((role: "user", content: text))
        inputText = ""
        isProcessing = true

        Task {
            await processWithTools(userMessage: text)
            isProcessing = false
            isInputFocused = true
        }
    }

    private func applyPendingSceneProposal() {
        guard let pendingSceneProposal else { return }
        lastStructuredUndoDocument = document.document

        switch pendingSceneProposal {
        case .create(let proposal):
            applyCreateProposal(proposal)
            messages.append((role: "assistant", content: "Applied scene plan to \(proposal.areaName) / \(proposal.sceneName)."))
        case .repair(let proposal):
            applyRepairProposal(proposal)
            messages.append((role: "assistant", content: "Applied scene repair to \(proposal.areaName)."))
        }

        self.pendingSceneProposal = nil
    }

    private func undoStructuredSceneApply() {
        guard let snapshot = lastStructuredUndoDocument else { return }
        document.document = snapshot
        lastStructuredUndoDocument = nil
        messages.append((role: "assistant", content: "Undid the last structured scene change."))
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
    }

    private func applyRepairProposal(_ proposal: SceneRepairProposal) {
        guard let index = document.document.parts.firstIndex(where: {
            $0.partType == .spriteArea && $0.name.lowercased() == proposal.areaName.lowercased()
        }) else {
            messages.append((role: "assistant", content: "Could not find sprite area '\(proposal.areaName)' to repair."))
            return
        }
        document.document.updatePart(id: document.document.parts[index].id) { part in
            part.updateActiveSceneSpec { scene in
                proposal.diff.apply(to: &scene)
            }
        }
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
                messages.append((role: "assistant", content: "Prepared a structured SpriteKit scene plan. Review it below before applying."))
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
                messages.append((role: "assistant", content: "Prepared a structured scene repair plan. Review the issues and apply it if it looks right."))
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
            } else if case OllamaError.requestFailed = error {
                hint = "\n\nCheck that Ollama is running at \(ollamaHost):\(ollamaPort) and the model \"\(ollamaModel)\" is installed (`ollama pull \(ollamaModel)`)."
            } else {
                hint = ""
            }
            messages.append((role: "assistant", content: "Structured scene planning failed: \(localized)\(hint)"))
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

        if let intent = spriteKitRoute.structuredIntent,
           await processStructuredScenePrompt(userMessage, intent: intent) {
            return
        }

        let client = OllamaToolClient(host: ollamaHost, port: ollamaPort, model: ollamaModel)

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
                - Use SpriteKit scene tools such as `get_scene_spec` and `apply_scene_diff`, and prefer nodes, physics bodies, actions, cameras, tile maps, and scene diagnostics over `set_part_property`.
                - Do NOT solve SpriteKit motion, bouncing, gravity, collisions, or staying inside bounds with `on idle` or `on frameUpdate` scripts.
                - If keyboard input is requested, use event handlers only to adjust velocity, forces, or actions on SpriteKit nodes.
                """
            }
        } else {
            spriteKitPromptRules = ""
        }

        // Build system prompt: authoring rules + the canonical HypeTalk
        // language guide (silently injected on every request so the model
        // always has the language surface in context) + the current stack
        // state snapshot.
        let systemPrompt = """
            You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is \(document.document.stack.width)x\(document.document.stack.height) points.

            RULES:
            - Call the needed tools to fulfill the user's request, then STOP and respond with a brief summary.
            - Do NOT repeat tool calls you have already made.
            - Do NOT delete parts unless the user specifically asks you to.
            - Stay inside Hype stack-authoring tools. Do not assume filesystem or arbitrary web access is available.
            - Create well-spaced, visually appealing layouts.
            - Use descriptive names for all parts.
            - For SpriteKit requests involving bouncing, gravity, collisions, or objects staying inside a sprite area, prefer native scene nodes, physics bodies, restitution, and velocity. Do NOT solve those with `on idle` or `on frameUpdate` scripts unless the user explicitly asks for custom scripting.
            \(spriteKitPromptRules)
            - When the user says "background", set on_background to "true" in create tools.
              Background parts are shared across ALL cards that use that background.
            - For button scripts, just provide the HypeTalk command (e.g. "go next"). It will be auto-wrapped in on mouseUp/end mouseUp.
            - When writing HypeTalk scripts, use ONLY valid HypeTalk syntax as described in the guide below.

            \(HypeTalkGuide.llmContext)

            CURRENT STATE:
            Stack: "\(document.document.stack.name)" (\(cardCount) cards)
            Current card: "\(cardName)" | Background: "\(bgName)"
            Card parts: \(currentParts.isEmpty ? "none" : currentParts)
            Background parts: \(bgPartsDesc.isEmpty ? "none" : bgPartsDesc)
            \(spriteInfo.isEmpty ? "" : "Sprites: \(spriteInfo)")
            \(repoAssets.isEmpty ? "" : "Repository assets: \(repoAssets)")
            """

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
                let response = try await client.chat(
                    messages: conversationMessages,
                    tools: spriteKitRoute.prefersSceneTooling
                        ? HypeToolDefinitions.spriteSceneAuthoringTools
                        : HypeToolDefinitions.authoringTools
                )

                if let toolCalls = response.message.tool_calls, !toolCalls.isEmpty {
                    conversationMessages.append(response.message)

                    for call in toolCalls {
                        let argsDesc = call.function.arguments
                            .map { "\($0.key): \($0.value)" }
                            .joined(separator: ", ")
                        let toolMsg = "Tool: \(call.function.name)(\(argsDesc))"
                        messages.append((role: "tool", content: toolMsg))

                        var doc = document.document
                        let result = await executor.execute(
                            toolName: call.function.name,
                            arguments: call.function.arguments,
                            document: &doc,
                            currentCardId: activeCardId
                        )
                        document.document = doc

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
                    continue
                }

                // No tool calls — model is done
                let text = response.message.content ?? "(no response)"
                messages.append((role: "assistant", content: text))
                conversationMessages.append(OllamaMessage(role: "assistant", content: text))
                break

            } catch {
                messages.append((role: "assistant", content: "Error: \(error.localizedDescription)"))
                break
            }
        }
    }
}

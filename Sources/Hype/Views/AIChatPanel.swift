import SwiftUI
import HypeCore

struct AIChatPanel: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @State private var inputText = ""
    @State private var messages: [(role: String, content: String)] = []
    @State private var isProcessing = false

    @AppStorage("ollamaHost") private var ollamaHost = "localhost"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"

    private let executor = HypeToolExecutor()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                Text("AI Assistant").font(.headline)
                Spacer()
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

            // Input
            HStack {
                TextField("Ask AI to build something...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }
                    .disabled(isProcessing)
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
            }
            .padding(8)
        }
        .frame(width: 350)
    }

    private func bubbleColor(for role: String) -> Color {
        switch role {
        case "user": return Color.accentColor.opacity(0.2)
        case "tool": return Color.green.opacity(0.1)
        default: return Color(NSColor.controlBackgroundColor)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messages.append((role: "user", content: text))
        inputText = ""
        isProcessing = true

        Task {
            await processWithTools(userMessage: text)
            isProcessing = false
        }
    }

    @MainActor
    private func processWithTools(userMessage: String) async {
        let client = OllamaToolClient(host: ollamaHost, port: ollamaPort, model: ollamaModel)

        // Get current stack context for the system prompt
        let cardId = currentCardId ?? document.document.sortedCards.first?.id ?? UUID()
        let currentParts = document.document.partsForCard(cardId)
            .map { "[\($0.partType.rawValue)] \"\($0.name)\" at (\(Int($0.left)),\(Int($0.top))) \(Int($0.width))x\(Int($0.height))" }
            .joined(separator: ", ")
        let cardCount = document.document.cards.count

        // Build fresh messages for THIS request only (not full history — avoids confusion)
        // Get background info
        let currentCard = document.document.cards.first(where: { $0.id == cardId })
        let bgName = currentCard.flatMap { document.document.backgroundForCard($0)?.name } ?? "unknown"
        let bgParts = currentCard.map { document.document.partsForBackground($0.backgroundId) } ?? []
        let bgPartsDesc = bgParts.map { "[\($0.partType.rawValue)] \"\($0.name)\"" }.joined(separator: ", ")

        var ollamaMessages: [OllamaMessage] = [
            OllamaMessage(role: "system", content: """
                You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is 800x600 points.

                RULES:
                - Call the needed tools to fulfill the user's request, then STOP and respond with a brief summary.
                - Do NOT repeat tool calls you have already made.
                - Do NOT delete parts unless the user specifically asks you to.
                - Create well-spaced, visually appealing layouts.
                - Use descriptive names for all parts.
                - When the user says "background", set on_background to "true" in create tools.
                  Background parts are shared across ALL cards that use that background.
                - For button scripts, just provide the command (e.g. "go next"). It will be auto-wrapped in on mouseUp/end mouseUp.

                CURRENT STATE: \(cardCount) cards. Background: "\(bgName)". \
                Card parts: \(currentParts.isEmpty ? "none" : currentParts). \
                Background parts: \(bgPartsDesc.isEmpty ? "none" : bgPartsDesc)
                """),
            OllamaMessage(role: "user", content: userMessage),
        ]

        // Tool-use loop (max 5 rounds — enough for any reasonable task)
        var rounds = 0
        while rounds < 5 {
            rounds += 1

            do {
                let response = try await client.chat(
                    messages: ollamaMessages,
                    tools: HypeToolDefinitions.allTools
                )

                // Check for tool calls
                if let toolCalls = response.message.tool_calls, !toolCalls.isEmpty {
                    // IMPORTANT: append the assistant's message with tool_calls to the conversation
                    // so the model knows what it already did
                    ollamaMessages.append(response.message)

                    for call in toolCalls {
                        let argsDesc = call.function.arguments
                            .map { "\($0.key): \($0.value)" }
                            .joined(separator: ", ")
                        let toolMsg = "Tool: \(call.function.name)(\(argsDesc))"
                        messages.append((role: "tool", content: toolMsg))

                        // Execute the tool against a local copy, then assign back
                        var doc = document.document
                        let result = await executor.execute(
                            toolName: call.function.name,
                            arguments: call.function.arguments,
                            document: &doc,
                            currentCardId: cardId
                        )
                        document.document = doc

                        // Handle navigation results
                        if result.hasPrefix("NAVIGATE:") {
                            let dest = String(result.dropFirst(9))
                            handleNavigation(destination: dest)
                        }

                        // Feed result back to model so it knows the outcome
                        ollamaMessages.append(OllamaMessage(role: "tool", content: result))
                    }
                    // Continue — model may want to call more tools
                    continue
                }

                // No tool calls — model is done, show the response
                let text = response.message.content ?? "(no response)"
                messages.append((role: "assistant", content: text))
                break

            } catch {
                messages.append((role: "assistant", content: "Error: \(error.localizedDescription)"))
                break
            }
        }
    }

    private func handleNavigation(destination: String) {
        // Try by card name first
        if let card = document.document.cards.first(where: { $0.name.lowercased() == destination.lowercased() }) {
            currentCardId = card.id
            return
        }
        // Try by direction
        let direction: NavigationDirection?
        switch destination.lowercased() {
        case "next": direction = .next
        case "previous", "prev": direction = .previous
        case "first": direction = .first
        case "last": direction = .last
        default: direction = nil
        }
        if let dir = direction, let cid = currentCardId {
            if let newId = CardNavigator.navigate(direction: dir, currentCardId: cid, document: document.document) {
                currentCardId = newId
            }
        }
    }
}

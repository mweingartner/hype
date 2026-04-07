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

        // Build conversation messages for Ollama
        var ollamaMessages: [OllamaMessage] = [
            OllamaMessage(role: "system", content: """
                You are an AI assistant for Hype, a HyperCard-inspired app. You can create and modify \
                stacks, cards, buttons, fields, shapes, and web pages using the available tools. The canvas \
                is 800x600 points. Create well-designed, visually appealing layouts. Always use descriptive \
                names for parts.
                """),
        ]

        // Add conversation history
        for msg in messages {
            ollamaMessages.append(OllamaMessage(
                role: msg.role == "tool" ? "tool" : msg.role,
                content: msg.content
            ))
        }

        // Tool-use loop (max 10 rounds)
        var rounds = 0
        while rounds < 10 {
            rounds += 1

            do {
                let response = try await client.chat(
                    messages: ollamaMessages,
                    tools: HypeToolDefinitions.allTools
                )

                // Check for tool calls
                if let toolCalls = response.message.tool_calls, !toolCalls.isEmpty {
                    for call in toolCalls {
                        let argsDesc = call.function.arguments
                            .map { "\($0.key): \($0.value)" }
                            .joined(separator: ", ")
                        let toolMsg = "Tool: \(call.function.name)(\(argsDesc))"
                        messages.append((role: "tool", content: toolMsg))

                        // Execute the tool against a local copy, then assign back
                        let cardId = currentCardId ?? document.document.sortedCards.first?.id ?? UUID()
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

                        // Feed result back to model
                        ollamaMessages.append(OllamaMessage(role: "tool", content: result))
                    }
                    // Continue the loop -- model may want to call more tools
                    continue
                }

                // No tool calls -- model is done, show the response
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

import SwiftUI
import HypeCore

struct AIPanel: View {
    @Binding var document: HypeDocumentWrapper
    @State private var inputText: String = ""
    @State private var messages: [(role: String, content: String)] = []
    @State private var isLoading: Bool = false
    @State private var apiKey: String = ""
    @State private var showKeyField: Bool = false

    private let aiService = AIService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Assistant").font(.headline)
                Spacer()
                Button(showKeyField ? "Hide Key" : "API Key") { showKeyField.toggle() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            if showKeyField {
                SecureField("Anthropic API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .onChange(of: apiKey) { _, newValue in
                        Task { await aiService.setApiKey(newValue) }
                    }
            }

            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                        HStack {
                            if msg.role == "user" { Spacer() }
                            Text(msg.content)
                                .padding(8)
                                .background(msg.role == "user" ? Color.blue.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .font(.system(size: 13))
                            if msg.role == "assistant" { Spacer() }
                        }
                    }
                    if isLoading {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text("Thinking...").font(.system(size: 11)).foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(8)
            }

            // Input
            HStack {
                TextField("Ask AI to create or modify your stack...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(8)
        }
        .frame(width: 320)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messages.append((role: "user", content: text))
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await aiService.ask(
                    prompt: text,
                    system: "You are a helpful assistant for Hype, a HyperCard-inspired app. Help users create and modify stacks."
                )
                messages.append((role: "assistant", content: response.text))
            } catch {
                messages.append((role: "assistant", content: "Error: \(error.localizedDescription)"))
            }
            isLoading = false
        }
    }
}

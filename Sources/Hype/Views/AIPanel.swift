import SwiftUI
import HypeCore

struct AIPanel: View {
    @Binding var document: HypeDocumentWrapper
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var inputText: String = ""
    @State private var messages: [(role: String, content: String)] = []
    @State private var isLoading: Bool = false
    @AppStorage(HypeAIConfiguration.providerKey) private var aiProviderRaw = HypeAIProvider.ollama.rawValue
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage(HypeAIConfiguration.openAIModelKey) private var openAIModel = HypeAIConfiguration.defaultOpenAIModel

    var body: some View {
        VStack(spacing: 0) {
            // Header — themed to match the toolbar so swapping
            // themes (Sunset / Modern Dark / Neon) actually retints
            // the AI panel chrome.
            HStack {
                Text("AI Assistant").font(.headline)
                Spacer()
                Text(modelLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(hypeTheme.toolbarBackground.swiftUIColor)
            .environment(\.colorScheme, hypeTheme.toolbarColorScheme)

            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                        HStack {
                            if msg.role == "user" { Spacer() }
                            Text(msg.content)
                                .padding(8)
                                .background(
                                    msg.role == "user"
                                        ? hypeTheme.accent.swiftUIColor.opacity(0.15)
                                        : hypeTheme.inspectorBackground.swiftUIColor
                                )
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
        // Panel surface — pulls inspector background from the
        // active theme so the side panel is dark in Modern Dark /
        // Neon and cream in Sunset, instead of staying system-light.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force the colorScheme to match the panel background's
        // luminance so SwiftUI's labels resolve a contrasting color
        // regardless of macOS appearance.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
    }

    private var modelLabel: String {
        if aiProviderRaw == HypeAIProvider.openAI.rawValue {
            return "OpenAI: \(openAIModel)"
        }
        return ollamaModel
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        appendMessage(role: "user", content: text)
        inputText = ""
        isLoading = true

        Task {
            do {
                let client = try HypeAIConfiguration.makeClient()
                let response = try await client.generate(
                    prompt: text,
                    model: nil,
                    system: "You are a helpful assistant for Hype, a HyperCard-inspired app. Help users create and modify stacks."
                )
                appendMessage(role: "assistant", content: response)
            } catch {
                appendMessage(role: "assistant", content: "Error: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    private func appendMessage(role: String, content: String) {
        messages.append((role: role, content: content))
        HypeLogger.shared.aiDialog(role: role, content: content, source: "AI Panel")
    }
}

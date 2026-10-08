import SwiftUI
import HypeCore

struct BraveSearchSettingsSection: View {
    @AppStorage(BraveSearchConfiguration.enabledKey) private var enabled = false
    @AppStorage(BraveSearchConfiguration.endpointKey) private var endpoint = BraveSearchConfiguration.defaultEndpoint
    @State private var status = ""
    @State private var toolNames: [String] = []
    @State private var isChecking = false
    @State private var checkTask: Task<Void, Never>?
    @State private var checkID = UUID()

    var body: some View {
        Section("Brave Search") {
            Toggle("Enable Brave Search for Hype agents", isOn: $enabled)
                .help("Allow authoring agents to send requested search queries through your existing Brave Search Bridge.")
            TextField("MCP URL", text: $endpoint)
                .textFieldStyle(.roundedBorder)
                .disabled(!enabled)
                .help("Use localhost on the bridge Mac, or a verified private network address when Hype runs elsewhere.")
            HStack {
                Button("Check Connection", action: checkConnection)
                    .disabled(!enabled || isChecking)
                if isChecking {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Checking Brave Search Bridge")
                    Button("Cancel", action: cancelCheck)
                }
            }
            if !status.isEmpty {
                Text(status).font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !toolNames.isEmpty {
                DisclosureGroup("Available tools (\(toolNames.count))") {
                    ForEach(toolNames, id: \.self) { name in
                        Text(name).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            Text("Keep Brave Search Bridge running on an awake, logged-in Mac. The API key stays in the bridge's Keychain; Hype needs no key. Queries go to Brave, and feature access depends on your subscription. Checking the connection discovers tools without spending a search request.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: enabled) { resetCheck() }
        .onChange(of: endpoint) { resetCheck() }
        .onDisappear(perform: cancelCheck)
    }

    private func checkConnection() {
        cancelCheck()
        let id = UUID()
        checkID = id
        isChecking = true
        status = "Checking bridge…"
        let session = BraveSearchSession(endpoint: endpoint)
        checkTask = Task { @MainActor in
            do {
                let tools = try await session.discover()
                guard checkID == id, !Task.isCancelled else { return }
                toolNames = tools.compactMap { $0.objectValue?["name"]?.stringValue }
                status = "Connected · \(toolNames.count) tools discovered. Search access is checked when a tool runs."
            } catch {
                guard checkID == id, !Task.isCancelled else { return }
                status = error.localizedDescription
                toolNames = []
            }
            guard checkID == id else { return }
            isChecking = false
            checkTask = nil
        }
    }

    private func cancelCheck() {
        checkID = UUID()
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
        if status == "Checking bridge…" { status = "Connection check cancelled." }
    }

    private func resetCheck() {
        cancelCheck()
        status = ""
        toolNames = []
    }
}

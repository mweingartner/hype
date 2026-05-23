import SwiftUI
import HypeCore

struct NetworkPanelView: View {
    @Binding var document: HypeDocumentWrapper
    let runtimeStatus: RuntimeStatusSnapshot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.hypeTheme) private var hypeTheme

    var body: some View {
        NavigationStack {
            Form {
                asyncSection
                outboundRulesSection
                savedListenersSection
                runtimeMonitorSection
            }
            .navigationTitle("Stack Network")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 640)
        // Sheet surface — tint with the active theme's inspector
        // background so the dialog matches the rest of the chrome.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so labels, toggles, and form
        // controls render with contrasting text against the themed
        // background regardless of macOS appearance.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
    }

    private var asyncSection: some View {
        Section("Async HypeTalk") {
            Text("Sync by default: normal handlers and existing `ask ai` / `ollama(...)` calls run inline and block until they finish.")
            Text("Suspending forms: `wait`, `wait until`, `await ollama(...)`, `await ollamaModels()`, `request ...` without `with message`, and runtime callbacks from listeners or async AI.")
            Text("Callback forms: use `with message \"handlerName\"` for long-lived work such as HTTP listeners, TCP listeners, TCP connections, and fire-and-forget AI requests.")
                .foregroundStyle(.secondary)
        }
    }

    private var outboundRulesSection: some View {
        Section("Outbound Rules") {
            if document.document.stack.networkManifest.outboundHostRules.isEmpty {
                Text("No outbound hosts are allowed yet. Add at least one rule before using `request` or `connect`.")
                    .foregroundStyle(.secondary)
            }

            ForEach(document.document.stack.networkManifest.outboundHostRules.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "Host pattern",
                        text: binding(
                            get: { document.document.stack.networkManifest.outboundHostRules[index].hostPattern },
                            set: { document.document.stack.networkManifest.outboundHostRules[index].hostPattern = $0 }
                        )
                    )
                    TextField(
                        "Schemes (comma separated)",
                        text: binding(
                            get: { document.document.stack.networkManifest.outboundHostRules[index].allowedSchemes.joined(separator: ",") },
                            set: { document.document.stack.networkManifest.outboundHostRules[index].allowedSchemes = csvList($0) }
                        )
                    )
                    TextField(
                        "Ports (comma separated, blank means any)",
                        text: binding(
                            get: {
                                document.document.stack.networkManifest.outboundHostRules[index]
                                    .allowedPorts
                                    .map(String.init)
                                    .joined(separator: ",")
                            },
                            set: {
                                document.document.stack.networkManifest.outboundHostRules[index].allowedPorts = csvPorts($0)
                            }
                        )
                    )
                    HStack {
                        Text("Examples: `localhost`, `127.0.0.1`, `*.example.com`")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            document.document.stack.networkManifest.outboundHostRules.remove(at: index)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button("Add Outbound Rule") {
                document.document.stack.networkManifest.outboundHostRules.append(
                    OutboundHostRule(hostPattern: "localhost", allowedSchemes: ["http", "https"], allowedPorts: [11434])
                )
            }
        }
    }

    private var savedListenersSection: some View {
        Section("Saved Listeners") {
            if document.document.stack.networkManifest.savedListeners.isEmpty {
                Text("Saved listeners define what `listen for http ...` and `listen for tcp ...` are allowed to bind, and which listeners can auto-start with the stack.")
                    .foregroundStyle(.secondary)
            }

            ForEach(document.document.stack.networkManifest.savedListeners.indices, id: \.self) { index in
                let listener = document.document.stack.networkManifest.savedListeners[index]
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "Name",
                        text: binding(
                            get: { document.document.stack.networkManifest.savedListeners[index].name },
                            set: { document.document.stack.networkManifest.savedListeners[index].name = $0 }
                        )
                    )

                    Picker(
                        "Transport",
                        selection: binding(
                            get: { document.document.stack.networkManifest.savedListeners[index].transport },
                            set: { document.document.stack.networkManifest.savedListeners[index].transport = $0 }
                        )
                    ) {
                        ForEach(NetworkTransportKind.allCases, id: \.self) { transport in
                            Text(transport.rawValue.uppercased()).tag(transport)
                        }
                    }

                    TextField(
                        "Host",
                        text: binding(
                            get: { document.document.stack.networkManifest.savedListeners[index].host },
                            set: { document.document.stack.networkManifest.savedListeners[index].host = $0 }
                        )
                    )

                    TextField(
                        "Port",
                        text: binding(
                            get: { String(document.document.stack.networkManifest.savedListeners[index].port) },
                            set: { document.document.stack.networkManifest.savedListeners[index].port = Int($0) ?? listener.port }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "Callback message",
                        text: binding(
                            get: { document.document.stack.networkManifest.savedListeners[index].callbackMessage },
                            set: { document.document.stack.networkManifest.savedListeners[index].callbackMessage = $0 }
                        )
                    )

                    Picker(
                        "Bind scope",
                        selection: binding(
                            get: { document.document.stack.networkManifest.savedListeners[index].bindScope },
                            set: { document.document.stack.networkManifest.savedListeners[index].bindScope = $0 }
                        )
                    ) {
                        ForEach(NetworkBindScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue.capitalized).tag(scope)
                        }
                    }

                    Toggle(
                        "Auto-start when this stack opens",
                        isOn: binding(
                            get: { document.document.stack.networkManifest.savedListeners[index].autoStart },
                            set: { document.document.stack.networkManifest.savedListeners[index].autoStart = $0 }
                        )
                    )

                    if document.document.stack.networkManifest.savedListeners[index].transport == .http {
                        TextField(
                            "HTTP method filter (optional)",
                            text: binding(
                                get: { document.document.stack.networkManifest.savedListeners[index].httpMethod ?? "" },
                                set: { document.document.stack.networkManifest.savedListeners[index].httpMethod = normalized($0) }
                            )
                        )
                        TextField(
                            "HTTP path filter (optional)",
                            text: binding(
                                get: { document.document.stack.networkManifest.savedListeners[index].httpPath ?? "" },
                                set: { document.document.stack.networkManifest.savedListeners[index].httpPath = normalized($0) }
                            )
                        )
                    }

                    if !isLoopbackHost(document.document.stack.networkManifest.savedListeners[index].host) {
                        Text("Warning: non-loopback listeners expose the stack to other machines on the network. Approval is local to this machine and is never saved inside the stack.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Button(isListenerActive(listener) ? "Stop" : "Start") {
                            toggleListener(listener)
                        }
                        .buttonStyle(.borderedProminent)

                        if isListenerActive(listener) {
                            Text("Running")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Stopped")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Remove", role: .destructive) {
                            document.document.stack.networkManifest.savedListeners.remove(at: index)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button("Add Saved Listener") {
                document.document.stack.networkManifest.savedListeners.append(
                    SavedNetworkListener(
                        name: "Local HTTP",
                        transport: .http,
                        port: 8080,
                        host: "127.0.0.1",
                        callbackMessage: "networkRequest"
                    )
                )
            }
        }
    }

    private var runtimeMonitorSection: some View {
        Section("Runtime Monitor") {
            GroupBox("Requests") {
                if runtimeStatus.requests.isEmpty {
                    Text("No pending or completed async requests in this session.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(runtimeStatus.requests) { request in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(request.method) \(request.url)")
                            Text("state: \(request.state)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let statusCode = request.statusCode {
                                Text("status: \(statusCode)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let error = request.error, !error.isEmpty {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            GroupBox("Listeners") {
                if runtimeStatus.listeners.isEmpty {
                    Text("No active listeners.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(runtimeStatus.listeners) { listener in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(listener.transport.uppercased()) \(listener.host):\(listener.port)")
                            Text("state: \(listener.state)  callback: \(listener.callbackMessage)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            GroupBox("Connections") {
                if runtimeStatus.connections.isEmpty {
                    Text("No active TCP connections.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(runtimeStatus.connections) { connection in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(connection.host):\(connection.port)")
                            Text("state: \(connection.state)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !connection.lastDataPreview.isEmpty {
                                Text(connection.lastDataPreview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let error = connection.error, !error.isEmpty {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func binding<T>(get: @escaping @Sendable () -> T, set: @escaping @Sendable (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }

    private func csvList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func csvPorts(_ value: String) -> [Int] {
        value
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isLoopbackHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return normalizedHost == "127.0.0.1" || normalizedHost == "localhost"
    }

    private func isListenerActive(_ listener: SavedNetworkListener) -> Bool {
        runtimeStatus.listeners.contains {
            $0.transport.lowercased() == listener.transport.rawValue &&
            $0.host.caseInsensitiveCompare(listener.host) == .orderedSame &&
            $0.port == listener.port &&
            $0.callbackMessage.caseInsensitiveCompare(listener.callbackMessage) == .orderedSame
        }
    }

    private func toggleListener(_ listener: SavedNetworkListener) {
        let snapshot = document.document
        let configuration = StackRuntimeConfiguration(
            aiProvider: SelectedAIScriptingProvider(),
            speechOutputProvider: OpenAISpeechOutputProvider.shared,
            speechListenerProvider: RuntimeSpeechListenerProvider.shared
        )
        Task {
            let runtime = await StackRuntimeRegistry.shared.runtime(for: snapshot, configuration: configuration)
            if await runtime.isSavedListenerActive(listener.id) {
                await runtime.stopSavedListener(definitionID: listener.id)
            } else {
                _ = try? await runtime.startSavedListener(definitionID: listener.id)
            }
        }
    }
}

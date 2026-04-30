import SwiftUI
import HypeCore

struct PreferencesView: View {
    @AppStorage("ollamaHost") private var ollamaHost = "localhost"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var availableModels: [String] = []
    @State private var isLoading = false
    @State private var connectionStatus = ""

    // MARK: - Web Asset Search state

    /// The provider preference key. Default: openverse.
    @AppStorage("hype.webAssets.provider") private var webAssetProviderRaw = "openverse"

    /// Pexels API key draft (SecureField). Held in memory only; written to Keychain on save.
    @State private var pexelsKeyDraft = ""
    @State private var pexelsKeyIsSet = false
    @State private var isTestingWebAsset = false
    @State private var webAssetTestStatus = ""

    /// The current document wrapper, passed in from the Settings scene host.
    /// Used to read `stack.webAssetsAllowed` for display; writes re-resolve
    /// the front document via the binding's `set` closure.
    @Binding var document: HypeDocumentWrapper?

    // MARK: - Init

    /// Full init with document binding (for Settings scene wiring).
    init(document: Binding<HypeDocumentWrapper?>) {
        self._document = document
    }

    /// Convenience no-arg init that creates a nil document binding.
    /// Preserves source-compatibility with existing `PreferencesView()` call sites.
    init() {
        self._document = .constant(nil)
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section("Ollama Connection") {
                TextField("Host", text: $ollamaHost)
                TextField("Port", text: $ollamaPort)

                HStack {
                    Button("Test Connection") { testConnection() }
                    if isLoading { ProgressView().scaleEffect(0.7) }
                    Text(connectionStatus)
                        .foregroundColor(connectionStatus.contains("Connected") ? .green : .red)
                        .font(.system(size: 11))
                }
            }

            Section("Model") {
                Picker("Model", selection: $ollamaModel) {
                    if availableModels.isEmpty {
                        Text(ollamaModel).tag(ollamaModel)
                    }
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Button("Refresh Models") { fetchModels() }
            }

            // MARK: - Web Asset Search section

            Section("Web Asset Search") {
                // Current Stack toggle — re-resolves the front document at write time.
                Toggle("Enable for Current Stack", isOn: currentStackWebAssetsBinding)
                    .disabled(document == nil)
                    .help("Allow the AI assistant to search and import images from the web for this stack.")

                // Provider picker
                Picker("Provider", selection: $webAssetProviderRaw) {
                    ForEach(WebAssetSearchProvider.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }

                // Pexels API key — only shown when Pexels is selected
                if webAssetProviderRaw == WebAssetSearchProvider.pexels.rawValue {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SecureField(
                                pexelsKeyIsSet ? "API key stored (tap to replace)" : "Pexels API key",
                                text: $pexelsKeyDraft
                            )
                            .textFieldStyle(.roundedBorder)

                            Button("Save") { savePexelsKey() }
                                .disabled(pexelsKeyDraft.isEmpty)

                            if pexelsKeyIsSet {
                                Button("Delete") { deletePexelsKey() }
                                    .foregroundColor(.red)
                            }
                        }

                        HStack {
                            Button("Test Connection") { testWebAssetProvider() }
                                .disabled(isTestingWebAsset)
                            if isTestingWebAsset { ProgressView().scaleEffect(0.7) }
                            if !webAssetTestStatus.isEmpty {
                                Text(webAssetTestStatus)
                                    .font(.system(size: 11))
                                    .foregroundColor(webAssetTestStatus.hasPrefix("OK") ? .green : .red)
                            }
                        }
                    }
                } else {
                    // Test connection for non-Pexels providers
                    HStack {
                        Button("Test Connection") { testWebAssetProvider() }
                            .disabled(isTestingWebAsset)
                        if isTestingWebAsset { ProgressView().scaleEffect(0.7) }
                        if !webAssetTestStatus.isEmpty {
                            Text(webAssetTestStatus)
                                .font(.system(size: 11))
                                .foregroundColor(webAssetTestStatus.hasPrefix("OK") ? .green : .red)
                        }
                    }
                }

                // Static policy disclosure
                Text("Downloaded assets are stored only in the document, not on disk. Attribution is added to the stack script automatically.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        // Settings surface — tint with the inspector-background
        // token so the Preferences scene picks up theme swaps.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so picker rows, toggles, and
        // text fields keep their labels readable on themed bg.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
        .onAppear {
            fetchModels()
            pexelsKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.pexelsAPIKeyAccount)
        }
    }

    // MARK: - Current Stack Binding

    /// A `Binding<Bool>` that reads `webAssetsAllowed` from the passed-in document
    /// and re-resolves the front document at write time via the binding chain.
    ///
    /// The `set` closure reads from the `document` binding (which is kept up-to-date
    /// by the Settings host) to find the currently displayed document and writes to it.
    /// This avoids capturing a stale reference at view-construction time (Finding 13).
    private var currentStackWebAssetsBinding: Binding<Bool> {
        Binding(
            get: {
                document?.document.stack.webAssetsAllowed ?? false
            },
            set: { newValue in
                // Mutate via the binding — the host keeps `document` current.
                document?.document.stack.webAssetsAllowed = newValue
            }
        )
    }

    // MARK: - Pexels Key Management

    private func savePexelsKey() {
        guard !pexelsKeyDraft.isEmpty else { return }
        do {
            try KeychainStore.setSecret(pexelsKeyDraft, account: KeychainStore.pexelsAPIKeyAccount)
            pexelsKeyDraft = ""
            pexelsKeyIsSet = true
        } catch {
            // Surface only to Preferences — not to AI-visible strings.
            webAssetTestStatus = keychainErrorMessage(for: error)
        }
    }

    private func deletePexelsKey() {
        do {
            try KeychainStore.deleteSecret(account: KeychainStore.pexelsAPIKeyAccount)
            pexelsKeyIsSet = false
            pexelsKeyDraft = ""
            webAssetTestStatus = ""
        } catch {
            webAssetTestStatus = keychainErrorMessage(for: error)
        }
    }

    /// Render a Keychain error as a narrow user-facing string.
    ///
    /// `KeychainStoreError.unhandledStatus(OSStatus)` is the usual failure
    /// mode — surface the integer code only (useful for support), never
    /// the full error description. This keeps the Preferences UI safe
    /// even if `KeychainStoreError` is later extended with more context-
    /// rich cases. (Security Finding N-6.)
    private func keychainErrorMessage(for error: Error) -> String {
        if let kcError = error as? KeychainStoreError {
            switch kcError {
            case .unhandledStatus(let status):
                return "Keychain error (code \(status))"
            case .encodingFailed:
                return "Keychain error (encoding failed)"
            case .itemNotFound:
                return "Keychain item not found"
            }
        }
        return "Keychain error"
    }

    // MARK: - Test Web Asset Provider

    /// Test the currently selected web-asset provider.
    ///
    /// On failure, shows "Connection failed" only — never `localizedDescription`
    /// (Security Finding 5).
    private func testWebAssetProvider() {
        isTestingWebAsset = true
        webAssetTestStatus = ""
        Task {
            let provider = WebAssetSearchProvider(rawValue: webAssetProviderRaw) ?? .openverse
            let client = WebAssetSearchClientFactory.make(provider: provider)
            do {
                let results = try await client.search(WebAssetSearchQuery(query: "test", maxResults: 1))
                await MainActor.run {
                    webAssetTestStatus = "OK: \(provider.displayName) returned \(results.count) result(s)."
                    isTestingWebAsset = false
                }
            } catch {
                await MainActor.run {
                    webAssetTestStatus = "Connection failed"   // Finding 5: no raw error text.
                    isTestingWebAsset = false
                }
            }
        }
    }

    // MARK: - Ollama Connection

    private func testConnection() {
        isLoading = true
        connectionStatus = ""
        Task {
            let urlString = "http://\(ollamaHost):\(ollamaPort)/api/tags"
            guard let url = URL(string: urlString) else {
                connectionStatus = "Invalid URL"
                isLoading = false
                return
            }
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    connectionStatus = "Connected"
                } else {
                    connectionStatus = "Error: unexpected status"
                }
            } catch {
                connectionStatus = "Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func fetchModels() {
        let urlString = "http://\(ollamaHost):\(ollamaPort)/api/tags"
        guard let url = URL(string: urlString) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["models"] as? [[String: Any]] {
                    availableModels = models.compactMap { $0["name"] as? String }
                    if !availableModels.isEmpty && !availableModels.contains(ollamaModel) {
                        ollamaModel = availableModels[0]
                    }
                }
            } catch {
                // Silently fail -- models stay empty until user refreshes
            }
        }
    }
}

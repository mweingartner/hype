import SwiftUI
import HypeCore

struct PreferencesView: View {
    @AppStorage("ollamaHost") private var ollamaHost = "localhost"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage(HypeAIConfiguration.providerKey) private var aiProviderRaw = HypeAIProvider.ollama.rawValue
    @AppStorage(HypeAIConfiguration.openAIModelKey) private var openAIModel = HypeAIConfiguration.defaultOpenAIModel
    @AppStorage(HypeAIConfiguration.openAIImageModelKey) private var openAIImageModel = HypeAIConfiguration.defaultOpenAIImageModel
    @AppStorage(HypeAIConfiguration.speechInputProviderKey) private var speechInputProviderRaw = HypeSpeechInputProvider.apple.rawValue
    @AppStorage(HypeAIConfiguration.openAITranscriptionModelKey) private var openAITranscriptionModel = HypeAIConfiguration.defaultOpenAITranscriptionModel
    @AppStorage(HypeAIConfiguration.openAITTSModelKey) private var openAITTSModel = HypeAIConfiguration.defaultOpenAITTSModel
    @AppStorage(HypeAIConfiguration.openAIVoiceKey) private var openAIVoice = HypeAIConfiguration.defaultOpenAIVoice
    @AppStorage(HypeAIConfiguration.speakAssistantResponsesKey) private var speakAssistantResponses = false
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var availableModels: [String] = []
    @State private var isLoading = false
    @State private var connectionStatus = ""
    @State private var openAIKeyDraft = ""
    @State private var openAIKeyIsSet = false
    @State private var isTestingOpenAI = false
    @State private var openAITestStatus = ""
    @State private var selectedCategory: PreferenceCategory = .ai

    private enum PreferenceCategory: String, CaseIterable, Hashable {
        case ai = "AI"
        case services = "Services"
        case speech = "Speech"
        case assets = "Assets"
        case context = "Context"

        var systemImage: String {
            switch self {
            case .ai:
                "sparkles"
            case .services:
                "cube"
            case .speech:
                "waveform"
            case .assets:
                "photo.on.rectangle"
            case .context:
                "books.vertical"
            }
        }
    }

    // MARK: - Meshy.ai state

    @State private var meshyKeyDraft: String = ""
    @State private var meshyKeyIsSet: Bool = false
    @State private var meshyBalance: Int? = nil
    @State private var isTestingMeshy: Bool = false
    @State private var meshyTestStatus: String = ""
    /// In-flight Task for balance refresh — cancelled before starting a new one (M3).
    @State private var meshyBalanceTask: Task<Void, Never>? = nil
    /// In-flight Task for connection test — cancelled before starting a new one (M3).
    @State private var meshyTestTask: Task<Void, Never>? = nil

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
        TabView(selection: $selectedCategory) {
            aiSettings
                .tabItem { Label(PreferenceCategory.ai.rawValue, systemImage: PreferenceCategory.ai.systemImage) }
                .tag(PreferenceCategory.ai)

            integrationSettings
                .tabItem { Label(PreferenceCategory.services.rawValue, systemImage: PreferenceCategory.services.systemImage) }
                .tag(PreferenceCategory.services)

            speechSettings
                .tabItem { Label(PreferenceCategory.speech.rawValue, systemImage: PreferenceCategory.speech.systemImage) }
                .tag(PreferenceCategory.speech)

            assetSettings
                .tabItem { Label(PreferenceCategory.assets.rawValue, systemImage: PreferenceCategory.assets.systemImage) }
                .tag(PreferenceCategory.assets)

            contextSettings
                .tabItem { Label(PreferenceCategory.context.rawValue, systemImage: PreferenceCategory.context.systemImage) }
                .tag(PreferenceCategory.context)
        }
        .frame(width: 560, height: 640)
        // Settings surface — tint with the inspector-background
        // token so the Preferences scene picks up theme swaps.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so picker rows, toggles, and
        // text fields keep their labels readable on themed bg.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
        .onAppear {
            fetchModels()
            pexelsKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.pexelsAPIKeyAccount)
            openAIKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.openAIAPIKeyAccount)
            meshyKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
        }
    }

    private var aiSettings: some View {
        settingsForm {
            Section("AI Provider") {
                Picker("Provider", selection: $aiProviderRaw) {
                    ForEach(HypeAIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }

                Text("The selected provider powers the AI Assistant, HypeTalk `ask ai` calls, structured scene planning, and Script Editor AI.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                if aiProviderRaw == HypeAIProvider.openAI.rawValue {
                    Picker("OpenAI Model", selection: $openAIModel) {
                        ForEach(HypeAIConfiguration.openAITextModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } else {
                    Picker("Ollama Model", selection: $ollamaModel) {
                        if availableModels.isEmpty {
                            Text(ollamaModel).tag(ollamaModel)
                        }
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Button("Refresh Models") { fetchModels() }
                }
            }

            Section("OpenAI") {
                HStack {
                    SecureField(
                        openAIKeyIsSet ? "API key stored (tap to replace)" : "OpenAI API key",
                        text: $openAIKeyDraft
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Save") { saveOpenAIKey() }
                        .disabled(openAIKeyDraft.isEmpty)

                    if openAIKeyIsSet {
                        Button("Delete") { deleteOpenAIKey() }
                            .foregroundColor(.red)
                    }
                }

                HStack {
                    Button("Test OpenAI") { testOpenAI() }
                        .disabled(isTestingOpenAI || !openAIKeyIsSet)
                    if isTestingOpenAI { ProgressView().scaleEffect(0.7) }
                    if !openAITestStatus.isEmpty {
                        Text(openAITestStatus)
                            .font(.system(size: 11))
                            .foregroundColor(openAITestStatus.hasPrefix("OK") ? .green : .red)
                    }
                }

                Picker("Image Model", selection: $openAIImageModel) {
                    ForEach(HypeAIConfiguration.openAIImageModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Text("Used when the AI generates images for cards, backgrounds, or Sprite Repository assets. This works even when Ollama is the selected chat provider.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var integrationSettings: some View {
        settingsForm {
            // MARK: - Meshy.ai section

            Section("Meshy.ai (3D model generation)") {
                Toggle("Enable for Current Stack", isOn: currentStackMeshyEnabledBinding)
                    .disabled(document == nil)
                    .help("Allow the AI assistant and the Sprite Repository to generate 3D models using your Meshy.ai credits for this stack.")

                HStack {
                    SecureField(
                        meshyKeyIsSet ? "API key stored (tap to replace)" : "Meshy API key (starts with msy_)",
                        text: $meshyKeyDraft
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Save") { saveMeshyKey() }
                        .disabled(meshyKeyDraft.isEmpty)

                    if meshyKeyIsSet {
                        Button("Delete") { deleteMeshyKey() }
                            .foregroundColor(.red)
                    }
                }

                HStack {
                    Text("Balance:")
                    if let balance = meshyBalance {
                        Text("\(balance) credits")
                    } else {
                        Text("—").foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { refreshMeshyBalance() }
                        .disabled(!meshyKeyIsSet)
                }

                HStack {
                    Button("Test connection") { testMeshyConnection() }
                        .disabled(!meshyKeyIsSet)
                    if isTestingMeshy { ProgressView().scaleEffect(0.7) }
                    if !meshyTestStatus.isEmpty {
                        Text(meshyTestStatus)
                            .font(.system(size: 11))
                            .foregroundColor(meshyTestStatus.hasPrefix("OK") ? .green : .red)
                    }
                }

                Text("Prompts are sent to api.meshy.ai using your Meshy.ai credits. Generated models are downloaded over HTTPS and embedded in the current .hype document — never stored elsewhere.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Phase 4: Webhook documentation disclosure group (C18/C19).
                // Read-only — no persisted state. The listener recipe itself
                // is configured per-stack in HypeTalk, not here.
                DisclosureGroup("Webhook notifications (advanced)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meshy can POST a webhook to a URL of your choice when a generation finishes. Hype's `listen for http on <port> \u{201c}messageName\u{201d}` HypeTalk command can receive these \u{2014} but the URL must be reachable from the public internet, which requires a tunnel (ngrok, Cloudflare Tunnel, Tailscale Funnel).")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("In your message handler, use `meshy_parse_webhook(body)` to extract task_id, status, and the GLB URL from the request body. Meshy does NOT sign webhook payloads \u{2014} keep your tunnel URL private.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Configure the webhook callback URL in your Meshy dashboard, not here.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Button("Open Meshy Dashboard\u{2026}") {
                            NSWorkspace.shared.open(URL(string: "https://app.meshy.ai/api-keys")!)
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 11))
            }
        }
    }

    private var speechSettings: some View {
        settingsForm {
            Section("Speech") {
                Picker("Voice Input", selection: $speechInputProviderRaw) {
                    ForEach(HypeSpeechInputProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }

                Picker("Transcription Model", selection: $openAITranscriptionModel) {
                    ForEach(HypeAIConfiguration.openAITranscriptionModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .disabled(speechInputProviderRaw != HypeSpeechInputProvider.openAI.rawValue)

                Toggle("Speak AI responses with OpenAI", isOn: $speakAssistantResponses)
                    .disabled(!openAIKeyIsSet)

                Text("Speaks AI Assistant replies and HypeTalk `ask ai` / `ollama(...)` responses. This uses OpenAI speech even when Ollama is the selected text provider.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Speech Model", selection: $openAITTSModel) {
                    ForEach(HypeAIConfiguration.openAITTSModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .disabled(!speakAssistantResponses || !openAIKeyIsSet)

                Picker("Voice", selection: $openAIVoice) {
                    ForEach(HypeAIConfiguration.openAIVoices, id: \.self) { voice in
                        Text(voice.capitalized).tag(voice)
                    }
                }
                .disabled(!speakAssistantResponses || !openAIKeyIsSet)
            }
        }
    }

    private var assetSettings: some View {
        settingsForm {
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
    }

    private var contextSettings: some View {
        settingsForm {
            Section("AI Context Library") {
                Toggle("Allow Current Stack Context with OpenAI", isOn: currentStackAIContextCloudSharingBinding)
                    .disabled(document == nil)
                    .help("Allow attached AI Context Library text and asset metadata to be sent to OpenAI for this stack.")

                Text("Local Ollama models can use attached context without this setting. Cloud models only receive stack-attached files, notes, image metadata, and text snippets when this is enabled for the current stack.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Current stack context: \(document?.document.aiContextLibrary.itemCount ?? 0) item(s), \(document?.document.aiContextLibrary.sourceCount ?? 0) source(s).")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
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
                // Copy-modify-reassign — see `currentStackMeshyEnabledBinding`
                // for the rationale (optional-chain mutation through `@Binding`
                // is unreliable for value-typed wrappers).
                guard var wrapper = document else { return }
                wrapper.document.stack.webAssetsAllowed = newValue
                document = wrapper
            }
        )
    }

    /// Stack-level cloud context sharing gate. The attached context library is
    /// document data, so cloud model access is deliberately opt-in per stack.
    private var currentStackAIContextCloudSharingBinding: Binding<Bool> {
        Binding(
            get: {
                document?.document.stack.aiContextCloudSharingAllowed ?? false
            },
            set: { newValue in
                guard var wrapper = document else { return }
                wrapper.document.stack.aiContextCloudSharingAllowed = newValue
                document = wrapper
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

    private func saveOpenAIKey() {
        guard !openAIKeyDraft.isEmpty else { return }
        do {
            try KeychainStore.setSecret(openAIKeyDraft, account: KeychainStore.openAIAPIKeyAccount)
            openAIKeyDraft = ""
            openAIKeyIsSet = true
            openAITestStatus = ""
        } catch {
            openAITestStatus = keychainErrorMessage(for: error)
        }
    }

    private func deleteOpenAIKey() {
        do {
            try KeychainStore.deleteSecret(account: KeychainStore.openAIAPIKeyAccount)
            openAIKeyIsSet = false
            openAIKeyDraft = ""
            openAITestStatus = ""
        } catch {
            openAITestStatus = keychainErrorMessage(for: error)
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

    private func testOpenAI() {
        isTestingOpenAI = true
        openAITestStatus = ""
        Task {
            do {
                let key = try KeychainStore.getSecret(account: KeychainStore.openAIAPIKeyAccount)
                let client = OpenAIResponsesClient(apiKey: key, model: openAIModel)
                let response = try await client.generate(
                    prompt: "Reply with exactly: OK",
                    model: nil,
                    system: "You are testing connectivity for Hype Preferences."
                )
                await MainActor.run {
                    openAITestStatus = response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Connection failed"
                        : "OK: OpenAI responded."
                    isTestingOpenAI = false
                }
            } catch {
                await MainActor.run {
                    openAITestStatus = "Connection failed"
                    isTestingOpenAI = false
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

    // MARK: - Meshy.ai Bindings and Actions

    /// Binding for `stack.meshyEnabled` — mirrors `currentStackWebAssetsBinding`.
    ///
    /// Uses copy-modify-reassign rather than `document?.document.stack.meshyEnabled = $0`.
    /// The chained-optional form is unreliable through `@Binding` to a value-typed
    /// wrapper: Swift's modify-accessor sometimes mutates a temporary copy instead of
    /// re-invoking the binding's setter. Reassigning the whole wrapper guarantees the
    /// write flows back through the focused-scene binding to the document scene.
    private var currentStackMeshyEnabledBinding: Binding<Bool> {
        Binding(
            get: { document?.document.stack.meshyEnabled ?? false },
            set: { newValue in
                guard var wrapper = document else { return }
                wrapper.document.stack.meshyEnabled = newValue
                document = wrapper
            }
        )
    }

    private func saveMeshyKey() {
        guard !meshyKeyDraft.isEmpty else { return }
        do {
            try KeychainStore.setSecret(meshyKeyDraft, account: KeychainStore.meshyAPIKeyAccount)
            meshyKeyDraft = ""
            meshyKeyIsSet = true
            meshyTestStatus = ""
        } catch {
            meshyTestStatus = keychainErrorMessage(for: error)
        }
    }

    private func deleteMeshyKey() {
        do {
            try KeychainStore.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)
            meshyKeyIsSet = false
            meshyKeyDraft = ""
            meshyBalance = nil
            meshyTestStatus = ""
        } catch {
            meshyTestStatus = keychainErrorMessage(for: error)
        }
    }

    /// Refresh the Meshy credit balance. Cancels any in-flight refresh
    /// before starting a new one (M3 — prevents unbounded concurrent Tasks).
    private func refreshMeshyBalance() {
        meshyBalanceTask?.cancel()
        meshyBalanceTask = Task {
            do {
                let key = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
                let client = MeshyAIClient(apiKey: key)
                let balance = try await client.fetchBalance()
                await MainActor.run { meshyBalance = balance }
            } catch {
                await MainActor.run { meshyBalance = nil }
            }
        }
    }

    /// Test the Meshy connection by fetching the balance. Cancels any
    /// in-flight test before starting a new one (M3).
    private func testMeshyConnection() {
        meshyTestTask?.cancel()
        isTestingMeshy = true
        meshyTestStatus = ""
        meshyTestTask = Task {
            do {
                let key = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
                let client = MeshyAIClient(apiKey: key)
                let balance = try await client.fetchBalance()
                await MainActor.run {
                    meshyTestStatus = "OK: \(balance) credits"
                    meshyBalance = balance
                    isTestingMeshy = false
                }
            } catch {
                await MainActor.run {
                    meshyTestStatus = "Connection failed"
                    isTestingMeshy = false
                }
            }
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

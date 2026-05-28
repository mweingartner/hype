import SwiftUI
import HypeCore
import AppKit

struct PreferencesView: View {
    @AppStorage("ollamaHost") private var ollamaHost = "localhost"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage(HypeAIConfiguration.llamaSwapHostKey) private var llamaSwapHost = HypeAIConfiguration.defaultLlamaSwapHost
    @AppStorage(HypeAIConfiguration.llamaSwapPortKey) private var llamaSwapPort = HypeAIConfiguration.defaultLlamaSwapPort
    @AppStorage(HypeAIConfiguration.llamaSwapModelKey) private var llamaSwapModel = HypeAIConfiguration.defaultLlamaSwapModel
    @AppStorage(HypeAIConfiguration.llamaCppHostKey) private var llamaCppHost = HypeAIConfiguration.defaultLlamaCppHost
    @AppStorage(HypeAIConfiguration.llamaCppPortKey) private var llamaCppPort = HypeAIConfiguration.defaultLlamaCppPort
    @AppStorage(HypeAIConfiguration.llamaCppModelKey) private var llamaCppModel = HypeAIConfiguration.defaultLlamaCppModel
    @AppStorage(HypeAIConfiguration.providerKey) private var aiProviderRaw = HypeAIProvider.ollama.rawValue
    @AppStorage(HypeAIConfiguration.openAIModelKey) private var openAIModel = HypeAIConfiguration.defaultOpenAIModel
    @AppStorage(HypeAIConfiguration.zAIBaseURLKey) private var zAIBaseURL = HypeAIConfiguration.defaultZAIBaseURL
    @AppStorage(HypeAIConfiguration.zAIModelKey) private var zAIModel = HypeAIConfiguration.defaultZAIModel
    @AppStorage(HypeAIConfiguration.miniMaxBaseURLKey) private var miniMaxBaseURL = HypeAIConfiguration.defaultMiniMaxBaseURL
    @AppStorage(HypeAIConfiguration.miniMaxModelKey) private var miniMaxModel = HypeAIConfiguration.defaultMiniMaxModel
    @AppStorage(HypeAIConfiguration.openAIImageModelKey) private var openAIImageModel = HypeAIConfiguration.defaultOpenAIImageModel
    @AppStorage(HypeAIConfiguration.speechInputProviderKey) private var speechInputProviderRaw = HypeSpeechInputProvider.apple.rawValue
    @AppStorage(HypeAIConfiguration.openAITranscriptionModelKey) private var openAITranscriptionModel = HypeAIConfiguration.defaultOpenAITranscriptionModel
    @AppStorage(HypeAIConfiguration.openAITTSModelKey) private var openAITTSModel = HypeAIConfiguration.defaultOpenAITTSModel
    @AppStorage(HypeAIConfiguration.openAIVoiceKey) private var openAIVoice = HypeAIConfiguration.defaultOpenAIVoice
    @AppStorage(HypeAIConfiguration.speakAssistantResponsesKey) private var speakAssistantResponses = false
    @AppStorage(AppleMusicConfiguration.enabledKey) private var appleMusicEnabled = false
    @AppStorage(AppleMusicConfiguration.playbackEngineKey) private var appleMusicPlaybackEngine = AppleMusicConfiguration.defaultPlaybackEngine.rawValue
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var availableModels: [String] = []
    @State private var llamaSwapAvailableModels: [String] = []
    @State private var llamaCppAvailableModels: [String] = []
    @State private var zAIAvailableModels: [String] = []
    @State private var miniMaxAvailableModels: [String] = []
    @State private var isLoading = false
    @State private var connectionStatus = ""
    @State private var isTestingOllamaDiagnostics = false
    @State private var ollamaDiagnosticsStatus = ""
    @State private var llamaSwapKeyDraft = ""
    @State private var llamaSwapKeyIsSet = false
    @State private var openAIKeyDraft = ""
    @State private var openAIKeyIsSet = false
    @State private var zAIKeyDraft = ""
    @State private var zAIKeyIsSet = false
    @State private var miniMaxKeyDraft = ""
    @State private var miniMaxKeyIsSet = false
    @State private var isTestingOpenAI = false
    @State private var openAITestStatus = ""
    @State private var isTestingHostedProvider = false
    @State private var hostedProviderTestStatus = ""
    @State private var appleMusicStatus = "Not checked"
    @State private var isCheckingAppleMusic = false
    @State private var selectedCategory: PreferenceCategory = .ai
    @State private var debugStatus: HypeDebugServerStatus?

    private enum PreferenceCategory: String, CaseIterable, Hashable {
        case ai = "AI"
        case services = "Services"
        case debug = "Debug"
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
            case .debug:
                "ant.fill"
            }
        }
    }

    // MARK: - Debug bridge state

    @AppStorage("hype.debug.enabled") private var debugEnabled = true

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

            debugSettings
                .tabItem { Label(PreferenceCategory.debug.rawValue, systemImage: PreferenceCategory.debug.systemImage) }
                .tag(PreferenceCategory.debug)

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
            openAIKeyIsSet = hasUsableSecret(account: KeychainStore.openAIAPIKeyAccount)
            zAIKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.zAIAPIKeyAccount)
            miniMaxKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.miniMaxAPIKeyAccount)
            llamaSwapKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.llamaSwapAPIKeyAccount)
            meshyKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
        }
        .onChange(of: aiProviderRaw) { _, _ in
            fetchModels()
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

            if aiProviderRaw == HypeAIProvider.ollama.rawValue {
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

                HStack {
                    Button("Test Tool + Streaming APIs") { testOllamaProviderDiagnostics() }
                        .disabled(isTestingOllamaDiagnostics)
                    if isTestingOllamaDiagnostics { ProgressView().scaleEffect(0.7) }
                    if !ollamaDiagnosticsStatus.isEmpty {
                        Text(ollamaDiagnosticsStatus)
                            .foregroundColor(ollamaDiagnosticsStatus.hasPrefix("OK") ? .green : .red)
                            .font(.system(size: 11))
                    }
                }

                Text("Runs three Ollama checks: native /api/tags + /api/pull + /api/chat tool calls, OpenAI-compatible /v1/chat/completions inference, and streaming response assembly.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }

            if aiProviderRaw == HypeAIProvider.llamaSwap.rawValue {
            Section("llama-swap Connection") {
                TextField("Host", text: $llamaSwapHost)
                TextField("Port", text: $llamaSwapPort)

                HStack {
                    SecureField(
                        llamaSwapKeyIsSet ? "API key stored (optional, tap to replace)" : "Optional API key",
                        text: $llamaSwapKeyDraft
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Save") { saveLlamaSwapKey() }
                        .disabled(llamaSwapKeyDraft.isEmpty)

                    if llamaSwapKeyIsSet {
                        Button("Delete") { deleteLlamaSwapKey() }
                            .foregroundColor(.red)
                    }
                }

                HStack {
                    Button("Test Connection") { testConnection() }
                    if isLoading { ProgressView().scaleEffect(0.7) }
                    Text(connectionStatus)
                        .foregroundColor(connectionStatus.contains("Connected") ? .green : .red)
                        .font(.system(size: 11))
                }

                Text("Hype calls llama-swap through its OpenAI-compatible API: GET /v1/models lists configured models, and the selected model name is sent in each /v1/responses request so llama-swap can load or swap to it.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }

            if aiProviderRaw == HypeAIProvider.llamaCpp.rawValue {
            Section("llama.cpp Connection") {
                TextField("Host", text: $llamaCppHost)
                TextField("Port", text: $llamaCppPort)

                HStack {
                    Button("Test Connection") { testConnection() }
                    if isLoading { ProgressView().scaleEffect(0.7) }
                    Text(connectionStatus)
                        .foregroundColor(connectionStatus.contains("Connected") ? .green : .red)
                        .font(.system(size: 11))
                }

                Text("Hype calls llama.cpp through its standard OpenAI-compatible streaming API at /v1/chat/completions. Default port: 8001.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }

            if aiProviderRaw == HypeAIProvider.zAI.rawValue || aiProviderRaw == HypeAIProvider.miniMax.rawValue {
                hostedOpenAICompatibleProviderSection
            }

            Section("Model") {
                if aiProviderRaw == HypeAIProvider.openAI.rawValue {
                    Picker("OpenAI Model", selection: $openAIModel) {
                        ForEach(HypeAIConfiguration.openAITextModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } else if aiProviderRaw == HypeAIProvider.zAI.rawValue {
                    Picker("Z.ai Model", selection: $zAIModel) {
                        let models = zAIAvailableModels.isEmpty ? HypeAIConfiguration.zAITextModels : zAIAvailableModels
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Button("Refresh Models") { fetchModels() }
                } else if aiProviderRaw == HypeAIProvider.miniMax.rawValue {
                    Picker("MiniMax Model", selection: $miniMaxModel) {
                        let models = miniMaxAvailableModels.isEmpty ? HypeAIConfiguration.miniMaxTextModels : miniMaxAvailableModels
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Button("Refresh Models") { fetchModels() }
                } else if aiProviderRaw == HypeAIProvider.llamaSwap.rawValue {
                    Picker("llama-swap Model", selection: $llamaSwapModel) {
                        if llamaSwapAvailableModels.isEmpty {
                            Text(llamaSwapModel).tag(llamaSwapModel)
                        }
                        ForEach(llamaSwapAvailableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Button("Refresh Models") { fetchModels() }
                } else if aiProviderRaw == HypeAIProvider.llamaCpp.rawValue {
                    Picker("llama.cpp Model", selection: $llamaCppModel) {
                        if llamaCppAvailableModels.isEmpty {
                            Text(llamaCppModel).tag(llamaCppModel)
                        }
                        ForEach(llamaCppAvailableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Button("Refresh Models") { fetchModels() }
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
                        .disabled(openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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

                Text("Used when the AI generates images for cards, backgrounds, or Asset Repository assets. This works even when Ollama is the selected chat provider.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hostedOpenAICompatibleProviderSection: some View {
        let isZAI = aiProviderRaw == HypeAIProvider.zAI.rawValue
        let title = isZAI ? "Z.ai" : "MiniMax"
        let baseURL = isZAI ? $zAIBaseURL : $miniMaxBaseURL
        let keyDraft = isZAI ? $zAIKeyDraft : $miniMaxKeyDraft
        let keyIsSet = isZAI ? zAIKeyIsSet : miniMaxKeyIsSet

        return Section("\(title) Connection") {
            TextField("Base URL", text: baseURL)

            if keyIsSet {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Token saved in Keychain")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.35), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                SecureField(
                    keyIsSet ? "Paste replacement API token" : "API token",
                    text: keyDraft
                )
                .textFieldStyle(.roundedBorder)

                Button("Save") { saveHostedProviderKey() }
                    .disabled(keyDraft.wrappedValue.isEmpty)

                if keyIsSet {
                    Button("Delete") { deleteHostedProviderKey() }
                        .foregroundColor(.red)
                }
            }

            HStack {
                Button("Test API + Streaming") { testHostedProviderStreaming() }
                    .disabled(isTestingHostedProvider || !keyIsSet)
                if isTestingHostedProvider { ProgressView().scaleEffect(0.7) }
                if !hostedProviderTestStatus.isEmpty {
                    Text(hostedProviderTestStatus)
                        .font(.system(size: 11))
                        .foregroundColor(hostedProviderTestStatus.hasPrefix("OK") ? .green : .red)
                }
            }

            Text("Uses the provider's OpenAI-compatible chat completions API for normal and streaming inference. Tokens are stored in Keychain, not UserDefaults.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var integrationSettings: some View {
        settingsForm {
            Section("Apple Music") {
                Toggle("Enable Apple Music in Hype", isOn: $appleMusicEnabled)
                    .help("Allow Hype to use MusicKit after the user authorizes Apple Music access.")

                Toggle("Enable for Current Stack", isOn: currentStackAppleMusicBinding)
                    .disabled(document == nil || !appleMusicEnabled)
                    .help("Allow this stack's scripts and AI tools to search or play Apple Music references.")

                Picker("Playback", selection: $appleMusicPlaybackEngine) {
                    Text("Hype app player").tag(AppleMusicPlaybackEngine.application.rawValue)
                }
                .disabled(!appleMusicEnabled)

                HStack {
                    Button("Authorize / Check") { checkAppleMusicAuthorization() }
                        .disabled(isCheckingAppleMusic || !appleMusicEnabled)
                    if isCheckingAppleMusic { ProgressView().scaleEffect(0.7) }
                    Text(appleMusicStatus)
                        .font(.system(size: 11))
                        .foregroundColor(appleMusicStatus.hasPrefix("OK") ? .green : .secondary)
                }

                Text("Apple Music items are stored as catalog or library references only. Hype-created AudioKit music can be embedded in the stack; protected Apple Music audio is never copied into the .hype file.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: - Meshy.ai section

            Section("Meshy.ai (3D model generation)") {
                Toggle("Enable for Current Stack", isOn: currentStackMeshyEnabledBinding)
                    .disabled(document == nil)
                    .help("Allow the AI assistant and the Asset Repository to generate 3D models using your Meshy.ai credits for this stack.")

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

    private var debugSettings: some View {
        settingsForm {
            Section("Debug Bridge") {
                Toggle("Enable debug socket", isOn: $debugEnabled)

                Text("The debug bridge exposes a Unix socket that external tools (like the MCP server) use to call Hype authoring tools. Enable to allow AI agents to control Hype.app.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                debugStatusRows
            }
        }
        .onAppear(perform: refreshDebugStatus)
        .onChange(of: debugEnabled) { _, _ in
            DispatchQueue.main.async {
                refreshDebugStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hypeDebugConnectionStatusDidChange)) { _ in
            refreshDebugStatus()
        }
    }

    private var debugStatusRows: some View {
        let status = debugStatus ?? HypeDebugServer.shared.status

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.isRunning ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)

                Text(status.isRunning ? "Running" : "Stopped")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                if status.activeConnectionCount > 0 {
                    Text("\(status.activeConnectionCount) connection\(status.activeConnectionCount == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            debugValueRow(
                title: "Instance link",
                value: status.instanceLink,
                copyValue: status.instanceLink,
                copyHelp: "Copy instance link"
            )

            debugValueRow(
                title: "Socket path",
                value: status.socketPath.isEmpty ? debugPendingSocketPathLabel : status.socketPath,
                copyValue: status.socketPath,
                copyHelp: "Copy socket path",
                copyDisabled: status.socketPath.isEmpty
            )

            debugValueRow(
                title: "Socket directory",
                value: status.discoveryDirectory.isEmpty ? debugSocketDirectoryLabel : status.discoveryDirectory,
                copyValue: status.discoveryDirectory,
                copyHelp: "Copy socket directory",
                copyDisabled: status.discoveryDirectory.isEmpty
            )
        }
    }

    private var debugPendingSocketPathLabel: String {
        let directory = debugSocketDirectoryLabel
        guard directory != "unavailable" else { return "unavailable" }
        return "\(directory)/\(ProcessInfo.processInfo.processIdentifier).sock"
    }

    private var debugSocketDirectoryLabel: String {
        (try? HypeDebugDirectory.socketDirectory().path) ?? "unavailable"
    }

    private func debugValueRow(
        title: String,
        value: String,
        copyValue: String,
        copyHelp: String,
        copyDisabled: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value.isEmpty ? "unavailable" : value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copyDebugValue(copyValue)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .disabled(copyDisabled || copyValue.isEmpty)
            .help(copyHelp)
        }
    }

    private func refreshDebugStatus() {
        debugStatus = HypeDebugServer.shared.status
    }

    private func copyDebugValue(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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

    private var currentStackAppleMusicBinding: Binding<Bool> {
        Binding(
            get: { document?.document.stack.appleMusicAllowed ?? false },
            set: { newValue in
                guard var wrapper = document else { return }
                wrapper.document.stack.appleMusicAllowed = newValue
                document = wrapper
            }
        )
    }

    private func checkAppleMusicAuthorization() {
        isCheckingAppleMusic = true
        appleMusicStatus = "Checking..."
        Task {
            let provider = AppleMusicProviderFactory.makeDefault()
            let status = await provider.requestAuthorization()
            let caps = await provider.capabilities()
            await MainActor.run {
                appleMusicStatus = status == .authorized
                    ? "OK: authorized, catalog playback=\(caps.canPlayCatalogContent)"
                    : "Apple Music: \(status.rawValue)"
                isCheckingAppleMusic = false
            }
        }
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
        let trimmedKey = openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        do {
            try KeychainStore.setSecret(trimmedKey, account: KeychainStore.openAIAPIKeyAccount)
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

    private func hasUsableSecret(account: String) -> Bool {
        guard let value = try? KeychainStore.getSecret(account: account) else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hostedProviderKeyAccount: String {
        aiProviderRaw == HypeAIProvider.zAI.rawValue
            ? KeychainStore.zAIAPIKeyAccount
            : KeychainStore.miniMaxAPIKeyAccount
    }

    private func saveHostedProviderKey() {
        let isZAI = aiProviderRaw == HypeAIProvider.zAI.rawValue
        let draft = isZAI ? zAIKeyDraft : miniMaxKeyDraft
        guard !draft.isEmpty else { return }
        do {
            try KeychainStore.setSecret(draft, account: hostedProviderKeyAccount)
            if isZAI {
                zAIKeyDraft = ""
                zAIKeyIsSet = true
            } else {
                miniMaxKeyDraft = ""
                miniMaxKeyIsSet = true
            }
            hostedProviderTestStatus = ""
        } catch {
            hostedProviderTestStatus = keychainErrorMessage(for: error)
        }
    }

    private func deleteHostedProviderKey() {
        do {
            try KeychainStore.deleteSecret(account: hostedProviderKeyAccount)
            if aiProviderRaw == HypeAIProvider.zAI.rawValue {
                zAIKeyIsSet = false
                zAIKeyDraft = ""
            } else {
                miniMaxKeyIsSet = false
                miniMaxKeyDraft = ""
            }
            hostedProviderTestStatus = ""
        } catch {
            hostedProviderTestStatus = keychainErrorMessage(for: error)
        }
    }

    private func testHostedProviderStreaming() {
        isTestingHostedProvider = true
        hostedProviderTestStatus = ""
        Task {
            do {
                let key = try KeychainStore.getSecret(account: hostedProviderKeyAccount)
                let isZAI = aiProviderRaw == HypeAIProvider.zAI.rawValue
                let rawBaseURL = isZAI ? zAIBaseURL : miniMaxBaseURL
                let model = isZAI ? zAIModel : miniMaxModel
                guard let baseURL = URL(string: rawBaseURL) else {
                    throw OpenAIChatCompletionsClient.StreamingError.invalidResponse
                }
                let client = OpenAIChatCompletionsClient(
                    configuration: .openAICompatible(
                        baseURL: baseURL,
                        apiKey: key,
                        model: model,
                        providerName: isZAI ? HypeAIProvider.zAI.rawValue : HypeAIProvider.miniMax.rawValue,
                        chatCompletionsPath: isZAI ? "chat/completions" : "v1/chat/completions",
                        modelListPath: isZAI ? "models" : "v1/models"
                    )
                )
                let inference = HypeAIClientChatInferenceProvider(client: client)
                let models = (try? await client.availableModels()) ?? []
                let response = try await inference.chat(AIChatInferenceRequest(
                    messages: [OllamaMessage(role: "user", content: "Reply with exactly: OK")],
                    tools: []
                ))
                let text = response.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else {
                    throw OpenAIChatCompletionsClient.StreamingError.invalidResponse
                }
                var streamed = ""
                for await token in inference.chatStream(AIChatInferenceRequest(
                    messages: [OllamaMessage(role: "user", content: "Reply with exactly: OK")],
                    tools: []
                )) {
                    streamed += token
                }
                await MainActor.run {
                    if !models.isEmpty {
                        if isZAI {
                            zAIAvailableModels = models
                        } else {
                            miniMaxAvailableModels = models
                        }
                    }
                    hostedProviderTestStatus = streamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Connection failed"
                        : models.isEmpty
                            ? "OK: API and streaming responded. Model list unavailable."
                            : "OK: \(models.count) model(s), API and streaming responded."
                    isTestingHostedProvider = false
                }
            } catch {
                await MainActor.run {
                    hostedProviderTestStatus = hostedProviderFailureMessage(for: error)
                    isTestingHostedProvider = false
                }
            }
        }
    }

    private func hostedProviderFailureMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return "Connection failed" }
        return "Connection failed: \(String(message.prefix(160)))"
    }

    private func saveLlamaSwapKey() {
        guard !llamaSwapKeyDraft.isEmpty else { return }
        do {
            try KeychainStore.setSecret(llamaSwapKeyDraft, account: KeychainStore.llamaSwapAPIKeyAccount)
            llamaSwapKeyDraft = ""
            llamaSwapKeyIsSet = true
            connectionStatus = ""
        } catch {
            connectionStatus = keychainErrorMessage(for: error)
        }
    }

    private func deleteLlamaSwapKey() {
        do {
            try KeychainStore.deleteSecret(account: KeychainStore.llamaSwapAPIKeyAccount)
            llamaSwapKeyIsSet = false
            llamaSwapKeyDraft = ""
            connectionStatus = ""
        } catch {
            connectionStatus = keychainErrorMessage(for: error)
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
            if aiProviderRaw == HypeAIProvider.llamaCpp.rawValue {
                do {
                    guard let baseURL = HypeAIConfiguration.localOpenAICompatibleBaseURL(host: llamaCppHost, port: llamaCppPort) else {
                        throw OpenAIChatCompletionsClient.StreamingError.invalidResponse
                    }
                    let client = OpenAIChatCompletionsClient(
                        configuration: .openAICompatible(
                            baseURL: baseURL,
                            model: llamaCppModel,
                            providerName: HypeAIProvider.llamaCpp.rawValue,
                            modelListPath: "v1/models"
                        )
                    )
                    let models = try await client.availableModels()
                    await MainActor.run {
                        llamaCppAvailableModels = models
                        if !models.isEmpty && !models.contains(llamaCppModel) {
                            llamaCppModel = models[0]
                        }
                        connectionStatus = "Connected"
                        isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        connectionStatus = "Error: \(error.localizedDescription)"
                        isLoading = false
                    }
                }
                return
            }

            if aiProviderRaw == HypeAIProvider.llamaSwap.rawValue {
                do {
                    let apiKey = try? KeychainStore.getSecret(account: KeychainStore.llamaSwapAPIKeyAccount)
                    let client = try LlamaSwapClient(
                        host: llamaSwapHost,
                        port: llamaSwapPort,
                        model: llamaSwapModel,
                        apiKey: apiKey,
                        timeouts: .init(request: 20, resource: 20)
                    )
                    let models = try await client.availableModels()
                    await MainActor.run {
                        llamaSwapAvailableModels = models
                        if !models.isEmpty && !models.contains(llamaSwapModel) {
                            llamaSwapModel = models[0]
                        }
                        connectionStatus = "Connected"
                        isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        connectionStatus = "Error: \(error.localizedDescription)"
                        isLoading = false
                    }
                }
                return
            }

            do {
                let client = OllamaToolClient(
                    host: ollamaHost,
                    port: ollamaPort,
                    model: ollamaModel,
                    timeouts: .quick
                )
                let models = try await client.availableModels()
                await MainActor.run {
                    availableModels = models
                    if !models.isEmpty && !models.contains(ollamaModel) {
                        ollamaModel = models[0]
                    }
                    connectionStatus = "Connected"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = "Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func testOllamaProviderDiagnostics() {
        isTestingOllamaDiagnostics = true
        ollamaDiagnosticsStatus = ""
        Task {
            let nativeClient = OllamaToolClient(
                host: ollamaHost,
                port: ollamaPort,
                model: ollamaModel,
                timeouts: .chat
            )
            let inferenceClient = OpenAIChatCompletionsClient(
                configuration: .ollama(host: ollamaHost, port: ollamaPort, model: ollamaModel)
            )
            let inference = HypeAIClientChatInferenceProvider(client: inferenceClient)
            do {
                let result = try await OllamaProviderDiagnostics().run(
                    nativeClient: nativeClient,
                    inferenceProvider: inference,
                    modelName: ollamaModel
                )
                await MainActor.run {
                    availableModels = result.models
                    ollamaDiagnosticsStatus = result.summary
                    isTestingOllamaDiagnostics = false
                }
            } catch {
                await MainActor.run {
                    ollamaDiagnosticsStatus = "Connection failed"
                    isTestingOllamaDiagnostics = false
                }
            }
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
        if aiProviderRaw == HypeAIProvider.llamaCpp.rawValue {
            Task {
                do {
                    guard let baseURL = HypeAIConfiguration.localOpenAICompatibleBaseURL(host: llamaCppHost, port: llamaCppPort) else { return }
                    let client = OpenAIChatCompletionsClient(
                        configuration: .openAICompatible(
                            baseURL: baseURL,
                            model: llamaCppModel,
                            providerName: HypeAIProvider.llamaCpp.rawValue,
                            modelListPath: "v1/models"
                        )
                    )
                    let models = try await client.availableModels()
                    await MainActor.run {
                        llamaCppAvailableModels = models
                        if !models.isEmpty && !models.contains(llamaCppModel) {
                            llamaCppModel = models[0]
                        }
                    }
                } catch {
                    // Silently fail -- models stay empty until user refreshes.
                }
            }
            return
        }

        if aiProviderRaw == HypeAIProvider.llamaSwap.rawValue {
            Task {
                do {
                    let apiKey = try? KeychainStore.getSecret(account: KeychainStore.llamaSwapAPIKeyAccount)
                    let client = try LlamaSwapClient(
                        host: llamaSwapHost,
                        port: llamaSwapPort,
                        model: llamaSwapModel,
                        apiKey: apiKey,
                        timeouts: .init(request: 20, resource: 20)
                    )
                    let models = try await client.availableModels()
                    await MainActor.run {
                        llamaSwapAvailableModels = models
                        if !models.isEmpty && !models.contains(llamaSwapModel) {
                            llamaSwapModel = models[0]
                        }
                    }
                } catch {
                    // Silently fail -- models stay empty until user refreshes
                }
            }
            return
        }

        if aiProviderRaw == HypeAIProvider.zAI.rawValue || aiProviderRaw == HypeAIProvider.miniMax.rawValue {
            Task {
                let isZAI = aiProviderRaw == HypeAIProvider.zAI.rawValue
                let account = isZAI ? KeychainStore.zAIAPIKeyAccount : KeychainStore.miniMaxAPIKeyAccount
                do {
                    let key = try KeychainStore.getSecret(account: account)
                    let rawBaseURL = isZAI ? zAIBaseURL : miniMaxBaseURL
                    guard let baseURL = URL(string: rawBaseURL) else { return }
                    let client = OpenAIChatCompletionsClient(
                        configuration: .openAICompatible(
                            baseURL: baseURL,
                            apiKey: key,
                            model: isZAI ? zAIModel : miniMaxModel,
                            providerName: isZAI ? HypeAIProvider.zAI.rawValue : HypeAIProvider.miniMax.rawValue,
                            chatCompletionsPath: isZAI ? "chat/completions" : "v1/chat/completions",
                            modelListPath: isZAI ? "models" : "v1/models"
                        )
                    )
                    let models = try await client.availableModels()
                    await MainActor.run {
                        if isZAI {
                            zAIAvailableModels = models
                            if !models.isEmpty && !models.contains(zAIModel) {
                                zAIModel = models[0]
                            }
                        } else {
                            miniMaxAvailableModels = models
                            if !models.isEmpty && !models.contains(miniMaxModel) {
                                miniMaxModel = models[0]
                            }
                        }
                    }
                } catch {
                    // Silently fail -- provider models stay at defaults until user refreshes with a valid token.
                }
            }
            return
        }

        guard aiProviderRaw == HypeAIProvider.ollama.rawValue else { return }
        Task {
            do {
                let client = OllamaToolClient(
                    host: ollamaHost,
                    port: ollamaPort,
                    model: ollamaModel,
                    timeouts: .quick
                )
                let models = try await client.availableModels()
                await MainActor.run {
                    availableModels = models
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

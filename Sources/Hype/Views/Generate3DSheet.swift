import SwiftUI
import HypeCore

// MARK: - Generate3DSheet

/// A SwiftUI sheet for generating a 3D model from a text prompt using Meshy.ai.
///
/// Security invariants:
/// - The sheet DOES NOT auto-submit on first paint. `generate()` is only
///   invoked by an explicit `Button("Generate")` press (invariant 17).
/// - The monitor is stored as `@State` and cancelled on `.onDisappear`.
/// - Gate is re-checked at `generate()` call time as belt-and-suspenders.
///
/// UX invariant (OQ4): when the user cancels before the POST returns,
/// a warning banner is shown: "Task may have been created on Meshy.
/// Check your dashboard." Credits may have been spent.
struct Generate3DSheet: View {
    @Binding var document: HypeDocumentWrapper
    /// When set, the primary imported asset's ref is written into this part.
    var targetPartId: UUID?
    /// Called on success with the freshly-imported primary `AssetRef`.
    var onAssetImported: ((AssetRef) -> Void)?
    /// Called when the sheet should be dismissed.
    var onDismiss: () -> Void

    // MARK: - Form state

    @State private var prompt: String = ""
    @State private var aiModel: MeshyAIModel = .meshy6
    @State private var artStyle: MeshyArtStyle = .realistic
    @State private var primaryFormat: MeshyOutputFormat = .glb
    @State private var alsoDownloadUSDZ: Bool = false
    @State private var alsoDownloadFBX: Bool = false
    @State private var polycount: Double = 30_000
    @State private var shouldRemesh: Bool = false

    // MARK: - Runtime state

    @State private var phase: Phase = .form
    @State private var monitor: MeshyTaskMonitor?
    @State private var generateTask: Task<Void, Never>?
    @State private var balance: Int?
    @State private var balanceLoading: Bool = false
    @State private var meshyKeyIsSet: Bool = false
    @State private var earlyCancel: Bool = false  // OQ4 warning flag

    enum Phase: Equatable {
        case form
        case submitting
        case progress(percent: Int)
        case importing
        case error(MeshyError)
        case done
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generate 3D Model")
                    .font(.headline)
                Spacer()
                // Balance display
                if let balance {
                    Text("\(balance) credits")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if balanceLoading {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .padding()

            Divider()

            // Main content
            switch phase {
            case .form:
                formContent
            case .submitting:
                progressContent(label: "Submitting…", percent: 0)
            case .progress(let percent):
                progressContent(label: "Generating… \(percent)%", percent: percent)
            case .importing:
                progressContent(label: "Importing model…", percent: 100)
            case .error(let err):
                errorContent(err)
            case .done:
                doneContent
            }
        }
        .frame(width: 540, height: 480)
        .onAppear {
            meshyKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
            Task { await refreshBalance() }
        }
        .onDisappear {
            generateTask?.cancel()
            Task { await monitor?.cancel() }
        }
    }

    // MARK: - Form

    @ViewBuilder
    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Prompt
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt (describe your 3D model)")
                        .font(.system(size: 11))
                    TextEditor(text: $prompt)
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        .onChange(of: prompt) { _, newValue in
                            // Cap at 600 chars (Meshy limit).
                            if newValue.count > 600 {
                                prompt = String(newValue.prefix(600))
                            }
                        }
                    Text("\(prompt.count)/600 characters")
                        .font(.system(size: 9))
                        .foregroundColor(prompt.count > 550 ? .orange : .secondary)
                }

                // Model + Art Style row
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Model").font(.system(size: 11))
                        Picker("", selection: $aiModel) {
                            ForEach(MeshyAIModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: aiModel) { _, newModel in
                            shouldRemesh = newModel.defaultRemesh
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Art Style").font(.system(size: 11))
                        Picker("", selection: $artStyle) {
                            ForEach(MeshyArtStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                // Additional formats
                VStack(alignment: .leading, spacing: 4) {
                    Text("Additional Formats").font(.system(size: 11))
                    Toggle("Also download USDZ (AR-ready)", isOn: $alsoDownloadUSDZ)
                        .font(.system(size: 11))
                    Toggle("Also download FBX (experimental — higher attack surface than GLB/USDZ)", isOn: $alsoDownloadFBX)
                        .font(.system(size: 11))
                }

                // Remesh toggle
                Toggle("Remesh geometry", isOn: $shouldRemesh)
                    .font(.system(size: 11))

                // Disclosure
                Text("Prompts are sent to api.meshy.ai using your Meshy.ai credits. The generated model is downloaded over HTTPS and embedded in this document.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }

        Divider()

        // Bottom buttons
        HStack {
            Button("Cancel") { onDismiss() }
            Spacer()
            Button("Generate") {
                generateTask = Task { await generate() }
            }
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !meshyKeyIsSet)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Progress

    @ViewBuilder
    private func progressContent(label: String, percent: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: Double(percent), total: 100)
                .frame(width: 300)
            Text(label)
                .font(.system(size: 13))

            // OQ4: show warning if there was an early cancel without a task id
            if earlyCancel {
                Text("Task may have been created on Meshy. Check your dashboard.")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            Spacer()
            Button("Cancel") {
                generateTask?.cancel()
                Task { await monitor?.cancel() }
                // If in submitting phase, we might not have a task id yet.
                if case .submitting = phase { earlyCancel = true }
                phase = .form
            }
        }
        .padding()
    }

    // MARK: - Error

    @ViewBuilder
    private func errorContent(_ error: MeshyError) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.red)
            Text(error.errorDescription ?? "An error occurred.")
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
                .padding(.horizontal)
            Spacer()
            HStack {
                Button("Close") { onDismiss() }
                Button("Retry") { phase = .form }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Done

    @ViewBuilder
    private var doneContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)
            Text("3D model generated and added to the repository.")
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
            Text("Save the document to keep the generated model.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func generate() async {
        // Belt-and-suspenders gate check (invariant 21).
        guard Meshy3DGate.status(for: document.document, keyIsSet: meshyKeyIsSet) == .ready else {
            await MainActor.run {
                phase = .error(.validationFailed(field: "stack", reason: "Meshy is not enabled for this stack. Enable it in Preferences → Meshy.ai."))
            }
            return
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            await MainActor.run {
                phase = .error(.validationFailed(field: "prompt", reason: "Enter a prompt before generating."))
            }
            return
        }

        await MainActor.run { phase = .submitting }

        do {
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
            let client = MeshyAIClient(apiKey: apiKey)

            var formats: Set<MeshyOutputFormat> = [.glb]
            if alsoDownloadUSDZ { formats.insert(.usdz) }
            if alsoDownloadFBX { formats.insert(.fbx) }

            let request = MeshyTextTo3DRequest(
                mode: .preview,
                prompt: String(trimmedPrompt.prefix(600)),
                artStyle: artStyle,
                aiModel: aiModel,
                shouldRemesh: shouldRemesh,
                moderation: true
            )

            let taskId = try await client.createTextTo3DTask(request)

            let taskMonitor = MeshyTaskMonitor(
                client: client,
                taskId: taskId,
                prompt: trimmedPrompt,
                aiModel: aiModel,
                requestedFormats: formats
            )
            await MainActor.run { monitor = taskMonitor }

            for await state in await taskMonitor.progress() {
                // Check for cooperative cancellation.
                if Task.isCancelled { break }

                switch state {
                case .pending:
                    await MainActor.run { phase = .progress(percent: 0) }
                case .inProgress(let percent):
                    await MainActor.run { phase = .progress(percent: percent) }
                case .succeeded(let result):
                    await MainActor.run { phase = .importing }
                    await handleSuccess(result, client: client)
                    return
                case .failed(let error):
                    await MainActor.run { phase = .error(error) }
                    return
                case .cancelled:
                    await MainActor.run { phase = .form }
                    return
                }
            }

        } catch let error as MeshyError {
            await MainActor.run { phase = .error(error) }
        } catch KeychainStoreError.itemNotFound {
            await MainActor.run { phase = .error(.noAPIKey) }
        } catch {
            await MainActor.run { phase = .error(.networkError) }
        }
    }

    @MainActor
    private func handleSuccess(_ result: MeshyTaskResult, client: MeshyAIClient) async {
        do {
            let importer = Meshy3DAssetImporter(client: client)
            let existingNames = Set(document.document.spriteRepository.assets.map(\.name))
            let assets = try await importer.importTask(result: result, existingAssetNames: existingNames)

            // Write via the document binding — triggers autosave and undo.
            for asset in assets {
                document.document.spriteRepository.addAsset(asset)
            }

            // Surface the primary GLB to the caller. When `targetPartId` is
            // set, the caller's `onAssetImported` closure is the SOLE writer
            // of `part.scene3DAssetRef` — we deliberately don't write here
            // (security F-1: avoid double-mutation that produces two undo
            // entries and racey observer notifications).
            if let primary = assets.first {
                let ref = document.document.spriteRepository.assetRef(for: primary)
                onAssetImported?(ref)
            }

            phase = .done
        } catch let error as MeshyError {
            phase = .error(error)
        } catch {
            phase = .error(.networkError)
        }
    }

    private func refreshBalance() async {
        guard meshyKeyIsSet else { return }
        await MainActor.run { balanceLoading = true }
        do {
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
            let client = MeshyAIClient(apiKey: apiKey)
            let bal = try await client.fetchBalance()
            await MainActor.run {
                balance = bal
                balanceLoading = false
            }
        } catch {
            await MainActor.run { balanceLoading = false }
        }
    }
}

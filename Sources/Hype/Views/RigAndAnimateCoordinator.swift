import SwiftUI
import HypeCore

// MARK: - RigAndAnimateCoordinator

/// Coordinator view for the full Rig + (optional) Animate flow.
///
/// Presented as a sheet from `AssetRepositoryView` when the user taps
/// "Rig & Animate…" on a `.model3D` asset. Owns the progress / picker /
/// progress / done state machine and the background `Task` that drives
/// `RigAndAnimateFlow`.
///
/// Phase state machine:
///   `.preflight`          — validating source has a Meshy task id, fetching balance.
///   `.rigging(percent)`   — `RigAndAnimateFlow.runRigging` in flight.
///   `.picking`            — `AnimationPickerView` is displayed so the user can
///                           choose an action. The rig result sits in
///                           `pendingRigTaskId`.
///   `.animating(percent)` — `RigAndAnimateFlow.runAnimation` in flight.
///   `.done`               — all assets are in the repository; ready to dismiss.
///   `.error(MeshyError)`  — terminal failure; the user can dismiss.
///
/// Security:
///   - `flowTask?.cancel()` is called whenever the sheet is dismissed (via
///     `onDismiss` path or the Cancel button) so in-flight network requests
///     are cancelled and no orphan Tasks are left running (security addendum).
///   - Keychain reads are done via `Task.detached(priority: .userInitiated)`
///     in `runFlow` to avoid synchronous SecItem calls on the main thread
///     (security M3 pattern, matching `LiveMeshyScriptingProvider`).
struct RigAndAnimateCoordinator: View {

    // MARK: - Inputs

    @Binding var document: HypeDocumentWrapper
    /// The source `.model3D` asset to rig. Must have a Meshy task id in
    /// its `provenance.attribution.taskId`. The coordinator validates this
    /// in `.preflight` before kicking off the network flow.
    let sourceAsset: Asset
    /// Called when the sheet should be dismissed. The caller is responsible
    /// for clearing the sheet binding.
    var onDismiss: () -> Void
    /// Called with the ids of all newly-imported assets so the repository
    /// view can re-select them.
    var onAssetsImported: (([UUID]) -> Void)?

    // MARK: - State

    @State private var phase: Phase = .preflight
    /// Handle for the active background flow task. Cancelled on dismiss.
    @State private var flowTask: Task<Void, Never>?
    /// Rigging task id captured after `runRigging` completes. Threaded
    /// into `runAnimation` if the user picks an animation.
    @State private var pendingRigTaskId: String?
    /// Rigged assets (base rig + optional basic walk/run clips).
    @State private var riggedAssets: [Asset] = []
    /// Whether the Meshy API key is present in the Keychain.
    @State private var meshyKeyIsSet: Bool = false
    /// Optional credit balance fetched at startup (cosmetic only).
    @State private var balance: Int?

    // MARK: - Phase

    enum Phase: Equatable {
        case preflight
        case rigging(percent: Int)
        case picking
        case animating(percent: Int)
        case done
        case error(MeshyError)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Text("Rig & Animate")
                    .font(.headline)
                Spacer()
                if let balance {
                    Text("\(balance) credits")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            // Main content region
            Group {
                switch phase {
                case .preflight:
                    preflightView

                case .rigging(let percent):
                    progressView(
                        label: percent == 0 ? "Submitting rig request…" : "Rigging… \(percent)%",
                        systemImage: "person.bust",
                        percent: percent
                    )

                case .picking:
                    // Inner sheet overlay: AnimationPickerView is presented
                    // as a full-view replacement inside the coordinator's
                    // window so it fits within the existing sheet frame.
                    AnimationPickerView(
                        onPick: { entry in
                            handlePick(entry)
                        },
                        onCancel: {
                            // Cancel the entire flow and close.
                            cancelAndDismiss()
                        }
                    )

                case .animating(let percent):
                    progressView(
                        label: percent == 0 ? "Submitting animation request…" : "Animating… \(percent)%",
                        systemImage: "figure.run",
                        percent: percent
                    )

                case .done:
                    doneView

                case .error(let err):
                    errorView(err)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer — hidden during the picking phase because
            // AnimationPickerView supplies its own footer buttons.
            if case .picking = phase {
                EmptyView()
            } else {
                Divider()
                footerButtons
            }
        }
        .frame(width: 540, height: 480)
        .onAppear {
            // Security (Phase 3 Defect 1, mirroring addendum M3): the
            // synchronous `SecItemCopyMatching` underlying `hasSecret`
            // can briefly block (locked keychain, iCloud sync). Probe
            // off the main thread so a slow lookup never janks the
            // sheet's render or hits the watchdog.
            Task.detached(priority: .userInitiated) {
                let keyIsSet = KeychainStore.hasSecret(
                    account: KeychainStore.meshyAPIKeyAccount
                )
                await MainActor.run {
                    meshyKeyIsSet = keyIsSet
                    startFlow()
                }
            }
        }
        .onDisappear {
            // Security addendum: cancel in-flight network work when the
            // sheet disappears for any reason (window close, escape key, etc.)
            flowTask?.cancel()
        }
    }

    // MARK: - Preflight view

    @ViewBuilder
    private var preflightView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress view

    @ViewBuilder
    private func progressView(label: String, systemImage: String, percent: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
            Text(label)
                .font(.system(size: 13))
            ProgressView(value: Double(percent), total: 100)
                .progressViewStyle(.linear)
                .frame(width: 280)
            Text("This may take several minutes.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Done view

    @ViewBuilder
    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)
            Text("Assets added to the Asset Repository.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
            Text("The imported models are embedded in this stack and autosaved.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Error view

    @ViewBuilder
    private func errorView(_ error: MeshyError) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.red)
            Text("Rig & Animate failed")
                .font(.headline)
            Text(error.errorDescription ?? "An unexpected error occurred.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Footer buttons

    @ViewBuilder
    private var footerButtons: some View {
        HStack {
            // Cancel / Close button — label shifts to "Close" once done.
            Button(isDone ? "Close" : "Cancel") {
                cancelAndDismiss()
            }
            Spacer()
        }
        .padding()
    }

    private var isDone: Bool {
        if case .done = phase { return true }
        if case .error = phase { return true }
        return false
    }

    // MARK: - Flow entry point

    private func startFlow() {
        flowTask = Task {
            await runFlow()
        }
    }

    // MARK: - Main async flow

    @MainActor
    private func runFlow() async {
        // Step 1: Preflight validation.
        guard let provenance = sourceAsset.provenance,
              !provenance.attribution.taskId.isEmpty
        else {
            phase = .error(.validationFailed(
                field: "sourceAsset",
                reason: "This 3D model doesn't have a Meshy task id in its provenance. Only models generated by Meshy can be rigged."
            ))
            return
        }

        guard provenance.attribution.providerIdentifier == "meshy" else {
            phase = .error(.validationFailed(
                field: "sourceAsset",
                reason: "Rigging is only supported for models generated by Meshy.ai."
            ))
            return
        }

        let sourceTaskId = provenance.attribution.taskId

        // Step 2: Gate check (main thread — Keychain.hasSecret is sync-safe here
        // because it is only a SecItemCopyMatching probe, not a lengthy operation,
        // and we're already on the main actor).
        let gate = Meshy3DGate.status(for: document.document, keyIsSet: meshyKeyIsSet)
        guard gate == .ready else {
            switch gate {
            case .apiKeyMissing:
                phase = .error(.noAPIKey)
            case .stackDisabled:
                phase = .error(.validationFailed(
                    field: "meshy",
                    reason: "Meshy is not enabled for this stack."
                ))
            case .ready:
                break
            }
            return
        }

        // Step 3: Fetch API key off main thread (security M3).
        let apiKey: String
        do {
            apiKey = try await Task.detached(priority: .userInitiated) {
                try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
            }.value
        } catch {
            phase = .error(.noAPIKey)
            return
        }

        // Step 4: Optionally refresh balance (best-effort; failure is silenced).
        let client = MeshyAIClient(apiKey: apiKey)
        if let bal = try? await client.fetchBalance() {
            balance = bal
        }

        // Step 5: Rigging stage.
        phase = .rigging(percent: 0)
        let existingNames = Set(document.document.assetRepository.assets.map(\.name))
        let flow = RigAndAnimateFlow(client: client)
        let riggingResult: (assets: [Asset], rigTaskId: String)
        do {
            riggingResult = try await flow.runRigging(
                sourceTaskId: sourceTaskId,
                sourceAssetName: sourceAsset.name,
                options: RigAndAnimateFlow.RiggingOptions(),
                existingAssetNames: existingNames,
                onProgress: { [self] state in
                    await MainActor.run {
                        switch state {
                        case .pending:
                            phase = .rigging(percent: 0)
                        case .inProgress(let pct):
                            phase = .rigging(percent: pct)
                        case .succeeded, .failed, .cancelled:
                            break
                        }
                    }
                }
            )
        } catch is CancellationError {
            // Task was cancelled (user closed the sheet). Do nothing —
            // `onDisappear` has already cleaned up.
            return
        } catch let err as MeshyError {
            phase = .error(err)
            return
        } catch {
            phase = .error(.networkError)
            return
        }

        // Step 6: Install rigged assets into the document and surface for selection.
        for asset in riggingResult.assets {
            document.document.assetRepository.addAsset(asset)
        }
        HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
        onAssetsImported?(riggingResult.assets.map(\.id))

        // Step 7: Store rig context and move to the picking phase.
        pendingRigTaskId = riggingResult.rigTaskId
        riggedAssets = riggingResult.assets
        phase = .picking
        // Control returns here after the user picks (or skips) from
        // AnimationPickerView — handlePick(_:) drives the next step.
    }

    // MARK: - Animation continuation

    /// Called by `AnimationPickerView.onPick`.
    ///
    /// - Parameter entry: The picked animation, or `nil` when the user
    ///   chose "Skip animation" (keep just the rigged base model).
    private func handlePick(_ entry: MeshyAnimationEntry?) {
        guard let entry else {
            // Skip animation — the rigged assets are already in the
            // repository (installed in Step 6 above). Mark done.
            phase = .done
            return
        }

        guard let rigTaskId = pendingRigTaskId else {
            // Defensive guard — should never happen if the state machine
            // is correct: `pendingRigTaskId` is set in Step 7 before
            // transitioning to .picking.
            phase = .error(.validationFailed(
                field: "rigTaskId",
                reason: "Internal error: rig task id was lost before animation could start."
            ))
            return
        }

        // Launch animation as a new sub-task. The outer `flowTask` is
        // already complete at this point, so we create a fresh one.
        flowTask = Task {
            await runAnimation(
                rigTaskId: rigTaskId,
                entry: entry
            )
        }
    }

    /// Animation stage — runs after the user picks an action from the picker.
    @MainActor
    private func runAnimation(rigTaskId: String, entry: MeshyAnimationEntry) async {
        phase = .animating(percent: 0)

        // Re-fetch API key (belt-and-suspenders; it was fetched once in
        // runFlow, but the sheet can be long-lived and keys may change).
        let apiKey: String
        do {
            apiKey = try await Task.detached(priority: .userInitiated) {
                try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
            }.value
        } catch {
            phase = .error(.noAPIKey)
            return
        }

        let client = MeshyAIClient(apiKey: apiKey)
        let flow = RigAndAnimateFlow(client: client)
        let existingNames = Set(document.document.assetRepository.assets.map(\.name))

        do {
            let animatedAsset = try await flow.runAnimation(
                rigTaskId: rigTaskId,
                actionId: entry.id,
                actionName: entry.name,
                sourceAssetName: sourceAsset.name,
                options: RigAndAnimateFlow.AnimationOptions(),
                existingAssetNames: existingNames,
                onProgress: { [self] state in
                    await MainActor.run {
                        switch state {
                        case .pending:
                            phase = .animating(percent: 0)
                        case .inProgress(let pct):
                            phase = .animating(percent: pct)
                        case .succeeded, .failed, .cancelled:
                            break
                        }
                    }
                }
            )
            document.document.assetRepository.addAsset(animatedAsset)
            HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
            onAssetsImported?([animatedAsset.id])
            phase = .done

        } catch is CancellationError {
            return
        } catch let err as MeshyError {
            phase = .error(err)
        } catch {
            phase = .error(.networkError)
        }
    }

    // MARK: - Cancel helper

    private func cancelAndDismiss() {
        flowTask?.cancel()
        onDismiss()
    }
}

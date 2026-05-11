import Foundation
import HypeCore

// MARK: - LiveMeshyScriptingProvider

/// Production implementation of `MeshyScriptingProvider`.
///
/// Lives in the `Hype` module (not `HypeCore`) because it reads from the Keychain
/// (which is permissible only in the app target on macOS) and broadcasts document
/// mutations via the same `stackRuntimeDocumentDidChange` notification that the
/// `StackRuntime` actor uses.
///
/// Threading contract:
/// - `generateSync` may be called from any async context (typically a `Task`
///   spawned inside `StackRuntime.startMeshyRequest`).
/// - Keychain reads are wrapped in `Task.detached` per security invariant M3
///   (avoid blocking the main thread with synchronous SecItem calls).
/// - After `Generate3DJob.run` completes, assets are installed into the live
///   document by posting `Notification.Name.stackRuntimeDocumentDidChange` with
///   the modified document snapshot. `MainContentView.body` listens on this
///   notification and routes the update back into the SwiftUI `@Binding` chain.
public struct LiveMeshyScriptingProvider: MeshyScriptingProvider {

    public init() {}

    /// Run a text-to-3D generation and install the result into the live document.
    ///
    /// Security (M3): Keychain reads happen in `Task.detached(priority: .userInitiated)`
    /// to avoid synchronous SecItem calls blocking the main thread.
    ///
    /// - Returns: The new asset's name (e.g. "a-wooden-barrel.glb").
    /// - Throws: `MeshyError` on gate refusal, API error, or empty prompt.
    public func generateSync(
        prompt: String,
        style: String?,
        model: String?,
        document: HypeDocument
    ) async throws -> String {

        // Step 1: Gate check (Keychain read off main thread — security M3).
        let keyIsSet = await Task.detached(priority: .userInitiated) {
            KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
        }.value

        let gate = Meshy3DGate.status(for: document, keyIsSet: keyIsSet)
        switch gate {
        case .stackDisabled:
            throw MeshyError.validationFailed(
                field: "meshy",
                reason: "Meshy is not enabled for this stack."
            )
        case .apiKeyMissing:
            throw MeshyError.noAPIKey
        case .ready:
            break
        }

        // Step 2: Fetch API key (Keychain read off main thread — security M3).
        let apiKey = try await Task.detached(priority: .userInitiated) {
            try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
        }.value

        // Step 3: Parse style / model with safe defaults.
        let artStyle: MeshyArtStyle = {
            switch style?.lowercased() {
            case "sculpture": return .sculpture
            default:          return .realistic
            }
        }()
        let aiModel = model.flatMap { MeshyAIModel(rawValue: $0) } ?? .meshy6

        // Step 4: Run the generation job.
        let client = MeshyAIClient(apiKey: apiKey)
        let job = Generate3DJob(client: client)
        let options = Generate3DJob.Options(
            aiModel: aiModel,
            shouldRemesh: aiModel.defaultRemesh,
            alsoUSDZ: false,
            alsoFBX: false,
            hardTimeout: 1800
        )
        let existingNames = Set(document.spriteRepository.assets.map(\.name))
        let assets = try await job.run(
            kind: .text(prompt: prompt, artStyle: artStyle),
            options: options,
            existingAssetNames: existingNames
        )

        guard let primary = assets.first else {
            throw MeshyError.invalidResponse
        }

        // Step 5: Install assets into the live document via the runtime's
        // notification channel (security OQ-C3: exactly one mutation per
        // generation — this IS the one mutation; StackRuntime must NOT mutate again).
        var modifiedDocument = document
        for asset in assets {
            modifiedDocument.spriteRepository.addAsset(asset)
        }
        let stackId = document.stack.id
        await MainActor.run {
            NotificationCenter.default.post(
                name: .stackRuntimeDocumentDidChange,
                object: nil,
                userInfo: [
                    "stackId": stackId,
                    "document": modifiedDocument,
                ]
            )
        }

        return primary.name
    }

    /// Remesh an existing repository asset and install the result into the live document.
    ///
    /// **Security (C9):** Keychain reads are wrapped in `Task.detached(priority: .userInitiated)`.
    /// **Security (C8):** exactly one mutation — this method installs; StackRuntime must not re-mutate.
    ///
    /// - Throws: `MeshyError.unsupportedSource` if the source has no Meshy task id.
    /// - Returns: The new asset's name.
    public func remeshSync(
        sourceAssetName: String,
        targetPolycount: Int,
        document: HypeDocument
    ) async throws -> String {

        // Step 1: Gate check (Keychain read off main thread — security C9).
        let keyIsSet = await Task.detached(priority: .userInitiated) {
            KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
        }.value

        let gate = Meshy3DGate.status(for: document, keyIsSet: keyIsSet)
        switch gate {
        case .stackDisabled:
            throw MeshyError.validationFailed(
                field: "meshy",
                reason: "Meshy is not enabled for this stack."
            )
        case .apiKeyMissing:
            throw MeshyError.noAPIKey
        case .ready:
            break
        }

        // Step 2: Find source asset and validate it has a Meshy task id.
        guard let sourceAsset = document.spriteRepository.assets.first(where: { $0.name == sourceAssetName }) else {
            throw MeshyError.unsupportedSource(operation: "remesh", assetName: sourceAssetName)
        }
        let sourceTaskId = sourceAsset.provenance?.attribution.taskId ?? ""
        guard !sourceTaskId.isEmpty,
              sourceAsset.provenance?.attribution.providerIdentifier == "meshy" else {
            throw MeshyError.unsupportedSource(operation: "remesh", assetName: sourceAssetName)
        }
        let sourcePrompt = sourceAsset.provenance?.searchQuery ?? ""

        // Step 3: Fetch API key (Keychain read off main thread — security C9).
        let apiKey = try await Task.detached(priority: .userInitiated) {
            try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
        }.value

        // Step 4: Run the remesh flow.
        let client = MeshyAIClient(apiKey: apiKey)
        let flow = RemeshAndRetextureFlow(client: client)
        let options = RemeshAndRetextureFlow.RemeshOptions(
            targetPolycount: targetPolycount,
            hardTimeout: 1800
        )
        let existingNames = Set(document.spriteRepository.assets.map(\.name))
        let asset = try await flow.runRemesh(
            sourceTaskId: sourceTaskId,
            sourceAssetName: sourceAssetName,
            sourcePrompt: sourcePrompt,
            options: options,
            existingAssetNames: existingNames
        )

        // Step 5: Install asset into the live document via the runtime's notification channel.
        // Security (C8): exactly one mutation — this IS the mutation; StackRuntime must not re-mutate.
        var modifiedDocument = document
        modifiedDocument.spriteRepository.addAsset(asset)
        let stackId = document.stack.id
        await MainActor.run {
            NotificationCenter.default.post(
                name: .stackRuntimeDocumentDidChange,
                object: nil,
                userInfo: [
                    "stackId": stackId,
                    "document": modifiedDocument,
                ]
            )
        }

        return asset.name
    }

    /// Retexture an existing repository asset and install the result into the live document.
    ///
    /// **Security (C9):** Keychain reads are wrapped in `Task.detached(priority: .userInitiated)`.
    /// **Security (C8):** exactly one mutation — this method installs; StackRuntime must not re-mutate.
    ///
    /// - Throws: `MeshyError.unsupportedSource` if the source has no Meshy task id.
    /// - Throws: `MeshyError.validationFailed` if `stylePrompt` is empty.
    /// - Returns: The new asset's name.
    public func retextureSync(
        sourceAssetName: String,
        stylePrompt: String,
        document: HypeDocument
    ) async throws -> String {

        // Fail-fast empty-prompt guard (Phase 4 M1). The eventual
        // client-layer check at `createRetextureTask` catches this too,
        // but only after two Keychain reads and a gate check have run.
        // Synchronous reject before any async work avoids that latency.
        let trimmedPrompt = stylePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw MeshyError.validationFailed(
                field: "style_prompt",
                reason: "Style prompt must not be empty."
            )
        }

        // Step 1: Gate check (Keychain read off main thread — security C9).
        let keyIsSet = await Task.detached(priority: .userInitiated) {
            KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
        }.value

        let gate = Meshy3DGate.status(for: document, keyIsSet: keyIsSet)
        switch gate {
        case .stackDisabled:
            throw MeshyError.validationFailed(
                field: "meshy",
                reason: "Meshy is not enabled for this stack."
            )
        case .apiKeyMissing:
            throw MeshyError.noAPIKey
        case .ready:
            break
        }

        // Step 2: Find source asset and validate it has a Meshy task id.
        guard let sourceAsset = document.spriteRepository.assets.first(where: { $0.name == sourceAssetName }) else {
            throw MeshyError.unsupportedSource(operation: "retexture", assetName: sourceAssetName)
        }
        let sourceTaskId = sourceAsset.provenance?.attribution.taskId ?? ""
        guard !sourceTaskId.isEmpty,
              sourceAsset.provenance?.attribution.providerIdentifier == "meshy" else {
            throw MeshyError.unsupportedSource(operation: "retexture", assetName: sourceAssetName)
        }
        let sourcePrompt = sourceAsset.provenance?.searchQuery ?? ""

        // Step 3: Fetch API key (Keychain read off main thread — security C9).
        let apiKey = try await Task.detached(priority: .userInitiated) {
            try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
        }.value

        // Step 4: Run the retexture flow.
        let client = MeshyAIClient(apiKey: apiKey)
        let flow = RemeshAndRetextureFlow(client: client)
        let options = RemeshAndRetextureFlow.RetextureOptions(hardTimeout: 1800)
        let existingNames = Set(document.spriteRepository.assets.map(\.name))
        let asset = try await flow.runRetexture(
            sourceTaskId: sourceTaskId,
            sourceAssetName: sourceAssetName,
            sourcePrompt: sourcePrompt,
            newStylePrompt: stylePrompt,
            options: options,
            existingAssetNames: existingNames
        )

        // Step 5: Install asset into the live document via the runtime's notification channel.
        // Security (C8): exactly one mutation — this IS the mutation; StackRuntime must not re-mutate.
        var modifiedDocument = document
        modifiedDocument.spriteRepository.addAsset(asset)
        let stackId = document.stack.id
        await MainActor.run {
            NotificationCenter.default.post(
                name: .stackRuntimeDocumentDidChange,
                object: nil,
                userInfo: [
                    "stackId": stackId,
                    "document": modifiedDocument,
                ]
            )
        }

        return asset.name
    }
}

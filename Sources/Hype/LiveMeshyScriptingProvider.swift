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
}

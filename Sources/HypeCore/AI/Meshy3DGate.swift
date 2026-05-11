import Foundation

// MARK: - Meshy3DGate

/// Pure helper enum encapsulating the "can we show the Generate 3D sheet?"
/// decision.
///
/// Lives in HypeCore so the AI tool layer (Phase 2) can call it without
/// depending on SwiftUI.
///
/// Security (M4): `status(for:keyIsSet:)` is a pure function of
/// `document.stack.meshyEnabled` and a pre-fetched `keyIsSet` Bool —
/// it does NOT probe the Keychain synchronously on the call site's
/// thread. Each call site caches `@State private var meshyKeyIsSet: Bool`
/// refreshed in `.onAppear` and after Save/Delete operations.
public enum Meshy3DGate {

    // MARK: - Status

    public enum Status: Sendable, Equatable {
        /// All gates pass — the Generate-3D sheet can be presented.
        case ready
        /// `stack.meshyEnabled == false`. The UI should prompt the user
        /// to enable Meshy for this stack before proceeding.
        case stackDisabled
        /// The Meshy API key is not set in the Keychain. The UI should
        /// direct the user to Preferences → Meshy.ai.
        case apiKeyMissing
    }

    // MARK: - Gate function

    /// Returns the current gate status for the given document and
    /// pre-fetched key state.
    ///
    /// - Parameters:
    ///   - document: The active `HypeDocument` (reads `stack.meshyEnabled`).
    ///   - keyIsSet: `true` if `KeychainStore.hasSecret(account: .meshyAPIKeyAccount)`
    ///     returned `true` when last checked. Call sites refresh this on
    ///     `.onAppear` and after Keychain mutations.
    /// - Returns: `.ready`, `.stackDisabled`, or `.apiKeyMissing`.
    public static func status(for document: HypeDocument, keyIsSet: Bool) -> Status {
        // Stack must be opted in first.
        guard document.stack.meshyEnabled else {
            return .stackDisabled
        }
        // API key must be present.
        guard keyIsSet else {
            return .apiKeyMissing
        }
        return .ready
    }
}

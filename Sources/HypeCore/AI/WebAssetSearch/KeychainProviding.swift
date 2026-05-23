import Foundation

// MARK: - KeychainProviding

/// An abstraction over Keychain storage for API secrets.
///
/// The production implementation is `KeychainStore.live`, which delegates to
/// the real `SecItem*` APIs. Tests inject an `InMemoryKeychain` stub to avoid
/// touching the real Keychain, which requires an entitlement not present in
/// the Swift Package Manager test runner.
///
/// All methods match the naming and semantics of `KeychainStore`'s static API
/// so that migration from direct static calls to injected-instance calls is
/// mechanical.
public protocol KeychainProviding: Sendable {

    /// Store or update a secret string.
    ///
    /// - Parameters:
    ///   - value: The secret string to persist.
    ///   - account: The account identifier (key name) within this service.
    /// - Throws: `KeychainStoreError.encodingFailed` when the value cannot be
    ///   UTF-8 encoded, or `KeychainStoreError.unhandledStatus` for unexpected
    ///   Keychain errors.
    func setSecret(_ value: String, account: String) throws

    /// Retrieve a secret string.
    ///
    /// - Parameter account: The account identifier to look up.
    /// - Returns: The stored secret.
    /// - Throws: `KeychainStoreError.itemNotFound` when no item exists, or
    ///   `KeychainStoreError.unhandledStatus` for unexpected Keychain errors.
    func getSecret(account: String) throws -> String

    /// Returns `true` when a secret exists for the given account.
    /// Errors map to `false` — this is a silent check.
    func hasSecret(account: String) -> Bool

    /// Delete a secret.
    ///
    /// - Parameter account: The account identifier to remove.
    /// - Throws: `KeychainStoreError.itemNotFound` when no item exists, or
    ///   `KeychainStoreError.unhandledStatus` for unexpected Keychain errors.
    func deleteSecret(account: String) throws
}

// MARK: - KeychainStore.live (production instance)

extension KeychainStore {

    /// The production `KeychainProviding` instance.
    ///
    /// Wraps the existing static `KeychainStore` API so that callers can
    /// accept a `KeychainProviding` instead of referencing the type directly.
    /// Default parameter values on initializers default to this value so that
    /// production code paths require zero changes.
    public static let live: KeychainProviding = LiveKeychainStore()
}

// MARK: - LiveKeychainStore (bridges static → instance)

/// A thin `Sendable` wrapper that forwards all calls to the `KeychainStore`
/// static API. This is the only concrete type that touches the real Keychain.
private struct LiveKeychainStore: KeychainProviding {

    func setSecret(_ value: String, account: String) throws {
        try KeychainStore.setSecret(value, account: account)
    }

    func getSecret(account: String) throws -> String {
        try KeychainStore.getSecret(account: account)
    }

    func hasSecret(account: String) -> Bool {
        KeychainStore.hasSecret(account: account)
    }

    func deleteSecret(account: String) throws {
        try KeychainStore.deleteSecret(account: account)
    }
}

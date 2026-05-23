import Foundation
@testable import HypeCore

// MARK: - InMemoryKeychain

/// An in-memory `KeychainProviding` stub for use in tests.
///
/// Thread-safe via an `NSLock`. Marked `@unchecked Sendable` because the lock
/// provides the necessary synchronisation that Swift's type system cannot verify
/// statically.
///
/// Usage:
/// ```swift
/// let keychain = InMemoryKeychain()
/// try keychain.setSecret("test_key", account: "meshy.apiKey")
/// let retrieved = try keychain.getSecret(account: "meshy.apiKey")
/// ```
///
/// Visibility: `package` so both `HypeCoreTests` and `HypeTests` can access it
/// without making it part of the public API.
package final class InMemoryKeychain: KeychainProviding, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [String: String] = [:]

    package init() {}

    // MARK: - KeychainProviding

    package func setSecret(_ value: String, account: String) throws {
        lock.withLock {
            storage[account] = value
        }
    }

    package func getSecret(account: String) throws -> String {
        try lock.withLock {
            guard let value = storage[account] else {
                throw KeychainStoreError.itemNotFound
            }
            return value
        }
    }

    package func hasSecret(account: String) -> Bool {
        lock.withLock {
            storage[account] != nil
        }
    }

    package func deleteSecret(account: String) throws {
        try lock.withLock {
            guard storage[account] != nil else {
                throw KeychainStoreError.itemNotFound
            }
            storage.removeValue(forKey: account)
        }
    }
}

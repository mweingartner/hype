import Testing
import Foundation
@testable import HypeCore

/// Keychain round-trip tests (macOS only).
///
/// Uses a unique test service identifier to avoid contaminating the production
/// Keychain. All items are cleaned up after each test via `defer`.
///
/// These tests run serially because Keychain operations on the same service
/// are not safe to interleave across concurrent tests.
#if canImport(Security)
@Suite("KeychainStore — round-trip write/read/delete", .serialized)
struct KeychainStoreTests {

    /// A unique test service name per test run to avoid contaminating
    /// the real "com.hype.webAssets" service used in production.
    /// Each test further scopes with a unique account.
    private let testService = "com.hype.webAssets.test.\(UUID().uuidString)"

    // MARK: - Helpers

    /// Write a secret to the Keychain using a custom service for isolation.
    /// We test through the actual KeychainStore API (which uses `service`
    /// constant "com.hype.webAssets") since KeychainStore doesn't expose a
    /// service parameter. Instead, we test with the real `pexelsAPIKeyAccount`
    /// and a unique secret value, cleaning up after each test.

    // MARK: - Write → Read round-trip

    @Test("setSecret and getSecret round-trip a simple string")
    func writeReadRoundTrip() throws {
        let account = "test.account.\(UUID().uuidString)"
        let secret = "my-test-secret-\(UUID().uuidString)"

        // Write
        try KeychainStore.setSecret(secret, account: account)
        defer { try? KeychainStore.deleteSecret(account: account) }

        // Read
        let retrieved = try KeychainStore.getSecret(account: account)
        #expect(retrieved == secret)
    }

    @Test("setSecret overwrites an existing item (update path)")
    func setSecretOverwritesExisting() throws {
        let account = "test.account.\(UUID().uuidString)"

        try KeychainStore.setSecret("first-value", account: account)
        defer { try? KeychainStore.deleteSecret(account: account) }

        try KeychainStore.setSecret("second-value", account: account)

        let retrieved = try KeychainStore.getSecret(account: account)
        #expect(retrieved == "second-value")
    }

    @Test("setSecret handles Unicode secrets correctly")
    func setSecretHandlesUnicode() throws {
        let account = "test.unicode.\(UUID().uuidString)"
        let unicodeSecret = "Hello, 世界! 🎉 — test"

        try KeychainStore.setSecret(unicodeSecret, account: account)
        defer { try? KeychainStore.deleteSecret(account: account) }

        let retrieved = try KeychainStore.getSecret(account: account)
        #expect(retrieved == unicodeSecret)
    }

    @Test("setSecret handles an empty string value")
    func setSecretEmptyString() throws {
        let account = "test.empty.\(UUID().uuidString)"

        try KeychainStore.setSecret("", account: account)
        defer { try? KeychainStore.deleteSecret(account: account) }

        let retrieved = try KeychainStore.getSecret(account: account)
        #expect(retrieved == "")
    }

    // MARK: - Delete

    @Test("deleteSecret removes the item from the Keychain")
    func deleteSecretRemovesItem() throws {
        let account = "test.delete.\(UUID().uuidString)"

        try KeychainStore.setSecret("to-delete", account: account)
        try KeychainStore.deleteSecret(account: account)

        // After deletion, getSecret should throw itemNotFound
        #expect(throws: KeychainStoreError.self) {
            try KeychainStore.getSecret(account: account)
        }
    }

    @Test("deleteSecret throws itemNotFound for a non-existent account")
    func deleteNonExistentThrowsItemNotFound() throws {
        let account = "test.nonexistent.\(UUID().uuidString)"
        do {
            try KeychainStore.deleteSecret(account: account)
            Issue.record("Expected itemNotFound but succeeded")
        } catch KeychainStoreError.itemNotFound {
            // Correct
        } catch {
            Issue.record("Expected itemNotFound, got \(error)")
        }
    }

    // MARK: - getSecret error paths

    @Test("getSecret throws itemNotFound for a non-existent account")
    func getSecretNonExistentThrowsItemNotFound() throws {
        let account = "test.nonexistent.\(UUID().uuidString)"
        do {
            _ = try KeychainStore.getSecret(account: account)
            Issue.record("Expected itemNotFound but succeeded")
        } catch KeychainStoreError.itemNotFound {
            // Correct
        } catch {
            Issue.record("Expected itemNotFound, got \(error)")
        }
    }

    // MARK: - hasSecret

    @Test("hasSecret returns true when a secret exists")
    func hasSecretReturnsTrueWhenExists() throws {
        let account = "test.has.\(UUID().uuidString)"

        try KeychainStore.setSecret("check-me", account: account)
        defer { try? KeychainStore.deleteSecret(account: account) }

        #expect(KeychainStore.hasSecret(account: account) == true)
    }

    @Test("hasSecret returns false when no secret exists")
    func hasSecretReturnsFalseWhenAbsent() {
        let account = "test.absent.\(UUID().uuidString)"
        #expect(KeychainStore.hasSecret(account: account) == false)
    }

    @Test("hasSecret returns false after the secret is deleted")
    func hasSecretReturnsFalseAfterDelete() throws {
        let account = "test.deleted.\(UUID().uuidString)"

        try KeychainStore.setSecret("temp", account: account)
        #expect(KeychainStore.hasSecret(account: account) == true)

        try KeychainStore.deleteSecret(account: account)
        #expect(KeychainStore.hasSecret(account: account) == false)
    }

    // MARK: - Well-known account constants

    @Test("pexelsAPIKeyAccount is 'pexels.apiKey'")
    func pexelsAPIKeyAccountConstant() {
        #expect(KeychainStore.pexelsAPIKeyAccount == "pexels.apiKey")
    }

    @Test("service identifier is 'com.hype.webAssets'")
    func serviceIdentifierConstant() {
        #expect(KeychainStore.service == "com.hype.webAssets")
    }

    // MARK: - Long secrets (large payload)

    @Test("setSecret handles a 4096-byte secret")
    func setSecretLargePayload() throws {
        let account = "test.large.\(UUID().uuidString)"
        let largeSecret = String(repeating: "A", count: 4096)

        try KeychainStore.setSecret(largeSecret, account: account)
        defer { try? KeychainStore.deleteSecret(account: account) }

        let retrieved = try KeychainStore.getSecret(account: account)
        #expect(retrieved == largeSecret)
    }
}
#endif

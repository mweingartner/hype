import Foundation
import Testing
@testable import HypeCore

/// Tests for the Meshy keychain account constant and in-memory round-trip operations.
///
/// These tests use `InMemoryKeychain` instead of the real macOS Keychain.
/// This eliminates the `errSecMissingEntitlement` (-67701) flake that occurred
/// in parallel runs under Swift Package Manager, where the Keychain entitlement
/// is not available.
///
/// The only test that touches the real Keychain is `keychainAccountConstant`,
/// which only reads a string constant — no SecItem calls.
@Suite("Meshy keychain account")
struct MeshyKeychainAccountTests {

    @Test("meshyAPIKeyAccount constant equals meshy.apiKey")
    func keychainAccountConstant() {
        #expect(KeychainStore.meshyAPIKeyAccount == "meshy.apiKey")
    }

    @Test("round-trip set / get / delete — in-memory")
    func roundTrip() throws {
        let keychain = InMemoryKeychain()

        let testValue = "msy_test_\(UUID().uuidString)"
        try keychain.setSecret(testValue, account: KeychainStore.meshyAPIKeyAccount)
        let retrieved = try keychain.getSecret(account: KeychainStore.meshyAPIKeyAccount)
        #expect(retrieved == testValue)

        try keychain.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)
        // After delete, getSecret should throw.
        var threw = false
        do {
            _ = try keychain.getSecret(account: KeychainStore.meshyAPIKeyAccount)
        } catch {
            threw = true
        }
        #expect(threw, "Expected getSecret to throw after delete")
    }

    @Test("hasSecret returns correct value — in-memory")
    func hasSecret() throws {
        let keychain = InMemoryKeychain()

        #expect(!keychain.hasSecret(account: KeychainStore.meshyAPIKeyAccount))

        try keychain.setSecret("msy_test", account: KeychainStore.meshyAPIKeyAccount)
        #expect(keychain.hasSecret(account: KeychainStore.meshyAPIKeyAccount))

        try keychain.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)
        #expect(!keychain.hasSecret(account: KeychainStore.meshyAPIKeyAccount))
    }

    @Test("deleting Meshy key does not affect openAI key — in-memory")
    func isolationFromOpenAI() throws {
        let keychain = InMemoryKeychain()

        // Seed the OpenAI slot.
        let canary = "openai_canary_\(UUID().uuidString)"
        try keychain.setSecret(canary, account: KeychainStore.openAIAPIKeyAccount)

        // Write and delete Meshy key.
        try keychain.setSecret("msy_test", account: KeychainStore.meshyAPIKeyAccount)
        try keychain.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)

        // OpenAI key must still be present and unchanged.
        let retrieved = try keychain.getSecret(account: KeychainStore.openAIAPIKeyAccount)
        #expect(retrieved == canary)
    }
}

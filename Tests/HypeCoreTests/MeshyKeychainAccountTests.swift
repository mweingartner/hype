import Foundation
import Testing
@testable import HypeCore

/// Tests for the Meshy keychain account constant and round-trip operations.
///
/// These tests hit the real macOS Keychain. They are marked `.serialized`
/// to avoid racing against each other or against production keys. The
/// test account uses the standard "meshy.apiKey" value — setUp/tearDown
/// ensure the key is absent before and after each test.
@Suite("Meshy keychain account", .serialized)
struct MeshyKeychainAccountTests {

    @Test("meshyAPIKeyAccount constant equals meshy.apiKey")
    func keychainAccountConstant() {
        #expect(KeychainStore.meshyAPIKeyAccount == "meshy.apiKey")
    }

    @Test("round-trip set / get / delete")
    func roundTrip() throws {
        // Ensure clean state.
        try? KeychainStore.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)

        let testValue = "msy_test_\(UUID().uuidString)"
        try KeychainStore.setSecret(testValue, account: KeychainStore.meshyAPIKeyAccount)
        let retrieved = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
        #expect(retrieved == testValue)

        try KeychainStore.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)
        // After delete, get should throw.
        var threw = false
        do {
            _ = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
        } catch {
            threw = true
        }
        #expect(threw, "Expected getSecret to throw after delete")
    }

    @Test("hasSecret returns correct value")
    func hasSecret() throws {
        try? KeychainStore.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)
        #expect(!KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount))

        try KeychainStore.setSecret("msy_test", account: KeychainStore.meshyAPIKeyAccount)
        #expect(KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount))

        try KeychainStore.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)
        #expect(!KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount))
    }

    @Test("deleting Meshy key does not affect openAI key")
    func isolationFromOpenAI() throws {
        // Ensure Meshy clean.
        try? KeychainStore.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)

        // Write a canary to openAI slot if not already set (restore it later).
        let openAIWasSet = KeychainStore.hasSecret(account: KeychainStore.openAIAPIKeyAccount)
        let canary = "openai_canary_\(UUID().uuidString)"
        if !openAIWasSet {
            try KeychainStore.setSecret(canary, account: KeychainStore.openAIAPIKeyAccount)
        }

        // Write and delete Meshy key.
        try KeychainStore.setSecret("msy_test", account: KeychainStore.meshyAPIKeyAccount)
        try KeychainStore.deleteSecret(account: KeychainStore.meshyAPIKeyAccount)

        // OpenAI key must still be present.
        #expect(KeychainStore.hasSecret(account: KeychainStore.openAIAPIKeyAccount))

        // Cleanup: remove canary only if we wrote it.
        if !openAIWasSet {
            try? KeychainStore.deleteSecret(account: KeychainStore.openAIAPIKeyAccount)
        }
    }
}

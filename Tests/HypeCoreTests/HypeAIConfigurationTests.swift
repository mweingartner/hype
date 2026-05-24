import Foundation
import Testing
@testable import HypeCore

@Suite("HypeAIConfiguration")
struct HypeAIConfigurationTests {
    @Test("llama-swap is a selectable AI provider")
    func llamaSwapProviderIsSelectable() {
        #expect(HypeAIProvider.allCases.contains(.llamaSwap))
        #expect(HypeAIProvider.llamaSwap.displayName == "llama-swap")
    }

    @Test("makeClient returns llama-swap client from user defaults")
    func makeClientReturnsLlamaSwapClient() throws {
        let defaults = try makeDefaults()
        defaults.set(HypeAIProvider.llamaSwap.rawValue, forKey: HypeAIConfiguration.providerKey)
        defaults.set("127.0.0.1", forKey: HypeAIConfiguration.llamaSwapHostKey)
        defaults.set("9292", forKey: HypeAIConfiguration.llamaSwapPortKey)
        defaults.set("qwen3-8b", forKey: HypeAIConfiguration.llamaSwapModelKey)

        let client = try HypeAIConfiguration.makeClient(defaults: defaults)

        #expect(client.providerName == "llama-swap")
        #expect(client.modelName == "qwen3-8b")
    }

    @Test("llama-swap defaults match local proxy convention")
    func llamaSwapDefaults() throws {
        let defaults = try makeDefaults()
        #expect(HypeAIConfiguration.llamaSwapHost(defaults: defaults) == "localhost")
        #expect(HypeAIConfiguration.llamaSwapPort(defaults: defaults) == "8080")
        #expect(HypeAIConfiguration.llamaSwapModel(defaults: defaults) == "model1")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HypeAIConfigurationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

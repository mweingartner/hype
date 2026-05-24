import Foundation
import Testing
@testable import HypeCore

@Suite("HypeAIConfiguration")
struct HypeAIConfigurationTests {
    @Test("hosted OpenAI-compatible providers are selectable")
    func hostedOpenAICompatibleProvidersAreSelectable() {
        #expect(HypeAIProvider.allCases.contains(.llamaSwap))
        #expect(HypeAIProvider.allCases.contains(.llamaCpp))
        #expect(HypeAIProvider.allCases.contains(.zAI))
        #expect(HypeAIProvider.allCases.contains(.miniMax))
        #expect(HypeAIProvider.llamaSwap.displayName == "llama-swap")
        #expect(HypeAIProvider.llamaCpp.displayName == "llama.cpp")
        #expect(HypeAIProvider.zAI.displayName == "Z.ai")
        #expect(HypeAIProvider.miniMax.displayName == "MiniMax")
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

    @Test("llama.cpp defaults match local OpenAI-compatible server convention")
    func llamaCppDefaults() throws {
        let defaults = try makeDefaults()
        #expect(HypeAIConfiguration.llamaCppHost(defaults: defaults) == "localhost")
        #expect(HypeAIConfiguration.llamaCppPort(defaults: defaults) == "8001")
        #expect(HypeAIConfiguration.llamaCppModel(defaults: defaults) == "model")
    }

    @Test("makeClient returns llama.cpp OpenAI-compatible client from user defaults")
    func makeClientReturnsLlamaCppClient() throws {
        let defaults = try makeDefaults()
        defaults.set(HypeAIProvider.llamaCpp.rawValue, forKey: HypeAIConfiguration.providerKey)
        defaults.set("127.0.0.1", forKey: HypeAIConfiguration.llamaCppHostKey)
        defaults.set("8001", forKey: HypeAIConfiguration.llamaCppPortKey)
        defaults.set("qwen2.5", forKey: HypeAIConfiguration.llamaCppModelKey)

        let client = try HypeAIConfiguration.makeClient(defaults: defaults)

        #expect(client is OpenAIChatCompletionsClient)
        #expect(client.providerName == "llama.cpp")
        #expect(client.modelName == "qwen2.5")
    }

    @Test("Z.ai and MiniMax defaults use US OpenAI-compatible endpoints")
    func hostedProviderDefaults() throws {
        let defaults = try makeDefaults()
        #expect(HypeAIConfiguration.zAIBaseURL(defaults: defaults) == "https://api.z.ai/api/paas/v4")
        #expect(HypeAIConfiguration.zAIModel(defaults: defaults) == "glm-5.1")
        #expect(HypeAIConfiguration.miniMaxBaseURL(defaults: defaults) == "https://api.minimax.io/v1")
        #expect(HypeAIConfiguration.miniMaxModel(defaults: defaults) == "MiniMax-M2")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HypeAIConfigurationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

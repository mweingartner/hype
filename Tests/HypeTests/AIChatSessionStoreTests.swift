import Foundation
import Testing
import HypeCore
@testable import Hype

@Suite("AI chat session store")
struct AIChatSessionStoreTests {
    @Test("saves and restores text transcript and conversation")
    func savesAndRestoresTextSession() throws {
        let defaults = try makeDefaults()
        let store = AIChatSessionStore(defaults: defaults)
        let stackId = UUID()

        store.save(
            stackId: stackId,
            transcriptMessages: [
                AIChatDisplayMessage(role: "user", content: "Build a menu"),
                AIChatDisplayMessage(role: "assistant", content: "**Done**"),
            ],
            conversationMessages: [
                OllamaMessage(role: "system", content: "System prompt"),
                OllamaMessage(role: "user", content: "Build a menu"),
                OllamaMessage(role: "assistant", content: "Done"),
            ]
        )

        let restored = try #require(store.load(stackId: stackId))
        #expect(restored.transcriptMessages.map(\.content) == ["Build a menu", "**Done**"])
        #expect(restored.conversationMessages.map(\.role) == ["system", "user", "assistant"])
        #expect(restored.conversationMessages.compactMap(\.content) == ["System prompt", "Build a menu", "Done"])
    }

    @Test("does not persist image base64 payloads")
    func doesNotPersistImagePayloads() throws {
        let defaults = try makeDefaults()
        let store = AIChatSessionStore(defaults: defaults)
        let stackId = UUID()

        store.save(
            stackId: stackId,
            transcriptMessages: [
                AIChatDisplayMessage(
                    role: "tool",
                    content: "Captured card image.",
                    imageBase64: "raw-image-bytes",
                    imagePixelWidth: 800,
                    imagePixelHeight: 600,
                    imageCaption: "current card"
                ),
            ],
            conversationMessages: [
                OllamaMessage(role: "user", content: "Analyze image", images: ["raw-image-bytes"]),
            ]
        )

        let restored = try #require(store.load(stackId: stackId))
        #expect(restored.transcriptMessages.first?.imageBase64 == nil)
        #expect(restored.transcriptMessages.first?.imageCaption == "current card")
        #expect(restored.conversationMessages.first?.images == nil)
        #expect(restored.conversationMessages.first?.content == "Analyze image")
    }

    @Test("clear removes persisted session")
    func clearRemovesPersistedSession() throws {
        let defaults = try makeDefaults()
        let store = AIChatSessionStore(defaults: defaults)
        let stackId = UUID()

        store.save(
            stackId: stackId,
            transcriptMessages: [AIChatDisplayMessage(role: "user", content: "Hello")],
            conversationMessages: [OllamaMessage(role: "user", content: "Hello")]
        )
        #expect(store.load(stackId: stackId) != nil)

        store.clear(stackId: stackId)

        #expect(store.load(stackId: stackId) == nil)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HypeTests.AIChatSessionStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

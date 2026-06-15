import Foundation
import HypeCore

struct AIChatSession: Codable {
    var transcriptMessages: [AIChatDisplayMessage]
    var conversationMessages: [OllamaMessage]
}

struct AIChatSessionStore {
    private let defaults: UserDefaults
    private let keyPrefix = "hype.aiChat.session."
    private let maximumTranscriptMessages = 200
    private let maximumConversationMessages = 120

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(stackId: UUID) -> AIChatSession? {
        guard let data = defaults.data(forKey: key(for: stackId)) else { return nil }
        return try? JSONDecoder().decode(AIChatSession.self, from: data)
    }

    func save(
        stackId: UUID,
        transcriptMessages: [AIChatDisplayMessage],
        conversationMessages: [OllamaMessage]
    ) {
        let sanitizedTranscript = transcriptMessages
            .suffix(maximumTranscriptMessages)
            .map(Self.sanitizedDisplayMessage)
        let sanitizedConversation = conversationMessages
            .suffix(maximumConversationMessages)
            .map(Self.sanitizedConversationMessage)

        guard !sanitizedTranscript.isEmpty || !sanitizedConversation.isEmpty else {
            clear(stackId: stackId)
            return
        }

        let session = AIChatSession(
            transcriptMessages: Array(sanitizedTranscript),
            conversationMessages: Array(sanitizedConversation)
        )
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key(for: stackId))
    }

    func clear(stackId: UUID) {
        defaults.removeObject(forKey: key(for: stackId))
    }

    private func key(for stackId: UUID) -> String {
        keyPrefix + stackId.uuidString
    }

    private static func sanitizedDisplayMessage(_ message: AIChatDisplayMessage) -> AIChatDisplayMessage {
        AIChatDisplayMessage(
            id: message.id,
            role: message.role,
            content: message.content,
            imageBase64: nil,
            imagePixelWidth: message.imagePixelWidth,
            imagePixelHeight: message.imagePixelHeight,
            imageCaption: message.imageCaption
        )
    }

    private static func sanitizedConversationMessage(_ message: OllamaMessage) -> OllamaMessage {
        OllamaMessage(
            role: message.role,
            content: message.content,
            tool_calls: message.tool_calls
        )
    }
}

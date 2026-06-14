import Foundation

struct AIChatDisplayMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: String
    let content: String
    let imageBase64: String?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let imageCaption: String?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        imageBase64: String? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        imageCaption: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imageBase64 = imageBase64
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.imageCaption = imageCaption
    }
}

struct AIChatStreamingTranscript: Equatable {
    private(set) var messages: [AIChatDisplayMessage] = []
    private(set) var streamingMessageId: UUID?
    private(set) var streamingContent = ""

    mutating func clear() {
        messages.removeAll()
        clearStreamingState()
    }

    mutating func clearStreamingState() {
        streamingMessageId = nil
        streamingContent = ""
    }

    mutating func restorePersistedMessages(_ persistedMessages: [AIChatDisplayMessage]) {
        messages = persistedMessages
        clearStreamingState()
    }

    mutating func appendMessage(
        role: String,
        content: String,
        imageBase64: String? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        imageCaption: String? = nil
    ) {
        messages.append(AIChatDisplayMessage(
            role: role,
            content: content,
            imageBase64: imageBase64,
            imagePixelWidth: imagePixelWidth,
            imagePixelHeight: imagePixelHeight,
            imageCaption: imageCaption
        ))
    }

    @discardableResult
    mutating func appendStreamingToken(_ token: String) -> UUID {
        let id = ensureStreamingMessage()
        streamingContent += token
        return id
    }

    @discardableResult
    mutating func finishStreamingMessage() -> String? {
        guard let id = streamingMessageId,
              let index = messages.firstIndex(where: { $0.id == id }) else {
            clearStreamingState()
            return nil
        }

        let existing = messages[index]
        messages[index] = AIChatDisplayMessage(
            id: existing.id,
            role: existing.role,
            content: streamingContent,
            imageBase64: existing.imageBase64,
            imagePixelWidth: existing.imagePixelWidth,
            imagePixelHeight: existing.imagePixelHeight,
            imageCaption: existing.imageCaption
        )
        let finalized = streamingContent
        clearStreamingState()
        return finalized
    }

    func displayContent(for message: AIChatDisplayMessage) -> String {
        streamingMessageId == message.id ? streamingContent : message.content
    }

    func visibleMessages(showThinking: Bool, showToolCalls: Bool) -> [AIChatDisplayMessage] {
        messages.filter { message in
            if message.role == "thinking" {
                return showThinking
            }
            if AIChatToolCallSummary(message: message) != nil {
                return showToolCalls
            }
            return true
        }
    }

    private mutating func ensureStreamingMessage() -> UUID {
        if let streamingMessageId {
            return streamingMessageId
        }
        let message = AIChatDisplayMessage(role: "assistant", content: "")
        messages.append(message)
        streamingMessageId = message.id
        streamingContent = ""
        return message.id
    }
}

struct AIChatToolCallSummary: Equatable {
    var name: String
    var arguments: String

    init?(message: AIChatDisplayMessage) {
        guard message.role == "tool",
              message.content.hasPrefix("Tool: ") else {
            return nil
        }
        let raw = String(message.content.dropFirst("Tool: ".count))
        if let open = raw.firstIndex(of: "("), raw.last == ")" {
            name = String(raw[..<open])
            arguments = String(raw[raw.index(after: open)..<raw.index(before: raw.endIndex)])
        } else {
            name = raw
            arguments = ""
        }
    }
}

import Testing
@testable import Hype

@Suite("AI chat streaming transcript")
struct AIChatStreamingTranscriptTests {
    @Test("streamed response chunks stay attached to one assistant bubble")
    func streamedChunksStayAttachedToOneBubble() {
        var transcript = AIChatStreamingTranscript()
        transcript.appendMessage(role: "user", content: "Say hello")

        let firstId = transcript.appendStreamingToken("Hel")
        #expect(transcript.messages.count == 2)
        #expect(transcript.messages[1].role == "assistant")
        #expect(transcript.messages[1].content == "")
        #expect(transcript.displayContent(for: transcript.messages[1]) == "Hel")

        let secondId = transcript.appendStreamingToken("lo")
        let thirdId = transcript.appendStreamingToken("!")

        #expect(firstId == secondId)
        #expect(secondId == thirdId)
        #expect(transcript.messages.count == 2)
        #expect(transcript.streamingMessageId == firstId)
        #expect(transcript.displayContent(for: transcript.messages[1]) == "Hello!")

        let finalized = transcript.finishStreamingMessage()

        #expect(finalized == "Hello!")
        #expect(transcript.messages.count == 2)
        #expect(transcript.messages[1].id == firstId)
        #expect(transcript.messages[1].content == "Hello!")
        #expect(transcript.displayContent(for: transcript.messages[1]) == "Hello!")
        #expect(transcript.streamingMessageId == nil)
        #expect(transcript.streamingContent.isEmpty)
    }

    @Test("new streamed response creates a new bubble after finalizing prior stream")
    func newStreamCreatesNewBubbleAfterFinalizing() {
        var transcript = AIChatStreamingTranscript()

        let firstId = transcript.appendStreamingToken("First")
        transcript.finishStreamingMessage()
        let secondId = transcript.appendStreamingToken("Second")

        #expect(firstId != secondId)
        #expect(transcript.messages.count == 2)
        #expect(transcript.messages.map(\.content) == ["First", ""])
        #expect(transcript.displayContent(for: transcript.messages[1]) == "Second")
    }

    @Test("tool call messages expose renderable name and arguments")
    func toolCallMessagesExposeRenderableSummary() throws {
        let message = AIChatDisplayMessage(
            role: "tool",
            content: "Tool: create_button(name: Start, left: 20)"
        )

        let summary = try #require(AIChatToolCallSummary(message: message))

        #expect(summary.name == "create_button")
        #expect(summary.arguments == "name: Start, left: 20")
    }

    @Test("visible messages respect thinking and tool-call toggles")
    func visibleMessagesRespectDisplayToggles() {
        var transcript = AIChatStreamingTranscript()
        transcript.appendMessage(role: "user", content: "Build")
        transcript.appendMessage(role: "thinking", content: "Thinking:\nNeed a button")
        transcript.appendMessage(role: "tool", content: "Tool: create_button(name: Start)")
        transcript.appendMessage(role: "assistant", content: "Created it")

        #expect(transcript.visibleMessages(showThinking: true, showToolCalls: true).map(\.role) == ["user", "thinking", "tool", "assistant"])
        #expect(transcript.visibleMessages(showThinking: false, showToolCalls: true).map(\.role) == ["user", "tool", "assistant"])
        #expect(transcript.visibleMessages(showThinking: true, showToolCalls: false).map(\.role) == ["user", "thinking", "assistant"])
        #expect(transcript.visibleMessages(showThinking: false, showToolCalls: false).map(\.role) == ["user", "assistant"])
    }
}

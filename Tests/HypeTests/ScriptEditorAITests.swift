import Testing
@testable import Hype
import HypeCore

@MainActor
@Suite("Script Editor AI")
struct ScriptEditorAITests {
    @Test("system prompt includes the canonical HypeTalk guide")
    func systemPromptIncludesHypeTalkGuide() {
        let prompt = ScriptEditorAIPrompts.systemPrompt

        #expect(prompt.contains("Hype's Script Editor AI"))
        #expect(prompt.contains("HypeTalk is not JavaScript"))
        #expect(prompt.contains(HypeTalkGuide.llmContext))
    }

    @Test("voice auto-submit delay stays in the requested silence window")
    func voiceAutoSubmitDelayStaysInRequestedWindow() {
        #expect(AISpeechCapture.silenceAutoSubmitDelaySeconds >= 3)
        #expect(AISpeechCapture.silenceAutoSubmitDelaySeconds <= 4)
    }

    @Test("user prompt carries target, selection, current script, and request")
    func userPromptCarriesScriptEditorContext() {
        let prompt = ScriptEditorAIPrompts.userPrompt(
            request: "Add a mouseUp handler",
            targetDescription: "button \"Save\"",
            selectedText: "beep",
            scriptText: "on mouseUp\n  beep\nend mouseUp"
        )

        #expect(prompt.contains("TARGET:\nbutton \"Save\""))
        #expect(prompt.contains("SELECTED TEXT:\nbeep"))
        #expect(prompt.contains("CURRENT SCRIPT:\non mouseUp"))
        #expect(prompt.contains("USER REQUEST:\nAdd a mouseUp handler"))
    }

    @Test("prompt history appends, bounds, and recalls like chat input")
    func promptHistoryAppendsBoundsAndRecallsLikeChatInput() {
        var history: [String] = []
        history = AIChatPromptHistory.appending("first", to: history)
        history = AIChatPromptHistory.appending("second", to: history)
        history = AIChatPromptHistory.appending("second", to: history)
        history = AIChatPromptHistory.appending("third", to: history)

        #expect(history == ["first", "second", "third"])

        var index = -1
        #expect(AIChatPromptHistory.recall(direction: .up, from: history, index: &index) == "third")
        #expect(AIChatPromptHistory.recall(direction: .up, from: history, index: &index) == "second")
        #expect(AIChatPromptHistory.recall(direction: .down, from: history, index: &index) == "third")
        #expect(AIChatPromptHistory.recall(direction: .down, from: history, index: &index) == "")
        #expect(index == -1)

        let oversized = (0..<(AIChatPromptHistory.maxEntries + 5)).reduce(into: [String]()) { partial, value in
            partial = AIChatPromptHistory.appending("prompt \(value)", to: partial)
        }
        #expect(oversized.count == AIChatPromptHistory.maxEntries)
        #expect(oversized.first == "prompt 5")
    }
}

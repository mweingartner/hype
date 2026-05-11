import Foundation
import Testing
@testable import Hype
@testable import HypeCore

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

    @Test("script editor exposes HypeTalk speech templates")
    func scriptEditorExposesSpeechTemplates() {
        let names = scriptEditorTemplateNames(for: "Speech")
        #expect(names.contains("say text"))
        #expect(names.contains("activate listener"))
        #expect(names.contains("deactivate listener"))
        #expect(names.contains("on listen"))
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

    @Test("script editor keeps sprite-area container and scene scripts distinct")
    func scriptEditorKeepsSpriteAreaContainerAndSceneTargetsDistinct() {
        var document = HypeDocument.newDocument(name: "Scripts")
        let cardId = document.cards[0].id
        let sceneId = UUID()
        var spriteArea = Part(partType: .spriteArea, cardId: cardId, name: "game_area")
        spriteArea.setSpriteAreaSpec(SpriteAreaSpec(
            activeSceneID: sceneId,
            scenes: [
                SpriteAreaScene(
                    id: sceneId,
                    scene: SceneSpec(name: "main", size: SizeSpec(width: 640, height: 480))
                )
            ],
            designSize: SizeSpec(width: 640, height: 480)
        ))
        document.addPart(spriteArea)

        #expect(scriptEditorResolvedTarget(in: document, target: .part(spriteArea.id), partId: spriteArea.id) == .part(spriteArea.id))
        #expect(scriptEditorResolvedTarget(in: document, target: .scene(partId: spriteArea.id, sceneId: sceneId), partId: spriteArea.id) == .scene(partId: spriteArea.id, sceneId: sceneId))
        #expect(scriptEditorDisplayedScriptText(storedScript: "") == "")
    }
}

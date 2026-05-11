import Testing
import Foundation
@testable import HypeCore

private final class AIProbe: @unchecked Sendable {
    var prompts: [String] = []
    var models: [String?] = []
}

private final class SpeechProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(text: String, source: String)] = []

    func record(text: String, source: String) {
        lock.withLock {
            entries.append((text, source))
        }
    }

    var texts: [String] {
        lock.withLock { entries.map(\.text) }
    }

    var sources: [String] {
        lock.withLock { entries.map(\.source) }
    }
}

private struct RecordingAIProvider: AIScriptingProvider {
    let current: String
    let available: [String]
    let generated: String
    let probe: AIProbe

    init(
        current: String = "llama3.2",
        available: [String] = ["llama3.2"],
        generated: String = "generated response",
        probe: AIProbe = AIProbe()
    ) {
        self.current = current
        self.available = available
        self.generated = generated
        self.probe = probe
    }

    func currentModel() -> String { current }
    func availableModels() throws -> [String] { available }

    func generate(prompt: String, model: String?) throws -> String {
        probe.prompts.append(prompt)
        probe.models.append(model)
        return generated
    }
}

private struct RecordingSpeechOutputProvider: SpeechOutputProvider {
    let probe: SpeechProbe

    func speakAIResponse(_ text: String, source: String) async {
        probe.record(text: text, source: source)
    }

    func speakScriptText(_ text: String, source: String) async {
        probe.record(text: text, source: source)
    }
}

private func makeAIScriptDoc() -> (HypeDocument, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id

    var button = Part(partType: .button, cardId: cardId, name: "Runner")
    button.script = ""
    doc.addPart(button)

    let field = Part(partType: .field, cardId: cardId, name: "output")
    doc.addPart(field)

    return (doc, cardId, button.id)
}

private func runAIScript(
    _ script: String,
    provider: any AIScriptingProvider,
    speechOutputProvider: SpeechOutputProvider = StubSpeechOutputProvider()
) async -> ExecutionResult {
    var (doc, cardId, buttonId) = makeAIScriptDoc()
    doc.updatePart(id: buttonId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    return await runOnLargeStack { [doc, cardId, buttonId] in
        dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: buttonId,
            document: doc,
            currentCardId: cardId,
            aiProvider: provider,
            speechOutputProvider: speechOutputProvider
        )
    }
}

private func outputText(from result: ExecutionResult) -> String? {
    result.modifiedDocument?.parts.first(where: { $0.name == "output" })?.textContent
}

@Suite("HypeTalk AI", .serialized)
struct HypeTalkAITests {
    private func parse(_ source: String) -> Bool {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return (try? parser.parse()) != nil
    }

    @Test("parses ask ai with explicit model") func parseAskAIWithModel() async {
        #expect(parse("""
        on mouseUp
          ask ai "Write a loading screen hint" with model "phi4"
        end mouseUp
        """))
    }

    @Test("parses prefix ollama function syntax") func parsePrefixOllamaFunction() async {
        #expect(parse("""
        on mouseUp
          put ollama "Write one line of dialog" into field "output"
        end mouseUp
        """))
    }

    @Test("parses speech commands and listen handlers")
    func parseSpeechCommandsAndListenHandler() async {
        #expect(parse("""
        on mouseUp
          say "hello"
          set activateListener to true
          activateListener false
        end mouseUp

        on listen spokenText
          put spokenText into field "output"
          pass listen
        end listen
        """))
    }

    @Test("ask ai stores the generated text in it") func askAIStoresGeneratedTextInIt() async {
        let provider = RecordingAIProvider(generated: "Scene summary")
        let result = await runAIScript("""
        on mouseUp
          ask ai "Summarize this scene"
          put it into field "output"
        end mouseUp
        """, provider: provider)

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "Scene summary")
        #expect(provider.probe.prompts == ["Summarize this scene"])
        #expect(provider.probe.models == [nil])
    }

    @Test("ask ai speaks the generated response through the speech output provider")
    func askAISpeaksGeneratedResponse() async {
        let speechProbe = SpeechProbe()
        let provider = RecordingAIProvider(generated: "Scene summary")
        let result = await runAIScript("""
        on mouseUp
          ask ai "Summarize this scene"
          put it into field "output"
        end mouseUp
        """, provider: provider, speechOutputProvider: RecordingSpeechOutputProvider(probe: speechProbe))

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "Scene summary")
        #expect(speechProbe.texts == ["Scene summary"])
        #expect(speechProbe.sources == ["HypeTalk AI"])
    }

    @Test("say command speaks through the script speech provider")
    func sayCommandSpeaksThroughScriptSpeechProvider() async {
        let speechProbe = SpeechProbe()
        let provider = RecordingAIProvider()
        let result = await runAIScript("""
        on mouseUp
          say "this is a test"
        end mouseUp
        """, provider: provider, speechOutputProvider: RecordingSpeechOutputProvider(probe: speechProbe))

        #expect(result.status == .completed)
        #expect(speechProbe.texts == ["this is a test"])
        #expect(speechProbe.sources == ["HypeTalk say"])
    }

    @Test("ask ai with model passes the requested model name") func askAIWithModelUsesRequestedModel() async {
        let provider = RecordingAIProvider(generated: "Boss encounter")
        let result = await runAIScript("""
        on mouseUp
          ask ai "Write a boss intro" with model "phi4-mini"
          put it into field "output"
        end mouseUp
        """, provider: provider)

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "Boss encounter")
        #expect(provider.probe.models == ["phi4-mini"])
    }

    @Test("ollama(model, prompt) works as an expression")
    func ollamaFunctionWithExplicitModel() async {
        let provider = RecordingAIProvider(generated: "Quest accepted")
        let result = await runAIScript("""
        on mouseUp
          put ollama("mistral-small", "Write a quest acceptance line") into field "output"
        end mouseUp
        """, provider: provider)

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "Quest accepted")
        #expect(provider.probe.prompts == ["Write a quest acceptance line"])
        #expect(provider.probe.models == ["mistral-small"])
    }

    @Test("ollama function speaks the generated response through the speech output provider")
    func ollamaFunctionSpeaksGeneratedResponse() async {
        let speechProbe = SpeechProbe()
        let provider = RecordingAIProvider(generated: "Quest accepted")
        let result = await runAIScript("""
        on mouseUp
          put ollama("mistral-small", "Write a quest acceptance line") into field "output"
        end mouseUp
        """, provider: provider, speechOutputProvider: RecordingSpeechOutputProvider(probe: speechProbe))

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "Quest accepted")
        #expect(speechProbe.texts == ["Quest accepted"])
        #expect(speechProbe.sources == ["HypeTalk AI"])
    }

    @Test("the aiModel returns the configured current model") func aiModelPropertyReturnsCurrentModel() async {
        let provider = RecordingAIProvider(current: "qwen3")
        let result = await runAIScript("""
        on mouseUp
          put the aiModel into field "output"
        end mouseUp
        """, provider: provider)

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "qwen3")
    }

    @Test("the aiModels returns a line-delimited model list") func aiModelsPropertyReturnsLines() async {
        let provider = RecordingAIProvider(
            available: ["llama3.2", "phi4-mini", "mistral-small"]
        )
        let result = await runAIScript("""
        on mouseUp
          put line 2 of the aiModels into field "output"
        end mouseUp
        """, provider: provider)

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "phi4-mini")
    }
}

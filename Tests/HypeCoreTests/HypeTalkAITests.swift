import Testing
import Foundation
@testable import HypeCore

private final class AIProbe: @unchecked Sendable {
    var prompts: [String] = []
    var models: [String?] = []
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
    provider: any AIScriptingProvider
) -> ExecutionResult {
    var (doc, cardId, buttonId) = makeAIScriptDoc()
    doc.updatePart(id: buttonId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    return dispatcher.dispatch(
        message: "mouseUp",
        params: [],
        targetId: buttonId,
        document: doc,
        currentCardId: cardId,
        aiProvider: provider
    )
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

    @Test("parses ask ai with explicit model")
    func parseAskAIWithModel() {
        #expect(parse("""
        on mouseUp
          ask ai "Write a loading screen hint" with model "phi4"
        end mouseUp
        """))
    }

    @Test("parses prefix ollama function syntax")
    func parsePrefixOllamaFunction() {
        #expect(parse("""
        on mouseUp
          put ollama "Write one line of dialog" into field "output"
        end mouseUp
        """))
    }

    @Test("ask ai stores the generated text in it")
    func askAIStoresGeneratedTextInIt() {
        let provider = RecordingAIProvider(generated: "Scene summary")
        let result = runAIScript("""
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

    @Test("ask ai with model passes the requested model name")
    func askAIWithModelUsesRequestedModel() {
        let provider = RecordingAIProvider(generated: "Boss encounter")
        let result = runAIScript("""
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
    func ollamaFunctionWithExplicitModel() {
        let provider = RecordingAIProvider(generated: "Quest accepted")
        let result = runAIScript("""
        on mouseUp
          put ollama("mistral-small", "Write a quest acceptance line") into field "output"
        end mouseUp
        """, provider: provider)

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "Quest accepted")
        #expect(provider.probe.prompts == ["Write a quest acceptance line"])
        #expect(provider.probe.models == ["mistral-small"])
    }

    @Test("the aiModel returns the configured current model")
    func aiModelPropertyReturnsCurrentModel() {
        let provider = RecordingAIProvider(current: "qwen3")
        let result = runAIScript("""
        on mouseUp
          put the aiModel into field "output"
        end mouseUp
        """, provider: provider)

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "qwen3")
    }

    @Test("the aiModels returns a line-delimited model list")
    func aiModelsPropertyReturnsLines() {
        let provider = RecordingAIProvider(
            available: ["llama3.2", "phi4-mini", "mistral-small"]
        )
        let result = runAIScript("""
        on mouseUp
          put line 2 of the aiModels into field "output"
        end mouseUp
        """, provider: provider)

        #expect(result.status == .completed)
        #expect(outputText(from: result) == "phi4-mini")
    }
}

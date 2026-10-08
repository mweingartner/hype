import Foundation
import Testing
@testable import HypeCore

@Suite("HypeTalk speak")
struct HypeTalkSpeakTests {
    @Test("All options are optional and speak returns completion, not a queued receipt")
    func defaults() async throws {
        let recorder = ScriptSpeechRecorder()
        let result = await execute(#"speak "Hello, world!""#, provider: recorder)
        #expect(result.error == nil)
        #expect(result.returnValue == "completed")
        #expect(await recorder.requests == [ScriptSpeechRequest(text: "Hello, world!")])
    }

    @Test("Named options preserve evaluated content and can appear in any order")
    func allOptions() async throws {
        let recorder = ScriptSpeechRecorder()
        let result = await execute("""
        put "Ryan" into voiceName
        speak "Exact " & "words." with output "wav", quality "studio", pace 1 / 2, tone "warm", voice voiceName
        """, provider: recorder)
        #expect(result.error == nil)
        #expect(await recorder.requests == [ScriptSpeechRequest(text: "Exact words.", voice: "Ryan", tone: "warm", pace: 0.5, quality: "studio", output: "wav")])
    }

    @Test("Voice discovery is newline-delimited and legacy say leaves it unchanged")
    func voicesAndSay() async {
        let recorder = ScriptSpeechRecorder()
        let result = await execute("""
        get the voices
        say "Legacy speech"
        """, provider: recorder)
        #expect(result.error == nil)
        #expect(result.returnValue == "Aiden\nRyan")
        #expect(await recorder.legacyTexts == ["Legacy speech"])
    }

    @Test("Service warnings remain visible in the result")
    func warnings() async {
        let recorder = ScriptSpeechRecorder(warnings: ["Recorded voice does not support tone"])
        let result = await execute(#"speak "Hello" with tone "warm""#, provider: recorder, returnExpression: "the result")
        #expect(result.returnValue == "Recorded voice does not support tone")
    }

    @Test("Bad speech values fail before a service call")
    func invalidValues() async {
        let cases = [(#"speak """#, "Speech needs non-empty"), (#"speak "x" pace "quick""#, "Speech pace"), (#"speak "x" pace 3"#, "Speech pace"), (#"speak "x" quality "tiny""#, "Speech quality"), (#"speak "x" output "mp3""#, "Speech output")]
        for (statement, message) in cases {
            let recorder = ScriptSpeechRecorder()
            let result = await execute(statement, provider: recorder)
            #expect(result.error?.message.contains(message) == true, "\(statement)")
            #expect(await recorder.requests.isEmpty)
        }
    }

    @Test("Malformed and duplicate options are rejected")
    func invalidSyntax() {
        for statement in ["speak", #"speak "x" with"#, #"speak "x" with pace"#, #"speak "x" voice "Ryan", voice "Aiden""#, #"speak "x" volume 1"#, #"speak "x" pace 1,"#] {
            var lexer = Lexer(source: "on t\n\(statement)\nend t")
            var parser = Parser(tokens: lexer.tokenize())
            #expect(throws: ParseError.self) { try parser.parse() }
        }
    }

    @Test("Seeded option-order permutations preserve the request", arguments: 0..<120)
    func optionOrder(seed: Int) async {
        let options = ["voice \"Ryan\"", "tone \"warm\"", "pace 0.9", "quality \"balanced\"", "output \"direct\""]
        let rotation = seed % options.count
        let ordered = Array(options[rotation...] + options[..<rotation])
        let recorder = ScriptSpeechRecorder()
        let result = await execute("speak \"case \(seed)\" with " + (seed.isMultiple(of: 2) ? ordered : Array(ordered.reversed())).joined(separator: ", "), provider: recorder)
        #expect(result.error == nil)
        #expect(await recorder.requests == [ScriptSpeechRequest(text: "case \(seed)", voice: "Ryan", tone: "warm", pace: 0.9, quality: "balanced", output: "direct")])
    }

    private func execute(_ statements: String, provider: any SpeechOutputProvider, returnExpression: String = "it") async -> ExecutionResult {
        var doc = HypeDocument.newDocument(name: "Speech tests")
        let card = doc.cards[0].id
        var button = Part(partType: .button, cardId: card, name: "Runner")
        button.script = "on mouseUp\n\(statements)\nreturn \(returnExpression)\nend mouseUp"
        doc.addPart(button)
        return await runOnLargeStack { [doc, card, button] in
            MessageDispatcher().dispatch(message: "mouseUp", params: [], targetId: button.id, document: doc, currentCardId: card, speechOutputProvider: provider)
        }
    }
}

private actor ScriptSpeechRecorder: SpeechOutputProvider {
    var requests: [ScriptSpeechRequest] = []
    var legacyTexts: [String] = []
    let warnings: [String]
    init(warnings: [String] = []) { self.warnings = warnings }
    func speakAIResponse(_ text: String, source: String) async {}
    func speakScriptText(_ text: String, source: String) async { legacyTexts.append(text) }
    func speak(_ request: ScriptSpeechRequest, source: String) async throws -> ScriptSpeechResult {
        requests.append(request)
        return ScriptSpeechResult(value: "completed", warnings: warnings)
    }
    func speechVoices() async throws -> [ScriptSpeechVoice] { [.init(id: "a", name: "Aiden"), .init(id: "r", name: "Ryan")] }
}

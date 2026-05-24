import Testing
import Foundation
@testable import HypeCore

// MARK: - Stubs

/// Stub provider that returns a fixed asset name synchronously.
private struct SuccessfulMeshyProvider: MeshyScriptingProvider {
    let assetName: String
    init(assetName: String = "generated-barrel.glb") {
        self.assetName = assetName
    }
    func generateSync(
        prompt: String, style: String?, model: String?,
        document: HypeDocument
    ) async throws -> String {
        return assetName
    }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String {
        return assetName
    }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String {
        return assetName
    }
}

/// Stub provider that always throws a gate refusal error.
private struct RefusingMeshyProvider: MeshyScriptingProvider {
    func generateSync(
        prompt: String, style: String?, model: String?,
        document: HypeDocument
    ) async throws -> String {
        throw MeshyError.noAPIKey
    }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String {
        throw MeshyError.noAPIKey
    }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String {
        throw MeshyError.noAPIKey
    }
}

// MARK: - Helpers

private func makeDoc() -> (HypeDocument, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    let btn = Part(partType: .button, cardId: cardId, name: "btn", left: 0, top: 0, width: 100, height: 30)
    doc.addPart(btn)
    let field = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 40, width: 200, height: 30)
    doc.addPart(field)
    return (doc, cardId, btn.id)
}

private func dispatchAsync(
    _ script: String,
    doc: HypeDocument,
    cardId: UUID,
    targetId: UUID,
    meshyProvider: (any MeshyScriptingProvider)?,
    runtimeProvider: (any ScriptRuntimeProviding)? = nil
) async -> ExecutionResult {
    var docVar = doc
    docVar.updatePart(id: targetId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    return await dispatcher.dispatchAsync(
        message: "mouseUp",
        params: [],
        targetId: targetId,
        document: docVar,
        currentCardId: cardId,
        meshyProvider: meshyProvider,
        runtimeProvider: runtimeProvider
    )
}

// MARK: - Tests

@Suite("Interpreter — ask meshy (Phase 3)", .serialized)
struct HypeTalkAskMeshyInterpreterTests {

    // MARK: (a) Synchronous form: result in `it` and `the result`

    @Test("ask meshy sync form puts asset name into 'it' and 'the result'")
    func syncFormPutsAssetNameInItAndResult() async throws {
        let (doc, cardId, targetId) = makeDoc()
        let provider = SuccessfulMeshyProvider(assetName: "golden-crown.glb")

        let script = """
        on mouseUp
          ask meshy "a golden crown"
          put it into field "out"
        end mouseUp
        """

        let result = await dispatchAsync(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: provider)

        let fieldText = result.modifiedDocument?.parts
            .first(where: { $0.name == "out" })?.textContent
        #expect(fieldText == "golden-crown.glb",
                "The sync form must put the asset name into 'it', which was then put into the field")
    }

    @Test("ask meshy sync form — 'the result' also holds asset name (OQ-C1)")
    func syncFormSetsTheResult() async throws {
        let (doc, cardId, targetId) = makeDoc()
        let provider = SuccessfulMeshyProvider(assetName: "a-barrel.glb")

        let script = """
        on mouseUp
          ask meshy "a barrel"
          put the result into field "out"
        end mouseUp
        """

        let result = await dispatchAsync(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: provider)

        let fieldText = result.modifiedDocument?.parts
            .first(where: { $0.name == "out" })?.textContent
        #expect(fieldText == "a-barrel.glb",
                "'the result' must be set to the asset name by the sync form (OQ-C1)")
    }

    // MARK: (b) No provider: both `it` and `the result` are ""

    @Test("ask meshy with nil provider — it and the result are empty string")
    func nilProviderSetsItAndResultToEmpty() async throws {
        let (doc, cardId, targetId) = makeDoc()

        let script = """
        on mouseUp
          ask meshy "anything"
          put it into field "out"
        end mouseUp
        """

        // Pass nil meshyProvider — should gracefully degrade to "" without throwing.
        let result = await dispatchAsync(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: nil)

        let fieldText = result.modifiedDocument?.parts
            .first(where: { $0.name == "out" })?.textContent ?? ""
        #expect(fieldText == "",
                "ask meshy with no provider must set 'it' to empty string (gate refusal, no throw)")
    }

    // MARK: (c) Gate refusal: provider throws → it = ""

    @Test("ask meshy when provider throws (gate refusal) — it set to empty string")
    func gateRefusalSetsItToEmpty() async throws {
        let (doc, cardId, targetId) = makeDoc()
        let provider = RefusingMeshyProvider()

        let script = """
        on mouseUp
          ask meshy "anything"
          put it into field "out"
        end mouseUp
        """

        let result = await dispatchAsync(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: provider)

        // The interpreter catches the error and sets it to "".
        let fieldText = result.modifiedDocument?.parts
            .first(where: { $0.name == "out" })?.textContent ?? ""
        #expect(fieldText == "",
                "ask meshy provider error must degrade to '' rather than crashing")
    }

    // MARK: (d) Style and model modifiers are forwarded to the provider

    @Test("ask meshy with style and model — modifiers forwarded to provider")
    func modifiersForwardedToProvider() async throws {
        struct CapturingProvider: MeshyScriptingProvider {
            let onCall: @Sendable (String, String?, String?) -> Void
            func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String {
                onCall(prompt, style, model)
                return "asset.glb"
            }
            func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String {
                return "asset.glb"
            }
            func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String {
                return "asset.glb"
            }
        }

        // Capture is done via an actor to avoid data races.
        actor Capture {
            var prompt: String?
            var style: String?
            var model: String?
            func set(prompt: String, style: String?, model: String?) {
                self.prompt = prompt
                self.style = style
                self.model = model
            }
        }

        let capture = Capture()
        let provider = CapturingProvider { p, s, m in
            Task { await capture.set(prompt: p, style: s, model: m) }
        }

        let (doc, cardId, targetId) = makeDoc()
        let script = """
        on mouseUp
          ask meshy "a marble pillar" with style "sculpture" with model "meshy-5"
        end mouseUp
        """

        _ = await dispatchAsync(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: provider)

        // Give the Task a moment to complete.
        try await Task.sleep(nanoseconds: 50_000_000)

        let prompt = await capture.prompt
        let style = await capture.style
        let model = await capture.model

        #expect(prompt == "a marble pillar")
        #expect(style == "sculpture")
        #expect(model == "meshy-5")
    }
}

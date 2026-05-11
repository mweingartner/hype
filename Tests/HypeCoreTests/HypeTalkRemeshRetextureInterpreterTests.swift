import Testing
import Foundation
@testable import HypeCore

// MARK: - Stubs

/// Provider that returns a fixed name for remesh/retexture.
private struct RemeshSuccessProvider: MeshyScriptingProvider {
    let assetName: String
    init(assetName: String = "barrel-remesh.glb") { self.assetName = assetName }
    func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String { assetName }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String { assetName }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String { assetName }
}

/// Provider that always throws noAPIKey.
private struct RemeshRefusingProvider: MeshyScriptingProvider {
    func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String { throw MeshyError.noAPIKey }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String { throw MeshyError.noAPIKey }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String { throw MeshyError.noAPIKey }
}

// MARK: - Helpers

/// Creates a doc with a button ("btn") and an output field ("out").
private func makeDoc() -> (HypeDocument, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    var btn = Part(partType: .button, cardId: cardId, name: "btn", left: 0, top: 0, width: 100, height: 30)
    doc.addPart(btn)
    var field = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 40, width: 200, height: 30)
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

private func fieldText(_ result: ExecutionResult) -> String? {
    result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent
}

// MARK: - Tests

@Suite("Interpreter — remesh asset / retexture asset (Phase 4)")
struct HypeTalkRemeshRetextureInterpreterTests {

    // MARK: (a) Sync remesh sets `it` and `the result` to new asset name

    @Test("Sync remesh sets it to the new asset name (captured in field)")
    func syncRemeshSetsIt() async {
        let (doc, cardId, targetId) = makeDoc()
        let script = """
        on mouseUp
          remesh asset "barrel" to 5000
          put it into field "out"
        end mouseUp
        """
        let result = await dispatchAsync(
            script,
            doc: doc, cardId: cardId, targetId: targetId,
            meshyProvider: RemeshSuccessProvider(assetName: "barrel-remesh.glb")
        )
        #expect(fieldText(result) == "barrel-remesh.glb",
                "Sync remesh must put new asset name into `it`, then into the field")
    }

    @Test("Sync remesh — the result also holds asset name")
    func syncRemeshSetsTheResult() async {
        let (doc, cardId, targetId) = makeDoc()
        let script = """
        on mouseUp
          remesh asset "barrel" to 5000
          put the result into field "out"
        end mouseUp
        """
        let result = await dispatchAsync(
            script,
            doc: doc, cardId: cardId, targetId: targetId,
            meshyProvider: RemeshSuccessProvider(assetName: "barrel-remesh.glb")
        )
        #expect(fieldText(result) == "barrel-remesh.glb",
                "Sync remesh must put new asset name into `the result`")
    }

    // MARK: (b) Async remesh (with message) sets `it` to a UUID string

    @Test("Async remesh (with message) sets it to a request UUID string")
    func asyncRemeshSetsItToUUID() async throws {
        let (doc, cardId, targetId) = makeDoc()

        var docVar = doc
        docVar.stack.meshyEnabled = true

        let config = StackRuntimeConfiguration(meshyProvider: RemeshSuccessProvider())
        let runtime = await StackRuntimeRegistry.shared.runtime(for: docVar, configuration: config)

        let script = """
        on mouseUp
          remesh asset "barrel" to 5000 with message "remeshDone"
          put it into field "out"
        end mouseUp
        """
        let result = await dispatchAsync(
            script,
            doc: docVar, cardId: cardId, targetId: targetId,
            meshyProvider: nil,
            runtimeProvider: runtime
        )
        let itValue = fieldText(result) ?? ""
        #expect(!itValue.isEmpty, "`it` must be set to the request id on async form")

        await StackRuntimeRegistry.shared.shutdown(stackID: docVar.stack.id)
    }

    // MARK: (c) Gate refusal sets `it` to ""

    @Test("Gate refusal (no API key) sets it to empty string in sync form")
    func gateRefusalSetsItToEmpty() async {
        let (doc, cardId, targetId) = makeDoc()
        let script = """
        on mouseUp
          remesh asset "barrel" to 5000
          put it into field "out"
        end mouseUp
        """
        let result = await dispatchAsync(
            script,
            doc: doc, cardId: cardId, targetId: targetId,
            meshyProvider: RemeshRefusingProvider()
        )
        #expect(fieldText(result) == "" || fieldText(result) == nil,
                "Gate refusal must set `it` to empty string")
    }

    // MARK: (d) Sync retexture sets `it` and `the result`

    @Test("Sync retexture sets it to the new asset name (captured in field)")
    func syncRetextureSetsIt() async {
        let (doc, cardId, targetId) = makeDoc()
        let script = """
        on mouseUp
          retexture asset "barrel" with prompt "rusty iron"
          put it into field "out"
        end mouseUp
        """
        let result = await dispatchAsync(
            script,
            doc: doc, cardId: cardId, targetId: targetId,
            meshyProvider: RemeshSuccessProvider(assetName: "barrel-retex.glb")
        )
        #expect(fieldText(result) == "barrel-retex.glb",
                "Sync retexture must put new asset name into `it`")
    }

    // MARK: (e) Retexture gate refusal sets `it` to ""

    @Test("Retexture gate refusal sets it to empty string")
    func retextureGateRefusalSetsItToEmpty() async {
        let (doc, cardId, targetId) = makeDoc()
        let script = """
        on mouseUp
          retexture asset "barrel" with prompt "marble"
          put it into field "out"
        end mouseUp
        """
        let result = await dispatchAsync(
            script,
            doc: doc, cardId: cardId, targetId: targetId,
            meshyProvider: RemeshRefusingProvider()
        )
        #expect(fieldText(result) == "" || fieldText(result) == nil)
    }
}

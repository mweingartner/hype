import Testing
import Foundation
@testable import HypeCore

// MARK: - Stubs

private struct SuccessfulMeshyProvider: MeshyScriptingProvider {
    let assetName: String
    init(assetName: String = "generated-barrel.glb") {
        self.assetName = assetName
    }
    func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String {
        return assetName
    }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String {
        return assetName
    }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String {
        return assetName
    }
}

private struct ThrowingMeshyProvider: MeshyScriptingProvider {
    func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String {
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
    var field = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 40, width: 200, height: 30)
    doc.addPart(field)
    return (doc, cardId, btn.id)
}

private func dispatch(
    _ script: String,
    doc: HypeDocument,
    cardId: UUID,
    targetId: UUID,
    meshyProvider: (any MeshyScriptingProvider)?
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
        meshyProvider: meshyProvider
    )
}

// MARK: - Tests

@Suite("Interpreter — ask meshy expression form (Phase 5)", .serialized)
struct HypeTalkAskMeshyExpressionInterpreterTests {

    // MARK: (a) `put ask meshy "barrel" into x` stores the asset name in x

    @Test("put ask meshy expression — asset name stored in target variable")
    func putAskMeshyStoresAssetNameInVariable() async throws {
        let (doc, cardId, targetId) = makeDoc()
        let provider = SuccessfulMeshyProvider(assetName: "wooden-barrel.glb")

        let script = """
        on mouseUp
          put ask meshy "a wooden barrel, low poly" into newModel
          put newModel into field "out"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: provider)
        let fieldText = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent
        #expect(fieldText == "wooden-barrel.glb",
                "The expression form must put the asset name into the target variable")
    }

    // MARK: (b) `the result` is NOT set by the expression form (only by the statement form)

    @Test("put ask meshy expression — the result is NOT set")
    func putAskMeshyExpressionDoesNotSetTheResult() async throws {
        let (doc, cardId, targetId) = makeDoc()
        let provider = SuccessfulMeshyProvider(assetName: "barrel.glb")

        // The expression form should NOT set `the result` — only the statement form does.
        // We verify by checking `the result` is "" after a pure expression-form call.
        let script = """
        on mouseUp
          put ask meshy "a barrel" into newModel
          put the result into field "out"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: provider)
        let fieldText = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        // `the result` should be empty because the expression form does not set it.
        #expect(fieldText == "",
                "Expression form must NOT set 'the result'; only Statement.askMeshy does")
    }

    // MARK: (c) Gate refusal — nil provider → expression returns ""

    @Test("put ask meshy with nil provider — expression returns empty string")
    func nilProviderExpressionReturnsEmpty() async throws {
        let (doc, cardId, targetId) = makeDoc()

        let script = """
        on mouseUp
          put ask meshy "anything" into newModel
          put newModel into field "out"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: nil)
        let fieldText = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        #expect(fieldText == "",
                "Expression form with nil provider must return empty string without throwing")
    }

    // MARK: (d) Gate refusal — provider throws → expression returns ""

    @Test("put ask meshy when provider throws — expression returns empty string")
    func throwingProviderExpressionReturnsEmpty() async throws {
        let (doc, cardId, targetId) = makeDoc()
        let provider = ThrowingMeshyProvider()

        let script = """
        on mouseUp
          put ask meshy "anything" into newModel
          put newModel into field "out"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: provider)
        let fieldText = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        #expect(fieldText == "",
                "Expression form must return '' on provider error rather than crashing")
    }

    // MARK: (e) End-to-end: put ask meshy into variable, set the model of scene3d to variable

    @Test("end-to-end: generate model and bind to scene3d part via variable")
    func endToEndGenerateAndBind() async throws {
        let (basedoc, cardId, targetId) = makeDoc()
        var doc = basedoc
        let provider = SuccessfulMeshyProvider(assetName: "wooden-barrel.glb")

        // Add a model3D asset to the repository so the resolver can find it.
        let asset = SpriteAsset(
            name: "wooden-barrel.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary"
        )
        doc.spriteRepository.addAsset(asset)

        // Add a scene3D part to the card.
        let viewer = Part(partType: .scene3D, cardId: cardId, name: "Viewer")
        doc.addPart(viewer)

        let script = """
        on mouseUp
          put ask meshy "a wooden barrel, low poly" into newModel
          set the model of scene3d "Viewer" to newModel
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId, meshyProvider: provider)

        guard let modifiedDoc = result.modifiedDocument else {
            Issue.record("Expected a modified document")
            return
        }
        let viewerPart = modifiedDoc.parts.first(where: { $0.name == "Viewer" })
        #expect(viewerPart?.scene3DAssetRef != nil,
                "The scene3D part should have an asset ref bound after set the model ... to newModel")
        #expect(viewerPart?.scene3DAssetRef?.name == "wooden-barrel.glb",
                "The bound asset ref should reference the newly generated asset")
    }
}

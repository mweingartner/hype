import Testing
import Foundation
@testable import HypeCore

// MARK: - Helpers

private func makeDocWithScene3DAndAsset(assetName: String = "wooden-barrel.glb") -> (HypeDocument, UUID, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id

    // A button to hold the test script.
    let btn = Part(partType: .button, cardId: cardId, name: "btn")
    doc.addPart(btn)

    // A scene3D part to bind to.
    let viewer = Part(partType: .scene3D, cardId: cardId, name: "Viewer")
    doc.addPart(viewer)

    // A model3D asset in the Asset Repository.
    let asset = Asset(
        name: assetName,
        kind: .model3D,
        mimeType: "model/gltf-binary"
    )
    doc.assetRepository.addAsset(asset)

    return (doc, cardId, btn.id, viewer.id)
}

private func dispatch(
    _ script: String,
    doc: HypeDocument,
    cardId: UUID,
    targetId: UUID
) async -> ExecutionResult {
    var docVar = doc
    docVar.updatePart(id: targetId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    return await dispatcher.dispatchAsync(
        message: "mouseUp",
        params: [],
        targetId: targetId,
        document: docVar,
        currentCardId: cardId
    )
}

// MARK: - Tests: set/get round-trip via `the model` property

@Suite("Interpreter — scene3D model property binding (Phase 5)")
struct HypeTalkScene3DModelBindingTests {

    // MARK: (a) set the model of scene3d "Viewer" to "<asset-name>" binds via AssetRef

    @Test("set the model of scene3d binds asset ref when name is in repository")
    func setModelBindsAssetRef() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "wooden-barrel.glb")

        let script = """
        on mouseUp
          set the model of scene3d "Viewer" to "wooden-barrel.glb"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let viewer = modified.parts.first(where: { $0.name == "Viewer" })
        #expect(viewer?.scene3DAssetRef != nil,
                "scene3DAssetRef must be set when asset name matches a model3D in the repository")
        #expect(viewer?.scene3DAssetRef?.name == "wooden-barrel.glb",
                "scene3DAssetRef.name must match the bound asset name")
        // URL fields must be cleared when asset-ref path wins.
        #expect(viewer?.scene3DURL == "",
                "scene3DURL must be cleared when bound via asset ref")
        #expect(viewer?.scene3DSourceURL == "",
                "scene3DSourceURL must be cleared when bound via asset ref")
    }

    @Test("set the model of scene3d binds by extensionless repository asset stem")
    func setModelBindsExtensionlessAssetStem() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "wooden-barrel.glb")

        let script = """
        on mouseUp
          set the model of scene3d "Viewer" to "wooden-barrel"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId)
        let viewer = result.modifiedDocument?.parts.first(where: { $0.name == "Viewer" })
        #expect(viewer?.scene3DAssetRef?.name == "wooden-barrel.glb",
                "extensionless scene3D model names should bind to matching model3D repository assets")
        #expect(viewer?.scene3DURL == "")
    }

    @Test("set the modelAsset alias of scene3d binds through the shared resolver")
    func setModelAssetAliasBindsAssetRef() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "barrel.glb")

        let script = """
        on mouseUp
          set the modelAsset of scene3d "Viewer" to "barrel"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId)
        let viewer = result.modifiedDocument?.parts.first(where: { $0.name == "Viewer" })
        #expect(viewer?.scene3DAssetRef?.name == "barrel.glb")
        #expect(viewer?.scene3DSourceURL == "")
    }

    // MARK: (b) get round-trip — `the model of scene3d "Viewer"` returns asset name

    @Test("get the model of scene3d returns asset name when bound via asset ref")
    func getModelReturnsAssetName() async throws {
        let (doc, cardId, targetId, viewerId) = makeDocWithScene3DAndAsset(assetName: "barrel.glb")

        var docVar = doc
        // Pre-bind the asset ref directly.
        let asset = docVar.assetRepository.asset(byName: "barrel.glb")!
        let assetRef = docVar.assetRepository.assetRef(for: asset)
        docVar.updatePart(id: viewerId) { $0.scene3DAssetRef = assetRef }

        let script = """
        on mouseUp
          put the model of scene3d "Viewer" into field "result"
        end mouseUp
        """
        var docWithField = docVar
        let field = Part(partType: .field, cardId: cardId, name: "result")
        docWithField.addPart(field)
        docWithField.updatePart(id: targetId) { $0.script = script }

        let dispatcher = MessageDispatcher()
        let result = await dispatcher.dispatchAsync(
            message: "mouseUp",
            params: [],
            targetId: targetId,
            document: docWithField,
            currentCardId: cardId
        )
        let fieldText = result.modifiedDocument?.parts.first(where: { $0.name == "result" })?.textContent
        #expect(fieldText == "barrel.glb",
                "the model getter must return the asset name when bound via scene3DAssetRef")
    }

    // MARK: (c) fallback — unknown asset name resolves to file-path path

    @Test("set the model with unknown asset name falls back to file-path resolver")
    func setModelFallsBackToFilePath() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "wooden-barrel.glb")

        // Use a path that is not in the repository.
        let script = """
        on mouseUp
          set the model of scene3d "Viewer" to "/tmp/cube.usdz"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let viewer = modified.parts.first(where: { $0.name == "Viewer" })
        // File path should have been stored in source URL, NOT bound as an asset ref.
        #expect(viewer?.scene3DAssetRef == nil,
                "scene3DAssetRef must NOT be set when the value is a file path")
        #expect(viewer?.scene3DSourceURL == "/tmp/cube.usdz",
                "scene3DSourceURL must be set to the file path for fallback resolution")
    }

    // MARK: (c2) Stale-ref clearing (Security Finding 3)

    /// Asserts that switching a scene3D part from an asset-ref binding to a
    /// file path properly nils out the prior `scene3DAssetRef`. Without this,
    /// the getter precedence rule (assetRef first, URL fallback) would
    /// continue to return the stale asset name even after the author rebound
    /// to a file path.
    @Test("rebinding model from asset name to file path clears scene3DAssetRef")
    func rebindingClearsStaleAssetRef() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "wooden-barrel.glb")

        // Step 1: bind to the repository asset (sets scene3DAssetRef).
        let bindScript = """
        on mouseUp
          set the model of scene3d "Viewer" to "wooden-barrel.glb"
        end mouseUp
        """
        let bindResult = await dispatch(bindScript, doc: doc, cardId: cardId, targetId: targetId)
        guard let afterBind = bindResult.modifiedDocument else {
            Issue.record("Expected modified document after bind")
            return
        }
        let viewerBound = afterBind.parts.first(where: { $0.name == "Viewer" })
        #expect(viewerBound?.scene3DAssetRef != nil, "Pre-condition: asset ref must be set")

        // Step 2: rebind to a file path (must clear scene3DAssetRef).
        let rebindScript = """
        on mouseUp
          set the model of scene3d "Viewer" to "/tmp/cube.usdz"
        end mouseUp
        """
        let rebindResult = await dispatch(rebindScript, doc: afterBind, cardId: cardId, targetId: targetId)
        guard let afterRebind = rebindResult.modifiedDocument else {
            Issue.record("Expected modified document after rebind")
            return
        }
        let viewerRebound = afterRebind.parts.first(where: { $0.name == "Viewer" })
        #expect(viewerRebound?.scene3DAssetRef == nil,
                "scene3DAssetRef must be cleared when rebinding to a file path")
        #expect(viewerRebound?.scene3DSourceURL == "/tmp/cube.usdz",
                "scene3DSourceURL must hold the new file path")
    }

    // MARK: (d) set/get round-trip through setter and getter

    @Test("set the model then get the model returns the same asset name")
    func setGetRoundTrip() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "space-fighter.glb")

        var docWithField = doc
        let field = Part(partType: .field, cardId: cardId, name: "result")
        docWithField.addPart(field)

        let script = """
        on mouseUp
          set the model of scene3d "Viewer" to "space-fighter.glb"
          put the model of scene3d "Viewer" into field "result"
        end mouseUp
        """

        let result = await dispatch(script, doc: docWithField, cardId: cardId, targetId: targetId)
        let fieldText = result.modifiedDocument?.parts.first(where: { $0.name == "result" })?.textContent
        #expect(fieldText == "space-fighter.glb",
                "set then get the model must return the same asset name (round-trip)")
    }
}

// MARK: - Tests: `put X into the model of scene3d "Y"` container form

@Suite("Interpreter — put into model container (Phase 5)")
struct HypeTalkPutIntoModelContainerTests {

    // MARK: (a) `put "asset-name" into the model of scene3d "Viewer"` binds via AssetRef

    @Test("put into the model of scene3d binds asset ref when name is in repository")
    func putIntoModelBindsAssetRef() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "wooden-barrel.glb")

        let script = """
        on mouseUp
          put "wooden-barrel.glb" into the model of scene3d "Viewer"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let viewer = modified.parts.first(where: { $0.name == "Viewer" })
        #expect(viewer?.scene3DAssetRef != nil,
                "put into the model must bind scene3DAssetRef when asset name is in repository")
        #expect(viewer?.scene3DAssetRef?.name == "wooden-barrel.glb")
    }

    // MARK: (b) `put "/path/to/file.usdz" into the model of scene3d "Viewer"` falls back to path

    @Test("put into the model falls back to file path when asset name not in repository")
    func putIntoModelFallsBackToFilePath() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "wooden-barrel.glb")

        let script = """
        on mouseUp
          put "/tmp/alien.usdz" into the model of scene3d "Viewer"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let viewer = modified.parts.first(where: { $0.name == "Viewer" })
        #expect(viewer?.scene3DAssetRef == nil,
                "put into the model must NOT set asset ref when value is a file path")
        #expect(viewer?.scene3DSourceURL == "/tmp/alien.usdz",
                "scene3DSourceURL must be set to the file path when fallback path is used")
    }

    // MARK: (c) the object property also accepts asset names with the same smart resolver

    @Test("set the object of scene3d with asset name binds via asset ref")
    func setObjectAlsoAcceptsAssetName() async throws {
        let (doc, cardId, targetId, _) = makeDocWithScene3DAndAsset(assetName: "barrel.glb")

        let script = """
        on mouseUp
          set the object of scene3d "Viewer" to "barrel.glb"
        end mouseUp
        """

        let result = await dispatch(script, doc: doc, cardId: cardId, targetId: targetId)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let viewer = modified.parts.first(where: { $0.name == "Viewer" })
        #expect(viewer?.scene3DAssetRef != nil,
                "set the object property must also bind asset ref when name is in repository (smart resolver)")
        #expect(viewer?.scene3DAssetRef?.name == "barrel.glb")
    }
}

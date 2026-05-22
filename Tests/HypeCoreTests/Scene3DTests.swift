import Testing
import Foundation
@testable import HypeCore

/// SceneKit-backed `scene3D` part. Tests focus on model + AI tool +
/// HypeTalk surface; the live SCNView is not instantiated.
@Suite("Scene3D — model, AI tools, HypeTalk grammar")
struct Scene3DTests {

    @Test("Defaults: empty URL, camera control on, lighting on, 4× MSAA")
    func defaults() {
        let part = Part(partType: .scene3D, name: "model")
        #expect(part.partType == .scene3D)
        #expect(part.scene3DURL == "")
        #expect(part.scene3DAllowsCameraControl == true)
        #expect(part.scene3DAutoLighting == true)
        #expect(part.scene3DAntialiasing == "multisampling4X")
        #expect(part.scene3DBackground == "")
    }

    @Test("Scene3D fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .scene3D, name: "model")
        part.scene3DURL = "/tmp/cube.usdz"
        part.scene3DAllowsCameraControl = false
        part.scene3DAutoLighting = false
        part.scene3DBackground = "#102030"
        part.scene3DAntialiasing = "multisampling2X"
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.scene3DURL == "/tmp/cube.usdz")
        #expect(decoded.scene3DAllowsCameraControl == false)
        #expect(decoded.scene3DAutoLighting == false)
        #expect(decoded.scene3DBackground == "#102030")
        #expect(decoded.scene3DAntialiasing == "multisampling2X")
    }

    @Test("create_scene3d builds a part with the requested fields")
    func aiCreate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_scene3d",
            arguments: [
                "name": "model",
                "left": "0", "top": "0", "width": "400", "height": "300",
                "model_url": "/tmp/cube.usdz",
                "allows_camera_control": "false",
                "auto_lighting": "false",
                "background": "#102030",
                "antialiasing": "multisampling2X"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .scene3D }
        #expect(part?.scene3DURL == "/tmp/cube.usdz")
        #expect(part?.scene3DAllowsCameraControl == false)
        #expect(part?.scene3DAutoLighting == false)
        #expect(part?.scene3DBackground == "#102030")
        #expect(part?.scene3DAntialiasing == "multisampling2X")
    }

    @Test("Unknown antialiasing falls back to multisampling4X")
    func aiCreateUnknownAA() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_scene3d",
            arguments: ["name": "model", "left": "0", "top": "0", "width": "200", "height": "200", "antialiasing": "purple-monkey"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .scene3D }?.scene3DAntialiasing == "multisampling4X")
    }

    @Test("set_part_property updates modelURL on a scene3D")
    func aiSetModelURL() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_scene3d",
            arguments: ["name": "model", "left": "0", "top": "0", "width": "200", "height": "200"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "model", "property": "model_url", "value": "/tmp/x.scn"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .scene3D }?.scene3DURL == "/tmp/x.scn")
    }

    @Test("set_part_property modelAsset binds repository model by extensionless stem")
    func aiSetModelAssetBindsRepositoryStem() async throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let model = SpriteAsset(name: "creature.glb", kind: .model3D, mimeType: "model/gltf-binary")
        doc.spriteRepository.addAsset(model)
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_scene3d",
            arguments: ["name": "model", "left": "0", "top": "0", "width": "200", "height": "200"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "model", "property": "modelAsset", "value": "creature"],
            document: &doc, currentCardId: cardId
        )

        let part = try #require(doc.parts.first { $0.partType == .scene3D })
        #expect(part.scene3DAssetRef?.id == model.id)
        #expect(part.scene3DAssetRef?.name == "creature.glb")
        #expect(part.scene3DURL == "")
        #expect(part.scene3DSourceURL == "")
    }

    @Test("Parser accepts `the modelURL of scene3d \"X\"`")
    func hypeTalkScene3D() throws {
        let source = "the modelURL of scene3d \"model\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "modelURL",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "scene3d")
        } else {
            Issue.record("expected propertyAccess(modelURL, objectRef(scene3d, ...)), got \(expr)")
        }
    }

    @Test("Parser accepts `model3d` as an alias for scene3d")
    func hypeTalkModel3DAlias() throws {
        let source = "the modelURL of model3d \"x\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(_, let target) = expr,
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "model3d")
        } else {
            Issue.record("expected objectRef(model3d, ...), got \(expr)")
        }
    }

    // MARK: - STL / object property end-to-end

    @Test("scene3DSourceURL defaults to empty string")
    func sourceURLDefault() {
        let part = Part(partType: .scene3D, name: "model")
        #expect(part.scene3DSourceURL == "")
    }

    @Test("scene3DSourceURL and scene3DURL round-trip through Codable")
    func sourceURLCodable() throws {
        var part = Part(partType: .scene3D, name: "model")
        part.scene3DURL = "/tmp/cache/abc.obj"
        part.scene3DSourceURL = "/original/cube.stl"
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.scene3DURL == "/tmp/cache/abc.obj")
        #expect(decoded.scene3DSourceURL == "/original/cube.stl")
    }

    @Test("Old documents without scene3DSourceURL decode with default empty string")
    func sourceURLBackwardCompat() throws {
        var part = Part(partType: .scene3D, name: "model")
        part.scene3DURL = "/tmp/cube.usdz"
        let data = try JSONEncoder().encode(part)
        // Strip scene3DSourceURL to simulate an old document.
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "scene3DSourceURL")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.scene3DSourceURL == "")
        #expect(decoded.scene3DURL == "/tmp/cube.usdz")
    }

    @Test("get_part_property 'object' returns scene3DSourceURL when set")
    func aiGetObjectProp() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_scene3d",
            arguments: ["name": "model", "left": "0", "top": "0", "width": "200", "height": "200"],
            document: &doc, currentCardId: cardId
        )
        // Set scene3DSourceURL manually to simulate an existing source path.
        if let idx = doc.parts.firstIndex(where: { $0.partType == .scene3D }) {
            doc.parts[idx].scene3DSourceURL = "/src/cube.usdz"
            doc.parts[idx].scene3DURL = "/src/cube.usdz"
        }
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "model", "property": "object"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "/src/cube.usdz")
    }

    @Test("set_part_property 'object' stores source URL and resolved URL")
    func aiSetObjectProp() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_scene3d",
            arguments: ["name": "model", "left": "0", "top": "0", "width": "200", "height": "200"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "model", "property": "object", "value": "/tmp/cube.usdz"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .scene3D }
        // For a non-STL file, source and resolved URL should match.
        #expect(part?.scene3DSourceURL == "/tmp/cube.usdz")
        #expect(part?.scene3DURL == "/tmp/cube.usdz")
    }

    @Test("create_scene3d with object arg sets scene3DSourceURL")
    func aiCreateWithObjectArg() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_scene3d",
            arguments: [
                "name": "model",
                "left": "0", "top": "0", "width": "400", "height": "300",
                "object": "/tmp/robot.usdz"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .scene3D }
        #expect(part?.scene3DSourceURL == "/tmp/robot.usdz")
        #expect(part?.scene3DURL == "/tmp/robot.usdz")
    }

    @Test("create_scene3d: object arg takes precedence over model_url")
    func aiCreateObjectPrecedence() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_scene3d",
            arguments: [
                "name": "model",
                "left": "0", "top": "0", "width": "400", "height": "300",
                "object": "/tmp/preferred.usdz",
                "model_url": "/tmp/legacy.usdz"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .scene3D }
        // "object" wins over "model_url".
        #expect(part?.scene3DSourceURL == "/tmp/preferred.usdz")
    }

    @Test("repository GLB resolves to same-task USDZ companion for rendering")
    func glbResolvesToTaskCompanionUSDZ() throws {
        let taskId = "task_123"
        var glb = SpriteAsset(name: "wooden-barrel.glb", kind: .model3D, mimeType: "model/gltf-binary")
        glb.provenance = AssetProvenance(
            origin: .aiGenerated,
            attribution: AssetAttribution(providerIdentifier: "meshy", taskId: taskId)
        )
        var usdz = SpriteAsset(name: "other-name.usdz", kind: .model3D, mimeType: "model/vnd.usdz+zip")
        usdz.provenance = AssetProvenance(
            origin: .aiGenerated,
            attribution: AssetAttribution(providerIdentifier: "meshy", taskId: taskId)
        )
        let repo = SpriteRepository(assets: [glb, usdz])
        let ref = repo.assetRef(for: glb)

        let resolved = try #require(Scene3DRepositoryAssetResolver.resolvedAsset(for: ref, in: repo))
        #expect(resolved.selectedAsset.id == glb.id)
        #expect(resolved.renderAsset.id == usdz.id)
        #expect(resolved.usesCompanionAsset)
    }

    @Test("repository GLB resolves to same-base USDZ companion for rendering")
    func glbResolvesToSameBaseUSDZ() throws {
        let glb = SpriteAsset(name: "space-fighter.glb", kind: .model3D, mimeType: "model/gltf-binary")
        let usdz = SpriteAsset(name: "space-fighter.usdz", kind: .model3D, mimeType: "model/vnd.usdz+zip")
        let repo = SpriteRepository(assets: [glb, usdz])
        let resolved = try #require(Scene3DRepositoryAssetResolver.resolvedAsset(for: repo.assetRef(for: glb), in: repo))

        #expect(resolved.renderAsset.id == usdz.id)
        #expect(resolved.usesCompanionAsset)
    }

    @Test("repository GLB resolves to newest same-base USDZ companion")
    func glbResolvesToNewestSameBaseUSDZ() throws {
        let glb = SpriteAsset(name: "space-fighter.glb", kind: .model3D, mimeType: "model/gltf-binary")
        let staleUSDZ = SpriteAsset(name: "space-fighter.usdz", kind: .model3D, mimeType: "model/vnd.usdz+zip", data: Data([1]))
        let newestUSDZ = SpriteAsset(name: "space-fighter.usdz", kind: .model3D, mimeType: "model/vnd.usdz+zip", data: Data([2]))
        let repo = SpriteRepository(assets: [glb, staleUSDZ, newestUSDZ])
        let resolved = try #require(Scene3DRepositoryAssetResolver.resolvedAsset(for: repo.assetRef(for: glb), in: repo))

        #expect(resolved.renderAsset.id == newestUSDZ.id)
        #expect(resolved.usesCompanionAsset)
    }

    @Test("repository GLB without USDZ companion is marked as companion-required")
    func glbWithoutCompanionRequiresUSDZ() throws {
        let glb = SpriteAsset(name: "solo.glb", kind: .model3D, mimeType: "model/gltf-binary")
        let repo = SpriteRepository(assets: [glb])
        let resolved = try #require(Scene3DRepositoryAssetResolver.resolvedAsset(for: repo.assetRef(for: glb), in: repo))

        #expect(resolved.renderAsset.id == glb.id)
        #expect(!resolved.usesCompanionAsset)
        #expect(Scene3DRepositoryAssetResolver.requiresCompanionForSceneKit(glb))
    }

    @Test("scene3D repository resolver ignores non-model assets")
    func scene3DResolverIgnoresNonModelAssets() throws {
        let image = SpriteAsset(name: "robot.glb", kind: .imageTexture, mimeType: "model/gltf-binary", data: Data([1]))
        let repo = SpriteRepository(assets: [image])

        #expect(Scene3DRepositoryAssetResolver.selectedAsset(for: repo.assetRef(for: image), in: repo) == nil)
        #expect(Scene3DRepositoryAssetResolver.resolvedAsset(for: repo.assetRef(for: image), in: repo) == nil)
    }

    @Test("scene3D load identity changes when embedded asset bytes change without size change")
    func scene3DLoadIdentityFingerprintsBytes() throws {
        let first = SpriteAsset(name: "robot.usdz", kind: .model3D, mimeType: "model/vnd.usdz+zip", data: Data([1, 2, 3]))
        var second = SpriteAsset(name: "robot.usdz", kind: .model3D, mimeType: "model/vnd.usdz+zip", data: Data([1, 2, 4]))
        second.id = first.id
        let ref = SpriteRepository(assets: [first]).assetRef(for: first)

        let firstKey = Scene3DRepositoryAssetResolver.loadIdentity(
            for: ref,
            in: SpriteRepository(assets: [first]),
            fallbackURL: ""
        )
        let secondKey = Scene3DRepositoryAssetResolver.loadIdentity(
            for: ref,
            in: SpriteRepository(assets: [second]),
            fallbackURL: ""
        )

        #expect(firstKey != secondKey)
    }
}

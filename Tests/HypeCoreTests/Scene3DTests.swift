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
}

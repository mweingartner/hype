import Testing
import AppKit
import SpriteKit
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("LiveSceneStateSync readback")
struct LiveSceneStateReadbackTests {

    // MARK: - CoordinateConverter round-trips

    @Test("position round-trip: toSK then toHype is identity")
    func positionRoundTripIsIdentity() {
        let converter = CoordinateConverter(sceneHeight: 600)
        let original = PointSpec(x: 120, y: 340)
        let sk = converter.toSK(original)
        let recovered = converter.toHype(sk)
        #expect(recovered.x == original.x)
        #expect(recovered.y == original.y)
    }

    @Test("rotation round-trip: toSKRotation then toHypeRotation is identity")
    func rotationRoundTripIsIdentity() {
        let converter = CoordinateConverter(sceneHeight: 600)
        let originalDegrees = 45.0
        let skRadians = converter.toSKRotation(originalDegrees)
        let recoveredDegrees = converter.toHypeRotation(skRadians)
        #expect(abs(recoveredDegrees - originalDegrees) < 1e-10)
    }

    @Test("velocityY sign convention: forward pass is sign-preserving")
    func velocityYSignConventionIsSignPreserving() {
        // The forward pass (SceneBridge: spec→SK) writes:
        //   body.velocity = CGVector(dx: velocityX, dy: velocityY)
        // with no sign flip. The reverse pass (LiveSceneStateSync: SK→spec) must
        // be identical: specVelocityY = body.velocity.dy.
        // This test formalises that invariant by constructing a node with a known
        // authored velocityY, applying it through SceneBridge (forward), and then
        // reading it back through LiveSceneStateSync (reverse).
        var body = PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            velocityX: 50,
            velocityY: -200   // downward in Hype's coordinate system
        )
        body.affectedByGravity = false
        var nodeSpec = HypeNodeSpec(
            name: "ball",
            nodeType: .sprite,
            position: PointSpec(x: 100, y: 100)
        )
        nodeSpec.size = SizeSpec(width: 20, height: 20)
        nodeSpec.physicsBody = body

        let scene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 400, height: 300),
            nodes: [nodeSpec]
        )
        let bridge = SceneBridge(sceneHeight: scene.size.height)
        let skScene = SKScene(size: CGSize(width: scene.size.width, height: scene.size.height))
        bridge.apply(spec: scene, to: skScene, repository: AssetRepository())

        // The live SKNode should now have the authored velocity applied.
        let liveNode = bridge.registry.node(for: nodeSpec.id)
        let skVelocityY = Double(liveNode?.physicsBody?.velocity.dy ?? 0)

        // Forward pass wrote velocityY = -200 into dy with no sign flip.
        #expect(skVelocityY == -200)

        // Now read back through LiveSceneStateSync.
        let merged = LiveSceneStateSync.merged(
            scene: scene,
            registry: bridge.registry,
            sceneHeight: scene.size.height
        )
        let mergedVelocityY = merged.node(named: "ball")?.physicsBody?.velocityY
        // Reverse pass must match the forward pass: no sign flip.
        #expect(mergedVelocityY == skVelocityY)
    }

    // MARK: - LiveSceneStateSync.merged

    @Test("merged overwrites position+velocity for a node with a live SKNode")
    func mergedOverwritesLiveNodePositionAndVelocity() {
        // Build a one-node SceneSpec and present it via SceneBridge so the
        // registry is populated.
        var body = PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            velocityX: 0,
            velocityY: 0
        )
        body.affectedByGravity = false
        var nodeSpec = HypeNodeSpec(
            name: "ball",
            nodeType: .sprite,
            position: PointSpec(x: 50, y: 50)
        )
        nodeSpec.size = SizeSpec(width: 20, height: 20)
        nodeSpec.physicsBody = body

        let sceneSize = SizeSpec(width: 400, height: 300)
        let scene = SceneSpec(
            name: "test",
            size: sceneSize,
            nodes: [nodeSpec]
        )
        let bridge = SceneBridge(sceneHeight: sceneSize.height)
        let skScene = SKScene(size: CGSize(width: sceneSize.width, height: sceneSize.height))
        bridge.apply(spec: scene, to: skScene, repository: AssetRepository())

        // Simulate physics moving the ball to a known SK position and giving it velocity.
        let skLiveX: CGFloat = 160
        let skLiveY: CGFloat = 120
        let skVelocityDX: CGFloat = 75
        let skVelocityDY: CGFloat = -150
        if let liveNode = bridge.registry.node(for: nodeSpec.id) {
            liveNode.position = CGPoint(x: skLiveX, y: skLiveY)
            liveNode.physicsBody?.velocity = CGVector(dx: skVelocityDX, dy: skVelocityDY)
        }

        // Merge live state back into the spec.
        let merged = LiveSceneStateSync.merged(
            scene: scene,
            registry: bridge.registry,
            sceneHeight: sceneSize.height
        )

        let mergedNode = merged.node(named: "ball")

        // Position: converter.toHype(PointSpec(x: 160, y: 120)) with sceneHeight=300
        // → hypeY = 300 - 120 = 180
        let converter = CoordinateConverter(sceneHeight: sceneSize.height)
        let expectedHypePos = converter.toHype(PointSpec(x: Double(skLiveX), y: Double(skLiveY)))

        #expect(mergedNode?.position.x == expectedHypePos.x)
        #expect(mergedNode?.position.y == expectedHypePos.y)

        // Velocity: no sign flip (mirrors SceneBridge forward pass)
        #expect(mergedNode?.physicsBody?.velocityX == Double(skVelocityDX))
        #expect(mergedNode?.physicsBody?.velocityY == Double(skVelocityDY))
    }

    @Test("merged leaves a node unchanged when it has no live SKNode")
    func mergedLeavesUnregisteredNodeUnchanged() {
        let nodeSpec = HypeNodeSpec(
            name: "ghost",
            nodeType: .sprite,
            position: PointSpec(x: 77, y: 88)
        )
        let scene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 400, height: 300),
            nodes: [nodeSpec]
        )

        // Empty registry — no live nodes registered.
        let emptyRegistry = NodeRegistry()

        let merged = LiveSceneStateSync.merged(
            scene: scene,
            registry: emptyRegistry,
            sceneHeight: 300
        )

        let mergedNode = merged.node(named: "ghost")
        #expect(mergedNode?.position.x == 77)
        #expect(mergedNode?.position.y == 88)
    }

    @Test("merged preserves authored values for nodes absent from the registry")
    func mergedPreservesAuthoredValuesForUnregisteredNodes() {
        // Two nodes; only one is registered. The other must be unchanged.
        var registeredSpec = HypeNodeSpec(
            name: "ball",
            nodeType: .sprite,
            position: PointSpec(x: 100, y: 100)
        )
        registeredSpec.size = SizeSpec(width: 20, height: 20)

        let unregisteredSpec = HypeNodeSpec(
            name: "wall",
            nodeType: .sprite,
            position: PointSpec(x: 200, y: 50)
        )

        let scene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 400, height: 300),
            nodes: [registeredSpec, unregisteredSpec]
        )

        // Register only the ball, with a live position different from authored.
        let registry = NodeRegistry()
        let liveBall = SKNode()
        liveBall.position = CGPoint(x: 150, y: 80)
        registry.register(id: registeredSpec.id, node: liveBall)

        let merged = LiveSceneStateSync.merged(
            scene: scene,
            registry: registry,
            sceneHeight: 300
        )

        // Ball should have the live position folded in.
        let mergedBall = merged.node(named: "ball")
        #expect(mergedBall?.position.x == 150)
        // hypeY = sceneHeight - skY = 300 - 80 = 220
        #expect(mergedBall?.position.y == 220)

        // Wall should be untouched.
        let mergedWall = merged.node(named: "wall")
        #expect(mergedWall?.position.x == 200)
        #expect(mergedWall?.position.y == 50)
    }

    @Test("merged overwrites alpha and isHidden from live node")
    func mergedOverwritesAlphaAndVisibility() {
        var nodeSpec = HypeNodeSpec(
            name: "sprite",
            nodeType: .sprite,
            position: PointSpec(x: 0, y: 0),
            alpha: 1.0,
            isHidden: false
        )
        nodeSpec.size = SizeSpec(width: 20, height: 20)

        let scene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 400, height: 300),
            nodes: [nodeSpec]
        )

        let registry = NodeRegistry()
        let liveNode = SKNode()
        liveNode.alpha = 0.5
        liveNode.isHidden = true
        registry.register(id: nodeSpec.id, node: liveNode)

        let merged = LiveSceneStateSync.merged(
            scene: scene,
            registry: registry,
            sceneHeight: 300
        )

        let mergedNode = merged.node(named: "sprite")
        #expect(mergedNode?.alpha == 0.5)
        #expect(mergedNode?.isHidden == true)
    }

    @Test("merged correctly converts rotation from SK CCW radians to Hype CW degrees")
    func mergedConvertsRotationConvention() {
        var nodeSpec = HypeNodeSpec(
            name: "arrow",
            nodeType: .sprite,
            position: PointSpec(x: 0, y: 0),
            rotation: 0
        )
        nodeSpec.size = SizeSpec(width: 20, height: 20)

        let scene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 400, height: 300),
            nodes: [nodeSpec]
        )

        let registry = NodeRegistry()
        let liveNode = SKNode()
        // SK 90° CCW = π/2 radians. toHypeRotation should give -90° (CW convention: 90 CCW = -90 CW).
        liveNode.zRotation = .pi / 2
        registry.register(id: nodeSpec.id, node: liveNode)

        let merged = LiveSceneStateSync.merged(
            scene: scene,
            registry: registry,
            sceneHeight: 300
        )

        let mergedNode = merged.node(named: "arrow")
        // SpriteKit stores zRotation internally as 32-bit Float, so reading it
        // back carries ~1e-7 radian error that amplifies to ~1e-5 degrees after
        // the 180/π scale. Assert against the live node's actual round-tripped
        // value with a tolerance that reflects that platform precision, not an
        // idealized 1e-10.
        let converter = CoordinateConverter(sceneHeight: 300)
        let expected = converter.toHypeRotation(Double(liveNode.zRotation))   // ≈ -90.0
        #expect(abs((mergedNode?.rotation ?? 0) - expected) < 1e-4)
        #expect(abs((mergedNode?.rotation ?? 0) - (-90.0)) < 1e-3)
    }
}

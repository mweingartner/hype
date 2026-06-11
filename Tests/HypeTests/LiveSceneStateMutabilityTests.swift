import Testing
import AppKit
import SpriteKit
@testable import Hype
@testable import HypeCore

// MARK: - LiveSceneStateSync immutability tests
//
// The architect's requirement: the live-state fold must apply ONLY in browse
// mode and never mutate the persisted document. These tests verify that:
//   1. merged() is a pure copy operation — the original SceneSpec is unchanged.
//   2. A node without a live SKNode registration is untouched in the result.
//   3. merged() with a live node updates only the returned copy, NOT the input.

@MainActor
@Suite("LiveSceneStateSync — immutability and copy semantics")
struct LiveSceneStateMutabilityTests {

    // MARK: - merged() does not mutate its input (empty registry)

    @Test("merged() with empty registry returns copy identical to original")
    func mergedEmptyRegistryReturnsCopy() {
        let nodeSpec = HypeNodeSpec(
            name: "wall",
            nodeType: .shape,
            position: PointSpec(x: 300, y: 200)
        )
        let originalScene = SceneSpec(
            name: "level1",
            size: SizeSpec(width: 800, height: 600),
            nodes: [nodeSpec]
        )

        let emptyRegistry = NodeRegistry()
        let merged = LiveSceneStateSync.merged(
            scene: originalScene,
            registry: emptyRegistry,
            sceneHeight: 600
        )

        // Result should reflect original authored values (no live state to fold in).
        #expect(merged.nodes.first?.position.x == 300)
        #expect(merged.nodes.first?.position.y == 200)

        // The original must be completely unchanged — merged() is a copy, not in-place.
        #expect(originalScene.nodes.first?.position.x == 300,
                "merged() must not mutate original scene node x")
        #expect(originalScene.nodes.first?.position.y == 200,
                "merged() must not mutate original scene node y")
        #expect(originalScene.name == "level1", "merged() must not mutate original scene name")
    }

    // MARK: - merged() does not mutate its input (live node registered)

    @Test("merged() with a live node updates the copy but not the original SceneSpec")
    func mergedWithLiveNodeDoesNotMutateOriginal() {
        let nodeSpec = HypeNodeSpec(
            name: "ball",
            nodeType: .sprite,
            position: PointSpec(x: 50, y: 75)
        )
        let originalScene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 400, height: 300),
            nodes: [nodeSpec]
        )
        // Capture authored values before merge.
        let authoredX = originalScene.nodes[0].position.x  // 50
        let authoredY = originalScene.nodes[0].position.y  // 75

        // Register a live node at a completely different position.
        let registry = NodeRegistry()
        let liveNode = SKNode()
        liveNode.position = CGPoint(x: 200, y: 180)
        registry.register(id: nodeSpec.id, node: liveNode)

        let merged = LiveSceneStateSync.merged(
            scene: originalScene,
            registry: registry,
            sceneHeight: 300
        )

        // Merged snapshot should reflect the live node's position (with Y flip).
        // CoordinateConverter.toHype: hypeY = sceneHeight - skY = 300 - 180 = 120.
        #expect(abs((merged.nodes.first?.position.x ?? 0) - 200) < 1e-6,
                "Expected live x=200 in merged result")
        #expect(abs((merged.nodes.first?.position.y ?? 0) - 120) < 1e-6,
                "Expected live hype-y=120 in merged result (300 - 180)")

        // THE CRITICAL ASSERTION: the original scene is unchanged.
        #expect(originalScene.nodes[0].position.x == authoredX,
                "merged() mutated the original scene node x: was \(authoredX), now \(originalScene.nodes[0].position.x)")
        #expect(originalScene.nodes[0].position.y == authoredY,
                "merged() mutated the original scene node y: was \(authoredY), now \(originalScene.nodes[0].position.y)")
    }

    // MARK: - Node without a live registration is untouched in the returned copy

    @Test("merged() leaves nodes without a live registration at their authored values in the returned copy")
    func mergedUnregisteredNodeIsUntouchedInResult() {
        let unregisteredNode = HypeNodeSpec(
            name: "staticWall",
            nodeType: .shape,
            position: PointSpec(x: 400, y: 0)
        )
        let scene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 800, height: 600),
            nodes: [unregisteredNode]
        )

        // Empty registry — no live node registered for this ID.
        let emptyRegistry = NodeRegistry()
        let merged = LiveSceneStateSync.merged(
            scene: scene,
            registry: emptyRegistry,
            sceneHeight: 600
        )

        // Unregistered node must be unchanged in the returned copy.
        #expect(merged.nodes.first?.position.x == 400,
                "Unregistered node x was changed in merged result")
        #expect(merged.nodes.first?.position.y == 0,
                "Unregistered node y was changed in merged result")
    }

    // MARK: - merged() with multiple nodes: only registered ones are updated

    @Test("merged() with mixed registered/unregistered nodes updates only registered ones")
    func mergedMixedRegistrationSelectiveUpdate() {
        let registeredNode = HypeNodeSpec(
            name: "ball",
            nodeType: .sprite,
            position: PointSpec(x: 100, y: 100)
        )
        let unregisteredNode = HypeNodeSpec(
            name: "platform",
            nodeType: .shape,
            position: PointSpec(x: 400, y: 50)
        )
        let scene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 800, height: 600),
            nodes: [registeredNode, unregisteredNode]
        )

        let registry = NodeRegistry()
        let liveBall = SKNode()
        liveBall.position = CGPoint(x: 250, y: 300)
        registry.register(id: registeredNode.id, node: liveBall)

        let merged = LiveSceneStateSync.merged(
            scene: scene,
            registry: registry,
            sceneHeight: 600
        )

        let mergedBall = merged.nodes.first(where: { $0.name == "ball" })
        let mergedPlatform = merged.nodes.first(where: { $0.name == "platform" })

        // Ball: live position (250, 600-300=300 in hype coords).
        #expect(mergedBall?.position.x == 250)
        #expect(mergedBall?.position.y == 300)

        // Platform: unchanged from authored.
        #expect(mergedPlatform?.position.x == 400)
        #expect(mergedPlatform?.position.y == 50)

        // Original scene node positions must be unchanged.
        let originalBall = scene.nodes.first(where: { $0.name == "ball" })
        let originalPlatform = scene.nodes.first(where: { $0.name == "platform" })
        #expect(originalBall?.position.x == 100, "Original ball x was mutated")
        #expect(originalBall?.position.y == 100, "Original ball y was mutated")
        #expect(originalPlatform?.position.x == 400, "Original platform x was mutated")
        #expect(originalPlatform?.position.y == 50, "Original platform y was mutated")
    }

    // MARK: - Alpha and isHidden: original unchanged after merge

    @Test("merged() with live alpha/isHidden does not mutate the original node's authored values")
    func mergedAlphaHiddenDoesNotMutateOriginal() {
        var nodeSpec = HypeNodeSpec(
            name: "sprite",
            nodeType: .sprite,
            position: PointSpec(x: 0, y: 0),
            alpha: 1.0,
            isHidden: false
        )
        nodeSpec.size = SizeSpec(width: 20, height: 20)

        let originalScene = SceneSpec(
            name: "test",
            size: SizeSpec(width: 400, height: 300),
            nodes: [nodeSpec]
        )

        let registry = NodeRegistry()
        let liveNode = SKNode()
        liveNode.alpha = 0.3
        liveNode.isHidden = true
        registry.register(id: nodeSpec.id, node: liveNode)

        _ = LiveSceneStateSync.merged(
            scene: originalScene,
            registry: registry,
            sceneHeight: 300
        )

        // Original must be unchanged.
        #expect(originalScene.nodes.first?.alpha == 1.0,
                "merged() mutated the original scene node alpha")
        #expect(originalScene.nodes.first?.isHidden == false,
                "merged() mutated the original scene node isHidden")
    }

    // MARK: - merged() never writes back to the document (structural guarantee)

    @Test("merged() returned SceneSpec is a separate value — node array identity is different")
    func mergedResultIsIndependentCopy() {
        let nodeSpec = HypeNodeSpec(name: "x", nodeType: .shape, position: PointSpec(x: 1, y: 2))
        let originalScene = SceneSpec(nodes: [nodeSpec])

        let merged = LiveSceneStateSync.merged(
            scene: originalScene,
            registry: NodeRegistry(),
            sceneHeight: 300
        )

        // SceneSpec and HypeNodeSpec are structs (value types). The merged result
        // is a copy. Mutating it must not affect the original.
        var mutatedMerged = merged
        mutatedMerged.nodes[0].position = PointSpec(x: 999, y: 999)

        #expect(originalScene.nodes.first?.position.x == 1,
                "Mutating the merged copy leaked back to the original")
        #expect(originalScene.nodes.first?.position.y == 2,
                "Mutating the merged copy leaked back to the original")
    }
}

import SpriteKit
import HypeCore

/// Folds live SKNode runtime state back into a value-typed `SceneSpec` snapshot
/// so that HypeTalk scripts dispatched during browse mode read physically-accurate
/// positions and velocities rather than the frozen authored values.
///
/// The returned `SceneSpec` is **transient** — it is never persisted or written
/// back into the document. It exists only for the duration of a single runtime
/// dispatch so the interpreter sees live coordinates.
///
/// All SKNode reads happen on the `@MainActor` before the value snapshot crosses
/// to the `StackRuntime` actor. No live object ever escapes this type.
@MainActor
enum LiveSceneStateSync {

    /// Returns a copy of `scene` with each node's position, rotation,
    /// velocity, alpha, and `isHidden` overwritten from the live SKNode
    /// registered under the node's UUID. Nodes whose UUID is not present
    /// in the registry are left unchanged. The returned spec is otherwise
    /// identical to the input — only the listed properties are touched.
    ///
    /// Coordinate conventions mirror the SceneBridge forward mapping exactly:
    /// - **Position**: `CoordinateConverter.toHype` (SK bottom-left → Hype top-left).
    /// - **Rotation**: `CoordinateConverter.toHypeRotation` (SK CCW radians → Hype CW degrees).
    /// - **Velocity**: direct read (`specVelocityY = skVelocityY`) — no sign flip,
    ///   matching SceneBridge's `CGVector(dx: vx, dy: vy)` forward pass.
    ///
    /// - Parameters:
    ///   - scene: The authored `SceneSpec` to use as the base.
    ///   - registry: The `NodeRegistry` that maps node UUIDs to live `SKNode` instances.
    ///   - sceneHeight: The scene's design height in points, used to flip the Y axis.
    /// - Returns: A transient `SceneSpec` copy with live values folded in.
    static func merged(
        scene: SceneSpec,
        registry: NodeRegistry,
        sceneHeight: Double
    ) -> SceneSpec {
        let converter = CoordinateConverter(sceneHeight: sceneHeight)
        var result = scene
        result.nodes = rewriteNodes(scene.nodes, registry: registry, converter: converter)
        return result
    }

    // MARK: - Private helpers

    /// Recursively rewrites a node array, folding in live state for any node
    /// whose UUID is registered. Children are processed the same way.
    private static func rewriteNodes(
        _ nodes: [HypeNodeSpec],
        registry: NodeRegistry,
        converter: CoordinateConverter
    ) -> [HypeNodeSpec] {
        nodes.map { spec in
            rewrite(spec, registry: registry, converter: converter)
        }
    }

    /// Returns a copy of `spec` with live SKNode state applied if the node is
    /// registered; otherwise returns `spec` unchanged.
    private static func rewrite(
        _ spec: HypeNodeSpec,
        registry: NodeRegistry,
        converter: CoordinateConverter
    ) -> HypeNodeSpec {
        var result = spec

        // Recursively process children first (same logic, independent of the parent).
        result.children = rewriteNodes(spec.children, registry: registry, converter: converter)

        // Look up the live node. If absent, leave authored values untouched.
        guard let liveNode = registry.node(for: spec.id) else {
            return result
        }

        // Position: SK uses bottom-left origin; Hype uses top-left. Convert via
        // CoordinateConverter.toHype, which applies: hypeY = sceneHeight - skY.
        let skPos = PointSpec(x: Double(liveNode.position.x), y: Double(liveNode.position.y))
        result.position = converter.toHype(skPos)

        // Rotation: SK uses counter-clockwise radians; Hype uses clockwise degrees.
        // CoordinateConverter.toHypeRotation applies: degrees = -(radians * 180 / π).
        result.rotation = converter.toHypeRotation(Double(liveNode.zRotation))

        // Alpha and visibility are direct reads — no coordinate conversion needed.
        result.alpha = Double(liveNode.alpha)
        result.isHidden = liveNode.isHidden

        // Velocity: mirror the SceneBridge forward pass, which writes
        //   body.velocity = CGVector(dx: velocityX, dy: velocityY)
        // with no Y-axis sign flip. So the reverse is also sign-preserving:
        //   specVelocityX = dx, specVelocityY = dy.
        if result.physicsBody != nil, let body = liveNode.physicsBody {
            result.physicsBody?.velocityX = Double(body.velocity.dx)
            result.physicsBody?.velocityY = Double(body.velocity.dy)
        }

        return result
    }
}

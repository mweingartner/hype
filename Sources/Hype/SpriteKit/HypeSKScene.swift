import SpriteKit
import HypeCore

/// Events from SpriteKit forwarded to HypeTalk dispatch.
enum SpriteEvent: Sendable {
    case mouseDown(nodeId: UUID?, scenePosition: PointSpec)
    case mouseUp(nodeId: UUID?, scenePosition: PointSpec)
    case mouseDragged(nodeId: UUID?, scenePosition: PointSpec)
    case mouseWithin(nodeId: UUID?, scenePosition: PointSpec)
    case keyDown(characters: String, keyCode: UInt16)
    case keyUp(characters: String, keyCode: UInt16)
    case contactBegan(nodeA: UUID, nodeB: UUID)
    case contactEnded(nodeA: UUID, nodeB: UUID)
    case frameUpdate(deltaTime: TimeInterval)
    case sceneDidLoad
    case actionFinished(name: String, nodeId: UUID)
}

@MainActor
protocol SpriteEventDelegate: AnyObject {
    func spriteScene(_ scene: HypeSKScene, didReceiveEvent event: SpriteEvent)
}

final class HypeSKScene: SKScene {
    @MainActor weak var eventDelegate: SpriteEventDelegate?
    @MainActor var registry: NodeRegistry?
    private var converter: CoordinateConverter
    private var lastUpdateTime: TimeInterval = 0

    @MainActor
    init(size: CGSize, sceneHeight: Double) {
        self.converter = CoordinateConverter(sceneHeight: sceneHeight)
        super.init(size: size)
        self.scaleMode = .aspectFit
        self.physicsWorld.contactDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @MainActor
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // Note: sceneDidLoad and openScene are dispatched directly from
        // rebuildSpriteScene() in CardCanvasView to avoid timing issues
        // with didMove being deferred during draw() cycles
    }

    // MARK: - Mouse Events

    @MainActor
    override func mouseDown(with event: NSEvent) {
        let loc = event.location(in: self)
        let nodeId = topHypeNode(at: loc)
        let hypePoint = converter.toHype(PointSpec(x: Double(loc.x), y: Double(loc.y)))
        eventDelegate?.spriteScene(self, didReceiveEvent: .mouseDown(nodeId: nodeId, scenePosition: hypePoint))
    }

    @MainActor
    override func mouseUp(with event: NSEvent) {
        let loc = event.location(in: self)
        let nodeId = topHypeNode(at: loc)
        let hypePoint = converter.toHype(PointSpec(x: Double(loc.x), y: Double(loc.y)))
        eventDelegate?.spriteScene(self, didReceiveEvent: .mouseUp(nodeId: nodeId, scenePosition: hypePoint))
    }

    @MainActor
    override func mouseDragged(with event: NSEvent) {
        let loc = event.location(in: self)
        let nodeId = topHypeNode(at: loc)
        let hypePoint = converter.toHype(PointSpec(x: Double(loc.x), y: Double(loc.y)))
        eventDelegate?.spriteScene(self, didReceiveEvent: .mouseDragged(nodeId: nodeId, scenePosition: hypePoint))
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = event.location(in: self)
        let nodeId = topHypeNode(at: loc)
        let hypePoint = converter.toHype(PointSpec(x: Double(loc.x), y: Double(loc.y)))
        eventDelegate?.spriteScene(self, didReceiveEvent: .mouseWithin(nodeId: nodeId, scenePosition: hypePoint))
    }

    // MARK: - Key Events

    @MainActor
    override func keyDown(with event: NSEvent) {
        eventDelegate?.spriteScene(self, didReceiveEvent: .keyDown(characters: HypeKeyInput.normalizedName(for: event), keyCode: event.keyCode))
    }

    @MainActor
    override func keyUp(with event: NSEvent) {
        eventDelegate?.spriteScene(self, didReceiveEvent: .keyUp(characters: HypeKeyInput.normalizedName(for: event), keyCode: event.keyCode))
    }

    // MARK: - Frame Update

    @MainActor
    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        eventDelegate?.spriteScene(self, didReceiveEvent: .frameUpdate(deltaTime: dt))
    }

    // MARK: - Hit Testing

    /// Find the deepest node at a point that has a registered Hype UUID.
    @MainActor
    private func topHypeNode(at point: CGPoint) -> UUID? {
        let nodes = self.nodes(at: point)
        for node in nodes {
            if let id = registry?.id(for: node) { return id }
            // Walk up parent chain
            var parent = node.parent
            while let p = parent {
                if let id = registry?.id(for: p) { return id }
                parent = p.parent
            }
        }
        return nil
    }
}

// MARK: - SKPhysicsContactDelegate

extension HypeSKScene: SKPhysicsContactDelegate {
    nonisolated func didBegin(_ contact: SKPhysicsContact) {
        guard let nodeA = contact.bodyA.node,
              let nodeB = contact.bodyB.node else { return }
        Task { @MainActor in
            guard let reg = self.registry,
                  let idA = reg.id(for: nodeA),
                  let idB = reg.id(for: nodeB) else { return }
            self.eventDelegate?.spriteScene(self, didReceiveEvent: .contactBegan(nodeA: idA, nodeB: idB))
        }
    }

    nonisolated func didEnd(_ contact: SKPhysicsContact) {
        guard let nodeA = contact.bodyA.node,
              let nodeB = contact.bodyB.node else { return }
        Task { @MainActor in
            guard let reg = self.registry,
                  let idA = reg.id(for: nodeA),
                  let idB = reg.id(for: nodeB) else { return }
            self.eventDelegate?.spriteScene(self, didReceiveEvent: .contactEnded(nodeA: idA, nodeB: idB))
        }
    }
}

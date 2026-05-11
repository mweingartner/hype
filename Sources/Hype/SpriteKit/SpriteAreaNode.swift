import SpriteKit
import HypeCore

/// A container node representing a spriteArea's scene content within the card-level SKScene.
/// Uses SKCropNode to clip content to the spriteArea's bounds.
///
/// Phase B infrastructure: provides an alternative rendering path for sprite areas
/// within the shared CardSKScene, rather than using separate SKView overlays.
@MainActor
final class SpriteAreaNode: SKNode {
    let partId: UUID
    let bridge: SceneBridge
    let areaSize: CGSize
    private let cropNode: SKCropNode
    /// Container for the sprite area's child nodes. Add scene content here.
    let contentNode: SKNode

    init(partId: UUID, size: CGSize, sceneHeight: Double) {
        self.partId = partId
        self.areaSize = size
        self.bridge = SceneBridge(sceneHeight: sceneHeight)
        self.cropNode = SKCropNode()
        self.contentNode = SKNode()
        super.init()

        self.name = "spriteArea_\(partId.uuidString)"

        // Create a rectangular mask for clipping to the area bounds.
        let mask = SKSpriteNode(color: .white, size: size)
        mask.anchorPoint = CGPoint(x: 0, y: 1) // top-left
        mask.position = .zero
        cropNode.maskNode = mask

        cropNode.addChild(contentNode)
        addChild(cropNode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Apply a SceneSpec to this area's content, building nodes from the spec.
    func applySpec(_ spec: SceneSpec, repository: SpriteRepository) {
        contentNode.removeAllChildren()
        bridge.registry.clear()

        for nodeSpec in spec.nodes {
            let skNode = bridge.makeNode(from: nodeSpec, repository: repository)
            contentNode.addChild(skNode)
        }
    }

    func updateFromPart(_ part: Part, repository: SpriteRepository) {
        position = CGPoint(x: part.left, y: -part.top)
        isHidden = !part.visible
        guard let spec = part.activeSceneSpec else {
            contentNode.removeAllChildren()
            bridge.registry.clear()
            return
        }
        applySpec(spec, repository: repository)
    }
}

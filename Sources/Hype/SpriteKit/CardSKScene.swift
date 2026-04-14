import SpriteKit
import HypeCore

/// The card-level SpriteKit scene that hosts the rendered card texture.
/// Used for card-to-card transitions via SpriteKit's presentScene(_:transition:).
/// In Phase A this scene only displays a static card image. Phase B and C
/// will add spriteLayer and nativeLayer for sprite areas and native part nodes.
@MainActor
final class CardSKScene: SKScene {
    /// Displays the card's rendered content as a texture.
    let cardNode = SKSpriteNode()
    /// Container for native shape/image part nodes (Phase C).
    let nativeLayer = SKNode()
    /// Container for spriteArea scene content (Phase B).
    let spriteLayer = SKNode()

    init(cardSize: CGSize) {
        super.init(size: cardSize)
        self.scaleMode = .resizeFill
        self.backgroundColor = .white

        // Card texture node — anchored at top-left, positioned at top of scene.
        // SpriteKit uses bottom-left origin, so placing the node at (0, height)
        // with anchor (0, 1) aligns the texture's top-left with the scene's top-left.
        cardNode.anchorPoint = CGPoint(x: 0, y: 1)
        cardNode.position = CGPoint(x: 0, y: cardSize.height)
        cardNode.zPosition = 0
        addChild(cardNode)

        // Layer for native part nodes (shapes, images) — Phase C
        nativeLayer.zPosition = 50
        nativeLayer.position = CGPoint(x: 0, y: cardSize.height)
        addChild(nativeLayer)

        // Layer for sprite area content — Phase B
        spriteLayer.zPosition = 100
        spriteLayer.position = CGPoint(x: 0, y: cardSize.height)
        addChild(spriteLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Update the card texture from a rendered NSImage.
    func updateCardTexture(_ image: NSImage) {
        let texture = SKTexture(image: image)
        cardNode.texture = texture
        cardNode.size = size
    }
}

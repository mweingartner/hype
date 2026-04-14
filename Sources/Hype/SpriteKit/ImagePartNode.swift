import SpriteKit
import HypeCore

/// Renders a Hype image part as a native SKSpriteNode in the CardSKScene's nativeLayer.
///
/// Phase C infrastructure: provides native SpriteKit rendering for image parts,
/// coexisting with the existing CGContext rendering path.
@MainActor
final class ImagePartNode: SKSpriteNode, CardPartNode {
    let partId: UUID

    init(part: Part) {
        self.partId = part.id
        super.init(texture: nil, color: .clear, size: .zero)
        self.anchorPoint = CGPoint(x: 0, y: 1) // top-left anchor
        self.name = "part_\(part.id.uuidString)"
        updateFromPart(part)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func updateFromPart(_ part: Part) {
        if let data = part.imageData, let image = NSImage(data: data) {
            self.texture = SKTexture(image: image)
        }
        self.size = CGSize(width: part.width, height: part.height)

        // Position in nativeLayer coords (nativeLayer is at top of scene, y-down)
        self.position = CGPoint(x: part.left, y: -part.top)
        self.isHidden = !part.visible

        // Simple inversion approximation for invertOnClick + hilite
        if part.invertOnClick && part.hilite {
            self.colorBlendFactor = 1.0
            self.color = .white
        } else {
            self.colorBlendFactor = 0
        }
    }
}

import SpriteKit
import HypeCore

/// Native SpriteKit representation of a persisted card paint snapshot.
@MainActor
final class PaintLayerNode: SKSpriteNode {
    init(layer: CardPaintLayer) {
        super.init(texture: nil, color: .clear, size: .zero)
        anchorPoint = CGPoint(x: 0, y: 1)
        name = "card_paint_\(layer.cardId.uuidString)"
        update(layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(_ layer: CardPaintLayer) {
        if let pngData = PaintLayer(snapshot: layer).pngData(),
           let image = NSImage(data: pngData) {
            texture = SKTexture(image: image)
        }
        size = CGSize(width: layer.width, height: layer.height)
        position = .zero
        isHidden = layer.isEmpty
    }
}

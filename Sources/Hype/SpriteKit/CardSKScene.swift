import SpriteKit
import HypeCore

/// The card-level SpriteKit scene that hosts the rendered card texture.
/// Used for card-to-card transitions via SpriteKit's presentScene(_:transition:).
/// In Phase A this scene only displays a static card image. Phase B and C
/// will add spriteLayer and nativeLayer for sprite areas and native part nodes.
@MainActor
final class CardSKScene: SKScene {
    static let nativeRenderablePartTypes: Set<PartType> = [.shape, .image, .button, .field, .spriteArea]

    /// Displays the card's rendered content as a texture.
    let cardNode = SKSpriteNode()
    /// Container for native shape/image part nodes (Phase C).
    let nativeLayer = SKNode()
    /// Container for spriteArea scene content (Phase B).
    let spriteLayer = SKNode()
    private var nativePartNodes: [UUID: SKNode] = [:]
    private var spriteAreaNodes: [UUID: SpriteAreaNode] = [:]
    private var paintLayerNode: PaintLayerNode?

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

    static func nativeRenderablePartIds(document: HypeDocument, cardId: UUID) -> Set<UUID> {
        Set(nativeRenderableParts(document: document, cardId: cardId).map(\.id))
    }

    static func nativeRenderableParts(document: HypeDocument, cardId: UUID) -> [Part] {
        document.effectivePartsForCard(cardId)
            .filter { $0.visible && nativeRenderablePartTypes.contains($0.partType) }
    }

    var nativePartNodeIds: Set<UUID> {
        Set(nativePartNodes.keys)
    }

    var spriteAreaNodeIds: Set<UUID> {
        Set(spriteAreaNodes.keys)
    }

    var hasPaintLayerNode: Bool {
        paintLayerNode != nil
    }

    /// Reconcile SpriteKit-native card content from the document model.
    func updateNativeContent(document: HypeDocument, cardId: UUID) {
        let parts = Self.nativeRenderableParts(document: document, cardId: cardId)
        let activeIds = Set(parts.map(\.id))

        for id in nativePartNodes.keys where !activeIds.contains(id) {
            nativePartNodes[id]?.removeFromParent()
            nativePartNodes.removeValue(forKey: id)
        }
        for id in spriteAreaNodes.keys where !activeIds.contains(id) {
            spriteAreaNodes[id]?.removeFromParent()
            spriteAreaNodes.removeValue(forKey: id)
        }

        for (order, part) in parts.enumerated() {
            switch part.partType {
            case .shape:
                let node = upsertNativeNode(part: part, make: ShapePartNode.init)
                (node as? ShapePartNode)?.updateFromPart(part)
                node.zPosition = CGFloat(order)
            case .image:
                let node = upsertNativeNode(part: part, make: ImagePartNode.init)
                (node as? ImagePartNode)?.updateFromPart(part)
                node.zPosition = CGFloat(order)
            case .button:
                let node = upsertNativeNode(part: part, make: ButtonPartNode.init)
                (node as? ButtonPartNode)?.updateFromPart(part)
                node.zPosition = CGFloat(order)
            case .field:
                let node = upsertNativeNode(part: part, make: FieldPartNode.init)
                (node as? FieldPartNode)?.updateFromPart(part)
                node.zPosition = CGFloat(order)
            case .spriteArea:
                let areaNode: SpriteAreaNode
                if let existing = spriteAreaNodes[part.id] {
                    areaNode = existing
                } else {
                    let sceneHeight = part.activeSceneSpec?.size.height ?? part.height
                    areaNode = SpriteAreaNode(partId: part.id, size: CGSize(width: part.width, height: part.height), sceneHeight: sceneHeight)
                    spriteLayer.addChild(areaNode)
                    spriteAreaNodes[part.id] = areaNode
                }
                areaNode.updateFromPart(part, repository: document.spriteRepository)
                areaNode.zPosition = CGFloat(order)
            default:
                break
            }
        }

        if let layer = document.paintLayer(forCardId: cardId), !layer.isEmpty {
            if let node = paintLayerNode {
                node.update(layer)
            } else {
                let node = PaintLayerNode(layer: layer)
                node.zPosition = 10_000
                nativeLayer.addChild(node)
                paintLayerNode = node
            }
        } else {
            paintLayerNode?.removeFromParent()
            paintLayerNode = nil
        }
    }

    private func upsertNativeNode<Node: SKNode & CardPartNode>(
        part: Part,
        make: (Part) -> Node
    ) -> SKNode {
        if let existing = nativePartNodes[part.id] as? Node {
            return existing
        }
        nativePartNodes[part.id]?.removeFromParent()
        let node = make(part)
        nativeLayer.addChild(node)
        nativePartNodes[part.id] = node
        return node
    }
}

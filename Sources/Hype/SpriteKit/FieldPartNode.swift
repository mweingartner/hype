import SpriteKit
import HypeCore

/// Native SpriteKit representation of non-editing field text and chrome.
@MainActor
final class FieldPartNode: SKNode, CardPartNode {
    let partId: UUID
    private let backgroundNode = SKShapeNode()
    private let labelNode = SKLabelNode()

    init(part: Part) {
        self.partId = part.id
        super.init()
        self.name = "part_\(part.id.uuidString)"
        addChild(backgroundNode)
        addChild(labelNode)
        updateFromPart(part)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func updateFromPart(_ part: Part) {
        let width = CGFloat(part.width)
        let height = CGFloat(part.height)
        let rect = CGRect(x: 0, y: -height, width: width, height: height)

        backgroundNode.path = RenderGeometry.roundedRectPath(in: rect, cornerWidth: part.fieldStyle == .search ? 10 : 0, cornerHeight: part.fieldStyle == .search ? 10 : 0)
        backgroundNode.fillColor = part.fieldStyle == .transparent ? .clear : (NSColor(hexString: part.fillColor) ?? .textBackgroundColor)
        backgroundNode.strokeColor = part.fieldStyle == .transparent ? .clear : (NSColor(hexString: part.strokeColor) ?? .separatorColor)
        backgroundNode.lineWidth = part.fieldStyle == .transparent ? 0 : max(0, CGFloat(part.strokeWidth))

        labelNode.text = part.textContent.isEmpty ? part.name : part.textContent
        labelNode.fontName = part.textFont.isEmpty || part.textFont == "System" ? NSFont.systemFont(ofSize: part.textSize).fontName : part.textFont
        labelNode.fontSize = CGFloat(max(1, part.textSize))
        labelNode.fontColor = !part.fontColor.isEmpty ? (NSColor(hexString: part.fontColor) ?? .labelColor) : .textColor
        labelNode.verticalAlignmentMode = .center
        switch part.textAlign {
        case .left:
            labelNode.horizontalAlignmentMode = .left
            labelNode.position = CGPoint(x: 6, y: -height / 2)
        case .center:
            labelNode.horizontalAlignmentMode = .center
            labelNode.position = CGPoint(x: width / 2, y: -height / 2)
        case .right:
            labelNode.horizontalAlignmentMode = .right
            labelNode.position = CGPoint(x: max(0, width - 6), y: -height / 2)
        }

        position = CGPoint(x: part.left, y: -part.top)
        zRotation = CGFloat(-part.rotation * .pi / 180)
        isHidden = !part.visible
        alpha = part.enabled ? 1.0 : 0.45
    }
}

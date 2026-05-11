import SpriteKit
import HypeCore

/// Native SpriteKit representation of a Hype button for card-level scenes.
@MainActor
final class ButtonPartNode: SKNode, CardPartNode {
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
        let cornerRadius: CGFloat = switch part.buttonStyle {
        case .roundRect, .default, .standard, .shadow, .popup, .toggle, .radio, .checkBox, .link:
            6
        case .oval:
            min(width, height) / 2
        case .transparent, .opaque:
            0
        }

        backgroundNode.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        backgroundNode.fillColor = part.buttonStyle == .transparent ? .clear : (NSColor(hexString: part.fillColor) ?? NSColor.controlColor)
        backgroundNode.strokeColor = NSColor(hexString: part.strokeColor) ?? NSColor.separatorColor
        backgroundNode.lineWidth = max(0, CGFloat(part.strokeWidth))

        labelNode.text = part.showName ? part.name : part.textContent
        labelNode.fontName = part.textFont.isEmpty || part.textFont == "System" ? NSFont.systemFont(ofSize: part.textSize).fontName : part.textFont
        labelNode.fontSize = CGFloat(max(1, part.textSize))
        labelNode.fontColor = !part.fontColor.isEmpty ? (NSColor(hexString: part.fontColor) ?? .labelColor) : .controlTextColor
        labelNode.horizontalAlignmentMode = .center
        labelNode.verticalAlignmentMode = .center
        labelNode.position = CGPoint(x: width / 2, y: -height / 2)

        position = CGPoint(x: part.left, y: -part.top)
        zRotation = CGFloat(-part.rotation * .pi / 180)
        isHidden = !part.visible
        alpha = part.enabled ? 1.0 : 0.45
    }
}

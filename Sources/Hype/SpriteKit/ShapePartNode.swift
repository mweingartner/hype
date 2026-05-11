import SpriteKit
import HypeCore

/// Renders a Hype shape part as a native SKShapeNode in the CardSKScene's nativeLayer.
///
/// Phase C infrastructure: provides native SpriteKit rendering for shape parts,
/// coexisting with the existing CGContext rendering path.
@MainActor
final class ShapePartNode: SKShapeNode, CardPartNode {
    let partId: UUID

    init(part: Part) {
        self.partId = part.id
        super.init()
        self.name = "part_\(part.id.uuidString)"
        updateFromPart(part)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func updateFromPart(_ part: Part) {
        let size = CGSize(width: part.width, height: part.height)
        let rect = CGRect(x: 0, y: -size.height, width: size.width, height: size.height)

        switch part.shapeType {
        case .rectangle:
            self.path = CGPath(rect: rect, transform: nil)

        case .roundRect:
            let r = min(CGFloat(part.cornerRadius), size.width / 2, size.height / 2)
            self.path = CGPath(
                roundedRect: rect,
                cornerWidth: r,
                cornerHeight: r,
                transform: nil
            )

        case .oval:
            self.path = CGPath(ellipseIn: rect, transform: nil)

        case .line:
            if part.pathData.count >= 2 {
                let mPath = CGMutablePath()
                let origin = part.pathData[0]
                mPath.move(to: CGPoint(x: origin.x - part.left, y: -(origin.y - part.top)))
                for i in 1..<part.pathData.count {
                    let pt = part.pathData[i]
                    mPath.addLine(to: CGPoint(x: pt.x - part.left, y: -(pt.y - part.top)))
                }
                self.path = mPath
            }

        case .freeform:
            if part.pathData.count >= 2 {
                let mPath = CGMutablePath()
                let origin = part.pathData[0]
                mPath.move(to: CGPoint(x: origin.x - part.left, y: -(origin.y - part.top)))
                for i in 1..<part.pathData.count {
                    let pt = part.pathData[i]
                    mPath.addLine(to: CGPoint(x: pt.x - part.left, y: -(pt.y - part.top)))
                }
                mPath.closeSubpath()
                self.path = mPath
            }
        }

        // Colors
        self.fillColor = NSColor(hexString: part.fillColor) ?? .white
        self.strokeColor = NSColor(hexString: part.strokeColor) ?? .black
        self.lineWidth = CGFloat(part.strokeWidth)

        // Position in nativeLayer coords (nativeLayer is at top of scene, y-down)
        self.position = CGPoint(x: part.left, y: -part.top)

        // Visibility
        self.isHidden = !part.visible
    }
}

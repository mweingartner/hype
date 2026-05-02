import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for `scene3D` parts. SceneKit views can't
/// render into a CG context cheaply, so the placeholder is an
/// isometric box icon plus the model filename — enough for users
/// to identify the part in edit mode and inside AI vision capture.
public enum Scene3DRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Background — dark gradient feels appropriate for 3D viewers.
        ctx.setFillColor(NSColor(calibratedWhite: 0.18, alpha: 1).cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Isometric box centered horizontally, upper portion.
        let boxSize = min(72, min(rect.width, rect.height) * 0.55)
        let boxCenter = CGPoint(x: rect.midX, y: rect.minY + boxSize / 2 + 12)
        drawIsometricBox(at: boxCenter, size: boxSize, ctx: ctx)

        // Filename caption below the icon.
        let caption = filenameCaption(for: part)
        let captionRect = CGRect(
            x: rect.minX + 6,
            y: rect.maxY - 22,
            width: rect.width - 12,
            height: 18
        )
        drawCenteredText(
            caption,
            in: captionRect,
            font: NSFont.systemFont(ofSize: 11, weight: .medium),
            color: NSColor.white,
            ctx: ctx
        )

        ctx.restoreGState()
    }

    private static func drawIsometricBox(at center: CGPoint, size: CGFloat, ctx: CGContext) {
        let half = size / 2
        // Three rhombus faces.
        // Top.
        let top = CGMutablePath()
        top.move(to: CGPoint(x: center.x, y: center.y - half))
        top.addLine(to: CGPoint(x: center.x + half, y: center.y - half * 0.5))
        top.addLine(to: CGPoint(x: center.x, y: center.y))
        top.addLine(to: CGPoint(x: center.x - half, y: center.y - half * 0.5))
        top.closeSubpath()
        ctx.setFillColor(NSColor(calibratedRed: 0.4, green: 0.55, blue: 0.85, alpha: 1).cgColor)
        ctx.addPath(top)
        ctx.fillPath()

        // Left face.
        let left = CGMutablePath()
        left.move(to: CGPoint(x: center.x - half, y: center.y - half * 0.5))
        left.addLine(to: CGPoint(x: center.x, y: center.y))
        left.addLine(to: CGPoint(x: center.x, y: center.y + half * 0.85))
        left.addLine(to: CGPoint(x: center.x - half, y: center.y + half * 0.35))
        left.closeSubpath()
        ctx.setFillColor(NSColor(calibratedRed: 0.3, green: 0.42, blue: 0.7, alpha: 1).cgColor)
        ctx.addPath(left)
        ctx.fillPath()

        // Right face.
        let right = CGMutablePath()
        right.move(to: CGPoint(x: center.x + half, y: center.y - half * 0.5))
        right.addLine(to: CGPoint(x: center.x, y: center.y))
        right.addLine(to: CGPoint(x: center.x, y: center.y + half * 0.85))
        right.addLine(to: CGPoint(x: center.x + half, y: center.y + half * 0.35))
        right.closeSubpath()
        ctx.setFillColor(NSColor(calibratedRed: 0.22, green: 0.3, blue: 0.55, alpha: 1).cgColor)
        ctx.addPath(right)
        ctx.fillPath()

        // Outline.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(top)
        ctx.addPath(left)
        ctx.addPath(right)
        ctx.strokePath()
    }

    private static func filenameCaption(for part: Part) -> String {
        guard !part.scene3DURL.isEmpty else { return "(no model loaded)" }
        if let url = URL(string: part.scene3DURL) {
            return url.lastPathComponent
        }
        return part.scene3DURL
    }

    private static func drawCenteredText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif

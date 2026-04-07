import Foundation
#if canImport(AppKit)
import AppKit

/// Renders a placeholder for video parts on the canvas.
public enum VideoRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Dark background
        ctx.setFillColor(NSColor(white: 0.15, alpha: 1).cgColor)
        ctx.fill(rect)

        // Border
        ctx.setStrokeColor(NSColor(white: 0.3, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(rect)

        // Play triangle icon
        let iconSize: CGFloat = min(40, rect.width / 3, rect.height / 3)
        let cx = rect.midX
        let cy = rect.midY
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.move(to: CGPoint(x: cx - iconSize / 3, y: cy - iconSize / 2))
        ctx.addLine(to: CGPoint(x: cx + iconSize / 2, y: cy))
        ctx.addLine(to: CGPoint(x: cx - iconSize / 3, y: cy + iconSize / 2))
        ctx.closePath()
        ctx.fillPath()

        // URL/filename text
        let displayText = part.videoURL.isEmpty ? "No video set" : (part.videoURL as NSString).lastPathComponent
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let textSize = (displayText as NSString).size(withAttributes: attrs)
        (displayText as NSString).draw(
            at: NSPoint(x: cx - textSize.width / 2, y: rect.maxY - textSize.height - 8),
            withAttributes: attrs
        )
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }
}
#endif

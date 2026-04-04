import Foundation
#if canImport(AppKit)
import AppKit

/// Renders a placeholder for webpage parts on the canvas.
public enum WebPageRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Light blue background
        ctx.setFillColor(NSColor(red: 0.91, green: 0.96, blue: 0.99, alpha: 1).cgColor)
        ctx.fill(rect)

        // Blue border
        ctx.setStrokeColor(NSColor(red: 0.29, green: 0.56, blue: 0.85, alpha: 1).cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(rect)

        // Globe icon (circle + lines)
        let cx = rect.midX
        let cy = rect.midY + 10
        let r: CGFloat = min(20, rect.width / 4, rect.height / 4)
        ctx.setStrokeColor(NSColor(red: 0.29, green: 0.56, blue: 0.85, alpha: 1).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx - r, y: cy))
        ctx.addLine(to: CGPoint(x: cx + r, y: cy))
        ctx.strokePath()
        ctx.addEllipse(in: CGRect(x: cx - r * 0.5, y: cy - r, width: r, height: r * 2))
        ctx.strokePath()

        // URL text
        let urlText = part.url.isEmpty ? "No URL set" : String(part.url.prefix(60))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(red: 0.29, green: 0.56, blue: 0.85, alpha: 1),
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let textSize = (urlText as NSString).size(withAttributes: attrs)
        let textX = cx - textSize.width / 2
        (urlText as NSString).draw(at: NSPoint(x: textX, y: cy - r - 20), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }
}
#endif

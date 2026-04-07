import Foundation
#if canImport(AppKit)
import AppKit

/// Renders image parts onto a CGContext.
public enum ImageRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        if let data = part.imageData,
           let image = NSImage(data: data) {
            // Draw the image correctly in a flipped coordinate system.
            // CGContext.draw() uses bottom-left origin, but our view is flipped (top-left).
            // We need to flip the context locally, draw, then restore.
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.saveGState()
                // Translate to the bottom of the rect and flip vertically
                ctx.translateBy(x: rect.minX, y: rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                // Draw at origin (0,0) since we've translated
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
                ctx.restoreGState()
            }

            // Handle invert-on-hilite
            if part.hilite {
                ctx.setBlendMode(.difference)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(rect)
                ctx.setBlendMode(.normal)
            }
        } else {
            // Placeholder -- no image loaded
            ctx.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.gray.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.stroke(rect)

            // Draw placeholder text
            let text = "Image" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: min(rect.width, rect.height) * 0.2),
                .foregroundColor: NSColor.gray,
            ]
            let textSize = text.size(withAttributes: attrs)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            text.draw(
                at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                withAttributes: attrs
            )
            NSGraphicsContext.restoreGraphicsState()
        }

        ctx.restoreGState()
    }
}
#endif

import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for color-well parts.
///
/// Color-well parts back to a native `NSColorWell` in browse mode
/// for live picking. The placeholder is a simple rounded swatch of
/// the bound color with a subtle border, mirroring AppKit's idle
/// appearance closely enough that the edit-mode visual matches the
/// live one.
public enum ColorWellRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // The actual swatch — fills the rect with the bound color,
        // falling back to gray on parse failure.
        let swatch = NSColor(hexString: part.colorWellHex) ?? NSColor.lightGray
        ctx.setFillColor(swatch.cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        // Thin dark border so the swatch reads on light card surfaces.
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Hex label centered, only if rect is tall enough not to
        // crush the text.
        if rect.height >= 22 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85)
            ]
            let str = part.colorWellHex.uppercased()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let size = (str as NSString).size(withAttributes: attrs)
            // Background pill behind the text for readability.
            let pillRect = CGRect(
                x: rect.midX - size.width / 2 - 4,
                y: rect.midY - size.height / 2 - 1,
                width: size.width + 8,
                height: size.height + 2
            )
            ctx.setFillColor(NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor)
            ctx.addPath(CGPath(roundedRect: pillRect, cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.fillPath()
            (str as NSString).draw(
                at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attrs
            )
            NSGraphicsContext.restoreGraphicsState()
        }

        ctx.restoreGState()
    }
}
#endif

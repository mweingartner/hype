import Foundation
#if canImport(AppKit)
import AppKit

/// CG renderer for `divider` parts.
///
/// The divider is rendered entirely via this renderer — no host view is
/// needed. It draws a single horizontal or vertical separator line.
public enum DividerRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect, theme: HypeTheme? = nil) {
        // Dividers don't get a glass treatment — a translucent divider
        // line would defeat its purpose. The `theme` parameter is
        // accepted for dispatch-signature parity with the other
        // renderers and reserved for future use (e.g. theme-driven
        // default divider color).
        _ = theme
        ctx.saveGState()

        // Resolve the stroke color (security: no force-unwrap).
        let color: NSColor = {
            guard !part.dividerColor.isEmpty,
                  let parsed = NSColor(hexString: part.dividerColor) else {
                return NSColor.separatorColor
            }
            return parsed
        }()

        ctx.setStrokeColor(color.cgColor)
        // Guard thickness to avoid zero-width invisible lines.
        let thickness = max(0.5, part.dividerThickness)
        ctx.setLineWidth(CGFloat(thickness))

        if part.dividerOrientation == "vertical" {
            let x = rect.midX
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
        } else {
            let y = rect.midY
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        ctx.strokePath()

        ctx.restoreGState()
    }
}
#endif

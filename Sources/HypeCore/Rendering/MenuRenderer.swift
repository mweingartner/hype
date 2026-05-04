import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for `menu` parts.
///
/// Draws a menu button placeholder. At runtime `MenuHostNSView` overlays
/// this with a live `NSPopUpButton`.
public enum MenuRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Draw a standard button-style rounded rectangle background.
        let bg = NSColor.controlColor.cgColor
        ctx.setFillColor(bg)
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Draw the title + dropdown arrow.
        let title = part.menuTitle.isEmpty ? part.textContent : part.menuTitle
        let displayTitle = title.isEmpty ? "Menu" : title
        let fontSize = CGFloat(part.textSize > 0 ? part.textSize : 13)
        let nsFont = NSFont(name: part.textFont, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]

        // Arrow area on the right.
        let arrowWidth: CGFloat = 20
        let titleRect = CGRect(x: rect.minX + 8, y: rect.minY,
                               width: rect.width - arrowWidth - 12, height: rect.height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (displayTitle as NSString).draw(in: titleRect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        // Draw a small downward-pointing triangle for the dropdown caret.
        let arrowX = rect.maxX - arrowWidth + 4
        let arrowY = rect.midY
        ctx.setFillColor(NSColor.secondaryLabelColor.cgColor)
        ctx.move(to: CGPoint(x: arrowX, y: arrowY - 3))
        ctx.addLine(to: CGPoint(x: arrowX + 8, y: arrowY - 3))
        ctx.addLine(to: CGPoint(x: arrowX + 4, y: arrowY + 3))
        ctx.closePath()
        ctx.fillPath()

        ctx.restoreGState()
    }
}
#endif

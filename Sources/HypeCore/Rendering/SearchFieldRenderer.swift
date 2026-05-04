import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for `searchField` parts.
///
/// Draws a search-field placeholder with magnifier icon. At runtime
/// `SearchFieldHostNSView` overlays this with a live `NSSearchField`.
public enum SearchFieldRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Rounded pill background typical of search fields.
        let cornerRadius = min(rect.height / 2, 10)
        let bg = NSColor.controlBackgroundColor.cgColor
        ctx.setFillColor(bg)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Magnifier icon (simplified: small circle + handle).
        let iconSize: CGFloat = min(14, rect.height * 0.55)
        let iconX = rect.minX + 6
        let iconY = rect.midY - iconSize / 2
        let glassRadius = iconSize * 0.35
        let glassCenter = CGPoint(x: iconX + glassRadius + 1, y: iconY + glassRadius + 1)

        ctx.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.addArc(center: glassCenter, radius: glassRadius,
                   startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
        // Handle
        let handleStart = CGPoint(x: glassCenter.x + glassRadius * 0.7,
                                  y: glassCenter.y + glassRadius * 0.7)
        let handleEnd = CGPoint(x: handleStart.x + iconSize * 0.3,
                                y: handleStart.y + iconSize * 0.3)
        ctx.move(to: handleStart)
        ctx.addLine(to: handleEnd)
        ctx.strokePath()

        // Placeholder text.
        let prompt = part.searchText.isEmpty ? part.searchPrompt : part.searchText
        let displayText = prompt.isEmpty ? "Search" : prompt
        let textColor: NSColor = part.searchText.isEmpty
            ? NSColor.placeholderTextColor
            : NSColor.labelColor
        let fontSize = CGFloat(part.textSize > 0 ? part.textSize : 13)
        let nsFont = NSFont(name: part.textFont, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont, .foregroundColor: textColor, .paragraphStyle: para
        ]
        let textLeft = iconX + iconSize + 6
        let textRect = CGRect(x: textLeft, y: rect.minY,
                              width: rect.maxX - textLeft - 8, height: rect.height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (displayText as NSString).draw(in: textRect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }
}
#endif

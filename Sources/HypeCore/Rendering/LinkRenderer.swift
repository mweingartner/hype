import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for `link` parts.
///
/// Draws a styled hyperlink label. At runtime `LinkHostNSView` overlays
/// this with a clickable `NSTextField`.
public enum LinkRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Determine link text: textContent if set, else the URL.
        let displayText = part.textContent.isEmpty ? part.url : part.textContent
        guard !displayText.isEmpty else {
            ctx.restoreGState()
            return
        }

        let fontSize = CGFloat(part.textSize > 0 ? part.textSize : 14)
        let nsFont = NSFont(name: part.textFont, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        // Blue, underlined link styling.
        let linkColor: NSColor = {
            if !part.fillColor.isEmpty, let c = NSColor(hexString: part.fillColor) { return c }
            return NSColor(red: 0, green: 0.4, blue: 0.8, alpha: 1)
        }()

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .paragraphStyle: para,
        ]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let padding: CGFloat = 4
        let textRect = rect.insetBy(dx: padding, dy: padding)
        (displayText as NSString).draw(in: textRect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }
}
#endif

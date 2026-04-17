import Foundation
#if canImport(AppKit)
import AppKit

/// Renders field parts using Core Graphics.
public enum FieldRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        switch part.fieldStyle {
        case .transparent:
            break
        case .opaque:
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect)
        case .rectangle:
            // Rectangle fields draw a 1-pixel *black* border around
            // the entire perimeter — unambiguous at any zoom level
            // and immediately readable as a framed text field. The
            // generic-visibility pass below explicitly skips this
            // style so the gray separator color doesn't overwrite
            // the black border we just painted.
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect)
        case .shadow:
            let shadowRect = rect.offsetBy(dx: 2, dy: -2)
            ctx.setFillColor(NSColor.shadowColor.withAlphaComponent(0.2).cgColor)
            ctx.fill(shadowRect)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.stroke(rect)
        case .scrolling:
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect)
            // Scrollbar track
            let scrollRect = CGRect(x: rect.maxX - 16, y: rect.minY, width: 16, height: rect.height)
            ctx.setFillColor(NSColor.controlColor.cgColor)
            ctx.fill(scrollRect)
            ctx.stroke(scrollRect)
        }

        // Give transparent / opaque fields a faint outline so the
        // user can see where they are on the canvas. Styles that
        // already paint their own border (rectangle, shadow,
        // scrolling) are skipped — otherwise the gray separator
        // color would overwrite the rectangle style's black border.
        if part.visible {
            switch part.fieldStyle {
            case .transparent, .opaque:
                ctx.setStrokeColor(NSColor.separatorColor.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(rect)
            case .rectangle, .shadow, .scrolling:
                break
            }
        }

        // Draw text content
        if !part.textContent.isEmpty {
            let padding: CGFloat = part.wideMargins ? 8 : 4
            let textRect = rect.insetBy(dx: padding, dy: padding)
            let maxWidth = textRect.width - (part.fieldStyle == .scrolling ? 16 : 0)

            let nsFont = NSFont(name: part.textFont, size: CGFloat(part.textSize)) ?? NSFont.systemFont(ofSize: CGFloat(part.textSize))
            let alignment: NSTextAlignment = part.textAlign == .center ? .center : part.textAlign == .right ? .right : .left
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            paragraphStyle.lineBreakMode = part.dontWrap ? .byClipping : .byWordWrapping

            let attrs: [NSAttributedString.Key: Any] = [
                .font: nsFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle,
            ]

            let displayText = String(part.textContent.prefix(10_000))

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let drawRect = NSRect(x: textRect.minX, y: textRect.minY, width: maxWidth, height: textRect.height)
            (displayText as NSString).draw(in: drawRect, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }

        ctx.restoreGState()
    }
}
#endif

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
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
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

        // When the field is visible, always draw a 1-pixel border
        // so the user can see the field's bounds on the canvas.
        // This applies to ALL field styles including transparent
        // and opaque (which otherwise have no visible border).
        // The border is a subtle gray line that doesn't clash with
        // the field's own style-specific chrome — for styles that
        // already have a border (rectangle, shadow, scrolling),
        // this is a no-op visually since the style border paints
        // on top. For transparent and opaque fields it's the ONLY
        // visual indicator of where the field is, which is exactly
        // the user's request.
        if part.visible {
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect)
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

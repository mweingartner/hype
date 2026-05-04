import Foundation
#if canImport(AppKit)
import AppKit

/// Renders field parts using Core Graphics.
public enum FieldRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        let fillColor = (NSColor(hexString: part.fillColor) ?? .white).cgColor
        let strokeColor = (NSColor(hexString: part.strokeColor) ?? .black).cgColor
        let strokeWidth = max(0, CGFloat(part.strokeWidth))

        func strokeFieldRect(_ targetRect: CGRect) {
            guard strokeWidth > 0 else { return }
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(strokeWidth)
            let inset = strokeWidth / 2
            ctx.stroke(targetRect.insetBy(dx: inset, dy: inset))
        }

        switch part.fieldStyle {
        case .transparent:
            break
        case .opaque:
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            strokeFieldRect(rect)
        case .rectangle:
            // Rectangle fields render the field's stored fill and
            // stroke values so AI/user property edits are visible.
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            strokeFieldRect(rect)
        case .shadow:
            let shadowRect = rect.offsetBy(dx: 2, dy: -2)
            ctx.setFillColor(NSColor.shadowColor.withAlphaComponent(0.2).cgColor)
            ctx.fill(shadowRect)
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            strokeFieldRect(rect)
        case .scrolling:
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            strokeFieldRect(rect)
            // Scrollbar track
            let scrollRect = CGRect(x: rect.maxX - 16, y: rect.minY, width: 16, height: rect.height)
            ctx.setFillColor(NSColor.controlColor.cgColor)
            ctx.fill(scrollRect)
            strokeFieldRect(scrollRect)
        case .secure:
            // Secure fields look like rectangle fields but mask text as bullets.
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            strokeFieldRect(rect)
        }

        if part.visible && part.fieldStyle == .transparent {
            strokeFieldRect(rect)
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

            // Secure fields render bullets instead of the raw text (security condition 2).
            let displayText: String
            if part.fieldStyle == .secure {
                displayText = String(repeating: "●", count: min(part.textContent.count, 50))
            } else {
                displayText = String(part.textContent.prefix(10_000))
            }

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

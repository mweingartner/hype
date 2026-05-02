import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for PDF parts.
///
/// PDF parts are backed at runtime by a `PDFView` hosted as a
/// subview in browse mode. This renderer is the placeholder that
/// shows in edit mode AND inside `CardRenderer.renderToImage`.
///
/// The placeholder shows a simple "PDF" icon plus the source URL's
/// last component so the user identifies the document at a glance
/// without needing the live viewer.
public enum PDFRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Background — light surface.
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // PDF "page" icon centered horizontally — a folded-corner sheet.
        let iconSize: CGFloat = min(48, rect.height * 0.4)
        let iconRect = CGRect(
            x: rect.midX - iconSize / 2,
            y: rect.minY + 16,
            width: iconSize * 0.78,
            height: iconSize
        )
        let iconPath = NSBezierPath()
        let cornerInset: CGFloat = iconSize * 0.18
        iconPath.move(to: NSPoint(x: iconRect.minX, y: iconRect.minY))
        iconPath.line(to: NSPoint(x: iconRect.maxX - cornerInset, y: iconRect.minY))
        iconPath.line(to: NSPoint(x: iconRect.maxX, y: iconRect.minY + cornerInset))
        iconPath.line(to: NSPoint(x: iconRect.maxX, y: iconRect.maxY))
        iconPath.line(to: NSPoint(x: iconRect.minX, y: iconRect.maxY))
        iconPath.close()
        ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.15).cgColor)
        ctx.beginPath()
        addBezierPath(iconPath, to: ctx)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(1.5)
        addBezierPath(iconPath, to: ctx)
        ctx.strokePath()

        // "PDF" label inside the icon.
        let labelRect = CGRect(
            x: iconRect.minX,
            y: iconRect.midY - 6,
            width: iconRect.width,
            height: 12
        )
        drawCenteredText(
            "PDF",
            in: labelRect,
            font: NSFont.systemFont(ofSize: 10, weight: .bold),
            color: NSColor.systemRed,
            ctx: ctx
        )

        // Filename / URL caption below the icon.
        let caption = filenameCaption(for: part)
        let captionRect = CGRect(
            x: rect.minX + 6,
            y: iconRect.maxY + 6,
            width: rect.width - 12,
            height: 16
        )
        drawCenteredText(
            caption,
            in: captionRect,
            font: NSFont.systemFont(ofSize: 11),
            color: NSColor.labelColor,
            ctx: ctx
        )

        // Page indicator.
        let pageRect = CGRect(
            x: rect.minX,
            y: rect.maxY - 18,
            width: rect.width,
            height: 14
        )
        drawCenteredText(
            "Page \(part.pdfCurrentPage)",
            in: pageRect,
            font: NSFont.systemFont(ofSize: 9),
            color: NSColor.secondaryLabelColor,
            ctx: ctx
        )

        ctx.restoreGState()
    }

    private static func filenameCaption(for part: Part) -> String {
        guard !part.pdfURL.isEmpty else { return "(no PDF loaded)" }
        if let url = URL(string: part.pdfURL) {
            return url.lastPathComponent
        }
        return part.pdfURL
    }

    private static func addBezierPath(_ path: NSBezierPath, to ctx: CGContext) {
        let cgPath = CGMutablePath()
        var pt = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<path.elementCount {
            switch path.element(at: i, associatedPoints: &pt) {
            case .moveTo: cgPath.move(to: pt[0])
            case .lineTo: cgPath.addLine(to: pt[0])
            case .curveTo: cgPath.addCurve(to: pt[2], control1: pt[0], control2: pt[1])
            case .closePath: cgPath.closeSubpath()
            case .quadraticCurveTo: cgPath.addQuadCurve(to: pt[1], control: pt[0])
            case .cubicCurveTo: cgPath.addCurve(to: pt[2], control1: pt[0], control2: pt[1])
            @unknown default: break
            }
        }
        ctx.addPath(cgPath)
    }

    private static func drawCenteredText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif

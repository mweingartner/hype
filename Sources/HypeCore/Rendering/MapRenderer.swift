import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for map parts.
///
/// Map parts use `MKMapView` at runtime in browse mode. This
/// placeholder shows a stylized map graphic + the center coords
/// + the count of annotations so users see the part for what it
/// is in edit mode and inside vision-capture renders.
public enum MapRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Soft pastel background with rounded corners.
        ctx.setFillColor(NSColor(calibratedRed: 0.85, green: 0.94, blue: 0.94, alpha: 1).cgColor)
        let path = RenderGeometry.roundedRectPath(in: rect, cornerWidth: 6, cornerHeight: 6)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Stylized "roads" — a few diagonal strokes for a hint of map.
        ctx.saveGState()
        ctx.clip(to: rect.insetBy(dx: 1, dy: 1))
        ctx.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(2)
        let count = max(3, Int(rect.width / 60))
        for i in 0..<count {
            let x = rect.minX + (rect.width / CGFloat(count)) * CGFloat(i)
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x + rect.height * 0.3, y: rect.maxY))
        }
        for i in 0..<count {
            let y = rect.minY + (rect.height / CGFloat(count)) * CGFloat(i)
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y + rect.width * 0.05))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Pin marker at the center.
        let pinY = rect.midY - 4
        let pinX = rect.midX
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fillEllipse(in: CGRect(x: pinX - 6, y: pinY - 6, width: 12, height: 12))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: pinX - 2, y: pinY - 2, width: 4, height: 4))

        // Coordinate caption at top-left.
        let coordRect = CGRect(x: rect.minX + 6, y: rect.minY + 4, width: rect.width - 12, height: 14)
        drawText(
            String(format: "%.4f, %.4f", part.mapCenterLat, part.mapCenterLon),
            in: coordRect,
            font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            color: NSColor.labelColor,
            alignLeft: true,
            ctx: ctx
        )

        // Annotation count at top-right.
        let annoCount = parseAnnotationCount(part.mapAnnotationsJSON)
        if annoCount > 0 {
            let annoRect = CGRect(
                x: rect.maxX - 80,
                y: rect.minY + 4,
                width: 76,
                height: 14
            )
            drawText(
                "\(annoCount) pin\(annoCount == 1 ? "" : "s")",
                in: annoRect,
                font: NSFont.systemFont(ofSize: 10, weight: .medium),
                color: NSColor.systemRed,
                alignLeft: false,
                ctx: ctx
            )
        }

        ctx.restoreGState()
    }

    private static func parseAnnotationCount(_ json: String) -> Int {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return 0 }
        return arr.count
    }

    private static func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignLeft: Bool, ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let originX = alignLeft ? rect.minX : rect.maxX - size.width
        let origin = CGPoint(x: originX, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif

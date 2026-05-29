import Foundation
#if canImport(AppKit)
import AppKit

/// Renders a placeholder for chart parts on the canvas (edit mode).
public enum ChartRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Light background
        ctx.setFillColor(NSColor(white: 0.97, alpha: 1).cgColor)
        ctx.fill(rect)

        // Border
        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(rect)

        // Parse chart type for display
        let config = ChartConfig.fromJSON(part.chartData)
        let typeLabel = config?.chartType.rawValue.capitalized ?? "Chart"
        let title = config?.title ?? ""

        // Draw simple chart icon
        let iconSize: CGFloat = min(30, rect.width / 4, rect.height / 4)
        let cx = rect.midX
        let cy = rect.midY - 10
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.5).cgColor)
        if config?.chartType == .spider {
            let center = CGPoint(x: cx, y: cy)
            let radius = iconSize / 2
            let points = (0..<5).map { index -> CGPoint in
                let angle = -.pi / 2 - CGFloat(index) * (2 * .pi / 5)
                let factor: CGFloat = [0.9, 0.55, 0.78, 0.45, 0.68][index]
                return CGPoint(
                    x: center.x + cos(angle) * radius * factor,
                    y: center.y + sin(angle) * radius * factor
                )
            }
            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.55).cgColor)
            for index in 0..<5 {
                let angle = -.pi / 2 - CGFloat(index) * (2 * .pi / 5)
                ctx.move(to: center)
                ctx.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
            ctx.strokePath()
            ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.22).cgColor)
            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
            ctx.move(to: points[0])
            for point in points.dropFirst() { ctx.addLine(to: point) }
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        } else {
            let heights: [CGFloat] = [0.6, 1.0, 0.8]
            for i in 0..<3 {
                let bw: CGFloat = iconSize / 5
                let bh: CGFloat = iconSize * heights[i]
                let bx = cx - iconSize / 2 + CGFloat(i) * (bw + 3)
                ctx.fill(CGRect(x: bx, y: cy + iconSize / 2 - bh, width: bw, height: bh))
            }
        }

        // Type and title text
        let displayText = title.isEmpty ? typeLabel : "\(typeLabel): \(title)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.7),
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let textSize = (displayText as NSString).size(withAttributes: attrs)
        (displayText as NSString).draw(
            at: NSPoint(x: cx - textSize.width / 2, y: cy + iconSize / 2 + 8),
            withAttributes: attrs
        )
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }
}
#endif

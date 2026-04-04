import Foundation
#if canImport(AppKit)
import AppKit

/// Renders shape parts using Core Graphics.
public enum ShapeRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        let fillColor = (NSColor(hexString: part.fillColor) ?? .white).cgColor
        let strokeColor = (NSColor(hexString: part.strokeColor) ?? .black).cgColor
        ctx.setFillColor(fillColor)
        ctx.setStrokeColor(strokeColor)
        ctx.setLineWidth(CGFloat(part.strokeWidth))

        switch part.shapeType {
        case .rectangle:
            ctx.fill(rect)
            if part.strokeWidth > 0 { ctx.stroke(rect) }

        case .roundRect:
            let r = min(CGFloat(part.cornerRadius), rect.width / 2, rect.height / 2)
            let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
            if part.strokeWidth > 0 {
                ctx.addPath(path)
                ctx.strokePath()
            }

        case .oval:
            ctx.fillEllipse(in: rect)
            if part.strokeWidth > 0 { ctx.strokeEllipse(in: rect) }

        case .line:
            if part.pathData.count >= 2 {
                let canvasHeight = rect.minY + rect.height + part.top  // approximate
                ctx.move(to: CGPoint(x: part.pathData[0].x, y: canvasHeight - part.pathData[0].y))
                ctx.addLine(to: CGPoint(x: part.pathData.last!.x, y: canvasHeight - part.pathData.last!.y))
                ctx.strokePath()
            } else {
                ctx.move(to: CGPoint(x: rect.minX, y: rect.minY))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                ctx.strokePath()
            }

        case .freeform:
            if part.pathData.count >= 2 {
                let canvasHeight = rect.minY + rect.height + part.top
                ctx.move(to: CGPoint(x: part.pathData[0].x, y: canvasHeight - part.pathData[0].y))
                for i in 1..<part.pathData.count {
                    ctx.addLine(to: CGPoint(x: part.pathData[i].x, y: canvasHeight - part.pathData[i].y))
                }
                ctx.closePath()
                ctx.fillPath()
            }
        }

        ctx.restoreGState()
    }
}

// MARK: - NSColor hex extension

extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
#endif

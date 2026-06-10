import Foundation
#if canImport(AppKit)
import AppKit

/// Renders shape parts using Core Graphics.
public enum ShapeRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect, theme: HypeTheme? = nil) {
        ctx.saveGState()
        let useGlass = GlassRenderer.shouldUseGlass(for: theme)

        // Apply rotation around the shape's centre when non-zero.
        // HypeTalk's `set the rotation of <shape> to N` writes the
        // angle in degrees, clockwise. Core Graphics rotates
        // counter-clockwise for positive angles, so we negate the
        // degrees before converting to radians. The rotation is
        // translated to the shape's centre so rotation happens in
        // place rather than around the view origin.
        if part.rotation != 0 {
            let cx = rect.midX
            let cy = rect.midY
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: -CGFloat(part.rotation) * .pi / 180)
            ctx.translateBy(x: -cx, y: -cy)
        }

        let fillColor = (NSColor(hexString: part.fillColor) ?? .white).cgColor
        let strokeColor = (NSColor(hexString: part.strokeColor) ?? .black).cgColor
        ctx.setFillColor(fillColor)
        ctx.setStrokeColor(strokeColor)
        ctx.setLineWidth(CGFloat(part.strokeWidth))

        switch part.shapeType {
        case .rectangle:
            if useGlass {
                let cornerR = theme.map { CGFloat($0.cornerRadiusMedium) } ?? 0
                GlassRenderer.fillRoundedRect(
                    ctx: ctx, rect: rect,
                    fillHex: part.fillColor,
                    cornerRadius: cornerR,
                    strokeHex: part.strokeWidth > 0 ? part.strokeColor : nil,
                    strokeWidth: CGFloat(part.strokeWidth),
                    shadowOpacity: theme.map { CGFloat($0.shadowOpacity) } ?? 0,
                    shadowRadius: theme.map { CGFloat($0.shadowRadius) } ?? 0
                )
            } else {
                ctx.fill(rect)
                if part.strokeWidth > 0 { ctx.stroke(rect) }
            }

        case .roundRect:
            // Use the shared helper so NaN/negative part geometry can't
            // trip CGPath's preconditions. The clamp formula is identical
            // to the previous inline: min(radius, w/2, h/2), floor at 0.
            let rawR = CGFloat(part.cornerRadius)
            if useGlass {
                // GlassRenderer.fillRoundedRect now routes through
                // RenderGeometry internally, but we still clamp here so
                // the caller's radius is already safe.
                let safeR = RenderGeometry.safeRect(rect)
                let clampedR = max(0, min(rawR.isFinite ? rawR : 0, safeR.width / 2, safeR.height / 2))
                GlassRenderer.fillRoundedRect(
                    ctx: ctx, rect: rect,
                    fillHex: part.fillColor,
                    cornerRadius: clampedR,
                    strokeHex: part.strokeWidth > 0 ? part.strokeColor : nil,
                    strokeWidth: CGFloat(part.strokeWidth),
                    shadowOpacity: theme.map { CGFloat($0.shadowOpacity) } ?? 0,
                    shadowRadius: theme.map { CGFloat($0.shadowRadius) } ?? 0
                )
            } else {
                let path = RenderGeometry.roundedRectPath(in: rect, cornerRadius: rawR)
                ctx.addPath(path)
                ctx.fillPath()
                if part.strokeWidth > 0 {
                    ctx.addPath(path)
                    ctx.strokePath()
                }
            }

        case .oval:
            // Glass oval would need a custom helper; for now apply
            // the standard fill+stroke. The oval shape's signature is
            // already strong enough that glass isn't a visual win.
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

public extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// Render this color as a `#RRGGBB` hex string. Converts to
    /// sRGB first so the round-trip is consistent regardless of
    /// the color's source space (deviceRGB, calibratedRGB, etc.).
    var hexString: String {
        let srgb = usingColorSpace(.sRGB) ?? self
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif

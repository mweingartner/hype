import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for `gauge` parts.
///
/// Edit-mode placeholder. At runtime `GaugeHostNSView` (an
/// `NSHostingView` wrapping SwiftUI `Gauge`) overlays this.
public enum GaugeRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect, theme: HypeTheme? = nil) {
        // Gauge uses an NSHostingView<SwiftUI Gauge> at runtime; the
        // CG path is an edit-mode placeholder. Live glass treatment
        // happens via SwiftUI's `.background(.regularMaterial)` on
        // the host when the theme flag is set; the placeholder stays
        // simple so the user can always see the gauge geometry.
        _ = theme
        ctx.saveGState()

        // Background — fixed 6pt corners, but the part rect may be
        // script-authored (zero/negative/NaN), so route through
        // RenderGeometry to guard CGPath preconditions.
        let bg = NSColor.controlBackgroundColor.cgColor
        ctx.setFillColor(bg)
        let path = RenderGeometry.roundedRectPath(in: rect, cornerRadius: 6)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Resolve safe bounds (security condition 5: guard NaN/Inf).
        let safeMin = part.gaugeMin.isFinite ? part.gaugeMin : 0
        let rawMax = part.gaugeMax.isFinite ? part.gaugeMax : 1
        let safeMax = rawMax > safeMin ? rawMax : safeMin + 1
        let safeValue = part.gaugeValue.isFinite ? part.gaugeValue : safeMin
        let fraction = min(1, max(0, (safeValue - safeMin) / (safeMax - safeMin)))

        let tint = resolvedTint(part.gaugeTint)

        let style = part.gaugeStyle
        let isCircular = style.contains("ircular")

        if isCircular {
            let radius: CGFloat = min(rect.width, rect.height) * 0.32
            let center = CGPoint(x: rect.midX, y: rect.midY)
            ctx.setLineWidth(4)
            ctx.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.2).cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()
            if fraction > 0 {
                ctx.setStrokeColor(tint.cgColor)
                let start: CGFloat = -.pi / 2
                ctx.addArc(center: center, radius: radius, startAngle: start,
                           endAngle: start + CGFloat(fraction) * .pi * 2, clockwise: false)
                ctx.strokePath()
            }
            // Value label in center — honor gaugeDecimals so a
            // gauge configured for integral steps shows "17" not
            // "17.0". Negative decimals defensively clamp to 0.
            let d = max(0, part.gaugeDecimals)
            let valueText = String(format: "%.\(d)f", safeValue)
            let labelRect = CGRect(x: center.x - 20, y: center.y - 8, width: 40, height: 16)
            drawText(valueText, in: labelRect, ctx: ctx,
                     font: NSFont.systemFont(ofSize: 10, weight: .medium),
                     color: NSColor.labelColor, centered: true)
        } else {
            // Linear bar
            let barPadding: CGFloat = 8
            let barHeight: CGFloat = min(14, rect.height * 0.35)
            let barTop = rect.midY - barHeight / 2
            // Clamp track width to ≥ 0 so a narrow script-authored part
            // (rect.width < 16) doesn't produce a negative-width rect,
            // which CGPath treats as a precondition violation.
            let trackWidth = max(0, rect.width - barPadding * 2)
            let trackRect = CGRect(x: rect.minX + barPadding, y: barTop,
                                   width: trackWidth, height: barHeight)
            let trackPath = RenderGeometry.roundedRectPath(in: trackRect, cornerRadius: barHeight / 2)
            ctx.setFillColor(NSColor.systemGray.withAlphaComponent(0.2).cgColor)
            ctx.addPath(trackPath)
            ctx.fillPath()

            if fraction > 0 {
                // Clamp fill width so it's never negative and never exceeds
                // the track (both matter when the track itself is very small).
                let rawFillWidth = max(barHeight, trackRect.width * CGFloat(fraction))
                let fillWidth = max(0, min(rawFillWidth, trackRect.width))
                let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY,
                                      width: fillWidth, height: barHeight)
                let fillPath = RenderGeometry.roundedRectPath(in: fillRect, cornerRadius: barHeight / 2)
                ctx.setFillColor(tint.cgColor)
                ctx.addPath(fillPath)
                ctx.fillPath()
            }

            // Min / max / label labels
            if !part.gaugeMinLabel.isEmpty {
                let minR = CGRect(x: trackRect.minX, y: trackRect.maxY + 2, width: 40, height: 12)
                drawText(part.gaugeMinLabel, in: minR, ctx: ctx,
                         font: NSFont.systemFont(ofSize: 9), color: NSColor.secondaryLabelColor, centered: false)
            }
            if !part.gaugeMaxLabel.isEmpty {
                let maxR = CGRect(x: trackRect.maxX - 40, y: trackRect.maxY + 2, width: 40, height: 12)
                drawText(part.gaugeMaxLabel, in: maxR, ctx: ctx,
                         font: NSFont.systemFont(ofSize: 9), color: NSColor.secondaryLabelColor, centered: false)
            }
        }

        // Top label
        if !part.gaugeLabel.isEmpty {
            let labelRect = CGRect(x: rect.minX + 8, y: rect.minY + 2,
                                   width: rect.width - 16, height: 14)
            drawText(part.gaugeLabel, in: labelRect, ctx: ctx,
                     font: NSFont.systemFont(ofSize: 10), color: NSColor.secondaryLabelColor, centered: false)
        }

        ctx.restoreGState()
    }

    // MARK: - Helpers

    private static func resolvedTint(_ hex: String) -> NSColor {
        guard !hex.isEmpty, let color = NSColor(hexString: hex) else {
            return NSColor.controlAccentColor
        }
        return color
    }

    private static func drawText(_ text: String, in rect: CGRect, ctx: CGContext,
                                  font: NSFont, color: NSColor, centered: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let para = NSMutableParagraphStyle()
        para.alignment = centered ? .center : .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif

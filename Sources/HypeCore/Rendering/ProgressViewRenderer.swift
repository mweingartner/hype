import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for `progressView` parts.
///
/// Edit-mode placeholder. At runtime `ProgressViewHostNSView` (an
/// `NSProgressIndicator` wrapper) overlays this in browse mode.
public enum ProgressViewRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect, theme: HypeTheme? = nil) {
        // ProgressView uses NSProgressIndicator at runtime; the CG
        // path is just an edit-mode placeholder. Glass treatment is
        // applied through the live AppKit overlay's window material.
        _ = theme
        ctx.saveGState()

        // No full-rect background. The renderer used to fill the
        // entire part bounds with `controlBackgroundColor` + a
        // rounded stroke, but in browse mode the live
        // `NSProgressIndicator` host overlays only the slim bar
        // area, so the renderer's rounded box showed through
        // ABOVE and BELOW the bar — making the part look like
        // it was "filled" across its entire rectangle. Drop the
        // outer box entirely; only draw the slim bar/label/spinner
        // so edit-mode + run-mode visually match the host view's
        // narrow vertical extent.

        let barPadding: CGFloat = 8
        let barHeight: CGFloat = min(12, rect.height * 0.35)
        var barTop = rect.midY - barHeight / 2

        // If a label is set, render it above the bar.
        if !part.progressLabel.isEmpty {
            let labelHeight: CGFloat = 16
            barTop = rect.minY + labelHeight + 4
            let labelRect = CGRect(x: rect.minX + barPadding, y: rect.minY + 2,
                                   width: rect.width - barPadding * 2, height: labelHeight)
            drawText(part.progressLabel, in: labelRect, ctx: ctx,
                     font: NSFont.systemFont(ofSize: 11),
                     color: NSColor.secondaryLabelColor)
        }

        if part.progressIsCircular {
            // Circular placeholder: arc proportional to value/total.
            let radius: CGFloat = min(rect.width, rect.height) * 0.3
            let center = CGPoint(x: rect.midX, y: rect.midY)
            ctx.setLineWidth(3)
            ctx.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.25).cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()

            let safeTotal = part.progressTotal.isFinite && part.progressTotal > 0 ? part.progressTotal : 1
            let fraction = part.progressIsIndeterminate ? 0.33
                : min(1, max(0, part.progressValue.isFinite ? part.progressValue / safeTotal : 0))
            if fraction > 0 {
                let tintColor = resolvedTint(part.progressTint)
                ctx.setStrokeColor(tintColor.cgColor)
                let start: CGFloat = -.pi / 2
                let end = start + CGFloat(fraction) * .pi * 2
                ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                ctx.strokePath()
            }
        } else {
            // Linear bar placeholder.
            // Clamp track width to ≥ 0 so a narrow script-authored part
            // (rect.width < barPadding * 2) doesn't produce a negative-
            // width rect, which CGPath treats as a precondition violation.
            let trackWidth = max(0, rect.width - barPadding * 2)
            let trackRect = CGRect(x: rect.minX + barPadding, y: barTop,
                                   width: trackWidth, height: barHeight)
            let trackPath = RenderGeometry.roundedRectPath(in: trackRect, cornerRadius: barHeight / 2)
            ctx.setFillColor(NSColor.systemGray.withAlphaComponent(0.2).cgColor)
            ctx.addPath(trackPath)
            ctx.fillPath()

            let safeTotal = part.progressTotal.isFinite && part.progressTotal > 0 ? part.progressTotal : 1
            let fraction = part.progressIsIndeterminate ? 0.33
                : min(1, max(0, part.progressValue.isFinite ? part.progressValue / safeTotal : 0))
            if fraction > 0 {
                // Clamp fill width so it's never negative and never exceeds
                // the track.
                let rawFillWidth = max(barHeight, trackRect.width * CGFloat(fraction))
                let fillWidth = max(0, min(rawFillWidth, trackRect.width))
                let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY,
                                      width: fillWidth, height: barHeight)
                let fillPath = RenderGeometry.roundedRectPath(in: fillRect, cornerRadius: barHeight / 2)
                ctx.setFillColor(resolvedTint(part.progressTint).cgColor)
                ctx.addPath(fillPath)
                ctx.fillPath()
            }

            if part.progressIsIndeterminate {
                // Draw "…" label as a visual cue for indeterminate state.
                let dotRect = CGRect(x: trackRect.minX, y: barTop - 14,
                                     width: 20, height: 12)
                drawText("…", in: dotRect, ctx: ctx,
                         font: NSFont.systemFont(ofSize: 10),
                         color: NSColor.secondaryLabelColor)
            }
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
                                  font: NSFont, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(in: rect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif

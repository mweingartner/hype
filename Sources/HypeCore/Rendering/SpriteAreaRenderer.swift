import Foundation
#if canImport(AppKit)
import AppKit

/// Renders a placeholder for sprite area parts on the canvas (edit mode).
public enum SpriteAreaRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Teal background — skipped when part.transparentBackground
        // is on, so any image part placed BEHIND this sprite area
        // shows through in CGContext-rendered snapshots/exports.
        // The dashed border still draws so the editor still has
        // a visible authoring outline.
        if !part.transparentBackground {
            ctx.setFillColor(NSColor.systemTeal.withAlphaComponent(0.15).cgColor)
            ctx.fill(rect)
        }

        // Dashed border
        ctx.setStrokeColor(NSColor.systemTeal.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(rect.insetBy(dx: 1, dy: 1))
        ctx.setLineDash(phase: 0, lengths: [])

        // Parse scene name
        let sceneName: String
        if let spec = SceneSpec.fromJSON(part.sceneSpec) {
            sceneName = "Scene: \(spec.name) (\(spec.nodes.count) nodes)"
        } else {
            sceneName = "Sprite Area (no scene)"
        }

        // Draw icon + text centered
        let displayText = "\u{1F3AE} \(sceneName)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.systemTeal,
        ]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let textSize = (displayText as NSString).size(withAttributes: attrs)
        (displayText as NSString).draw(
            at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attrs
        )
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }
}
#endif

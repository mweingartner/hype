import Foundation
#if canImport(AppKit)
import AppKit

/// Renders image parts onto a CGContext.
public enum ImageRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Kick off async GIF decode / ensure state when the part's
        // data is an animated GIF.  This is O(1) when state already
        // exists (fingerprint match).  Returns immediately — the
        // main thread is never blocked on decode.
        if part.animated, let data = part.imageData {
            GIFAnimator.shared.ensureState(partId: part.id, imageData: data, autoplay: true)
        }

        var drewFromAnimator = false

        // Query the animator for the current GIF frame.
        if let cgImage = GIFAnimator.shared.currentFrame(partId: part.id) {
            var toDraw = part.transparentBackground
                ? ImageChromaKey.apply(to: cgImage)
                : cgImage
            // CoreImage filter pass (sepia, blur, vignette, etc.) —
            // returns the original when filter name is empty/unknown.
            if !part.imageFilter.isEmpty {
                toDraw = ImageFilter.apply(part.imageFilter, intensity: part.imageFilterIntensity, to: toDraw)
            }
            drawCGImageFlipped(ctx: ctx, image: toDraw, rect: rect)
            drewFromAnimator = true
        }

        // Static fallback: JPEG / PNG / single-frame GIF / decode-pending.
        if !drewFromAnimator {
            if let data = part.imageData,
               let image = NSImage(data: data),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                var toDraw = part.transparentBackground
                    ? ImageChromaKey.apply(to: cgImage)
                    : cgImage
                if !part.imageFilter.isEmpty {
                    toDraw = ImageFilter.apply(part.imageFilter, intensity: part.imageFilterIntensity, to: toDraw)
                }
                drawCGImageFlipped(ctx: ctx, image: toDraw, rect: rect)
            } else if part.imageData == nil {
                // Placeholder — no image loaded yet.
                ctx.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(NSColor.gray.cgColor)
                ctx.setLineWidth(1)
                ctx.setLineDash(phase: 0, lengths: [4, 4])
                ctx.stroke(rect)

                let text = "Image" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: min(rect.width, rect.height) * 0.2),
                    .foregroundColor: NSColor.gray,
                ]
                let textSize = text.size(withAttributes: attrs)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                text.draw(
                    at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                    withAttributes: attrs
                )
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        // Invert-on-hilite (image parts that respond to click).
        if part.hilite {
            ctx.setBlendMode(.difference)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect)
            ctx.setBlendMode(.normal)
        }

        ctx.restoreGState()
    }

    /// Draw a `CGImage` into `rect` with a Y-flip to compensate for
    /// AppKit's flipped coordinate system.  Extracted as a helper so
    /// both the animator path and the static-image path share one
    /// implementation.
    private static func drawCGImageFlipped(ctx: CGContext, image: CGImage, rect: CGRect) {
        ctx.saveGState()
        // Translate to the bottom of the rect and flip vertically.
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}
#endif

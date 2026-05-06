import Foundation
#if canImport(AppKit)
import AppKit

/// Helpers for rendering a part with the "Liquid Glass" treatment.
///
/// CG can't run a live blur, so this isn't a faithful reproduction
/// of `NSVisualEffectView`'s vibrancy at the per-part level — but the
/// visual signature of glass (translucent fill, top-edge specular
/// highlight, soft outer drop shadow) is reproducible with three
/// flat passes:
///
/// 1. **Outer drop shadow** — soft radial gradient anchored ~3pt
///    below the part. Subtle (alpha ~0.18) so the part reads as
///    floating without feeling heavy.
/// 2. **Translucent fill** — the resolved fillColor at ~65-72% alpha.
///    Lets the underlying card surface (`theme.cardBackground` —
///    itself translucent in this theme) bleed through.
/// 3. **Top-edge highlight** — 1pt tall white-ish gradient along the
///    top of the rounded rect. Reads as the bevel a glass element
///    would catch from overhead light.
///
/// Renderers that opt in (`ButtonRenderer`, `FieldRenderer`,
/// `ShapeRenderer`, etc. — when `theme.usesGlassMaterial == true`)
/// call `GlassRenderer.fillRoundedRect(...)` in place of their flat
/// `setFillColor / fill / stroke` sequence.
public enum GlassRenderer {

    /// Decide whether a renderer should use the glass treatment.
    /// Centralized so the per-renderer call site is just an early-
    /// return.
    public static func shouldUseGlass(for theme: HypeTheme?) -> Bool {
        theme?.usesGlassMaterial == true
    }

    /// Paint a glass-style fill inside `rect`, with rounded corners
    /// at `cornerRadius`, using the resolved color `fillHex` (alpha
    /// from the hex's alpha channel if 8 chars, else applied as
    /// 65%). Adds the top-edge highlight + outer drop shadow.
    ///
    /// `strokeHex` is optional — pass nil to skip the hairline ring.
    /// The ring itself is also alpha-bled so the part doesn't feel
    /// heavy in dark mode.
    public static func fillRoundedRect(
        ctx: CGContext,
        rect: CGRect,
        fillHex: String,
        cornerRadius: CGFloat,
        strokeHex: String? = nil,
        strokeWidth: CGFloat = 0.5,
        shadowOpacity: CGFloat = 0.18,
        shadowRadius: CGFloat = 8
    ) {
        ctx.saveGState()

        // 1) Outer drop shadow.
        let shadowColor = NSColor.black.withAlphaComponent(shadowOpacity).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: 3),
                      blur: shadowRadius,
                      color: shadowColor)

        // 2) Translucent fill.
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(path)
        let fill = nsColorFromHexWithAlpha(fillHex, defaultAlpha: 0.65).cgColor
        ctx.setFillColor(fill)
        ctx.fillPath()

        // Disable the shadow before painting the highlight so it
        // doesn't acquire the same drop offset.
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        // 3) Top-edge specular highlight.
        // Clip to the rounded rect, then paint a 1pt white gradient
        // along the top — outside the clip the highlight wouldn't
        // hug the corners.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let topGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor.white.withAlphaComponent(0.35).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor,
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        let highlightHeight = min(rect.height * 0.5, 12)
        ctx.drawLinearGradient(
            topGradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.minY + highlightHeight),
            options: []
        )
        ctx.restoreGState()

        // 4) Hairline border ring.
        if let strokeHex {
            ctx.addPath(path)
            ctx.setStrokeColor(nsColorFromHexWithAlpha(strokeHex, defaultAlpha: 1.0).cgColor)
            ctx.setLineWidth(strokeWidth)
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    /// Variant for plain (non-rounded) rectangles — just delegates.
    public static func fillRect(
        ctx: CGContext,
        rect: CGRect,
        fillHex: String,
        strokeHex: String? = nil,
        strokeWidth: CGFloat = 0.5,
        shadowOpacity: CGFloat = 0.18,
        shadowRadius: CGFloat = 8
    ) {
        fillRoundedRect(
            ctx: ctx,
            rect: rect,
            fillHex: fillHex,
            cornerRadius: 0,
            strokeHex: strokeHex,
            strokeWidth: strokeWidth,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius
        )
    }

    /// Parse `"#RRGGBB"` or `"#RRGGBBAA"` into an `NSColor`. When the
    /// hex carries no alpha channel, applies `defaultAlpha`. Used by
    /// the helpers above so theme color refs (which may include an
    /// alpha) translate correctly.
    static func nsColorFromHexWithAlpha(_ hex: String, defaultAlpha: CGFloat) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              let value = UInt32(s, radix: 16)
        else { return NSColor.white.withAlphaComponent(defaultAlpha) }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >>  8) & 0xFF) / 255
            a = CGFloat( value        & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >>  8) & 0xFF) / 255
            b = CGFloat( value        & 0xFF) / 255
            a = defaultAlpha
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
#endif

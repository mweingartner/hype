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

        // Honor Apple's accessibility-display flags. When Reduce
        // Transparency is on, fall back to a flat opaque fill with
        // a real border — same shape, no glass illusion. When
        // Increase Contrast is on, drop the specular highlight and
        // beef up the border so the control reads with a stark
        // edge instead of a soft bevel. Apple HIG: "Never override
        // system settings."
        let reduceTransparency = LiquidGlassEnvironment.reduceTransparency
        let increaseContrast = LiquidGlassEnvironment.increaseContrast

        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // 1) Outer drop shadow — skipped in high-contrast mode
        // so the part edge reads as crisp, not floating.
        if !increaseContrast {
            let shadowColor = NSColor.black.withAlphaComponent(shadowOpacity).cgColor
            ctx.setShadow(offset: CGSize(width: 0, height: 3),
                          blur: shadowRadius,
                          color: shadowColor)
        }

        // 2) Fill. Opaque under Reduce Transparency; otherwise the
        // theme's resolved alpha (defaults to 65%) bleeds the
        // background through, matching Apple's frosted-glass look.
        ctx.addPath(path)
        let fillAlpha: CGFloat = reduceTransparency ? 1.0 : 0.65
        let fill = nsColorFromHexWithAlpha(fillHex, defaultAlpha: fillAlpha).cgColor
        ctx.setFillColor(fill)
        ctx.fillPath()

        // Disable shadow before painting highlights / border so they
        // don't inherit the drop offset.
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        // 3) Specular highlight — only in default mode. Apple's
        // actual Liquid Glass uses real-time refraction; the closest
        // CG can do without a Metal shader is a thin top-edge sheen
        // that suggests a glass bevel. Slimmer than the prior
        // implementation (12pt → 6pt) so it reads as a refractive
        // edge rather than a heavy gradient.
        if !increaseContrast && !reduceTransparency {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()

            // Top-edge sheen.
            let topGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor.white.withAlphaComponent(0.30).cgColor,
                    NSColor.white.withAlphaComponent(0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            let highlightHeight = min(rect.height * 0.35, 6)
            ctx.drawLinearGradient(
                topGradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.minY + highlightHeight),
                options: []
            )

            // Bottom-edge counter-glow — adds the depth cue that
            // distinguishes Liquid Glass from old-school glossy
            // buttons. Very faint (alpha 0.10) so it doesn't read
            // as a second highlight.
            let bottomGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor.white.withAlphaComponent(0.0).cgColor,
                    NSColor.white.withAlphaComponent(0.10).cgColor,
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            let bottomHeight = min(rect.height * 0.4, 4)
            ctx.drawLinearGradient(
                bottomGradient,
                start: CGPoint(x: rect.midX, y: rect.maxY - bottomHeight),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )

            ctx.restoreGState()
        }

        // 4) Border. In high-contrast mode, force a visible stroke
        // even when the caller passed nil and beef up the alpha so
        // the part has a crisp outline that doesn't depend on the
        // soft glass bevel.
        let effectiveStroke = increaseContrast
            ? (strokeHex ?? "#000000")
            : strokeHex
        let effectiveAlpha: CGFloat = increaseContrast ? 0.85 : 1.0
        let effectiveWidth: CGFloat = increaseContrast
            ? max(strokeWidth, 1.0)
            : strokeWidth
        if let s = effectiveStroke {
            ctx.addPath(path)
            ctx.setStrokeColor(nsColorFromHexWithAlpha(s, defaultAlpha: effectiveAlpha).cgColor)
            ctx.setLineWidth(effectiveWidth)
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

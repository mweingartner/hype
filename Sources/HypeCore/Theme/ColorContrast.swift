import Foundation
import CoreGraphics

#if canImport(AppKit)
import AppKit
#endif

/// WCAG 2.x contrast utilities + a hue-preserving adjuster that
/// darkens or lightens a color until it meets a contrast threshold
/// against a reference background.
///
/// **Why this exists**: built-in themes are hand-tuned, but user-
/// created themes (and AI-authored ones) can land on combinations
/// that look on-brand but fail the basic readability bar — e.g. a
/// warm beige background with a tan accent used as `comment` color
/// in the script editor. Rather than ship a theme designer that
/// silently produces unreadable output, every renderer routes its
/// text colors through `ensuringContrast(against:minRatio:)` first.
/// The runtime adjustment preserves hue and saturation, only
/// pushing the lightness component toward 0 or 1 until the
/// contrast threshold is met.
///
/// **Threshold defaults**: WCAG AA for normal text is 4.5:1; for
/// large or bold text 3:1. We default `minRatio` to 4.5 so the
/// safeguard is conservative; callers can opt down to 3.0 for
/// large headings.
public enum ColorContrast {

    // MARK: - Luminance + ratio

    /// WCAG relative luminance for an sRGB color. Inputs are in
    /// `[0, 1]` per channel. Output is in `[0, 1]`.
    ///
    /// Formula: linearize each channel through the sRGB inverse
    /// gamma, then weight by ITU-R BT.709 coefficients.
    public static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let R = linearize(r), G = linearize(g), B = linearize(b)
        return 0.2126 * R + 0.7152 * G + 0.0722 * B
    }

    /// WCAG contrast ratio between two colors. Always >= 1; values
    /// above 4.5 pass AA for normal text, above 7 pass AAA, above
    /// 3 are acceptable for large text only.
    public static func contrastRatio(
        _ a: (r: Double, g: Double, b: Double),
        _ b: (r: Double, g: Double, b: Double)
    ) -> Double {
        let la = relativeLuminance(r: a.r, g: a.g, b: a.b)
        let lb = relativeLuminance(r: b.r, g: b.g, b: b.b)
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Hex parsing helpers

    /// Parse `"#RRGGBB"` or `"#RRGGBBAA"` into normalized
    /// `(r, g, b)` floats in `[0, 1]`. Alpha is ignored. Returns
    /// `nil` for unparseable input.
    public static func parseHex(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              let value = UInt32(s, radix: 16)
        else { return nil }
        let r, g, bb: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            bb = Double((value >>  8) & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >>  8) & 0xFF) / 255
            bb = Double( value        & 0xFF) / 255
        }
        return (r, g, bb)
    }

    /// Encode `(r, g, b)` floats in `[0, 1]` as `"#RRGGBB"`
    /// upper-case hex. Values outside `[0, 1]` are clamped.
    public static func encodeHex(r: Double, g: Double, b: Double) -> String {
        let R = Int((max(0, min(1, r)) * 255).rounded())
        let G = Int((max(0, min(1, g)) * 255).rounded())
        let B = Int((max(0, min(1, b)) * 255).rounded())
        return String(format: "#%02X%02X%02X", R, G, B)
    }

    // MARK: - HSL bridge

    /// Convert sRGB → HSL. Each channel in `[0, 1]`. The hue is in
    /// `[0, 1]` (multiply by 360 for degrees). Achromatic colors
    /// return hue = 0.
    public static func rgbToHSL(r: Double, g: Double, b: Double)
        -> (h: Double, s: Double, l: Double)
    {
        let cmax = max(r, g, b), cmin = min(r, g, b), delta = cmax - cmin
        let l = (cmax + cmin) / 2
        guard delta > 0 else { return (0, 0, l) }
        let s = l < 0.5 ? delta / (cmax + cmin) : delta / (2 - cmax - cmin)
        var h: Double
        switch cmax {
        case r:  h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g:  h = ((b - r) / delta) + 2
        default: h = ((r - g) / delta) + 4
        }
        h /= 6
        if h < 0 { h += 1 }
        return (h, s, l)
    }

    /// Convert HSL → sRGB. Each channel in `[0, 1]`.
    public static func hslToRGB(h: Double, s: Double, l: Double)
        -> (r: Double, g: Double, b: Double)
    {
        guard s > 0 else { return (l, l, l) }
        func hueComponent(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0/6 { return p + (q - p) * 6 * t }
            if t < 1.0/2 { return q }
            if t < 2.0/3 { return p + (q - p) * (2.0/3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (
            hueComponent(p, q, h + 1.0/3),
            hueComponent(p, q, h),
            hueComponent(p, q, h - 1.0/3)
        )
    }

    // MARK: - Contrast-safe adjuster

    /// Adjust `foregroundHex` by walking its HSL lightness toward
    /// 0 or 1 (whichever direction increases contrast against
    /// `backgroundHex`) until WCAG contrast ratio meets or exceeds
    /// `minRatio`. Hue and saturation are preserved so the color
    /// "still fits the theme."
    ///
    /// If the target is unachievable (e.g. someone asks for ratio
    /// 21 between a dark gray and black), the closest achievable
    /// pure black or white is returned.
    ///
    /// Returns the original hex unchanged when the contrast is
    /// already sufficient — callers can wrap every text color in
    /// this without paying a cost on already-correct themes.
    public static func ensuringContrast(
        foregroundHex: String,
        backgroundHex: String,
        minRatio: Double = 4.5
    ) -> String {
        guard let fg = parseHex(foregroundHex),
              let bg = parseHex(backgroundHex)
        else { return foregroundHex }

        let initialRatio = contrastRatio(fg, bg)
        if initialRatio >= minRatio { return foregroundHex }

        let bgLum = relativeLuminance(r: bg.r, g: bg.g, b: bg.b)
        let goingDarker = bgLum > 0.5  // dark-on-light if bg is light
        var hsl = rgbToHSL(r: fg.r, g: fg.g, b: fg.b)

        // Walk lightness in 1% steps. Bounded loop so we always
        // terminate; with a max of 100 iterations the worst-case
        // cost is trivial.
        for _ in 0..<100 {
            if goingDarker {
                if hsl.l <= 0 { break }
                hsl.l = max(0, hsl.l - 0.01)
            } else {
                if hsl.l >= 1 { break }
                hsl.l = min(1, hsl.l + 0.01)
            }
            let candidate = hslToRGB(h: hsl.h, s: hsl.s, l: hsl.l)
            if contrastRatio(candidate, bg) >= minRatio {
                return encodeHex(r: candidate.r, g: candidate.g, b: candidate.b)
            }
        }

        // Fully saturated direction couldn't reach the threshold —
        // return pure black or white as the last resort.
        return goingDarker ? "#000000" : "#FFFFFF"
    }
}

// MARK: - ColorRef convenience

public extension ColorRef {
    /// Return a copy of this color whose effective hex form has at
    /// least `minRatio:1` contrast with `backgroundHex`. System-key
    /// colors are passed through unchanged — they're tied to the
    /// platform's appearance and shouldn't be auto-darkened.
    ///
    /// Use this in any renderer that puts text on a known
    /// background:
    /// ```
    /// let safe = theme.scriptTheme.comment.ensuringContrast(
    ///     against: theme.scriptTheme.background.rawDescription,
    ///     minRatio: 4.5
    /// )
    /// ```
    func ensuringContrast(against backgroundHex: String, minRatio: Double = 4.5)
        -> ColorRef
    {
        switch self {
        case .systemKey:
            // System keys honor macOS appearance — let the OS
            // handle contrast there. Auto-adjusting them would
            // bake the current appearance into the color and break
            // dark-mode adaptation.
            return self
        case .hex(let h):
            let adjusted = ColorContrast.ensuringContrast(
                foregroundHex: h, backgroundHex: backgroundHex, minRatio: minRatio
            )
            return adjusted == h ? self : .hex(adjusted)
        }
    }
}

#if canImport(AppKit)
public extension ColorContrast {
    /// Pick a readable text color (near-black or near-white) for the
    /// given fill background, regardless of system appearance.
    ///
    /// **Why this exists**: `NSColor.labelColor` is dynamic — light
    /// in dark mode, dark in light mode. Using it for text rendered
    /// on a part with an EXPLICIT fill color (e.g. `#FFFFFF`) means
    /// the text adapts to the appearance even though the background
    /// does not — producing white-on-white in dark mode. This helper
    /// chooses a fixed color that contrasts against the actual fill,
    /// independent of system appearance.
    ///
    /// Algorithm: relative luminance of the fill in `[0, 1]` —
    /// > 0.5 picks `#000000`, otherwise `#FFFFFF`. Empty / invalid
    /// fillHex falls back to `#000000` (assumes a light background
    /// since the renderer's white default is the most common case).
    static func readableTextColor(forFillHex fillHex: String) -> NSColor {
        guard let rgb = parseHex(fillHex) else { return NSColor.black }
        let lum = relativeLuminance(r: rgb.r, g: rgb.g, b: rgb.b)
        return lum > 0.5 ? NSColor.black : NSColor.white
    }

    /// Same idea, but takes an arbitrary `NSColor` (which may be a
    /// dynamic system color whose rendered RGB depends on the current
    /// `NSAppearance`). Resolves the color to sRGB-space components
    /// and picks `.black` for fills with luminance > 0.5, otherwise
    /// `.white`.
    ///
    /// Used by renderers that paint over a theme-derived color
    /// (`theme.accent.nsColor`, `theme.buttonHilite.nsColor`, …).
    /// Driving the text-color choice off the actual rendered color
    /// keeps labels readable whether the theme picked `#FF8C42`
    /// (Sunset orange — needs dark text) or `#0A84FF` (Liquid Glass
    /// blue — needs light text).
    static func readableTextColor(for nsColor: NSColor) -> NSColor {
        // Try the sRGB-resolved values; system colors only resolve
        // when there's an active appearance, but renderers are
        // always running inside a CGContext that has one.
        let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let r = Double(srgb.redComponent)
        let g = Double(srgb.greenComponent)
        let b = Double(srgb.blueComponent)
        let lum = relativeLuminance(r: r, g: g, b: b)
        return lum > 0.5 ? NSColor.black : NSColor.white
    }
}
#endif

import Testing
import Foundation
@testable import HypeCore

/// Audits every built-in theme's text-on-background pairs against
/// WCAG AA (4.5:1 for normal text). Any failing pair becomes a
/// hard failure here so future theme tweaks can't silently regress
/// readability. Both for the visible card surfaces and the script
/// editor's syntax palette.
@Suite("Built-in themes meet WCAG AA contrast on every text-on-background pair")
struct ThemeContrastAuditTests {

    private static let aa: Double = 4.5

    /// Helpers — extract hex pair, return nil for system-key colors
    /// (they honor macOS appearance dynamically and aren't checked
    /// here).
    private static func hexPair(fg: ColorRef, bg: ColorRef)
        -> (String, String)?
    {
        guard case .hex(let f) = fg, case .hex(let b) = bg else { return nil }
        return (f, b)
    }

    private static func ratio(fg: ColorRef, bg: ColorRef) -> Double? {
        guard let (f, b) = hexPair(fg: fg, bg: bg),
              let fp = ColorContrast.parseHex(f),
              let bp = ColorContrast.parseHex(b)
        else { return nil }
        return ColorContrast.contrastRatio(fp, bp)
    }

    /// All the (label, foreground, background) text-bearing pairs a
    /// theme must satisfy for normal-weight text to be readable.
    /// Some pairs (lineNumber, bracket) we relax to 3:1 since they
    /// render at smaller weight in the gutter and on punctuation.
    private static func textPairs(theme: HypeTheme)
        -> [(label: String, fg: ColorRef, bg: ColorRef, minRatio: Double)]
    {
        let aa = ThemeContrastAuditTests.aa
        let aaLarge = 3.0  // for gutter / punctuation
        return [
            ("cardForeground / cardBackground",       theme.cardForeground,     theme.cardBackground,     aa),
            ("buttonForeground / buttonBackground",   theme.buttonForeground,   theme.buttonBackground,   aa),
            ("fieldForeground / fieldBackground",     theme.fieldForeground,    theme.fieldBackground,    aa),
            ("shapeStroke / shapeFill",               theme.shapeStrokeDefault, theme.shapeFillDefault,   aa),
            ("scriptTheme.foreground / .background",  theme.scriptTheme.foreground,    theme.scriptTheme.background, aa),
            ("scriptTheme.keyword / .background",     theme.scriptTheme.keyword,       theme.scriptTheme.background, aa),
            ("scriptTheme.command / .background",     theme.scriptTheme.command,       theme.scriptTheme.background, aa),
            ("scriptTheme.string / .background",      theme.scriptTheme.stringLiteral, theme.scriptTheme.background, aa),
            ("scriptTheme.number / .background",      theme.scriptTheme.numberLiteral, theme.scriptTheme.background, aa),
            ("scriptTheme.comment / .background",     theme.scriptTheme.comment,       theme.scriptTheme.background, aa),
            ("scriptTheme.identifier / .background",  theme.scriptTheme.identifier,    theme.scriptTheme.background, aa),
            ("scriptTheme.property / .background",    theme.scriptTheme.property,      theme.scriptTheme.background, aa),
            ("scriptTheme.bracket / .background",     theme.scriptTheme.bracket,       theme.scriptTheme.background, aaLarge),
            ("scriptTheme.lineNumber / .background",  theme.scriptTheme.lineNumber,    theme.scriptTheme.background, aaLarge),
        ]
    }

    @Test("Built-in themes pass WCAG AA on every text/background pair",
          arguments: BuiltInThemes.all)
    func themesPassAA(theme: HypeTheme) {
        for pair in Self.textPairs(theme: theme) {
            guard let r = Self.ratio(fg: pair.fg, bg: pair.bg) else { continue }
            #expect(r >= pair.minRatio,
                    "[\(theme.name)] \(pair.label) ratio = \(String(format: "%.2f", r)) (need \(pair.minRatio))")
        }
    }

    @Test("ColorRef.ensuringContrast reaches the requested ratio on a low-contrast pair")
    func ensuringContrastBumpsRatio() {
        // Light beige bg, tan foreground — fails AA badly.
        let bg = "#FFF7EC"
        let fgIn = ColorRef.hex("#9A7A5E")
        let adjusted = fgIn.ensuringContrast(against: bg, minRatio: 4.5)
        guard case .hex(let h) = adjusted else {
            Issue.record("expected .hex result, got \(adjusted)")
            return
        }
        guard let fp = ColorContrast.parseHex(h),
              let bp = ColorContrast.parseHex(bg)
        else {
            Issue.record("failed to parse adjusted/background hex")
            return
        }
        let r = ColorContrast.contrastRatio(fp, bp)
        #expect(r >= 4.5, "after ensuringContrast, ratio = \(r) (was failing)")
    }

    @Test("ColorRef.ensuringContrast leaves already-passing colors alone")
    func ensuringContrastIsIdempotent() {
        // Black on white, definitely passing.
        let fg = ColorRef.hex("#000000")
        let result = fg.ensuringContrast(against: "#FFFFFF", minRatio: 4.5)
        #expect(result == fg)
    }

    @Test("ColorRef.ensuringContrast preserves systemKey unchanged")
    func ensuringContrastPreservesSystemKey() {
        let fg = ColorRef.systemKey("textColor")
        let result = fg.ensuringContrast(against: "#FFFFFF", minRatio: 4.5)
        #expect(result == fg)
    }

    @Test("ContrastRatio matches well-known reference values within 1%")
    func contrastRatioReferenceValues() {
        // Black on white → 21:1 exactly per spec.
        let black = ColorContrast.parseHex("#000000")!
        let white = ColorContrast.parseHex("#FFFFFF")!
        #expect(abs(ColorContrast.contrastRatio(black, white) - 21.0) < 0.01)

        // #767676 ("dim gray") on white → ~4.54:1 — the canonical
        // WCAG AA boundary case.
        let dim = ColorContrast.parseHex("#767676")!
        let r = ColorContrast.contrastRatio(dim, white)
        #expect(r >= 4.5 && r < 4.6,
                "expected ~4.54 at the AA boundary, got \(r)")
    }
}

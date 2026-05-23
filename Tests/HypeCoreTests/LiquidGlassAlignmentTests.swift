import Foundation
import Testing
@testable import HypeCore
#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Regression tests pinning the alignment between Hype's Liquid Glass
/// theme and Apple's macOS 26 Tahoe / iOS 26 Liquid Glass spec.
///
/// Each test cites the specific Apple HIG or WWDC25 rule it enforces
/// so a future change that drops one of these invariants is easy to
/// diagnose.
@Suite("Liquid Glass theme — Apple HIG alignment")
struct LiquidGlassAlignmentTests {

    // MARK: - Identity + opt-in

    @Test("Liquid Glass theme opts into the glass material flag")
    func glassThemeOptsIn() {
        #expect(BuiltInThemes.liquidGlass.usesGlassMaterial == true)
    }

    @Test("non-glass themes do NOT opt into glass material")
    func nonGlassThemesAreFlat() {
        #expect(BuiltInThemes.system.usesGlassMaterial == false)
        #expect(BuiltInThemes.classicHyperCard.usesGlassMaterial == false)
        #expect(BuiltInThemes.modernLight.usesGlassMaterial == false)
        #expect(BuiltInThemes.modernDark.usesGlassMaterial == false)
        #expect(BuiltInThemes.sunset.usesGlassMaterial == false)
        #expect(BuiltInThemes.neon.usesGlassMaterial == false)
    }

    // MARK: - Apple HIG spec invariants

    @Test("accent + hilite + selection stroke all bind to the system accent color")
    func accentsFlowFromSystem() {
        // Apple's Liquid Glass picks up the user-chosen accent (System
        // Settings → Appearance → Accent color). Hardcoding a single
        // hex would force every user to "Apple Blue" regardless.
        // ColorRef wraps the systemKey raw form as "system:<key>".
        let glass = BuiltInThemes.liquidGlass
        #expect(glass.accent.rawDescription == "system:controlAccentColor",
                "accent must flow from controlAccentColor (Apple HIG: Liquid Glass adopts the system tint)")
        #expect(glass.buttonHilite.rawDescription == "system:controlAccentColor",
                "buttonHilite must flow from controlAccentColor so CTAs match the system accent")
        #expect(glass.selectionStroke.rawDescription == "system:controlAccentColor",
                "selection stroke must follow the system accent")
    }

    @Test("cornerRadiusLarge matches Apple's 16pt rounded-rect standard")
    func cornerRadiusLargeMatchesAppleStandard() {
        // Apple's Liquid Glass standard for non-capsule rounded
        // controls is 16pt (cited in the macOS 26 Tahoe HIG +
        // GlassEffectContainer reference). Our previous value of 18pt
        // was close but off-spec.
        #expect(BuiltInThemes.liquidGlass.cornerRadiusLarge == 16,
                "cornerRadiusLarge must be 16pt per Apple's macOS 26 rounded-rect spec")
    }

    @Test("hairline border + thin stroke for refractive-edge aesthetic")
    func hairlineStrokesPreserved() {
        // Liquid Glass relies on hairline strokes (0.5pt) for the
        // refractive-edge look. A 1pt+ default stroke would read as
        // a hard outline and break the bevel illusion.
        #expect(BuiltInThemes.liquidGlass.strokeWidthThin == 0.5)
    }

    @Test("shadow opacity is gentle so part reads as floating, not heavy")
    func shadowIsGentle() {
        // Apple's Liquid Glass uses subtle drop shadows for the
        // "floating above content" cue. > 0.25 reads as heavy
        // material design / pre-Tahoe macOS.
        #expect(BuiltInThemes.liquidGlass.shadowOpacity <= 0.25)
    }

    // MARK: - Accessibility helper invariants

    /// `LiquidGlassEnvironment` is the single source of truth for the
    /// three accessibility flags that Liquid Glass must honor. The
    /// values are read-only proxies for NSWorkspace; this test just
    /// confirms the API surface exists and returns Bools (not Optional).
    @Test("LiquidGlassEnvironment exposes the three Apple-required accessibility flags")
    func environmentExposesAccessibilityFlags() {
        // Each property must compile + return Bool (the real value
        // depends on the test machine's accessibility settings).
        let _: Bool = LiquidGlassEnvironment.reduceTransparency
        let _: Bool = LiquidGlassEnvironment.increaseContrast
        let _: Bool = LiquidGlassEnvironment.reduceMotion
    }

    // MARK: - GlassRenderer contract

    /// Smoke test that `GlassRenderer.fillRoundedRect` runs without
    /// crashing for the standard input shape. Doesn't assert pixels —
    /// AppKit CG rendering is hard to compare deterministically — but
    /// catches the case where someone breaks the helper outright.
    #if canImport(AppKit)
    @MainActor
    @Test("GlassRenderer.fillRoundedRect draws without throwing")
    func glassRendererDrawsCleanly() {
        let size = CGSize(width: 200, height: 80)
        let pixelWidth = Int(size.width * 2)
        let pixelHeight = Int(size.height * 2)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = pixelWidth * 4
        let dataPtr: UnsafeMutableRawPointer? = nil
        guard let ctx = CGContext(
            data: dataPtr,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                       | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            Issue.record("Failed to create CGContext for the smoke test")
            return
        }
        ctx.scaleBy(x: 2, y: 2)

        GlassRenderer.fillRoundedRect(
            ctx: ctx,
            rect: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4),
            fillHex: "#FFFFFF80",   // 50% white — typical glass fill
            cornerRadius: 16,        // Apple standard
            strokeHex: "#0000001A"   // 10% black hairline
        )

        // Survived all branches — including the new
        // increaseContrast / reduceTransparency paths even when
        // those flags are false on this machine. A trap would
        // have crashed the test.
        #expect(ctx.makeImage() != nil, "context produced a valid CGImage")
    }
    #endif

    @Test("shouldUseGlass returns true for the Liquid Glass theme and false for the rest")
    func shouldUseGlassMatchesFlag() {
        #expect(GlassRenderer.shouldUseGlass(for: BuiltInThemes.liquidGlass))
        #expect(!GlassRenderer.shouldUseGlass(for: BuiltInThemes.system))
        #expect(!GlassRenderer.shouldUseGlass(for: nil))
    }
}

import Testing
import Foundation
import CoreGraphics
@testable import HypeCore
#if canImport(AppKit)
import AppKit
#endif

// Regression tests that degenerate part geometry (zero/negative/NaN
// width or height, oversized corner radius) never crashes the app.
//
// The tests run through the real renderer entry points via the same
// bitmap-context harness used in ControlCleanupTests.  Completing a
// test without a crash IS the primary assertion; a trivial #expect(true)
// follows each smoke call to make the intent explicit.

@Suite("Renderer — degenerate geometry can't crash the app")
struct RendererDegenerateGeometryTests {

    // ── RenderGeometry unit tests ─────────────────────────────────────

    @Test("RenderGeometry.safeRect: NaN components produce a zero rect")
    func safeRectNaN() {
        let nan = CGFloat.nan
        let safe = RenderGeometry.safeRect(CGRect(x: nan, y: nan, width: nan, height: nan))
        #expect(safe.origin.x.isFinite, "origin.x should be finite")
        #expect(safe.origin.y.isFinite, "origin.y should be finite")
        #expect(safe.width.isFinite,    "width should be finite")
        #expect(safe.height.isFinite,   "height should be finite")
        #expect(safe.width  >= 0, "width should be non-negative")
        #expect(safe.height >= 0, "height should be non-negative")
    }

    @Test("RenderGeometry.safeRect: negative size is standardized to non-negative")
    func safeRectNegativeSize() {
        // A rect with negative width: origin shifts left but size is non-negative.
        let r = CGRect(x: 10, y: 10, width: -20, height: -30)
        let safe = RenderGeometry.safeRect(r)
        #expect(safe.width  >= 0)
        #expect(safe.height >= 0)
    }

    @Test("RenderGeometry.safeRect: already-canonical rect is unchanged")
    func safeRectPassthrough() {
        let r = CGRect(x: 5, y: 5, width: 100, height: 50)
        let safe = RenderGeometry.safeRect(r)
        #expect(safe == r)
    }

    @Test("RenderGeometry.roundedRectPath: huge corner on 10×10 rect is clamped to 5")
    func roundedRectPathCornerClamped() {
        let path = RenderGeometry.roundedRectPath(in: CGRect(x: 0, y: 0, width: 10, height: 10),
                                                  cornerRadius: 9999)
        // Path bounding box matches the input rect (no expansion from oversized corner).
        let bb = path.boundingBox
        #expect(abs(bb.width  - 10) < 0.5, "bounding width should be ~10; got \(bb.width)")
        #expect(abs(bb.height - 10) < 0.5, "bounding height should be ~10; got \(bb.height)")
    }

    @Test("RenderGeometry.roundedRectPath: NaN corner produces a valid path")
    func roundedRectPathNaNCorner() {
        // Must not trap; result is a valid (finite bounding-box) path.
        let path = RenderGeometry.roundedRectPath(in: CGRect(x: 0, y: 0, width: 20, height: 20),
                                                  cornerRadius: CGFloat.nan)
        let bb = path.boundingBox
        #expect(bb.width.isFinite,  "bounding width should be finite")
        #expect(bb.height.isFinite, "bounding height should be finite")
    }

    @Test("RenderGeometry.roundedRectPath: zero-size rect yields rect path not rounded-rect")
    func roundedRectPathEmptyRect() {
        // Zero-size: CGPath(roundedRect:) is undefined; helper returns a plain rect path.
        let path = RenderGeometry.roundedRectPath(in: CGRect(x: 5, y: 5, width: 0, height: 0),
                                                  cornerRadius: 10)
        let bb = path.boundingBox
        // Bounding box of a degenerate rect path is itself; the important
        // thing is that it's finite and no trap occurred.
        #expect(bb.width.isFinite)
        #expect(bb.height.isFinite)
    }

    @Test("RenderGeometry.roundedRectPath: NaN size input produces a valid finite path")
    func roundedRectPathNaNSize() {
        let path = RenderGeometry.roundedRectPath(
            in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: CGFloat.nan),
            cornerRadius: 6
        )
        let bb = path.boundingBox
        #expect(bb.width.isFinite)
        #expect(bb.height.isFinite)
    }

    // ── Renderer smoke matrix ─────────────────────────────────────────
    //
    // Each test renders through the real renderer with a degenerate
    // part rect.  Not crashing is the assertion.

    #if canImport(AppKit)

    // MARK: Button styles

    @MainActor
    @Test("ButtonRenderer: width=5/height=4 does not crash for default style")
    func buttonDefaultTinyRect() {
        renderButton(style: .default, size: NSSize(width: 5, height: 4))
        #expect(true)
    }

    @MainActor
    @Test("ButtonRenderer: width=0/height=0 does not crash for default style")
    func buttonDefaultZeroRect() {
        renderButton(style: .default, size: NSSize(width: 0, height: 0))
        #expect(true)
    }

    @MainActor
    @Test("ButtonRenderer: width=-10/height=-10 does not crash for default style")
    func buttonDefaultNegativeRect() {
        renderButton(style: .default, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    @MainActor
    @Test("ButtonRenderer: cornerRadius=9999 on width=3 does not crash for roundRect style")
    func buttonRoundRectOversizedCorner() {
        var part = Part(partType: .button, name: "B")
        part.buttonStyle = .roundRect
        part.cornerRadius = 9999
        renderPartSize(part, size: NSSize(width: 3, height: 20))
        #expect(true)
    }

    @MainActor
    @Test("ButtonRenderer: NaN width does not crash for roundRect style")
    func buttonRoundRectNaNWidth() {
        renderButton(style: .roundRect, size: NSSize(width: CGFloat.nan, height: 20))
        #expect(true)
    }

    @MainActor
    @Test("ButtonRenderer: width=5/height=4 does not crash for popup style")
    func buttonPopupTinyRect() {
        renderButton(style: .popup, size: NSSize(width: 5, height: 4))
        #expect(true)
    }

    @MainActor
    @Test("ButtonRenderer: width=0/height=0 does not crash for checkBox style")
    func buttonCheckboxZeroRect() {
        renderButton(style: .checkBox, size: NSSize(width: 0, height: 0))
        #expect(true)
    }

    @MainActor
    @Test("ButtonRenderer: width=-10/height=-10 does not crash for toggle style")
    func buttonToggleNegativeRect() {
        renderButton(style: .toggle, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    // MARK: Field styles

    @MainActor
    @Test("FieldRenderer: width=5/height=4 does not crash for rectangle style")
    func fieldRectangleTiny() {
        renderField(style: .rectangle, size: NSSize(width: 5, height: 4))
        #expect(true)
    }

    @MainActor
    @Test("FieldRenderer: width=0/height=0 does not crash for rectangle style")
    func fieldRectangleZero() {
        renderField(style: .rectangle, size: NSSize(width: 0, height: 0))
        #expect(true)
    }

    @MainActor
    @Test("FieldRenderer: width=-10/height=-10 does not crash for scrolling style")
    func fieldScrollingNegative() {
        renderField(style: .scrolling, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    @MainActor
    @Test("FieldRenderer: width=3 does not crash for search style (width < pill radius)")
    func fieldSearchNarrow() {
        renderField(style: .search, size: NSSize(width: 3, height: 20))
        #expect(true)
    }

    @MainActor
    @Test("FieldRenderer: NaN size does not crash for search style")
    func fieldSearchNaN() {
        renderField(style: .search, size: NSSize(width: CGFloat.nan, height: CGFloat.nan))
        #expect(true)
    }

    // MARK: Shape

    @MainActor
    @Test("ShapeRenderer: cornerRadius=9999 on width=10/height=10 does not crash")
    func shapeRoundRectOversizedCorner() {
        var part = Part(partType: .shape, name: "S")
        part.shapeType = .roundRect
        part.cornerRadius = 9999
        renderPartSize(part, size: NSSize(width: 10, height: 10))
        #expect(true)
    }

    @MainActor
    @Test("ShapeRenderer: width=0/height=0 does not crash for roundRect")
    func shapeRoundRectZero() {
        var part = Part(partType: .shape, name: "S")
        part.shapeType = .roundRect
        part.cornerRadius = 8
        renderPartSize(part, size: NSSize(width: 0, height: 0))
        #expect(true)
    }

    @MainActor
    @Test("ShapeRenderer: width=-10/height=-10 does not crash for roundRect")
    func shapeRoundRectNegative() {
        var part = Part(partType: .shape, name: "S")
        part.shapeType = .roundRect
        part.cornerRadius = 8
        renderPartSize(part, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    @MainActor
    @Test("ShapeRenderer: NaN size does not crash for roundRect")
    func shapeRoundRectNaN() {
        var part = Part(partType: .shape, name: "S")
        part.shapeType = .roundRect
        part.cornerRadius = 8
        renderPartSize(part, size: NSSize(width: CGFloat.nan, height: CGFloat.nan))
        #expect(true)
    }

    // MARK: Gauge

    @MainActor
    @Test("GaugeRenderer: width=5/height=4 does not crash (linear)")
    func gaugeTinyRect() {
        let part = Part(partType: .gauge, name: "g")
        renderPartSize(part, size: NSSize(width: 5, height: 4))
        #expect(true)
    }

    @MainActor
    @Test("GaugeRenderer: width=0/height=0 does not crash")
    func gaugeZeroRect() {
        let part = Part(partType: .gauge, name: "g")
        renderPartSize(part, size: NSSize(width: 0, height: 0))
        #expect(true)
    }

    @MainActor
    @Test("GaugeRenderer: width=-10/height=-10 does not crash")
    func gaugeNegativeRect() {
        let part = Part(partType: .gauge, name: "g")
        renderPartSize(part, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    @MainActor
    @Test("GaugeRenderer: NaN size does not crash")
    func gaugeNaNRect() {
        let part = Part(partType: .gauge, name: "g")
        renderPartSize(part, size: NSSize(width: CGFloat.nan, height: CGFloat.nan))
        #expect(true)
    }

    @MainActor
    @Test("GaugeRenderer: circular style with tiny rect does not crash")
    func gaugeCircularTiny() {
        var part = Part(partType: .gauge, name: "g")
        part.gaugeStyle = "circular"
        renderPartSize(part, size: NSSize(width: 5, height: 5))
        #expect(true)
    }

    // MARK: ProgressView

    @MainActor
    @Test("ProgressViewRenderer: width=5/height=4 does not crash (linear)")
    func progressViewTinyRect() {
        let part = Part(partType: .progressView, name: "p")
        renderPartSize(part, size: NSSize(width: 5, height: 4))
        #expect(true)
    }

    @MainActor
    @Test("ProgressViewRenderer: width=0/height=0 does not crash")
    func progressViewZeroRect() {
        let part = Part(partType: .progressView, name: "p")
        renderPartSize(part, size: NSSize(width: 0, height: 0))
        #expect(true)
    }

    @MainActor
    @Test("ProgressViewRenderer: width=-10/height=-10 does not crash")
    func progressViewNegativeRect() {
        let part = Part(partType: .progressView, name: "p")
        renderPartSize(part, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    @MainActor
    @Test("ProgressViewRenderer: NaN size does not crash")
    func progressViewNaNRect() {
        let part = Part(partType: .progressView, name: "p")
        renderPartSize(part, size: NSSize(width: CGFloat.nan, height: CGFloat.nan))
        #expect(true)
    }

    @MainActor
    @Test("ProgressViewRenderer: circular style with tiny rect does not crash")
    func progressViewCircularTiny() {
        var part = Part(partType: .progressView, name: "p")
        part.progressIsCircular = true
        renderPartSize(part, size: NSSize(width: 5, height: 5))
        #expect(true)
    }

    // MARK: Calendar

    @MainActor
    @Test("CalendarRenderer: width=5/height=4 does not crash")
    func calendarTinyRect() {
        let part = Part(partType: .calendar, name: "cal")
        renderPartSize(part, size: NSSize(width: 5, height: 4))
        #expect(true)
    }

    @MainActor
    @Test("CalendarRenderer: width=0/height=0 does not crash")
    func calendarZeroRect() {
        let part = Part(partType: .calendar, name: "cal")
        renderPartSize(part, size: NSSize(width: 0, height: 0))
        #expect(true)
    }

    @MainActor
    @Test("CalendarRenderer: width=-10/height=-10 does not crash")
    func calendarNegativeRect() {
        let part = Part(partType: .calendar, name: "cal")
        renderPartSize(part, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    @MainActor
    @Test("CalendarRenderer: NaN size does not crash")
    func calendarNaNRect() {
        let part = Part(partType: .calendar, name: "cal")
        renderPartSize(part, size: NSSize(width: CGFloat.nan, height: CGFloat.nan))
        #expect(true)
    }

    // MARK: MusicControlsRenderer (music player + piano keyboard)

    @MainActor
    @Test("MusicControlsRenderer: musicPlayer width=5/height=4 does not crash")
    func musicPlayerTinyRect() {
        let part = Part(partType: .musicPlayer, name: "m")
        renderPartSize(part, size: NSSize(width: 5, height: 4))
        #expect(true)
    }

    @MainActor
    @Test("MusicControlsRenderer: musicPlayer width=0/height=0 does not crash")
    func musicPlayerZeroRect() {
        let part = Part(partType: .musicPlayer, name: "m")
        renderPartSize(part, size: NSSize(width: 0, height: 0))
        #expect(true)
    }

    @MainActor
    @Test("MusicControlsRenderer: musicPlayer width=-10/height=-10 does not crash")
    func musicPlayerNegativeRect() {
        let part = Part(partType: .musicPlayer, name: "m")
        renderPartSize(part, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    @MainActor
    @Test("MusicControlsRenderer: musicPlayer NaN size does not crash")
    func musicPlayerNaNRect() {
        let part = Part(partType: .musicPlayer, name: "m")
        renderPartSize(part, size: NSSize(width: CGFloat.nan, height: CGFloat.nan))
        #expect(true)
    }

    @MainActor
    @Test("MusicControlsRenderer: pianoKeyboard width=5/height=4 does not crash")
    func pianoKeyboardTinyRect() {
        let part = Part(partType: .pianoKeyboard, name: "k")
        renderPartSize(part, size: NSSize(width: 5, height: 4))
        #expect(true)
    }

    @MainActor
    @Test("MusicControlsRenderer: pianoKeyboard width=-10/height=-10 does not crash")
    func pianoKeyboardNegativeRect() {
        let part = Part(partType: .pianoKeyboard, name: "k")
        renderPartSize(part, size: NSSize(width: -10, height: -10))
        #expect(true)
    }

    // MARK: Glass path (GlassRenderer)

    @MainActor
    @Test("GlassRenderer: button with Liquid Glass theme and width=5/height=4 does not crash")
    func glassButtonTinyRect() {
        var part = Part(partType: .button, name: "G")
        part.buttonStyle = .default
        renderPartSizeTheme(part, size: NSSize(width: 5, height: 4), theme: BuiltInThemes.liquidGlass)
        #expect(true)
    }

    @MainActor
    @Test("GlassRenderer: button with Liquid Glass theme and width=0/height=0 does not crash")
    func glassButtonZeroRect() {
        var part = Part(partType: .button, name: "G")
        part.buttonStyle = .default
        renderPartSizeTheme(part, size: NSSize(width: 0, height: 0), theme: BuiltInThemes.liquidGlass)
        #expect(true)
    }

    @MainActor
    @Test("GlassRenderer: button with Liquid Glass theme and NaN size does not crash")
    func glassButtonNaNRect() {
        var part = Part(partType: .button, name: "G")
        part.buttonStyle = .default
        renderPartSizeTheme(part, size: NSSize(width: CGFloat.nan, height: CGFloat.nan), theme: BuiltInThemes.liquidGlass)
        #expect(true)
    }

    @MainActor
    @Test("GlassRenderer: rectangle field with Liquid Glass theme and width=5/height=4 does not crash")
    func glassFieldTinyRect() {
        var part = Part(partType: .field, name: "GF")
        part.fieldStyle = .rectangle
        renderPartSizeTheme(part, size: NSSize(width: 5, height: 4), theme: BuiltInThemes.liquidGlass)
        #expect(true)
    }

    #endif
}

// MARK: - Rendering helpers (AppKit only)

#if canImport(AppKit)

/// Render a button part with the given style using a part rect inset by 4pt.
@MainActor
private func renderButton(style: ButtonStyle, size: NSSize) {
    var part = Part(partType: .button, name: "B")
    part.buttonStyle = style
    renderPartSize(part, size: size)
}

/// Render a field part with the given style using a part rect inset by 4pt.
@MainActor
private func renderField(style: FieldStyle, size: NSSize) {
    var part = Part(partType: .field, name: "F")
    part.fieldStyle = style
    renderPartSize(part, size: size)
}

/// Render any part through `CardRenderer.drawPart` (or directly via the
/// per-renderer path) into a throwaway bitmap context.  The part rect is
/// the full size rect (no inset); this mirrors what CardRenderer passes.
@MainActor
private func renderPartSize(_ part: Part, size: NSSize) {
    renderPartSizeTheme(part, size: size, theme: nil)
}

@MainActor
private func renderPartSizeTheme(_ part: Part, size: NSSize, theme: HypeTheme?) {
    let w = max(1, Int(abs(size.width.isFinite ? size.width : 1)))
    let h = max(1, Int(abs(size.height.isFinite ? size.height : 1)))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w,
        pixelsHigh: h,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let gfx = NSGraphicsContext(bitmapImageRep: rep) else { return }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = gfx
    let ctx = gfx.cgContext

    // Match CardRenderer's flip so renderers see a top-left origin.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)

    // Use the actual (possibly degenerate) rect as-is — that is what
    // the real CardRenderer passes when script geometry is extreme.
    let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)

    switch part.partType {
    case .button:
        ButtonRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
    case .field:
        FieldRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
    case .shape:
        ShapeRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
    case .gauge:
        GaugeRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
    case .progressView:
        ProgressViewRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
    case .calendar:
        CalendarRenderer.draw(ctx: ctx, part: part, rect: rect)
    case .musicPlayer, .pianoKeyboard, .stepSequencer, .musicMixer, .appleMusicBrowser, .musicQueue:
        MusicControlsRenderer.draw(part.partType, ctx: ctx, part: part, rect: rect, theme: theme)
    default:
        break
    }
}

#endif

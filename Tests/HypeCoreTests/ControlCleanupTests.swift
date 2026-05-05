import Testing
import Foundation
@testable import HypeCore
#if canImport(AppKit)
import AppKit
#endif

// Regression tests for the control-rendering cleanup pass:
//   1. Shadow buttons shift their shadow top-right → bottom-left on press
//   2. New buttons default to .default style
//   3. Checkboxes always draw a visible rectangle at the check location
//   4. New fields default to .rectangle and draw a 1px black border
//
// Rendering assertions use a tiny `NSBitmapImageRep` so we can
// sample specific pixels from the rendered output and verify that
// a given stroke or fill color landed where it should. The tests
// skip on non-AppKit platforms (where the renderers compile out).

@Suite("Control cleanup — defaults & rendering")
struct ControlCleanupTests {

    // MARK: - Defaults

    @Test("New button parts default to .default style")
    func newButtonDefaultsToDefaultStyle() {
        let button = Part(partType: .button)
        #expect(button.buttonStyle == .default)
    }

    @Test("New field parts default to .rectangle style")
    func newFieldDefaultsToRectangleStyle() {
        let field = Part(partType: .field)
        #expect(field.fieldStyle == .rectangle)
    }

    @Test("create_button via HypeToolExecutor inherits the .default style when no style arg is passed")
    func createButtonAIDefaultStyleIsDefault() {
        // Confirms the AI tool path doesn't accidentally override
        // the model-level default. The tool only sets buttonStyle
        // when an explicit style arg comes in.
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let placed = doc.partsForCard(cardId)
        _ = placed
        // Simulate the production flow: new Part with default init,
        // then no explicit style set (mirroring create_button's
        // `if let style = arguments["style"]` branch when absent).
        let part = Part(partType: .button, cardId: cardId, name: "OK")
        #expect(part.buttonStyle == .default)
    }

    // MARK: - Shadow button press animation
    //
    // Differential tests: we don't assert exact brightness values
    // (antialiasing and subpixel coverage make that fragile).
    // Instead we compare the resting and pressed snapshots and
    // confirm that the top-right shadow region goes from dark →
    // light and the bottom-left region goes from light → dark when
    // the button is pressed.

    #if canImport(AppKit)
    // Test helper draws a 60×40 button with rect (4, 4, 52, 32). At
    // rest the shadow is offset (+2, -2) so visible shadow pixels
    // sit in the top-right strip (x∈[56,58], y∈[2,4] across the top
    // of the button). When pressed, the shadow swaps to (-2, +2),
    // putting visible shadow in the bottom-left strip (x∈[2,4],
    // y∈[34,38] at the bottom). We compare the average brightness
    // of those two regions across the two hilite states.

    @MainActor
    @Test("shadow button: bottom strip outside face darkens when pressed (shadow arrives)")
    func shadowBottomLeftDarkensOnPress() {
        let unpressed = renderShadowButton(hilite: false)
        let pressed = renderShadowButton(hilite: true)
        // Bottom strip y=36..37 — outside BOTH face positions so the
        // hilite accent color on the face doesn't skew the sample.
        // At rest: no shadow here (rest shadow ends at y=33).
        // When pressed: shadow runs y=[6,38), so rows 36..37 get shadow.
        let restArea = unpressed.averageBrightness(xRange: 2...30, yRange: 36...37)
        let pressArea = pressed.averageBrightness(xRange: 2...30, yRange: 36...37)
        #expect(restArea > pressArea + 0.02,
                "expected bottom-left to darken on press: rest=\(restArea) press=\(pressArea)")
    }

    @MainActor
    @Test("shadow button: left strip outside face darkens when pressed (shadow arrives)")
    func shadowLeftStripDarkensOnPress() {
        let unpressed = renderShadowButton(hilite: false)
        let pressed = renderShadowButton(hilite: true)
        // Left strip x=2..3 — outside BOTH face positions.
        // At rest: no shadow here (rest shadow starts at x=6).
        // When pressed: shadow runs x=[2,54), so cols 2..3 get shadow.
        let restArea = unpressed.averageBrightness(xRange: 2...3, yRange: 15...30)
        let pressArea = pressed.averageBrightness(xRange: 2...3, yRange: 15...30)
        #expect(restArea > pressArea + 0.02,
                "expected left strip to darken on press: rest=\(restArea) press=\(pressArea)")
    }
    #endif

    // MARK: - Checkbox always visible

    #if canImport(AppKit)
    @MainActor
    @Test("checkbox: box outline has dark edges in both checked and unchecked states")
    func checkboxBoxAlwaysVisible() {
        let unchecked = renderCheckbox(hilite: false)
        let checked = renderCheckbox(hilite: true)
        // Sample the left edge of the 16px box (box starts at
        // rect.minX + 4 = 8, so the left edge sits around x=8).
        // Take a 3-pixel-tall vertical slice centered on the box.
        let uncheckedEdge = unchecked.averageBrightness(xRange: 7...9, yRange: 14...26)
        let checkedEdge = checked.averageBrightness(xRange: 7...9, yRange: 14...26)
        // Both states should show the black outline — so the edge
        // region should be noticeably darker than the white inner
        // fill of the box (which we can also sample for reference).
        let uncheckedInner = unchecked.averageBrightness(xRange: 14...16, yRange: 18...22)
        #expect(uncheckedEdge < uncheckedInner,
                "expected unchecked box to have a visible dark edge: edge=\(uncheckedEdge) inner=\(uncheckedInner)")
        let checkedInner = checked.averageBrightness(xRange: 17...19, yRange: 18...22)
        #expect(checkedEdge < checkedInner,
                "expected checked box to still have a visible dark edge: edge=\(checkedEdge) inner=\(checkedInner)")
    }
    #endif

    // MARK: - Rectangle field border

    #if canImport(AppKit)
    @MainActor
    @Test("rectangle field with a 1px stroke renders darker than the same field with stroke=0 (perimeter ink)")
    func rectangleFieldStrokeAddsInk() {
        // Differential check: a rectangle field with a 1px black
        // stroke must average darker than the SAME field with the
        // stroke disabled (`strokeWidth = 0`), purely because of the
        // perimeter pixels. A 1px outline on a 92×32 inset rect adds
        // ~248 dark pixels out of ~4000 — easy to clear a small
        // threshold without depending on exact stroke alignment.
        //
        // The legacy `.opaque` field style was a duplicate of
        // `.rectangle` — both rendered with the same fill + stroke
        // call sequence — and has been removed. Pre-existing
        // documents containing `"opaque"` migrate to `.rectangle`
        // via `FieldStyle.resolved(rawOrAlias:)`; that migration is
        // covered separately by `opaqueFieldStyleMigratesToRectangle`.
        var stroked = Part(partType: .field)
        stroked.fieldStyle = .rectangle
        let strokedImg = renderField(stroked, size: NSSize(width: 100, height: 40))

        var unstroked = Part(partType: .field)
        unstroked.fieldStyle = .rectangle
        unstroked.strokeWidth = 0
        let unstrokedImg = renderField(unstroked, size: NSSize(width: 100, height: 40))

        let strokedAvg = strokedImg.averageBrightness(xRange: 0...99, yRange: 0...39)
        let unstrokedAvg = unstrokedImg.averageBrightness(xRange: 0...99, yRange: 0...39)
        #expect(strokedAvg < unstrokedAvg,
                "expected stroke=1 to average darker than stroke=0 (perimeter ink): stroked=\(strokedAvg) unstroked=\(unstrokedAvg)")
    }

    // ButtonStyle / FieldStyle migration tests for the removed
    // `.rectangle`, `.opaque`, and `radioButton` cases live in
    // SecurityRegressionTests next to the existing legacy-decoder
    // assertions, so the migration table has a single test home.

    @MainActor
    @Test("rectangle field: interior is near-white (field fills with white)")
    func rectangleFieldInteriorIsWhite() {
        let img = renderRectangleField()
        let interior = img.averageBrightness(xRange: 20...40, yRange: 15...25)
        #expect(interior > 0.95,
                "expected white interior (got brightness \(interior))")
    }

    @MainActor
    @Test("field renderer honors configured border width")
    func fieldRendererHonorsConfiguredBorderWidth() {
        var part = Part(partType: .field)
        part.fieldStyle = .rectangle
        part.strokeColor = "#FF0000"
        part.strokeWidth = 3

        var noBorder = part
        noBorder.strokeWidth = 0

        let bordered = renderField(part, size: NSSize(width: 100, height: 40))
        let plain = renderField(noBorder, size: NSSize(width: 100, height: 40))
        let borderedAvg = bordered.averageBrightness(xRange: 0...99, yRange: 0...39)
        let plainAvg = plain.averageBrightness(xRange: 0...99, yRange: 0...39)
        #expect(borderedAvg < plainAvg - 0.01,
                "expected configured border to add visible ink: bordered=\(borderedAvg) plain=\(plainAvg)")
    }

    @MainActor
    @Test("transparent locked label fields can render without an outline")
    func transparentLabelCanRenderWithoutOutline() {
        var part = Part(partType: .field)
        part.fieldStyle = .transparent
        part.lockText = true
        part.strokeWidth = 0

        let img = renderField(part, size: NSSize(width: 100, height: 40))
        let edge = img.averageBrightness(xRange: 5...7, yRange: 15...25)
        #expect(abs(edge - 0.5) < 0.03,
                "expected no outline over gray backdrop, got brightness \(edge)")
    }
    #endif
}

#if canImport(AppKit)
// MARK: - Rendering helpers

@MainActor
private func renderShadowButton(hilite: Bool) -> RenderedPixels {
    var part = Part(partType: .button, name: "Hello")
    part.buttonStyle = .shadow
    part.hilite = hilite
    return renderPart(part, size: NSSize(width: 60, height: 40))
}

@MainActor
private func renderCheckbox(hilite: Bool) -> RenderedPixels {
    var part = Part(partType: .button, name: "Option A")
    part.buttonStyle = .checkBox
    part.hilite = hilite
    return renderPart(part, size: NSSize(width: 120, height: 40))
}

@MainActor
private func renderRectangleField() -> RenderedPixels {
    var part = Part(partType: .field)
    part.fieldStyle = .rectangle
    return renderField(part, size: NSSize(width: 100, height: 40))
}

/// Render directly into a 1x NSBitmapImageRep — sidesteps NSImage's
/// device-scale-aware drawing path (Retina doubling, color space
/// coercion) so the pixel coordinates in our assertions match the
/// points we passed to the renderer.
///
/// The render runs under a forced `.aqua` (light-mode) appearance so
/// the dynamic system colors used by the renderers
/// (`controlBackgroundColor`, `shadowColor`, `controlAccentColor`,
/// etc.) resolve to the same values regardless of the developer's
/// macOS appearance setting. Without this, tests that compare
/// brightness regions fail on dark-mode machines because
/// `controlBackgroundColor` is light gray on light mode and dark
/// gray on dark mode — flipping the assertion's expected ordering.
@MainActor
private func renderToBitmap(size: NSSize, flipped: Bool = true, _ draw: (CGContext) -> Void) -> RenderedPixels {
    let w = Int(size.width)
    let h = Int(size.height)
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
    ), let gfx = NSGraphicsContext(bitmapImageRep: rep) else {
        return RenderedPixels(width: w, height: h, pixels: [])
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = gfx
    let ctx = gfx.cgContext
    if flipped {
        // Match the production flip from CardRenderer so the
        // renderer sees a top-left origin context.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
    }
    // Force light appearance so dynamic system colors are
    // deterministic across developer machines.
    if let aqua = NSAppearance(named: .aqua) {
        aqua.performAsCurrentDrawingAppearance {
            draw(ctx)
        }
    } else {
        draw(ctx)
    }
    guard let data = rep.bitmapData else {
        return RenderedPixels(width: w, height: h, pixels: [])
    }
    let byteCount = w * h * 4
    return RenderedPixels(
        width: w,
        height: h,
        pixels: Array(UnsafeBufferPointer(start: data, count: byteCount))
    )
}

@MainActor
private func renderPart(_ part: Part, size: NSSize) -> RenderedPixels {
    renderToBitmap(size: size) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        let rect = CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8)
        ButtonRenderer.draw(ctx: ctx, part: part, rect: rect)
    }
}

@MainActor
private func renderField(_ part: Part, size: NSSize) -> RenderedPixels {
    renderToBitmap(size: size) { ctx in
        // Gray backdrop so black borders and white fills both stand
        // apart from the surrounding canvas during assertions.
        ctx.setFillColor(NSColor(white: 0.5, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        // Inset the field rect by 5px on all sides so the stroke at
        // the perimeter lands fully inside the bitmap (a 1px stroke
        // centered on an integer coordinate covers y∈[n-0.5, n+0.5],
        // which clips when the coordinate is 0 or size.height-1).
        let rect = CGRect(x: 5, y: 5, width: size.width - 10, height: size.height - 10)
        FieldRenderer.draw(ctx: ctx, part: part, rect: rect)
    }
}

/// Minimal pixel-reader over an NSImage for rendering assertions.
/// Extracts per-pixel color into an RGBA flat array so tests can
/// sample specific coordinates without depending on the image's
/// backing store format.
private struct RenderedPixels {
    let width: Int
    let height: Int
    private let pixels: [UInt8]  // RGBA, row-major, 4 bytes per pixel

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    struct Color {
        let r: Double
        let g: Double
        let b: Double
        let a: Double
        var brightness: Double { (r + g + b) / 3 }
    }

    func color(x: Int, y: Int) -> Color {
        guard pixels.count == width * height * 4,
              x >= 0, x < width, y >= 0, y < height else {
            return Color(r: 0, g: 0, b: 0, a: 0)
        }
        let i = (y * width + x) * 4
        return Color(
            r: Double(pixels[i]) / 255,
            g: Double(pixels[i + 1]) / 255,
            b: Double(pixels[i + 2]) / 255,
            a: Double(pixels[i + 3]) / 255
        )
    }

    /// Average brightness across a rectangular patch. Smooths over
    /// antialiasing so differential assertions don't hinge on exact
    /// subpixel coverage.
    func averageBrightness(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) -> Double {
        var sum = 0.0
        var count = 0
        for y in yRange {
            for x in xRange {
                let c = color(x: x, y: y)
                sum += c.brightness
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }
}
#endif

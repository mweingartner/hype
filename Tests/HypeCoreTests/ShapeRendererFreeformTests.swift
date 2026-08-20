import Testing
import Foundation
import CoreGraphics
@testable import HypeCore

#if canImport(AppKit)
import AppKit
#endif

// Turtle-graphics D8 / criterion 10 (renderer parity) + criterion 14
// (frame move → geometry moves) for the CG render site
// (`ShapeRenderer.draw` `.freeform`), plus direct unit coverage of the
// shared `RenderGeometry.freeformIsOpenStroke` /
// `RenderGeometry.freeformLocalPoints` helpers every render site goes
// through (spec.md "Freeform renderer alignment").
//
// The renderer-level assertions sample actual rendered pixels through
// the same bitmap-context harness pattern used by
// `RendererDegenerateGeometryTests`/`ControlCleanupTests` rather than
// inspecting `Path`/`CGPath` internals — an open stroke that is truly
// unfilled and a closed shape that is truly filled are both directly
// observable that way.

@Suite("RenderGeometry — freeform contract (turtle-graphics D8)")
struct RenderGeometryFreeformTests {

    // MARK: - freeformIsOpenStroke

    @Test("freeformIsOpenStroke: empty fillColor is an open stroke")
    func openStrokeWhenFillColorEmpty() {
        var part = Part(partType: .shape, name: "s")
        part.shapeType = .freeform
        part.fillColor = ""
        #expect(RenderGeometry.freeformIsOpenStroke(part))
    }

    @Test("freeformIsOpenStroke: non-empty fillColor (including legacy #FFFFFF) is closed")
    func closedWhenFillColorNonEmpty() {
        var part = Part(partType: .shape, name: "s")
        part.shapeType = .freeform
        part.fillColor = "#FFFFFF"
        #expect(!RenderGeometry.freeformIsOpenStroke(part))

        part.fillColor = "#FF0000"
        #expect(!RenderGeometry.freeformIsOpenStroke(part))
    }

    // MARK: - freeformLocalPoints

    @Test("freeformLocalPoints: anchors the tight bounding box (no stroke padding) to the origin")
    func localPointsAnchorToOriginNoPadding() {
        var part = Part(partType: .shape, name: "s")
        part.shapeType = .freeform
        part.strokeWidth = 0
        part.pathData = [
            PathPoint(x: 400, y: 300),
            PathPoint(x: 450, y: 300),
            PathPoint(x: 450, y: 350),
            PathPoint(x: 400, y: 350),
        ]
        let points = RenderGeometry.freeformLocalPoints(part)
        #expect(points.count == 4)
        #expect(points.map(\.x) == [0, 50, 50, 0])
        #expect(points.map(\.y) == [0, 0, 50, 50])
    }

    @Test("freeformLocalPoints: pads the anchor by strokeWidth/2, matching TurtleEngine's frame math")
    func localPointsPadByHalfStrokeWidth() {
        var part = Part(partType: .shape, name: "s")
        part.shapeType = .freeform
        part.strokeWidth = 10  // pad = 5 on every side
        part.pathData = [
            PathPoint(x: 400, y: 300),
            PathPoint(x: 450, y: 300),
        ]
        let points = RenderGeometry.freeformLocalPoints(part)
        #expect(points[0] == CGPoint(x: 5, y: 5))
        #expect(points[1] == CGPoint(x: 55, y: 5))
    }

    @Test("freeformLocalPoints: empty pathData returns an empty array")
    func localPointsEmptyWhenNoPathData() {
        let part = Part(partType: .shape, name: "s")
        #expect(RenderGeometry.freeformLocalPoints(part).isEmpty)
    }

    @Test("freeformLocalPoints: NaN point components and NaN strokeWidth don't propagate NaN")
    func localPointsNaNSafe() {
        var part = Part(partType: .shape, name: "s")
        part.shapeType = .freeform
        part.strokeWidth = .nan
        part.pathData = [
            PathPoint(x: .nan, y: 10),
            PathPoint(x: 20, y: .nan),
        ]
        let points = RenderGeometry.freeformLocalPoints(part)
        #expect(points.count == 2)
        for point in points {
            #expect(point.x.isFinite, "x should never be NaN")
            #expect(point.y.isFinite, "y should never be NaN")
        }
    }
}

#if canImport(AppKit)
@Suite("ShapeRenderer — freeform parity (turtle-graphics D8, criteria 10 + 14)")
struct ShapeRendererFreeformTests {

    // MARK: - Criterion 10: open/unfilled vs closed/filled

    @Test("open stroke part (fillColor \"\") renders unfilled with a stroked outline")
    func openStrokeRendersUnfilledWithOutline() {
        let part = squarePart(fillColor: "", strokeColor: "#000000", strokeWidth: 2)
        let pixels = renderFreeform(part, rect: CGRect(x: 5, y: 5, width: 20, height: 20))

        // Interior of the "square" must stay background (white) — an
        // open polyline is never filled.
        let interior = pixels.averageBrightness(xRange: 12...18, yRange: 12...18)
        #expect(interior > 0.9, "open stroke interior should be untouched background, got brightness \(interior)")

        // The stroke itself must be visible: sample along the top
        // edge of the square (the first/second vertex segment).
        let topEdge = pixels.averageBrightness(xRange: 8...22, yRange: 5...7)
        #expect(topEdge < 0.5, "open stroke should paint a visible outline, got brightness \(topEdge)")
    }

    @Test("closed fill part (fillColor non-empty) renders filled and outlined")
    func closedFillRendersFilledAndOutlined() {
        let part = squarePart(fillColor: "#000000", strokeColor: "#000000", strokeWidth: 2)
        let pixels = renderFreeform(part, rect: CGRect(x: 5, y: 5, width: 20, height: 20))

        let interior = pixels.averageBrightness(xRange: 12...18, yRange: 12...18)
        #expect(interior < 0.1, "closed fill interior should be painted, got brightness \(interior)")
    }

    @Test("legacy #FFFFFF freeform part still renders closed and filled (Condition 6 regression)")
    func legacyWhiteFillStillClosesAndFills() {
        // White-on-white would be indistinguishable, so render against
        // a black backdrop and confirm the fill actually paints.
        let part = squarePart(fillColor: "#FFFFFF", strokeColor: "#000000", strokeWidth: 0)
        let pixels = renderFreeform(part, rect: CGRect(x: 5, y: 5, width: 20, height: 20), background: .black)

        let interior = pixels.averageBrightness(xRange: 12...18, yRange: 12...18)
        #expect(interior > 0.9, "legacy #FFFFFF freeform should still fill, got brightness \(interior)")
    }

    @Test("a fillColor \"\" part is never rendered as a solid black polygon (D8 rationale)")
    func openStrokeNeverRendersAsSolidBlack() {
        // Same shape, same background as the closed-black-fill test —
        // the only difference is fillColor "". If the open branch ever
        // regressed to unconditional close+fill, the interior would
        // paint black here exactly like the closed test above.
        let part = squarePart(fillColor: "", strokeColor: "#000000", strokeWidth: 2)
        let pixels = renderFreeform(part, rect: CGRect(x: 5, y: 5, width: 20, height: 20))
        let interior = pixels.averageBrightness(xRange: 12...18, yRange: 12...18)
        #expect(interior > 0.9, "an open stroke must never render as a filled polygon, got brightness \(interior)")
    }

    // MARK: - Criterion 14: frame moved +Δ → rendered geometry moves +Δ

    @Test("moving the part's frame translates the rendered drawing by the same delta")
    func movingFrameTranslatesRenderedGeometry() {
        let part = squarePart(fillColor: "#000000", strokeColor: "#000000", strokeWidth: 0)

        let atOrigin = renderFreeform(part, rect: CGRect(x: 5, y: 5, width: 20, height: 20), canvasSize: NSSize(width: 60, height: 60))
        let shifted = renderFreeform(part, rect: CGRect(x: 25, y: 5, width: 20, height: 20), canvasSize: NSSize(width: 60, height: 60))

        // Region that was filled before the +20 x-shift is now empty …
        let vacatedRegion = shifted.averageBrightness(xRange: 12...18, yRange: 12...18)
        #expect(vacatedRegion > 0.9, "region should be vacated after the frame moves, got brightness \(vacatedRegion)")

        // … and the drawing reappears, filled, at the shifted location.
        let arrivedRegion = shifted.averageBrightness(xRange: 32...38, yRange: 12...18)
        #expect(arrivedRegion < 0.1, "drawing should reappear filled at the shifted location, got brightness \(arrivedRegion)")

        // Sanity: the un-shifted render did paint the original region.
        let originalRegion = atOrigin.averageBrightness(xRange: 12...18, yRange: 12...18)
        #expect(originalRegion < 0.1, "sanity: original render should be filled before the shift, got brightness \(originalRegion)")
    }
}

// MARK: - Rendering helpers (AppKit only)

/// A 20×20 square freeform part (`pathData` in absolute card
/// coordinates), matching the frame used to render it in these tests.
private func squarePart(fillColor: String, strokeColor: String, strokeWidth: Double) -> Part {
    var part = Part(partType: .shape, name: "turtle path 1")
    part.shapeType = .freeform
    part.fillColor = fillColor
    part.strokeColor = strokeColor
    part.strokeWidth = strokeWidth
    part.pathData = [
        PathPoint(x: 400, y: 300),
        PathPoint(x: 420, y: 300),
        PathPoint(x: 420, y: 320),
        PathPoint(x: 400, y: 320),
    ]
    return part
}

/// Renders `part` through the real `ShapeRenderer.draw` entry point at
/// `rect` into a throwaway bitmap context, filled with `background`
/// first so fill/no-fill and stroke/no-stroke are directly observable
/// as pixel brightness.
private func renderFreeform(
    _ part: Part,
    rect: CGRect,
    background: NSColor = .white,
    canvasSize: NSSize = NSSize(width: 40, height: 40)
) -> RenderedFreeformPixels {
    let w = Int(canvasSize.width)
    let h = Int(canvasSize.height)
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
        return RenderedFreeformPixels(width: w, height: h, stride: w * 4, pixels: [])
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = gfx
    let ctx = gfx.cgContext

    // Match CardRenderer's flip (CardRenderer.swift:45-46) so
    // ShapeRenderer sees the same top-left-origin, y-down context it
    // does in production — required for the D8 mirroring fix (no
    // manual y-flip inside .freeform) to land at the coordinates these
    // tests expect.
    ctx.translateBy(x: 0, y: canvasSize.height)
    ctx.scaleBy(x: 1, y: -1)

    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(origin: .zero, size: canvasSize))
    ShapeRenderer.draw(ctx: ctx, part: part, rect: rect)

    // NSBitmapImageRep pads each row to its own alignment (e.g. 60
    // pixels × 4 bytes = 240, but `bytesPerRow` may report 256) —
    // always read the rep's actual stride rather than assuming
    // `width * 4`, or sampled rows silently shift.
    let stride = rep.bytesPerRow
    guard let data = rep.bitmapData else {
        return RenderedFreeformPixels(width: w, height: h, stride: stride, pixels: [])
    }
    let byteCount = h * stride
    return RenderedFreeformPixels(width: w, height: h, stride: stride, pixels: Array(UnsafeBufferPointer(start: data, count: byteCount)))
}

/// RGBA pixel sampler — see `ControlCleanupTests.RenderedPixels` for
/// the original pattern this mirrors, with an explicit row `stride`
/// (NSBitmapImageRep's `bytesPerRow` can pad past `width * 4`).
private struct RenderedFreeformPixels {
    let width: Int
    let height: Int
    private let stride: Int
    private let pixels: [UInt8]

    init(width: Int, height: Int, stride: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.stride = stride
        self.pixels = pixels
    }

    func brightness(x: Int, y: Int) -> Double {
        guard pixels.count == height * stride, x >= 0, x < width, y >= 0, y < height else { return 0 }
        let i = y * stride + x * 4
        let r = Double(pixels[i]) / 255
        let g = Double(pixels[i + 1]) / 255
        let b = Double(pixels[i + 2]) / 255
        return (r + g + b) / 3
    }

    func averageBrightness(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) -> Double {
        var sum = 0.0
        var count = 0
        for y in yRange {
            for x in xRange {
                sum += brightness(x: x, y: y)
                count += 1
            }
        }
        return count == 0 ? 0 : sum / Double(count)
    }
}
#endif

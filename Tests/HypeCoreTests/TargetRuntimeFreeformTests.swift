import Foundation
import Testing
@testable import HypeCore

// Turtle-graphics D8/N3 (spec.md "Freeform renderer alignment", design.md
// d9): the third freeform render site, `TargetRuntimeShapeView` in
// `Sources/HypeCore/Export/TargetRuntimeControlViews.swift`.
//
// `TargetRuntimeShapeView` (and its `shapePath`/`normalizedPathPoints`
// helpers) are `private` to that file — by design, this control-view
// source is also copied verbatim into generated export packages
// (see `TargetPlatformTests.targetRuntimeAdapterSourceHasExplicitStylePaths`,
// the established pattern this file follows), so it cannot be
// instantiated or rendered from a test target. These tests therefore
// combine:
//   1. Source-text assertions pinning the exact gate this change wired
//      in (matches the codebase's existing convention for this file).
//   2. Direct unit coverage of the shared `RenderGeometry` decision the
//      gate delegates to, applied to the exact boolean expression the
//      production code uses — the "observable branch" the plan calls
//      for when the drawn `Path` itself is unreachable.
@Suite("TargetRuntimeShapeView freeform gate (turtle-graphics D8/N3, d9)")
struct TargetRuntimeFreeformTests {

    private static var source: String {
        get throws {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/HypeCore/Export/TargetRuntimeControlViews.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("shapePath gates closeSubpath() on !freeformIsOpenStroke (never closes an open pen trail)")
    func shapePathGatesCloseSubpath() throws {
        let source = try Self.source
        #expect(source.contains("if !RenderGeometry.freeformIsOpenStroke(part) {"))
        #expect(source.contains("path.closeSubpath()"))
    }

    @Test("body gates the unconditional fill on the same freeformIsOpenStroke helper (d9 rationale)")
    func bodyGatesFillOnFreeformIsOpenStroke() throws {
        let source = try Self.source
        // The exact boolean the fill/stroke decision is keyed on —
        // scoped to .freeform so non-freeform shapes (rectangle,
        // roundRect, oval, line) keep filling unconditionally.
        #expect(source.contains("part.shapeType == .freeform && RenderGeometry.freeformIsOpenStroke(part)"))
        // The fill call itself must be conditional, not unconditional.
        #expect(source.contains("if !isOpenFreeformStroke {"))
        #expect(source.contains("context.fill(path, with: .color(Color(hex: part.fillColor)))"))
        // d9's stated rationale for why this matters, kept as a durable comment.
        #expect(source.contains("Color(hex: \"\")` resolves"))
    }

    @Test("open branch strokes with round cap/join when strokeWidth > 0")
    func openBranchUsesRoundCapAndJoin() throws {
        let source = try Self.source
        #expect(source.contains("StrokeStyle(lineWidth: part.strokeWidth, lineCap: .round, lineJoin: .round)"))
    }

    @Test("normalizedPathPoints stretch-to-fit geometry is left unchanged (N3)")
    func normalizedPathPointsUnchanged() throws {
        let source = try Self.source
        #expect(source.contains("private func normalizedPathPoints(in rect: CGRect) -> [CGPoint] {"))
        #expect(source.contains("let scaleX = rect.width / max(1, maxX - minX)"))
        #expect(source.contains("let scaleY = rect.height / max(1, maxY - minY)"))
        // .freeform's shapePath still calls the unmodified stretch-to-fit
        // helper — the only thing this change unified is close/fill.
        #expect(source.contains("let points = normalizedPathPoints(in: rect)"))
    }

    // MARK: - Observable branch: the exact production boolean, exercised directly

    @Test("the production open/closed decision: fillColor \"\" is open, every other freeform fillColor is closed")
    func freeformOpenClosedDecisionMatrix() {
        let cases: [(fillColor: String, expectOpen: Bool)] = [
            ("", true),
            ("#FFFFFF", false),  // legacy default — Condition 6
            ("#000000", false),
            ("#FF0000", false),
        ]
        for (fillColor, expectOpen) in cases {
            var part = Part(partType: .shape, name: "s")
            part.shapeType = .freeform
            part.fillColor = fillColor
            let isOpenFreeformStroke = part.shapeType == .freeform && RenderGeometry.freeformIsOpenStroke(part)
            #expect(isOpenFreeformStroke == expectOpen,
                    "fillColor '\(fillColor)' should be \(expectOpen ? "open" : "closed")")
        }
    }

    @Test("non-freeform shape types are never treated as an open stroke, even with an empty fillColor")
    func nonFreeformShapesAreNeverOpenStrokes() {
        for shapeType: ShapeType in [.rectangle, .roundRect, .oval, .line] {
            var part = Part(partType: .shape, name: "s")
            part.shapeType = shapeType
            part.fillColor = ""  // pathological input; still must not disable fill for non-freeform types
            let isOpenFreeformStroke = part.shapeType == .freeform && RenderGeometry.freeformIsOpenStroke(part)
            #expect(!isOpenFreeformStroke, "\(shapeType) must never be gated as an open freeform stroke")
        }
    }
}

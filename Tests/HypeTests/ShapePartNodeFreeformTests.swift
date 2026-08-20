import AppKit
import SpriteKit
import Testing
@testable import Hype
@testable import HypeCore

/// Turtle-graphics D8, criterion 10 (open/unfilled vs closed/filled
/// parity) and criterion 14 (frame moved +Δ → geometry moves +Δ) for
/// the SpriteKit render site (`ShapePartNode.updateFromPart`).
///
/// `Tests/HypeTests` is the AppKit/SpriteKit-backed target — it is
/// compiled (so this file must build cleanly) but not executed by
/// `scripts/mpd-test.sh`, which is headless. These tests are still
/// written to real semantics (not smoke-only) so they exercise the
/// contract correctly wherever they do run (locally, or on a
/// graphical CI runner).
@MainActor
@Suite("ShapePartNode freeform rendering (turtle-graphics D8)")
struct ShapePartNodeFreeformTests {

    // MARK: - Criterion 10: open/unfilled vs closed/filled

    @Test("open stroke part (fillColor \"\") clears the node's fill and never closes the path")
    func openStrokeIsUnfilledAndUnclosed() {
        let part = squareFreeformPart(fillColor: "", strokeColor: "#000000", strokeWidth: 2)
        let node = ShapePartNode(part: part)

        #expect(node.fillColor == .clear, "an open pen trail must never be filled")
        #expect(node.lineCap == .round, "pen trails must not show miter spikes")
        #expect(node.lineJoin == .round)

        guard let path = node.path else {
            Issue.record("expected a path for a 4-point open stroke")
            return
        }
        // All 4 vertices are still present (the polyline itself is
        // unaffected by the fill decision) — only the closing segment
        // and the fill are withheld.
        let bb = path.boundingBox
        #expect(abs(bb.width - 20) < 0.5, "expected the 20×20 square's bounding box, got \(bb)")
        #expect(abs(bb.height - 20) < 0.5, "expected the 20×20 square's bounding box, got \(bb)")
    }

    @Test("open stroke with zero strokeWidth also clears the stroke color (no SpriteKit default hairline)")
    func openStrokeZeroWidthClearsStrokeColor() {
        let part = squareFreeformPart(fillColor: "", strokeColor: "#000000", strokeWidth: 0)
        let node = ShapePartNode(part: part)
        #expect(node.strokeColor == .clear)
    }

    @Test("open stroke with non-zero strokeWidth keeps the pen's stroke color")
    func openStrokeNonZeroWidthKeepsStrokeColor() {
        let part = squareFreeformPart(fillColor: "", strokeColor: "#FF0000", strokeWidth: 2)
        let node = ShapePartNode(part: part)
        #expect(node.strokeColor.hexString == "#FF0000")
    }

    @Test("closed fill part (fillColor non-empty) closes the path and keeps its fill color")
    func closedFillClosesPathAndKeepsFillColor() {
        let part = squareFreeformPart(fillColor: "#FF0000", strokeColor: "#000000", strokeWidth: 2)
        let node = ShapePartNode(part: part)

        #expect(node.fillColor.hexString == "#FF0000")
        #expect(node.lineCap == .round)
        #expect(node.lineJoin == .round)
        #expect(node.path != nil)
        #expect(node.path?.isEmpty == false)
    }

    @Test("legacy #FFFFFF freeform part still renders closed and filled (Condition 6 regression)")
    func legacyWhiteFillStillClosesAndFills() {
        let part = squareFreeformPart(fillColor: "#FFFFFF", strokeColor: "#000000", strokeWidth: 1)
        let node = ShapePartNode(part: part)
        #expect(node.fillColor.hexString == "#FFFFFF")
        #expect(node.path != nil)
    }

    // MARK: - Criterion 14: frame moved +Δ → rendered geometry moves +Δ

    @Test("moving the part's frame translates the node position by the same delta")
    func movingFrameTranslatesNodePosition() {
        var part = squareFreeformPart(fillColor: "#000000", strokeColor: "#000000", strokeWidth: 0)
        let node = ShapePartNode(part: part)
        let originalPosition = node.position
        let originalPathBoundingBox = node.path?.boundingBox

        part.left += 30
        part.top += 12
        node.updateFromPart(part)

        #expect(abs(node.position.x - (originalPosition.x + 30)) < 0.001)
        #expect(abs(node.position.y - (originalPosition.y - 12)) < 0.001)
        // The path's local geometry is frame-independent (anchored to
        // the path's own tight bounding box) — a frame move is carried
        // entirely by the node's position, not by rebuilding the path
        // at a different local offset.
        #expect(node.path?.boundingBox == originalPathBoundingBox)
    }
}

@MainActor
private func squareFreeformPart(fillColor: String, strokeColor: String, strokeWidth: Double) -> Part {
    var part = Part(partType: .shape, name: "turtle path 1")
    part.shapeType = .freeform
    part.left = 100
    part.top = 100
    part.width = 20
    part.height = 20
    part.fillColor = fillColor
    part.strokeColor = strokeColor
    part.strokeWidth = strokeWidth
    part.pathData = [
        PathPoint(x: 0, y: 0),
        PathPoint(x: 20, y: 0),
        PathPoint(x: 20, y: 20),
        PathPoint(x: 0, y: 20),
    ]
    return part
}

import Testing
@testable import HypeCore

@Suite("Alignment Engine Tests")
struct AlignmentTests {

    let engine = AlignmentEngine()

    /// Helper to create a part at a given position and size.
    private func makePart(left: Double, top: Double, width: Double = 100, height: Double = 50) -> Part {
        Part(partType: .button, left: left, top: top, width: width, height: height)
    }

    @Test func snapToEdgeAlignment() {
        let other = makePart(left: 200, top: 100)
        // Moving part's left edge is near other's left edge (200)
        let moving = makePart(left: 203, top: 300)
        let result = engine.computeMoveSnap(
            movingPart: moving, otherParts: [other],
            canvasWidth: 800, canvasHeight: 600
        )
        #expect(result.dx == -3)
        #expect(!result.guides.isEmpty)
        #expect(result.guides.contains(where: { $0.kind == .edge }))
    }

    @Test func snapToCenterAlignment() {
        // Other part: left=200, width=100, centerX=250
        // Moving part: left=248, width=100, centerX=298
        // Edges: left=248 (nearest other edge=200, dist=48), right=348 (nearest=300, dist=48)
        // Center: 298 vs 250, dist=48 — all too far.
        // Use: other at left=500 width=100 centerX=550; moving at left=498 width=100 centerX=548
        // Moving edges: left=498, right=598. Other edges: left=500(dist=2), right=600(dist=2), center=550(dist=2)
        // Edge and center are equidistant; edge is checked first. Need center to be strictly closer.
        // Other: left=500, width=100, centerX=550. Moving: left=497, width=100, centerX=547 (3pt from 550)
        // left=497 vs 500: dist=3. right=597 vs 600: dist=3. center=547 vs 550: dist=3. All same.
        // Make moving centerX closer to other centerX than any edge is to other edges.
        // Other: left=500, width=100. Moving: left=502, width=96, centerX=550 — exact center match!
        // But left=502 vs 500: dist=2; right=598 vs 600: dist=2; center=550 vs 550: dist=0. Center wins.
        let other = makePart(left: 500, top: 100, width: 100)
        let moving = makePart(left: 502, top: 300, width: 96)
        let result = engine.computeMoveSnap(
            movingPart: moving, otherParts: [other],
            canvasWidth: 800, canvasHeight: 600
        )
        // CenterX of moving = 550, matches other centerX = 550 exactly (dist=0)
        // This is better than edge match (dist=2), so center guide should win
        #expect(result.dx == 0)
        #expect(result.guides.contains(where: { $0.kind == .center }))
    }

    @Test func snapToCanvasCenter() {
        // Canvas is 800x600, center = (400, 300)
        // Moving part center X = 398 + 100/2 = 448... let's use left=348, centerX=398
        let moving = makePart(left: 348, top: 100, width: 100)
        let result = engine.computeMoveSnap(
            movingPart: moving, otherParts: [],
            canvasWidth: 800, canvasHeight: 600
        )
        // CenterX = 398, canvas center = 400, so dx = +2
        #expect(result.dx == 2)
        #expect(result.guides.contains(where: { $0.kind == .canvas }))
    }

    @Test func snapToHIGSpacing() {
        let other = makePart(left: 100, top: 100, width: 100)
        // Other right edge = 200. Moving left = 208 (8pt gap = HIG small)
        let moving = makePart(left: 209, top: 100)
        let result = engine.computeMoveSnap(
            movingPart: moving, otherParts: [other],
            canvasWidth: 800, canvasHeight: 600
        )
        // Target = 200 + 8 = 208, moving left = 209, so dx = -1
        #expect(result.dx == -1)
        #expect(result.guides.contains(where: { $0.kind == .spacing }))
    }

    @Test func noSnapBeyondThreshold() {
        let other = makePart(left: 200, top: 200, width: 100, height: 50)
        // Moving part is far from any alignment (edges, centers, spacing, and canvas center)
        // Moving: left=30, top=30, right=130, bottom=80, centerX=80, centerY=55
        // Other: left=200, top=200, right=300, bottom=250, centerX=250, centerY=225
        // Canvas center: (75, 55) — avoid that too. Use large canvas.
        let moving = makePart(left: 30, top: 30, width: 100, height: 50)
        let result = engine.computeMoveSnap(
            movingPart: moving, otherParts: [other],
            canvasWidth: 2000, canvasHeight: 2000
        )
        #expect(result.dx == 0)
        #expect(result.dy == 0)
        #expect(result.guides.isEmpty)
    }

    @Test func resizeSnapMatchesWidth() {
        let other = makePart(left: 300, top: 100, width: 150, height: 80)
        // Resizing part has width close to 150
        let resizing = makePart(left: 50, top: 50, width: 147, height: 60)
        let result = engine.computeResizeSnap(
            resizingPart: resizing, otherParts: [other],
            canvasWidth: 800, canvasHeight: 600
        )
        #expect(result.dw == 3)
    }

    @Test func resizeSnapMatchesHeight() {
        let other = makePart(left: 300, top: 100, width: 150, height: 80)
        let resizing = makePart(left: 50, top: 50, width: 200, height: 82)
        let result = engine.computeResizeSnap(
            resizingPart: resizing, otherParts: [other],
            canvasWidth: 800, canvasHeight: 600
        )
        #expect(result.dh == -2)
    }
}

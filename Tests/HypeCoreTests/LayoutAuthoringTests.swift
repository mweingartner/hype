import Foundation
import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import HypeCore

@Suite("Layout authoring grid")
struct LayoutAuthoringTests {
    @Test("default sizes match the HIG-oriented creation contract")
    func defaultSizesMatchCreationContract() {
        #expect(PartCreationDefaults.defaultSize(for: .button) == PartDefaultSize(width: 88, height: 24))
        #expect(PartCreationDefaults.defaultSize(for: .field) == PartDefaultSize(width: 96, height: 22))
        #expect(PartCreationDefaults.defaultSize(for: .slider) == PartDefaultSize(width: 96, height: 16))
        #expect(PartCreationDefaults.defaultSize(for: .progressView) == PartDefaultSize(width: 96, height: 14))
        #expect(PartCreationDefaults.defaultSize(for: .spriteArea) == PartDefaultSize(width: 320, height: 240))
    }

    @Test("canonical creation tools map to one persisted part type")
    func creationToolsMapToPartTypes() throws {
        let button = try #require(PartCreationDefaults.toolSpec(for: "button"))
        #expect(button.partType == .button)
        #expect(button.extras.isEmpty)

        let shape = try #require(PartCreationDefaults.toolSpec(for: "shape"))
        #expect(shape.partType == .shape)
        #expect(shape.extras["shapeType"] == "rectangle")

        #expect(PartCreationDefaults.toolSpec(for: "select") == nil)
        #expect(PartCreationDefaults.toolSpec(for: "pencil") == nil)
    }

    #if canImport(CoreGraphics)
    @Test("tiny creation drags create a default-sized snapped part")
    func tinyCreationDragUsesDefaultSize() {
        let rect = PartCreationDefaults.creationRect(
            for: .button,
            dragStart: CGPoint(x: 10, y: 20),
            currentPoint: CGPoint(x: 12, y: 22)
        )

        #expect(rect.origin.x == 16)
        #expect(rect.origin.y == 24)
        #expect(rect.size.width == 88)
        #expect(rect.size.height == 24)
    }

    @Test("explicit creation drags snap origin and size unless Shift fine control is active")
    func explicitCreationDragSnapsUnlessFineControl() {
        let snapped = PartCreationDefaults.creationRect(
            for: .button,
            dragStart: CGPoint(x: 10, y: 20),
            currentPoint: CGPoint(x: 110, y: 80)
        )
        #expect(snapped.origin.x == 8)
        #expect(snapped.origin.y == 24)
        #expect(snapped.size.width == 104)
        #expect(snapped.size.height == 64)

        let fine = PartCreationDefaults.creationRect(
            for: .button,
            dragStart: CGPoint(x: 10, y: 20),
            currentPoint: CGPoint(x: 110, y: 80),
            fineControl: true
        )
        #expect(fine.origin.x == 10)
        #expect(fine.origin.y == 20)
        #expect(fine.size.width == 100)
        #expect(fine.size.height == 60)
    }
    #endif

    @Test("plain moves snap to the 8-point grid and Option moves expose smart spacing")
    func moveSnapGridAndSmartSpacing() {
        let engine = AlignmentEngine()
        let other = Part(partType: .button, cardId: UUID(), left: 50, top: 40, width: 50, height: 24)
        let moving = Part(partType: .button, cardId: UUID(), left: 109, top: 33, width: 20, height: 24)

        let plain = engine.computeMoveSnap(
            movingPart: moving,
            otherParts: [other],
            canvasWidth: 300,
            canvasHeight: 200
        )
        #expect(plain.dx == 3)
        #expect(!plain.guides.contains { $0.kind == .spacing })

        let smart = engine.computeMoveSnap(
            movingPart: moving,
            otherParts: [other],
            canvasWidth: 300,
            canvasHeight: 200,
            smartSpacing: true
        )
        #expect(smart.dx == -1)
        #expect(smart.guides.contains { $0.kind == .spacing })
    }

    @Test("margin and baseline guides are active snap targets")
    func marginAndBaselineGuidesAreSnapTargets() {
        let engine = AlignmentEngine()
        let marginPart = Part(partType: .shape, cardId: UUID(), left: 18, top: 44, width: 60, height: 40)
        let marginSnap = engine.computeMoveSnap(
            movingPart: marginPart,
            otherParts: [],
            canvasWidth: 300,
            canvasHeight: 200
        )
        #expect(marginSnap.dx == 2)
        #expect(marginSnap.guides.contains { $0.kind == .margin })

        let otherField = Part(partType: .field, cardId: UUID(), left: 40, top: 50, width: 100, height: 22)
        var movingField = Part(partType: .field, cardId: UUID(), left: 160, top: 14.18, width: 100, height: 80)
        movingField.textSize = 45
        let baselineSnap = engine.computeMoveSnap(
            movingPart: movingField,
            otherParts: [otherField],
            canvasWidth: 300,
            canvasHeight: 200,
            fineControl: true
        )
        #expect(abs(baselineSnap.dy) < 0.01)
        #expect(baselineSnap.guides.contains { $0.kind == .baseline })
    }

    @Test("resize snaps dimensions to 8-point increments unless Shift fine control is active")
    func resizeSnapUsesGrid() {
        let engine = AlignmentEngine()
        let part = Part(partType: .shape, cardId: UUID(), left: 0, top: 0, width: 101, height: 58)

        let snapped = engine.computeResizeSnap(
            resizingPart: part,
            otherParts: [],
            canvasWidth: 300,
            canvasHeight: 200
        )
        #expect(snapped.dw == 3)
        #expect(snapped.dh == -2)

        let fine = engine.computeResizeSnap(
            resizingPart: part,
            otherParts: [],
            canvasWidth: 300,
            canvasHeight: 200,
            fineControl: true
        )
        #expect(fine.dw == 0)
        #expect(fine.dh == 0)
    }
}

import AppKit
import Foundation
import HypeCore
import Testing
@testable import Hype

@Suite("Form control host views")
@MainActor
struct FormControlHostViewTests {
    @Test("Slider host applies dimension-derived orientation")
    func sliderHostAppliesDimensionDerivedOrientation() {
        let host = SliderHostNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        var part = Part(partType: .slider, name: "volume")

        part.width = 160
        part.height = 24
        host.apply(part)
        #expect(host.orientation == .horizontal)

        part.width = 24
        part.height = 160
        host.frame = NSRect(x: 0, y: 0, width: 24, height: 160)
        host.apply(part)
        #expect(host.orientation == .vertical)
    }

    @Test("Slider host emits interaction-end after Hype mouse tracking completes")
    func sliderHostEmitsInteractionEndAfterTrackingCompletes() {
        let host = SliderHostNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        var endCount = 0
        host.onInteractionEnd = { endCount += 1 }

        host.beginMouseTracking(atLocalPoint: NSPoint(x: 6, y: 12))
        host.endMouseTracking(atLocalPoint: NSPoint(x: 6, y: 12))

        #expect(endCount == 1)
    }

    @Test("Slider host maps horizontal track clicks directly to values")
    func sliderHostMapsHorizontalTrackClicksDirectlyToValues() {
        let host = SliderHostNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        var part = Part(partType: .slider, name: "zoom")
        part.width = 160
        part.height = 24
        part.controlMin = 0
        part.controlMax = 100
        part.controlValue = 0
        host.apply(part)

        var changes: [Double] = []
        host.onValueChange = { changes.append($0) }

        #expect(host.setValue(fromLocalPoint: NSPoint(x: 154, y: 12)))
        #expect(abs(host.controlValue - 100) < 0.0001)
        #expect(abs((changes.last ?? -1) - 100) < 0.0001)

        #expect(host.setValue(fromLocalPoint: NSPoint(x: 6, y: 12)))
        #expect(abs(host.controlValue - 0) < 0.0001)
        #expect(abs((changes.last ?? -1) - 0) < 0.0001)
    }

    @Test("Slider host maps vertical track clicks directly to values")
    func sliderHostMapsVerticalTrackClicksDirectlyToValues() {
        let host = SliderHostNSView(frame: NSRect(x: 0, y: 0, width: 32, height: 232))
        var part = Part(partType: .slider, name: "zoom")
        part.width = 32
        part.height = 232
        part.controlMin = 0.005
        part.controlMax = 50
        part.controlValue = 0.005
        host.apply(part)

        var changes: [Double] = []
        host.onValueChange = { changes.append($0) }

        #expect(host.orientation == .vertical)
        #expect(host.setValue(fromLocalPoint: NSPoint(x: 16, y: 6)))
        #expect(abs(host.controlValue - 50) < 0.0001)
        #expect(abs((changes.last ?? -1) - 50) < 0.0001)

        #expect(host.setValue(fromLocalPoint: NSPoint(x: 16, y: 226)))
        #expect(abs(host.controlValue - 0.005) < 0.0001)
        #expect(abs((changes.last ?? -1) - 0.005) < 0.0001)
    }

    @Test("Slider mouse tracking is owned by the full Hype host rect")
    func sliderMouseTrackingIsOwnedByFullHypeHostRect() throws {
        let host = SliderHostNSView(frame: NSRect(x: 0, y: 0, width: 32, height: 232))
        var part = Part(partType: .slider, name: "zoom")
        part.width = 32
        part.height = 232
        part.controlMin = 0.005
        part.controlMax = 50
        part.controlValue = 0.005
        host.apply(part)

        #expect(host.hitTest(NSPoint(x: 16, y: 116)) === host)

        var beginCount = 0
        var endCount = 0
        var changes: [Double] = []
        host.onInteractionBegin = { beginCount += 1 }
        host.onInteractionEnd = { endCount += 1 }
        host.onValueChange = { changes.append($0) }

        host.beginMouseTracking(atLocalPoint: NSPoint(x: 16, y: 226))
        #expect(host.isMouseTracking)
        #expect(beginCount == 1)

        host.continueMouseTracking(atLocalPoint: NSPoint(x: 16, y: 6))
        #expect(host.controlValue > 49)
        #expect(changes.last.map { $0 > 49 } == true)

        host.endMouseTracking(atLocalPoint: NSPoint(x: 16, y: 6))
        #expect(!host.isMouseTracking)
        #expect(endCount == 1)

        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hype/Views/FormControlHostViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains("override func hitTest(_ point: NSPoint) -> NSView?"))
        #expect(source.contains("return self"))
        #expect(source.contains("final class SliderHostNSView: NSView"))
        #expect(source.contains("override var acceptsFirstResponder: Bool { true }"))
        #expect(source.contains("private func trackMouseSequence(startingWith event: NSEvent)"))
        #expect(source.contains("window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])"))
        #expect(source.contains("func beginMouseTracking(atLocalPoint point: NSPoint)"))
        #expect(source.contains("override func mouseDragged(with event: NSEvent)"))
        #expect(source.contains("override func mouseUp(with event: NSEvent)"))
        #expect(source.contains("func value(forLocalPoint point: NSPoint) -> Double"))
        #expect(!source.contains("final class HypeSliderControl: NSSlider"))
        #expect(!source.contains("super.mouseDown(with: event)"))
    }

    @Test("Canvas slider fallback maps visible vertical slider points to values")
    func canvasSliderFallbackMapsVerticalPointsToValues() {
        var part = Part(partType: .slider, name: "zoom")
        part.left = 595.5
        part.top = 483.08
        part.width = 32
        part.height = 232
        part.controlMin = 0.005
        part.controlMax = 50

        let topValue = CardCanvasNSView.canvasSliderControlValue(
            forCanvasPoint: CGPoint(x: 611.5, y: 489.08),
            part: part
        )
        let bottomValue = CardCanvasNSView.canvasSliderControlValue(
            forCanvasPoint: CGPoint(x: 611.5, y: 709.08),
            part: part
        )

        #expect(abs(topValue - 50) < 0.0001)
        #expect(abs(bottomValue - 0.005) < 0.0001)
    }

    @Test("Slider host ignores stale model values during active mouse tracking")
    func sliderHostIgnoresStaleModelValuesDuringTracking() {
        let host = SliderHostNSView(frame: NSRect(x: 0, y: 0, width: 32, height: 232))
        var part = Part(partType: .slider, name: "zoom")
        part.width = 32
        part.height = 232
        part.controlMin = 0
        part.controlMax = 100
        part.controlValue = 10
        host.apply(part)

        host.beginMouseTracking(atLocalPoint: NSPoint(x: 154, y: 16))
        host.apply(part)
        #expect(host.controlValue > 90)

        host.endMouseTracking(atLocalPoint: NSPoint(x: 154, y: 16))
        part.controlValue = 40
        host.apply(part)
        #expect(abs(host.controlValue - 40) < 0.0001)
    }

    @Test("Slider interaction-end is wired to HypeTalk mouseUp dispatch")
    func sliderInteractionEndDispatchesMouseUp() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hype/Views/CardCanvasView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("host.onInteractionEnd = { [weak self] in"))
        #expect(source.contains("self?.coordinator?.dispatchMessage(\"mouseUp\", to: partId)"))
    }

    @Test("Canvas hit testing explicitly routes slider hosts")
    func canvasHitTestingExplicitlyRoutesSliderHosts() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hype/Views/CardCanvasView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("for view in sliderViews.values.reversed()"))
        #expect(source.contains("return view.hitTest(localPoint) ?? view"))
    }

    @Test("Runtime mode forces browse interaction even if the selected tool drifts")
    func runtimeModeForcesBrowseInteractionEvenIfSelectedToolDrifts() {
        #expect(CardCanvasNSView.effectiveMouseTool(currentTool: .select, runtimeModeEnabled: true) == .browse)
        #expect(CardCanvasNSView.effectiveMouseTool(currentTool: .slider, runtimeModeEnabled: true) == .browse)
        #expect(CardCanvasNSView.effectiveMouseTool(currentTool: .select, runtimeModeEnabled: false) == .select)

        #expect(CardCanvasNSView.allowsRuntimeInteraction(currentTool: .select, runtimeModeEnabled: true))
        #expect(CardCanvasNSView.allowsRuntimeInteraction(currentTool: .slider, runtimeModeEnabled: true))
        #expect(CardCanvasNSView.allowsRuntimeInteraction(currentTool: .browse, runtimeModeEnabled: false))
        #expect(!CardCanvasNSView.allowsRuntimeInteraction(currentTool: .select, runtimeModeEnabled: false))
        #expect(!CardCanvasNSView.allowsRuntimeInteraction(currentTool: .slider, runtimeModeEnabled: false))
    }

    @Test("Scripted continuous sliders preserve live value when applying script results")
    func scriptedContinuousSlidersPreserveLiveValueWhenApplyingScriptResults() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hype/Views/CardCanvasView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("preservingLiveControlValueFor: id"))
        #expect(source.contains("modified.updatePart(id: preservedControlPartId) { $0.controlValue = liveValue }"))
        #expect(source.contains("nsView?.setSliderHostDisplayedValue(partId: preservedControlPartId, value: liveValue)"))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

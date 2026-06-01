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
        #expect(host.slider.isVertical == false)

        part.width = 24
        part.height = 160
        host.frame = NSRect(x: 0, y: 0, width: 24, height: 160)
        host.apply(part)
        #expect(host.slider.isVertical == true)
    }

    @Test("Slider host emits interaction-end after AppKit mouse tracking completes")
    func sliderHostEmitsInteractionEndAfterTrackingCompletes() {
        let host = SliderHostNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        var endCount = 0
        host.onInteractionEnd = { endCount += 1 }

        host.slider.notifyMouseTrackingEnded()

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
        host.slider.frame = host.bounds

        var changes: [Double] = []
        host.onValueChange = { changes.append($0) }

        #expect(host.slider.setValue(fromLocalPoint: NSPoint(x: 154, y: 12)))
        #expect(abs(host.slider.doubleValue - 100) < 0.0001)
        #expect(abs((changes.last ?? -1) - 100) < 0.0001)

        #expect(host.slider.setValue(fromLocalPoint: NSPoint(x: 6, y: 12)))
        #expect(abs(host.slider.doubleValue - 0) < 0.0001)
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
        host.slider.frame = host.bounds

        var changes: [Double] = []
        host.onValueChange = { changes.append($0) }

        #expect(host.slider.isVertical)
        #expect(host.slider.setValue(fromLocalPoint: NSPoint(x: 16, y: 6)))
        #expect(abs(host.slider.doubleValue - 50) < 0.0001)
        #expect(abs((changes.last ?? -1) - 50) < 0.0001)

        #expect(host.slider.setValue(fromLocalPoint: NSPoint(x: 16, y: 226)))
        #expect(abs(host.slider.doubleValue - 0.005) < 0.0001)
        #expect(abs((changes.last ?? -1) - 0.005) < 0.0001)
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

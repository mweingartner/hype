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

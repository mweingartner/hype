import AppKit
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
}

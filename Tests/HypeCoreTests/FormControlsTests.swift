import Testing
import AppKit
import Foundation
@testable import HypeCore

/// Phase 2 form controls — Stepper, Slider, Toggle, Segmented. Share
/// a unified controlValue/min/max/step backing on Part; tests verify
/// each behaves correctly against that shared schema and that the
/// AI tool surface produces the right part with the right defaults.
@Suite("Form controls — Stepper / Slider / Toggle / Segmented")
struct FormControlsTests {

    // MARK: - Defaults

    @Test("Stepper defaults: value 0, min 0, max 100, step 1")
    func stepperDefaults() {
        let part = Part(partType: .stepper, name: "qty")
        #expect(part.partType == .stepper)
        #expect(part.controlValue == 0)
        #expect(part.controlMin == 0)
        #expect(part.controlMax == 100)
        #expect(part.controlStep == 1)
    }

    @Test("Slider defaults match stepper defaults")
    func sliderDefaults() {
        let part = Part(partType: .slider, name: "volume")
        #expect(part.partType == .slider)
        #expect(part.controlValue == 0)
        #expect(part.controlMin == 0)
        #expect(part.controlMax == 100)
    }

    @Test("Slider orientation follows longest dimension")
    func sliderOrientationFollowsLongestDimension() {
        var part = Part(partType: .slider, name: "volume")
        part.width = 160
        part.height = 24
        #expect(part.sliderControlOrientation == .horizontal)

        part.width = 24
        part.height = 160
        #expect(part.sliderControlOrientation == .vertical)

        part.width = 48
        part.height = 48
        #expect(part.sliderControlOrientation == .horizontal)
    }

    @MainActor
    @Test("Slider preview renderer follows longest dimension")
    func sliderPreviewRendererFollowsLongestDimension() throws {
        var horizontal = Part(partType: .slider, name: "horizontal")
        horizontal.width = 160
        horizontal.height = 24
        horizontal.controlValue = 50
        horizontal.controlMin = 0
        horizontal.controlMax = 100

        var vertical = Part(partType: .slider, name: "vertical")
        vertical.width = 24
        vertical.height = 160
        vertical.controlValue = 50
        vertical.controlMin = 0
        vertical.controlMax = 100

        let horizontalBounds = try #require(renderedSliderInkBounds(part: horizontal, width: 160, height: 24))
        let verticalBounds = try #require(renderedSliderInkBounds(part: vertical, width: 24, height: 160))

        #expect(horizontalBounds.width > horizontalBounds.height)
        #expect(verticalBounds.height > verticalBounds.width)
    }

    @Test("Toggle defaults: off (controlValue 0)")
    func toggleDefaults() {
        let part = Part(partType: .toggle, name: "muted")
        #expect(part.partType == .toggle)
        #expect(part.controlValue == 0)
    }

    @Test("Segmented defaults: three segments, index 0")
    func segmentedDefaults() {
        let part = Part(partType: .segmented, name: "tabs")
        #expect(part.partType == .segmented)
        #expect(part.controlValue == 0)
        #expect(part.segmentItems == "First|Second|Third")
    }

    // MARK: - Codable

    @Test("Stepper round-trips through Codable")
    func stepperCodable() throws {
        var part = Part(partType: .stepper, name: "qty")
        part.controlValue = 42
        part.controlMin = -10
        part.controlMax = 100
        part.controlStep = 5
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.controlValue == 42)
        #expect(decoded.controlMin == -10)
        #expect(decoded.controlMax == 100)
        #expect(decoded.controlStep == 5)
    }

    @Test("Segmented items round-trip through Codable")
    func segmentedCodable() throws {
        var part = Part(partType: .segmented, name: "tabs")
        part.segmentItems = "Day|Week|Month|Year"
        part.controlValue = 2
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.segmentItems == "Day|Week|Month|Year")
        #expect(decoded.controlValue == 2)
    }

    // MARK: - AI tools

    @Test("create_stepper builds a stepper with the requested bounds")
    func aiCreateStepper() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_stepper",
            arguments: [
                "name": "qty", "left": "0", "top": "0", "width": "70", "height": "24",
                "value": "5", "min": "0", "max": "20", "step": "1"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .stepper }
        #expect(part?.controlValue == 5)
        #expect(part?.controlMax == 20)
        #expect(part?.controlStep == 1)
    }

    @Test("create_slider builds a slider with min/max")
    func aiCreateSlider() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_slider",
            arguments: [
                "name": "volume", "left": "0", "top": "0", "width": "200", "height": "24",
                "value": "50", "min": "0", "max": "100"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .slider }
        #expect(part?.controlValue == 50)
    }

    // create_toggle removed in dedup — toggle is now a button style.
    // The equivalent test is aiCreateButtonToggle below.

    @Test("create_button with style=toggle creates a toggle-styled button")
    func aiCreateButtonToggle() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_button",
            arguments: ["name": "muted", "left": "0", "top": "0", "width": "44", "height": "26", "style": "toggle"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.name == "muted" && $0.partType == .button }
        #expect(part != nil)
        #expect(part?.buttonStyle == .toggle)
    }

    @Test("create_button with deprecated style=switch is migrated to .toggle")
    func aiCreateButtonSwitchAliasMigratesToToggle() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_button",
            arguments: ["name": "muted", "left": "0", "top": "0", "width": "44", "height": "26", "style": "switch"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.name == "muted" && $0.partType == .button }
        #expect(part != nil)
        // The "switch" raw value used to be its own ButtonStyle case
        // but was a duplicate of `.toggle` — both rendered as the
        // same NSSwitch-style track-and-knob UI. The case was
        // removed and "switch" now resolves to `.toggle` via
        // ButtonStyle.resolved(rawOrAlias:).
        #expect(part?.buttonStyle == .toggle)
    }

    @Test("create_segmented sets segments + selected index")
    func aiCreateSegmented() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_segmented",
            arguments: [
                "name": "tabs", "left": "0", "top": "0", "width": "240", "height": "26",
                "segments": "Day|Week|Month",
                "selected_segment": "1"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .segmented }
        #expect(part?.segmentItems == "Day|Week|Month")
        #expect(part?.controlValue == 1)
    }

    @Test("set_part_property accepts 'value' on a stepper")
    func aiSetStepperValue() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_stepper",
            arguments: ["name": "qty", "left": "0", "top": "0", "width": "70", "height": "24"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "qty", "property": "value", "value": "13"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .stepper }?.controlValue == 13)
    }

    // toggle-specific 'on' tests removed — toggle migrated to button
    // with ButtonStyle.toggle; the on/off state is now part.hilite,
    // covered by the existing button tests.

    @Test("get_part_property returns the integer for selectedSegment")
    func aiGetSelectedSegment() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_segmented",
            arguments: ["name": "tabs", "left": "0", "top": "0", "width": "240", "height": "26",
                        "segments": "A|B|C", "selected_segment": "2"],
            document: &doc, currentCardId: cardId
        )
        let segResult = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "tabs", "property": "selected_segment"],
            document: &doc, currentCardId: cardId
        )
        #expect(segResult == "2")
    }

    // MARK: - HypeTalk parser

    @Test("Parser accepts `the value of slider \"X\"`")
    func hypeTalkSlider() throws {
        let source = "the value of slider \"volume\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "value",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "slider")
        } else {
            Issue.record("expected propertyAccess(value, objectRef(slider, ...)), got \(expr)")
        }
    }

    @Test("Parser accepts `the on of toggle \"X\"`")
    func hypeTalkToggle() throws {
        let source = "the on of toggle \"muted\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, _) = expr {
            #expect(prop == "on")
        } else {
            Issue.record("expected propertyAccess(on, ...), got \(expr)")
        }
    }
}

@MainActor
private func renderedSliderInkBounds(part: Part, width: Int, height: Int) -> CGRect? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

    pixels.withUnsafeMutableBytes { rawBuffer in
        guard let context = CGContext(
            data: rawBuffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.clear(rect)
        if let aqua = NSAppearance(named: .aqua) {
            aqua.performAsCurrentDrawingAppearance {
                FormControlsRenderer.draw(.slider, ctx: context, part: part, rect: rect)
            }
        } else {
            FormControlsRenderer.draw(.slider, ctx: context, part: part, rect: rect)
        }
    }

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    for y in 0..<height {
        for x in 0..<width {
            let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
            guard alpha > 0 else { continue }
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

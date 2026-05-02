import Testing
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

    @Test("create_toggle 'on' arg writes 1.0 into controlValue")
    func aiCreateToggleOn() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_toggle",
            arguments: ["name": "muted", "left": "0", "top": "0", "width": "44", "height": "26", "on": "true"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .toggle }
        #expect(part?.controlValue == 1.0)
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

    @Test("set_part_property 'on' on a toggle stores 1.0 / 0.0")
    func aiSetToggleOn() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_toggle",
            arguments: ["name": "muted", "left": "0", "top": "0", "width": "44", "height": "26"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "muted", "property": "on", "value": "true"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .toggle }?.controlValue == 1)

        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "muted", "property": "on", "value": "false"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .toggle }?.controlValue == 0)
    }

    @Test("get_part_property returns 'true'/'false' for toggle.on, integer for selectedSegment")
    func aiGetters() async {
        var doc = HypeDocument.newDocument(name: "FormTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_toggle",
            arguments: ["name": "muted", "left": "0", "top": "0", "width": "44", "height": "26", "on": "true"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "create_segmented",
            arguments: ["name": "tabs", "left": "0", "top": "0", "width": "240", "height": "26",
                        "segments": "A|B|C", "selected_segment": "2"],
            document: &doc, currentCardId: cardId
        )
        let onResult = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "muted", "property": "on"],
            document: &doc, currentCardId: cardId
        )
        #expect(onResult == "true")

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

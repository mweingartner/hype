import Testing
import Foundation
@testable import HypeCore

/// Gauge part — a value indicator with labeled min/max.
///
/// Tests cover model defaults, Codable, backward-compat decode,
/// AI tool create + set/get, HypeTalk parser, and the security
/// condition that gaugeMax must always exceed gaugeMin.
@Suite("Gauge — model, AI tools, HypeTalk grammar, max > min enforcement")
struct GaugeTests {

    // MARK: - Model defaults

    @Test("Gauge defaults: value 0, min 0, max 1, linearCapacity style, empty tint/labels")
    func defaults() {
        let part = Part(partType: .gauge, name: "temp")
        #expect(part.partType == .gauge)
        #expect(part.gaugeValue == 0)
        #expect(part.gaugeMin == 0)
        #expect(part.gaugeMax == 1.0)
        #expect(part.gaugeStyle == "linearCapacity")
        #expect(part.gaugeTint == "")
        #expect(part.gaugeLabel == "")
        #expect(part.gaugeMinLabel == "")
        #expect(part.gaugeMaxLabel == "")
    }

    // MARK: - Codable round-trip

    @Test("Gauge fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .gauge, name: "temp")
        part.gaugeValue = 0.7
        part.gaugeMin = 0.0
        part.gaugeMax = 1.0
        part.gaugeStyle = "accessoryCircular"
        part.gaugeTint = "#FF4444"
        part.gaugeLabel = "Temperature"
        part.gaugeMinLabel = "Cold"
        part.gaugeMaxLabel = "Hot"
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.gaugeValue == 0.7)
        #expect(decoded.gaugeMin == 0.0)
        #expect(decoded.gaugeMax == 1.0)
        #expect(decoded.gaugeStyle == "accessoryCircular")
        #expect(decoded.gaugeTint == "#FF4444")
        #expect(decoded.gaugeLabel == "Temperature")
        #expect(decoded.gaugeMinLabel == "Cold")
        #expect(decoded.gaugeMaxLabel == "Hot")
    }

    // MARK: - Backward-compat decode

    @Test("Old document without gauge fields decodes with defaults")
    func backwardCompat() throws {
        var part = Part(partType: .gauge, name: "temp")
        part.gaugeMax = 5.0
        part.gaugeLabel = "Level"
        let data = try JSONEncoder().encode(part)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "gaugeValue")
        dict.removeValue(forKey: "gaugeMin")
        dict.removeValue(forKey: "gaugeMax")
        dict.removeValue(forKey: "gaugeStyle")
        dict.removeValue(forKey: "gaugeTint")
        dict.removeValue(forKey: "gaugeLabel")
        dict.removeValue(forKey: "gaugeMinLabel")
        dict.removeValue(forKey: "gaugeMaxLabel")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.gaugeValue == 0)
        #expect(decoded.gaugeMin == 0)
        #expect(decoded.gaugeMax == 1.0)
        #expect(decoded.gaugeStyle == "linearCapacity")
        #expect(decoded.gaugeLabel == "")
    }

    // MARK: - AI tools

    @Test("create_gauge builds a part with specified fields")
    func aiCreate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: [
                "name": "temp",
                "left": "0", "top": "0", "width": "200", "height": "44",
                "value": "0.6",
                "min": "0",
                "max": "1.0",
                "style": "accessoryLinear",
                "tint": "#3399FF",
                "label": "CPU",
                "min_label": "Low",
                "max_label": "High"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .gauge }
        #expect(part?.gaugeValue == 0.6)
        #expect(part?.gaugeMin == 0)
        #expect(part?.gaugeMax == 1.0)
        #expect(part?.gaugeStyle == "accessoryLinear")
        #expect(part?.gaugeTint == "#3399FF")
        #expect(part?.gaugeLabel == "CPU")
        #expect(part?.gaugeMinLabel == "Low")
        #expect(part?.gaugeMaxLabel == "High")
    }

    @Test("create_gauge with invalid style falls back to linearCapacity")
    func aiCreateInvalidStyle() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: [
                "name": "temp",
                "left": "0", "top": "0", "width": "200", "height": "44",
                "style": "invalidStyleName"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .gauge }
        #expect(part?.gaugeStyle == "linearCapacity")
    }

    @Test("set_part_property updates gaugeValue")
    func aiSetValue() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "temp", "left": "0", "top": "0", "width": "200", "height": "44"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "temp", "property": "gaugevalue", "value": "0.8"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .gauge }?.gaugeValue == 0.8)
    }

    @Test("set_part_property updates gaugeLabel with cap")
    func aiSetLabel() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "temp", "left": "0", "top": "0", "width": "200", "height": "44"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "temp", "property": "gauge_label", "value": "Battery"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .gauge }?.gaugeLabel == "Battery")
    }

    @Test("get_part_property reads gaugeValue")
    func aiGetValue() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .gauge, cardId: cardId, name: "temp",
                        left: 0, top: 0, width: 200, height: 44)
        part.gaugeValue = 0.55
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "temp", "property": "gaugevalue"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "0.55")
    }

    @Test("get_part_property 'value' on gauge reads gaugeValue")
    func aiGetValueAlias() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .gauge, cardId: cardId, name: "temp",
                        left: 0, top: 0, width: 200, height: 44)
        part.gaugeValue = 0.25
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "temp", "property": "value"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "0.25")
    }

    // MARK: - HypeTalk grammar

    @Test("HypeTalk parser accepts `the gaugeValue of gauge \"X\"`")
    func hypeTalkParser() throws {
        let source = "the gaugeValue of gauge \"temp\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "gaugeValue",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "gauge")
        } else {
            Issue.record("expected propertyAccess(gaugeValue, objectRef(gauge, ...)), got \(expr)")
        }
    }

    @Test("HypeTalk: `set the gaugeValue of gauge \"X\" to 0.9` updates the model")
    func hypeTalkSetter() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .gauge, cardId: cardId, name: "temp",
                        left: 0, top: 0, width: 200, height: 44)
        doc.addPart(part)
        let source = """
        on test
          set the gaugeValue of gauge "temp" to 0.9
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "temp" }!
        #expect(updated.gaugeValue == 0.9)
    }

    // MARK: - Security: max > min enforcement

    @Test("gaugeMax enforces > gaugeMin via set_part_property when equal")
    func gaugeMaxEnforcedViaAI() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "temp", "left": "0", "top": "0", "width": "200", "height": "44",
                        "min": "5", "max": "10"],
            document: &doc, currentCardId: cardId
        )
        // Set max = current min (5); should snap to min + 1 = 6
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "temp", "property": "gaugemax", "value": "5"],
            document: &doc, currentCardId: cardId
        )
        let stored = doc.parts.first { $0.partType == .gauge }?.gaugeMax ?? 0
        #expect(stored > 5)
    }

    @Test("create_gauge with max <= min corrects max to min + 1")
    func aiCreateMaxEqMin() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "temp", "left": "0", "top": "0", "width": "200", "height": "44",
                        "min": "10", "max": "10"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .gauge }
        #expect((part?.gaugeMax ?? 0) > (part?.gaugeMin ?? 0))
    }

    @Test("gaugeMax enforces > gaugeMin via HypeTalk setter")
    func gaugeMaxEnforcedViaHypeTalk() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .gauge, cardId: cardId, name: "temp",
                        left: 0, top: 0, width: 200, height: 44)
        part.gaugeMin = 3.0
        part.gaugeMax = 10.0
        doc.addPart(part)
        // Set max to same as min; interpreter should bump it to min + 1
        let source = """
        on test
          set the gaugeMax of gauge "temp" to 3
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let stored = (result.modifiedDocument ?? doc).parts.first { $0.name == "temp" }!.gaugeMax
        #expect(stored > 3.0)
    }

    @Test("gaugeLabel clamps to 256 chars via set_part_property")
    func gaugeLabelCapped() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "temp", "left": "0", "top": "0", "width": "200", "height": "44"],
            document: &doc, currentCardId: cardId
        )
        let longLabel = String(repeating: "X", count: 400)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "temp", "property": "gauge_label", "value": longLabel],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .gauge }?.gaugeLabel.count == 256)
    }
}

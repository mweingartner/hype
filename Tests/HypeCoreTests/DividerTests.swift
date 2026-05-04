import Testing
import Foundation
@testable import HypeCore

/// Divider part — a horizontal or vertical separator line.
///
/// Tests cover model defaults, Codable, backward-compat decode,
/// AI tool create + set/get, HypeTalk parser/setter, and the
/// minimum-thickness floor (0.5 pt).
@Suite("Divider — model, AI tools, HypeTalk grammar, thickness floor")
struct DividerTests {

    // MARK: - Model defaults

    @Test("Divider defaults: horizontal, thickness 1.0, empty color")
    func defaults() {
        let part = Part(partType: .divider, name: "sep")
        #expect(part.partType == .divider)
        #expect(part.dividerOrientation == "horizontal")
        #expect(part.dividerThickness == 1.0)
        #expect(part.dividerColor == "")
    }

    // MARK: - Codable round-trip

    @Test("Divider fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .divider, name: "sep")
        part.dividerOrientation = "vertical"
        part.dividerThickness = 2.5
        part.dividerColor = "#AAAAAA"
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.dividerOrientation == "vertical")
        #expect(decoded.dividerThickness == 2.5)
        #expect(decoded.dividerColor == "#AAAAAA")
    }

    // MARK: - Backward-compat decode

    @Test("Old document without divider fields decodes with defaults")
    func backwardCompat() throws {
        var part = Part(partType: .divider, name: "sep")
        part.dividerOrientation = "vertical"
        part.dividerThickness = 3.0
        let data = try JSONEncoder().encode(part)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "dividerOrientation")
        dict.removeValue(forKey: "dividerThickness")
        dict.removeValue(forKey: "dividerColor")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.dividerOrientation == "horizontal")
        #expect(decoded.dividerThickness == 1.0)
        #expect(decoded.dividerColor == "")
    }

    // MARK: - AI tools

    @Test("create_divider builds a horizontal divider with default thickness")
    func aiCreateHorizontal() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_divider",
            arguments: [
                "name": "sep",
                "left": "50", "top": "100", "width": "400", "height": "2",
                "orientation": "horizontal"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .divider }
        #expect(part?.dividerOrientation == "horizontal")
        #expect(part?.dividerThickness == 1.0)
    }

    @Test("create_divider builds a vertical divider with custom thickness and color")
    func aiCreateVertical() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_divider",
            arguments: [
                "name": "vsep",
                "left": "200", "top": "0", "width": "2", "height": "400",
                "orientation": "vertical",
                "thickness": "2.0",
                "color": "#CCCCCC"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .divider }
        #expect(part?.dividerOrientation == "vertical")
        #expect(part?.dividerThickness == 2.0)
        #expect(part?.dividerColor == "#CCCCCC")
    }

    @Test("create_divider unknown orientation defaults to horizontal")
    func aiCreateUnknownOrientation() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_divider",
            arguments: ["name": "sep", "left": "0", "top": "0", "width": "400", "height": "2",
                        "orientation": "diagonal"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .divider }
        #expect(part?.dividerOrientation == "horizontal")
    }

    @Test("set_part_property updates dividerOrientation")
    func aiSetOrientation() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_divider",
            arguments: ["name": "sep", "left": "0", "top": "0", "width": "400", "height": "2"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "sep", "property": "orientation", "value": "vertical"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .divider }?.dividerOrientation == "vertical")
    }

    @Test("set_part_property updates dividerThickness")
    func aiSetThickness() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_divider",
            arguments: ["name": "sep", "left": "0", "top": "0", "width": "400", "height": "2"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "sep", "property": "thickness", "value": "3.0"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .divider }?.dividerThickness == 3.0)
    }

    @Test("set_part_property updates dividerColor")
    func aiSetColor() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_divider",
            arguments: ["name": "sep", "left": "0", "top": "0", "width": "400", "height": "2"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "sep", "property": "dividercolor", "value": "#FF0000"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .divider }?.dividerColor == "#FF0000")
    }

    @Test("get_part_property reads dividerOrientation")
    func aiGetOrientation() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .divider, cardId: cardId, name: "sep",
                        left: 0, top: 0, width: 400, height: 2)
        part.dividerOrientation = "vertical"
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "sep", "property": "orientation"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "vertical")
    }

    @Test("get_part_property reads dividerThickness")
    func aiGetThickness() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .divider, cardId: cardId, name: "sep",
                        left: 0, top: 0, width: 400, height: 2)
        part.dividerThickness = 2.5
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "sep", "property": "thickness"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "2.5")
    }

    // MARK: - HypeTalk grammar

    @Test("HypeTalk parser accepts `the orientation of divider \"X\"`")
    func hypeTalkParser() throws {
        let source = "the orientation of divider \"sep\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "orientation",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "divider")
        } else {
            Issue.record("expected propertyAccess(orientation, objectRef(divider, ...)), got \(expr)")
        }
    }

    @Test("HypeTalk: `set the orientation of divider \"X\" to \"vertical\"` updates the model")
    func hypeTalkSetter() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .divider, cardId: cardId, name: "sep",
                        left: 0, top: 0, width: 400, height: 2)
        doc.addPart(part)
        let source = """
        on test
          set the orientation of divider "sep" to "vertical"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "sep" }!
        #expect(updated.dividerOrientation == "vertical")
    }

    @Test("HypeTalk: `set the thickness of divider \"X\" to 4` updates the model")
    func hypeTalkSetThickness() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .divider, cardId: cardId, name: "sep",
                        left: 0, top: 0, width: 400, height: 2)
        doc.addPart(part)
        let source = """
        on test
          set the thickness of divider "sep" to 4
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "sep" }!
        #expect(updated.dividerThickness == 4.0)
    }

    // MARK: - Security: thickness floor

    @Test("dividerThickness clamps to >= 0.5 when set to 0 via set_part_property")
    func thicknessFloorViaAI() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_divider",
            arguments: ["name": "sep", "left": "0", "top": "0", "width": "400", "height": "2"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "sep", "property": "thickness", "value": "0"],
            document: &doc, currentCardId: cardId
        )
        let stored = doc.parts.first { $0.partType == .divider }?.dividerThickness ?? 0
        #expect(stored >= 0.5)
    }

    @Test("dividerThickness clamps to >= 0.5 when set to 0 via HypeTalk setter")
    func thicknessFloorViaHypeTalk() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .divider, cardId: cardId, name: "sep",
                        left: 0, top: 0, width: 400, height: 2)
        doc.addPart(part)
        let source = """
        on test
          set the thickness of divider "sep" to 0
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let stored = (result.modifiedDocument ?? doc).parts.first { $0.name == "sep" }!.dividerThickness
        #expect(stored >= 0.5)
    }
}

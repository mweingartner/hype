import Testing
import Foundation
@testable import HypeCore

/// ProgressView part — linear/circular progress indicator.
///
/// Tests cover model defaults, Codable, backward-compat decode,
/// AI tool create + set/get, HypeTalk parser, and the numeric-clamp
/// security conditions (no divide-by-zero, no negative total).
@Suite("ProgressView — model, AI tools, HypeTalk grammar, numeric clamps")
struct ProgressViewTests {

    // MARK: - Model defaults

    @Test("ProgressView defaults: value 0, total 1, linear, determinate, empty label/tint")
    func defaults() {
        let part = Part(partType: .progressView, name: "loader")
        #expect(part.partType == .progressView)
        #expect(part.progressValue == 0)
        #expect(part.progressTotal == 1.0)
        #expect(part.progressIsCircular == false)
        #expect(part.progressIsIndeterminate == false)
        #expect(part.progressLabel == "")
        #expect(part.progressTint == "")
    }

    // MARK: - Codable round-trip

    @Test("ProgressView fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .progressView, name: "loader")
        part.progressValue = 0.6
        part.progressTotal = 2.0
        part.progressIsCircular = true
        part.progressIsIndeterminate = false
        part.progressLabel = "Loading…"
        part.progressTint = "#FF8800"
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.progressValue == 0.6)
        #expect(decoded.progressTotal == 2.0)
        #expect(decoded.progressIsCircular == true)
        #expect(decoded.progressIsIndeterminate == false)
        #expect(decoded.progressLabel == "Loading…")
        #expect(decoded.progressTint == "#FF8800")
    }

    // MARK: - Backward-compat decode

    @Test("Old document without progressValue/progressTotal decodes with defaults")
    func backwardCompat() throws {
        var part = Part(partType: .progressView, name: "loader")
        part.progressValue = 0.5
        part.progressTotal = 10.0
        let data = try JSONEncoder().encode(part)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "progressValue")
        dict.removeValue(forKey: "progressTotal")
        dict.removeValue(forKey: "progressIsCircular")
        dict.removeValue(forKey: "progressLabel")
        dict.removeValue(forKey: "progressTint")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.progressValue == 0)
        #expect(decoded.progressTotal == 1.0)
        #expect(decoded.progressIsCircular == false)
        #expect(decoded.progressLabel == "")
    }

    // MARK: - AI tools

    @Test("create_progressview builds a part with specified value/total/label")
    func aiCreate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: [
                "name": "loader",
                "left": "10", "top": "20", "width": "240", "height": "20",
                "value": "0.4",
                "total": "1.0",
                "is_circular": "false",
                "is_indeterminate": "false",
                "label": "Syncing",
                "tint": "#3399FF",
                "decimals": "2"     // round to 2 decimals so 0.4 round-trips
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .progressView }
        #expect(part?.progressValue == 0.4)
        #expect(part?.progressTotal == 1.0)
        #expect(part?.progressIsCircular == false)
        #expect(part?.progressIsIndeterminate == false)
        #expect(part?.progressLabel == "Syncing")
        #expect(part?.progressTint == "#3399FF")
    }

    @Test("create_progressview circular + indeterminate flags work")
    func aiCreateCircularIndeterminate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: [
                "name": "spinner",
                "left": "0", "top": "0", "width": "40", "height": "40",
                "is_circular": "true",
                "is_indeterminate": "true"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .progressView }
        #expect(part?.progressIsCircular == true)
        #expect(part?.progressIsIndeterminate == true)
    }

    @Test("set_part_property updates progressValue on a progressView")
    func aiSetValue() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20",
                        "decimals": "2"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "loader", "property": "progressvalue", "value": "0.75"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .progressView }?.progressValue == 0.75)
    }

    @Test("Default progressDecimals=0 → progressView rounds writes to integers")
    func defaultDecimalsRoundsToInteger() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20",
                        "total": "100", "value": "17.93"],
            document: &doc, currentCardId: cardId
        )
        // Default decimals=0 → 17.93 rounds to 18.
        let part = doc.parts.first { $0.partType == .progressView }
        #expect(part?.progressValue == 18)
    }

    @Test("set_part_property `decimals` rounds subsequent value writes")
    func aiSetDecimalsRoundsValue() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20",
                        "total": "100"],
            document: &doc, currentCardId: cardId
        )
        // Set decimals=1 then write a value with more precision.
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "loader", "property": "decimals", "value": "1"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "loader", "property": "value", "value": "42.789"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .progressView }?.progressValue == 42.8)
    }

    @Test("set_part_property updates progressTotal on a progressView")
    func aiSetTotal() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "loader", "property": "total", "value": "5.0"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .progressView }?.progressTotal == 5.0)
    }

    @Test("get_part_property reads progressValue")
    func aiGetValue() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .progressView, cardId: cardId, name: "loader",
                        left: 0, top: 0, width: 200, height: 20)
        part.progressValue = 0.3
        part.progressTotal = 1.0
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "loader", "property": "progressvalue"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "0.3")
    }

    @Test("get_part_property 'value' on progressView reads progressValue")
    func aiGetValueAlias() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .progressView, cardId: cardId, name: "loader",
                        left: 0, top: 0, width: 200, height: 20)
        part.progressValue = 0.5
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "loader", "property": "value"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "0.5")
    }

    // MARK: - HypeTalk grammar

    @Test("HypeTalk parser accepts `the progressValue of progressView \"X\"`")
    func hypeTalkParser() throws {
        let source = "the progressValue of progressView \"loader\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "progressValue",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "progressview")
        } else {
            Issue.record("expected propertyAccess(progressValue, objectRef(progressview, ...)), got \(expr)")
        }
    }

    @Test("HypeTalk: `set the progressValue of progressView \"X\" to 0.8` updates the model")
    func hypeTalkSetter() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .progressView, cardId: cardId, name: "loader",
                        left: 0, top: 0, width: 200, height: 20)
        // Default progressDecimals is 0 (integer-only steps); raise it to 2
        // so the fractional 0.8 round-trips through the setter.
        part.progressDecimals = 2
        doc.addPart(part)
        let source = """
        on test
          set the progressValue of progressView "loader" to 0.8
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "loader" }!
        #expect(updated.progressValue == 0.8)
    }

    // MARK: - Security: numeric clamps

    @Test("progressTotal clamps to >= 1e-10 via set_part_property")
    func progressTotalClampedAtZeroViaAI() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "loader", "property": "total", "value": "0"],
            document: &doc, currentCardId: cardId
        )
        let stored = doc.parts.first { $0.partType == .progressView }?.progressTotal ?? 0
        #expect(stored > 0)
        #expect(stored >= 1e-10)
    }

    @Test("progressTotal clamps to >= 1e-10 via HypeTalk setter")
    func progressTotalClampedViaHypeTalk() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .progressView, cardId: cardId, name: "loader",
                        left: 0, top: 0, width: 200, height: 20)
        doc.addPart(part)
        let source = """
        on test
          set the progressTotal of progressView "loader" to 0
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let stored = (result.modifiedDocument ?? doc).parts.first { $0.name == "loader" }!.progressTotal
        #expect(stored >= 1e-10)
    }

    @Test("progressLabel clamps to 256 chars via set_part_property")
    func progressLabelCapped() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20"],
            document: &doc, currentCardId: cardId
        )
        let longLabel = String(repeating: "A", count: 500)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "loader", "property": "progresslabel", "value": longLabel],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .progressView }?.progressLabel.count == 256)
    }

    @Test("list_all_properties shows progressView-specific section")
    func listAllProperties() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20",
                        "label": "Syncing"],
            document: &doc, currentCardId: cardId
        )
        let result = await executor.execute(
            toolName: "list_all_properties",
            arguments: ["part_name": "loader"],
            document: &doc, currentCardId: cardId
        )
        // `list_all_properties` is registry-driven (control-property-
        // consistency P2, task 2.3) — the row names are the lowercase
        // canonical dispatch names, with `progresstotal`'s registered
        // `total` alias annotated alongside it. Updated deliberately
        // to the registry output format (task 2.5).
        #expect(result.contains("progressvalue"))
        #expect(result.contains("progresstotal"))
        #expect(result.contains("aliases: progress_total, total"))
        #expect(result.contains("progresscircular"))
        #expect(result.contains("progressindeterminate"))
        #expect(result.contains("Syncing"))
    }
}

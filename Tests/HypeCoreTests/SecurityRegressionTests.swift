import Testing
import Foundation
@testable import HypeCore

// MARK: - Secure field masking (Security condition 2)

/// Pins the secure-field masking logic so future refactors can't
/// silently expose password field contents through the AI or HypeTalk surfaces.
@Suite("Secure field masking — AI tool + HypeTalk + describe surfaces")
struct SecureFieldMaskingTests {

    @Test("get_part_property 'text' on secure field returns '(masked)'")
    func getTextSecureFieldMasked() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .field, cardId: cardId, name: "pwd",
                        left: 0, top: 0, width: 200, height: 30)
        part.textContent = "s3cr3t"
        part.fieldStyle = .secure
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "pwd", "property": "text"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "(masked)")
        #expect(!result.contains("s3cr3t"))
    }

    @Test("get_part_property 'text' on rectangle field returns plaintext")
    func getTextRectangleFieldPlaintext() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .field, cardId: cardId, name: "notes",
                        left: 0, top: 0, width: 200, height: 30)
        part.textContent = "hello world"
        part.fieldStyle = .rectangle
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "notes", "property": "text"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "hello world")
    }

    @Test("list_all_properties on secure field shows (masked) not the actual text")
    func listAllPropertiesSecureMasks() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .field, cardId: cardId, name: "pwd",
                        left: 0, top: 0, width: 200, height: 30)
        part.textContent = "s3cr3t"
        part.fieldStyle = .secure
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "list_all_properties",
            arguments: ["part_name": "pwd"],
            document: &doc, currentCardId: cardId
        )
        #expect(result.contains("(masked)"))
        #expect(!result.contains("s3cr3t"))
    }

    @Test("formatAllProperties (describePartFull path) on secure field hides text")
    func describePartFullSecureMasks() {
        var part = Part(partType: .field, cardId: UUID(), name: "pwd",
                        left: 0, top: 0, width: 200, height: 30)
        part.textContent = "s3cr3t"
        part.fieldStyle = .secure
        let description = HypeToolExecutor.formatAllProperties(part)
        #expect(!description.contains("s3cr3t"))
        #expect(description.contains("(masked)"))
    }

    @Test("get_card_parts on card with secure field hides text")
    func getCardPartsSecureMasks() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .field, cardId: cardId, name: "pwd",
                        left: 0, top: 0, width: 200, height: 30)
        part.textContent = "s3cr3t"
        part.fieldStyle = .secure
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_card_parts",
            arguments: [:],
            document: &doc, currentCardId: cardId
        )
        #expect(!result.contains("s3cr3t"))
    }

    @Test("HypeTalk: `the text of field \"X\"` on secure field returns \"(masked)\"")
    func hypeTalkSecureFieldMasked() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var secureField = Part(partType: .field, cardId: cardId, name: "pwd",
                               left: 0, top: 0, width: 200, height: 30)
        secureField.textContent = "s3cr3t"
        secureField.fieldStyle = .secure
        doc.addPart(secureField)
        // Output field to capture the result
        var outputField = Part(partType: .field, cardId: cardId, name: "output",
                               left: 0, top: 50, width: 200, height: 30)
        outputField.textContent = ""
        doc.addPart(outputField)

        let source = """
        on test
          put the text of field "pwd" into field "output"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let finalDoc = result.modifiedDocument ?? doc
        let outputText = finalDoc.parts.first { $0.name == "output" }?.textContent ?? ""
        #expect(outputText == "(masked)")
        #expect(!outputText.contains("s3cr3t"))
    }
}

// MARK: - PartType.unknown forward-compat filtering (Security condition 4)

/// Pins the forward-compat filtering of unknown part types so a
/// future .hype file with a new part kind doesn't crash older builds.
@Suite("Backward-compat: PartType.unknown filtered on load")
struct BackwardCompatTests {

    @Test("Document with unknown partType raw value decodes; part is filtered out")
    func unknownPartTypeFilteredOnLoad() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        // Add a known part to ensure the array is non-trivially decoded.
        let knownPart = Part(partType: .button, cardId: cardId, name: "btn",
                             left: 0, top: 0, width: 120, height: 40)
        doc.addPart(knownPart)

        // Encode the document, then inject a part with an unknown partType raw value.
        var docDict = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(doc)
        ) as! [String: Any]
        var partsArr = docDict["parts"] as! [[String: Any]]

        // Build a fake part dict that mirrors a real Part but with a future-type raw value.
        var fakePart = partsArr[0]  // clone the known part's structure
        fakePart["partType"] = "futureControlType"
        fakePart["id"] = UUID().uuidString
        fakePart["name"] = "futurePart"
        partsArr.append(fakePart)
        docDict["parts"] = partsArr

        let mutated = try JSONSerialization.data(withJSONObject: docDict)
        // Must not throw.
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: mutated)
        // The future part must have been filtered out.
        #expect(!decoded.parts.contains { $0.name == "futurePart" })
        // The known button must still be present.
        #expect(decoded.parts.contains { $0.name == "btn" })
    }

    @Test("ButtonStyle init(from:) degrades unknown raw value to .standard")
    func buttonStyleDegradesToStandard() throws {
        // Simulate an unknown future ButtonStyle arriving in JSON.
        let json = "\"futureButtonStyleXYZ\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ButtonStyle.self, from: data)
        #expect(decoded == .standard)
    }

    @Test("ButtonStyle init(from:) maps legacy 'radioButton' to .standard")
    func buttonStyleLegacyRadioButton() throws {
        let json = "\"radioButton\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ButtonStyle.self, from: data)
        #expect(decoded == .standard)
    }

    @Test("FieldStyle init(from:) degrades unknown raw value to .rectangle")
    func fieldStyleDegradesToRectangle() throws {
        let json = "\"futureFieldStyleXYZ\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FieldStyle.self, from: data)
        #expect(decoded == .rectangle)
    }

    @Test("ButtonStyle .radio is a valid recognized style")
    func buttonStyleRadioRecognized() throws {
        let json = "\"radio\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ButtonStyle.self, from: data)
        #expect(decoded == .radio)
    }

    @Test("FieldStyle .secure is a valid recognized style")
    func fieldStyleSecureRecognized() throws {
        let json = "\"secure\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FieldStyle.self, from: data)
        #expect(decoded == .secure)
    }
}

// MARK: - Numeric clamp regressions

/// Pins the numeric safety guards so renderers never encounter
/// divide-by-zero or inverted gauge ranges.
@Suite("Numeric clamps — progressTotal >= 1e-10, gaugeMax > gaugeMin")
struct NumericClampTests {

    @Test("progressTotal clamps to >= 1e-10 via create_progressview with total=0")
    func createProgressViewZeroTotal() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20",
                        "total": "0"],
            document: &doc, currentCardId: cardId
        )
        let total = doc.parts.first { $0.partType == .progressView }?.progressTotal ?? 0
        #expect(total >= 1e-10)
    }

    @Test("progressTotal clamps to >= 1e-10 via create_progressview with total=-5")
    func createProgressViewNegativeTotal() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20",
                        "total": "-5"],
            document: &doc, currentCardId: cardId
        )
        let total = doc.parts.first { $0.partType == .progressView }?.progressTotal ?? 0
        #expect(total >= 1e-10)
    }

    @Test("progressValue clamped to [0, total] at create time when value > total")
    func createProgressViewValueExceedsTotal() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "loader", "left": "0", "top": "0", "width": "200", "height": "20",
                        "value": "5", "total": "1"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .progressView }
        #expect((part?.progressValue ?? 0) <= (part?.progressTotal ?? 1))
    }

    @Test("gaugeMax enforces > gaugeMin via create_gauge with max = min")
    func createGaugeMaxEqualMin() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "g", "left": "0", "top": "0", "width": "200", "height": "44",
                        "min": "10", "max": "10"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .gauge }
        #expect((part?.gaugeMax ?? 0) > (part?.gaugeMin ?? 0))
    }

    @Test("gaugeMax enforces > gaugeMin via create_gauge with max < min")
    func createGaugeMaxLessThanMin() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "g", "left": "0", "top": "0", "width": "200", "height": "44",
                        "min": "10", "max": "5"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .gauge }
        #expect((part?.gaugeMax ?? 0) > (part?.gaugeMin ?? 0))
    }

    @Test("gaugeValue clamped to [gaugeMin, gaugeMax] on set via AI")
    func gaugeValueClamped() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "g", "left": "0", "top": "0", "width": "200", "height": "44",
                        "min": "0", "max": "1"],
            document: &doc, currentCardId: cardId
        )
        // Attempt to set value beyond max
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "g", "property": "gaugevalue", "value": "999"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .gauge }
        let val = part?.gaugeValue ?? 0
        let max = part?.gaugeMax ?? 1
        #expect(val <= max)
    }
}

// MARK: - Length cap regressions

/// Pins the length caps so user-supplied data can't bloat document size.
@Suite("Length caps — menuItems 64KB, searchText 1KB, gaugeLabel 256 chars")
struct LengthCapTests {

    // menuItems / searchText length-cap tests removed — the
    // standalone .menu and .searchField PartTypes are gone (dedup
    // collapsed them into ButtonStyle.popup and FieldStyle.search).
    // The setter-side caps still exist on the underlying fields
    // (menuItems / searchText) for parts whose pre-migration form
    // had them populated; we just no longer create new parts of
    // those types via AI tools.

    @Test("gaugeLabel clamps to 256 chars via set_part_property")
    func gaugeLabelCapViaAI() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_gauge",
            arguments: ["name": "g", "left": "0", "top": "0", "width": "200", "height": "44"],
            document: &doc, currentCardId: cardId
        )
        let longLabel = String(repeating: "L", count: 500)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "g", "property": "gauge_label", "value": longLabel],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .gauge }?.gaugeLabel.count == 256)
    }

    @Test("progressLabel clamps to 256 chars via set_part_property")
    func progressLabelCapViaAI() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_progressview",
            arguments: ["name": "p", "left": "0", "top": "0", "width": "200", "height": "20"],
            document: &doc, currentCardId: cardId
        )
        let longLabel = String(repeating: "L", count: 500)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "p", "property": "progresslabel", "value": longLabel],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .progressView }?.progressLabel.count == 256)
    }
}

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

// MARK: - Registry-driven masking law (control-property-consistency, Security condition 1)

/// Sets the underlying model field a `secureMasked` descriptor reads,
/// so the test below can drive an arbitrary masked descriptor without
/// a hand-maintained per-property switch of its own.
///
/// Returns `false` when `canonical` isn't a recognized secureMasked
/// descriptor, so the caller can fail loudly instead of silently
/// skipping a newly-added masked descriptor this seeder doesn't know
/// how to prime yet.
private func seedSecureMaskedField(canonical: String, into part: inout Part) -> Bool {
    switch canonical {
    case "textcontent": part.textContent = "s3cr3t-text"
    case "htmlcontent": part.htmlContent = "s3cr3t-html"
    case "searchtext": part.searchText = "s3cr3t-search"
    default: return false
    }
    return true
}

/// Pins Security condition 1 (the masking law) STRUCTURALLY: it walks
/// `PartPropertyRegistry.secureMaskedDescriptors` — every descriptor
/// flagged `secureMasked` — rather than a hand-listed set of property
/// names, so a future masked field is caught by test *shape*: add a
/// descriptor with `secureMasked: true` and this suite immediately
/// exercises every one of its aliases against a `.secure` field,
/// without anyone remembering to touch this test file.
@Suite("Registry-driven masking law — every secureMasked descriptor, every alias", .serialized)
struct RegistryDrivenMaskingLawTests {
    @Test("secureMasked descriptor set is exactly {textContent, htmlContent, searchText}")
    func secureMaskedSetIsTheDocumentedThree() {
        let names = Set(PartPropertyRegistry.secureMaskedDescriptors.map(\.canonical))
        #expect(names == ["textcontent", "htmlcontent", "searchtext"])
    }

    @Test(
        "every alias of every secureMasked descriptor returns \"(masked)\" on a .secure field, via HypeTalk GET",
        arguments: PartPropertyRegistry.secureMaskedDescriptors.flatMap { descriptor in
            ([descriptor.canonical] + descriptor.aliases).map { (descriptor.canonical, $0) }
        }
    )
    func everyAliasIsMasked(canonical: String, alias: String) async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var secureField = Part(partType: .field, cardId: cardId, name: "pwd",
                               left: 0, top: 0, width: 200, height: 30)
        secureField.fieldStyle = .secure
        guard seedSecureMaskedField(canonical: canonical, into: &secureField) else {
            Issue.record("no test seeder registered for secureMasked descriptor '\(canonical)' — add one to seedSecureMaskedField(canonical:into:)")
            return
        }
        doc.addPart(secureField)
        let outputField = Part(partType: .field, cardId: cardId, name: "output",
                               left: 0, top: 50, width: 200, height: 30)
        doc.addPart(outputField)
        doc.cards[0].script = """
        on openCard
          put the \(alias) of field "pwd" into field "output"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "'\(alias)' script error: \(result.error?.message ?? "")")
        let outputText = result.modifiedDocument?.parts.first { $0.name == "output" }?.textContent ?? ""
        #expect(outputText == "(masked)", "alias '\(alias)' of descriptor '\(canonical)' did not mask: got '\(outputText)'")
    }

    @Test("a non-secure (rectangle) field still reads plaintext through every secureMasked alias")
    func nonSecureFieldStaysPlaintext() async {
        for descriptor in PartPropertyRegistry.secureMaskedDescriptors {
            var doc = HypeDocument.newDocument(name: "Test")
            let cardId = doc.cards[0].id
            var field = Part(partType: .field, cardId: cardId, name: "notes",
                             left: 0, top: 0, width: 200, height: 30)
            field.fieldStyle = .rectangle
            guard seedSecureMaskedField(canonical: descriptor.canonical, into: &field) else { continue }
            doc.addPart(field)
            let outputField = Part(partType: .field, cardId: cardId, name: "output",
                                   left: 0, top: 50, width: 200, height: 30)
            doc.addPart(outputField)
            doc.cards[0].script = """
            on openCard
              put the \(descriptor.canonical) of field "notes" into field "output"
            end openCard
            """
            let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
                message: "openCard", params: [], targetId: cardId,
                document: doc, currentCardId: cardId
            ) }
            #expect(result.status == .completed, "'\(descriptor.canonical)' script error: \(result.error?.message ?? "")")
            let outputText = result.modifiedDocument?.parts.first { $0.name == "output" }?.textContent ?? ""
            #expect(outputText != "(masked)", "'\(descriptor.canonical)' must not mask a non-secure field")
        }
    }

    /// `value` is deliberately NOT a literal alias of the `textContent`
    /// descriptor (it's a bare polymorphic word that the registry
    /// remaps to the `textcontent` canonical only when the target is
    /// a field) — Condition 1 names it explicitly as the property that
    /// bypassed masking before this change (HypeToolExecutor.swift
    /// 3827-3835 / Interpreter.swift 5667-5677, pre-fix), so it gets
    /// its own direct test rather than relying on the alias-list walk
    /// above to happen to cover it.
    @Test("`value` of a .secure field masks too (Security Finding 1 — the exact bypass this change closes)")
    func valueAliasIsMaskedOnSecureField() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var secureField = Part(partType: .field, cardId: cardId, name: "pwd",
                               left: 0, top: 0, width: 200, height: 30)
        secureField.fieldStyle = .secure
        secureField.textContent = "s3cr3t-value"
        doc.addPart(secureField)
        let outputField = Part(partType: .field, cardId: cardId, name: "output",
                               left: 0, top: 50, width: 200, height: 30)
        doc.addPart(outputField)
        doc.cards[0].script = """
        on openCard
          put the value of field "pwd" into field "output"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let outputText = result.modifiedDocument?.parts.first { $0.name == "output" }?.textContent ?? ""
        #expect(outputText == "(masked)")
        #expect(!outputText.contains("s3cr3t-value"))
    }
}

// MARK: - Registry-driven masking law, AI getter (control-property-consistency P2)
//
// `RegistryDrivenMaskingLawTests` above pins the law through HypeTalk's
// `MessageDispatcher`. Condition 1 (as amended for P2) requires the
// SAME structural guarantee on the AI surface's `get_part_property` —
// `value`/`htmlContent`/`searchText` bypassed masking there before this
// change (HypeToolExecutor.swift ~3827/3988, plus htmlContent having no
// AI getter at all). This suite walks the identical registry-driven
// alias list through `HypeToolExecutor.execute` instead of a script.
@Suite("Registry-driven masking law — AI getter, every secureMasked descriptor, every alias", .serialized)
struct RegistryDrivenMaskingLawAITests {
    @Test(
        "every alias of every secureMasked descriptor returns \"(masked)\" on a .secure field, via get_part_property",
        arguments: PartPropertyRegistry.secureMaskedDescriptors.flatMap { descriptor in
            ([descriptor.canonical] + descriptor.aliases).map { (descriptor.canonical, $0) }
        }
    )
    func everyAliasIsMaskedViaAIGetter(canonical: String, alias: String) async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var secureField = Part(partType: .field, cardId: cardId, name: "pwd",
                               left: 0, top: 0, width: 200, height: 30)
        secureField.fieldStyle = .secure
        guard seedSecureMaskedField(canonical: canonical, into: &secureField) else {
            Issue.record("no test seeder registered for secureMasked descriptor '\(canonical)' — add one to seedSecureMaskedField(canonical:into:)")
            return
        }
        doc.addPart(secureField)
        let result = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "pwd", "property": alias],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "(masked)", "alias '\(alias)' of descriptor '\(canonical)' did not mask via get_part_property: got '\(result)'")
    }

    @Test("a non-secure (rectangle) field still reads plaintext through get_part_property for every secureMasked alias")
    func nonSecureFieldStaysPlaintextViaAIGetter() async {
        for descriptor in PartPropertyRegistry.secureMaskedDescriptors {
            var doc = HypeDocument.newDocument(name: "Test")
            let cardId = doc.cards[0].id
            var field = Part(partType: .field, cardId: cardId, name: "notes",
                             left: 0, top: 0, width: 200, height: 30)
            field.fieldStyle = .rectangle
            guard seedSecureMaskedField(canonical: descriptor.canonical, into: &field) else { continue }
            doc.addPart(field)
            let result = await HypeToolExecutor().execute(
                toolName: "get_part_property",
                arguments: ["part_name": "notes", "property": descriptor.canonical],
                document: &doc, currentCardId: cardId
            )
            #expect(result != "(masked)", "'\(descriptor.canonical)' must not mask a non-secure field via get_part_property")
        }
    }

    /// `value` on the AI surface (Security Finding 1's exact bypass —
    /// HypeToolExecutor.swift's OLD `case "value"` branch read
    /// `part.textContent` directly, ignoring the mask below it) gets
    /// its own direct test for the same reason the HypeTalk suite does.
    @Test("`value` of a .secure field masks via get_part_property (Security Finding 1 — the exact AI bypass this change closes)")
    func valueMasksViaAIGetter() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var secureField = Part(partType: .field, cardId: cardId, name: "pwd",
                               left: 0, top: 0, width: 200, height: 30)
        secureField.fieldStyle = .secure
        secureField.textContent = "s3cr3t-value"
        doc.addPart(secureField)
        let result = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "pwd", "property": "value"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "(masked)")
        #expect(!result.contains("s3cr3t-value"))
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

    @Test("ButtonStyle init(from:) maps legacy 'radioButton' to .radio")
    func buttonStyleLegacyRadioButton() throws {
        // Older Hype builds had a `.radioButton` enum case that was
        // later renamed to `.radio`. The migration table in
        // `ButtonStyle.resolved(rawOrAlias:)` maps the legacy raw
        // value back to its modern equivalent so older `.hype` files
        // still load with the correct radio-circle rendering.
        //
        // This previously mapped to `.standard` (a filled rectangle),
        // which was a bug — radio buttons would silently morph into
        // rectangles after a save/reload round-trip. Fixed in the
        // duplicate-styles cleanup.
        let json = "\"radioButton\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ButtonStyle.self, from: data)
        #expect(decoded == .radio)
    }

    @Test("ButtonStyle init(from:) maps legacy 'rectangle' to .standard")
    func buttonStyleLegacyRectangle() throws {
        // `.rectangle` was a duplicate of `.standard` (byte-identical
        // renderer code) and has been removed. The migration alias
        // keeps older `.hype` files loading cleanly without changing
        // their visual appearance.
        let json = "\"rectangle\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ButtonStyle.self, from: data)
        #expect(decoded == .standard)
    }

    @Test("ButtonStyle init(from:) maps legacy 'switch' to .toggle")
    func buttonStyleLegacySwitch() throws {
        // `.switch` was a duplicate of `.toggle` and has been removed.
        let json = "\"switch\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ButtonStyle.self, from: data)
        #expect(decoded == .toggle)
    }

    @Test("FieldStyle init(from:) maps legacy 'opaque' to .rectangle")
    func fieldStyleLegacyOpaque() throws {
        // `.opaque` was a duplicate of `.rectangle` (same renderer
        // code) and has been removed. The migration alias preserves
        // older `.hype` files.
        let json = "\"opaque\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FieldStyle.self, from: data)
        #expect(decoded == .rectangle)
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

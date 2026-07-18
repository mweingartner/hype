import Testing
import Foundation
@testable import HypeCore

// Structural conformance tests for `PartPropertyRegistry`
// (`control-property-consistency` design.md Decision 1, test plan
// items 1/2). These tests exercise the registry's own data — alias
// uniqueness, alias symmetry, applicability shape — independent of
// the interpreter switches; `PartPropertyDispatchTests.swift` covers
// end-to-end HypeTalk dispatch through the registry gate.

@Suite("PartPropertyRegistry — alias uniqueness and shape")
struct PartPropertyRegistryStructureTests {
    @Test("no two descriptors share a canonical name or alias")
    func aliasUniqueness() {
        var seen: [String: String] = [:]
        var collisions: [String] = []
        for descriptor in PartPropertyRegistry.descriptors {
            for key in [descriptor.canonical] + descriptor.aliases {
                if let owner = seen[key], owner != descriptor.canonical {
                    collisions.append("'\(key)' claimed by both '\(owner)' and '\(descriptor.canonical)'")
                } else {
                    seen[key] = descriptor.canonical
                }
            }
        }
        #expect(collisions.isEmpty, "Alias collisions: \(collisions.joined(separator: "; "))")
    }

    @Test("every descriptor has a non-empty canonical name and doc summary")
    func descriptorsAreDocumented() {
        for descriptor in PartPropertyRegistry.descriptors {
            #expect(!descriptor.canonical.isEmpty)
            #expect(!descriptor.docSummary.isEmpty, "\(descriptor.canonical) has no docSummary")
            // Canonical/aliases are always the lowercase dispatch key —
            // the switches key on exactly this casing.
            #expect(descriptor.canonical == descriptor.canonical.lowercased())
            for alias in descriptor.aliases {
                #expect(alias == alias.lowercased(), "\(descriptor.canonical) alias '\(alias)' is not lowercase")
            }
        }
    }

    @Test("readOnly descriptors always resolveSet to .readOnly, regardless of part type")
    func readOnlyAlwaysReadOnly() {
        let readOnlyDescriptors = PartPropertyRegistry.descriptors.filter { $0.mutability == .readOnly }
        #expect(!readOnlyDescriptors.isEmpty)
        for descriptor in readOnlyDescriptors {
            for type in PartType.allCases {
                var part = Part(partType: type, name: "x")
                part.fieldStyle = .rectangle
                let resolution = PartPropertyRegistry.resolveSet(descriptor.canonical, for: part)
                guard case .readOnly = resolution else {
                    Issue.record("\(descriptor.canonical) on \(type) resolved to \(resolution), expected .readOnly")
                    continue
                }
            }
        }
    }

    @Test("noOpStub descriptors always resolveSet to .noOp, regardless of part type")
    func noOpStubAlwaysNoOp() {
        let stubDescriptors = PartPropertyRegistry.descriptors.filter { $0.mutability == .noOpStub }
        // The 11 classic field props + scroll/scrollpos (Condition 3).
        #expect(stubDescriptors.count == 12, "expected 12 no-op stubs, found \(stubDescriptors.count)")
        for descriptor in stubDescriptors {
            for type in [PartType.button, .field, .shape, .gauge] {
                let part = Part(partType: type, name: "x")
                let resolution = PartPropertyRegistry.resolveSet(descriptor.canonical, for: part)
                guard case .noOp = resolution else {
                    Issue.record("\(descriptor.canonical) on \(type) resolved to \(resolution), expected .noOp")
                    continue
                }
            }
        }
    }

    @Test("secureMasked descriptors are exactly textContent, htmlContent, searchText")
    func secureMaskedSetIsComplete() {
        let masked = Set(PartPropertyRegistry.secureMaskedDescriptors.map(\.canonical))
        #expect(masked == ["textcontent", "htmlcontent", "searchtext"])
    }
}

@Suite("PartPropertyRegistry — round-trip law")
struct PartPropertyRegistryRoundTripTests {
    /// `set the <alias> of <part> to <value>` then `get the <alias> of
    /// <part>` returns `value` — the round-trip law (mock acceptance
    /// criterion 1), spot-checked across representative descriptors of
    /// every `ValueKind`, both through their canonical name and an alias.
    private func roundTrip(
        partType: PartType,
        property: String,
        value: String,
        expectedGet: String? = nil,
        setup: ((inout Part) -> Void)? = nil
    ) async -> (ok: Bool, got: String, error: String?) {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: partType, cardId: cardId, name: "p1", left: 0, top: 0, width: 100, height: 40)
        setup?(&part)
        doc.addPart(part)
        let out = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 60, width: 100, height: 40)
        doc.addPart(out)
        let typeWord = partType.rawValue.lowercased()
        // `name` is special: the SET renames the part's own lookup
        // identifier, so the follow-up GET must address it by the
        // NEW name — every other property leaves "p1" resolvable.
        let readIdentifier = property == "name" ? value : "p1"
        doc.cards[0].script = """
        on openCard
          set the \(property) of \(typeWord) "p1" to "\(value)"
          put the \(property) of \(typeWord) "\(readIdentifier)" into field "out"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        let got = result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent ?? ""
        let expected = expectedGet ?? value
        return (result.status == .completed && got == expected, got, result.error?.message)
    }

    @Test("string kind: name round-trips")
    func stringRoundTrip() async {
        let r = await roundTrip(partType: .field, property: "name", value: "renamed")
        #expect(r.ok, "got '\(r.got)', error: \(r.error ?? "none")")
    }

    @Test("number kind: gaugeMin round-trips")
    func numberRoundTrip() async {
        let r = await roundTrip(partType: .gauge, property: "gaugemin", value: "5")
        #expect(r.ok, "got '\(r.got)', error: \(r.error ?? "none")")
    }

    @Test("boolean kind: visible round-trips")
    func booleanRoundTrip() async {
        let r = await roundTrip(partType: .button, property: "visible", value: "false")
        #expect(r.ok, "got '\(r.got)', error: \(r.error ?? "none")")
    }

    @Test("color kind: fillColor normalizes to #UPPER")
    func colorRoundTrip() async {
        let r = await roundTrip(partType: .shape, property: "fillcolor", value: "#ff00aa", expectedGet: "#FF00AA")
        #expect(r.ok, "got '\(r.got)', error: \(r.error ?? "none")")
    }

    @Test("gaugeTint alias round-trips through the bare `tint` polymorphic word")
    func tintAliasRoundTrip() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let gauge = Part(partType: .gauge, cardId: cardId, name: "g1", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(gauge)
        let out = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 60, width: 100, height: 40)
        doc.addPart(out)
        doc.cards[0].script = """
        on openCard
          set the tint of gauge "g1" to "#112233"
          put the tint of gauge "g1" into field "out"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let got = result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent
        #expect(got == "#112233")
    }

    @Test("size pair round-trips: set \"w,h\" then get returns \"w,h\"")
    func sizePairRoundTrip() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let shape = Part(partType: .shape, cardId: cardId, name: "s1", left: 0, top: 0, width: 10, height: 10)
        doc.addPart(shape)
        let out = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 60, width: 100, height: 40)
        doc.addPart(out)
        doc.cards[0].script = """
        on openCard
          set the size of shape "s1" to "200,150"
          put the size of shape "s1" into field "out"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let out2 = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out2?.textContent == "200,150")
        let shape2 = result.modifiedDocument?.parts.first { $0.name == "s1" }
        #expect(shape2?.width == 200)
        #expect(shape2?.height == 150)
    }
}

// MARK: - AI round-trip law (control-property-consistency P2)
//
// The HypeTalk half above proves the registry gate round-trips
// through `MessageDispatcher`; this suite drives the SAME scenarios
// through `HypeToolExecutor.execute` to prove the AI tool surface
// round-trips identically through the shared registry (mock §3:
// "one shared registry drives both").

@Suite("PartPropertyRegistry — AI round-trip law")
struct PartPropertyRegistryAIRoundTripTests {
    private func aiRoundTrip(
        partType: PartType,
        property: String,
        value: String,
        expectedGet: String? = nil,
        setup: ((inout Part) -> Void)? = nil
    ) async -> (ok: Bool, got: String, setResult: String) {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: partType, cardId: cardId, name: "p1", left: 0, top: 0, width: 100, height: 40)
        setup?(&part)
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let setResult = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "p1", "property": property, "value": value],
            document: &doc, currentCardId: cardId
        )
        let readIdentifier = property == "name" ? value : "p1"
        let got = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": readIdentifier, "property": property],
            document: &doc, currentCardId: cardId
        )
        let expected = expectedGet ?? value
        return (got == expected, got, setResult)
    }

    @Test("string kind: name round-trips")
    func stringRoundTrip() async {
        let r = await aiRoundTrip(partType: .field, property: "name", value: "renamed")
        #expect(r.ok, "got '\(r.got)', set result: \(r.setResult)")
    }

    @Test("number kind: gaugeMin round-trips")
    func numberRoundTrip() async {
        // The AI surface's established numeric convention is Swift's
        // plain `String(Double)` (not HypeTalk's trailing-zero-trimmed
        // `formatNumber`) — "5" round-trips to "5.0", not "5". This
        // reflects existing AI GET behavior for every other plain
        // numeric case (strokeWidth, mapSpan, musicVolume, …), so the
        // expectation here is the value's Double representation.
        let r = await aiRoundTrip(partType: .gauge, property: "gaugemin", value: "5", expectedGet: "5.0")
        #expect(r.ok, "got '\(r.got)', set result: \(r.setResult)")
    }

    @Test("boolean kind: visible round-trips")
    func booleanRoundTrip() async {
        let r = await aiRoundTrip(partType: .button, property: "visible", value: "false")
        #expect(r.ok, "got '\(r.got)', set result: \(r.setResult)")
    }

    @Test("color kind: fillColor normalizes to #UPPER")
    func colorRoundTrip() async {
        let r = await aiRoundTrip(partType: .shape, property: "fillcolor", value: "#ff00aa", expectedGet: "#FF00AA")
        #expect(r.ok, "got '\(r.got)', set result: \(r.setResult)")
    }

    @Test("pair kind: size round-trips")
    func sizeRoundTrip() async {
        let r = await aiRoundTrip(partType: .shape, property: "size", value: "200,150")
        #expect(r.ok, "got '\(r.got)', set result: \(r.setResult)")
    }

    @Test("gaugeTint alias round-trips through the bare `tint` polymorphic word")
    func tintAliasRoundTrip() async {
        let r = await aiRoundTrip(partType: .gauge, property: "tint", value: "#112233")
        #expect(r.ok, "got '\(r.got)', set result: \(r.setResult)")
    }
}

// MARK: - list_all_properties two-direction diff vs the registry (A1, Condition 15)
//
// `formatAllProperties` (task 2.3) is registry-driven; these tests are
// the mechanical enforcement of "zero missing, zero phantom" per part
// type, walking every `PartType` rather than a hand-picked sample —
// exactly the failure mode a hand-maintained dump used to hide.

@Suite("list_all_properties — two-direction diff vs the registry")
struct ListAllPropertiesRegistryDiffTests {
    /// Mirrors `formatAllProperties`'s own private `belongs(_:)`
    /// filter: a descriptor "belongs" to `type` for LISTING purposes
    /// when its SET applicability (falling back to GET applicability)
    /// names a restricted type set; a descriptor with no restriction
    /// at all is universal and always belongs.
    private func belongs(_ descriptor: PartPropertyRegistry.Descriptor, to type: PartType) -> Bool {
        guard let applicability = descriptor.setApplicability ?? descriptor.getApplicability else {
            return true
        }
        return applicability.types.contains(type)
    }

    private static let realTypes: [PartType] = PartType.allCases.filter { $0 != .unknown }

    @Test(
        "every aiExposed, non-legacy, applicable descriptor's canonical name is a row in list_all_properties",
        arguments: ListAllPropertiesRegistryDiffTests.realTypes
    )
    func noMissingDescriptors(type: PartType) {
        let part = Part(partType: type, name: "x")
        let output = HypeToolExecutor.formatAllProperties(part)
        let expected = PartPropertyRegistry.descriptors.filter { $0.aiExposed && !$0.legacy && belongs($0, to: type) }
        for descriptor in expected {
            #expect(output.contains("\n\(descriptor.canonical) ="), "\(type.rawValue): missing '\(descriptor.canonical)' from list_all_properties")
        }
    }

    @Test(
        "every legacy descriptor applicable to the type is named under the Legacy note, without a value",
        arguments: ListAllPropertiesRegistryDiffTests.realTypes
    )
    func legacyDescriptorsNamedWithoutValues(type: PartType) {
        let part = Part(partType: type, name: "x")
        let output = HypeToolExecutor.formatAllProperties(part)
        let legacy = PartPropertyRegistry.descriptors.filter { $0.legacy && belongs($0, to: type) }
        guard !legacy.isEmpty else { return }
        #expect(output.contains("## Legacy / not scriptable"), "\(type.rawValue): expected a Legacy note")
        for descriptor in legacy {
            #expect(output.contains(descriptor.canonical), "\(type.rawValue): missing legacy name '\(descriptor.canonical)'")
            // Named under the note, never as a "name = value" row.
            #expect(!output.contains("\n\(descriptor.canonical) ="), "\(type.rawValue): legacy '\(descriptor.canonical)' leaked a value row")
        }
    }

    @Test(
        "no phantom rows: every row's canonical name resolves through the registry for this part type",
        arguments: ListAllPropertiesRegistryDiffTests.realTypes
    )
    func noPhantomRows(type: PartType) {
        var part = Part(partType: type, name: "x")
        if type == .chart {
            // A populated chart actually exercises the "## Chart-
            // specific" exclusion below (an empty chartData produces
            // no chart-specific rows at all, which would let a broken
            // exclusion pass by accident).
            part.chartData = ChartConfig().toJSON()
        }
        let output = HypeToolExecutor.formatAllProperties(part)
        // "## Chart-specific" rows are a DOCUMENTED exception (Condition
        // 12): chart sub-properties (title, spider colors, …) are
        // handled by `chartPropertyValue`/`applyChartProperty`
        // entirely OUTSIDE the registry, so they never resolve through
        // `PartPropertyRegistry` — only `chartdata` (in "## Type-
        // specific") does.
        var inChartSpecificSection = false
        let rowNames: [String] = output.split(separator: "\n").compactMap { line -> String? in
            if line.hasPrefix("## ") {
                inChartSpecificSection = (line == "## Chart-specific")
                return nil
            }
            guard !inChartSpecificSection, !line.hasPrefix("#"), let range = line.range(of: " = ") else { return nil }
            return String(line[line.startIndex..<range.lowerBound])
        }
        #expect(!rowNames.isEmpty, "\(type.rawValue): expected at least one property row")
        for name in rowNames {
            guard case .property = PartPropertyRegistry.resolveGet(name, for: part) else {
                Issue.record("\(type.rawValue): row '\(name)' does not resolve through the registry")
                continue
            }
        }
    }

    @Test("secure field masks textContent in list_all_properties")
    func secureFieldMasksInListAllProperties() {
        var field = Part(partType: .field, name: "pwd")
        field.fieldStyle = .secure
        field.textContent = "s3cr3t"
        let output = HypeToolExecutor.formatAllProperties(field)
        #expect(output.contains("(masked)"))
        #expect(!output.contains("s3cr3t"))
    }

    /// Chart sub-properties (title, spider colors, …) are handled by
    /// `chartPropertyValue`/`applyChartProperty`, NOT the registry
    /// (Condition 12) — only `chartdata` is a registry descriptor.
    /// `list_all_properties` must still surface them (a genuine gap
    /// the first registry-driven rewrite introduced and this test
    /// pins against regressing again) via a dedicated "## Chart-
    /// specific" section, through the SAME reader `get_part_property`
    /// uses.
    @Test("chart-specific properties (title, spider colors, …) still appear in list_all_properties")
    func chartSpecificPropertiesAppear() {
        var chart = Part(partType: .chart, name: "Sales")
        var config = ChartConfig()
        config.title = "Q3 Revenue"
        config.chartType = .bar
        chart.chartData = config.toJSON()
        let output = HypeToolExecutor.formatAllProperties(chart)
        #expect(output.contains("## Chart-specific"))
        #expect(output.contains("charttitle = Q3 Revenue"))
        #expect(output.contains("charttype = bar"))
        #expect(output.contains("x_axis_label"))
        #expect(output.contains("spider_grid_color"))
    }
}

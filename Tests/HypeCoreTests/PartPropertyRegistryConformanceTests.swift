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

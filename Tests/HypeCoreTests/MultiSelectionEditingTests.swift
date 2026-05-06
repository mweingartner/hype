import Testing
import Foundation
@testable import HypeCore

@Suite("MultiSelectionEditing — common-value + bulk-apply across a part selection")
struct MultiSelectionEditingTests {

    // MARK: - commonValue

    @Test("Empty input yields nil")
    func commonValueEmpty() {
        let parts: [Part] = []
        let result = MultiSelectionEditing.commonValue(in: parts, for: \.width)
        #expect(result == nil)
    }

    @Test("Single part yields its own value")
    func commonValueSingle() {
        let p = Part(partType: .button, name: "a", left: 0, top: 0, width: 100, height: 40)
        let result = MultiSelectionEditing.commonValue(in: [p], for: \.width)
        #expect(result == 100)
    }

    @Test("All parts agree → returns the shared value")
    func commonValueAllAgree() {
        let parts = [
            Part(partType: .button, name: "a", left: 0, top: 0, width: 80, height: 40),
            Part(partType: .button, name: "b", left: 0, top: 0, width: 80, height: 40),
            Part(partType: .button, name: "c", left: 0, top: 0, width: 80, height: 40),
        ]
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.width) == 80)
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.height) == 40)
    }

    @Test("Any disagreement → returns nil")
    func commonValueAnyDisagreement() {
        let parts = [
            Part(partType: .button, name: "a", left: 0, top: 0, width: 80, height: 40),
            Part(partType: .button, name: "b", left: 0, top: 0, width: 100, height: 40),  // different width
            Part(partType: .button, name: "c", left: 0, top: 0, width: 80, height: 40),
        ]
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.width) == nil)
        // Heights all agree → still returns 40.
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.height) == 40)
    }

    @Test("Disagreement on the first two parts short-circuits without scanning the rest")
    func commonValueShortCircuits() {
        // Construct a 1000-part list where the first two disagree.
        // The implementation should bail on the second read; we
        // can't directly observe that, but we can verify it returns
        // the right answer in a single test that also doubles as a
        // soft latency check.
        var parts: [Part] = []
        parts.append(Part(partType: .button, name: "a", left: 0, top: 0, width: 80, height: 40))
        parts.append(Part(partType: .button, name: "b", left: 0, top: 0, width: 100, height: 40))
        for _ in 0..<998 {
            parts.append(Part(partType: .button, name: "x", left: 0, top: 0, width: 80, height: 40))
        }
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.width) == nil)
    }

    @Test("commonValue works for String properties (textFont)")
    func commonValueStringProperty() {
        var parts = [
            Part(partType: .field, name: "a"),
            Part(partType: .field, name: "b"),
        ]
        // Force a specific font on both so the test doesn't depend
        // on whatever default the Part initializer happens to pick.
        parts[0].textFont = "Helvetica"
        parts[1].textFont = "Helvetica"
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.textFont) == "Helvetica")

        var modified = parts
        modified[1].textFont = "Menlo"
        #expect(MultiSelectionEditing.commonValue(in: modified, for: \.textFont) == nil)
    }

    @Test("commonValue works for Bool properties (visible)")
    func commonValueBoolProperty() {
        var parts = [
            Part(partType: .button, name: "a"),
            Part(partType: .button, name: "b"),
        ]
        // Default visible is true for both.
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.visible) == true)

        parts[1].visible = false
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.visible) == nil)

        parts[0].visible = false
        #expect(MultiSelectionEditing.commonValue(in: parts, for: \.visible) == false)
    }

    // MARK: - applyValue

    @Test("applyValue mutates only the selected ids, leaving others alone")
    func applyValueScopedToSelection() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var a = Part(partType: .button, cardId: cardId, name: "A", left: 0, top: 0, width: 80, height: 40)
        var b = Part(partType: .button, cardId: cardId, name: "B", left: 0, top: 0, width: 80, height: 40)
        var c = Part(partType: .button, cardId: cardId, name: "C", left: 0, top: 0, width: 80, height: 40)
        doc.addPart(a); doc.addPart(b); doc.addPart(c)
        let aId = a.id; let bId = b.id; let cId = c.id

        // Select only A and C; bulk-set width to 200.
        let count = MultiSelectionEditing.applyValue(
            200.0,
            to: \.width,
            in: &doc,
            for: [aId, cId]
        )
        #expect(count == 2)
        #expect(doc.parts.first(where: { $0.id == aId })?.width == 200)
        #expect(doc.parts.first(where: { $0.id == bId })?.width == 80)   // untouched
        #expect(doc.parts.first(where: { $0.id == cId })?.width == 200)

        // Suppress unused warning for the `var` (we reuse the
        // captured ids; the local copies were just for setup).
        _ = a; _ = b; _ = c
    }

    @Test("applyValue silently skips ids that don't resolve to a part")
    func applyValueIgnoresUnknownIds() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var p = Part(partType: .button, cardId: cardId, name: "P", left: 0, top: 0, width: 80, height: 40)
        doc.addPart(p)
        let pId = p.id

        let count = MultiSelectionEditing.applyValue(
            123.0,
            to: \.height,
            in: &doc,
            for: [pId, UUID(), UUID()]   // 2 unknown ids
        )
        #expect(count == 1)
        #expect(doc.parts.first(where: { $0.id == pId })?.height == 123)

        _ = p
    }

    @Test("applyValue works for String properties")
    func applyValueStringProperty() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var a = Part(partType: .field, cardId: cardId, name: "A")
        var b = Part(partType: .field, cardId: cardId, name: "B")
        doc.addPart(a); doc.addPart(b)
        let aId = a.id; let bId = b.id

        MultiSelectionEditing.applyValue(
            "Menlo",
            to: \.textFont,
            in: &doc,
            for: [aId, bId]
        )
        #expect(doc.parts.first(where: { $0.id == aId })?.textFont == "Menlo")
        #expect(doc.parts.first(where: { $0.id == bId })?.textFont == "Menlo")

        _ = a; _ = b
    }

    // MARK: - Generic commonValue: works on HypeNodeSpec too

    @Test("commonValue is generic over the element type — works on HypeNodeSpec")
    func commonValueOnSceneNodes() {
        var n1 = HypeNodeSpec(name: "a", nodeType: .sprite, position: PointSpec(x: 100, y: 50))
        var n2 = HypeNodeSpec(name: "b", nodeType: .sprite, position: PointSpec(x: 100, y: 50))
        var n3 = HypeNodeSpec(name: "c", nodeType: .sprite, position: PointSpec(x: 100, y: 50))
        // All three share x=100, y=50.
        let nodes = [n1, n2, n3]
        #expect(MultiSelectionEditing.commonValue(in: nodes, for: \.position.x) == 100)
        #expect(MultiSelectionEditing.commonValue(in: nodes, for: \.position.y) == 50)
        // Diverge on rotation; same nodeType.
        n1.rotation = 0
        n2.rotation = 90
        n3.rotation = 0
        let rotNodes = [n1, n2, n3]
        #expect(MultiSelectionEditing.commonValue(in: rotNodes, for: \.rotation) == nil)
        #expect(MultiSelectionEditing.commonValue(in: rotNodes, for: \.nodeType) == .sprite)
    }

    @Test("commonValue works on optional KeyPaths (HypeNodeSpec.fontSize, .text)")
    func commonValueOptionalProperties() {
        var n1 = HypeNodeSpec(name: "a", nodeType: .label, position: PointSpec(x: 0, y: 0))
        n1.text = "Hi"
        n1.fontSize = 14
        var n2 = HypeNodeSpec(name: "b", nodeType: .label, position: PointSpec(x: 0, y: 0))
        n2.text = "Hi"
        n2.fontSize = 14
        // Both labels with text="Hi", fontSize=14.
        #expect(MultiSelectionEditing.commonValue(in: [n1, n2], for: \.text) == "Hi")
        #expect(MultiSelectionEditing.commonValue(in: [n1, n2], for: \.fontSize) == 14)
        // One has nil fontSize → values differ → nil.
        n2.fontSize = nil
        #expect(MultiSelectionEditing.commonValue(in: [n1, n2], for: \.fontSize) == nil)
    }

    @Test("applyValue + commonValue round-trip: differing selection becomes uniform after apply")
    func applyAndRecheckCommonValue() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var a = Part(partType: .button, cardId: cardId, name: "A", left: 0, top: 0, width: 80, height: 40)
        var b = Part(partType: .button, cardId: cardId, name: "B", left: 0, top: 0, width: 100, height: 40)
        var c = Part(partType: .button, cardId: cardId, name: "C", left: 0, top: 0, width: 120, height: 40)
        doc.addPart(a); doc.addPart(b); doc.addPart(c)
        let ids: Set<UUID> = [a.id, b.id, c.id]

        // Before: heights agree (40), widths differ.
        let preWidthCommon = MultiSelectionEditing.commonValue(
            in: doc.parts.filter { ids.contains($0.id) },
            for: \.width
        )
        #expect(preWidthCommon == nil)

        // Apply width=200 across the selection.
        MultiSelectionEditing.applyValue(200.0, to: \.width, in: &doc, for: ids)

        // After: widths agree at 200.
        let postWidthCommon = MultiSelectionEditing.commonValue(
            in: doc.parts.filter { ids.contains($0.id) },
            for: \.width
        )
        #expect(postWidthCommon == 200)

        _ = a; _ = b; _ = c
    }
}

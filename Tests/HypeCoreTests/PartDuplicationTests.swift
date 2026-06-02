import Testing
import Foundation
@testable import HypeCore

@Suite("Part duplication")
struct PartDuplicationTests {
    @Test("duplicateParts copies one part with offset, unique name, sort key, and selected result id")
    func duplicateSinglePart() throws {
        var document = HypeDocument.newDocument(name: "Duplicate Single")
        let cardId = try #require(document.sortedCards.first?.id)
        let button = Part(partType: .button, cardId: cardId, name: "Action", sortKey: "a000003", left: 12, top: 20, width: 88, height: 24)
        document.addPart(button)

        let result = document.duplicateParts(ids: [button.id])

        #expect(result.copiedPartIds.count == 1)
        let copyId = try #require(result.originalToCopy[button.id])
        let copy = try #require(document.part(byId: copyId))
        #expect(copy.id != button.id)
        #expect(copy.name == "Action copy")
        #expect(copy.left == 20)
        #expect(copy.top == 28)
        #expect(copy.width == button.width)
        #expect(copy.height == button.height)
        #expect(copy.cardId == cardId)
        #expect(copy.backgroundId == nil)
        #expect(copy.sortKey == "a000004")
        #expect(result.copiedPartIds == [copyId])
    }

    @Test("duplicateParts uses requested name for a single AI-style duplicate and still deduplicates")
    func duplicateSinglePartWithRequestedName() throws {
        var document = HypeDocument.newDocument(name: "Duplicate Named")
        let cardId = try #require(document.sortedCards.first?.id)
        let original = Part(partType: .field, cardId: cardId, name: "Name", left: 0, top: 0, width: 100, height: 24)
        let existing = Part(partType: .field, cardId: cardId, name: "Name Copy", left: 0, top: 40, width: 100, height: 24)
        document.addPart(original)
        document.addPart(existing)

        let result = document.duplicateParts(
            ids: [original.id],
            options: PartDuplicationOptions(offsetX: 20, offsetY: 10, requestedSingleName: "Name Copy")
        )

        let copy = try #require(result.copiedPartIds.first.flatMap { document.part(byId: $0) })
        #expect(copy.name == "Name Copy copy")
        #expect(copy.left == 20)
        #expect(copy.top == 10)

        let exactResult = document.duplicateParts(
            ids: [original.id],
            options: PartDuplicationOptions(offsetX: 1, offsetY: 1, requestedSingleName: "Explicit")
        )
        let exactCopy = try #require(exactResult.copiedPartIds.first.flatMap { document.part(byId: $0) })
        #expect(exactCopy.name == "Explicit")
    }

    @Test("duplicateParts copies multi-selection in document order and keeps copies selected")
    func duplicateMultipleParts() throws {
        var document = HypeDocument.newDocument(name: "Duplicate Multiple")
        let cardId = try #require(document.sortedCards.first?.id)
        let first = Part(partType: .button, cardId: cardId, name: "First", sortKey: "a000000", left: 0, top: 0, width: 88, height: 24)
        let second = Part(partType: .shape, cardId: cardId, name: "Second", sortKey: "a000001", left: 100, top: 0, width: 40, height: 40)
        document.addPart(first)
        document.addPart(second)

        let result = document.duplicateParts(ids: [second.id, first.id])

        let copies = result.copiedPartIds.compactMap { document.part(byId: $0) }
        #expect(copies.map(\.name) == ["First copy", "Second copy"])
        #expect(copies.map(\.left) == [8, 108])
        #expect(copies.map(\.top) == [8, 8])
        #expect(copies.map(\.sortKey) == ["a000002", "a000003"])
    }

    @Test("duplicateParts duplicates grouped selections as a new group")
    func duplicateGroupedParts() throws {
        var document = HypeDocument.newDocument(name: "Duplicate Group")
        let cardId = try #require(document.sortedCards.first?.id)
        let first = Part(partType: .button, cardId: cardId, name: "First", left: 0, top: 0, width: 88, height: 24)
        let second = Part(partType: .field, cardId: cardId, name: "Second", left: 100, top: 0, width: 96, height: 22)
        document.addPart(first)
        document.addPart(second)
        let maybeOriginalGroupId = document.groupParts(ids: [first.id, second.id])
        let originalGroupId = try #require(maybeOriginalGroupId)

        let result = document.duplicateParts(ids: [first.id])

        let copies = result.copiedPartIds.compactMap { document.part(byId: $0) }
        #expect(copies.count == 2)
        let copiedGroupIds = Set(copies.compactMap(\.groupId))
        #expect(copiedGroupIds.count == 1)
        #expect(copiedGroupIds.first != originalGroupId)
        #expect(document.expandedGroupSelection([result.copiedPartIds[0]]) == Set(result.copiedPartIds))
    }

    @Test("duplicateParts copies only intra-selection constraints")
    func duplicateIntraSelectionConstraintsOnly() throws {
        var document = HypeDocument.newDocument(name: "Duplicate Constraints")
        let cardId = try #require(document.sortedCards.first?.id)
        let source = Part(partType: .button, cardId: cardId, name: "Source", left: 0, top: 0, width: 88, height: 24)
        let target = Part(partType: .field, cardId: cardId, name: "Target", left: 100, top: 0, width: 96, height: 22)
        let outside = Part(partType: .shape, cardId: cardId, name: "Outside", left: 200, top: 0, width: 40, height: 40)
        document.addPart(source)
        document.addPart(target)
        document.addPart(outside)
        let internalConstraint = LayoutConstraint(sourcePartId: source.id, sourceEdge: .right, targetType: .part, targetPartId: target.id, targetEdge: .left, distance: 12)
        let outsideConstraint = LayoutConstraint(sourcePartId: source.id, sourceEdge: .left, targetType: .part, targetPartId: outside.id, targetEdge: .right, distance: 20)
        let canvasConstraint = LayoutConstraint(sourcePartId: source.id, sourceEdge: .top, targetType: .canvas, targetEdge: .top, distance: 20)
        document.addConstraint(internalConstraint)
        document.addConstraint(outsideConstraint)
        document.addConstraint(canvasConstraint)

        let result = document.duplicateParts(ids: [source.id, target.id])

        #expect(result.copiedConstraintIds.count == 1)
        let copiedConstraintId = try #require(result.copiedConstraintIds.first)
        let copiedConstraint = try #require(document.constraints.first { $0.id == copiedConstraintId })
        #expect(copiedConstraint.sourcePartId == result.originalToCopy[source.id])
        #expect(copiedConstraint.targetPartId == result.originalToCopy[target.id])
        #expect(copiedConstraint.distance == internalConstraint.distance)
        #expect(document.constraints.count == 4)
    }

    @Test("duplicateParts preserves background ownership")
    func duplicateBackgroundPart() throws {
        var document = HypeDocument.newDocument(name: "Duplicate Background")
        let backgroundId = try #require(document.backgrounds.first?.id)
        let field = Part(partType: .field, backgroundId: backgroundId, name: "Shared", left: 4, top: 4, width: 120, height: 30)
        document.addPart(field)

        let result = document.duplicateParts(ids: [field.id])

        let copy = try #require(result.copiedPartIds.first.flatMap { document.part(byId: $0) })
        #expect(copy.cardId == nil)
        #expect(copy.backgroundId == backgroundId)
        #expect(copy.name == "Shared copy")
    }

    @Test("duplicate_part AI tool uses canonical duplicate semantics")
    func duplicatePartToolUsesCanonicalSemantics() async throws {
        var document = HypeDocument.newDocument(name: "Duplicate Tool")
        let cardId = try #require(document.sortedCards.first?.id)
        var button = Part(partType: .button, cardId: cardId, name: "Run", left: 10, top: 20, width: 88, height: 24)
        button.script = "on mouseUp\n  answer \"hi\"\nend mouseUp"
        button.textContent = "Click Me"
        document.addPart(button)
        let executor = HypeToolExecutor()

        let message = await executor.execute(
            toolName: "duplicate_part",
            arguments: [
                "part_name": "Run",
                "new_name": "Run Again",
                "dx": "30",
                "dy": "40"
            ],
            document: &document,
            currentCardId: cardId
        )

        let copy = try #require(document.parts.first { $0.name == "Run Again" })
        #expect(message == "Duplicated 'Run' as 'Run Again'")
        #expect(copy.left == 40)
        #expect(copy.top == 60)
        #expect(copy.script == button.script)
        #expect(copy.textContent == button.textContent)
        #expect(copy.id != button.id)
    }
}

import Foundation
import Testing
@testable import HypeCore

@Suite("Part layer transfer")
struct PartLayerTransferTests {
    @Test("transferParts moves card parts to background by replacing them with deep copies")
    func transferCardPartToBackground() throws {
        var document = HypeDocument.newDocument(name: "Card to Background")
        let card = try #require(document.sortedCards.first)
        var button = Part(partType: .button, cardId: card.id, name: "Launch", sortKey: "a000003", left: 24, top: 32, width: 88, height: 24)
        button.textContent = "Launch"
        button.script = "on mouseUp\n  answer \"go\"\nend mouseUp"
        document.addPart(button)

        let result = document.transferParts(ids: [button.id], to: .background(card.backgroundId))

        #expect(result.removedPartIds == [button.id])
        let movedId = try #require(result.originalToTransferred[button.id])
        #expect(result.transferredPartIds == [movedId])
        #expect(document.part(byId: button.id) == nil)

        let moved = try #require(document.part(byId: movedId))
        #expect(moved.id != button.id)
        #expect(moved.cardId == nil)
        #expect(moved.backgroundId == card.backgroundId)
        #expect(moved.name == "Launch")
        #expect(moved.left == button.left)
        #expect(moved.top == button.top)
        #expect(moved.width == button.width)
        #expect(moved.height == button.height)
        #expect(moved.textContent == button.textContent)
        #expect(moved.script == button.script)
        #expect(moved.sortKey == "a000004")
    }

    @Test("transferParts moves background parts to the current card")
    func transferBackgroundPartToCard() throws {
        var document = HypeDocument.newDocument(name: "Background to Card")
        let card = try #require(document.sortedCards.first)
        let field = Part(partType: .field, backgroundId: card.backgroundId, name: "Shared Name", left: 10, top: 10, width: 140, height: 28)
        document.addPart(field)

        let result = document.transferParts(ids: [field.id], to: .card(card.id))

        let moved = try #require(result.transferredPartIds.first.flatMap { document.part(byId: $0) })
        #expect(document.part(byId: field.id) == nil)
        #expect(moved.cardId == card.id)
        #expect(moved.backgroundId == nil)
        #expect(moved.name == "Shared Name")
        #expect(document.partsForCard(card.id).map(\.id).contains(moved.id))
        #expect(!document.partsForBackground(card.backgroundId).map(\.id).contains(field.id))
    }

    @Test("transferParts expands grouped selections and assigns a new group id")
    func transferGroupedSelection() throws {
        var document = HypeDocument.newDocument(name: "Grouped Transfer")
        let card = try #require(document.sortedCards.first)
        let first = Part(partType: .button, cardId: card.id, name: "First", left: 0, top: 0, width: 88, height: 24)
        let second = Part(partType: .field, cardId: card.id, name: "Second", left: 100, top: 0, width: 100, height: 24)
        document.addPart(first)
        document.addPart(second)
        let maybeGroupId = document.groupParts(ids: [first.id, second.id])
        let originalGroupId = try #require(maybeGroupId)

        let result = document.transferParts(ids: [first.id], to: .background(card.backgroundId))

        #expect(result.transferredPartIds.count == 2)
        let movedParts = result.transferredPartIds.compactMap { document.part(byId: $0) }
        #expect(movedParts.count == 2)
        let movedGroupIds = Set(movedParts.compactMap(\.groupId))
        #expect(movedGroupIds.count == 1)
        #expect(movedGroupIds.first != originalGroupId)
        #expect(document.expandedGroupSelection([result.transferredPartIds[0]]) == Set(result.transferredPartIds))
        #expect(movedParts.allSatisfy { $0.cardId == nil && $0.backgroundId == card.backgroundId })
    }

    @Test("transferParts deduplicates names in the destination layer")
    func transferDeduplicatesDestinationNames() throws {
        var document = HypeDocument.newDocument(name: "Name Conflict")
        let card = try #require(document.sortedCards.first)
        let existingBackgroundPart = Part(partType: .button, backgroundId: card.backgroundId, name: "Action", left: 0, top: 0, width: 88, height: 24)
        let cardPart = Part(partType: .button, cardId: card.id, name: "Action", left: 100, top: 0, width: 88, height: 24)
        document.addPart(existingBackgroundPart)
        document.addPart(cardPart)

        let result = document.transferParts(ids: [cardPart.id], to: .background(card.backgroundId))

        let moved = try #require(result.transferredPartIds.first.flatMap { document.part(byId: $0) })
        #expect(moved.name == "Action copy")
    }

    @Test("transferParts preserves canvas and intra-selection constraints while removing stale external references")
    func transferConstraints() throws {
        var document = HypeDocument.newDocument(name: "Constraint Transfer")
        let card = try #require(document.sortedCards.first)
        let source = Part(partType: .button, cardId: card.id, name: "Source", left: 0, top: 0, width: 88, height: 24)
        let target = Part(partType: .field, cardId: card.id, name: "Target", left: 120, top: 0, width: 100, height: 24)
        let outside = Part(partType: .shape, cardId: card.id, name: "Outside", left: 240, top: 0, width: 40, height: 40)
        document.addPart(source)
        document.addPart(target)
        document.addPart(outside)

        let canvasConstraint = LayoutConstraint(sourcePartId: source.id, sourceEdge: .left, targetType: .canvas, targetEdge: .left, distance: 20)
        let internalConstraint = LayoutConstraint(sourcePartId: source.id, sourceEdge: .right, targetType: .part, targetPartId: target.id, targetEdge: .left, distance: 12)
        let externalConstraint = LayoutConstraint(sourcePartId: source.id, sourceEdge: .top, targetType: .part, targetPartId: outside.id, targetEdge: .bottom, distance: 30)
        let externalSourceConstraint = LayoutConstraint(sourcePartId: outside.id, sourceEdge: .bottom, targetType: .part, targetPartId: source.id, targetEdge: .top, distance: 18)
        document.addConstraint(canvasConstraint)
        document.addConstraint(internalConstraint)
        document.addConstraint(externalConstraint)
        document.addConstraint(externalSourceConstraint)

        let result = document.transferParts(ids: [source.id, target.id], to: .background(card.backgroundId))

        #expect(result.copiedConstraintIds.count == 2)
        #expect(document.constraints.count == 2)
        let movedSourceId = try #require(result.originalToTransferred[source.id])
        let movedTargetId = try #require(result.originalToTransferred[target.id])
        let movedConstraints = result.copiedConstraintIds.compactMap { id in
            document.constraints.first { $0.id == id }
        }

        #expect(movedConstraints.contains { constraint in
            constraint.sourcePartId == movedSourceId
                && constraint.targetType == .canvas
                && constraint.targetPartId == nil
                && constraint.distance == canvasConstraint.distance
        })
        #expect(movedConstraints.contains { constraint in
            constraint.sourcePartId == movedSourceId
                && constraint.targetType == .part
                && constraint.targetPartId == movedTargetId
                && constraint.distance == internalConstraint.distance
        })
        #expect(!document.constraints.contains { constraint in
            constraint.sourcePartId == source.id
                || constraint.sourcePartId == target.id
                || constraint.targetPartId == source.id
                || constraint.targetPartId == target.id
        })
    }
}

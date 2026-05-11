import Foundation
import Testing
@testable import HypeCore

@Suite("Part grouping")
struct PartGroupingTests {
    private func makeDocument() -> (HypeDocument, UUID, UUID) {
        var document = HypeDocument.newDocument(name: "Grouping")
        let cardId = document.sortedCards[0].id
        let backgroundId = document.sortedCards[0].backgroundId
        document.addPart(Part(partType: .button, cardId: cardId, name: "A", left: 10, top: 20, width: 40, height: 30))
        document.addPart(Part(partType: .field, cardId: cardId, name: "B", left: 70, top: 50, width: 80, height: 40))
        document.addPart(Part(partType: .shape, cardId: cardId, name: "C", left: 200, top: 60, width: 30, height: 20))
        return (document, cardId, backgroundId)
    }

    @Test("groupParts assigns one group id and expands member selection")
    func groupPartsAssignsOneGroupId() throws {
        var (document, _, _) = makeDocument()
        let a = try #require(document.parts.first { $0.name == "A" }?.id)
        let b = try #require(document.parts.first { $0.name == "B" }?.id)

        let maybeGroupId = document.groupParts(ids: [a, b])
        let groupId = try #require(maybeGroupId)
        #expect(document.part(byId: a)?.groupId == groupId)
        #expect(document.part(byId: b)?.groupId == groupId)
        #expect(document.expandedGroupSelection([a]) == [a, b])

        let units = document.selectionUnits(for: [a])
        #expect(units.count == 1)
        #expect(units[0].ids == [a, b])
        #expect(units[0].bounds == PartBounds(left: 10, top: 20, width: 140, height: 70))
    }

    @Test("groupParts rejects mixed card/background ownership")
    func groupPartsRejectsMixedLayers() throws {
        var (document, cardId, backgroundId) = makeDocument()
        let cardPart = try #require(document.parts.first { $0.cardId == cardId }?.id)
        let backgroundPart = Part(partType: .button, backgroundId: backgroundId, name: "BG", left: 5, top: 5)
        document.addPart(backgroundPart)

        #expect(document.groupParts(ids: [cardPart, backgroundPart.id]) == nil)
        #expect(document.part(byId: cardPart)?.groupId == nil)
        #expect(document.part(byId: backgroundPart.id)?.groupId == nil)
    }

    @Test("moveParts moves every member when called with one grouped member")
    func movePartsMovesWholeGroup() throws {
        var (document, _, _) = makeDocument()
        let a = try #require(document.parts.first { $0.name == "A" }?.id)
        let b = try #require(document.parts.first { $0.name == "B" }?.id)
        _ = document.groupParts(ids: [a, b])

        document.moveParts(ids: [a], dx: 12, dy: -5)

        #expect(document.part(byId: a)?.left == 22)
        #expect(document.part(byId: a)?.top == 15)
        #expect(document.part(byId: b)?.left == 82)
        #expect(document.part(byId: b)?.top == 45)
    }

    @Test("resizeParts scales grouped members from group bounds")
    func resizePartsScalesGroupedMembers() throws {
        var (document, _, _) = makeDocument()
        let a = try #require(document.parts.first { $0.name == "A" }?.id)
        let b = try #require(document.parts.first { $0.name == "B" }?.id)
        _ = document.groupParts(ids: [a, b])
        let oldBounds = try #require(document.selectionUnits(for: [a]).first?.bounds)

        document.resizeParts(
            ids: [a],
            from: oldBounds,
            to: PartBounds(left: 10, top: 20, width: 280, height: 140)
        )

        let resizedA = try #require(document.part(byId: a))
        let resizedB = try #require(document.part(byId: b))
        #expect(resizedA.left == 10)
        #expect(resizedA.top == 20)
        #expect(resizedA.width == 80)
        #expect(resizedA.height == 60)
        #expect(resizedB.left == 130)
        #expect(resizedB.top == 80)
        #expect(resizedB.width == 160)
        #expect(resizedB.height == 80)
    }

    @Test("ungroupParts clears all represented group members")
    func ungroupPartsClearsMembers() throws {
        var (document, _, _) = makeDocument()
        let a = try #require(document.parts.first { $0.name == "A" }?.id)
        let b = try #require(document.parts.first { $0.name == "B" }?.id)
        _ = document.groupParts(ids: [a, b])

        let affected = document.ungroupParts(ids: [a])

        #expect(affected == [a, b])
        #expect(document.part(byId: a)?.groupId == nil)
        #expect(document.part(byId: b)?.groupId == nil)
        #expect(document.expandedGroupSelection([a]) == [a])
    }

    @Test("groupId round-trips through Codable")
    func groupIdRoundTrips() throws {
        var (document, _, _) = makeDocument()
        let a = try #require(document.parts.first { $0.name == "A" }?.id)
        let b = try #require(document.parts.first { $0.name == "B" }?.id)
        let maybeGroupId = document.groupParts(ids: [a, b])
        let groupId = try #require(maybeGroupId)

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: data)

        #expect(decoded.part(byId: a)?.groupId == groupId)
        #expect(decoded.part(byId: b)?.groupId == groupId)
        #expect(decoded.expandedGroupSelection([a]) == [a, b])
    }
}

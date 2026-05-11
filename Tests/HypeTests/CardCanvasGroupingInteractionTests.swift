import AppKit
import SwiftUI
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("Card canvas grouping interaction")
struct CardCanvasGroupingInteractionTests {
    private final class CanvasState {
        var wrapper = HypeDocumentWrapper()
        var selectedPartIds: Set<UUID> = []

        init(document: HypeDocument) {
            wrapper.document = document
        }
    }

    private func groupedFixture() throws -> (CanvasState, UUID, UUID, CardCanvasView.Coordinator, CardCanvasNSView) {
        var document = HypeDocument.newDocument(name: "Grouped Canvas")
        let cardId = document.sortedCards[0].id

        let first = Part(partType: .button, cardId: cardId, name: "first", left: 10, top: 20, width: 40, height: 30)
        let second = Part(partType: .field, cardId: cardId, name: "second", left: 80, top: 60, width: 90, height: 40)
        document.addPart(first)
        document.addPart(second)
        let maybeGroupId = document.groupParts(ids: [first.id, second.id])
        _ = try #require(maybeGroupId)

        let state = CanvasState(document: document)
        let canvasView = CardCanvasView(
            document: Binding(
                get: { state.wrapper },
                set: { state.wrapper = $0 }
            ),
            currentCardId: cardId,
            currentTool: .select,
            selectedPartIds: Binding(
                get: { state.selectedPartIds },
                set: { state.selectedPartIds = $0 }
            ),
            editingBackground: false
        )

        let coordinator = CardCanvasView.Coordinator(parent: canvasView)
        let nsView = CardCanvasNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        nsView.document = state.wrapper.document
        nsView.currentCardId = cardId
        nsView.currentTool = .select
        nsView.coordinator = coordinator
        coordinator.nsView = nsView

        return (state, first.id, second.id, coordinator, nsView)
    }

    @Test("selecting one group member selects the whole group")
    func selectingGroupedMemberExpandsSelection() throws {
        let (state, firstId, secondId, coordinator, _) = try groupedFixture()

        coordinator.selectPart(firstId)

        #expect(state.selectedPartIds == [firstId, secondId])
    }

    @Test("shift arrow nudges every grouped member through canvas key handling")
    func shiftArrowNudgesWholeGroup() throws {
        let (state, firstId, secondId, coordinator, nsView) = try groupedFixture()
        state.selectedPartIds = [firstId]
        nsView.selectedPartIds = [firstId]
        let rightArrow = String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: rightArrow,
            charactersIgnoringModifiers: rightArrow,
            isARepeat: false,
            keyCode: 124
        ))

        withExtendedLifetime(coordinator) {
            nsView.keyDown(with: event)
        }

        let first = try #require(state.wrapper.document.part(byId: firstId))
        let second = try #require(state.wrapper.document.part(byId: secondId))
        #expect(first.left == 15)
        #expect(second.left == 85)
        #expect(state.selectedPartIds == [firstId, secondId])
    }
}

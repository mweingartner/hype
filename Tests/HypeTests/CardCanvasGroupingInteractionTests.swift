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

    private func emptyCanvasFixture() -> (CanvasState, UUID, CardCanvasView.Coordinator, CardCanvasNSView) {
        let document = HypeDocument.newDocument(name: "Creation Canvas")
        let cardId = document.sortedCards[0].id
        let state = CanvasState(document: document)
        let canvasView = CardCanvasView(
            document: Binding(
                get: { state.wrapper },
                set: { state.wrapper = $0 }
            ),
            currentCardId: cardId,
            currentTool: .button,
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
        nsView.currentTool = .button
        nsView.coordinator = coordinator
        coordinator.nsView = nsView
        return (state, cardId, coordinator, nsView)
    }

    @Test("selecting one group member selects the whole group")
    func selectingGroupedMemberExpandsSelection() throws {
        let (state, firstId, secondId, coordinator, _) = try groupedFixture()

        coordinator.selectPart(firstId)

        #expect(state.selectedPartIds == [firstId, secondId])
    }

    @Test("dropping a creation tool creates a snapped default-sized part, selects it, and does not create constraints")
    func commitCreationToolCreatesSelectedPartWithoutConstraints() throws {
        let (state, cardId, coordinator, nsView) = emptyCanvasFixture()

        let createdId = try #require(nsView.commitCreationTool(.button, at: CGPoint(x: 13, y: 21)))
        let part = try #require(state.wrapper.document.part(byId: createdId))
        withExtendedLifetime(coordinator) {}
        #expect(part.cardId == cardId)
        #expect(part.partType == .button)
        #expect(part.left == 20)
        #expect(part.top == 20)
        #expect(part.width == 88)
        #expect(part.height == 24)
        #expect(state.selectedPartIds == [createdId])
        #expect(state.wrapper.document.constraints.isEmpty)
        #expect(nsView.currentTool == .select)
    }

    @Test("rapid shift placement keeps the creation tool active and accumulates selection")
    func rapidCreationPlacementKeepsToolAndAccumulatedSelection() throws {
        let (state, cardId, coordinator, nsView) = emptyCanvasFixture()

        let firstId = try #require(nsView.commitCreationTool(
            .button,
            at: CGPoint(x: 13, y: 21),
            modifierFlags: [.shift],
            mode: .appendSelectionKeepPlacementTool
        ))
        let secondId = try #require(nsView.commitCreationTool(
            .button,
            at: CGPoint(x: 125, y: 21),
            modifierFlags: [.shift],
            mode: .appendSelectionKeepPlacementTool
        ))
        withExtendedLifetime(coordinator) {}

        let first = try #require(state.wrapper.document.part(byId: firstId))
        let second = try #require(state.wrapper.document.part(byId: secondId))
        #expect(first.cardId == cardId)
        #expect(second.cardId == cardId)
        #expect(first.partType == .button)
        #expect(second.partType == .button)
        #expect(first.left == 13)
        #expect(second.left == 125)
        #expect(state.selectedPartIds == [firstId, secondId])
        #expect(nsView.currentTool == .button)
        #expect(state.wrapper.document.constraints.isEmpty)
    }

    @Test("arrow nudges every grouped member by the 8-point grid through canvas key handling")
    func arrowNudgesWholeGroupByGridUnit() throws {
        let (state, firstId, secondId, coordinator, nsView) = try groupedFixture()
        state.selectedPartIds = [firstId]
        nsView.selectedPartIds = [firstId]
        let rightArrow = String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
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
        #expect(first.left == 18)
        #expect(second.left == 88)
        #expect(state.selectedPartIds == [firstId, secondId])
    }

    @Test("shift arrow micro-nudges every grouped member by one point")
    func shiftArrowMicroNudgesWholeGroup() throws {
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
        #expect(first.left == 11)
        #expect(second.left == 81)
        #expect(state.selectedPartIds == [firstId, secondId])
    }

    @Test("browse mode keyboard dispatch does not fall through to edit-mode nudge")
    func browseModeKeyboardDoesNotNudgeStaleSelection() throws {
        let (state, firstId, secondId, coordinator, nsView) = try groupedFixture()
        state.selectedPartIds = [firstId]
        nsView.selectedPartIds = [firstId]
        nsView.currentTool = .browse
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
        #expect(first.left == 10)
        #expect(second.left == 80)
    }
}

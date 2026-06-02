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

    private final class NotificationCounter: @unchecked Sendable {
        var count = 0
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

    @Test("command-D duplicates the selected group and selects the copies")
    func commandDDuplicatesSelectedGroup() throws {
        let (state, firstId, secondId, coordinator, nsView) = try groupedFixture()
        state.selectedPartIds = [firstId]
        nsView.selectedPartIds = [firstId]

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "d",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))

        withExtendedLifetime(coordinator) {
            nsView.keyDown(with: event)
        }

        let copyIds = state.selectedPartIds
        #expect(copyIds.count == 2)
        #expect(!copyIds.contains(firstId))
        #expect(!copyIds.contains(secondId))
        let copies = state.wrapper.document.parts.filter { copyIds.contains($0.id) }
        #expect(copies.map(\.name).sorted() == ["first copy", "second copy"])
        #expect(Set(copies.compactMap(\.groupId)).count == 1)
        #expect(copies.contains { $0.left == 18 && $0.top == 28 })
        #expect(copies.contains { $0.left == 88 && $0.top == 68 })
    }

    @Test("browse mode command-D does not duplicate a stale authoring selection")
    func browseModeCommandDDoesNotDuplicateSelection() throws {
        let (state, firstId, _, coordinator, nsView) = try groupedFixture()
        state.selectedPartIds = [firstId]
        nsView.selectedPartIds = [firstId]
        nsView.currentTool = .browse
        let originalPartCount = state.wrapper.document.parts.count

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "d",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))

        withExtendedLifetime(coordinator) {
            nsView.keyDown(with: event)
        }

        #expect(state.wrapper.document.parts.count == originalPartCount)
        #expect(state.selectedPartIds == [firstId])
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

    @Test("authoring browse double-click opens properties")
    func authoringBrowseDoubleClickOpensProperties() throws {
        let (_, firstId, _, coordinator, nsView) = try groupedFixture()
        nsView.currentTool = .browse
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = nsView

        let counter = NotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .editPartProperties,
            object: nil,
            queue: nil
        ) { notification in
            if notification.object as? UUID == firstId {
                counter.count += 1
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: nsView.convert(NSPoint(x: 12, y: 22), to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 2,
            pressure: 1
        ))

        withExtendedLifetime((coordinator, window)) {
            nsView.mouseDown(with: event)
        }

        #expect(counter.count == 1)
    }

    @Test("runtime mode double-click does not enter edit mode")
    func runtimeModeDoubleClickDoesNotOpenProperties() throws {
        let (state, firstId, _, coordinator, nsView) = try groupedFixture()
        state.wrapper.document.stack.runtimeModeEnabled = true
        nsView.document.stack.runtimeModeEnabled = true
        nsView.currentTool = .browse
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = nsView

        let counter = NotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .editPartProperties,
            object: nil,
            queue: nil
        ) { notification in
            if notification.object as? UUID == firstId {
                counter.count += 1
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: nsView.convert(NSPoint(x: 12, y: 22), to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 2,
            pressure: 1
        ))

        withExtendedLifetime((coordinator, window)) {
            nsView.mouseDown(with: event)
        }

        #expect(counter.count == 0)
        #expect(nsView.currentTool == .browse)
        #expect(state.selectedPartIds.isEmpty)
    }
}

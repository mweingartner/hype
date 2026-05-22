import SwiftUI
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("Card canvas deletion")
struct CardCanvasDeletionTests {
    @Test("deletePart does not resurrect part after async delete dispatch completes")
    func deletePartDoesNotResurrectAfterDispatch() async throws {
        var document = HypeDocument.newDocument(name: "Delete Race")
        let cardId = document.cards[0].id
        let spriteArea = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "game_area",
            left: 20,
            top: 20,
            width: 320,
            height: 240
        )
        document.addPart(spriteArea)

        var wrapper = HypeDocumentWrapper()
        wrapper.document = document
        var selection: Set<UUID> = [spriteArea.id]
        let documentBinding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let selectionBinding = Binding<Set<UUID>>(
            get: { selection },
            set: { selection = $0 }
        )
        let view = CardCanvasView(
            document: documentBinding,
            currentCardId: cardId,
            currentTool: .select,
            selectedPartIds: selectionBinding,
            editingBackground: false
        )
        let coordinator = CardCanvasView.Coordinator(parent: view)

        coordinator.deletePart(id: spriteArea.id)
        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(!wrapper.document.parts.contains(where: { $0.id == spriteArea.id }))
        #expect(!selection.contains(spriteArea.id))
    }
}

import Foundation
import HypeCore
import SwiftUI

@MainActor
struct HypeAutomationSession {
    var stackId: UUID
    var binding: Binding<HypeDocumentWrapper>
    var currentCardId: UUID?
    var selectedPartIds: Set<UUID>
    var currentTool: ToolName
    var editingBackground: Bool
    var updatedAt: Date

    var document: HypeDocument {
        binding.wrappedValue.document
    }
}

@MainActor
final class HypeAutomationRegistry {
    static let shared = HypeAutomationRegistry()

    private var sessions: [UUID: HypeAutomationSession] = [:]
    private var activeStackId: UUID?

    func upsert(
        binding: Binding<HypeDocumentWrapper>,
        currentCardId: UUID?,
        selectedPartIds: Set<UUID>,
        currentTool: ToolName,
        editingBackground: Bool
    ) {
        let stackId = binding.wrappedValue.document.stack.id
        sessions[stackId] = HypeAutomationSession(
            stackId: stackId,
            binding: binding,
            currentCardId: currentCardId,
            selectedPartIds: selectedPartIds,
            currentTool: currentTool,
            editingBackground: editingBackground,
            updatedAt: Date()
        )
        activeStackId = stackId
    }

    func remove(stackId: UUID) {
        sessions.removeValue(forKey: stackId)
        if activeStackId == stackId {
            activeStackId = sessions.values.sorted { $0.updatedAt > $1.updatedAt }.first?.stackId
        }
    }

    func markActive(stackId: UUID) {
        guard sessions[stackId] != nil else { return }
        activeStackId = stackId
    }

    func activeSession() -> HypeAutomationSession? {
        if let activeStackId, let session = sessions[activeStackId] {
            return session
        }
        if let active = HypeDocumentMutationCoordinator.shared.activeDocumentBinding {
            let stackId = active.wrappedValue.document.stack.id
            return sessions[stackId]
        }
        return sessions.values.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    func session(stackId: UUID) -> HypeAutomationSession? {
        sessions[stackId]
    }

    func listSessions() -> [HypeAutomationSession] {
        sessions.values.sorted { $0.document.stack.name < $1.document.stack.name }
    }

    func apply(
        document: HypeDocument,
        to session: HypeAutomationSession,
        currentCardId: UUID?,
        actionName: String
    ) {
        HypeDocumentMutationCoordinator.shared.applyDocument(
            document,
            to: session.binding,
            undoManager: nil,
            actionName: actionName
        )
        upsert(
            binding: session.binding,
            currentCardId: currentCardId ?? session.currentCardId,
            selectedPartIds: session.selectedPartIds,
            currentTool: session.currentTool,
            editingBackground: session.editingBackground
        )
    }
}

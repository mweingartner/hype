import Foundation

public enum AIEditTransactionState: String, Codable, Sendable, Equatable {
    case preview
    case applied
    case rolledBack
    case failed
}

public enum AIEditOperationPhase: String, Codable, Sendable, Equatable {
    case preview
    case deferredExternalApply
    case appliedExternal
}

public struct AIEditDocumentDelta: Codable, Sendable, Equatable {
    public var createdPartIds: [UUID]
    public var deletedPartIds: [UUID]
    public var changedPartIds: [UUID]
    public var createdCardIds: [UUID]
    public var deletedCardIds: [UUID]
    public var changedCardIds: [UUID]
    public var createdBackgroundIds: [UUID]
    public var deletedBackgroundIds: [UUID]
    public var changedBackgroundIds: [UUID]
    public var stackChanged: Bool
    public var assetRepositoryChanged: Bool
    public var paintLayersChanged: Bool

    public static let empty = AIEditDocumentDelta(
        createdPartIds: [],
        deletedPartIds: [],
        changedPartIds: [],
        createdCardIds: [],
        deletedCardIds: [],
        changedCardIds: [],
        createdBackgroundIds: [],
        deletedBackgroundIds: [],
        changedBackgroundIds: [],
        stackChanged: false,
        assetRepositoryChanged: false,
        paintLayersChanged: false
    )

    public var hasChanges: Bool {
        !createdPartIds.isEmpty
            || !deletedPartIds.isEmpty
            || !changedPartIds.isEmpty
            || !createdCardIds.isEmpty
            || !deletedCardIds.isEmpty
            || !changedCardIds.isEmpty
            || !createdBackgroundIds.isEmpty
            || !deletedBackgroundIds.isEmpty
            || !changedBackgroundIds.isEmpty
            || stackChanged
            || assetRepositoryChanged
            || paintLayersChanged
    }

    public func merged(with other: AIEditDocumentDelta) -> AIEditDocumentDelta {
        AIEditDocumentDelta(
            createdPartIds: merge(createdPartIds, other.createdPartIds),
            deletedPartIds: merge(deletedPartIds, other.deletedPartIds),
            changedPartIds: merge(changedPartIds, other.changedPartIds),
            createdCardIds: merge(createdCardIds, other.createdCardIds),
            deletedCardIds: merge(deletedCardIds, other.deletedCardIds),
            changedCardIds: merge(changedCardIds, other.changedCardIds),
            createdBackgroundIds: merge(createdBackgroundIds, other.createdBackgroundIds),
            deletedBackgroundIds: merge(deletedBackgroundIds, other.deletedBackgroundIds),
            changedBackgroundIds: merge(changedBackgroundIds, other.changedBackgroundIds),
            stackChanged: stackChanged || other.stackChanged,
            assetRepositoryChanged: assetRepositoryChanged || other.assetRepositoryChanged,
            paintLayersChanged: paintLayersChanged || other.paintLayersChanged
        )
    }

    private func merge(_ lhs: [UUID], _ rhs: [UUID]) -> [UUID] {
        Array(Set(lhs).union(rhs)).sorted { $0.uuidString < $1.uuidString }
    }
}

public struct AIEditOperationResult: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var toolName: String
    public var arguments: [String: String]
    public var result: String
    public var delta: AIEditDocumentDelta
    public var navigationDirective: String?
    public var phase: AIEditOperationPhase

    public init(
        id: UUID = UUID(),
        toolName: String,
        arguments: [String: String],
        result: String,
        delta: AIEditDocumentDelta,
        navigationDirective: String? = nil,
        phase: AIEditOperationPhase = .preview
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.delta = delta
        self.navigationDirective = navigationDirective
        self.phase = phase
    }
}

public struct AIEditTransaction: Sendable, Identifiable {
    public var id: UUID
    public var prompt: String
    public var providerName: String
    public var createdAt: Date
    public var state: AIEditTransactionState
    public var rollbackDocument: HypeDocument
    public var previewDocument: HypeDocument
    public var operations: [AIEditOperationResult]
    public var delta: AIEditDocumentDelta
    public var diagnostics: [String]

    public init(
        id: UUID = UUID(),
        prompt: String,
        providerName: String,
        createdAt: Date = Date(),
        state: AIEditTransactionState,
        rollbackDocument: HypeDocument,
        previewDocument: HypeDocument,
        operations: [AIEditOperationResult],
        delta: AIEditDocumentDelta,
        diagnostics: [String] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.providerName = providerName
        self.createdAt = createdAt
        self.state = state
        self.rollbackDocument = rollbackDocument
        self.previewDocument = previewDocument
        self.operations = operations
        self.delta = delta
        self.diagnostics = diagnostics
    }
}

public struct AIEditTransactionRunner: Sendable {
    public var executor: HypeToolExecutor

    public init(executor: HypeToolExecutor = HypeToolExecutor()) {
        self.executor = executor
    }

    public func preview(
        toolCalls: [OllamaToolCall],
        document: HypeDocument,
        currentCardId: UUID,
        prompt: String,
        providerName: String
    ) async -> AIEditTransaction {
        var draft = document
        var operationResults: [AIEditOperationResult] = []
        var mergedDelta = AIEditDocumentDelta.empty
        var diagnostics: [String] = []

        for call in toolCalls {
            if Self.isDeferredExternalTool(call.function.name) {
                let result = Self.deferredExternalPreviewMessage(for: call.function.name)
                diagnostics.append(result)
                operationResults.append(
                    AIEditOperationResult(
                        toolName: call.function.name,
                        arguments: call.function.arguments,
                        result: result,
                        delta: .empty,
                        navigationDirective: nil,
                        phase: .deferredExternalApply
                    )
                )
                continue
            }

            let before = draft
            let result = await executor.execute(
                toolName: call.function.name,
                arguments: call.function.arguments,
                document: &draft,
                currentCardId: currentCardId
            )
            let delta = Self.delta(from: before, to: draft)
            mergedDelta = mergedDelta.merged(with: delta)
            if result.hasPrefix("__HYPE_INTERNAL_DRAFT_REFUSED_v1:") {
                diagnostics.append("Script draft refused by host validation for \(call.function.name).")
            }
            operationResults.append(
                AIEditOperationResult(
                    toolName: call.function.name,
                    arguments: call.function.arguments,
                    result: result,
                    delta: delta,
                    navigationDirective: Self.navigationDirective(from: result)
                )
            )
        }

        return AIEditTransaction(
            prompt: prompt,
            providerName: providerName,
            state: .preview,
            rollbackDocument: document,
            previewDocument: draft,
            operations: operationResults,
            delta: mergedDelta,
            diagnostics: diagnostics
        )
    }

    @discardableResult
    public func apply(_ transaction: inout AIEditTransaction, to document: inout HypeDocument) -> AIEditTransaction {
        if transaction.operations.contains(where: { $0.phase == .deferredExternalApply }) {
            transaction.state = .failed
            transaction.diagnostics.append("Transaction contains deferred external tool calls; use async apply(currentCardId:) so billable operations run only during apply.")
            return transaction
        }
        document = transaction.previewDocument
        transaction.state = .applied
        return transaction
    }

    @discardableResult
    public func apply(
        _ transaction: inout AIEditTransaction,
        to document: inout HypeDocument,
        currentCardId: UUID
    ) async -> AIEditTransaction {
        document = transaction.previewDocument

        for index in transaction.operations.indices where transaction.operations[index].phase == .deferredExternalApply {
            let before = document
            let toolName = transaction.operations[index].toolName
            let args = transaction.operations[index].arguments
            let result = await executor.execute(
                toolName: toolName,
                arguments: args,
                document: &document,
                currentCardId: currentCardId
            )
            let delta = Self.delta(from: before, to: document)
            transaction.operations[index].result = result
            transaction.operations[index].delta = delta
            transaction.operations[index].navigationDirective = Self.navigationDirective(from: result)
            transaction.operations[index].phase = .appliedExternal
        }

        transaction.previewDocument = document
        transaction.delta = Self.delta(from: transaction.rollbackDocument, to: document)
        transaction.state = .applied
        return transaction
    }

    @discardableResult
    public func rollback(_ transaction: inout AIEditTransaction, to document: inout HypeDocument) -> AIEditTransaction {
        document = transaction.rollbackDocument
        transaction.state = .rolledBack
        return transaction
    }

    public static func delta(from before: HypeDocument, to after: HypeDocument) -> AIEditDocumentDelta {
        AIEditDocumentDelta(
            createdPartIds: createdIds(before.parts.map(\.id), after.parts.map(\.id)),
            deletedPartIds: deletedIds(before.parts.map(\.id), after.parts.map(\.id)),
            changedPartIds: changedIds(before.parts, after.parts),
            createdCardIds: createdIds(before.cards.map(\.id), after.cards.map(\.id)),
            deletedCardIds: deletedIds(before.cards.map(\.id), after.cards.map(\.id)),
            changedCardIds: changedIds(before.cards, after.cards),
            createdBackgroundIds: createdIds(before.backgrounds.map(\.id), after.backgrounds.map(\.id)),
            deletedBackgroundIds: deletedIds(before.backgrounds.map(\.id), after.backgrounds.map(\.id)),
            changedBackgroundIds: changedIds(before.backgrounds, after.backgrounds),
            stackChanged: encoded(before.stack) != encoded(after.stack),
            assetRepositoryChanged: encoded(before.assetRepository) != encoded(after.assetRepository),
            paintLayersChanged: encoded(before.paintLayers) != encoded(after.paintLayers)
        )
    }

    private static func navigationDirective(from result: String) -> String? {
        if result.hasPrefix("CREATED_CARD:") { return result }
        if result.hasPrefix("NAVIGATE:") { return result }
        return nil
    }

    public static func isDeferredExternalTool(_ toolName: String) -> Bool {
        switch toolName {
        case "generate_3d_model_from_text",
             "generate_3d_model_from_image",
             "generate_3d_model_from_images",
             "remesh_3d_model",
             "retexture_3d_model":
            return true
        default:
            return false
        }
    }

    private static func deferredExternalPreviewMessage(for toolName: String) -> String {
        "Deferred external operation '\(toolName)' until Apply. This Meshy.ai call may consume credits and cannot be undone externally; rollback only restores the Hype document."
    }

    private static func createdIds(_ before: [UUID], _ after: [UUID]) -> [UUID] {
        Array(Set(after).subtracting(before)).sorted { $0.uuidString < $1.uuidString }
    }

    private static func deletedIds(_ before: [UUID], _ after: [UUID]) -> [UUID] {
        Array(Set(before).subtracting(after)).sorted { $0.uuidString < $1.uuidString }
    }

    private static func changedIds<T: Identifiable & Encodable>(_ before: [T], _ after: [T]) -> [UUID] where T.ID == UUID {
        let beforeById = Dictionary(uniqueKeysWithValues: before.map { ($0.id, encoded($0)) })
        return after.compactMap { item in
            guard let previous = beforeById[item.id] else { return nil }
            return previous != encoded(item) ? item.id : nil
        }
        .sorted { $0.uuidString < $1.uuidString }
    }

    private static func encoded<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}

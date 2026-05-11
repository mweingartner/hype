import Foundation

public enum AIEditTransactionState: String, Codable, Sendable, Equatable {
    case preview
    case applied
    case rolledBack
    case failed
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
    public var spriteRepositoryChanged: Bool
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
        spriteRepositoryChanged: false,
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
            || spriteRepositoryChanged
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
            spriteRepositoryChanged: spriteRepositoryChanged || other.spriteRepositoryChanged,
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

    public init(
        id: UUID = UUID(),
        toolName: String,
        arguments: [String: String],
        result: String,
        delta: AIEditDocumentDelta,
        navigationDirective: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.delta = delta
        self.navigationDirective = navigationDirective
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
        document = transaction.previewDocument
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
            spriteRepositoryChanged: encoded(before.spriteRepository) != encoded(after.spriteRepository),
            paintLayersChanged: encoded(before.paintLayers) != encoded(after.paintLayers)
        )
    }

    private static func navigationDirective(from result: String) -> String? {
        if result.hasPrefix("CREATED_CARD:") { return result }
        if result.hasPrefix("NAVIGATE:") { return result }
        return nil
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

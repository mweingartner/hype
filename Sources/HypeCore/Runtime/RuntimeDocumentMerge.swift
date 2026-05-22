import Foundation

public struct RuntimeDocumentMergeResult: Sendable {
    public var document: HypeDocument
    public var preservedCurrentOnlyEntities: Bool

    public init(document: HypeDocument, preservedCurrentOnlyEntities: Bool) {
        self.document = document
        self.preservedCurrentOnlyEntities = preservedCurrentOnlyEntities
    }
}

/// Merges a runtime-produced document snapshot back into the currently
/// authored document without letting stale runtime snapshots delete newer
/// authoring edits.
///
/// Runtime scripts often return a full `HypeDocument`, but queued scene
/// timers can be based on an older snapshot while the AI/user is creating
/// parts or assets. Applying that runtime snapshot wholesale can erase those
/// newly-created entities. This merge keeps runtime changes for shared IDs
/// while preserving entities that only exist in the current authoring state.
public enum RuntimeDocumentMerge {
    public static func preservingCurrentOnlyEntities(
        runtimeDocument: HypeDocument,
        currentDocument: HypeDocument
    ) -> RuntimeDocumentMergeResult {
        guard runtimeDocument.stack.id == currentDocument.stack.id else {
            return RuntimeDocumentMergeResult(document: runtimeDocument, preservedCurrentOnlyEntities: false)
        }

        var merged = runtimeDocument
        var preserved = false

        preserved = appendMissing(&merged.backgrounds, from: currentDocument.backgrounds) || preserved
        preserved = appendMissing(&merged.cards, from: currentDocument.cards) || preserved
        preserved = appendMissing(&merged.parts, from: currentDocument.parts) || preserved
        preserved = appendMissing(&merged.constraints, from: currentDocument.constraints) || preserved
        preserved = appendMissing(&merged.themes, from: currentDocument.themes) || preserved
        preserved = appendMissingPaintLayers(&merged.paintLayers, from: currentDocument.paintLayers) || preserved

        let repositoryMerge = mergeRepository(runtimeDocument.spriteRepository, currentRepository: currentDocument.spriteRepository)
        merged.spriteRepository = repositoryMerge.repository
        preserved = repositoryMerge.preserved || preserved

        let contextMerge = mergeAIContextLibrary(runtimeDocument.aiContextLibrary, currentLibrary: currentDocument.aiContextLibrary)
        merged.aiContextLibrary = contextMerge.library
        preserved = contextMerge.preserved || preserved

        if currentDocument.aiPromptHistory.count > runtimeDocument.aiPromptHistory.count {
            merged.aiPromptHistory = currentDocument.aiPromptHistory
            preserved = true
        }

        if currentDocument.defaultBackgroundId != nil && runtimeDocument.defaultBackgroundId == nil {
            merged.defaultBackgroundId = currentDocument.defaultBackgroundId
            preserved = true
        }

        return RuntimeDocumentMergeResult(document: merged, preservedCurrentOnlyEntities: preserved)
    }

    private static func appendMissing<T: Identifiable>(
        _ target: inout [T],
        from source: [T]
    ) -> Bool where T.ID: Hashable {
        let existing = Set(target.map(\.id))
        let missing = source.filter { !existing.contains($0.id) }
        guard !missing.isEmpty else { return false }
        target.append(contentsOf: missing)
        return true
    }

    private static func appendMissingPaintLayers(
        _ target: inout [CardPaintLayer],
        from source: [CardPaintLayer]
    ) -> Bool {
        let existing = Set(target.map(\.cardId))
        let missing = source.filter { !existing.contains($0.cardId) }
        guard !missing.isEmpty else { return false }
        target.append(contentsOf: missing)
        return true
    }

    private static func mergeRepository(
        _ runtimeRepository: SpriteRepository,
        currentRepository: SpriteRepository
    ) -> (repository: SpriteRepository, preserved: Bool) {
        var merged = runtimeRepository
        let existingAssetIds = Set(merged.assets.map(\.id))
        let missingAssets = currentRepository.assets.filter { !existingAssetIds.contains($0.id) }
        if !missingAssets.isEmpty {
            merged.assets.append(contentsOf: missingAssets)
        }
        return (merged, !missingAssets.isEmpty)
    }

    private static func mergeAIContextLibrary(
        _ runtimeLibrary: AIContextLibrary,
        currentLibrary: AIContextLibrary
    ) -> (library: AIContextLibrary, preserved: Bool) {
        var merged = runtimeLibrary
        let existingItemIds = Set(merged.items.map(\.id))
        let missingItems = currentLibrary.items.filter { !existingItemIds.contains($0.id) }
        if !missingItems.isEmpty {
            merged.items.append(contentsOf: missingItems)
        }
        return (merged, !missingItems.isEmpty)
    }
}

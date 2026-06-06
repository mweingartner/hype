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
    public static func applyingRuntimeChanges(
        runtimeDocument: HypeDocument,
        baseDocument: HypeDocument,
        currentDocument: HypeDocument
    ) -> RuntimeDocumentMergeResult {
        guard runtimeDocument.stack.id == baseDocument.stack.id,
              runtimeDocument.stack.id == currentDocument.stack.id else {
            return RuntimeDocumentMergeResult(document: runtimeDocument, preservedCurrentOnlyEntities: false)
        }

        let result = preservingCurrentOnlyEntities(
            runtimeDocument: runtimeDocument,
            currentDocument: currentDocument
        )
        var merged = result.document
        var preserved = result.preservedCurrentOnlyEntities

        preserved = preserveCurrentEditsWhenRuntimeUnchanged(
            merged: &merged.backgrounds,
            base: baseDocument.backgrounds,
            runtime: runtimeDocument.backgrounds,
            current: currentDocument.backgrounds
        ) || preserved
        preserved = preserveCurrentEditsWhenRuntimeUnchanged(
            merged: &merged.cards,
            base: baseDocument.cards,
            runtime: runtimeDocument.cards,
            current: currentDocument.cards
        ) || preserved
        preserved = preserveCurrentEditsWhenRuntimeUnchanged(
            merged: &merged.parts,
            base: baseDocument.parts,
            runtime: runtimeDocument.parts,
            current: currentDocument.parts
        ) || preserved
        preserved = preserveCurrentEditsWhenRuntimeUnchanged(
            merged: &merged.constraints,
            base: baseDocument.constraints,
            runtime: runtimeDocument.constraints,
            current: currentDocument.constraints
        ) || preserved
        preserved = preserveCurrentEditsWhenRuntimeUnchanged(
            merged: &merged.themes,
            base: baseDocument.themes,
            runtime: runtimeDocument.themes,
            current: currentDocument.themes
        ) || preserved

        return RuntimeDocumentMergeResult(document: merged, preservedCurrentOnlyEntities: preserved)
    }

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

        let repositoryMerge = mergeRepository(runtimeDocument.assetRepository, currentRepository: currentDocument.assetRepository)
        merged.assetRepository = repositoryMerge.repository
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

        // Runtime snapshots are full-document values and may arrive after the
        // user has already left runtime mode. Do not let a stale in-flight
        // script snapshot force the authoring window back into runtime mode.
        if !currentDocument.stack.runtimeModeEnabled && runtimeDocument.stack.runtimeModeEnabled {
            merged.stack.runtimeModeEnabled = false
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
        _ runtimeRepository: AssetRepository,
        currentRepository: AssetRepository
    ) -> (repository: AssetRepository, preserved: Bool) {
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
        var preserved = false
        let existingSourceIds = Set(merged.sources.map(\.id))
        let missingSources = currentLibrary.sources.filter { !existingSourceIds.contains($0.id) }
        if !missingSources.isEmpty {
            merged.sources.append(contentsOf: missingSources)
            preserved = true
        }

        let existingItemIds = Set(merged.items.map(\.id))
        let missingItems = currentLibrary.items.filter { !existingItemIds.contains($0.id) }
        if !missingItems.isEmpty {
            merged.items.append(contentsOf: missingItems)
            for item in missingItems {
                guard let index = merged.sources.firstIndex(where: { $0.id == item.sourceId }),
                      !merged.sources[index].itemIds.contains(item.id) else {
                    continue
                }
                merged.sources[index].itemIds.append(item.id)
            }
            preserved = true
        }
        return (merged, preserved)
    }

    private static func preserveCurrentEditsWhenRuntimeUnchanged<T>(
        merged: inout [T],
        base: [T],
        runtime: [T],
        current: [T]
    ) -> Bool where T: Identifiable & Codable, T.ID: Hashable {
        let baseById = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let runtimeById = Dictionary(uniqueKeysWithValues: runtime.map { ($0.id, $0) })
        var didPreserve = false

        for currentEntity in current {
            guard let baseEntity = baseById[currentEntity.id],
                  let runtimeEntity = runtimeById[currentEntity.id],
                  codableEquivalent(runtimeEntity, baseEntity),
                  !codableEquivalent(currentEntity, baseEntity) else {
                continue
            }

            if let index = merged.firstIndex(where: { $0.id == currentEntity.id }) {
                merged[index] = currentEntity
            } else {
                merged.append(currentEntity)
            }
            didPreserve = true
        }

        return didPreserve
    }

    private static func codableEquivalent<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let left = try? encoder.encode(lhs),
              let right = try? encoder.encode(rhs) else {
            return false
        }
        return left == right
    }
}

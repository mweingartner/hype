import Foundation

public enum PartLayerTransferDestination: Equatable, Sendable {
    case card(UUID)
    case background(UUID)
}

public struct PartLayerTransferResult: Equatable, Sendable {
    public var originalToTransferred: [UUID: UUID]
    public var transferredPartIds: [UUID]
    public var copiedConstraintIds: [UUID]
    public var removedPartIds: [UUID]

    public init(
        originalToTransferred: [UUID: UUID],
        transferredPartIds: [UUID],
        copiedConstraintIds: [UUID] = [],
        removedPartIds: [UUID] = []
    ) {
        self.originalToTransferred = originalToTransferred
        self.transferredPartIds = transferredPartIds
        self.copiedConstraintIds = copiedConstraintIds
        self.removedPartIds = removedPartIds
    }
}

public extension HypeDocument {
    /// Move parts between the current card layer and its background layer by
    /// replacing each selected part with a deep value copy owned by the
    /// destination layer. Returning new IDs keeps undo/selection state explicit
    /// and avoids pretending a layer transfer is just an in-place owner edit.
    @discardableResult
    mutating func transferParts(
        ids rawIds: Set<UUID>,
        to destination: PartLayerTransferDestination
    ) -> PartLayerTransferResult {
        let expanded = expandedGroupSelection(rawIds)
        guard !expanded.isEmpty else {
            return PartLayerTransferResult(originalToTransferred: [:], transferredPartIds: [])
        }

        let originals = parts.filter { expanded.contains($0.id) }
        guard !originals.isEmpty else {
            return PartLayerTransferResult(originalToTransferred: [:], transferredPartIds: [])
        }

        let originalIds = Set(originals.map(\.id))
        let transferredIdsByOriginal = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, UUID()) })
        let groupIdsByOriginalGroup = Dictionary(uniqueKeysWithValues: Set(originals.compactMap(\.groupId)).map { ($0, UUID()) })
        var usedNamesByOwner = transferNameIndexByOwner(excluding: originalIds)
        var nextSortOrdinal = transferNextPartSortOrdinal()

        var transferredParts: [Part] = []
        transferredParts.reserveCapacity(originals.count)

        for original in originals {
            guard let transferredId = transferredIdsByOriginal[original.id] else { continue }
            var copy = original
            copy.id = transferredId
            copy.sortKey = String(format: "a%06d", nextSortOrdinal)
            nextSortOrdinal += 1

            switch destination {
            case .card(let cardId):
                copy.cardId = cardId
                copy.backgroundId = nil
            case .background(let backgroundId):
                copy.cardId = nil
                copy.backgroundId = backgroundId
            }

            if let originalGroupId = original.groupId {
                copy.groupId = groupIdsByOriginalGroup[originalGroupId]
            }

            let ownerKey = PartLayerTransferOwnerKey(part: copy)
            let baseName = transferBaseName(for: original)
            copy.name = Self.uniqueTransferredName(
                baseName: baseName,
                usedNames: &usedNamesByOwner[ownerKey, default: Set<String>()]
            )
            transferredParts.append(copy)
        }

        let copiedConstraintIds = transferredConstraints(
            originalIds: originalIds,
            transferredIdsByOriginal: transferredIdsByOriginal
        )

        parts.removeAll { originalIds.contains($0.id) }
        parts.append(contentsOf: transferredParts)
        constraints.removeAll { constraint in
            originalIds.contains(constraint.sourcePartId)
                || constraint.targetPartId.map(originalIds.contains) == true
        }
        constraints.append(contentsOf: copiedConstraintIds.constraints)

        return PartLayerTransferResult(
            originalToTransferred: transferredIdsByOriginal,
            transferredPartIds: transferredParts.map(\.id),
            copiedConstraintIds: copiedConstraintIds.ids,
            removedPartIds: originals.map(\.id)
        )
    }

    private func transferNameIndexByOwner(excluding removedIds: Set<UUID>) -> [PartLayerTransferOwnerKey: Set<String>] {
        var result: [PartLayerTransferOwnerKey: Set<String>] = [:]
        for part in parts where !removedIds.contains(part.id) {
            result[PartLayerTransferOwnerKey(part: part), default: []].insert(part.name)
        }
        return result
    }

    private func transferNextPartSortOrdinal() -> Int {
        let ordinals = parts.compactMap { part -> Int? in
            guard part.sortKey.hasPrefix("a") else { return nil }
            return Int(part.sortKey.dropFirst())
        }
        return (ordinals.max() ?? -1) + 1
    }

    private func transferBaseName(for part: Part) -> String {
        let trimmed = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return part.partType.rawValue
    }

    private static func uniqueTransferredName(baseName: String, usedNames: inout Set<String>) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedBase.isEmpty ? "Part" : trimmedBase
        if !usedNames.contains(base) {
            usedNames.insert(base)
            return base
        }

        var candidate = "\(base) copy"
        if !usedNames.contains(candidate) {
            usedNames.insert(candidate)
            return candidate
        }

        var suffix = 2
        while true {
            candidate = "\(base) copy \(suffix)"
            if !usedNames.contains(candidate) {
                usedNames.insert(candidate)
                return candidate
            }
            suffix += 1
        }
    }

    private func transferredConstraints(
        originalIds: Set<UUID>,
        transferredIdsByOriginal: [UUID: UUID]
    ) -> (constraints: [LayoutConstraint], ids: [UUID]) {
        var copied: [LayoutConstraint] = []
        var copiedIds: [UUID] = []

        for constraint in constraints {
            guard let transferredSourceId = transferredIdsByOriginal[constraint.sourcePartId] else { continue }

            switch constraint.targetType {
            case .canvas:
                var copy = constraint
                copy.id = UUID()
                copy.sourcePartId = transferredSourceId
                copied.append(copy)
                copiedIds.append(copy.id)
            case .part:
                guard let originalTargetId = constraint.targetPartId,
                      originalIds.contains(originalTargetId),
                      let transferredTargetId = transferredIdsByOriginal[originalTargetId] else {
                    continue
                }
                var copy = constraint
                copy.id = UUID()
                copy.sourcePartId = transferredSourceId
                copy.targetPartId = transferredTargetId
                copied.append(copy)
                copiedIds.append(copy.id)
            }
        }

        return (copied, copiedIds)
    }
}

private struct PartLayerTransferOwnerKey: Hashable {
    var cardId: UUID?
    var backgroundId: UUID?

    init(part: Part) {
        self.cardId = part.cardId
        self.backgroundId = part.backgroundId
    }
}

import Foundation

public struct PartDuplicationOptions: Equatable, Sendable {
    public var offsetX: Double
    public var offsetY: Double
    public var requestedSingleName: String?

    public init(
        offsetX: Double = LayoutGrid.standardNudge,
        offsetY: Double = LayoutGrid.standardNudge,
        requestedSingleName: String? = nil
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.requestedSingleName = requestedSingleName
    }
}

public struct PartDuplicationResult: Equatable, Sendable {
    public var originalToCopy: [UUID: UUID]
    public var copiedPartIds: [UUID]
    public var copiedConstraintIds: [UUID]

    public init(
        originalToCopy: [UUID: UUID],
        copiedPartIds: [UUID],
        copiedConstraintIds: [UUID] = []
    ) {
        self.originalToCopy = originalToCopy
        self.copiedPartIds = copiedPartIds
        self.copiedConstraintIds = copiedConstraintIds
    }
}

public extension HypeDocument {
    @discardableResult
    mutating func duplicateParts(
        ids rawIds: Set<UUID>,
        options: PartDuplicationOptions = PartDuplicationOptions()
    ) -> PartDuplicationResult {
        let expanded = expandedGroupSelection(rawIds)
        guard !expanded.isEmpty else {
            return PartDuplicationResult(originalToCopy: [:], copiedPartIds: [])
        }

        let originals = parts.filter { expanded.contains($0.id) }
        guard !originals.isEmpty else {
            return PartDuplicationResult(originalToCopy: [:], copiedPartIds: [])
        }

        let copyIdsByOriginal = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, UUID()) })
        let groupIdsByOriginalGroup = Dictionary(uniqueKeysWithValues: Set(originals.compactMap(\.groupId)).map { ($0, UUID()) })
        var usedNamesByOwner = duplicateNameIndexByOwner()
        var nextSortOrdinal = nextPartSortOrdinal()
        let requestedSingleName = originals.count == 1 ? options.requestedSingleName?.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        var copies: [Part] = []
        copies.reserveCapacity(originals.count)

        for original in originals {
            guard let copyId = copyIdsByOriginal[original.id] else { continue }
            var copy = original
            copy.id = copyId
            copy.left = original.left + options.offsetX
            copy.top = original.top + options.offsetY
            copy.sortKey = String(format: "a%06d", nextSortOrdinal)
            nextSortOrdinal += 1
            if let originalGroupId = original.groupId {
                copy.groupId = groupIdsByOriginalGroup[originalGroupId]
            }

            let ownerKey = PartDuplicationOwnerKey(part: original)
            let hasRequestedName = requestedSingleName?.isEmpty == false
            let baseName = hasRequestedName ? requestedSingleName! : defaultDuplicateBaseName(for: original)
            copy.name = Self.uniqueDuplicateName(
                baseName: baseName,
                usedNames: &usedNamesByOwner[ownerKey, default: Set<String>()],
                preferBaseName: hasRequestedName
            )

            copies.append(copy)
        }

        parts.append(contentsOf: copies)

        let copiedConstraintIds = duplicateConstraints(
            selectedOriginalIds: Set(originals.map(\.id)),
            copyIdsByOriginal: copyIdsByOriginal
        )

        return PartDuplicationResult(
            originalToCopy: copyIdsByOriginal,
            copiedPartIds: copies.map(\.id),
            copiedConstraintIds: copiedConstraintIds
        )
    }

    private func duplicateNameIndexByOwner() -> [PartDuplicationOwnerKey: Set<String>] {
        var result: [PartDuplicationOwnerKey: Set<String>] = [:]
        for part in parts {
            result[PartDuplicationOwnerKey(part: part), default: []].insert(part.name)
        }
        return result
    }

    private func nextPartSortOrdinal() -> Int {
        let ordinals = parts.compactMap { part -> Int? in
            guard part.sortKey.hasPrefix("a") else { return nil }
            return Int(part.sortKey.dropFirst())
        }
        return (ordinals.max() ?? -1) + 1
    }

    private func defaultDuplicateBaseName(for part: Part) -> String {
        let trimmed = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return part.partType.rawValue
    }

    private static func uniqueDuplicateName(baseName: String, usedNames: inout Set<String>, preferBaseName: Bool) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedBase.isEmpty ? "Part" : trimmedBase
        if preferBaseName && !usedNames.contains(base) {
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

    private mutating func duplicateConstraints(
        selectedOriginalIds: Set<UUID>,
        copyIdsByOriginal: [UUID: UUID]
    ) -> [UUID] {
        var copiedIds: [UUID] = []
        let copies = constraints.compactMap { constraint -> LayoutConstraint? in
            guard let copiedSourceId = copyIdsByOriginal[constraint.sourcePartId] else { return nil }
            guard constraint.targetType == .part,
                  let targetPartId = constraint.targetPartId,
                  selectedOriginalIds.contains(targetPartId),
                  let copiedTargetId = copyIdsByOriginal[targetPartId] else {
                return nil
            }

            var copy = constraint
            copy.id = UUID()
            copy.sourcePartId = copiedSourceId
            copy.targetPartId = copiedTargetId
            copiedIds.append(copy.id)
            return copy
        }
        constraints.append(contentsOf: copies)
        return copiedIds
    }
}

private struct PartDuplicationOwnerKey: Hashable {
    var cardId: UUID?
    var backgroundId: UUID?

    init(part: Part) {
        self.cardId = part.cardId
        self.backgroundId = part.backgroundId
    }
}

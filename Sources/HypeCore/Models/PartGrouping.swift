import Foundation

/// Rectangle math for authoring selections without pulling AppKit/CoreGraphics
/// into the HypeCore model layer.
public struct PartBounds: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var width: Double
    public var height: Double

    public init(left: Double, top: Double, width: Double, height: Double) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }

    public var right: Double { left + width }
    public var bottom: Double { top + height }
    public var centerX: Double { left + width / 2 }
    public var centerY: Double { top + height / 2 }

    public static func union(_ parts: [Part]) -> PartBounds? {
        guard let first = parts.first else { return nil }
        var minLeft = first.left
        var minTop = first.top
        var maxRight = first.left + first.width
        var maxBottom = first.top + first.height

        for part in parts.dropFirst() {
            minLeft = min(minLeft, part.left)
            minTop = min(minTop, part.top)
            maxRight = max(maxRight, part.left + part.width)
            maxBottom = max(maxBottom, part.top + part.height)
        }

        return PartBounds(
            left: minLeft,
            top: minTop,
            width: max(0, maxRight - minLeft),
            height: max(0, maxBottom - minTop)
        )
    }
}

/// A canvas selection unit: either one ungrouped part or all live members of
/// one flat authoring group.
public struct PartSelectionUnit: Equatable, Sendable {
    public var ids: Set<UUID>
    public var groupId: UUID?
    public var bounds: PartBounds

    public init(ids: Set<UUID>, groupId: UUID?, bounds: PartBounds) {
        self.ids = ids
        self.groupId = groupId
        self.bounds = bounds
    }
}

public extension HypeDocument {
    /// Expand any selected grouped part to every member of that group. This is
    /// the central rule that makes a grouped part behave like one object while
    /// still storing only ordinary parts.
    func expandedGroupSelection(_ ids: Set<UUID>) -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        var expanded = ids
        let selectedGroupIds = Set(parts.compactMap { part -> UUID? in
            ids.contains(part.id) ? part.groupId : nil
        })
        guard !selectedGroupIds.isEmpty else { return expanded }
        for part in parts where part.groupId.map(selectedGroupIds.contains) == true {
            expanded.insert(part.id)
        }
        return expanded
    }

    /// Return grouped selection units in document order. A group with fewer
    /// than two live members degrades to individual part behavior.
    func selectionUnits(for ids: Set<UUID>) -> [PartSelectionUnit] {
        let expanded = expandedGroupSelection(ids)
        guard !expanded.isEmpty else { return [] }

        var units: [PartSelectionUnit] = []
        var emittedGroups: Set<UUID> = []

        for part in parts where expanded.contains(part.id) {
            if let groupId = part.groupId {
                guard !emittedGroups.contains(groupId) else { continue }
                let members = parts.filter { $0.groupId == groupId && expanded.contains($0.id) }
                if members.count >= 2, let bounds = PartBounds.union(members) {
                    emittedGroups.insert(groupId)
                    units.append(PartSelectionUnit(
                        ids: Set(members.map(\.id)),
                        groupId: groupId,
                        bounds: bounds
                    ))
                    continue
                }
            }

            units.append(PartSelectionUnit(
                ids: [part.id],
                groupId: nil,
                bounds: PartBounds(left: part.left, top: part.top, width: part.width, height: part.height)
            ))
        }

        return units
    }

    /// Group the selected parts if they all belong to the same card/background
    /// layer. Existing groups are flattened into the new group, matching the
    /// practical authoring expectation that a selected set becomes one unit.
    @discardableResult
    mutating func groupParts(ids rawIds: Set<UUID>) -> UUID? {
        let ids = expandedGroupSelection(rawIds)
        let selected = parts.filter { ids.contains($0.id) }
        guard selected.count >= 2 else { return nil }

        let firstOwner = selected[0].groupingOwnerKey
        guard selected.allSatisfy({ $0.groupingOwnerKey == firstOwner }) else { return nil }

        let newGroupId = UUID()
        for index in parts.indices where ids.contains(parts[index].id) {
            parts[index].groupId = newGroupId
        }
        return newGroupId
    }

    /// Ungroup every group represented by the supplied selection. Returns the
    /// part ids that were affected so the UI can keep them selected.
    @discardableResult
    mutating func ungroupParts(ids rawIds: Set<UUID>) -> Set<UUID> {
        let ids = expandedGroupSelection(rawIds)
        let groupIds = Set(parts.compactMap { part -> UUID? in
            ids.contains(part.id) ? part.groupId : nil
        })
        guard !groupIds.isEmpty else { return [] }

        var affected: Set<UUID> = []
        for index in parts.indices where parts[index].groupId.map(groupIds.contains) == true {
            affected.insert(parts[index].id)
            parts[index].groupId = nil
        }
        return affected
    }

    mutating func moveParts(ids rawIds: Set<UUID>, dx: Double, dy: Double) {
        let ids = expandedGroupSelection(rawIds)
        guard !ids.isEmpty else { return }
        for index in parts.indices where ids.contains(parts[index].id) {
            parts[index].left += dx
            parts[index].top += dy
        }
    }

    /// Resize all selected parts proportionally from an old group bounds to a
    /// new group bounds. This keeps each child object's relative position and
    /// size inside the group.
    mutating func resizeParts(ids rawIds: Set<UUID>, from oldBounds: PartBounds, to newBounds: PartBounds) {
        let ids = expandedGroupSelection(rawIds)
        guard !ids.isEmpty else { return }
        let oldWidth = max(oldBounds.width, 0.0001)
        let oldHeight = max(oldBounds.height, 0.0001)
        let newWidth = max(newBounds.width, 1)
        let newHeight = max(newBounds.height, 1)

        for index in parts.indices where ids.contains(parts[index].id) {
            let part = parts[index]
            let relativeLeft = (part.left - oldBounds.left) / oldWidth
            let relativeTop = (part.top - oldBounds.top) / oldHeight
            let relativeWidth = part.width / oldWidth
            let relativeHeight = part.height / oldHeight

            parts[index].left = newBounds.left + relativeLeft * newWidth
            parts[index].top = newBounds.top + relativeTop * newHeight
            parts[index].width = max(1, relativeWidth * newWidth)
            parts[index].height = max(1, relativeHeight * newHeight)
        }
    }

    mutating func bringForward(ids rawIds: Set<UUID>) {
        let ids = expandedGroupSelection(rawIds)
        guard !ids.isEmpty else { return }
        for index in parts.indices.dropLast().reversed() where ids.contains(parts[index].id) && !ids.contains(parts[index + 1].id) {
            parts.swapAt(index, index + 1)
        }
    }

    mutating func sendBackward(ids rawIds: Set<UUID>) {
        let ids = expandedGroupSelection(rawIds)
        guard !ids.isEmpty else { return }
        for index in parts.indices.dropFirst() where ids.contains(parts[index].id) && !ids.contains(parts[index - 1].id) {
            parts.swapAt(index, index - 1)
        }
    }

    mutating func bringToFront(ids rawIds: Set<UUID>) {
        let ids = expandedGroupSelection(rawIds)
        guard !ids.isEmpty else { return }
        let moving = parts.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        parts.removeAll { ids.contains($0.id) }
        parts.append(contentsOf: moving)
    }

    mutating func sendToBack(ids rawIds: Set<UUID>) {
        let ids = expandedGroupSelection(rawIds)
        guard !ids.isEmpty else { return }
        let moving = parts.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        parts.removeAll { ids.contains($0.id) }
        parts.insert(contentsOf: moving, at: 0)
    }
}

private extension Part {
    var groupingOwnerKey: String {
        "\(cardId?.uuidString ?? "nil")|\(backgroundId?.uuidString ?? "nil")"
    }
}

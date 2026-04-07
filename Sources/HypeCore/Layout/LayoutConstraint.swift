import Foundation

/// A layout constraint linking one part's edge to another part's edge or a canvas edge.
public struct LayoutConstraint: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var sourcePartId: UUID
    public var sourceEdge: ConstraintEdge
    public var targetType: ConstraintTargetType
    public var targetPartId: UUID?
    public var targetEdge: ConstraintEdge
    public var distance: Double

    public init(
        id: UUID = UUID(),
        sourcePartId: UUID,
        sourceEdge: ConstraintEdge,
        targetType: ConstraintTargetType,
        targetPartId: UUID? = nil,
        targetEdge: ConstraintEdge,
        distance: Double
    ) {
        self.id = id
        self.sourcePartId = sourcePartId
        self.sourceEdge = sourceEdge
        self.targetType = targetType
        self.targetPartId = targetPartId
        self.targetEdge = targetEdge
        self.distance = distance
    }
}

public enum ConstraintEdge: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom, centerX, centerY

    public var isHorizontal: Bool {
        self == .left || self == .right || self == .centerX
    }
}

public enum ConstraintTargetType: String, Codable, Sendable {
    case part, canvas
}

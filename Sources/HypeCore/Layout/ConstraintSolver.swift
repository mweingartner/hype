import Foundation

/// Iterative constraint solver that resolves layout constraints into updated part geometries.
public struct ConstraintSolver: Sendable {

    public init() {}

    /// Solve all constraints and return updated part geometries.
    /// Only parts whose geometry actually changed are included in the result.
    public func solve(
        constraints: [LayoutConstraint],
        parts: [Part],
        canvasWidth: Double,
        canvasHeight: Double
    ) -> [UUID: (left: Double, top: Double, width: Double, height: Double)] {
        guard !constraints.isEmpty else { return [:] }

        var updates: [UUID: (left: Double, top: Double, width: Double, height: Double)] = [:]

        // Initialize with current positions
        var geometry: [UUID: (left: Double, top: Double, width: Double, height: Double)] = [:]
        for part in parts {
            geometry[part.id] = (left: part.left, top: part.top, width: part.width, height: part.height)
        }

        // Iterative solver: repeat until stable (max 10 iterations)
        var changed = true
        var iterations = 0
        let maxIterations = 10

        while changed && iterations < maxIterations {
            changed = false
            iterations += 1

            for constraint in constraints {
                guard var sourceGeom = geometry[constraint.sourcePartId] else { continue }

                // Resolve target edge position
                let targetPos: Double
                if constraint.targetType == .canvas {
                    targetPos = canvasEdgePosition(constraint.targetEdge, width: canvasWidth, height: canvasHeight)
                } else if let targetId = constraint.targetPartId, let targetGeom = geometry[targetId] {
                    targetPos = partEdgePosition(constraint.targetEdge, geom: targetGeom)
                } else {
                    continue
                }

                // Compute where the source edge should be
                let desiredSourcePos = targetPos + constraint.distance

                // Apply to source geometry
                let currentSourcePos = partEdgePosition(constraint.sourceEdge, geom: sourceGeom)
                if abs(currentSourcePos - desiredSourcePos) > 0.5 {
                    applyEdgePosition(
                        edge: constraint.sourceEdge,
                        position: desiredSourcePos,
                        geom: &sourceGeom
                    )
                    geometry[constraint.sourcePartId] = sourceGeom
                    changed = true
                }
            }
        }

        // Collect only parts that actually changed
        for part in parts {
            if let newGeom = geometry[part.id] {
                if abs(newGeom.left - part.left) > 0.5 || abs(newGeom.top - part.top) > 0.5 ||
                   abs(newGeom.width - part.width) > 0.5 || abs(newGeom.height - part.height) > 0.5 {
                    updates[part.id] = newGeom
                }
            }
        }

        return updates
    }

    private func canvasEdgePosition(_ edge: ConstraintEdge, width: Double, height: Double) -> Double {
        switch edge {
        case .left: return 0
        case .right: return width
        case .top: return 0
        case .bottom: return height
        case .centerX: return width / 2
        case .centerY: return height / 2
        }
    }

    private func partEdgePosition(_ edge: ConstraintEdge, geom: (left: Double, top: Double, width: Double, height: Double)) -> Double {
        switch edge {
        case .left: return geom.left
        case .right: return geom.left + geom.width
        case .top: return geom.top
        case .bottom: return geom.top + geom.height
        case .centerX: return geom.left + geom.width / 2
        case .centerY: return geom.top + geom.height / 2
        }
    }

    private func applyEdgePosition(edge: ConstraintEdge, position: Double, geom: inout (left: Double, top: Double, width: Double, height: Double)) {
        switch edge {
        case .left: geom.left = position
        case .right: geom.left = position - geom.width
        case .top: geom.top = position
        case .bottom: geom.top = position - geom.height
        case .centerX: geom.left = position - geom.width / 2
        case .centerY: geom.top = position - geom.height / 2
        }
    }
}

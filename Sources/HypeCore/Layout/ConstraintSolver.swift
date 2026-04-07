import Foundation

/// Iterative constraint solver that resolves layout constraints into updated part geometries.
/// When a part has both left+right or top+bottom constraints, the width/height is adjusted
/// rather than moving the part.
public struct ConstraintSolver: Sendable {

    public init() {}

    /// Solve all constraints and return updated part geometries.
    public func solve(
        constraints: [LayoutConstraint],
        parts: [Part],
        canvasWidth: Double,
        canvasHeight: Double
    ) -> [UUID: (left: Double, top: Double, width: Double, height: Double)] {
        guard !constraints.isEmpty else { return [:] }

        // Initialize with current positions
        var geometry: [UUID: (left: Double, top: Double, width: Double, height: Double)] = [:]
        for part in parts {
            geometry[part.id] = (left: part.left, top: part.top, width: part.width, height: part.height)
        }

        // Group constraints by source part
        var partConstraints: [UUID: [LayoutConstraint]] = [:]
        for c in constraints {
            partConstraints[c.sourcePartId, default: []].append(c)
        }

        // Iterative solver: repeat until stable (max 10 iterations)
        var changed = true
        var iterations = 0

        while changed && iterations < 10 {
            changed = false
            iterations += 1

            for (partId, pConstraints) in partConstraints {
                guard var geom = geometry[partId] else { continue }
                let originalGeom = geom

                // Separate horizontal and vertical constraints
                let hConstraints = pConstraints.filter { $0.sourceEdge.isHorizontal }
                let vConstraints = pConstraints.filter { !$0.sourceEdge.isHorizontal }

                // Resolve horizontal constraints
                resolveAxis(
                    constraints: hConstraints,
                    geom: &geom,
                    canvasWidth: canvasWidth,
                    canvasHeight: canvasHeight,
                    allGeometry: geometry
                )

                // Resolve vertical constraints
                resolveAxis(
                    constraints: vConstraints,
                    geom: &geom,
                    canvasWidth: canvasWidth,
                    canvasHeight: canvasHeight,
                    allGeometry: geometry
                )

                if abs(geom.left - originalGeom.left) > 0.5 ||
                   abs(geom.top - originalGeom.top) > 0.5 ||
                   abs(geom.width - originalGeom.width) > 0.5 ||
                   abs(geom.height - originalGeom.height) > 0.5 {
                    geometry[partId] = geom
                    changed = true
                }
            }
        }

        // Collect only parts that actually changed from their original
        var updates: [UUID: (left: Double, top: Double, width: Double, height: Double)] = [:]
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

    /// Resolve constraints for one axis (horizontal or vertical).
    /// If both start-edge and end-edge are constrained, adjust size instead of position.
    private func resolveAxis(
        constraints: [LayoutConstraint],
        geom: inout (left: Double, top: Double, width: Double, height: Double),
        canvasWidth: Double,
        canvasHeight: Double,
        allGeometry: [UUID: (left: Double, top: Double, width: Double, height: Double)]
    ) {
        guard !constraints.isEmpty else { return }

        var resolvedPositions: [ConstraintEdge: Double] = [:]

        for c in constraints {
            let targetPos: Double
            if c.targetType == .canvas {
                targetPos = canvasEdgePosition(c.targetEdge, width: canvasWidth, height: canvasHeight)
            } else if let tid = c.targetPartId, let tGeom = allGeometry[tid] {
                targetPos = partEdgePosition(c.targetEdge, geom: tGeom)
            } else {
                continue
            }
            resolvedPositions[c.sourceEdge] = targetPos + c.distance
        }

        let isHorizontal = constraints.first!.sourceEdge.isHorizontal

        if isHorizontal {
            let hasLeft = resolvedPositions[.left]
            let hasRight = resolvedPositions[.right]
            let hasCenter = resolvedPositions[.centerX]

            if let leftPos = hasLeft, let rightPos = hasRight {
                // Both left and right constrained → pin left, adjust width
                geom.left = leftPos
                geom.width = max(10, rightPos - leftPos)
            } else if let leftPos = hasLeft {
                geom.left = leftPos
            } else if let rightPos = hasRight {
                // Right constrained only → move part so right edge is at rightPos
                geom.left = rightPos - geom.width
            } else if let centerPos = hasCenter {
                geom.left = centerPos - geom.width / 2
            }
        } else {
            let hasTop = resolvedPositions[.top]
            let hasBottom = resolvedPositions[.bottom]
            let hasCenter = resolvedPositions[.centerY]

            if let topPos = hasTop, let bottomPos = hasBottom {
                // Both top and bottom constrained → pin top, adjust height
                geom.top = topPos
                geom.height = max(10, bottomPos - topPos)
            } else if let topPos = hasTop {
                geom.top = topPos
            } else if let bottomPos = hasBottom {
                // Bottom constrained only → move part so bottom edge is at bottomPos
                geom.top = bottomPos - geom.height
            } else if let centerPos = hasCenter {
                geom.top = centerPos - geom.height / 2
            }
        }
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
}

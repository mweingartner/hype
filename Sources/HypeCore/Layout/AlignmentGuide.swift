import Foundation

/// A snap guide line drawn on the canvas during move/resize operations.
public struct SnapGuide: Sendable, Equatable {
    public enum Orientation: Sendable, Equatable { case horizontal, vertical }
    public var orientation: Orientation
    public var position: Double  // x for vertical, y for horizontal
    public var kind: SnapKind

    public init(orientation: Orientation, position: Double, kind: SnapKind) {
        self.orientation = orientation
        self.position = position
        self.kind = kind
    }
}

/// The type of alignment a snap guide represents.
public enum SnapKind: Sendable, Equatable {
    case edge       // aligned to another part's edge
    case center     // aligned to another part's center
    case canvas     // aligned to canvas center
    case spacing    // standard HIG spacing from adjacent part
}

/// Apple HIG standard spacing values (points).
public enum HIGSpacing {
    public static let small: Double = 8
    public static let medium: Double = 12
    public static let large: Double = 20
}

/// Snap threshold in points — how close before snapping activates.
public let snapThreshold: Double = 6

/// Computes snap adjustments and guide lines for moving/resizing parts.
public struct AlignmentEngine: Sendable {

    public init() {}

    /// Compute snap adjustment for moving a part.
    /// Returns (dx, dy) adjustment to apply, plus active guide lines.
    public func computeMoveSnap(
        movingPart: Part,
        otherParts: [Part],
        canvasWidth: Double,
        canvasHeight: Double
    ) -> (dx: Double, dy: Double, guides: [SnapGuide]) {
        var guides: [SnapGuide] = []

        let movingRect = PartRect(part: movingPart)

        // Collect all snap targets from other parts
        var verticalTargets: [(position: Double, kind: SnapKind)] = []
        var horizontalTargets: [(position: Double, kind: SnapKind)] = []

        // Canvas center
        verticalTargets.append((canvasWidth / 2, .canvas))
        horizontalTargets.append((canvasHeight / 2, .canvas))

        for other in otherParts {
            let otherRect = PartRect(part: other)

            // Edge alignment targets
            verticalTargets.append((otherRect.left, .edge))
            verticalTargets.append((otherRect.right, .edge))
            verticalTargets.append((otherRect.centerX, .center))

            horizontalTargets.append((otherRect.top, .edge))
            horizontalTargets.append((otherRect.bottom, .edge))
            horizontalTargets.append((otherRect.centerY, .center))

            // Spacing targets (standard gaps from edges)
            for spacing in [HIGSpacing.small, HIGSpacing.medium, HIGSpacing.large] {
                verticalTargets.append((otherRect.right + spacing, .spacing))
                verticalTargets.append((otherRect.left - spacing, .spacing))
                horizontalTargets.append((otherRect.bottom + spacing, .spacing))
                horizontalTargets.append((otherRect.top - spacing, .spacing))
            }
        }

        // Find best vertical snap (x-axis) across left edge, right edge, and center
        let movingEdgesV: [(Double, String)] = [
            (movingRect.left, "left"),
            (movingRect.right, "right"),
            (movingRect.centerX, "centerX"),
        ]

        var bestDx: Double? = nil
        var bestDxDist: Double = snapThreshold + 1

        for (edge, _) in movingEdgesV {
            for target in verticalTargets {
                let dist = abs(edge - target.position)
                if dist < snapThreshold && dist < bestDxDist {
                    bestDx = target.position - edge
                    bestDxDist = dist
                    // Reset guides for this axis since we found a better match
                    guides.removeAll { $0.orientation == .vertical }
                    guides.append(SnapGuide(orientation: .vertical, position: target.position, kind: target.kind))
                }
            }
        }

        // Find best horizontal snap (y-axis) across top edge, bottom edge, and center
        let movingEdgesH: [(Double, String)] = [
            (movingRect.top, "top"),
            (movingRect.bottom, "bottom"),
            (movingRect.centerY, "centerY"),
        ]

        var bestDy: Double? = nil
        var bestDyDist: Double = snapThreshold + 1

        for (edge, _) in movingEdgesH {
            for target in horizontalTargets {
                let dist = abs(edge - target.position)
                if dist < snapThreshold && dist < bestDyDist {
                    bestDy = target.position - edge
                    bestDyDist = dist
                    guides.removeAll { $0.orientation == .horizontal }
                    guides.append(SnapGuide(orientation: .horizontal, position: target.position, kind: target.kind))
                }
            }
        }

        return (bestDx ?? 0, bestDy ?? 0, guides)
    }

    /// Compute snap adjustment for resizing a part.
    /// Snaps width/height to match another part's dimensions.
    public func computeResizeSnap(
        resizingPart: Part,
        otherParts: [Part],
        canvasWidth: Double,
        canvasHeight: Double
    ) -> (dw: Double, dh: Double, guides: [SnapGuide]) {
        var guides: [SnapGuide] = []
        var dw: Double = 0
        var dh: Double = 0

        for other in otherParts {
            if dw == 0 && abs(resizingPart.width - other.width) < snapThreshold {
                dw = other.width - resizingPart.width
                guides.append(SnapGuide(
                    orientation: .vertical,
                    position: resizingPart.left + other.width,
                    kind: .edge
                ))
            }
            if dh == 0 && abs(resizingPart.height - other.height) < snapThreshold {
                dh = other.height - resizingPart.height
                guides.append(SnapGuide(
                    orientation: .horizontal,
                    position: resizingPart.top + other.height,
                    kind: .edge
                ))
            }
        }

        return (dw, dh, guides)
    }
}

/// Helper to extract rect values from a Part.
struct PartRect {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double
    let centerX: Double
    let centerY: Double

    init(part: Part) {
        self.left = part.left
        self.top = part.top
        self.right = part.left + part.width
        self.bottom = part.top + part.height
        self.centerX = part.left + part.width / 2
        self.centerY = part.top + part.height / 2
    }
}

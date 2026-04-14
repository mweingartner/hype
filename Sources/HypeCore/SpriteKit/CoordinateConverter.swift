import Foundation

/// Converts between Hype's top-left origin coordinate system and SpriteKit's bottom-left origin.
public struct CoordinateConverter: Sendable {
    public let sceneHeight: Double

    public init(sceneHeight: Double) {
        self.sceneHeight = sceneHeight
    }

    /// Hype point (top-left origin) to SpriteKit point (bottom-left origin).
    public func toSK(_ point: PointSpec) -> PointSpec {
        PointSpec(x: point.x, y: sceneHeight - point.y)
    }

    /// SpriteKit point (bottom-left origin) to Hype point (top-left origin).
    public func toHype(_ point: PointSpec) -> PointSpec {
        PointSpec(x: point.x, y: sceneHeight - point.y)
    }

    /// Hype degrees (clockwise) to SpriteKit radians (counter-clockwise).
    public func toSKRotation(_ degrees: Double) -> Double {
        -degrees * .pi / 180.0
    }

    /// SpriteKit radians (counter-clockwise) to Hype degrees (clockwise).
    public func toHypeRotation(_ radians: Double) -> Double {
        -radians * 180.0 / .pi
    }
}

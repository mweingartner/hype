import Foundation

/// The five HyperCard object types.
public enum ObjectType: String, Codable, Sendable {
    case stack, background, card, button, field, shape, webpage
}

/// Part type discriminator.
public enum PartType: String, Codable, Sendable {
    case button, field, shape, webpage
}

/// Button visual styles.
public enum ButtonStyle: String, Codable, Sendable {
    case transparent, opaque, rectangle, roundRect, shadow
    case checkBox, radioButton, standard, `default`, popup, oval
}

/// Field visual styles.
public enum FieldStyle: String, Codable, Sendable {
    case transparent, opaque, rectangle, shadow, scrolling
}

/// Shape types.
public enum ShapeType: String, Codable, Sendable {
    case rectangle, roundRect, oval, line, freeform
}

/// A point in a shape path.
public struct PathPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Text alignment.
public enum TextAlignment: String, Codable, Sendable {
    case left, center, right
}

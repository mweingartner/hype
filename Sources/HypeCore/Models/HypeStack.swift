import Foundation

/// The five HyperCard object types.
public enum ObjectType: String, Codable, Sendable {
    case stack, background, card, button, field, shape, webpage, image, video, chart
}

/// Part type discriminator.
public enum PartType: String, Codable, Sendable {
    case button, field, shape, webpage, image, video, chart, spriteArea
    case calendar, pdf, map, colorWell
    case stepper, slider, toggle, segmented
    case audioRecorder, scene3D
    // Phase 3 — Apple controls catalog coverage.
    case progressView, gauge, link, menu, searchField, divider
    /// Sentinel returned by the decoder when an unknown raw value is seen.
    /// Document loaders filter parts whose `partType` decodes to `.unknown`
    /// so a future-stamped .hype file doesn't crash older builds.
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let known = PartType(rawValue: raw) {
            self = known
        } else {
            HypeLogger.shared.warn("Unknown part type '\(raw)'; treating as .unknown", source: "PartType.init(from:)")
            self = .unknown
        }
    }
}

/// Button visual styles.
public enum ButtonStyle: String, Codable, Sendable, CaseIterable {
    case transparent, opaque, rectangle, roundRect, shadow
    case checkBox, standard, `default`, popup, oval, toggle, radio

    /// Styles shown in the UI picker (excludes legacy/redundant styles).
    public static let pickerCases: [ButtonStyle] = [
        .standard, .default, .shadow, .transparent, .oval, .toggle,
        .checkBox, .popup, .radio,
    ]

    /// Custom decoder that maps the removed `"radioButton"` raw value
    /// to `.standard` so older .hype files still load cleanly. Unknown
    /// future values also degrade to `.standard` for forward-compat.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "radioButton" {
            self = .standard
        } else if let style = ButtonStyle(rawValue: raw) {
            self = style
        } else {
            // Unknown future styles degrade to .standard (security condition 4)
            self = .standard
        }
    }
}

/// Field visual styles.
public enum FieldStyle: String, Codable, Sendable, CaseIterable {
    case transparent, opaque, rectangle, shadow, scrolling, secure

    /// Custom decoder — unknown raw values degrade to `.rectangle`
    /// for forward-compat (security condition 4).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = FieldStyle(rawValue: raw) ?? .rectangle
    }
}

/// Shape types.
public enum ShapeType: String, Codable, Sendable, CaseIterable {
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

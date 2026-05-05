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
    /// Underlined-text link (formerly the standalone `link` part
    /// type). Click opens `Part.url` via the same scheme-allowlist
    /// path the dedicated link host enforced.
    case link

    /// Styles shown in the UI picker (excludes legacy/redundant styles).
    /// `.toggle` is the canonical NSSwitch-style modern switch UI;
    /// the older `.switch` enum case was a duplicate of `.toggle`
    /// and has been removed (the decoder still accepts the
    /// `"switch"` raw value and migrates it to `.toggle` for
    /// backward-compat with older `.hype` files).
    public static let pickerCases: [ButtonStyle] = [
        .standard, .default, .shadow, .transparent, .oval, .toggle,
        .link, .checkBox, .popup, .radio,
    ]

    /// Custom decoder.
    ///
    /// - `"radioButton"` → `.standard` (older renamed .hype files)
    /// - `"switch"` → `.toggle` (`.switch` was a duplicate that has
    ///   been removed)
    /// - Unknown future values → `.standard` (security condition 4 —
    ///   forward-compat without crashing)
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ButtonStyle.resolved(rawOrAlias: raw) ?? .standard
    }

    /// Map a string (raw value or known alias) to a `ButtonStyle`.
    ///
    /// Used by the Codable decoder above and by callers that accept
    /// user-supplied style strings (the AI tool surface, scripts,
    /// inspector value-binding, etc.) so a single migration table
    /// covers every entry point.
    ///
    /// Returns `nil` only when the input is genuinely unrecognized;
    /// callers decide whether to fall back to a default or refuse.
    public static func resolved(rawOrAlias raw: String) -> ButtonStyle? {
        switch raw {
        case "radioButton": return .standard
        case "switch":      return .toggle
        default:            return ButtonStyle(rawValue: raw)
        }
    }
}

/// Field visual styles.
public enum FieldStyle: String, Codable, Sendable, CaseIterable {
    case transparent, opaque, rectangle, shadow, scrolling, secure
    /// Search-field appearance (rounded rect with leading magnifying-
    /// glass icon). Replaces the standalone `searchField` part —
    /// fold into the field surface so there's one text-input control.
    /// Lifecycle messages `searchChanged` and `searchSubmitted`
    /// dispatch on fields with this style.
    case search

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

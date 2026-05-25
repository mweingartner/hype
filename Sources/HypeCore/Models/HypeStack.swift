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
    case musicPlayer, pianoKeyboard, stepSequencer, musicMixer, appleMusicBrowser, musicQueue
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
    case transparent, opaque, roundRect, shadow
    case checkBox, standard, `default`, popup, oval, toggle, radio
    /// Underlined-text link (formerly the standalone `link` part
    /// type). Click opens `Part.url` via the same scheme-allowlist
    /// path the dedicated link host enforced.
    case link

    /// Styles shown in the UI picker (excludes legacy/redundant styles).
    ///
    /// Three `ButtonStyle` cases were removed because they were
    /// byte-identical duplicates of cases that remain:
    /// - `.switch` was a duplicate of `.toggle` (NSSwitch UI)
    /// - `.rectangle` was a duplicate of `.standard` (filled rect
    ///    with a 1px separator stroke)
    ///
    /// The decoder still accepts those raw values and migrates them
    /// (see `resolved(rawOrAlias:)`) so older `.hype` files load
    /// cleanly. Old `radioButton` is also accepted and now correctly
    /// migrates to `.radio` (it had previously been bug-routed to
    /// `.standard`, which rendered as a rectangle instead of the
    /// expected radio circle).
    public static let pickerCases: [ButtonStyle] = [
        .standard, .default, .shadow, .transparent, .oval, .toggle,
        .link, .checkBox, .popup, .radio,
    ]

    /// Custom decoder.
    ///
    /// Migration table — see `resolved(rawOrAlias:)` for the full
    /// list. Unknown future values degrade to `.standard` for
    /// forward-compat (security condition 4 — never crash on a
    /// future-stamped .hype file).
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
        case "radioButton": return .radio    // pre-rename .hype files
        case "switch":      return .toggle   // collapsed duplicate
        case "rectangle":   return .standard // collapsed duplicate
        default:            return ButtonStyle(rawValue: raw)
        }
    }
}

/// Field visual styles.
public enum FieldStyle: String, Codable, Sendable, CaseIterable {
    case transparent, rectangle, shadow, scrolling, secure
    /// Search-field appearance (rounded rect with leading magnifying-
    /// glass icon). Replaces the standalone `searchField` part —
    /// fold into the field surface so there's one text-input control.
    /// Lifecycle messages `searchChanged` and `searchSubmitted`
    /// dispatch on fields with this style.
    case search

    /// Custom decoder — see `resolved(rawOrAlias:)` for the migration
    /// table. Unknown raw values degrade to `.rectangle` for
    /// forward-compat (security condition 4).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = FieldStyle.resolved(rawOrAlias: raw) ?? .rectangle
    }

    /// Map a string (raw value or known alias) to a `FieldStyle`.
    ///
    /// `.opaque` was removed because its renderer code was
    /// byte-identical to `.rectangle` (both did
    /// `fill(rect); strokeFieldRect(rect)`), and `.rectangle` is the
    /// canonical default everywhere — `Part.init`, the AI
    /// `create_field` tool, the script-interpreter `set the style`
    /// fallback, the Inspector binding, and the `formatAllProperties`
    /// "default=rectangle" tag all use it. The `"opaque"` raw value
    /// is still accepted on decode and migrates to `.rectangle`.
    public static func resolved(rawOrAlias raw: String) -> FieldStyle? {
        switch raw {
        case "opaque": return .rectangle  // collapsed duplicate
        default:       return FieldStyle(rawValue: raw)
        }
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

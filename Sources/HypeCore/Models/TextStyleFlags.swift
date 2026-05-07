import Foundation

/// Parsed, type-safe representation of a HypeTalk `textStyle` string.
///
/// HypeTalk follows HyperCard's convention: `textStyle` is a single
/// string, comma-separated when multiple traits are active. The
/// canonical values are:
///   `"plain"` (or `""`) — no flags set; the renderer paints with
///       the part's plain font, no decoration.
///   `"bold"`, `"italic"`, `"underline"`, `"strikethrough"` — set
///       individually or in any combination, e.g. `"bold,italic"` or
///       `"bold, italic, underline"` (whitespace tolerant).
///
/// This struct is the single source of truth for parsing and
/// emitting that string. Every renderer (`ButtonRenderer.drawLabel`,
/// `FieldRenderer`, `SceneBridge` for `SKLabelNode`) consults the
/// same helper so a part's textStyle renders identically everywhere.
///
/// Aliases recognized on parse:
///   `strike`, `strikeout` → `strikethrough`
///   `underlined` → `underline`
///   Case-insensitive throughout.
///
/// Output via `rawString` is always canonical lowercase comma+space
/// joined (e.g. `"bold, italic"`) so a round-trip parses → writes
/// the canonical form. An empty / plain instance returns `"plain"`.
public struct TextStyleFlags: Equatable, Sendable {
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool

    public init(
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
    }

    /// Parse a textStyle string. Unrecognized tokens are silently
    /// ignored — a future-stamped `.hype` document with a textStyle
    /// of `"shadow"` or `"condense"` (HyperCard had more variants we
    /// don't implement) loads cleanly with no traits set rather than
    /// crashing.
    public init(string: String) {
        let lower = string.lowercased()
        let trimmed = lower.trimmingCharacters(in: .whitespaces)
        // Empty or "plain" → all flags false.
        if trimmed.isEmpty || trimmed == "plain" {
            self.init()
            return
        }
        let tokens = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var b = false, i = false, u = false, s = false
        for t in tokens {
            switch t {
            case "bold": b = true
            case "italic": i = true
            case "underline", "underlined": u = true
            case "strikethrough", "strike", "strikeout": s = true
            default: break  // forward-compat: unknown tokens ignored
            }
        }
        self.init(bold: b, italic: i, underline: u, strikethrough: s)
    }

    /// Canonical comma+space joined emit. Single source of truth so
    /// `Codable` round-trips and HypeTalk `the textStyle of <part>`
    /// reads always match. Returns `"plain"` for the empty case so
    /// HyperCard scripts that compare against `"plain"` keep
    /// working: `if the textStyle of button "X" is "plain" then …`.
    public var rawString: String {
        var parts: [String] = []
        if bold          { parts.append("bold") }
        if italic        { parts.append("italic") }
        if underline     { parts.append("underline") }
        if strikethrough { parts.append("strikethrough") }
        return parts.isEmpty ? "plain" : parts.joined(separator: ", ")
    }

    /// True when no traits are active. Used by the inspector to
    /// short-circuit the "Plain" toggle and by the AI tool surface
    /// to drop the field from `formatAllProperties` summaries when
    /// it's at its default.
    public var isPlain: Bool { !bold && !italic && !underline && !strikethrough }
}

import Foundation

/// Shared hex-color validator for the HypeTalk and AI script surfaces
/// (`control-property-consistency` Decision 4).
///
/// Every color-kind part property write goes through `normalized(_:)`
/// so a script can no longer silently store an unrenderable value
/// (a named color, garbage text, an odd digit count). The accepted
/// grammar is the union of what every renderer already accepts, so no
/// currently-renderable value becomes an error:
/// - `NSColor(hexString:)` — 6-digit (`ShapeRenderer.swift:119`)
/// - `GlassRenderer.nsColorFromHexWithAlpha` — 6- or 8-digit (`GlassRenderer.swift:191`)
/// - `ColorRef.normalizedHex` — 6- or 8-digit (`ColorRef.swift:98`)
///
/// `ChartConfig.normalizedHex` (spider chart colors) is a deliberately
/// separate, fallback-on-invalid validator and is untouched by this
/// type — chart color writes stay byte-identical (Condition 6).
public enum HexColor {
    /// Fixed, case-insensitive classic-color-name table (design.md D9,
    /// turtle-graphics; part-properties spec delta). Additive only —
    /// resolved entirely before the hex path, after the empty-string
    /// passthrough, so existing hex acceptance and the `""` sentinel
    /// stay byte-identical (Condition 5).
    private static let namedColors: [String: String] = [
        "black": "#000000",
        "white": "#FFFFFF",
        "red": "#FF0000",
        "green": "#008000",
        "blue": "#0000FF",
        "yellow": "#FFFF00",
        "orange": "#FFA500",
        "purple": "#800080",
        "pink": "#FFC0CB",
        "brown": "#A52A2A",
        "gray": "#808080",
        "grey": "#808080",
        "cyan": "#00FFFF",
        "magenta": "#FF00FF",
        "lime": "#00FF00",
        "navy": "#000080",
        "teal": "#008080",
    ]

    /// Normalizes a user-supplied color string for storage.
    ///
    /// - `""` passes through unchanged — the app-wide "auto / clear"
    ///   sentinel for color-kind properties (empty means "let the
    ///   renderer choose", e.g. auto contrast-aware text color).
    /// - A fixed, case-insensitive classic color name (`red`, `navy`,
    ///   `grey`/`gray`, ...) resolves to its canonical `#RRGGBB` value.
    /// - A 6-digit or 8-digit hex string, with or without a leading
    ///   `#`, case-insensitive, normalizes to `#UPPERCASE` so stored
    ///   values (and round-trips through HypeTalk/AI) are stable.
    /// - Anything else (unrecognized names, wrong digit counts,
    ///   non-hex characters) returns `nil` — the caller surfaces this
    ///   as a validation error rather than silently storing garbage.
    ///
    /// - Parameter raw: the user-supplied value, as typed in a script.
    /// - Returns: the normalized storage form, or `nil` when `raw`
    ///   isn't a valid color.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        if let named = namedColors[trimmed.lowercased()] {
            return named
        }
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard body.count == 6 || body.count == 8, UInt64(body, radix: 16) != nil else {
            return nil
        }
        return "#\(body.uppercased())"
    }
}

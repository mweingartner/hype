import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

/// A reference to a color, expressed either as a fixed hex literal
/// (e.g. "#FF8800") or as a semantic system key (e.g. "system.accentColor")
/// that resolves through the host platform's appearance.
///
/// Themes use `ColorRef` rather than raw hex strings so a built-in
/// theme like "System" can opt into following macOS Light/Dark mode
/// for some surfaces while still pinning specific accents. User
/// themes typically use `.hex(...)` for full control.
///
/// On non-AppKit platforms the system-key path falls back to a
/// neutral middle-gray so scripts and tests still resolve a color.
public enum ColorRef: Codable, Sendable, Equatable, Hashable {
    /// Fixed sRGB color in `#RRGGBB` or `#RRGGBBAA` form.
    case hex(String)

    /// Named system color. Recognized keys mirror NSColor's
    /// canonical accessors:
    ///   - `system.accentColor`
    ///   - `system.controlBackgroundColor`
    ///   - `system.windowBackgroundColor`
    ///   - `system.labelColor`
    ///   - `system.secondaryLabelColor`
    ///   - `system.textColor`
    ///   - `system.textBackgroundColor`
    ///   - `system.gridColor`
    ///   - `system.separatorColor`
    ///   - `system.selectedContentBackgroundColor`
    /// Anything else falls back to neutral gray.
    case systemKey(String)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case kind, value }

    public init(from decoder: Decoder) throws {
        // Tolerant decode so themes round-trip cleanly even when
        // user/AI input doesn't quite match either shape.
        if let single = try? decoder.singleValueContainer() {
            if let raw = try? single.decode(String.self) {
                self = Self.parse(raw)
                return
            }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decode(String.self, forKey: .kind)) ?? "hex"
        let value = (try? c.decode(String.self, forKey: .value)) ?? "#000000"
        switch kind {
        case "system": self = .systemKey(value)
        default:       self = .hex(Self.normalizedHex(value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        // Encode as a single string so JSON stays compact and
        // human-readable: `"#FF8800"` or `"system:accentColor"`.
        var c = encoder.singleValueContainer()
        switch self {
        case .hex(let h):       try c.encode(h)
        case .systemKey(let k): try c.encode("system:\(k)")
        }
    }

    /// Parse `"#RRGGBB"`, `"#RRGGBBAA"`, or `"system:<key>"` into a
    /// `ColorRef`. Returns `.hex("#000000")` for unrecognized input
    /// rather than failing — themes should never throw at decode
    /// time because of one bad swatch.
    public static func parse(_ raw: String) -> ColorRef {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("system:") {
            return .systemKey(String(s.dropFirst("system:".count)))
        }
        if s.hasPrefix("#") {
            return .hex(normalizedHex(s))
        }
        // Bare 6/8-char hex without leading hash — common in human-
        // authored themes.
        let hex = s.uppercased()
        if hex.count == 6 || hex.count == 8,
           hex.allSatisfy({ "0123456789ABCDEF".contains($0) }) {
            return .hex("#" + hex)
        }
        return .hex("#000000")
    }

    /// Normalize a hex string to `"#RRGGBB"` or `"#RRGGBBAA"` upper-
    /// case form. Inputs missing a `#` are accepted; inputs with
    /// invalid characters fall back to black.
    public static func normalizedHex(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              s.allSatisfy({ "0123456789ABCDEF".contains($0) })
        else { return "#000000" }
        return "#" + s
    }

    /// The hex representation when this is a `.hex` value, otherwise
    /// the raw key name. Used for serialization-stable comparisons.
    public var rawDescription: String {
        switch self {
        case .hex(let h):       return h
        case .systemKey(let k): return "system:\(k)"
        }
    }

    // MARK: Resolution

    #if canImport(AppKit)
    /// Resolve to an `NSColor`. System keys honor the current
    /// appearance; hex literals are exact sRGB values.
    public var nsColor: NSColor {
        switch self {
        case .hex(let h):
            return Self.makeNSColor(fromHex: h)
        case .systemKey(let key):
            switch key {
            case "accentColor":                       return .controlAccentColor
            case "controlBackgroundColor":            return .controlBackgroundColor
            case "windowBackgroundColor":             return .windowBackgroundColor
            case "labelColor":                        return .labelColor
            case "secondaryLabelColor":               return .secondaryLabelColor
            case "tertiaryLabelColor":                return .tertiaryLabelColor
            case "textColor":                         return .textColor
            case "textBackgroundColor":               return .textBackgroundColor
            case "gridColor":                         return .gridColor
            case "separatorColor":                    return .separatorColor
            case "selectedContentBackgroundColor":    return .selectedContentBackgroundColor
            case "controlColor":                      return .controlColor
            case "controlTextColor":                  return .controlTextColor
            case "selectedControlColor":              return .selectedControlColor
            default:                                  return NSColor(white: 0.5, alpha: 1)
            }
        }
    }

    private static func makeNSColor(fromHex hex: String) -> NSColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt32(s, radix: 16) else { return .black }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >>  8) & 0xFF) / 255
            a = CGFloat( value        & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >>  8) & 0xFF) / 255
            b = CGFloat( value        & 0xFF) / 255
            a = 1
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    #endif

    #if canImport(SwiftUI)
    /// SwiftUI `Color`. Bridges through `nsColor` on AppKit so the
    /// system-key resolution honors macOS appearance dynamically.
    public var swiftUIColor: Color {
        #if canImport(AppKit)
        return Color(nsColor: nsColor)
        #else
        if case .hex(let h) = self { return Self.swiftUIColor(fromHex: h) }
        return Color.gray
        #endif
    }

    private static func swiftUIColor(fromHex hex: String) -> Color {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt32(s, radix: 16) else { return .black }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >>  8) & 0xFF) / 255
            a = Double( value        & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >>  8) & 0xFF) / 255
            b = Double( value        & 0xFF) / 255
            a = 1
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
    #endif
}

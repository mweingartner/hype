import Foundation
#if canImport(AppKit)
import AppKit

/// Visual effects for card transitions (inspired by HyperCard).
public enum VisualEffect: String, Sendable, CaseIterable {
    case dissolve, wipeLeft, wipeRight, wipeUp, wipeDown
    case irisOpen, irisClose, scrollLeft, scrollRight
    case `none`

    /// Apply this effect as a Core Animation transition.
    public var caTransitionType: String {
        switch self {
        case .dissolve: return "fade"
        case .wipeLeft, .wipeRight, .wipeUp, .wipeDown: return "push"
        case .irisOpen: return "reveal"
        case .irisClose: return "moveIn"
        case .scrollLeft, .scrollRight: return "push"
        case .none: return ""
        }
    }

    public var caTransitionSubtype: String? {
        switch self {
        case .wipeLeft, .scrollLeft: return "fromRight"
        case .wipeRight, .scrollRight: return "fromLeft"
        case .wipeUp: return "fromTop"
        case .wipeDown: return "fromBottom"
        default: return nil
        }
    }

    /// Parse a HypeTalk effect name into a VisualEffect.
    ///
    /// Accepts both the enum raw values (`wipeLeft`, `irisOpen`)
    /// and the human-friendly aliases users actually type in
    /// scripts: `dissolve`, `push`, `crossfade`, `doorway`,
    /// `moveIn`, `reveal`, `flipHorizontal`, `flipVertical`.
    /// Multi-word names like `"wipe left"` are camelCased before
    /// lookup.
    public static func fromName(_ name: String) -> VisualEffect {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)

        // Human-friendly aliases first (these are what users type
        // and what the HypeTalkGuide documents).
        switch lower {
        // Single-word aliases
        case "dissolve", "crossfade":       return .dissolve
        case "push":                        return .wipeLeft
        case "doorway":                     return .irisOpen
        case "reveal":                      return .wipeRight
        // Multi-word aliases (what users type unquoted)
        case "wipe left":                   return .wipeLeft
        case "wipe right":                  return .wipeRight
        case "wipe up":                     return .wipeUp
        case "wipe down":                   return .wipeDown
        case "iris open":                   return .irisOpen
        case "iris close":                  return .irisClose
        case "scroll left":                 return .scrollLeft
        case "scroll right":                return .scrollRight
        case "move in", "movein":           return .scrollLeft
        case "flip horizontal", "fliphorizontal": return .wipeLeft
        case "flip vertical", "flipvertical":     return .wipeUp
        default: break
        }

        // Try camelCasing multi-word names (e.g. "wipe left" → "wipeLeft")
        let words = lower.split(separator: " ")
        guard let first = words.first else { return .none }
        let camel = String(first) + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return VisualEffect(rawValue: camel) ?? .none
    }
}
#endif

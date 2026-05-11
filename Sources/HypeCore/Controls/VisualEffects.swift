import Foundation
#if canImport(AppKit)
import AppKit

/// Visual effects for card transitions (inspired by HyperCard).
public enum VisualEffect: String, Sendable, CaseIterable {
    case dissolve, fade, crossFade
    case wipeLeft, wipeRight, wipeUp, wipeDown
    case irisOpen, irisClose, doorway
    case scrollLeft, scrollRight, scrollUp, scrollDown
    case pushLeft, pushRight, pushUp, pushDown
    case moveInLeft, moveInRight, moveInUp, moveInDown
    case revealLeft, revealRight, revealUp, revealDown
    case flipHorizontal, flipVertical
    case `none`

    /// Apply this effect as a Core Animation transition.
    public var caTransitionType: String {
        switch self {
        case .dissolve, .fade, .crossFade: return "fade"
        case .wipeLeft, .wipeRight, .wipeUp, .wipeDown: return "reveal"
        case .irisOpen, .irisClose, .doorway: return "moveIn"
        case .scrollLeft, .scrollRight, .scrollUp, .scrollDown,
             .pushLeft, .pushRight, .pushUp, .pushDown: return "push"
        case .moveInLeft, .moveInRight, .moveInUp, .moveInDown: return "moveIn"
        case .revealLeft, .revealRight, .revealUp, .revealDown: return "reveal"
        case .flipHorizontal: return "oglFlip"
        case .flipVertical: return "oglFlip"
        case .none: return ""
        }
    }

    public var caTransitionSubtype: String? {
        switch self {
        case .wipeLeft, .scrollLeft, .pushLeft, .moveInLeft, .revealLeft:
            return "fromRight"
        case .wipeRight, .scrollRight, .pushRight, .moveInRight, .revealRight:
            return "fromLeft"
        case .wipeUp, .scrollUp, .pushUp, .moveInUp, .revealUp, .flipVertical:
            return "fromTop"
        case .wipeDown, .scrollDown, .pushDown, .moveInDown, .revealDown:
            return "fromBottom"
        case .flipHorizontal:
            return "fromLeft"
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
        let lower = normalizedWords(name)

        // Human-friendly aliases first (these are what users type
        // and what the HypeTalkGuide documents).
        switch lower {
        // Single-word aliases
        case "none", "plain", "cut":        return .none
        case "dissolve":                    return .dissolve
        case "fade":                        return .fade
        case "crossfade", "cross fade":     return .crossFade
        case "doorway":                     return .doorway
        case "wipe":                        return .wipeLeft
        case "iris":                        return .irisOpen
        case "scroll":                      return .scrollLeft
        case "push":                        return .pushLeft
        case "move in", "movein":           return .moveInLeft
        case "reveal":                      return .revealLeft
        case "flip":                        return .flipHorizontal
        // Multi-word aliases (what users type unquoted)
        case "wipe left":                   return .wipeLeft
        case "wipe right":                  return .wipeRight
        case "wipe up":                     return .wipeUp
        case "wipe down":                   return .wipeDown
        case "iris open":                   return .irisOpen
        case "iris close":                  return .irisClose
        case "scroll left":                 return .scrollLeft
        case "scroll right":                return .scrollRight
        case "scroll up":                   return .scrollUp
        case "scroll down":                 return .scrollDown
        case "push left":                   return .pushLeft
        case "push right":                  return .pushRight
        case "push up":                     return .pushUp
        case "push down":                   return .pushDown
        case "move in left", "movein left": return .moveInLeft
        case "move in right", "movein right": return .moveInRight
        case "move in up", "movein up":     return .moveInUp
        case "move in down", "movein down": return .moveInDown
        case "reveal left":                 return .revealLeft
        case "reveal right":                return .revealRight
        case "reveal up":                   return .revealUp
        case "reveal down":                 return .revealDown
        case "flip horizontal", "fliphorizontal": return .flipHorizontal
        case "flip vertical", "flipvertical":     return .flipVertical
        default: break
        }

        let compact = lower.replacingOccurrences(of: " ", with: "")
        if let match = allCases.first(where: { normalizedRawValue($0.rawValue) == compact }) {
            return match
        }

        // Try camelCasing multi-word names (e.g. "wipe left" -> "wipeLeft")
        let words = lower.split(separator: " ")
        guard let first = words.first else { return .none }
        let camel = String(first) + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return VisualEffect(rawValue: camel) ?? .none
    }

    private static func normalizedWords(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func normalizedRawValue(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}
#endif

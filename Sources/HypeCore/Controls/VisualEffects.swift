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

    /// Parse a HypeTalk effect name (e.g. "wipe left" -> .wipeLeft).
    public static func fromName(_ name: String) -> VisualEffect {
        let words = name.lowercased().split(separator: " ")
        guard let first = words.first else { return .none }
        let camel = String(first) + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return VisualEffect(rawValue: camel) ?? .none
    }
}
#endif

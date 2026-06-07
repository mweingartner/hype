import Foundation

/// HyperCard-compatible authoring capability level for a stack.
///
/// This gates Hype's authoring surfaces. It is intentionally not a security
/// boundary: stack scripts, external automations, and debug/MCP tools still
/// need their own validation and permission checks.
public enum HypeUserLevel: Int, CaseIterable, Codable, Sendable, Identifiable {
    case browsing = 1
    case typing = 2
    case painting = 3
    case authoring = 4
    case scripting = 5

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .browsing: return "Browsing"
        case .typing: return "Typing"
        case .painting: return "Painting"
        case .authoring: return "Authoring"
        case .scripting: return "Scripting"
        }
    }

    public var preferenceLabel: String {
        "Level \(rawValue) - \(displayName)"
    }

    public var helpText: String {
        switch self {
        case .browsing:
            return "Navigate cards and click controls. Editing text, artwork, objects, and scripts is disabled."
        case .typing:
            return "Browsing plus editing unlocked text fields. Layout, artwork, objects, and scripts remain protected."
        case .painting:
            return "Typing plus paint tools for card and background artwork. Object layout and scripts remain protected."
        case .authoring:
            return "Painting plus object creation, selection, movement, sizing, properties, cards, and backgrounds."
        case .scripting:
            return "Authoring plus script editor access and script mutation."
        }
    }

    public var canEditTextFields: Bool { rawValue >= Self.typing.rawValue }
    public var canUsePaintTools: Bool { rawValue >= Self.painting.rawValue }
    public var canAuthorObjects: Bool { rawValue >= Self.authoring.rawValue }
    public var canEditScripts: Bool { rawValue >= Self.scripting.rawValue }

    public static func clamped(_ rawValue: Int) -> HypeUserLevel {
        HypeUserLevel(rawValue: min(max(rawValue, 1), 5)) ?? .scripting
    }

    public static func parse(_ value: String) -> HypeUserLevel? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if let numeric = Int(normalized) {
            return clamped(numeric)
        }
        switch normalized {
        case "browse", "browsing":
            return .browsing
        case "type", "typing":
            return .typing
        case "paint", "painting":
            return .painting
        case "author", "authoring":
            return .authoring
        case "script", "scripting":
            return .scripting
        default:
            return nil
        }
    }
}

public extension Int {
    var hypeUserLevel: HypeUserLevel {
        HypeUserLevel.clamped(self)
    }
}

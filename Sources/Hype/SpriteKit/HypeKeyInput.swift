import AppKit

enum HypeKeyInput {
    static func normalizedName(for event: NSEvent) -> String {
        if let controlKeyName = normalizedControlKeyName(for: event) {
            return controlKeyName
        }

        if let specialKeyName = normalizedName(for: event.specialKey) {
            return specialKeyName
        }

        let characters = event.charactersIgnoringModifiers ?? event.characters ?? ""
        if let functionKeyName = normalizedFunctionKeyName(for: characters) {
            return functionKeyName
        }

        return characters.lowercased()
    }

    private static func normalizedControlKeyName(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36:
            return "return"
        case 76:
            return "enter"
        case 48:
            return "tab"
        case 49:
            return "space"
        case 53:
            return "escape"
        default:
            return nil
        }
    }

    private static func normalizedName(for specialKey: NSEvent.SpecialKey?) -> String? {
        guard let specialKey else { return nil }
        switch specialKey {
        case .upArrow:
            return "up"
        case .downArrow:
            return "down"
        case .leftArrow:
            return "left"
        case .rightArrow:
            return "right"
        default:
            return nil
        }
    }

    private static func normalizedFunctionKeyName(for characters: String) -> String? {
        guard characters.unicodeScalars.count == 1,
              let scalar = characters.unicodeScalars.first else {
            return nil
        }

        switch scalar.value {
        case UInt32(NSUpArrowFunctionKey):
            return "up"
        case UInt32(NSDownArrowFunctionKey):
            return "down"
        case UInt32(NSLeftArrowFunctionKey):
            return "left"
        case UInt32(NSRightArrowFunctionKey):
            return "right"
        default:
            return nil
        }
    }
}

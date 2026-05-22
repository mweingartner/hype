import Foundation
import HypeCore

/// Stable accessibility identifiers used by UI automation and assistive clients.
///
/// These identifiers are intentionally non-localized and ID-based. Visible labels
/// can change with themes, user content, or localization; automation needs a
/// durable contract tied to Hype's document model.
enum HypeAccessibilityID {
    static let mainWindow = "hype.window.main"
    static let objectsPanel = "hype.panel.objects"
    static let propertyInspector = "hype.panel.inspector"
    static let aiAssistant = "hype.panel.ai"
    static let aiMessages = "hype.ai.messages"
    static let aiPrompt = "hype.ai.prompt"
    static let aiSend = "hype.ai.send"
    static let aiStop = "hype.ai.stop"
    static let aiVoiceInput = "hype.ai.voiceInput"
    static let aiClearChat = "hype.ai.clearChat"
    static let scriptEditor = "hype.window.scriptEditor"
    static let scriptEditorCommands = "hype.scriptEditor.commands"
    static let scriptEditorText = "hype.scriptEditor.text"
    static let scriptEditorAI = "hype.scriptEditor.ai"
    static let spriteRepository = "hype.window.spriteRepository"
    static let aiContextLibrary = "hype.window.aiContextLibrary"
    static let preferences = "hype.window.preferences"

    static func canvas(cardId: UUID) -> String {
        "hype.canvas.card.\(cardId.uuidString)"
    }

    static func stack(_ id: UUID) -> String {
        "hype.stack.\(id.uuidString)"
    }

    static func card(_ id: UUID) -> String {
        "hype.card.\(id.uuidString)"
    }

    static func background(_ id: UUID) -> String {
        "hype.background.\(id.uuidString)"
    }

    static func part(_ id: UUID) -> String {
        "hype.part.\(id.uuidString)"
    }

    static func spriteScene(partId: UUID, sceneId: UUID) -> String {
        "hype.spriteArea.\(partId.uuidString).scene.\(sceneId.uuidString)"
    }

    static func spriteNode(partId: UUID, sceneId: UUID, nodeId: UUID) -> String {
        "hype.spriteArea.\(partId.uuidString).scene.\(sceneId.uuidString).node.\(nodeId.uuidString)"
    }

    static func tool(_ tool: ToolName) -> String {
        "hype.tool.\(tool.rawValue)"
    }

    static func toolbar(_ name: String) -> String {
        "hype.toolbar.\(name)"
    }

    static func inspectorField(_ name: String) -> String {
        "hype.inspector.\(name)"
    }

    static func scriptTemplate(_ name: String) -> String {
        "hype.scriptEditor.template.\(slug(name))"
    }

    private static func slug(_ value: String) -> String {
        value
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

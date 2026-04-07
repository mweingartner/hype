import SwiftUI
import HypeCore

struct GoMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Go") {
            Button("First Card") { NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.first) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Previous Card") { NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.previous) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next Card") { NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.next) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Last Card") { NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.last) }
                .keyboardShortcut("4", modifiers: .command)
        }
    }
}

struct ObjectsMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Objects") {
            Button("New Card") { NotificationCenter.default.post(name: .addNewCard, object: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Delete Card") { NotificationCenter.default.post(name: .deleteCurrentCard, object: nil) }
            Divider()
            Button("New Background...") { NotificationCenter.default.post(name: .addNewBackground, object: nil) }
            Divider()
            Button("Card Info...") { }
            Button("Background Info...") { }
            Button("Stack Info...") { }
        }
    }
}

struct ToolsMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Tools") {
            Button("Browse") { NotificationCenter.default.post(name: .selectTool, object: ToolName.browse) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Button") { NotificationCenter.default.post(name: .selectTool, object: ToolName.button) }
            Button("Field") { NotificationCenter.default.post(name: .selectTool, object: ToolName.field) }
            Button("Shape") { NotificationCenter.default.post(name: .selectTool, object: ToolName.shape) }
            Divider()
            Button("Select") { NotificationCenter.default.post(name: .selectTool, object: ToolName.select) }
            Button("Pencil") { NotificationCenter.default.post(name: .selectTool, object: ToolName.pencil) }
            Button("Line") { NotificationCenter.default.post(name: .selectTool, object: ToolName.line) }
            Button("Rectangle") { NotificationCenter.default.post(name: .selectTool, object: ToolName.rect) }
            Button("Oval") { NotificationCenter.default.post(name: .selectTool, object: ToolName.oval) }
        }
    }
}

extension Notification.Name {
    static let navigateCard = Notification.Name("navigateCard")
    static let navigateToCard = Notification.Name("navigateToCard")
    static let selectTool = Notification.Name("selectTool")
    static let addNewCard = Notification.Name("addNewCard")
    static let deleteCurrentCard = Notification.Name("deleteCurrentCard")
    static let editPartProperties = Notification.Name("editPartProperties")
    static let addNewBackground = Notification.Name("addNewBackground")
}

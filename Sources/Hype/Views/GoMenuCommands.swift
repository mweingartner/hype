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
            Button("Edit Background") { NotificationCenter.default.post(name: .toggleEditBackground, object: true) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Edit Card") { NotificationCenter.default.post(name: .toggleEditBackground, object: false) }
            Divider()
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

struct ArrangeMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Arrange") {
            Button("Bring Forward") { NotificationCenter.default.post(name: .bringForward, object: nil) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Send Backward") { NotificationCenter.default.post(name: .sendBackward, object: nil) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
            Button("Bring to Front") { NotificationCenter.default.post(name: .bringToFront, object: nil) }
                .keyboardShortcut("+", modifiers: [.command, .shift])
            Button("Send to Back") { NotificationCenter.default.post(name: .sendToBack, object: nil) }
                .keyboardShortcut("-", modifiers: [.command, .shift])
            Divider()
            Button("Align Left") { NotificationCenter.default.post(name: .alignLeft, object: nil) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Align Right") { NotificationCenter.default.post(name: .alignRight, object: nil) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Align Top") { NotificationCenter.default.post(name: .alignTop, object: nil) }
            Button("Align Bottom") { NotificationCenter.default.post(name: .alignBottom, object: nil) }
            Button("Align Horizontal Center") { NotificationCenter.default.post(name: .alignHCenter, object: nil) }
            Button("Align Vertical Center") { NotificationCenter.default.post(name: .alignVCenter, object: nil) }
            Divider()
            Button("Distribute Horizontally") { NotificationCenter.default.post(name: .distributeH, object: nil) }
            Button("Distribute Vertically") { NotificationCenter.default.post(name: .distributeV, object: nil) }
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
    static let toggleEditBackground = Notification.Name("toggleEditBackground")
    static let bringForward = Notification.Name("bringForward")
    static let sendBackward = Notification.Name("sendBackward")
    static let bringToFront = Notification.Name("bringToFront")
    static let sendToBack = Notification.Name("sendToBack")
    static let toggleAI = Notification.Name("toggleAI")
    static let alignLeft = Notification.Name("alignLeft")
    static let alignRight = Notification.Name("alignRight")
    static let alignTop = Notification.Name("alignTop")
    static let alignBottom = Notification.Name("alignBottom")
    static let alignHCenter = Notification.Name("alignHCenter")
    static let alignVCenter = Notification.Name("alignVCenter")
    static let distributeH = Notification.Name("distributeH")
    static let distributeV = Notification.Name("distributeV")
}

struct AIMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("AI") {
            Button("Show AI Assistant") {
                NotificationCenter.default.post(name: .toggleAI, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }
}

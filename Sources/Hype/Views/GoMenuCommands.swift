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
    @AppStorage("hypeRuntimeMode") private var isRuntimeMode: Bool = false
    @AppStorage("hypeObjectsPanelVisible") private var objectsPanelVisible: Bool = true

    var body: some Commands {
        CommandMenu("Tools") {
            Button(isRuntimeMode ? "Switch to Edit Mode" : "Switch to Runtime Mode") {
                NotificationCenter.default.post(name: .toggleRuntimeMode, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button(objectsPanelVisible ? "Hide Objects Panel" : "Show Objects Panel") {
                NotificationCenter.default.post(name: .toggleObjectsPanel, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

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
            Divider()
            Button("Sprite Area") { NotificationCenter.default.post(name: .selectTool, object: ToolName.spriteArea) }
            Button("Sprite Repository...") {
                NotificationCenter.default.post(name: .openSpriteRepository, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

/// Adds Theme-related items to the existing Edit menu.
///
/// Edit is a system-managed menu (DocumentGroup creates it via the
/// standard pasteboard commands), so we splice in via
/// `CommandGroup(after: .pasteboard)` rather than declaring a fresh
/// `CommandMenu("Edit")` — the latter would produce a duplicate Edit
/// menu next to the system one.
struct EditMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Themes...") {
                NotificationCenter.default.post(name: .openThemeDesigner, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
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
    static let showAllCards = Notification.Name("showAllCards")
    static let openSpriteRepository = Notification.Name("openSpriteRepository")
    static let toggleRuntimeMode = Notification.Name("toggleRuntimeMode")
    static let toggleObjectsPanel = Notification.Name("toggleObjectsPanel")
    static let haltAIChat = Notification.Name("haltAIChat")
    /// Posted by `CardCanvasView.Coordinator` when a HypeTalk runtime
    /// or parse error is surfaced during dispatch. `userInfo` contains:
    ///   - `"target"`: a `ScriptTarget` value (part / card / background
    ///     / stack / hype) identifying the script to open
    ///   - `"partId"`: a `UUID` (only when target is `.part(_)`), used
    ///     as the legacy `partId` argument to `openScriptEditorWindow`
    ///   - `"line"`: an `Int` line number (1-based) to highlight in the
    ///     script editor, or `0` if the error has no line info
    ///   - `"message"`: a `String` error description for display
    ///   - `"handler"`: a `String` handler name (e.g. "idle") for
    ///     context in the error banner
    ///
    /// `MainContentView` listens for this and opens the script editor
    /// for the offending object with the error line highlighted.
    static let showScriptError = Notification.Name("showScriptError")
    /// Posted by `openScriptEditorWindow` when it reuses an
    /// already-open script editor window for a runtime error
    /// instead of opening a new one. The currently-displayed
    /// `ScriptEditor` listens for this and refreshes its red error
    /// stripe and the bottom error banner without rebuilding the
    /// view. `userInfo` carries:
    ///   - `"identityKey"`: a `String` matching `ScriptTarget
    ///     .identityKey` so a stale editor for some other target
    ///     ignores the broadcast
    ///   - `"line"`: an `Int` 1-based line number to highlight
    ///   - `"message"`: a `String` description for the banner
    ///
    /// This is the second half of the "no runaway windows on
    /// repeated runtime errors" fix — the first half is the
    /// dedup map in `openScriptEditorWindow` itself.
    static let refreshScriptError = Notification.Name("refreshScriptError")
    /// Posted by `CardCanvasNSView.mouseUp` when the user Cmd+clicks
    /// a part or empty space in browse mode. `userInfo` carries
    /// either `"partId": UUID` (for a part) or `"cardId": UUID`
    /// (for the card). `MainContentView` listens and opens the
    /// script editor via `openScriptEditorWindow`.
    static let openPartScriptEditor = Notification.Name("openPartScriptEditor")
    /// Reveal a node inside a Sprite Area inspector. `userInfo` carries
    /// `partId`, `sceneId`, and `nodeId`.
    static let revealSpriteNode = Notification.Name("revealSpriteNode")
    /// Internal follow-up posted by `MainContentView` after it has
    /// selected the owning part and navigated to the right card.
    static let focusSpriteNodeInInspector = Notification.Name("focusSpriteNodeInInspector")
    /// Select an asset inside the detached Sprite Repository window.
    /// `userInfo["assetId"]` contains the repository asset UUID.
    static let selectSpriteRepositoryAsset = Notification.Name("selectSpriteRepositoryAsset")
    /// Posted by the Edit > Themes... menu item AND by the Theme
    /// section's "Edit Themes..." button in the Property Inspector.
    /// `MainContentView` listens and opens (or focuses) the detached
    /// Theme Designer window via `openThemeDesignerWindow`.
    static let openThemeDesigner = Notification.Name("hype.openThemeDesigner")
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

/// Adds items to the existing Window menu (created by DocumentGroup)
/// rather than creating a duplicate "Window" menu.
struct WindowMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .windowList) {
            Divider()
            Button("Show Console") {
                NotificationCenter.default.post(name: .showConsole, object: nil)
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let showConsole = Notification.Name("showConsole")
}

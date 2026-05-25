import SwiftUI
import HypeCore

// MARK: - Go menu (navigation + card/background management)

/// Card navigation + card/background management. Cleaned up so card-
/// management items live alongside the navigation verbs they relate
/// to, rather than being split across Go and Objects.
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

            Divider()

            Button("New Card") { NotificationCenter.default.post(name: .addNewCard, object: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Delete Current Card") { NotificationCenter.default.post(name: .deleteCurrentCard, object: nil) }

            Divider()

            Button("Edit Card") { NotificationCenter.default.post(name: .toggleEditBackground, object: false) }
            Button("Edit Background") { NotificationCenter.default.post(name: .toggleEditBackground, object: true) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("New Background…") { NotificationCenter.default.post(name: .addNewBackground, object: nil) }
        }
    }
}

// MARK: - Objects menu (control / part creation — canonical PartTypes)

/// One menu item per canonical ToolName that creates a new part. Replaces the
/// old "Objects" menu, which had only a handful of entries plus
/// dead `Card Info…` / `Background Info…` / `Stack Info…` stubs.
///
/// The menu items post `.selectTool` notifications — same channel
/// the toolbar uses — so picking "Calendar" from this menu puts the
/// canvas into the calendar drag-to-create mode just like clicking
/// the calendar icon in the left panel.
struct ObjectsMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Objects") {
            // Basic objects.
            Group {
                Button("Button") { NotificationCenter.default.post(name: .selectTool, object: ToolName.button) }
                Button("Field") { NotificationCenter.default.post(name: .selectTool, object: ToolName.field) }
                Button("Shape") { NotificationCenter.default.post(name: .selectTool, object: ToolName.shape) }
                Button("Image") { NotificationCenter.default.post(name: .selectTool, object: ToolName.image) }
                Button("Web Page") { NotificationCenter.default.post(name: .selectTool, object: ToolName.webpage) }
                Button("Video") { NotificationCenter.default.post(name: .selectTool, object: ToolName.video) }
                Button("Chart") { NotificationCenter.default.post(name: .selectTool, object: ToolName.chart) }
            }

            Divider()

            // Framework-backed controls (Phase 1 + 2 roadmap items).
            Group {
                Button("Calendar") { NotificationCenter.default.post(name: .selectTool, object: ToolName.calendar) }
                Button("PDF Viewer") { NotificationCenter.default.post(name: .selectTool, object: ToolName.pdf) }
                Button("Map") { NotificationCenter.default.post(name: .selectTool, object: ToolName.map) }
                Button("Color Well") { NotificationCenter.default.post(name: .selectTool, object: ToolName.colorWell) }
                Button("Audio Recorder") { NotificationCenter.default.post(name: .selectTool, object: ToolName.audioRecorder) }
                Button("Music Player") { NotificationCenter.default.post(name: .selectTool, object: ToolName.musicPlayer) }
                Button("Piano Keyboard") { NotificationCenter.default.post(name: .selectTool, object: ToolName.pianoKeyboard) }
                Button("Step Sequencer") { NotificationCenter.default.post(name: .selectTool, object: ToolName.stepSequencer) }
                Button("Music Mixer") { NotificationCenter.default.post(name: .selectTool, object: ToolName.musicMixer) }
                Button("MusicKit Search") { NotificationCenter.default.post(name: .selectTool, object: ToolName.appleMusicBrowser) }
                Button("3D Scene") { NotificationCenter.default.post(name: .selectTool, object: ToolName.scene3D) }
                Button("Sprite Area") { NotificationCenter.default.post(name: .selectTool, object: ToolName.spriteArea) }
            }

            Divider()

            // Form controls — share a controlValue backing.
            // Toggle removed in dedup — create as button + .toggle
            // style instead.
            Group {
                Button("Stepper") { NotificationCenter.default.post(name: .selectTool, object: ToolName.stepper) }
                Button("Slider") { NotificationCenter.default.post(name: .selectTool, object: ToolName.slider) }
                Button("Segmented Control") { NotificationCenter.default.post(name: .selectTool, object: ToolName.segmented) }
                Button("Progress View") { NotificationCenter.default.post(name: .selectTool, object: ToolName.progressView) }
                Button("Gauge") { NotificationCenter.default.post(name: .selectTool, object: ToolName.gauge) }
                Button("Divider") { NotificationCenter.default.post(name: .selectTool, object: ToolName.divider) }
            }
        }
    }
}

struct ArrangeMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Arrange") {
            Button("Group") { NotificationCenter.default.post(name: .groupSelection, object: nil) }
                .keyboardShortcut("g", modifiers: [.command, .option])
            Button("Ungroup") { NotificationCenter.default.post(name: .ungroupSelection, object: nil) }
                .keyboardShortcut("g", modifiers: [.command, .option, .shift])
            Divider()
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

// MARK: - Tools menu (selection + paint tools only)

/// Tools menu now contains only the "what does a click DO" tools —
/// browse, select, and the raster paint tools. Object-creation tools
/// moved to the dedicated Objects menu; mode/panel toggles moved to
/// the new View menu; the dead Sprite Repository entry moved to
/// Window where it belongs.
struct ToolsMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Tools") {
            Button("Browse") { NotificationCenter.default.post(name: .selectTool, object: ToolName.browse) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Select") { NotificationCenter.default.post(name: .selectTool, object: ToolName.select) }

            Divider()

            // Raster paint tools.
            Button("Pencil") { NotificationCenter.default.post(name: .selectTool, object: ToolName.pencil) }
            Button("Spray") { NotificationCenter.default.post(name: .selectTool, object: ToolName.spray) }
            Button("Bucket Fill") { NotificationCenter.default.post(name: .selectTool, object: ToolName.bucket) }
            Button("Eraser") { NotificationCenter.default.post(name: .selectTool, object: ToolName.eraser) }
        }
    }
}

// MARK: - View menu additions (mode + panel + window-visibility toggles)

/// Adds Hype's "show/hide a piece of UI" commands to the existing
/// system View menu. SwiftUI/DocumentGroup already creates a View
/// menu, so this must use `CommandGroup` rather than `CommandMenu` to
/// avoid a duplicate top-level View menu.
struct ViewMenuCommands: Commands {
    @AppStorage("hypeObjectsPanelVisible") private var objectsPanelVisible: Bool = true

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Switch Runtime/Edit Mode") {
                NotificationCenter.default.post(name: .toggleRuntimeMode, object: nil)
            }
            .help("Switch to Runtime Mode or back to Edit Mode for the current stack")
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button(objectsPanelVisible ? "Hide Objects Panel" : "Show Objects Panel") {
                NotificationCenter.default.post(name: .toggleObjectsPanel, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Menu("Emulate Target Device") {
                Button("Off") {
                    NotificationCenter.default.post(name: .setTargetEmulation, object: nil, userInfo: ["profileId": ""])
                }
                Divider()
                Button("macOS Default Card") {
                    NotificationCenter.default.post(name: .setTargetEmulation, object: nil, userInfo: ["profileId": "macos-default"])
                }
                Button("iPhone Portrait") {
                    NotificationCenter.default.post(name: .setTargetEmulation, object: nil, userInfo: ["profileId": "iphone-portrait"])
                }
                Button("iPhone Landscape") {
                    NotificationCenter.default.post(name: .setTargetEmulation, object: nil, userInfo: ["profileId": "iphone-landscape"])
                }
                Button("iPad Portrait") {
                    NotificationCenter.default.post(name: .setTargetEmulation, object: nil, userInfo: ["profileId": "ipad-portrait"])
                }
                Button("iPad Landscape") {
                    NotificationCenter.default.post(name: .setTargetEmulation, object: nil, userInfo: ["profileId": "ipad-landscape"])
                }
                Button("tvOS 1080p") {
                    NotificationCenter.default.post(name: .setTargetEmulation, object: nil, userInfo: ["profileId": "tvos-1080p"])
                }
            }

            Button("Show AI Assistant") {
                NotificationCenter.default.post(name: .toggleAI, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Show Console") {
                NotificationCenter.default.post(name: .showConsole, object: nil)
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
        }
    }
}

/// Adds Hype-specific items to the existing Edit menu.
///
/// Edit is a system-managed menu (DocumentGroup creates it via the
/// standard pasteboard commands), so we splice in via
/// `CommandGroup(after: .pasteboard)` rather than declaring a fresh
/// `CommandMenu("Edit")` — the latter would produce a duplicate Edit
/// menu next to the system one.
///
/// Note: the Themes menu item moved to Window (the Theme Designer is
/// a window, not an edit operation). This struct is currently empty
/// but kept as a stub so future Hype-specific Edit additions have a
/// place to go without re-introducing the parallel-Edit-menu bug.
struct EditMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) { }
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
    static let groupSelection = Notification.Name("groupSelection")
    static let ungroupSelection = Notification.Name("ungroupSelection")
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
    static let openAIContextLibrary = Notification.Name("openAIContextLibrary")
    static let toggleRuntimeMode = Notification.Name("toggleRuntimeMode")
    static let toggleObjectsPanel = Notification.Name("toggleObjectsPanel")
    static let setTargetEmulation = Notification.Name("setTargetEmulation")
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

// MARK: - AI menu (chat panel + AI-specific actions)

/// AI menu hosts AI-feature-specific actions. The "Show AI
/// Assistant" toggle now lives in View (with the other show/hide
/// commands), so this menu is reserved for actions that DO things
/// with the AI rather than just toggling its visibility — Halt
/// being the obvious example.
struct AIMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("AI") {
            Button("Halt Current Run") {
                NotificationCenter.default.post(name: .haltAIChat, object: nil)
            }
            .keyboardShortcut(".", modifiers: .command)
        }
    }
}

// MARK: - Window menu additions

/// Adds items to the existing Window menu (created by DocumentGroup)
/// rather than creating a duplicate "Window" menu. This is where
/// auxiliary windows live — sprite repository, theme designer, etc.
/// Console moved to View since it's a transient toggleable panel,
/// not a true window.
struct WindowMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .windowList) {
            Divider()
            Button("Sprite Repository") {
                NotificationCenter.default.post(name: .openSpriteRepository, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("AI Context Library") {
                NotificationCenter.default.post(name: .openAIContextLibrary, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Theme Designer") {
                NotificationCenter.default.post(name: .openThemeDesigner, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let showConsole = Notification.Name("showConsole")
}

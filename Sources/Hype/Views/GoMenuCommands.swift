import SwiftUI
import HypeCore

// MARK: - Go menu (navigation + card/background management)

/// Card navigation + card/background management. Cleaned up so card-
/// management items live alongside the navigation verbs they relate
/// to, rather than being split across Go and Objects.
struct GoMenuCommands: Commands {
    @FocusedValue(\.hypeAuthoringCommandContext) private var authoringCommands

    private var canUsePaintTools: Bool {
        authoringCommands?.userLevel.canUsePaintTools ?? false
    }

    private var canAuthorObjects: Bool {
        authoringCommands?.userLevel.canAuthorObjects ?? false
    }

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
                .disabled(!canAuthorObjects)
            Button("Delete Current Card") { NotificationCenter.default.post(name: .deleteCurrentCard, object: nil) }
                .disabled(!canAuthorObjects)

            Divider()

            Button("Edit Card") { NotificationCenter.default.post(name: .toggleEditBackground, object: false) }
                .disabled(!canUsePaintTools)
            Button("Edit Background") { NotificationCenter.default.post(name: .toggleEditBackground, object: true) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!canUsePaintTools)
            Button("New Background…") { NotificationCenter.default.post(name: .addNewBackground, object: nil) }
                .disabled(!canAuthorObjects)
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
    @FocusedValue(\.hypeAuthoringCommandContext) private var authoringCommands

    private var canAuthorObjects: Bool {
        authoringCommands?.userLevel.canAuthorObjects ?? false
    }

    var body: some Commands {
        CommandMenu("Objects") {
            // Basic objects.
            Group {
                Button("Button") { NotificationCenter.default.post(name: .selectTool, object: ToolName.button) }.disabled(!canAuthorObjects)
                Button("Field") { NotificationCenter.default.post(name: .selectTool, object: ToolName.field) }.disabled(!canAuthorObjects)
                Button("Shape") { NotificationCenter.default.post(name: .selectTool, object: ToolName.shape) }.disabled(!canAuthorObjects)
                Button("Image") { NotificationCenter.default.post(name: .selectTool, object: ToolName.image) }.disabled(!canAuthorObjects)
                Button("Web Page") { NotificationCenter.default.post(name: .selectTool, object: ToolName.webpage) }.disabled(!canAuthorObjects)
                Button("Video") { NotificationCenter.default.post(name: .selectTool, object: ToolName.video) }.disabled(!canAuthorObjects)
                Button("Chart") { NotificationCenter.default.post(name: .selectTool, object: ToolName.chart) }.disabled(!canAuthorObjects)
            }

            Divider()

            // Framework-backed controls (Phase 1 + 2 roadmap items).
            Group {
                Button("Calendar") { NotificationCenter.default.post(name: .selectTool, object: ToolName.calendar) }.disabled(!canAuthorObjects)
                Button("PDF Viewer") { NotificationCenter.default.post(name: .selectTool, object: ToolName.pdf) }.disabled(!canAuthorObjects)
                Button("Map") { NotificationCenter.default.post(name: .selectTool, object: ToolName.map) }.disabled(!canAuthorObjects)
                Button("Color Well") { NotificationCenter.default.post(name: .selectTool, object: ToolName.colorWell) }.disabled(!canAuthorObjects)
                Button("Audio Recorder") { NotificationCenter.default.post(name: .selectTool, object: ToolName.audioRecorder) }.disabled(!canAuthorObjects)
                Button("Music Player") { NotificationCenter.default.post(name: .selectTool, object: ToolName.musicPlayer) }.disabled(!canAuthorObjects)
                Button("Piano Keyboard") { NotificationCenter.default.post(name: .selectTool, object: ToolName.pianoKeyboard) }.disabled(!canAuthorObjects)
                Button("Step Sequencer") { NotificationCenter.default.post(name: .selectTool, object: ToolName.stepSequencer) }.disabled(!canAuthorObjects)
                Button("Music Mixer") { NotificationCenter.default.post(name: .selectTool, object: ToolName.musicMixer) }.disabled(!canAuthorObjects)
                Button("MusicKit Search") { NotificationCenter.default.post(name: .selectTool, object: ToolName.appleMusicBrowser) }.disabled(!canAuthorObjects)
                Button("3D Scene") { NotificationCenter.default.post(name: .selectTool, object: ToolName.scene3D) }.disabled(!canAuthorObjects)
                Button("Sprite Area") { NotificationCenter.default.post(name: .selectTool, object: ToolName.spriteArea) }.disabled(!canAuthorObjects)
            }

            Divider()

            // Form controls — share a controlValue backing.
            // Toggle removed in dedup — create as button + .toggle
            // style instead.
            Group {
                Button("Stepper") { NotificationCenter.default.post(name: .selectTool, object: ToolName.stepper) }.disabled(!canAuthorObjects)
                Button("Slider") { NotificationCenter.default.post(name: .selectTool, object: ToolName.slider) }.disabled(!canAuthorObjects)
                Button("Segmented Control") { NotificationCenter.default.post(name: .selectTool, object: ToolName.segmented) }.disabled(!canAuthorObjects)
                Button("Progress View") { NotificationCenter.default.post(name: .selectTool, object: ToolName.progressView) }.disabled(!canAuthorObjects)
                Button("Gauge") { NotificationCenter.default.post(name: .selectTool, object: ToolName.gauge) }.disabled(!canAuthorObjects)
                Button("Divider") { NotificationCenter.default.post(name: .selectTool, object: ToolName.divider) }.disabled(!canAuthorObjects)
            }
        }
    }
}

struct ArrangeMenuCommands: Commands {
    @FocusedValue(\.hypeAuthoringCommandContext) private var authoringCommands

    var body: some Commands {
        CommandMenu("Arrange") {
            Button("Group") { NotificationCenter.default.post(name: .groupSelection, object: nil) }
                .keyboardShortcut("g", modifiers: [.command, .option])
            Button("Ungroup") { NotificationCenter.default.post(name: .ungroupSelection, object: nil) }
                .keyboardShortcut("g", modifiers: [.command, .option, .shift])
            Divider()
            Button(authoringCommands?.layerTransferTitle ?? "Move to Background") {
                authoringCommands?.transferSelectionToAlternateLayer()
            }
            .disabled(!(authoringCommands?.canTransferSelectionToAlternateLayer ?? false))
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
/// the new View menu; the dead Asset Repository entry moved to
/// Window where it belongs.
struct ToolsMenuCommands: Commands {
    @FocusedValue(\.hypeAuthoringCommandContext) private var authoringCommands

    private var canUsePaintTools: Bool {
        authoringCommands?.userLevel.canUsePaintTools ?? false
    }

    private var canAuthorObjects: Bool {
        authoringCommands?.userLevel.canAuthorObjects ?? false
    }

    var body: some Commands {
        CommandMenu("Tools") {
            Button("Browse") { NotificationCenter.default.post(name: .selectTool, object: ToolName.browse) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Select") { NotificationCenter.default.post(name: .selectTool, object: ToolName.select) }
                .disabled(!canAuthorObjects)

            Divider()

            // Raster paint tools.
            Button("Pencil") { NotificationCenter.default.post(name: .selectTool, object: ToolName.pencil) }
                .disabled(!canUsePaintTools)
            Button("Spray") { NotificationCenter.default.post(name: .selectTool, object: ToolName.spray) }
                .disabled(!canUsePaintTools)
            Button("Bucket Fill") { NotificationCenter.default.post(name: .selectTool, object: ToolName.bucket) }
                .disabled(!canUsePaintTools)
            Button("Eraser") { NotificationCenter.default.post(name: .selectTool, object: ToolName.eraser) }
                .disabled(!canUsePaintTools)
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
    @FocusedValue(\.hypeAuthoringCommandContext) private var authoringCommands

    private var canAuthorObjects: Bool {
        authoringCommands?.userLevel.canAuthorObjects ?? false
    }

    private var canEditScripts: Bool {
        authoringCommands?.userLevel.canEditScripts ?? false
    }

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

            Button("Target Platforms…") {
                NotificationCenter.default.post(name: .showTargetPlatforms, object: nil)
            }
            .help("Choose the stack's deployment targets and primary design target")
            .disabled(!canAuthorObjects)

            Button("Export Runtime Packages…") {
                NotificationCenter.default.post(name: .exportRuntimePackages, object: nil)
            }
            .help("Generate runtime-only package artifacts for the selected target platforms")
            .disabled(!canAuthorObjects)

            Button("Test Stack in Simulator…") {
                NotificationCenter.default.post(name: .testStackInSimulator, object: nil)
            }
            .help("Build the current stack as a runtime-only app and launch it in Apple Simulator")
            .disabled(!canAuthorObjects)

            Menu("Emulate Target Device") {
                Button("Off") {
                    NotificationCenter.default.post(name: .setTargetEmulation, object: nil, userInfo: ["profileId": ""])
                }
                Divider()
                ForEach(HypeDeviceProfileCatalog.standardProfiles) { profile in
                    Button(profile.displayName) {
                        NotificationCenter.default.post(
                            name: .setTargetEmulation,
                            object: nil,
                            userInfo: ["profileId": profile.id]
                        )
                    }
                }
            }

            Button("Show AI Assistant") {
                NotificationCenter.default.post(name: .toggleAI, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(!canEditScripts)

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
struct EditMenuCommands: Commands {
    @FocusedValue(\.hypeAuthoringCommandContext) private var authoringCommands

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Duplicate") {
                authoringCommands?.duplicateSelection()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!(authoringCommands?.canDuplicateSelection ?? false))
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
    static let openAssetRepository = Notification.Name("openAssetRepository")
    static let openAIContextLibrary = Notification.Name("openAIContextLibrary")
    static let toggleRuntimeMode = Notification.Name("toggleRuntimeMode")
    static let toggleObjectsPanel = Notification.Name("toggleObjectsPanel")
    static let showTargetPlatforms = Notification.Name("showTargetPlatforms")
    static let exportRuntimePackages = Notification.Name("exportRuntimePackages")
    static let testStackInSimulator = Notification.Name("testStackInSimulator")
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
    /// Posted by authoring surfaces when the user requests a script
    /// editor. The canvas posts this for Command-Option-click on a
    /// part; inspectors and error surfaces may post explicit
    /// `ScriptTarget` values. `MainContentView` listens and opens the
    /// script editor via `openScriptEditorWindow` after checking the
    /// current stack user level.
    static let openPartScriptEditor = Notification.Name("openPartScriptEditor")
    /// Posted by a clickable console-log script error action. Unlike
    /// `.showScriptError`, this presents the editor in the current
    /// document window instead of opening a detached script window.
    static let openScriptErrorLink = Notification.Name("openScriptErrorLink")
    /// Reveal a node inside a Sprite Area inspector. `userInfo` carries
    /// `partId`, `sceneId`, and `nodeId`.
    static let revealSpriteNode = Notification.Name("revealSpriteNode")
    /// Internal follow-up posted by `MainContentView` after it has
    /// selected the owning part and navigated to the right card.
    static let focusSpriteNodeInInspector = Notification.Name("focusSpriteNodeInInspector")
    /// Select an asset inside the detached Asset Repository window.
    /// `userInfo["assetId"]` contains the repository asset UUID.
    static let selectAssetRepositoryAsset = Notification.Name("selectAssetRepositoryAsset")
    /// Posted by the Edit > Themes... menu item AND by the Theme
    /// section's "Edit Themes..." button in the Property Inspector.
    /// `MainContentView` listens and opens (or focuses) the detached
    /// Theme Designer window via `openThemeDesignerWindow`.
    static let openThemeDesigner = Notification.Name("hype.openThemeDesigner")
    static let cancelRunningScripts = Notification.Name("hype.cancelRunningScripts")
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
                NotificationCenter.default.post(name: .cancelRunningScripts, object: nil)
            }
            .keyboardShortcut(".", modifiers: .command)
        }
    }
}

// MARK: - Window menu additions

/// Adds items to the existing Window menu (created by DocumentGroup)
/// rather than creating a duplicate "Window" menu. This is where
/// auxiliary windows live — asset repository, theme designer, etc.
/// Console moved to View since it's a transient toggleable panel,
/// not a true window.
struct WindowMenuCommands: Commands {
    @FocusedValue(\.hypeAuthoringCommandContext) private var authoringCommands

    private var canAuthorObjects: Bool {
        authoringCommands?.userLevel.canAuthorObjects ?? false
    }

    private var canEditScripts: Bool {
        authoringCommands?.userLevel.canEditScripts ?? false
    }

    var body: some Commands {
        CommandGroup(after: .windowList) {
            Divider()
            Button("Asset Repository") {
                NotificationCenter.default.post(name: .openAssetRepository, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!canAuthorObjects)
            Button("AI Context Library") {
                NotificationCenter.default.post(name: .openAIContextLibrary, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!canEditScripts)
            Button("Theme Designer") {
                NotificationCenter.default.post(name: .openThemeDesigner, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!canAuthorObjects)
        }
    }
}

extension Notification.Name {
    static let showConsole = Notification.Name("showConsole")
}

import Foundation
import HypeCore

#if canImport(AppKit)
import AppKit

/// Production host-application provider that routes HypeTalk application-shell
/// commands to AppKit APIs.
///
/// Security note (for code reviewers)
/// -----------------------------------
/// A `.hype` stack can script app-shell commands such as `quit`, `save stack`,
/// and `doMenu "..."`. HyperCard compatibility requires `doMenu` to address the
/// full Hype menu surface, including commands that mutate the current stack. To
/// keep that broad surface bounded, `doMenu` executes only Hype-owned explicit
/// command names or real enabled `NSMenuItem` target/action entries already in
/// the app menu. It never constructs arbitrary selectors from script strings.
public struct AppKitHostApplicationProvider: HostApplicationProvider, Sendable {

    /// The stack UUID of the document that owns this provider.
    ///
    /// When non-nil, `doMenu` navigation posts are scoped to that specific
    /// document so they cannot accidentally mutate a background window.
    /// Pass `nil` (the default) only when no document context is available —
    /// legacy unscoped posts degrade to key-window-only delivery via
    /// `MenuCommandScoping.shouldHandle`.
    private let stackId: UUID?

    public init(stackId: UUID? = nil) {
        self.stackId = stackId
    }

    private static func normalizedToolKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    static func normalizedMenuKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: "&", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    private static func toolName(for name: String) -> ToolName? {
        switch normalizedToolKey(name) {
        case "browse", "browsetool":
            return .browse
        case "select", "selecttool":
            return .select
        case "button", "buttontool":
            return .button
        case "field", "text", "fieldtool":
            return .field
        case "shape", "shapetool":
            return .shape
        case "image", "imagetool":
            return .image
        case "video", "videotool":
            return .video
        case "chart", "charttool":
            return .chart
        case "webpage", "web", "webpagetool":
            return .webpage
        case "spritearea", "spritescene", "spriteareatool":
            return .spriteArea
        case "calendar":
            return .calendar
        case "pdf":
            return .pdf
        case "map":
            return .map
        case "colorwell":
            return .colorWell
        case "stepper":
            return .stepper
        case "slider":
            return .slider
        case "segmented":
            return .segmented
        case "audiorecorder", "recorder":
            return .audioRecorder
        case "scene3d", "model3d":
            return .scene3D
        case "musicplayer":
            return .musicPlayer
        case "pianokeyboard", "keyboard":
            return .pianoKeyboard
        case "stepsequencer", "sequencer":
            return .stepSequencer
        case "musicmixer", "mixer":
            return .musicMixer
        case "applemusicbrowser", "musickitsearch", "musicbrowser":
            return .appleMusicBrowser
        case "progressview", "progress":
            return .progressView
        case "gauge":
            return .gauge
        case "divider":
            return .divider
        case "pencil":
            return .pencil
        case "spray", "spraycan":
            return .spray
        case "bucket", "bucketfill", "paintbucket":
            return .bucket
        case "eraser":
            return .eraser
        default:
            return nil
        }
    }

    @MainActor
    private func postToolSelection(_ tool: ToolName) {
        NotificationCenter.default.post(
            name: .selectTool,
            object: tool,
            userInfo: MenuCommandScoping.userInfo(stackId: stackId)
        )
    }

    private func scopedUserInfo(_ additionalValues: [AnyHashable: Any] = [:]) -> [AnyHashable: Any]? {
        var userInfo = additionalValues
        if let stackId {
            userInfo[MenuCommandScoping.stackIdKey] = stackId
        }
        return userInfo.isEmpty ? nil : userInfo
    }

    @MainActor
    private func postScopedNotification(
        _ name: Notification.Name,
        object: Any? = nil,
        userInfo additionalValues: [AnyHashable: Any] = [:]
    ) {
        NotificationCenter.default.post(
            name: name,
            object: object,
            userInfo: scopedUserInfo(additionalValues)
        )
    }

    // MARK: - Screen lock / unlock

    /// Lock the screen: post a notification that `CardCanvasNSView` observes
    /// to suppress `needsDisplay` updates, reducing visual flicker during
    /// multi-step script mutations.
    public func lockScreen() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .hypeScreenLock, object: nil)
        }
    }

    /// Unlock the screen: post a notification that `CardCanvasNSView` observes
    /// to re-enable redraws and trigger an immediate refresh.
    public func unlockScreen() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .hypeScreenUnlock, object: nil)
        }
    }

    public func chooseTool(_ name: String) async -> Bool {
        guard let tool = Self.toolName(for: name) else { return false }
        await MainActor.run {
            postToolSelection(tool)
        }
        return true
    }

    // MARK: - Stack file operations

    /// Open a `.hype` stack at the given absolute path.
    ///
    /// - Guards: path must be non-empty, have a `.hype` extension, and point to
    ///   an existing file.  Malformed paths are silently ignored — they must not
    ///   crash, and a hostile stack cannot use this to open arbitrary file types.
    public func openStack(path: String) async {
        guard let resolved = Self.resolvedStackURL(forPath: path) else { return }
        await MainActor.run {
            NSDocumentController.shared.openDocument(withContentsOf: resolved, display: true) { _, _, _ in }
        }
    }

    /// Validate + canonicalize a script-supplied stack path, returning the URL
    /// to open or `nil` when it must be refused. Pure + testable (security
    /// review Finding 2 — CWE-22). Canonicalizes BEFORE the extension/existence
    /// guards so `..` components and symlinks can't smuggle a non-`.hype`
    /// target past the extension check.
    static func resolvedStackURL(forPath path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: path).standardized.resolvingSymlinksInPath()
        guard resolved.pathExtension.lowercased() == "hype" else { return nil }
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        return resolved
    }

    /// Trigger an autosave of the frontmost document.
    public func saveStack() async {
        await MainActor.run {
            guard let doc = NSDocumentController.shared.currentDocument
                      ?? NSDocumentController.shared.documents.first
            else { return }
            doc.save(self)
        }
    }

    /// Perform a close on the frontmost window (honoring the document's
    /// unsaved-changes prompt).
    public func closeWindow() async {
        await MainActor.run {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            window.performClose(nil)
        }
    }

    // MARK: - Application lifecycle

    /// Terminate the application.  Equivalent to File > Quit.
    public func quitApp() async {
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Script editor

    /// Open the Script Editor for the object identified by `objectId`.
    ///
    /// Uses the same `openPartScriptEditor` notification that
    /// `CardCanvasAccessibility` and cmd+click already use, so `MainContentView`
    /// handles the actual window-management.  When `objectId` is `nil` the
    /// notification carries no part info and the handler falls through to the
    /// current card's editor.
    public func editScript(ofObjectId objectId: UUID?) async {
        await MainActor.run {
            var userInfo: [AnyHashable: Any] = [:]
            if let objectId {
                userInfo["partId"] = objectId
                userInfo["target"] = ScriptTarget.part(objectId)
            }
            NotificationCenter.default.post(
                name: .openPartScriptEditor,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    // MARK: - Print

    /// Print the current card as a rendered bitmap, or the text content of a
    /// named field.
    ///
    /// Runs entirely on the main actor because `CardRenderer.renderToImage` and
    /// `NSPrintOperation` are both main-thread APIs.
    public func print(target: HostPrintTarget) async {
        await MainActor.run {
            switch target {
            case .card:
                printCurrentCard()
            case .field(let identifier):
                printField(identifier: identifier)
            }
        }
    }

    @MainActor
    private func printCurrentCard() {
        // Gather the document + current card from the focused document window.
        guard let notification = currentDocumentInfo() else { return }
        let (document, cardId) = notification

        let renderer = CardRenderer()
        let size = NSSize(width: 800, height: 600)
        let image = renderer.renderToImage(document: document, cardId: cardId, size: size)

        let printView = NSImageView(frame: NSRect(origin: .zero, size: size))
        printView.image = image

        let op = NSPrintOperation(view: printView)
        op.run()
    }

    @MainActor
    private func printField(identifier: String) {
        guard let notification = currentDocumentInfo() else { return }
        let (document, cardId) = notification

        // Find the field by name or ordinal on the current card.
        let field = document.parts.first(where: {
            $0.partType == .field && $0.cardId == cardId &&
            ($0.name.lowercased() == identifier.lowercased() || "\($0.id)" == identifier)
        }) ?? document.parts.first(where: {
            $0.partType == .field && $0.cardId == cardId
        })
        let text = field?.textContent ?? ""

        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        printView.string = text

        let op = NSPrintOperation(view: printView)
        op.run()
    }

    // MARK: - doMenu

    /// Execute a named menu item.
    ///
    /// The dispatch order is:
    /// 1. Hype-owned explicit SwiftUI command names that otherwise may not have
    ///    stable AppKit target/action entries.
    /// 2. Common responder-chain commands used by system menus.
    /// 3. The actual enabled item in `NSApplication.shared.mainMenu`.
    ///
    /// This intentionally supports mutating menu items. User-level and document
    /// targeting gates live in the same notification handlers used by the visible
    /// menu, so script calls and user clicks share behavior.
    public func doMenu(item: String) async -> Bool {
        let key = Self.normalizedMenuKey(item)
        guard !key.isEmpty else { return false }

        return await MainActor.run {
            if dispatchExplicitHypeMenuItem(key) { return true }
            if dispatchStandardResponderMenuItem(key) { return true }
            return dispatchMainMenuItem(key)
        }
    }

    @MainActor
    private func dispatchExplicitHypeMenuItem(_ key: String) -> Bool {
        switch key {
        // Go menu.
        case "first", "firstcard":
            postScopedNotification(.navigateCard, object: NavigationDirection.first)
        case "prev", "previous", "prevcard", "previouscard":
            postScopedNotification(.navigateCard, object: NavigationDirection.previous)
        case "next", "nextcard":
            postScopedNotification(.navigateCard, object: NavigationDirection.next)
        case "last", "lastcard":
            postScopedNotification(.navigateCard, object: NavigationDirection.last)
        case "back":
            postScopedNotification(.navigateCard, object: NavigationDirection.previous)
        case "newcard":
            postScopedNotification(.addNewCard)
        case "deletecard", "deletecurrentcard":
            postScopedNotification(.deleteCurrentCard)
        case "editcard":
            postScopedNotification(.toggleEditBackground, object: false)
        case "editbackground":
            postScopedNotification(.toggleEditBackground, object: true)
        case "newbackground":
            postScopedNotification(.addNewBackground)

        // Objects menu.
        case "button":
            postToolSelection(.button)
        case "field":
            postToolSelection(.field)
        case "shape":
            postToolSelection(.shape)
        case "image":
            postToolSelection(.image)
        case "webpage", "web":
            postToolSelection(.webpage)
        case "video":
            postToolSelection(.video)
        case "chart":
            postToolSelection(.chart)
        case "calendar":
            postToolSelection(.calendar)
        case "pdf", "pdfviewer":
            postToolSelection(.pdf)
        case "map":
            postToolSelection(.map)
        case "colorwell":
            postToolSelection(.colorWell)
        case "audiorecorder":
            postToolSelection(.audioRecorder)
        case "musicplayer":
            postToolSelection(.musicPlayer)
        case "pianokeyboard":
            postToolSelection(.pianoKeyboard)
        case "stepsequencer":
            postToolSelection(.stepSequencer)
        case "musicmixer":
            postToolSelection(.musicMixer)
        case "musickitsearch", "applemusicbrowser":
            postToolSelection(.appleMusicBrowser)
        case "3dscene", "scene3d":
            postToolSelection(.scene3D)
        case "spritearea":
            postToolSelection(.spriteArea)
        case "stepper":
            postToolSelection(.stepper)
        case "slider":
            postToolSelection(.slider)
        case "segmentedcontrol", "segmented":
            postToolSelection(.segmented)
        case "progressview":
            postToolSelection(.progressView)
        case "gauge":
            postToolSelection(.gauge)
        case "divider":
            postToolSelection(.divider)

        // Arrange menu.
        case "group":
            postScopedNotification(.groupSelection)
        case "ungroup":
            postScopedNotification(.ungroupSelection)
        case "duplicate":
            postScopedNotification(.duplicateSelection)
        case "movetobackground", "movetocard":
            postScopedNotification(.transferSelectionToAlternateLayer)
        case "bringforward":
            postScopedNotification(.bringForward)
        case "sendbackward":
            postScopedNotification(.sendBackward)
        case "bringtofront":
            postScopedNotification(.bringToFront)
        case "sendtoback":
            postScopedNotification(.sendToBack)
        case "alignleft":
            postScopedNotification(.alignLeft)
        case "alignright":
            postScopedNotification(.alignRight)
        case "aligntop":
            postScopedNotification(.alignTop)
        case "alignbottom":
            postScopedNotification(.alignBottom)
        case "alignhorizontalcenter":
            postScopedNotification(.alignHCenter)
        case "alignverticalcenter":
            postScopedNotification(.alignVCenter)
        case "distributehorizontally":
            postScopedNotification(.distributeH)
        case "distributevertically":
            postScopedNotification(.distributeV)

        // Tools menu.
        case "browse":
            postToolSelection(.browse)
        case "select":
            postToolSelection(.select)
        case "pencil":
            postToolSelection(.pencil)
        case "spray":
            postToolSelection(.spray)
        case "bucketfill", "bucket", "paintbucket":
            postToolSelection(.bucket)
        case "eraser":
            postToolSelection(.eraser)

        // View / AI / Window menu additions.
        case "switchruntimeeditmode", "runtimeeditmode":
            postScopedNotification(.toggleRuntimeMode)
        case "showobjectspanel", "hideobjectspanel", "toggleobjectspanel":
            postScopedNotification(.toggleObjectsPanel)
        case "targetplatforms":
            postScopedNotification(.showTargetPlatforms)
        case "exportruntimepackages":
            postScopedNotification(.exportRuntimePackages)
        case "teststackinsimulator":
            postScopedNotification(.testStackInSimulator)
        case "showaiassistant", "hideaiassistant", "aiassistant":
            postScopedNotification(.toggleAI)
        case "showconsole", "console":
            postScopedNotification(.showConsole)
        case "haltcurrentrun", "halt":
            postScopedNotification(.haltAIChat)
            postScopedNotification(.cancelRunningScripts)
        case "assetrepository":
            postScopedNotification(.openAssetRepository)
        case "aicontextlibrary":
            postScopedNotification(.openAIContextLibrary)
        case "themedesigner", "themes":
            postScopedNotification(.openThemeDesigner)
        default:
            return false
        }
        return true
    }

    @MainActor
    private func dispatchStandardResponderMenuItem(_ key: String) -> Bool {
        switch key {
        case "selectall":
            _ = NSApplication.shared.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
            return true
        case "copy":
            _ = NSApplication.shared.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            return true
        case "paste":
            _ = NSApplication.shared.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return true
        case "cut":
            _ = NSApplication.shared.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            return true
        case "clear", "delete":
            _ = NSApplication.shared.sendAction(NSSelectorFromString("delete:"), to: nil, from: nil)
            return true
        case "undo":
            _ = NSApplication.shared.sendAction(NSSelectorFromString("undo:"), to: nil, from: nil)
            return true
        case "redo":
            _ = NSApplication.shared.sendAction(NSSelectorFromString("redo:"), to: nil, from: nil)
            return true
        case "save":
            guard let document = NSDocumentController.shared.currentDocument
                    ?? NSDocumentController.shared.documents.first else { return false }
            document.save(nil)
            return true
        case "close", "closewindow":
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return false }
            window.performClose(nil)
            return true
        case "print":
            printCurrentCard()
            return true
        default:
            return false
        }
    }

    @MainActor
    private func dispatchMainMenuItem(_ key: String) -> Bool {
        guard let mainMenu = NSApplication.shared.mainMenu,
              let item = Self.findMenuItem(in: mainMenu, matching: key),
              item.isEnabled,
              let action = item.action else {
            return false
        }
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    @MainActor
    private static func findMenuItem(in menu: NSMenu, matching key: String) -> NSMenuItem? {
        for item in menu.items where !item.isSeparatorItem {
            if normalizedMenuKey(item.title) == key {
                return item
            }
            if let submenu = item.submenu,
               let match = findMenuItem(in: submenu, matching: key) {
                return match
            }
        }
        return nil
    }

    // MARK: - Menus

    /// Return the titles of every top-level menu in the application's menu bar.
    ///
    /// Reads `NSApplication.shared.mainMenu` on the main actor and returns the
    /// titles of all items that have a submenu (i.e. the top-level menu titles
    /// such as "Apple", "File", "Edit", "Go", "Window", "Help").  Items without
    /// a submenu (separators and bare menu items at top level) are excluded.
    public func menuTitles() async -> [String] {
        await MainActor.run {
            guard let mainMenu = NSApplication.shared.mainMenu else { return [] }
            return mainMenu.items
                .filter { $0.submenu != nil }
                .compactMap { $0.title.isEmpty ? nil : $0.title }
        }
    }

    // MARK: - Private helpers

    /// Retrieve the HypeDocument and current card UUID from the focused window's
    /// notification post, falling back to the first open document.
    ///
    /// Returns `nil` if no document is currently open.
    /// Single-entry cache so a pathological `repeat N times / print`
    /// loop doesn't re-read + re-decode the document file from disk on
    /// every iteration (security review Finding 3 — main-thread self-DoS).
    /// Keyed on (path, modification date); invalidated automatically when
    /// the file changes. Main-actor-isolated, so the mutable static is safe.
    @MainActor
    private static var printDocCache: (path: String, mtime: Date, doc: HypeDocument, cardId: UUID)?

    @MainActor
    private func currentDocumentInfo() -> (HypeDocument, UUID)? {
        // The focused document publishes its state via a SwiftUI FocusedValue;
        // since we cannot read that from here, we look up the current NSDocument
        // and read the last-saved state from the mutation coordinator's snapshot.
        // For printing this is accurate enough.
        guard let nsDoc = NSDocumentController.shared.currentDocument
                  ?? NSDocumentController.shared.documents.first,
              let url = nsDoc.fileURL
        else { return nil }

        // Reuse the cached decode when the file is unchanged since last read.
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if let cache = Self.printDocCache,
           cache.path == url.path,
           let mtime, cache.mtime == mtime {
            return (cache.doc, cache.cardId)
        }

        // Try to decode the on-disk state; if unavailable, bail gracefully.
        guard let data = try? Data(contentsOf: url),
              let hypeDoc = try? JSONDecoder().decode(HypeDocument.self, from: data)
        else { return nil }

        let cardId = hypeDoc.sortedCards.first?.id ?? hypeDoc.stack.id
        if let mtime {
            Self.printDocCache = (url.path, mtime, hypeDoc, cardId)
        }
        return (hypeDoc, cardId)
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted by `AppKitHostApplicationProvider.lockScreen()` to suppress
    /// canvas redraws during bulk HypeTalk mutations.
    static let hypeScreenLock = Notification.Name("hypeScreenLock")
    /// Posted by `AppKitHostApplicationProvider.unlockScreen()` to re-enable
    /// canvas redraws and trigger an immediate refresh.
    static let hypeScreenUnlock = Notification.Name("hypeScreenUnlock")
}

#endif

import SwiftUI
import HypeCore
import UniformTypeIdentifiers

/// App delegate to handle quit lifecycle, dispatch the "quit" system message,
/// and save/restore window state across launches.
@MainActor
final class HypeAppDelegate: NSObject, NSApplicationDelegate {
    private let launchState = AppLaunchState()
    private var pendingWindowFrame: NSRect?
    private var hasAppliedPendingFrame = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        pendingWindowFrame = launchState.visibleWindowFrame(
            using: NSScreen.screens.map(\.visibleFrame)
        )
        installWindowObservers()

        if let lastURL = launchState.lastOpenedFileURL {
            openDocument(at: lastURL)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if launchState.lastOpenedFileURL != nil {
            return false
        }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }

        if let lastURL = launchState.lastOpenedFileURL {
            openDocument(at: lastURL)
            return true
        }

        if let window = sender.windows.first {
            window.makeKeyAndOrderFront(nil)
            applyPendingWindowFrame(to: window)
            return true
        }

        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Dispatch "quit" message to the current card of each open document.
        // This gives scripts a chance to run cleanup handlers before the app exits.
        NotificationCenter.default.post(name: .hypeQuit, object: nil)

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            persistState(for: window)
        }

        if let doc = NSDocumentController.shared.currentDocument ?? NSDocumentController.shared.documents.first,
           let url = doc.fileURL {
            launchState.save(fileURL: url)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func installWindowObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowDidBecomeMain(_:)), name: NSWindow.didBecomeMainNotification, object: nil)
        center.addObserver(self, selector: #selector(windowDidMoveOrResize(_:)), name: NSWindow.didMoveNotification, object: nil)
        center.addObserver(self, selector: #selector(windowDidMoveOrResize(_:)), name: NSWindow.didResizeNotification, object: nil)
        center.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    private func openDocument(at url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] document, _, error in
            guard let self else { return }

            if error != nil && document == nil {
                self.launchState.clearLastOpenedFile()
                NSDocumentController.shared.newDocument(nil)
            }

            if let window = document?.windowControllers.first?.window {
                self.applyPendingWindowFrame(to: window)
            } else if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                self.applyPendingWindowFrame(to: window)
            }
        }
    }

    private func persistState(for window: NSWindow) {
        launchState.save(windowFrame: window.frame)
        if let url = fileURL(for: window) {
            launchState.save(fileURL: url)
        }
    }

    private func fileURL(for window: NSWindow) -> URL? {
        NSDocumentController.shared.documents.first { document in
            document.windowControllers.contains { $0.window === window }
        }?.fileURL
    }

    private func applyPendingWindowFrame(to window: NSWindow?) {
        guard !hasAppliedPendingFrame,
              let frame = pendingWindowFrame,
              let window else { return }
        window.setFrame(frame, display: true)
        hasAppliedPendingFrame = true
    }

    @objc
    private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        persistState(for: window)
        applyPendingWindowFrame(to: window)
    }

    @objc
    private func windowDidMoveOrResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        persistState(for: window)
    }

    @objc
    private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        persistState(for: window)
    }
}

extension Notification.Name {
    static let hypeQuit = Notification.Name("hypeQuit")
}

@main
struct HypeApp: App {
    @NSApplicationDelegateAdaptor(HypeAppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: HypeDocumentWrapper()) { file in
            MainContentView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
            }
            // Menu order follows the macOS HIG convention used by
            // Pages, Keynote, and Xcode: standard menus (File, Edit,
            // View) come first, then app-specific menus (Go,
            // Objects, Arrange, Tools, AI), with Window and Help
            // last. Window is added by SwiftUI; Help is added by
            // the system.
            EditMenuCommands()
            ViewMenuCommands()
            GoMenuCommands()
            ObjectsMenuCommands()
            ArrangeMenuCommands()
            ToolsMenuCommands()
            AIMenuCommands()
            WindowMenuCommands()
        }

        Settings {
            // Bridge the focused-document binding into PreferencesView
            // so the "Enable for Current Stack" toggle can actually
            // reach the front document. SwiftUI `Settings { }` is a
            // separate scene that doesn't implicitly track the focused
            // FileDocument — we publish the binding via
            // `.focusedSceneValue(\.hypeCurrentDocument, $document)` in
            // `MainContentView` and consume it here via `@FocusedValue`.
            PreferencesSceneWrapper()
        }
    }
}

// MARK: - FocusedValue bridge for the Settings scene

/// `FocusedValueKey` that publishes the binding to the front Hype
/// document wrapper. Used by the Settings scene to edit per-stack
/// preferences — specifically `stack.webAssetsAllowed` — from the
/// global Preferences window without introducing an `NSDocument`
/// round-trip (Hype is SwiftUI-native and uses `FileDocument`).
struct HypeCurrentDocumentKey: FocusedValueKey {
    typealias Value = Binding<HypeDocumentWrapper>
}

extension FocusedValues {
    /// Binding to the focused document wrapper, published from
    /// `MainContentView` via `.focusedSceneValue(...)`. `nil` when no
    /// document window is focused (e.g. Preferences is open with no
    /// other window in front).
    var hypeCurrentDocument: Binding<HypeDocumentWrapper>? {
        get { self[HypeCurrentDocumentKey.self] }
        set { self[HypeCurrentDocumentKey.self] = newValue }
    }
}

/// Small wrapper that reads the focused document binding from
/// `@FocusedValue` and hands it to `PreferencesView`. Kept separate
/// so `PreferencesView` itself stays decoupled from the
/// `FocusedValue` machinery and remains unit-testable with a plain
/// `Binding<HypeDocumentWrapper?>`.
struct PreferencesSceneWrapper: View {
    @FocusedValue(\.hypeCurrentDocument) private var focusedDocument: Binding<HypeDocumentWrapper>?

    var body: some View {
        // Bridge `Binding<HypeDocumentWrapper>?` (focused value) into
        // the `Binding<HypeDocumentWrapper?>` that `PreferencesView`
        // expects. The set closure writes back through the focused
        // binding when one is present — Finding 13's re-resolve-at-
        // write-time guarantee falls out naturally because
        // `@FocusedValue` re-evaluates with the current focus on
        // every render.
        let bridged = Binding<HypeDocumentWrapper?>(
            get: { focusedDocument?.wrappedValue },
            set: { newValue in
                guard let newValue, let focusedDocument else { return }
                focusedDocument.wrappedValue = newValue
            }
        )
        PreferencesView(document: bridged)
    }
}

/// Wrapper to make HypeDocument work with SwiftUI DocumentGroup.
struct HypeDocumentWrapper: FileDocument {
    var document: HypeDocument

    static var readableContentTypes: [UTType] { [.hypeStack] }

    init() {
        self.document = HypeDocument.newDocument()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.document = try JSONDecoder().decode(HypeDocument.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(document)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let hypeStack = UTType(exportedAs: "com.hype.stack", conformingTo: .json)
}

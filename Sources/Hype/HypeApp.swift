import SwiftUI
import HypeCore
import UniformTypeIdentifiers
import AppKit

/// App delegate to handle quit lifecycle, dispatch the "quit" system message,
/// and save/restore window state across launches.
@MainActor
final class HypeAppDelegate: NSObject, NSApplicationDelegate {
    private let launchState = AppLaunchState()
    private var pendingWindowFrame: NSRect?
    private var hasAppliedPendingFrame = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Halve the system tooltip delay. AppKit reads the
        // `NSInitialToolTipDelay` UserDefaults key when deciding
        // how long to wait before showing a tooltip; the platform
        // default is ~750ms, which feels sluggish for hover help
        // on tightly-packed tool palettes and authored stack
        // controls. 0.35s ≈ half of that — still long enough not
        // to fire while the user is just sweeping the cursor
        // across the screen, but short enough to feel responsive
        // when they actually pause on a control. Applies to every
        // `.help(...)` modifier and every per-part NSToolTip we
        // register on `CardCanvasNSView`.
        UserDefaults.standard.set(0.35, forKey: "NSInitialToolTipDelay")

        pendingWindowFrame = launchState.visibleWindowFrame(
            using: NSScreen.screens.map(\.visibleFrame)
        )
        installWindowObservers()

        if let lastURL = launchState.lastOpenedFileURL {
            openDocument(at: lastURL)
        }

        // Force a proper activation cycle on the first window.
        //
        // SwiftUI's `DocumentGroup` opens its first window in the
        // "key" state directly, without going through a
        // resignKey → becomeKey transition. The .help() / NSToolTip
        // tracking areas are registered LAZILY in response to
        // those becomeKey/becomeMain notifications, so at first
        // launch the tracking areas exist on disk but aren't yet
        // dispatching. The user sees: hovering tool icons in the
        // left panel does nothing — until they tab away from Hype
        // and back, at which point AppKit fires the proper
        // resignKey → becomeKey cycle and tooltips start working.
        //
        // Calling `NSApp.activate(ignoringOtherApps: true)` after
        // the first runloop tick (so the document window has had
        // a chance to actually appear) forces the same cycle
        // explicitly: AppKit re-evaluates window state, runs the
        // becomeKey/becomeMain notifications, and the tracking
        // areas register without needing the user to tab.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
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
        HypeDocumentMutationCoordinator.shared.flushAllAutosaves()

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            persistState(for: window)
        }

        if let doc = NSDocumentController.shared.currentDocument ?? NSDocumentController.shared.documents.first,
           let url = doc.fileURL {
            launchState.save(fileURL: url)
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
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
        // Belt-and-suspenders for the tooltip-doesn't-fire-at-
        // launch issue. NSToolTip uses tracking areas which
        // generally don't need `acceptsMouseMovedEvents`, but
        // setting it true ensures the window's content view
        // delivers mouseMoved through the responder chain — some
        // SwiftUI tooltip code paths depend on that. Cheap to
        // set, defensive against future regressions.
        window.acceptsMouseMovedEvents = true
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
        HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
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
                Button("Import HyperCard Stack…") {
                    HyperCardImportPanel.open()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
            }
            // Menu order follows the macOS HIG convention used by
            // Pages, Keynote, and Xcode: standard menus (File, Edit,
            // View) come first, then app-specific menus (Go,
            // Objects, Arrange, Tools, AI), with Window and Help
            // last. SwiftUI supplies View/Window/Help, so Hype
            // inserts additions with CommandGroup rather than
            // declaring duplicate top-level menus.
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
        // binding when one is present.
        //
        // Fallback: when Preferences becomes the focused scene
        // (typical the moment the user opens it via Cmd-,), the
        // document scene loses focus and `@FocusedValue` returns nil
        // — making per-stack toggles permanently disabled. We fall
        // back to `HypeDocumentMutationCoordinator.activeDocumentBinding`
        // which `MainContentView` keeps current on appear/disappear,
        // so the toggle stays live across the focus transition.
        let bridged = Binding<HypeDocumentWrapper?>(
            get: {
                if let focused = focusedDocument {
                    return focused.wrappedValue
                }
                return HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue
            },
            set: { newValue in
                guard let newValue else { return }
                if let focused = focusedDocument {
                    focused.wrappedValue = newValue
                } else if let fallback = HypeDocumentMutationCoordinator.shared.activeDocumentBinding {
                    fallback.wrappedValue = newValue
                }
            }
        )
        PreferencesView(document: bridged)
    }
}

/// Wrapper to make HypeDocument work with SwiftUI DocumentGroup.
struct HypeDocumentWrapper: FileDocument {
    var document: HypeDocument

    static var readableContentTypes: [UTType] { [.hypeStack, .hyperCardStack] }

    init() {
        self.document = HypeDocument.newDocument()
    }

    init(configuration: ReadConfiguration) throws {
        if configuration.file.isDirectory {
            self.document = try HypeSQLiteStackStore().load(from: configuration.file)
            return
        }

        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.document = try HyperCardToHypeConverter().convert(data: data).document
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try HypeSQLiteStackStore().fileWrapper(for: document)
    }
}

extension UTType {
    static let hypeStack = UTType(exportedAs: "com.hype.stack", conformingTo: .package)
    static let hyperCardStack = UTType(importedAs: "com.apple.hypercard.stack", conformingTo: .data)
}

@MainActor
private enum HyperCardImportPanel {
    static func open() {
        let panel = NSOpenPanel()
        panel.title = "Import HyperCard Stack"
        panel.message = "Select an original HyperCard stack data fork. Hype will convert it to a temporary .hype document and preserve the original forks when size limits allow."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = [.hyperCardStack, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let package = try HyperCardInputNormalizer().normalize(url: url)
            let result = try HyperCardToHypeConverter().convert(package: package)
            let encoded = try JSONEncoder().encode(result.document)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-imported.hype")
            try encoded.write(to: outputURL, options: .atomic)
            NSDocumentController.shared.openDocument(withContentsOf: outputURL, display: true) { _, _, error in
                if let error {
                    HypeLogger.shared.error("Failed to open converted HyperCard import: \(error.localizedDescription)", source: "HyperCardImport")
                    showImportError(error)
                }
            }
        } catch {
            HypeLogger.shared.error("HyperCard import failed: \(error.localizedDescription)", source: "HyperCardImport")
            showImportError(error)
        }
    }

    private static func showImportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "HyperCard Import Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

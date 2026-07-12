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
    /// The stack file `pendingWindowFrame` was computed for; `nil` means
    /// the untitled/global fallback. Checked against a window's own
    /// document URL before ever applying the pending frame, so a window
    /// belonging to a different (or still-opening) stack can never
    /// receive it.
    private var pendingWindowFrameURL: URL?
    private var hasAppliedPendingFrame = false
    private var debugDefaultsObserver: NSObjectProtocol?

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
        UserDefaults.standard.register(defaults: ["hype.debug.enabled": true])

        pendingWindowFrameURL = launchState.lastOpenedFileURL
        pendingWindowFrame = launchState.restorableWindowFrame(
            forFileAt: pendingWindowFrameURL,
            visibleScreenFrames: visibleScreenFrames
        )
        installWindowObservers()
        updateDebugServerState()
        debugDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateDebugServerState()
            }
        }

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
        if let debugDefaultsObserver {
            NotificationCenter.default.removeObserver(debugDefaultsObserver)
            self.debugDefaultsObserver = nil
        }
        HypeDebugServer.shared.stop()
        HypeDocumentMutationCoordinator.shared.flushAllAutosaves()

        // Prefer `mainWindow`: document windows are main, while `keyWindow`
        // may be a floating auxiliary panel (script editor, console) that
        // happened to have focus at quit. `persistState(for:)`'s document
        // guard makes this safe regardless of which window is picked.
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
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

    private func updateDebugServerState() {
        if UserDefaults.standard.bool(forKey: "hype.debug.enabled") {
            HypeDebugServer.shared.start()
        } else {
            HypeDebugServer.shared.stop()
        }
    }

    /// The visible area of every attached screen, in the global
    /// bottom-left coordinate space `AppLaunchState` clamps against. Read
    /// fresh each time rather than cached, since displays can connect or
    /// disconnect between launch and any later recompute.
    private var visibleScreenFrames: [NSRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    private func openDocument(at url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] document, _, error in
            guard let self else { return }

            if error != nil && document == nil {
                self.launchState.clearLastOpenedFile()
                // The stack the pending frame was computed for failed to
                // open. Retarget at the global fallback so the untitled
                // replacement window restores the last document window's
                // frame instead of carrying forward a frame keyed to a
                // file that just failed to load.
                self.pendingWindowFrameURL = nil
                self.pendingWindowFrame = self.launchState.restorableWindowFrame(
                    forFileAt: nil,
                    visibleScreenFrames: self.visibleScreenFrames
                )
                NSDocumentController.shared.newDocument(nil)
            }

            if let window = document?.windowControllers.first?.window {
                self.applyPendingWindowFrame(to: window)
            } else {
                // SwiftUI's DocumentGroup may not have attached the window
                // controller yet when this completion fires. Retry once on
                // the next runloop tick; `windowDidBecomeMain` remains the
                // backstop if the window still isn't attached by then.
                DispatchQueue.main.async {
                    if let window = document?.windowControllers.first?.window {
                        self.applyPendingWindowFrame(to: window)
                    }
                }
            }
        }
    }

    private func persistState(for window: NSWindow) {
        // Auxiliary windows — panels, sheets, the script editor, the asset
        // repository, About, the console, and Settings — are never owned
        // by an NSDocument. This guard is the fix for the poisoned-launch-
        // geometry bug: only a stack's own document window may persist
        // launch geometry.
        guard let document = document(for: window) else { return }
        launchState.save(windowFrame: window.frame, forFileAt: document.fileURL)
        if let url = document.fileURL {
            launchState.save(fileURL: url)
        }
    }

    /// The open `NSDocument` that owns `window`, if any. Used both to
    /// resolve a window's file URL and to gate which windows may persist
    /// launch geometry — a window with no owning document is always an
    /// auxiliary window.
    private func document(for window: NSWindow) -> NSDocument? {
        NSDocumentController.shared.documents.first { document in
            document.windowControllers.contains { $0.window === window }
        }
    }

    private func fileURL(for window: NSWindow) -> URL? {
        document(for: window)?.fileURL
    }

    private func applyPendingWindowFrame(to window: NSWindow?) {
        guard !hasAppliedPendingFrame,
              let frame = pendingWindowFrame,
              let window,
              let document = document(for: window) else { return }

        // Skip WITHOUT consuming the pending frame when the window's own
        // stack doesn't match the one the frame was computed for —
        // `hasAppliedPendingFrame` stays false so a later `becomeMain` for
        // the *right* window can still apply it. Both sides `nil`
        // (untitled) counts as a match.
        let windowFrameKey = document.fileURL.map(AppLaunchState.frameKey(forFileAt:))
        let pendingFrameKey = pendingWindowFrameURL.map(AppLaunchState.frameKey(forFileAt:))
        guard windowFrameKey == pendingFrameKey else { return }

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
        // Apply the restored frame before persisting: reversing this order
        // would immediately overwrite the just-restored geometry with
        // whatever default frame the window opened at.
        applyPendingWindowFrame(to: window)
        persistState(for: window)
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
            CommandGroup(replacing: .appInfo) {
                Button("About Hype") {
                    HypeAboutPanel.show()
                }
            }
            CommandGroup(after: .newItem) {
                Button("Import HyperCard Stack…") {
                    HyperCardImportPanel.open()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(!StackImportRuntime.isAvailable)
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

    static var readableContentTypes: [UTType] {
        StackImportRuntime.isAvailable ? [.hypeStack, .hyperCardStack] : [.hypeStack]
    }

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
        guard StackImportRuntime.isAvailable else {
            let status = StackImportRuntime.status
            throw HyperCardImportError.stackimportUnavailable(status.detail ?? status.aboutLine)
        }
        self.document = try StackImportCImporter().importStack(
            data: data,
            sourceFileName: configuration.file.preferredFilename
        ).document
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
        guard StackImportRuntime.isAvailable else {
            showImportUnavailable()
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Import HyperCard Stack"
        panel.message = "Select an original HyperCard stack data fork. Hype will convert it to a temporary .hype document and preserve the original forks when size limits allow."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = [.hyperCardStack, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? makeImportParentWindow()

        let progressState = HyperCardImportProgressState()
        let importView = HyperCardImportView(state: progressState)
        let importWindow = sheetWindow(
            title: "Importing HyperCard Stack",
            rootView: importView,
            size: NSSize(width: 360, height: 280)
        )

        parentWindow.beginSheet(importWindow)
        Task {
            await performImport(url: url, parentWindow: parentWindow, importWindow: importWindow, state: progressState)
        }
    }

    private static func makeImportParentWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return window
    }

    private static func performImport(
        url: URL,
        parentWindow: NSWindow,
        importWindow: NSWindow,
        state: HyperCardImportProgressState
    ) async {
        do {
            var importer = StackImportCImporter()
            importer.progressHandler = { message, percent in
                Task { @MainActor in
                    state.message = message
                    state.percent = percent
                }
            }

            let result = try await Task.detached(priority: .userInitiated) {
                try importer.importStack(at: url)
            }.value

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-imported.hype")
            try HypeSQLiteStackStore().save(result.document, toPackageAt: outputURL)

            await MainActor.run {
                state.message = "Import complete."
                state.percent = 100
                state.result = result
                state.outputURL = outputURL
                state.isComplete = true
            }
        } catch {
            await MainActor.run {
                state.error = error
            }
        }
    }

    private static func sheetWindow<Content: View>(title: String, rootView: Content, size: NSSize) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = hostingController
        return window
    }

    private static func showImportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "HyperCard Import Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func showImportUnavailable() {
        let status = StackImportRuntime.status
        let alert = NSAlert()
        alert.messageText = "HyperCard Import Unavailable"
        alert.informativeText = status.detail ?? status.aboutLine
        alert.alertStyle = .informational
        alert.runModal()
    }
}

@MainActor
private final class HyperCardImportProgressState: ObservableObject {
    @Published var message: String = "Preparing..."
    @Published var percent: Int = 0
    @Published var result: HyperCardImportResult?
    @Published var outputURL: URL?
    @Published var isComplete: Bool = false
    @Published var error: Error?
}

import SwiftUI

private struct HyperCardImportView: View {
    @ObservedObject var state: HyperCardImportProgressState

    var body: some View {
        if state.isComplete, let result = state.result, let outputURL = state.outputURL {
            completionCard(result: result, outputURL: outputURL)
        } else if let error = state.error {
            errorCard(error: error)
        } else {
            progressView
        }
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
            Text("Importing HyperCard Stack")
                .font(.system(size: 14, weight: .medium))
            Text(state.message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            ProgressView(value: Double(state.percent), total: 100)
                .progressViewStyle(.linear)
                .frame(width: 280)
            Text("\(state.percent)%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .frame(width: 360, height: 280)
    }

    private func completionCard(result: HyperCardImportResult, outputURL: URL) -> some View {
        VStack(spacing: 0) {
            completionHeader(stackName: result.report.stackName)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    statsSection(report: result.report, document: result.document)
                    if !result.report.resourceSummary.isEmpty {
                        resourcesSection(report: result.report)
                    }
                    if !result.report.warnings.isEmpty {
                        warningsSection(report: result.report)
                    }
                    if !result.report.unsupportedFeatures.isEmpty {
                        unsupportedSection(report: result.report)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 260)
            Divider()
            completionFooter(result: result, outputURL: outputURL)
        }
        .frame(width: 480, height: 440)
    }

    private func errorCard(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Import Failed")
                .font(.system(size: 14, weight: .medium))
            Text(error.localizedDescription)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(40)
        .frame(width: 360, height: 200)
    }

    private func completionHeader(stackName: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Complete")
                    .font(.system(size: 14, weight: .semibold))
                Text(stackName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding()
    }

    private func statsSection(report: HyperCardImportReport, document: HypeDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stack Contents")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 24) {
                statItem(value: "\(report.importedBackgrounds)", label: "Backgrounds")
                statItem(value: "\(report.importedCards)", label: "Cards")
                statItem(value: "\(report.importedParts)", label: "Parts")
                statItem(value: "\(report.importedScripts)", label: "Scripts")
            }
            let totalAssets = document.assetRepository.assets.count
            let totalAssetBytes = document.assetRepository.assets.reduce(0) { $0 + $1.data.count }
            if totalAssets > 0 {
                HStack(spacing: 24) {
                    statItem(value: "\(totalAssets)", label: "Assets")
                    statItem(value: ByteCountFormatter.string(fromByteCount: Int64(totalAssetBytes), countStyle: .file), label: "Asset Size")
                    if let cardSize = Optional(report.cardSize) {
                        statItem(value: "\(cardSize.width)×\(cardSize.height)", label: "Card Size")
                    }
                }
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func resourcesSection(report: HyperCardImportReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Converted Resources")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(report.resourceSummary.prefix(6), id: \.type) { summary in
                HStack {
                    Text(resourceTypeLabel(summary.type))
                        .font(.system(size: 11))
                    Spacer()
                    Text("\(summary.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            if report.resourceSummary.count > 6 {
                Text("+ \(report.resourceSummary.count - 6) more resource types")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func warningsSection(report: HyperCardImportReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 11))
                Text("Warnings (\(report.warnings.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            ForEach(report.warnings.prefix(3), id: \.self) { warning in
                Text("• \(warning)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if report.warnings.count > 3 {
                Text("+ \(report.warnings.count - 3) more warnings")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func unsupportedSection(report: HyperCardImportReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 11))
                Text("Unknown (\(report.unsupportedFeatures.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Text("Some stack features were not fully understood during import.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func completionFooter(result: HyperCardImportResult, outputURL: URL) -> some View {
        HStack(spacing: 12) {
            Button("Open Stack") {
                NSDocumentController.shared.openDocument(withContentsOf: outputURL, display: true) { _, _, error in
                    if let error {
                        HypeLogger.shared.error("Failed to open converted HyperCard import: \(error.localizedDescription)", source: "HyperCardImport")
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Done") {
                NSApp.keyWindow?.endSheet(NSApp.keyWindow?.attachedSheet ?? NSApp.keyWindow!)
            }
        }
        .padding()
    }

    private func resourceTypeLabel(_ type: String) -> String {
        let labels: [String: String] = [
            "snd": "Sounds",
            "PICT": "Pictures",
            "ICN#": "Icons",
            "IC07": "Icons (large)",
            "IC18": "Icons (8-bit)",
            "IC19": "Icons (16-color)",
            "CRSR": "Cursors",
            "STR#": "Strings",
            "IDes": "Icon Definitions",
        ]
        return labels[type] ?? type
    }
}

@MainActor
private enum HypeAboutPanel {
    static func show() {
        if let window = hypeAboutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Hype"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: HypeAboutView(
            optionalFrameworks: [
                OptionalFrameworkAboutItem.stackImport(status: StackImportRuntime.status)
            ],
            openSourceManifest: OpenSourceManifest.load()
        ))
        hypeAboutWindow = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                hypeAboutWindow = nil
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private var hypeAboutWindow: NSWindow?

private struct OptionalFrameworkAboutItem: Identifiable {
    enum State {
        case available
        case unavailable
    }

    let id: String
    let name: String
    let purpose: String
    let state: State
    let version: String?
    let frameworkPath: String
    let installCommand: String
    let detail: String?

    static func stackImport(status: StackImportLibraryStatus) -> OptionalFrameworkAboutItem {
        OptionalFrameworkAboutItem(
            id: "stackimport",
            name: "StackImport.framework",
            purpose: "HyperCard stack import",
            state: status.isAvailable ? .available : .unavailable,
            version: status.version,
            frameworkPath: status.frameworkPath,
            installCommand: status.installCommand,
            detail: status.detail
        )
    }
}

private struct HypeAboutView: View {
    let optionalFrameworks: [OptionalFrameworkAboutItem]
    let openSourceManifest: OpenSourceManifest

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Hype"
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?):
            return "Version \(version) (\(build))"
        case let (version?, nil):
            return "Version \(version)"
        case let (nil, build?):
            return "Build \(build)"
        default:
            return "Development Build"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    appIcon
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appName)
                            .font(.system(size: 28, weight: .semibold))
                        Text(appVersion)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Optional Frameworks")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ForEach(optionalFrameworks) { item in
                            OptionalFrameworkRow(item: item)
                        }
                    }
                }

                OpenSourceManifestSection(manifest: openSourceManifest)
            }
            .padding(24)
        }
        .frame(width: 640, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

private struct OpenSourceManifestSection: View {
    let manifest: OpenSourceManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Source")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(manifest.components.count) components")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(manifest.reportText, forType: .string)
                } label: {
                    Label("Copy Report", systemImage: "doc.on.doc")
                }
                .font(.system(size: 11))
                .help("Copy open source report")
            }

            VStack(spacing: 8) {
                ForEach(manifest.components) { component in
                    OpenSourceComponentRow(component: component)
                }
            }
        }
    }
}

private struct OpenSourceComponentRow: View {
    let component: OpenSourceComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(.blue)
                    .font(.system(size: 14, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(component.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(component.usage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(component.license)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.10))
                    .clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                metadata(label: "Kind", value: component.kind)
                metadata(label: "Version", value: component.version)
            }

            Text(component.sourceURL)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(13)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }

    private var iconName: String {
        component.kind.lowercased().contains("framework") ? "shippingbox" : "curlybraces"
    }

    private func metadata(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11))
        }
    }
}

private struct OptionalFrameworkRow: View {
    let item: OptionalFrameworkAboutItem

    private var isAvailable: Bool { item.state == .available }
    private var statusColor: Color { isAvailable ? .green : .orange }
    private var statusTitle: String { isAvailable ? "Available" : "Unavailable" }
    private var statusIcon: String { isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.purpose)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                metadataLine(label: "Version", value: item.version ?? "Not installed")
                metadataLine(label: "Path", value: item.frameworkPath)
            }

            if !isAvailable {
                VStack(alignment: .leading, spacing: 7) {
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Text(item.installCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.installCommand, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy install command")
                    }
                }
            }
        }
        .padding(13)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }

    private func metadataLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: label == "Path" ? .monospaced : .default))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct OpenSourceManifest: Decodable {
    var schemaVersion: Int
    var components: [OpenSourceComponent]

    static func load() -> OpenSourceManifest {
        guard let url = Bundle.main.url(forResource: "OpenSourceManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(OpenSourceManifest.self, from: data) else {
            return OpenSourceManifest(schemaVersion: 1, components: [])
        }
        return manifest
    }

    var reportText: String {
        var lines: [String] = [
            "Hype Open Source Manifest",
            "Schema Version: \(schemaVersion)",
            "",
        ]
        for component in components {
            lines.append("\(component.name)")
            lines.append("  Kind: \(component.kind)")
            lines.append("  Version: \(component.version)")
            lines.append("  License: \(component.license)")
            lines.append("  Source: \(component.sourceURL)")
            lines.append("  Usage: \(component.usage)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

private struct OpenSourceComponent: Decodable, Identifiable {
    var id: String { "\(name)-\(version)" }
    var name: String
    var kind: String
    var version: String
    var license: String
    var sourceURL: String
    var usage: String
}

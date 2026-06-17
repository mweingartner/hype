import SwiftUI
import HypeCore

/// Return the live canvas dimensions by finding the actual
/// `CardCanvasNSView` in the key window's view hierarchy.
/// Falls back to the stack model dimensions when no canvas is
/// found (e.g. during tests or before the window is shown).
///
/// IMPORTANT: uses the CardCanvasNSView's bounds — NOT the
/// window's contentView bounds, which includes the toolbar,
/// sidebar, and status bar. Using the wrong bounds causes
/// bottom-constrained parts to render below the visible canvas
/// edge on card navigation.
@MainActor
private func liveCanvasSize(fallbackStack stack: Stack) -> (Double, Double) {
    if let window = NSApp?.keyWindow ?? NSApp?.mainWindow,
       let canvas = findCardCanvas(in: window.contentView) {
        let size = canvas.bounds.size
        if size.width > 0, size.height > 0 {
            return (Double(size.width), Double(size.height))
        }
    }
    return (Double(stack.width), Double(stack.height))
}

/// Recursively search the view hierarchy for a CardCanvasNSView.
@MainActor
private func findCardCanvas(in view: NSView?) -> CardCanvasNSView? {
    guard let view = view else { return nil }
    if let canvas = view as? CardCanvasNSView { return canvas }
    for subview in view.subviews {
        if let found = findCardCanvas(in: subview) { return found }
    }
    return nil
}

private struct TargetCanvasFrameModifier: ViewModifier {
    let stack: Stack
    let emulatedProfile: HypeDeviceProfile?

    func body(content: Content) -> some View {
        if let emulatedProfile {
            content
                .frame(width: CGFloat(emulatedProfile.width), height: CGFloat(emulatedProfile.height))
        } else {
            content
                .frame(minWidth: CGFloat(stack.width), minHeight: CGFloat(stack.height))
        }
    }
}

private struct ScriptActivityStatusControl: View {
    let runningScripts: [RuntimeStatusSnapshot.RunningScriptSummary]
    var action: () -> Void

    private var label: String {
        runningScripts.count == 1 ? "Script running" : "\(runningScripts.count) scripts running"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
            Button(action: action) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Stop running scripts (Command-.)")
            .accessibilityLabel("Stop running scripts")
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            Capsule(style: .continuous)
                .fill(Color.orange.opacity(0.11))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

private struct CardStatusSummary: Equatable {
    var title: String
    var index: Int
    var count: Int
    var isEditingBackground: Bool
    var canGoFirst: Bool
    var canGoPrevious: Bool
    var canGoNext: Bool
    var canGoLast: Bool
}

private struct StatusIconButtonStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

private struct StatusChip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 5) {
            content
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private struct CardNavigationStatusControl: View {
    var summary: CardStatusSummary
    var navigate: (NavigationDirection) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                navigate(.first)
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(StatusIconButtonStyle())
            .disabled(!summary.canGoFirst)
            .help("First card")
            .accessibilityLabel("First card")

            Button {
                navigate(.previous)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(StatusIconButtonStyle())
            .disabled(!summary.canGoPrevious)
            .help("Previous card")
            .accessibilityLabel("Previous card")

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if summary.isEditingBackground {
                        Text("Background edit")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text("\(summary.index + 1) / \(summary.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: cardCountBadgeWidth, height: 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .frame(width: cardReadoutWidth, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(summary.title), card \(summary.index + 1) of \(summary.count)")

            Button {
                navigate(.next)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(StatusIconButtonStyle())
            .disabled(!summary.canGoNext)
            .help("Next card")
            .accessibilityLabel("Next card")

            Button {
                navigate(.last)
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(StatusIconButtonStyle())
            .disabled(!summary.canGoLast)
            .help("Last card")
            .accessibilityLabel("Last card")
        }
    }

    private var cardReadoutWidth: CGFloat {
        switch cardCountDigitBreak {
        case 0...3:
            return 140
        case 4...5:
            return 160
        case 6:
            return 178
        default:
            return 196
        }
    }

    private var cardCountBadgeWidth: CGFloat {
        switch cardCountDigitBreak {
        case 0...3:
            return 48
        case 4...5:
            return 66
        case 6:
            return 82
        default:
            return 98
        }
    }

    private var cardCountDigitBreak: Int {
        let largestVisibleNumber = max(summary.index + 1, summary.count)
        return String(largestVisibleNumber).count
    }
}

struct MainContentView: View {
    @Binding var document: HypeDocumentWrapper
    @Environment(\.undoManager) private var undoManager
    @State private var currentCardId: UUID?
    @State private var currentTool: ToolName = .browse
    @State private var selectedPartIds: Set<UUID> = []
    @State private var editingBackground: Bool = false
    @State private var showAI: Bool = false
    @State private var paintColor: Color = .black
    @State private var pencilRadius: Double = 2
    @State private var showRepository: Bool = false
    @State private var showNetworkPanel: Bool = false
    @State private var runtimeStatus = RuntimeStatusSnapshot(requests: [], listeners: [], connections: [])
    @State private var showTargetSelectionSheet: Bool = false
    @State private var showSimulatorLaunchSheet: Bool = false
    @State private var emulatedProfileId: String?
    @State private var debuggerConnectionCount = 0
    @State private var displayedRunningScripts: [RuntimeStatusSnapshot.RunningScriptSummary] = []
    @State private var scriptActivityTask: Task<Void, Never>?
    @State private var scriptActivityShownAt: Date?

    /// The window hosting this view, captured by `WindowAccessor`.
    /// Used to compute `isKeyDocument` for notification scoping.
    @State private var hostingWindow: NSWindow?

    /// Whether the current view's window is the key window.
    ///
    /// `nil` window → `true` keeps headless tests, single-context hosting, and
    /// any scenario where no window exists working exactly as before — unscoped
    /// (legacy) notifications still reach their single subscriber rather than
    /// being silently dropped.
    private var isKeyDocument: Bool {
        hostingWindow?.isKeyWindow ?? true
    }

    /// Whether the slide-out objects panel is open. Toggled via the
    /// Tools menu (⇧⌘O) or the toolbar button. Persisted so users
    /// who prefer the canvas-without-chrome layout keep it.
    @AppStorage("hypeObjectsPanelVisible") private var objectsPanelVisible: Bool = true

    private var toolState: ToolState {
        var state = ToolState(currentTool: currentTool.rawValue)
        state.selectedPartId = selectedPartIds.first
        return state
    }

    private var trackedDocumentBinding: Binding<HypeDocumentWrapper> {
        HypeDocumentMutationCoordinator.shared.trackedBinding(
            $document,
            undoManager: undoManager,
            actionName: "Edit Stack"
        )
    }

    private var authoringCommandContext: HypeAuthoringCommandContext {
        HypeAuthoringCommandContext(
            userLevel: activeUserLevel,
            canDuplicateSelection: canDuplicateSelectedParts,
            duplicateSelection: duplicateSelectedParts,
            layerTransferTitle: layerTransferTitle,
            canTransferSelectionToAlternateLayer: canTransferSelectedPartsToAlternateLayer,
            transferSelectionToAlternateLayer: transferSelectedPartsToAlternateLayer
        )
    }

    private var canDuplicateSelectedParts: Bool {
        guard !isRuntimeMode, activeUserLevel.canAuthorObjects, !selectedPartIds.isEmpty else { return false }
        guard !Self.firstResponderIsTextEditor else { return false }
        return !selectedPartIds.intersection(editablePartIdsForCurrentLayer()).isEmpty
    }

    private var layerTransferTitle: String {
        editingBackground ? "Move to Card" : "Move to Background"
    }

    private var canTransferSelectedPartsToAlternateLayer: Bool {
        guard !isRuntimeMode, activeUserLevel.canAuthorObjects, !selectedPartIds.isEmpty else { return false }
        guard !Self.firstResponderIsTextEditor else { return false }
        guard effectiveCurrentCardId != nil else { return false }
        return !selectedPartIds.intersection(editablePartIdsForCurrentLayer()).isEmpty
    }

    private var showInspector: Bool {
        // Hidden in runtime mode — the entire point of runtime mode
        // is to show the stack as the end-user experiences it,
        // without authoring chrome.
        !isRuntimeMode && activeUserLevel.canUsePaintTools
    }

    private var isRuntimeMode: Bool {
        document.document.stack.runtimeModeEnabled
    }

    private var activeUserLevel: HypeUserLevel {
        document.document.stack.userLevel.hypeUserLevel
    }

    private var emulatedProfile: HypeDeviceProfile? {
        guard let emulatedProfileId else { return nil }
        return HypeDeviceProfileCatalog.profile(id: emulatedProfileId)
    }

    private var effectiveCurrentCardId: UUID? {
        CurrentCardSelectionResolver.resolvedCardId(preferred: currentCardId, in: document.document)
    }

    /// Resolve the currently-active theme through the cascade so
    /// every downstream view sees a consistent value via
    /// `@Environment(\.hypeTheme)`. Card → background → stack →
    /// `BuiltInThemes.system`. See ThemeResolver.swift for details.
    private var resolvedTheme: HypeTheme {
        document.document.effectiveTheme(forCard: effectiveCurrentCardId)
    }

    var body: some View {
        mainContent
            .environment(\.hypeTheme, resolvedTheme)
            .onAppear {
                HypeDocumentMutationCoordinator.shared.noteDocumentOpened(document.document)
                resetCurrentCardSelection()
                coerceCurrentToolForUserLevel()
                updateAutomationRegistry()
                if !document.document.stack.deploymentTargets.selectionPromptAcknowledged && !isRuntimeMode {
                    showTargetSelectionSheet = true
                }
                refreshRuntimeStatus()
                if let cardId = currentCardId {
                    Task {
                        await dispatchLifecycleAsync("openStack", targetId: document.document.stack.id, currentCardId: cardId)
                        await dispatchLifecycleAsync("openCard", targetId: cardId, currentCardId: cardId)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .stackRuntimeDocumentDidChange)) { notification in
                guard let stackId = notification.userInfo?["stackId"] as? UUID,
                      stackId == document.document.stack.id,
                      let updated = notification.userInfo?["document"] as? HypeDocument else { return }
                let merge = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
                    runtimeDocument: updated,
                    currentDocument: document.document,
                    preserveCurrentRuntimeMode: true
                )
                applyDocument(merge.document, actionName: "Apply Runtime Changes")
                if merge.preservedCurrentOnlyEntities {
                    syncRuntimeDocument(merge.document)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .stackRuntimeStatusDidChange)) { notification in
                guard let stackId = notification.userInfo?["stackId"] as? UUID,
                      stackId == document.document.stack.id else { return }
                refreshRuntimeStatus()
            }
            .onChange(of: runtimeStatus.runningScripts) { _, runningScripts in
                updateDisplayedScriptActivity(runningScripts)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cancelRunningScripts)) { _ in
                cancelRunningScripts()
            }
            .modifier(ScriptErrorConsoleHandlers(
                document: trackedDocumentBinding,
                currentCardId: $currentCardId,
                currentTool: $currentTool,
                selectedPartIds: $selectedPartIds,
                isKeyDocument: isKeyDocument
            ))
            .modifier(NavigationHandlers(
                document: trackedDocumentBinding,
                currentCardId: $currentCardId,
                currentTool: $currentTool,
                selectedPartIds: $selectedPartIds,
                editingBackground: $editingBackground,
                showAI: $showAI,
                showRepository: $showRepository,
                isKeyDocument: isKeyDocument
            ))
            .modifier(ArrangeHandlers(
                document: trackedDocumentBinding,
                selectedPartIds: $selectedPartIds,
                isKeyDocument: isKeyDocument
            ))
            .modifier(AlignmentHandlers(
                document: trackedDocumentBinding,
                selectedPartIds: $selectedPartIds,
                isKeyDocument: isKeyDocument
            ))
            // Publish the focused document binding so the global
            // Preferences window (Settings scene) can reach the
            // current stack to read/write `webAssetsAllowed`. Without
            // this bridge, SwiftUI's `Settings { ... }` scene has no
            // handle on the focused `FileDocument` — the toggle
            // would always render disabled. See `HypeApp.swift` for
            // the FocusedValueKey declaration and the wrapper that
            // reads this value in the Settings scene.
            .modifier(FocusedSceneCommandValues(
                document: trackedDocumentBinding,
                authoringCommandContext: authoringCommandContext
            ))
            // Capture the hosting NSWindow so `isKeyDocument` can be
            // computed for notification scoping. See `WindowAccessor`.
            .background(WindowAccessor(window: $hostingWindow))
            // Also register with the mutation coordinator as the
            // currently-active document. `@FocusedValue` returns nil
            // once Preferences itself becomes the focused scene, so
            // the Preferences pane falls back to this registry to
            // resolve the "last-edited" document and keep its
            // per-stack toggles live.
            .onAppear {
                HypeDocumentMutationCoordinator.shared.activeDocumentBinding = trackedDocumentBinding
                updateAutomationRegistry()
            }
            .onDisappear {
                HypeAutomationRegistry.shared.remove(stackId: document.document.stack.id)
                scriptActivityTask?.cancel()
                HypeDocumentMutationCoordinator.shared.activeDocumentBinding = nil
                HypeDocumentMutationCoordinator.shared.activeCardId = nil
            }
            .onChange(of: document.document.stack.id) { _, _ in
                resetCurrentCardSelection()
                updateAutomationRegistry()
            }
            .onChange(of: document.document.cards.map(\.id)) { _, _ in
                repairCurrentCardSelection()
                updateAutomationRegistry()
            }
            .onChange(of: document.document.cards.map(\.backgroundId)) { _, _ in
                repairCurrentCardSelection()
                updateAutomationRegistry()
            }
            .onChange(of: document.document.backgrounds.map(\.id)) { _, _ in
                repairCurrentCardSelection()
                updateAutomationRegistry()
            }
            .onChange(of: currentCardId) { _, _ in updateAutomationRegistry() }
            .onChange(of: selectedPartIds) { _, _ in updateAutomationRegistry() }
            .onChange(of: currentTool) { _, _ in updateAutomationRegistry() }
            .onChange(of: editingBackground) { _, _ in updateAutomationRegistry() }
    }

    private func updateAutomationRegistry() {
        HypeDocumentMutationCoordinator.shared.activeCardId = currentCardId
        HypeAutomationRegistry.shared.upsert(
            binding: trackedDocumentBinding,
            currentCardId: effectiveCurrentCardId,
            selectedPartIds: selectedPartIds,
            currentTool: currentTool,
            editingBackground: editingBackground
        )
    }

    private func coerceCurrentToolForUserLevel() {
        if !ObjectToolCatalog.isTool(currentTool, availableAt: activeUserLevel) {
            currentTool = ObjectToolCatalog.fallbackTool(for: activeUserLevel)
        }
        if !activeUserLevel.canAuthorObjects {
            selectedPartIds = []
        }
        if !activeUserLevel.canEditScripts {
            showAI = false
        }
    }

    private func editablePartIdsForCurrentLayer() -> Set<UUID> {
        guard let currentCardId = effectiveCurrentCardId else { return [] }
        if editingBackground,
           let backgroundId = document.document.cards.first(where: { $0.id == currentCardId })?.backgroundId {
            return Set(document.document.partsForBackground(backgroundId).map(\.id))
        }
        return Set(document.document.partsForCard(currentCardId).map(\.id))
    }

    private func duplicateSelectedParts() {
        guard canDuplicateSelectedParts else { return }
        let ids = selectedPartIds.intersection(editablePartIdsForCurrentLayer())
        guard !ids.isEmpty else { return }

        var updatedDocument = document.document
        let result = updatedDocument.duplicateParts(ids: ids)
        guard !result.copiedPartIds.isEmpty else { return }

        HypeDocumentMutationCoordinator.shared.applyDocument(
            updatedDocument,
            to: trackedDocumentBinding,
            undoManager: undoManager,
            actionName: "Duplicate Selection"
        )
        selectedPartIds = updatedDocument.expandedGroupSelection(Set(result.copiedPartIds))
        currentTool = .select
        updateAutomationRegistry()
    }

    private func transferSelectedPartsToAlternateLayer() {
        guard canTransferSelectedPartsToAlternateLayer,
              let currentCardId = effectiveCurrentCardId,
              let currentCard = document.document.cards.first(where: { $0.id == currentCardId }) else { return }
        let ids = selectedPartIds.intersection(editablePartIdsForCurrentLayer())
        guard !ids.isEmpty else { return }

        let destination: PartLayerTransferDestination = editingBackground
            ? .card(currentCardId)
            : .background(currentCard.backgroundId)

        var updatedDocument = document.document
        let result = updatedDocument.transferParts(ids: ids, to: destination)
        guard !result.transferredPartIds.isEmpty else { return }

        HypeDocumentMutationCoordinator.shared.applyDocument(
            updatedDocument,
            to: trackedDocumentBinding,
            undoManager: undoManager,
            actionName: layerTransferTitle
        )
        editingBackground.toggle()
        selectedPartIds = updatedDocument.expandedGroupSelection(Set(result.transferredPartIds))
        currentTool = .select
        updateAutomationRegistry()
    }

    private static var firstResponderIsTextEditor: Bool {
        guard let firstResponder = NSApp?.keyWindow?.firstResponder else { return false }
        if firstResponder is NSTextView || firstResponder is NSTextField { return true }
        return String(describing: type(of: firstResponder)).contains("FieldEditor")
    }

    private func resetCurrentCardSelection() {
        currentCardId = CurrentCardSelectionResolver.resolvedCardId(preferred: nil, in: document.document)
        selectedPartIds = []
        editingBackground = false
    }

    private func repairCurrentCardSelection() {
        let resolved = CurrentCardSelectionResolver.resolvedCardId(preferred: currentCardId, in: document.document)
        if currentCardId != resolved {
            currentCardId = resolved
            selectedPartIds = []
            if resolved == nil {
                editingBackground = false
            }
        }
    }

    private var mainContent: some View {
        HSplitView {
            // Slide-out objects panel — left edge of the window.
            // Hidden when objectsPanelVisible == false (and the
            // entire panel collapses, not just emptied) so the
            // canvas reclaims the width. In runtime mode the panel
            // stays available because Run/Edit toggle still lives
            // there, but the tool palette inside it goes blank.
            if objectsPanelVisible {
                ObjectsToolPanel(
                    currentTool: $currentTool,
                    selectedPartIds: $selectedPartIds,
                    isRuntimeMode: isRuntimeMode,
                    targetPlatforms: document.document.stack.deploymentTargets.selectedPlatforms,
                    userLevel: activeUserLevel,
                    stackId: document.document.stack.id
                )
                .accessibilityIdentifier(HypeAccessibilityID.objectsPanel)
            }

            canvasArea
            sidePanels
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Objects-panel toggle is the leftmost item now —
                // mirrors macOS sidebar conventions (Mail, Notes).
                Button(action: { objectsPanelVisible.toggle() }) {
                    Image(systemName: "sidebar.leading")
                }
                .help(objectsPanelVisible ? "Hide Objects Panel (⇧⌘O)" : "Show Objects Panel (⇧⌘O)")
                .accessibilityLabel(objectsPanelVisible ? "Hide Objects Panel" : "Show Objects Panel")
                .accessibilityIdentifier(HypeAccessibilityID.toolbar("objectsPanel"))

                Spacer()

                // Hide the navigate / repository / AI / network
                // buttons in runtime mode — they're authoring
                // surfaces. Keep just navigation since end users
                // need to move between cards. Runtime mode also
                // hides the entire toolbar's edit-mode tool palette
                // because that's now in ObjectsToolPanel.
                Button(action: navigatePrevious) {
                    Image(systemName: "chevron.left")
                }
                .help("Previous Card")
                .disabled(!canNavigatePrevious)
                .accessibilityLabel("Previous Card")
                .accessibilityIdentifier(HypeAccessibilityID.toolbar("previousCard"))

                Button(action: navigateNext) {
                    Image(systemName: "chevron.right")
                }
                .help("Next Card")
                .disabled(!canNavigateNext)
                .accessibilityLabel("Next Card")
                .accessibilityIdentifier(HypeAccessibilityID.toolbar("nextCard"))

                if !isRuntimeMode && activeUserLevel.canAuthorObjects {
                    Divider()

                    Button(action: {
                        openAssetRepositoryWindow(document: trackedDocumentBinding)
                    }) {
                        Image(systemName: "tray.2")
                    }
                    .help("Asset Repository")
                    .accessibilityLabel("Asset Repository")
                    .accessibilityIdentifier(HypeAccessibilityID.toolbar("assetRepository"))

                    Button(action: {
                        openAIContextLibraryWindow(document: trackedDocumentBinding)
                    }) {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .help("AI Context Library")
                    .accessibilityLabel("AI Context Library")
                    .accessibilityIdentifier(HypeAccessibilityID.toolbar("aiContextLibrary"))

                    if activeUserLevel.canEditScripts {
                        Button(action: { showAI.toggle() }) {
                            Image(systemName: "sparkles")
                                .foregroundColor(showAI ? .accentColor : .primary)
                        }
                        .help("AI Assistant")
                        .accessibilityLabel(showAI ? "Hide AI Assistant" : "Show AI Assistant")
                        .accessibilityIdentifier(HypeAccessibilityID.toolbar("aiAssistant"))
                    }

                    Button(action: { showNetworkPanel = true }) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .help("Stack Network")
                    .accessibilityLabel("Stack Network")
                    .accessibilityIdentifier(HypeAccessibilityID.toolbar("stackNetwork"))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRuntimeMode)) { note in
            guard MenuCommandScoping.shouldHandle(
                notificationStackId: MenuCommandScoping.stackId(from: note),
                documentStackId: document.document.stack.id,
                isKeyDocument: isKeyDocument
            ) else { return }
            setRuntimeMode(!isRuntimeMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleObjectsPanel)) { _ in
            // toggleObjectsPanel controls a UI panel (AppStorage), not
            // document state — intentionally left unscoped so the
            // keyboard shortcut always reaches the active window's panel
            // regardless of focus.
            objectsPanelVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .duplicateSelection)) { note in
            guard MenuCommandScoping.shouldHandle(
                notificationStackId: MenuCommandScoping.stackId(from: note),
                documentStackId: document.document.stack.id,
                isKeyDocument: isKeyDocument
            ) else { return }
            duplicateSelectedParts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transferSelectionToAlternateLayer)) { note in
            guard MenuCommandScoping.shouldHandle(
                notificationStackId: MenuCommandScoping.stackId(from: note),
                documentStackId: document.document.stack.id,
                isKeyDocument: isKeyDocument
            ) else { return }
            transferSelectedPartsToAlternateLayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTargetPlatforms)) { note in
            guard MenuCommandScoping.shouldHandle(
                notificationStackId: MenuCommandScoping.stackId(from: note),
                documentStackId: document.document.stack.id,
                isKeyDocument: isKeyDocument
            ) else { return }
            guard activeUserLevel.canAuthorObjects else { return }
            showTargetSelectionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRuntimePackages)) { note in
            guard MenuCommandScoping.shouldHandle(
                notificationStackId: MenuCommandScoping.stackId(from: note),
                documentStackId: document.document.stack.id,
                isKeyDocument: isKeyDocument
            ) else { return }
            guard activeUserLevel.canAuthorObjects else { return }
            exportRuntimePackages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .testStackInSimulator)) { note in
            guard MenuCommandScoping.shouldHandle(
                notificationStackId: MenuCommandScoping.stackId(from: note),
                documentStackId: document.document.stack.id,
                isKeyDocument: isKeyDocument
            ) else { return }
            guard activeUserLevel.canAuthorObjects else { return }
            showSimulatorLaunchSheet = true
        }
        .onChange(of: document.document.stack.deploymentTargets.selectedPlatforms) { _, platforms in
            if let partType = ObjectToolCatalog.createdPartType(for: currentTool),
               !PartAvailabilityCatalog.supports(partType, across: platforms) {
                currentTool = .select
            }
        }
        .onChange(of: document.document.stack.userLevel) { _, _ in
            coerceCurrentToolForUserLevel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .setTargetEmulation)) { notification in
            guard MenuCommandScoping.shouldHandle(
                notificationStackId: MenuCommandScoping.stackId(from: notification),
                documentStackId: document.document.stack.id,
                isKeyDocument: isKeyDocument
            ) else { return }
            let profileId = notification.userInfo?["profileId"] as? String
            emulatedProfileId = profileId?.isEmpty == false ? profileId : nil
            Task { @MainActor in
                resolveConstraints()
            }
        }
        .sheet(isPresented: $showNetworkPanel) {
            NetworkPanelView(document: trackedDocumentBinding, runtimeStatus: runtimeStatus)
        }
        .sheet(isPresented: $showTargetSelectionSheet) {
            StackTargetSelectionSheet(document: trackedDocumentBinding)
        }
        .sheet(isPresented: $showSimulatorLaunchSheet) {
            SimulatorLaunchSheet(document: trackedDocumentBinding)
        }
    }

    // MARK: - Canvas and Panels

    @ViewBuilder
    private var canvasArea: some View {
        VStack(spacing: 0) {
            if let cardId = effectiveCurrentCardId {
                CardCanvasView(
                    document: trackedDocumentBinding,
                    currentCardId: cardId,
                    currentTool: currentTool,
                    selectedPartIds: $selectedPartIds,
                    editingBackground: editingBackground,
                    paintColorHex: paintColor.toHex(),
                    pencilRadius: Int(pencilRadius)
                )
                .accessibilityIdentifier(HypeAccessibilityID.canvas(cardId: cardId))
                .modifier(TargetCanvasFrameModifier(stack: document.document.stack, emulatedProfile: emulatedProfile))
                // Canvas margin — the area visible when the window
                // is larger than the card. Pulls from the active
                // theme's canvasMargin so a Sunset theme tints the
                // surround warm and a Neon theme drops it to near-
                // black, matching the card surface.
                .background(resolvedTheme.canvasMargin.swiftUIColor)
            } else {
                Text("No cards in stack")
                    .frame(minWidth: CGFloat(document.document.stack.width), minHeight: CGFloat(document.document.stack.height))
                    .background(resolvedTheme.canvasMargin.swiftUIColor)
            }

            HStack(spacing: 10) {
                if let summary = cardStatusSummary {
                    CardNavigationStatusControl(summary: summary) { direction in
                        navigate(direction)
                    }
                } else {
                    Text("No stack open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Paint color picker (shown for spray, bucket, pencil, eraser tools)
                if currentTool == .spray || currentTool == .bucket || currentTool == .pencil || currentTool == .eraser {
                    StatusChip {
                        ColorPicker("", selection: $paintColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 18, height: 16)
                        Text("Color")
                    }
                }
                if debuggerConnectionCount > 0 {
                    StatusChip {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Debugger")
                    }
                    .help(debuggerConnectionCount == 1 ? "Debugger connected" : "\(debuggerConnectionCount) debugger connections")
                    .accessibilityLabel("Debugger connected")
                }
                if !displayedRunningScripts.isEmpty {
                    ScriptActivityStatusControl(
                        runningScripts: displayedRunningScripts,
                        action: cancelRunningScripts
                    )
                    .help(runningScriptHelpText)
                }
                StatusChip {
                    Image(systemName: toolModeIconName)
                        .font(.system(size: 10, weight: .semibold))
                    Text(toolModeText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 36)
            .background(
                ZStack(alignment: .top) {
                    resolvedTheme.toolbarBackground.swiftUIColor
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 0.5)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: -1)
            )
            // Same colorScheme override as the inspector — keep
            // the labels readable on the themed background.
            .environment(\.colorScheme, resolvedTheme.toolbarColorScheme)
            .onAppear {
                debuggerConnectionCount = HypeDebugServer.shared.activeConnectionCount
            }
            .onReceive(NotificationCenter.default.publisher(for: .hypeDebugConnectionStatusDidChange)) { notification in
                debuggerConnectionCount = notification.userInfo?["connectionCount"] as? Int ?? 0
            }
        }
    }

    private var runningScriptHelpText: String {
        let names = displayedRunningScripts.map(\.message).joined(separator: ", ")
        return names.isEmpty ? "Scripts are running" : "Running: \(names)"
    }

    @ViewBuilder
    private var sidePanels: some View {
        if showInspector {
            PropertyInspector(document: trackedDocumentBinding, selectedPartIds: $selectedPartIds,
                              currentTool: currentTool, currentCardId: effectiveCurrentCardId,
                              paintColor: $paintColor, pencilRadius: $pencilRadius,
                              userLevel: activeUserLevel)
            .accessibilityIdentifier(HypeAccessibilityID.propertyInspector)
        }
        if showAI && activeUserLevel.canEditScripts {
            AIChatPanel(document: trackedDocumentBinding, currentCardId: $currentCardId)
                .accessibilityIdentifier(HypeAccessibilityID.aiAssistant)
        }
    }

    // MARK: - Navigation

    private var cardStatusSummary: CardStatusSummary? {
        guard let cardId = currentCardId else { return nil }
        let (index, count) = CardNavigator.cardPosition(currentCardId: cardId, document: document.document)
        let card = document.document.cards.first { $0.id == cardId }
        let fallback = "Card \(index + 1)"
        let title = card?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? card?.name ?? fallback
            : fallback
        return CardStatusSummary(
            title: title,
            index: index,
            count: count,
            isEditingBackground: editingBackground,
            canGoFirst: index > 0,
            canGoPrevious: canNavigatePrevious,
            canGoNext: canNavigateNext,
            canGoLast: index + 1 < count
        )
    }

    private var canNavigatePrevious: Bool {
        guard let cardId = effectiveCurrentCardId else { return false }
        return CardNavigator.navigate(direction: .previous, currentCardId: cardId, document: document.document) != nil
    }

    private var canNavigateNext: Bool {
        guard let cardId = effectiveCurrentCardId else { return false }
        return CardNavigator.navigate(direction: .next, currentCardId: cardId, document: document.document) != nil
    }

    private func navigate(_ direction: NavigationDirection) {
        guard let cardId = currentCardId,
              let newId = CardNavigator.navigate(direction: direction, currentCardId: cardId, document: document.document) else { return }
        navigateToCard(newId)
    }

    private func navigatePrevious() {
        guard let cardId = effectiveCurrentCardId,
              let newId = CardNavigator.navigate(direction: .previous, currentCardId: cardId, document: document.document) else { return }
        navigateToCard(newId)
    }

    private func navigateNext() {
        guard let cardId = effectiveCurrentCardId,
              let newId = CardNavigator.navigate(direction: .next, currentCardId: cardId, document: document.document) else { return }
        navigateToCard(newId)
    }

    /// Dispatch a lifecycle / system HypeTalk message and write any
    /// document mutations the handler produced back into the
    /// SwiftUI document binding.
    ///
    /// Earlier versions of every lifecycle call site used
    /// `let _ = dispatcher.dispatch(...)`, which ran the handler
    /// but silently threw away its mutated document. A handler
    /// like `on openCard / put "Hello" into field "title" / end
    /// openCard` would run, set the field in its local document
    /// snapshot, and then have that entire mutation discarded.
    /// This helper fixes that.
    ///
    /// There's an intentional duplicate of this helper in
    /// `NavigationHandlers` below, which has its own separate
    /// `document` binding and its own lifecycle call sites. Both
    /// copies do the same thing — kept independent so each struct
    /// remains self-contained.
    private func dispatchLifecycle(
        _ message: String,
        targetId: UUID,
        currentCardId: UUID
    ) {
        Task {
            await dispatchLifecycleAsync(message, targetId: targetId, currentCardId: currentCardId)
        }
    }

    @MainActor
    private func dispatchLifecycleAsync(
        _ message: String,
        targetId: UUID,
        currentCardId: UUID
    ) async {
        let snapshot = document.document
        let config = runtimeConfiguration()
        let runtime = await StackRuntimeRegistry.shared.runtime(for: snapshot, configuration: config)
        let result = await runtime.dispatchAndWait(
            message,
            params: [],
            targetId: targetId,
            currentCardId: currentCardId
        )
        if let modified = result.modifiedDocument {
            applyDocument(modified, actionName: "Run \(message)")
        }
    }

    /// Navigate to a new card, dispatching HypeTalk lifecycle messages.
    private func navigateToCard(_ newCardId: UUID) {
        Task {
            await navigateToCardAsync(newCardId)
        }
    }

    @MainActor
    private func navigateToCardAsync(_ newCardId: UUID) async {
        let oldCardId = currentCardId
        let oldBgId = oldCardId.flatMap { id in
            document.document.cards.first(where: { $0.id == id })?.backgroundId
        }
        let newBgId = document.document.cards.first(where: { $0.id == newCardId })?.backgroundId

        currentCardId = newCardId
        selectedPartIds = []

        // Close old card and potentially old background. The visible
        // card changes before lifecycle dispatch so scripted navigation
        // from a running handler (for example repeated `nextCard` with
        // waits) is not blocked behind lifecycle messages queued on the
        // same StackRuntime.
        if let oldCardId {
            await dispatchLifecycleAsync("closeCard", targetId: oldCardId, currentCardId: oldCardId)
            if oldBgId != newBgId, let bid = oldBgId {
                await dispatchLifecycleAsync("closeBackground", targetId: bid, currentCardId: oldCardId)
            }
        }

        // Open new background if changed, then open new card
        if oldBgId != newBgId, let bid = newBgId {
            await dispatchLifecycleAsync("openBackground", targetId: bid, currentCardId: newCardId)
        }
        await dispatchLifecycleAsync("openCard", targetId: newCardId, currentCardId: newCardId)

        // Resolve constraints for the new card
        resolveConstraints()
    }

    /// Resolve layout constraints for all parts on the current card.
    private func resolveConstraints() {
        guard let cardId = effectiveCurrentCardId else { return }
        let solver = ConstraintSolver()
        let cardParts = document.document.partsForCard(cardId)
        let card = document.document.cards.first(where: { $0.id == cardId })
        let bgParts = card.map { document.document.partsForBackground($0.backgroundId) } ?? []
        let allParts = cardParts + bgParts
        let partIds = Set(allParts.map(\.id))
        let relevantConstraints = document.document.constraints.filter { partIds.contains($0.sourcePartId) }

        // Use the actual canvas bounds so constraints resolve to
        // the live window edges. Fall back to stack dimensions
        // if the window isn't available.
        let (cw, ch) = liveCanvasSize(fallbackStack: document.document.stack)
        let updates = solver.solve(
            constraints: relevantConstraints,
            parts: allParts,
            canvasWidth: cw,
            canvasHeight: ch
        )

        mutateDocument(actionName: "Resolve Layout Constraints") { document in
            for (partId, geom) in updates {
                document.updatePart(id: partId) {
                    $0.left = geom.left
                    $0.top = geom.top
                    $0.width = geom.width
                    $0.height = geom.height
                }
            }
        }
    }

    private func exportRuntimePackages() {
        let panel = NSOpenPanel()
        panel.title = "Choose Runtime Package Export Folder"
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            do {
                let results = try TargetRuntimePackageBuilder().buildPackages(
                    for: document.document,
                    at: directory
                )
                let packageNames = results.map { $0.packageURL.lastPathComponent }.joined(separator: ", ")
                HypeLogger.shared.info(
                    "Exported runtime package artifacts: \(packageNames)",
                    source: "TargetRuntimePackageBuilder"
                )
            } catch {
                HypeLogger.shared.error(
                    "Runtime package export failed: \(error.localizedDescription)",
                    source: "TargetRuntimePackageBuilder"
                )
            }
        }
    }

    // MARK: - Info text

    private var cardInfoText: String {
        guard let cardId = effectiveCurrentCardId else { return "No cards in stack" }
        let (index, count) = CardNavigator.cardPosition(currentCardId: cardId, document: document.document)
        let card = document.document.cards.first { $0.id == cardId }
        let name = card?.name.isEmpty == false ? card!.name : "Card \(index + 1)"
        let bgIndicator: String
        if editingBackground {
            bgIndicator = " -- Background Edit"
        } else {
            bgIndicator = ""
        }
        let emulationIndicator = emulatedProfile.map { " -- Emulating \($0.displayName)" } ?? ""
        return "\(name) -- \(index + 1) of \(count)\(bgIndicator)\(emulationIndicator)"
    }

    private var toolModeText: String {
        let mode: String
        switch toolState.category {
        case .browse: mode = "Browse"
        case .edit: mode = "Edit"
        case .paint: mode = "Paint"
        }
        return "\(currentTool.rawValue.capitalized) (\(mode))"
    }

    private var toolModeIconName: String {
        switch toolState.category {
        case .browse: return "hand.point.up.left"
        case .edit: return "cursorarrow"
        case .paint: return "paintbrush"
        }
    }

    // MARK: - Tool palette

    @ViewBuilder
    private var toolPaletteButtons: some View {
        ForEach(ToolName.allCases, id: \.self) { tool in
            Button(action: {
                currentTool = tool
                selectedPartIds = []
            }) {
                Image(systemName: tool.systemImageName)
                    .foregroundColor(currentTool == tool ? .accentColor : .primary)
            }
            .help(tool.rawValue.capitalized)
        }
    }

    private func runtimeConfiguration() -> StackRuntimeConfiguration {
        let stack = document.document.stack
        let fileProvider: any FileAccessProvider = stack.fileAccessAllowed
            ? AppKitFileAccessProvider(stackId: stack.id)
            : StubFileAccessProvider()
        return StackRuntimeConfiguration(
            systemProvider: AppKitSystemProvider(),
            hostProvider: AppKitHostApplicationProvider(stackId: stack.id),
            aiProvider: SelectedAIScriptingProvider(),
            meshyProvider: LiveMeshyScriptingProvider(),
            speechOutputProvider: OpenAISpeechOutputProvider.shared,
            speechListenerProvider: RuntimeSpeechListenerProvider.shared,
            // Production builds must use AppKitNetworkPermissionPrompter so
            // that network access requests are presented as interactive NSAlerts.
            // The StackRuntimeConfiguration default (AllowAllNetworkPermissionPrompter)
            // exists for test harnesses only — app code always passes a real prompter.
            approvalPrompter: AppKitNetworkPermissionPrompter(stackName: stack.name),
            fileProvider: fileProvider
        )
    }

    private func refreshRuntimeStatus() {
        let snapshot = document.document
        let config = runtimeConfiguration()
        Task {
            let runtime = await StackRuntimeRegistry.shared.runtime(for: snapshot, configuration: config)
            let status = await runtime.statusSnapshot()
            await MainActor.run {
                runtimeStatus = status
            }
        }
    }

    private func cancelRunningScripts() {
        let snapshot = document.document
        let config = runtimeConfiguration()
        Task {
            let runtime = await StackRuntimeRegistry.shared.runtime(for: snapshot, configuration: config)
            await runtime.cancelRunningScripts()
            let status = await runtime.statusSnapshot()
            await MainActor.run {
                runtimeStatus = status
            }
        }
    }

    private func updateDisplayedScriptActivity(_ runningScripts: [RuntimeStatusSnapshot.RunningScriptSummary]) {
        scriptActivityTask?.cancel()
        if runningScripts.isEmpty {
            let shownAt = scriptActivityShownAt ?? Date()
            let visibleTime = Date().timeIntervalSince(shownAt)
            let remaining = max(0, 0.25 - visibleTime)
            scriptActivityTask = Task { @MainActor in
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
                displayedRunningScripts = []
                scriptActivityShownAt = nil
            }
            return
        }

        if !displayedRunningScripts.isEmpty {
            displayedRunningScripts = runningScripts
            return
        }

        scriptActivityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            displayedRunningScripts = runningScripts
            scriptActivityShownAt = Date()
        }
    }

    private func syncRuntimeDocument(_ snapshot: HypeDocument) {
        let config = runtimeConfiguration()
        Task {
            _ = await StackRuntimeRegistry.shared.runtime(for: snapshot, configuration: config)
        }
    }

    private func mutateDocument(actionName: String, _ mutation: (inout HypeDocument) -> Void) {
        HypeDocumentMutationCoordinator.shared.mutate(
            $document,
            undoManager: undoManager,
            actionName: actionName,
            mutation
        )
    }

    private func setRuntimeMode(_ enabled: Bool) {
        guard document.document.stack.runtimeModeEnabled != enabled else { return }
        var updated = document.document
        updated.stack.runtimeModeEnabled = enabled
        applyDocument(updated, actionName: enabled ? "Switch to Runtime Mode" : "Switch to Edit Mode")
        syncRuntimeDocument(updated)

        if enabled {
            // Entering runtime mode: clear authoring side-effects.
            currentTool = .browse
            selectedPartIds = []
            editingBackground = false
        } else {
            // Leaving runtime mode must be authoritative even when scripts are
            // still unwinding and posting stale runtime document snapshots.
            currentTool = .select
            selectedPartIds = []
            editingBackground = false
            cancelRunningScripts()
        }
    }

    private func applyDocument(_ updated: HypeDocument, actionName: String) {
        HypeDocumentMutationCoordinator.shared.applyDocument(
            updated,
            to: $document,
            undoManager: undoManager,
            actionName: actionName
        )
        let resolved = CurrentCardSelectionResolver.resolvedCardId(preferred: currentCardId, in: updated)
        if currentCardId != resolved {
            currentCardId = resolved
            selectedPartIds = []
        }
    }
}

// MARK: - Notification Handler Modifiers

/// Sub-modifier for the `.openThemeDesigner` notification. Lifted
/// out as its own modifier rather than appended to the main
/// `NavigationHandlers` chain because that chain has grown long
/// enough that the Swift type-checker rejects it on time-budget
/// grounds. Splitting along functional lines (theme vs. arrange vs.
/// alignment vs. navigation) keeps each chain digestible.
private struct ThemeDesignerHandler: ViewModifier {
    @Binding var document: HypeDocumentWrapper
    let isKeyDocument: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openThemeDesigner)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                // The Edit > Themes... menu item AND the "Edit
                // Themes..." button inside the PropertyInspector
                // both post this notification. The opener is
                // idempotent per-document — a second invocation
                // surfaces the existing window rather than spawning
                // a duplicate. See `ThemeDesignerWindowController`.
                openThemeDesignerWindow(document: $document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAIContextLibrary)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canEditScripts else { return }
                openAIContextLibraryWindow(document: $document)
            }
    }
}

private struct ScriptErrorConsoleHandlers: ViewModifier {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>
    let isKeyDocument: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showScriptError)) { _ in
                // showScriptError is posted by the runtime's script dispatch
                // without a stack id — it opens the shared console window and
                // clears the authoring selection. Scoped to key-window only so
                // a script error in a background document doesn't clobber the
                // foreground document's selection state.
                guard isKeyDocument else { return }
                currentTool = .select
                selectedPartIds = []
                openConsoleWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openScriptErrorLink)) { notification in
                // openScriptErrorLink carries a hype:// URL that encodes a
                // stack id — identity-checked inside makeScriptErrorOpenRequest
                // via `UUID(uuidString: stackId) != document.document.stack.id`.
                // The existing check is sufficient; no additional scoping needed.
                openScriptErrorLink(notification: notification)
            }
    }

    private func openScriptErrorLink(notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else { return }
        if let request = makeScriptErrorOpenRequest(from: url) {
            guard document.document.stack.userLevel.hypeUserLevel.canEditScripts else { return }
            revealScriptTarget(request.target)
            openScriptEditorWindow(
                document: $document,
                partId: request.partId,
                target: request.target,
                initialErrorLine: request.line,
                initialErrorMessage: request.message
            )
            return
        }
        openHypeReference(url)
    }

    private func makeScriptErrorOpenRequest(from url: URL) -> (
        target: ScriptTarget,
        partId: UUID?,
        line: Int?,
        message: String?
    )? {
        guard url.scheme == "hype",
              url.host == "script-error" || url.host == "script",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        if let stackId = query["stack"], UUID(uuidString: stackId) != document.document.stack.id {
            return nil
        }
        guard let kind = query["target"],
              let target = scriptTarget(kind: kind, query: query) else { return nil }
        return (
            target: target,
            partId: partId(for: target),
            line: query["line"].flatMap(Int.init),
            message: query["message"]
        )
    }

    private func scriptTarget(kind: String, query: [String: String]) -> ScriptTarget? {
        switch kind {
        case "part":
            return query["id"].flatMap(UUID.init(uuidString:)).map(ScriptTarget.part)
        case "card":
            return query["id"].flatMap(UUID.init(uuidString:)).map(ScriptTarget.card)
        case "background":
            return query["id"].flatMap(UUID.init(uuidString:)).map(ScriptTarget.background)
        case "scene":
            guard let partId = query["partId"].flatMap(UUID.init(uuidString:)),
                  let sceneId = query["id"].flatMap(UUID.init(uuidString:)) else { return nil }
            return .scene(partId: partId, sceneId: sceneId)
        case "node":
            guard let partId = query["partId"].flatMap(UUID.init(uuidString:)),
                  let nodeId = query["id"].flatMap(UUID.init(uuidString:)) else { return nil }
            return .node(partId: partId, nodeId: nodeId)
        case "stack":
            return .stack
        case "hype":
            return .hype
        case "object":
            return query["id"].flatMap(UUID.init(uuidString:)).flatMap(resolveObjectScriptTarget)
        default:
            return nil
        }
    }

    private func resolveObjectScriptTarget(_ id: UUID) -> ScriptTarget? {
        if document.document.parts.contains(where: { $0.id == id }) {
            return .part(id)
        }
        if document.document.cards.contains(where: { $0.id == id }) {
            return .card(id)
        }
        if document.document.backgrounds.contains(where: { $0.id == id }) {
            return .background(id)
        }
        if document.document.stack.id == id {
            return .stack
        }
        if id == MessageDispatcher.hypeScriptSentinel {
            return .hype
        }
        return nil
    }

    private func openHypeReference(_ url: URL) {
        guard url.scheme == "hype",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        if let stackId = query["stack"], UUID(uuidString: stackId) != document.document.stack.id {
            return
        }
        switch url.host {
        case "card":
            if let cardId = query["id"].flatMap(UUID.init(uuidString:)) {
                navigateToCard(cardId)
            }
        case "object":
            if let objectId = query["id"].flatMap(UUID.init(uuidString:)),
               let target = resolveObjectScriptTarget(objectId) {
                revealScriptTarget(target)
            }
        default:
            return
        }
    }

    private func partId(for target: ScriptTarget) -> UUID? {
        switch target {
        case .part(let id), .scene(let id, _), .node(let id, _):
            return id
        case .card, .background, .stack, .hype:
            return nil
        }
    }

    private func revealScriptTarget(_ target: ScriptTarget) {
        currentTool = .select
        switch target {
        case .part(let id), .scene(let id, _), .node(let id, _):
            selectedPartIds = [id]
            if let part = document.document.parts.first(where: { $0.id == id }) {
                if let cardId = part.cardId {
                    navigateToCard(cardId)
                } else if let bgId = part.backgroundId,
                          let cardId = document.document.cards.first(where: { $0.backgroundId == bgId })?.id {
                    navigateToCard(cardId)
                }
            }
        case .card(let id):
            selectedPartIds = []
            navigateToCard(id)
        case .background(let id):
            selectedPartIds = []
            if let cardId = document.document.cards.first(where: { $0.backgroundId == id })?.id {
                navigateToCard(cardId)
            }
        case .stack, .hype:
            selectedPartIds = []
        }
    }

    private func navigateToCard(_ cardId: UUID) {
        guard document.document.cards.contains(where: { $0.id == cardId }) else { return }
        currentCardId = cardId
    }
}

/// Sub-modifier for navigation, tool, card, and background notifications.
private struct NavigationHandlers: ViewModifier {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>
    @Binding var editingBackground: Bool
    @Binding var showAI: Bool
    @Binding var showRepository: Bool
    let isKeyDocument: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .navigateCard)) { notification in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: notification),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard let direction = notification.object as? NavigationDirection,
                      let cardId = currentCardId else { return }
                if let newId = CardNavigator.navigate(direction: direction, currentCardId: cardId, document: document.document) {
                    navigateToCard(newId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectTool)) { notification in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: notification),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard let tool = notification.object as? ToolName else { return }
                let userLevel = document.document.stack.userLevel.hypeUserLevel
                guard ObjectToolCatalog.isTool(tool, availableAt: userLevel) else { return }
                if let partType = ObjectToolCatalog.createdPartType(for: tool),
                   !PartAvailabilityCatalog.supports(partType, across: document.document.stack.deploymentTargets.selectedPlatforms) {
                    return
                }
                currentTool = tool
                let preserveSelection = notification.userInfo?[ToolSelectionNotification.preserveSelectionUserInfoKey] as? Bool ?? false
                if !preserveSelection {
                    selectedPartIds = []
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToCard)) { notification in
                // navigateToCard carries a specific UUID target — already
                // identity-checked by the navigateToCard(cardId:) guard below.
                // No additional scoping needed; wrong-document UUIDs are
                // silently ignored by the `contains(where:)` guard.
                guard let cardId = notification.object as? UUID else { return }
                navigateToCard(cardId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToProjectTarget)) { notification in
                guard let target = notification.object as? ProjectNavigationTarget else { return }
                ProjectNavigationRouter.route(target)
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNewCard)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                addNewCard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteCurrentCard)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                deleteCurrentCard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNewBackground)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                addNewBackgroundFlow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleEditBackground)) { notification in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: notification),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canUsePaintTools else { return }
                editingBackground = (notification.object as? Bool) ?? false
                selectedPartIds = []
            }
            .onReceive(NotificationCenter.default.publisher(for: .editPartProperties)) { notification in
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                if let partId = notification.object as? UUID {
                    // editPartProperties carries a specific part UUID — the
                    // document's own parts are checked by expandedGroupSelection;
                    // a UUID from another document's part will simply find no
                    // match and leave selection unchanged. Already identity-checked.
                    selectedPartIds = document.document.expandedGroupSelection([partId])
                    currentTool = .select
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleAI)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canEditScripts else { return }
                showAI.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAssetRepository)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                // The menu/shortcut no longer toggles a sheet —
                // it opens (or surfaces) the detached browser
                // window. openAssetRepositoryWindow is idempotent:
                // a second invocation re-orders the existing
                // window to the front instead of creating a
                // duplicate.
                openAssetRepositoryWindow(document: $document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAllCards)) { _ in
                cycleAllCards()
            }
            .onReceive(NotificationCenter.default.publisher(for: .revealSpriteNode)) { notification in
                revealSpriteNode(notification: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .hypeQuit)) { _ in
                // hypeQuit is app-global — intentionally dispatched to every
                // open document so all quit handlers run before termination.
                if let cardId = currentCardId {
                    dispatchLifecycle("quit", targetId: cardId, currentCardId: cardId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPartScriptEditor)) { notification in
                openPartScriptEditor(notification: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showConsole)) { _ in
                // showConsole opens a shared/global console window —
                // intentionally unscoped so only one console opens regardless
                // of which document is focused.
                openConsoleWindow()
            }
            .modifier(ThemeDesignerHandler(document: $document, isKeyDocument: isKeyDocument))
    }

    /// Parse a `.showScriptError` notification payload and open the
    /// script editor for the offending object with the runtime error
    /// line pre-highlighted. Falls back gracefully if any field is
    /// missing so a malformed notification never crashes the UI.
    private func openScriptErrorEditor(notification: Notification) {
        guard document.document.stack.userLevel.hypeUserLevel.canEditScripts else { return }
        let info = notification.userInfo ?? [:]
        let target = resolvedScriptTarget(from: info)
        let line = info["line"] as? Int
        let message = info["message"] as? String
        let partId = info["partId"] as? UUID ?? resolvedPartID(from: info)
        openScriptEditorWindow(
            document: $document,
            partId: partId,
            target: target,
            initialErrorLine: line,
            initialErrorMessage: message
        )
    }

    private func openPartScriptEditor(notification: Notification) {
        guard document.document.stack.userLevel.hypeUserLevel.canEditScripts else { return }
        // Command-Option-click on a part and other script-editor
        // surfaces converge here. User-level gating stays duplicated
        // at this boundary so synthesized notifications cannot bypass
        // the Scripting-level requirement.
        let info = notification.userInfo ?? [:]
        if let target = info["target"] as? ScriptTarget {
            let partId = info["partId"] as? UUID
            openScriptEditorWindow(document: $document, partId: partId, target: target)
        } else if let partId = info["partId"] as? UUID {
            let target: ScriptTarget = .part(partId)
            openScriptEditorWindow(document: $document, partId: partId, target: target)
        } else if let cardId = info["cardId"] as? UUID {
            let target: ScriptTarget = .card(cardId)
            openScriptEditorWindow(document: $document, target: target)
        }
    }

    private func resolvedScriptTarget(from info: [AnyHashable: Any]) -> ScriptTarget? {
        if let target = info["target"] as? ScriptTarget {
            return target
        }
        guard let objectId = info["objectId"] as? UUID else { return nil }
        if document.document.parts.contains(where: { $0.id == objectId }) {
            return .part(objectId)
        }
        if document.document.cards.contains(where: { $0.id == objectId }) {
            return .card(objectId)
        }
        if document.document.backgrounds.contains(where: { $0.id == objectId }) {
            return .background(objectId)
        }
        if document.document.stack.id == objectId {
            return .stack
        }
        if objectId == MessageDispatcher.hypeScriptSentinel {
            return .hype
        }
        return nil
    }

    private func resolvedPartID(from info: [AnyHashable: Any]) -> UUID? {
        guard let objectId = info["objectId"] as? UUID,
              document.document.parts.contains(where: { $0.id == objectId }) else { return nil }
        return objectId
    }

    private func revealSpriteNode(notification: Notification) {
        guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
        let info = notification.userInfo ?? [:]
        guard let partId = info["partId"] as? UUID else { return }

        if let part = document.document.parts.first(where: { $0.id == partId }) {
            if let ownerCardId = part.cardId {
                if currentCardId != ownerCardId {
                    navigateToCard(ownerCardId)
                }
            } else if let bgId = part.backgroundId,
                      let ownerCardId = document.document.cards.first(where: { $0.backgroundId == bgId })?.id,
                      currentCardId != ownerCardId {
                navigateToCard(ownerCardId)
            }
        }

        currentTool = .select
        selectedPartIds = [partId]

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .focusSpriteNodeInInspector,
                object: nil,
                userInfo: info
            )
        }
    }

    /// Dispatch a lifecycle / system HypeTalk message and apply any
    /// document mutations the handler produced back into the SwiftUI
    /// document binding.
    ///
    /// Earlier versions of every lifecycle call site used
    /// `let _ = dispatcher.dispatch(...)`, which ran the handler but
    /// silently threw away its mutated document. A handler like
    /// `on openCard / put "Hello" into field "title" / end openCard`
    /// would run, set the field in its local document snapshot, and
    /// then have that entire mutation discarded on return. This
    /// helper fixes that by writing `result.modifiedDocument` back
    /// into `document.document` whenever the handler produced one.
    private func dispatchLifecycle(
        _ message: String,
        targetId: UUID,
        currentCardId: UUID
    ) {
        Task {
            await dispatchLifecycleAsync(message, targetId: targetId, currentCardId: currentCardId)
        }
    }

    /// Navigate to a new card, dispatching HypeTalk lifecycle messages.
    private func navigateToCard(_ newCardId: UUID) {
        Task {
            await navigateToCardAsync(newCardId)
        }
    }

    @MainActor
    private func dispatchLifecycleAsync(
        _ message: String,
        targetId: UUID,
        currentCardId: UUID
    ) async {
        let snapshot = document.document
        let stack = snapshot.stack
        let fileProvider: any FileAccessProvider = stack.fileAccessAllowed
            ? AppKitFileAccessProvider(stackId: stack.id)
            : StubFileAccessProvider()
        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: snapshot,
            configuration: StackRuntimeConfiguration(
                systemProvider: AppKitSystemProvider(),
                hostProvider: AppKitHostApplicationProvider(stackId: stack.id),
                aiProvider: SelectedAIScriptingProvider(),
                meshyProvider: LiveMeshyScriptingProvider(),
                speechOutputProvider: OpenAISpeechOutputProvider.shared,
                speechListenerProvider: RuntimeSpeechListenerProvider.shared,
                // Production site: must use AppKitNetworkPermissionPrompter,
                // not the AllowAll default that exists for test harnesses only.
                approvalPrompter: AppKitNetworkPermissionPrompter(stackName: stack.name),
                fileProvider: fileProvider
            )
        )
        let result = await runtime.dispatchAndWait(
            message,
            params: [],
            targetId: targetId,
            currentCardId: currentCardId
        )
        if let modified = result.modifiedDocument {
            document.document = modified
        }
    }

    @MainActor
    private func navigateToCardAsync(_ newCardId: UUID) async {
        let oldCardId = currentCardId
        let oldBgId = oldCardId.flatMap { id in
            document.document.cards.first(where: { $0.id == id })?.backgroundId
        }
        let newBgId = document.document.cards.first(where: { $0.id == newCardId })?.backgroundId

        currentCardId = newCardId
        selectedPartIds = []

        // Close/open lifecycle dispatch can queue behind the script that
        // requested navigation. Update the visible card first so `go next`
        // and classic `nextCard` automate card changes while that script
        // continues running in edit mode with the Browse tool selected.
        if let oldCardId {
            await dispatchLifecycleAsync("closeCard", targetId: oldCardId, currentCardId: oldCardId)
            if oldBgId != newBgId, let bid = oldBgId {
                await dispatchLifecycleAsync("closeBackground", targetId: bid, currentCardId: oldCardId)
            }
        }

        if oldBgId != newBgId, let bid = newBgId {
            await dispatchLifecycleAsync("openBackground", targetId: bid, currentCardId: newCardId)
        }
        await dispatchLifecycleAsync("openCard", targetId: newCardId, currentCardId: newCardId)

        // Resolve constraints for the new card
        resolveConstraints(document: &document.document, cardId: newCardId)
    }

    /// Resolve layout constraints for all parts on a card.
    private func resolveConstraints(document: inout HypeDocument, cardId: UUID) {
        let solver = ConstraintSolver()
        let cardParts = document.partsForCard(cardId)
        let card = document.cards.first(where: { $0.id == cardId })
        let bgParts = card.map { document.partsForBackground($0.backgroundId) } ?? []
        let allParts = cardParts + bgParts
        let partIds = Set(allParts.map(\.id))
        let relevantConstraints = document.constraints.filter { partIds.contains($0.sourcePartId) }

        let (cw, ch) = liveCanvasSize(fallbackStack: document.stack)
        let updates = solver.solve(
            constraints: relevantConstraints,
            parts: allParts,
            canvasWidth: cw,
            canvasHeight: ch
        )

        for (partId, geom) in updates {
            document.updatePart(id: partId) {
                $0.left = geom.left
                $0.top = geom.top
                $0.width = geom.width
                $0.height = geom.height
            }
        }
    }

    /// Cycle through every card in the deck with a 1-second pause, then return to the first card.
    private func cycleAllCards() {
        let sorted = document.document.sortedCards
        guard sorted.count > 1 else { return }
        Task { @MainActor in
            for card in sorted {
                currentCardId = card.id
                selectedPartIds = []
                try? await Task.sleep(for: .seconds(1))
            }
            // Return to the first card
            currentCardId = sorted.first?.id
            selectedPartIds = []
        }
    }

    private func addNewCard() {
        guard let cardId = currentCardId else { return }
        let sorted = document.document.sortedCards
        let currentIndex = sorted.firstIndex(where: { $0.id == cardId })
        let newCard = document.document.addCard(afterIndex: currentIndex)
        // Dispatch newCard — a handler may initialise part state on
        // the freshly-created card, and that mutation must be
        // written back.
        dispatchLifecycle("newCard", targetId: newCard.id, currentCardId: newCard.id)
        navigateToCard(newCard.id)
    }

    /// Create a new background after prompting for a name.
    /// The background simply appears in the inspector picker;
    /// no card is auto-created and no navigation happens.
    private func addNewBackgroundFlow() {
        let count = document.document.backgrounds.count
        let suggestedName = "Background \(count + 1)"

        let alert = NSAlert()
        alert.messageText = "New Background"
        alert.informativeText = "Name the new background."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        nameField.stringValue = suggestedName
        nameField.placeholderString = suggestedName
        alert.accessoryView = nameField
        alert.window.initialFirstResponder = nameField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? suggestedName : typed

        let _ = document.document.addBackground(name: name)
    }

    private func deleteCurrentCard() {
        guard let cardId = currentCardId else { return }
        guard document.document.cards.count > 1 else { return }
        // Dispatch deleteCard before removing — handler may save
        // state elsewhere, e.g. into a stack-level field or global.
        dispatchLifecycle("deleteCard", targetId: cardId, currentCardId: cardId)
        let sorted = document.document.sortedCards
        if let idx = sorted.firstIndex(where: { $0.id == cardId }) {
            let nextId = idx + 1 < sorted.count ? sorted[idx + 1].id :
                         idx > 0 ? sorted[idx - 1].id : nil
            let cardParts = document.document.partsForCard(cardId)
            for part in cardParts {
                document.document.deletePart(id: part.id)
            }
            document.document.cards.removeAll { $0.id == cardId }
            if let nextId = nextId {
                navigateToCard(nextId)
            } else {
                currentCardId = nil
                selectedPartIds = []
            }
        }
    }
}

/// Sub-modifier for draw-order (arrange) notifications.
private struct ArrangeHandlers: ViewModifier {
    @Binding var document: HypeDocumentWrapper
    @Binding var selectedPartIds: Set<UUID>
    let isKeyDocument: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .groupSelection)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                if let groupId = document.document.groupParts(ids: selectedPartIds) {
                    selectedPartIds = document.document.expandedGroupSelection(
                        Set(document.document.parts.filter { $0.groupId == groupId }.map(\.id))
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ungroupSelection)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                let affected = document.document.ungroupParts(ids: selectedPartIds)
                if !affected.isEmpty {
                    selectedPartIds = affected
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bringForward)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                document.document.bringForward(ids: selectedPartIds)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sendBackward)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                document.document.sendBackward(ids: selectedPartIds)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bringToFront)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                document.document.bringToFront(ids: selectedPartIds)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sendToBack)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
                document.document.sendToBack(ids: selectedPartIds)
            }
    }
}

private struct FocusedSceneCommandValues: ViewModifier {
    let document: Binding<HypeDocumentWrapper>
    let authoringCommandContext: HypeAuthoringCommandContext

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.hypeCurrentDocument, document)
            .focusedSceneValue(\.hypeAuthoringCommandContext, authoringCommandContext)
    }
}

/// Sub-modifier for alignment and distribution notifications.
private struct AlignmentHandlers: ViewModifier {
    @Binding var document: HypeDocumentWrapper
    @Binding var selectedPartIds: Set<UUID>
    let isKeyDocument: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .alignLeft)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                alignSelectedParts(.left)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignRight)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                alignSelectedParts(.right)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignTop)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                alignSelectedParts(.top)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignBottom)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                alignSelectedParts(.bottom)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignHCenter)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                alignSelectedParts(.hCenter)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignVCenter)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                alignSelectedParts(.vCenter)
            }
            .onReceive(NotificationCenter.default.publisher(for: .distributeH)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                alignSelectedParts(.distributeH)
            }
            .onReceive(NotificationCenter.default.publisher(for: .distributeV)) { note in
                guard MenuCommandScoping.shouldHandle(
                    notificationStackId: MenuCommandScoping.stackId(from: note),
                    documentStackId: document.document.stack.id,
                    isKeyDocument: isKeyDocument
                ) else { return }
                alignSelectedParts(.distributeV)
            }
    }

    private enum AlignmentType {
        case left, right, top, bottom, hCenter, vCenter, distributeH, distributeV
    }

    private func alignSelectedParts(_ alignment: AlignmentType) {
        guard document.document.stack.userLevel.hypeUserLevel.canAuthorObjects else { return }
        let units = document.document.selectionUnits(for: selectedPartIds)
        guard units.count >= 2 else { return }

        switch alignment {
        case .left:
            let minLeft = units.map(\.bounds.left).min()!
            for unit in units {
                document.document.moveParts(ids: unit.ids, dx: minLeft - unit.bounds.left, dy: 0)
            }
        case .right:
            let maxRight = units.map(\.bounds.right).max()!
            for unit in units {
                document.document.moveParts(ids: unit.ids, dx: maxRight - unit.bounds.right, dy: 0)
            }
        case .top:
            let minTop = units.map(\.bounds.top).min()!
            for unit in units {
                document.document.moveParts(ids: unit.ids, dx: 0, dy: minTop - unit.bounds.top)
            }
        case .bottom:
            let maxBottom = units.map(\.bounds.bottom).max()!
            for unit in units {
                document.document.moveParts(ids: unit.ids, dx: 0, dy: maxBottom - unit.bounds.bottom)
            }
        case .hCenter:
            let avgCenterX = units.map(\.bounds.centerX).reduce(0, +) / Double(units.count)
            for unit in units {
                document.document.moveParts(ids: unit.ids, dx: avgCenterX - unit.bounds.centerX, dy: 0)
            }
        case .vCenter:
            let avgCenterY = units.map(\.bounds.centerY).reduce(0, +) / Double(units.count)
            for unit in units {
                document.document.moveParts(ids: unit.ids, dx: 0, dy: avgCenterY - unit.bounds.centerY)
            }
        case .distributeH:
            let sorted = units.sorted { $0.bounds.left < $1.bounds.left }
            guard sorted.count >= 3 else { return }
            let totalSpan = sorted.last!.bounds.left - sorted.first!.bounds.left
            let step = totalSpan / Double(sorted.count - 1)
            for (i, unit) in sorted.enumerated() {
                if i > 0 && i < sorted.count - 1 {
                    let targetLeft = sorted.first!.bounds.left + step * Double(i)
                    document.document.moveParts(ids: unit.ids, dx: targetLeft - unit.bounds.left, dy: 0)
                }
            }
        case .distributeV:
            let sorted = units.sorted { $0.bounds.top < $1.bounds.top }
            guard sorted.count >= 3 else { return }
            let totalSpan = sorted.last!.bounds.top - sorted.first!.bounds.top
            let step = totalSpan / Double(sorted.count - 1)
            for (i, unit) in sorted.enumerated() {
                if i > 0 && i < sorted.count - 1 {
                    let targetTop = sorted.first!.bounds.top + step * Double(i)
                    document.document.moveParts(ids: unit.ids, dx: 0, dy: targetTop - unit.bounds.top)
                }
            }
        }
    }

}

// MARK: - Window key-status accessor

/// Captures the `NSWindow` hosting this SwiftUI view into a `Binding<NSWindow?>`.
///
/// Used by `MainContentView` to compute `isKeyDocument` for notification
/// scoping — we need to know whether THIS document's window is currently
/// the key window so legacy unscoped broadcasts (nil `hypeTargetStackId`)
/// reach only the foreground document instead of every open document.
///
/// Implemented as a zero-size `NSViewRepresentable` attached via
/// `.background(WindowAccessor(...))`. The `Coordinator` walks up the
/// view hierarchy from the NSView once to find the window, then writes it
/// into the binding. Subsequent key-window changes are observed via
/// `NSWindow.didBecomeKeyNotification` / `NSWindow.didResignKeyNotification`
/// so SwiftUI re-evaluates `isKeyDocument` on every focus change without
/// polling.
private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Walk up the view hierarchy once the view has been embedded.
        // `window` is nil until the view is actually attached to a window,
        // so we defer to the next runloop tick to let the hierarchy settle.
        //
        // We capture `$window` (the Binding projection) into the closure so
        // the coordinator can write back to the @State storage when key-window
        // status changes. Binding is a struct whose setter closure captures
        // the @State storage by reference — safe to copy.
        let windowBinding = $window
        DispatchQueue.main.async { [weak nsView] in
            guard let w = nsView?.window else { return }
            guard context.coordinator.observedWindow !== w else { return }
            context.coordinator.observe(w, onChange: {
                // Writing the same window reference triggers a SwiftUI @State
                // update, which causes isKeyDocument to be recomputed on the
                // next render pass.
                windowBinding.wrappedValue = w
            })
            // Immediately set the binding so the initial value is correct.
            windowBinding.wrappedValue = w
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private(set) var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        /// Start observing key-window state changes on `window`.
        ///
        /// `onChange` is called whenever the window becomes key or resigns key
        /// so SwiftUI can recompute `isKeyDocument`. The closure does not need
        /// to capture the window — it just triggers a state re-read.
        func observe(_ window: NSWindow, onChange: @escaping () -> Void) {
            // Remove previous observers to avoid leaks when the window changes.
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            observedWindow = window

            let center = NotificationCenter.default
            let becomeKey = center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { _ in onChange() }
            let resignKey = center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { _ in onChange() }
            observers = [becomeKey, resignKey]
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

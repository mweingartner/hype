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

fileprivate struct ScriptErrorSheetRequest: Identifiable {
    let id = UUID()
    var target: ScriptTarget
    var partId: UUID?
    var line: Int?
    var message: String?
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
    @State private var scriptErrorSheetRequest: ScriptErrorSheetRequest?
    @State private var runtimeStatus = RuntimeStatusSnapshot(requests: [], listeners: [], connections: [])
    @State private var showTargetSelectionSheet: Bool = false
    @State private var emulatedProfileId: String?

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

    private var showInspector: Bool {
        // Hidden in runtime mode — the entire point of runtime mode
        // is to show the stack as the end-user experiences it,
        // without authoring chrome.
        !isRuntimeMode
    }

    private var isRuntimeMode: Bool {
        document.document.stack.runtimeModeEnabled
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
                    currentDocument: document.document
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
            .modifier(ScriptErrorConsoleHandlers(
                document: trackedDocumentBinding,
                currentCardId: $currentCardId,
                currentTool: $currentTool,
                selectedPartIds: $selectedPartIds,
                scriptErrorSheetRequest: $scriptErrorSheetRequest
            ))
            .modifier(NavigationHandlers(
                document: trackedDocumentBinding,
                currentCardId: $currentCardId,
                currentTool: $currentTool,
                selectedPartIds: $selectedPartIds,
                editingBackground: $editingBackground,
                showAI: $showAI,
                showRepository: $showRepository
            ))
            .modifier(ArrangeHandlers(
                document: trackedDocumentBinding,
                selectedPartIds: $selectedPartIds
            ))
            .modifier(AlignmentHandlers(
                document: trackedDocumentBinding,
                selectedPartIds: $selectedPartIds
            ))
            // Publish the focused document binding so the global
            // Preferences window (Settings scene) can reach the
            // current stack to read/write `webAssetsAllowed`. Without
            // this bridge, SwiftUI's `Settings { ... }` scene has no
            // handle on the focused `FileDocument` — the toggle
            // would always render disabled. See `HypeApp.swift` for
            // the FocusedValueKey declaration and the wrapper that
            // reads this value in the Settings scene.
            .focusedSceneValue(\.hypeCurrentDocument, trackedDocumentBinding)
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
                HypeDocumentMutationCoordinator.shared.activeDocumentBinding = nil
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
        HypeAutomationRegistry.shared.upsert(
            binding: trackedDocumentBinding,
            currentCardId: effectiveCurrentCardId,
            selectedPartIds: selectedPartIds,
            currentTool: currentTool,
            editingBackground: editingBackground
        )
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
                    targetPlatforms: document.document.stack.deploymentTargets.selectedPlatforms
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

                if !isRuntimeMode {
                    Divider()

                    Button(action: {
                        openSpriteRepositoryWindow(document: trackedDocumentBinding)
                    }) {
                        Image(systemName: "tray.2")
                    }
                    .help("Sprite Repository")
                    .accessibilityLabel("Sprite Repository")
                    .accessibilityIdentifier(HypeAccessibilityID.toolbar("spriteRepository"))

                    Button(action: {
                        openAIContextLibraryWindow(document: trackedDocumentBinding)
                    }) {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .help("AI Context Library")
                    .accessibilityLabel("AI Context Library")
                    .accessibilityIdentifier(HypeAccessibilityID.toolbar("aiContextLibrary"))

                    Button(action: { showAI.toggle() }) {
                        Image(systemName: "sparkles")
                            .foregroundColor(showAI ? .accentColor : .primary)
                    }
                    .help("AI Assistant")
                    .accessibilityLabel(showAI ? "Hide AI Assistant" : "Show AI Assistant")
                    .accessibilityIdentifier(HypeAccessibilityID.toolbar("aiAssistant"))

                    Button(action: { showNetworkPanel = true }) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .help("Stack Network")
                    .accessibilityLabel("Stack Network")
                    .accessibilityIdentifier(HypeAccessibilityID.toolbar("stackNetwork"))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRuntimeMode)) { _ in
            setRuntimeMode(!isRuntimeMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleObjectsPanel)) { _ in
            objectsPanelVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTargetPlatforms)) { _ in
            showTargetSelectionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRuntimePackages)) { _ in
            exportRuntimePackages()
        }
        .onChange(of: document.document.stack.deploymentTargets.selectedPlatforms) { _, platforms in
            if let partType = ObjectToolCatalog.createdPartType(for: currentTool),
               !PartAvailabilityCatalog.supports(partType, across: platforms) {
                currentTool = .select
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setTargetEmulation)) { notification in
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
        .sheet(item: $scriptErrorSheetRequest) { request in
            ScriptEditor(
                document: trackedDocumentBinding,
                partId: request.partId,
                target: request.target,
                initialErrorLine: request.line,
                initialErrorMessage: request.message,
                identityKey: request.target.identityKey,
                onDone: { scriptErrorSheetRequest = nil }
            )
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

            // Status bar
            HStack {
                Text(cardInfoText)
                    .font(.system(size: 11))
                Spacer()
                // Paint color picker (shown for spray, bucket, pencil, eraser tools)
                if currentTool == .spray || currentTool == .bucket || currentTool == .pencil || currentTool == .eraser {
                    ColorPicker("", selection: $paintColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 24, height: 18)
                    Text("Color")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Text(toolModeText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            // Status strip below the canvas — tinted with the
            // active theme's toolbar background so it matches the
            // top toolbar visually.
            .background(resolvedTheme.toolbarBackground.swiftUIColor)
            // Same colorScheme override as the inspector — keep
            // the labels readable on the themed background.
            .environment(\.colorScheme, resolvedTheme.toolbarColorScheme)
        }
    }

    @ViewBuilder
    private var sidePanels: some View {
        if showInspector {
            PropertyInspector(document: trackedDocumentBinding, selectedPartIds: $selectedPartIds,
                              currentTool: currentTool, currentCardId: effectiveCurrentCardId,
                              paintColor: $paintColor, pencilRadius: $pencilRadius)
            .accessibilityIdentifier(HypeAccessibilityID.propertyInspector)
        }
        if showAI {
            AIChatPanel(document: trackedDocumentBinding, currentCardId: $currentCardId)
                .accessibilityIdentifier(HypeAccessibilityID.aiAssistant)
        }
    }

    // MARK: - Navigation

    private var canNavigatePrevious: Bool {
        guard let cardId = effectiveCurrentCardId else { return false }
        return CardNavigator.navigate(direction: .previous, currentCardId: cardId, document: document.document) != nil
    }

    private var canNavigateNext: Bool {
        guard let cardId = effectiveCurrentCardId else { return false }
        return CardNavigator.navigate(direction: .next, currentCardId: cardId, document: document.document) != nil
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
        // Close old card and potentially old background
        if let oldCardId = currentCardId {
            let oldBgId = document.document.cards.first(where: { $0.id == oldCardId })?.backgroundId
            await dispatchLifecycleAsync("closeCard", targetId: oldCardId, currentCardId: oldCardId)

            // Background change?
            let newBgId = document.document.cards.first(where: { $0.id == newCardId })?.backgroundId
            if oldBgId != newBgId, let bid = oldBgId {
                await dispatchLifecycleAsync("closeBackground", targetId: bid, currentCardId: oldCardId)
            }
        }

        currentCardId = newCardId
        selectedPartIds = []

        // Open new background if changed, then open new card
        if let oldCardId = document.document.sortedCards.first(where: { $0.id != newCardId })?.id {
            let oldBgId = document.document.cards.first(where: { $0.id == oldCardId })?.backgroundId
            let newBgId = document.document.cards.first(where: { $0.id == newCardId })?.backgroundId
            if oldBgId != newBgId, let bid = newBgId {
                await dispatchLifecycleAsync("openBackground", targetId: bid, currentCardId: newCardId)
            }
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
        StackRuntimeConfiguration(
            aiProvider: SelectedAIScriptingProvider(),
            meshyProvider: LiveMeshyScriptingProvider(),
            speechOutputProvider: OpenAISpeechOutputProvider.shared,
            speechListenerProvider: RuntimeSpeechListenerProvider.shared
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
        mutateDocument(actionName: enabled ? "Switch to Runtime Mode" : "Switch to Edit Mode") { document in
            document.stack.runtimeModeEnabled = enabled
        }
        // Entering runtime mode: clear authoring side-effects.
        if enabled {
            currentTool = .browse
            selectedPartIds = []
            editingBackground = false
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

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openThemeDesigner)) { _ in
                // The Edit > Themes... menu item AND the "Edit
                // Themes..." button inside the PropertyInspector
                // both post this notification. The opener is
                // idempotent per-document — a second invocation
                // surfaces the existing window rather than spawning
                // a duplicate. See `ThemeDesignerWindowController`.
                openThemeDesignerWindow(document: $document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAIContextLibrary)) { _ in
                openAIContextLibraryWindow(document: $document)
            }
    }
}

private struct ScriptErrorConsoleHandlers: ViewModifier {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>
    @Binding var scriptErrorSheetRequest: ScriptErrorSheetRequest?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showScriptError)) { _ in
                currentTool = .select
                selectedPartIds = []
                openConsoleWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openScriptErrorLink)) { notification in
                openScriptErrorLink(notification: notification)
            }
    }

    private func openScriptErrorLink(notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else { return }
        if let request = makeScriptErrorSheetRequest(from: url) {
            revealScriptTarget(request.target)
            scriptErrorSheetRequest = request
            return
        }
        openHypeReference(url)
    }

    private func makeScriptErrorSheetRequest(from url: URL) -> ScriptErrorSheetRequest? {
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
        return ScriptErrorSheetRequest(
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

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .navigateCard)) { notification in
                guard let direction = notification.object as? NavigationDirection,
                      let cardId = currentCardId else { return }
                if let newId = CardNavigator.navigate(direction: direction, currentCardId: cardId, document: document.document) {
                    navigateToCard(newId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectTool)) { notification in
                guard let tool = notification.object as? ToolName else { return }
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
                guard let cardId = notification.object as? UUID else { return }
                navigateToCard(cardId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNewCard)) { _ in
                addNewCard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteCurrentCard)) { _ in
                deleteCurrentCard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNewBackground)) { _ in
                addNewBackgroundFlow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleEditBackground)) { notification in
                editingBackground = (notification.object as? Bool) ?? false
                selectedPartIds = []
            }
            .onReceive(NotificationCenter.default.publisher(for: .editPartProperties)) { notification in
                if let partId = notification.object as? UUID {
                    selectedPartIds = document.document.expandedGroupSelection([partId])
                    currentTool = .select
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleAI)) { _ in
                showAI.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSpriteRepository)) { _ in
                // The menu/shortcut no longer toggles a sheet —
                // it opens (or surfaces) the detached browser
                // window. openSpriteRepositoryWindow is idempotent:
                // a second invocation re-orders the existing
                // window to the front instead of creating a
                // duplicate.
                openSpriteRepositoryWindow(document: $document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAllCards)) { _ in
                cycleAllCards()
            }
            .onReceive(NotificationCenter.default.publisher(for: .revealSpriteNode)) { notification in
                revealSpriteNode(notification: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .hypeQuit)) { _ in
                // Dispatch "quit" system message to the current card
                // before app terminates. The quit handler runs
                // synchronously and any document mutations it makes
                // are written back before the app exits.
                if let cardId = currentCardId {
                    dispatchLifecycle("quit", targetId: cardId, currentCardId: cardId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPartScriptEditor)) { notification in
                openPartScriptEditor(notification: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showConsole)) { _ in
                openConsoleWindow()
            }
            .modifier(ThemeDesignerHandler(document: $document))
    }

    /// Parse a `.showScriptError` notification payload and open the
    /// script editor for the offending object with the runtime error
    /// line pre-highlighted. Falls back gracefully if any field is
    /// missing so a malformed notification never crashes the UI.
    private func openScriptErrorEditor(notification: Notification) {
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
        // Cmd+click in browse mode: open the script editor for the
        // clicked part, or the current card when clicking empty space.
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
        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: snapshot,
            configuration: StackRuntimeConfiguration(
                aiProvider: SelectedAIScriptingProvider(),
                meshyProvider: LiveMeshyScriptingProvider(),
                speechOutputProvider: OpenAISpeechOutputProvider.shared,
                speechListenerProvider: RuntimeSpeechListenerProvider.shared
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
        // Close old card and potentially old background
        if let oldCardId = currentCardId {
            let oldBgId = document.document.cards.first(where: { $0.id == oldCardId })?.backgroundId
            await dispatchLifecycleAsync("closeCard", targetId: oldCardId, currentCardId: oldCardId)

            let newBgId = document.document.cards.first(where: { $0.id == newCardId })?.backgroundId
            if oldBgId != newBgId, let bid = oldBgId {
                await dispatchLifecycleAsync("closeBackground", targetId: bid, currentCardId: oldCardId)
            }
        }

        currentCardId = newCardId
        selectedPartIds = []

        // Open new card (and new background if changed)
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

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .groupSelection)) { _ in
                if let groupId = document.document.groupParts(ids: selectedPartIds) {
                    selectedPartIds = document.document.expandedGroupSelection(
                        Set(document.document.parts.filter { $0.groupId == groupId }.map(\.id))
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ungroupSelection)) { _ in
                let affected = document.document.ungroupParts(ids: selectedPartIds)
                if !affected.isEmpty {
                    selectedPartIds = affected
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bringForward)) { _ in
                document.document.bringForward(ids: selectedPartIds)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sendBackward)) { _ in
                document.document.sendBackward(ids: selectedPartIds)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bringToFront)) { _ in
                document.document.bringToFront(ids: selectedPartIds)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sendToBack)) { _ in
                document.document.sendToBack(ids: selectedPartIds)
            }
    }
}

/// Sub-modifier for alignment and distribution notifications.
private struct AlignmentHandlers: ViewModifier {
    @Binding var document: HypeDocumentWrapper
    @Binding var selectedPartIds: Set<UUID>

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .alignLeft)) { _ in
                alignSelectedParts(.left)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignRight)) { _ in
                alignSelectedParts(.right)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignTop)) { _ in
                alignSelectedParts(.top)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignBottom)) { _ in
                alignSelectedParts(.bottom)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignHCenter)) { _ in
                alignSelectedParts(.hCenter)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alignVCenter)) { _ in
                alignSelectedParts(.vCenter)
            }
            .onReceive(NotificationCenter.default.publisher(for: .distributeH)) { _ in
                alignSelectedParts(.distributeH)
            }
            .onReceive(NotificationCenter.default.publisher(for: .distributeV)) { _ in
                alignSelectedParts(.distributeV)
            }
    }

    private enum AlignmentType {
        case left, right, top, bottom, hCenter, vCenter, distributeH, distributeV
    }

    private func alignSelectedParts(_ alignment: AlignmentType) {
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

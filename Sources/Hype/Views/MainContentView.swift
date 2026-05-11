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
private func findCardCanvas(in view: NSView?) -> CardCanvasNSView? {
    guard let view = view else { return nil }
    if let canvas = view as? CardCanvasNSView { return canvas }
    for subview in view.subviews {
        if let found = findCardCanvas(in: subview) { return found }
    }
    return nil
}

struct MainContentView: View {
    @Binding var document: HypeDocumentWrapper
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

    /// Runtime vs Edit mode. Persisted across launches so a stack
    /// distributed in runtime mode reopens in runtime mode. Toggled
    /// via the Tools menu (⇧⌘E) or the Run/Edit buttons in
    /// `ObjectsToolPanel`.
    @AppStorage("hypeRuntimeMode") private var isRuntimeMode: Bool = false

    /// Whether the slide-out objects panel is open. Toggled via the
    /// Tools menu (⇧⌘O) or the toolbar button. Persisted so users
    /// who prefer the canvas-without-chrome layout keep it.
    @AppStorage("hypeObjectsPanelVisible") private var objectsPanelVisible: Bool = true

    private var toolState: ToolState {
        var state = ToolState(currentTool: currentTool.rawValue)
        state.selectedPartId = selectedPartIds.first
        return state
    }

    private var showInspector: Bool {
        // Hidden in runtime mode — the entire point of runtime mode
        // is to show the stack as the end-user experiences it,
        // without authoring chrome.
        !isRuntimeMode
    }

    /// Resolve the currently-active theme through the cascade so
    /// every downstream view sees a consistent value via
    /// `@Environment(\.hypeTheme)`. Card → background → stack →
    /// `BuiltInThemes.system`. See ThemeResolver.swift for details.
    private var resolvedTheme: HypeTheme {
        document.document.effectiveTheme(forCard: currentCardId)
    }

    var body: some View {
        mainContent
            .environment(\.hypeTheme, resolvedTheme)
            .onAppear {
                currentCardId = document.document.sortedCards.first?.id
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
                document.document = updated
            }
            .onReceive(NotificationCenter.default.publisher(for: .stackRuntimeStatusDidChange)) { notification in
                guard let stackId = notification.userInfo?["stackId"] as? UUID,
                      stackId == document.document.stack.id else { return }
                refreshRuntimeStatus()
            }
            .modifier(NavigationHandlers(
                document: $document,
                currentCardId: $currentCardId,
                currentTool: $currentTool,
                selectedPartIds: $selectedPartIds,
                editingBackground: $editingBackground,
                showAI: $showAI,
                showRepository: $showRepository
            ))
            .modifier(ArrangeHandlers(
                document: $document,
                selectedPartIds: $selectedPartIds
            ))
            .modifier(AlignmentHandlers(
                document: $document,
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
            .focusedSceneValue(\.hypeCurrentDocument, $document)
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
                    selectedPartIds: $selectedPartIds
                )
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

                Button(action: navigateNext) {
                    Image(systemName: "chevron.right")
                }
                .help("Next Card")
                .disabled(!canNavigateNext)

                if !isRuntimeMode {
                    Divider()

                    Button(action: {
                        openSpriteRepositoryWindow(document: $document)
                    }) {
                        Image(systemName: "tray.2")
                    }
                    .help("Sprite Repository")

                    Button(action: {
                        openAIContextLibraryWindow(document: $document)
                    }) {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .help("AI Context Library")

                    Button(action: { showAI.toggle() }) {
                        Image(systemName: "sparkles")
                            .foregroundColor(showAI ? .accentColor : .primary)
                    }
                    .help("AI Assistant")

                    Button(action: { showNetworkPanel = true }) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .help("Stack Network")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRuntimeMode)) { _ in
            isRuntimeMode.toggle()
            // Entering runtime mode: clear authoring side-effects.
            if isRuntimeMode {
                currentTool = .browse
                selectedPartIds = []
                editingBackground = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleObjectsPanel)) { _ in
            objectsPanelVisible.toggle()
        }
        .sheet(isPresented: $showNetworkPanel) {
            NetworkPanelView(document: $document, runtimeStatus: runtimeStatus)
        }
    }

    // MARK: - Canvas and Panels

    @ViewBuilder
    private var canvasArea: some View {
        VStack(spacing: 0) {
            CardCanvasView(
                document: $document,
                currentCardId: currentCardId ?? document.document.sortedCards.first?.id ?? UUID(),
                currentTool: currentTool,
                selectedPartIds: $selectedPartIds,
                editingBackground: editingBackground,
                paintColorHex: paintColor.toHex(),
                pencilRadius: Int(pencilRadius)
            )
            .frame(
                minWidth: CGFloat(document.document.stack.width),
                minHeight: CGFloat(document.document.stack.height)
            )
            // Canvas margin — the area visible when the window
            // is larger than the card. Pulls from the active
            // theme's canvasMargin so a Sunset theme tints the
            // surround warm and a Neon theme drops it to near-
            // black, matching the card surface.
            .background(resolvedTheme.canvasMargin.swiftUIColor)

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
            PropertyInspector(document: $document, selectedPartIds: $selectedPartIds,
                              currentTool: currentTool, currentCardId: currentCardId,
                              paintColor: $paintColor, pencilRadius: $pencilRadius)
        }
        if showAI {
            AIChatPanel(document: $document, currentCardId: $currentCardId)
        }
    }

    // MARK: - Navigation

    private var canNavigatePrevious: Bool {
        guard let cardId = currentCardId else { return false }
        return CardNavigator.navigate(direction: .previous, currentCardId: cardId, document: document.document) != nil
    }

    private var canNavigateNext: Bool {
        guard let cardId = currentCardId else { return false }
        return CardNavigator.navigate(direction: .next, currentCardId: cardId, document: document.document) != nil
    }

    private func navigatePrevious() {
        guard let cardId = currentCardId,
              let newId = CardNavigator.navigate(direction: .previous, currentCardId: cardId, document: document.document) else { return }
        navigateToCard(newId)
    }

    private func navigateNext() {
        guard let cardId = currentCardId,
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
            document.document = modified
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
        guard let cardId = currentCardId else { return }
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

        for (partId, geom) in updates {
            document.document.updatePart(id: partId) {
                $0.left = geom.left
                $0.top = geom.top
                $0.width = geom.width
                $0.height = geom.height
            }
        }
    }

    // MARK: - Info text

    private var cardInfoText: String {
        guard let cardId = currentCardId else { return "No stack open" }
        let (index, count) = CardNavigator.cardPosition(currentCardId: cardId, document: document.document)
        let card = document.document.cards.first { $0.id == cardId }
        let name = card?.name.isEmpty == false ? card!.name : "Card \(index + 1)"
        let bgIndicator: String
        if editingBackground {
            bgIndicator = " -- Background Edit"
        } else {
            bgIndicator = ""
        }
        return "\(name) -- \(index + 1) of \(count)\(bgIndicator)"
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
            speechOutputProvider: OpenAISpeechOutputProvider.shared
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
                currentTool = tool
                selectedPartIds = []
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
            .onReceive(NotificationCenter.default.publisher(for: .showScriptError)) { notification in
                // Runtime / parse error from HypeTalk dispatch.
                //
                // Two things have to happen in lockstep here, both
                // motivated by a real bug a user hit: a buggy
                // `on idle` handler kept throwing every 500 ms,
                // and the editor opened a fresh window each time
                // because (a) we didn't dedupe and (b) the idle
                // timer kept firing in browse mode.
                //
                // 1. Drop out of browse mode into edit mode (the
                //    `.select` tool sits in the .edit category, so
                //    `CardCanvasNSView.startIdleTimer`'s
                //    `category == .browse` guard immediately stops
                //    every subsequent tick). This is the primary
                //    fix — once the timer stops firing, no more
                //    error events get generated and the user can
                //    actually fix the script.
                //
                // 2. Open (or refresh) the script editor for the
                //    offending object. `openScriptEditorWindow` is
                //    now idempotent per target — a second call for
                //    the same target reuses the existing window
                //    and just refreshes its highlight, so even
                //    other event paths (mouseEnter, etc.) can't
                //    spawn duplicates.
                currentTool = .select
                selectedPartIds = []
                openScriptErrorEditor(notification: notification)
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
        if let partId = info["partId"] as? UUID {
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
                speechOutputProvider: OpenAISpeechOutputProvider.shared
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
                document.document.removePart(id: part.id)
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

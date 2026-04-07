import SwiftUI
import HypeCore

struct MainContentView: View {
    @Binding var document: HypeDocumentWrapper
    @State private var currentCardId: UUID?
    @State private var currentTool: ToolName = .browse
    @State private var selectedPartIds: Set<UUID> = []
    @State private var editingBackground: Bool = false
    @State private var showAI: Bool = false
    @State private var paintColor: Color = .black

    private var toolState: ToolState {
        var state = ToolState(currentTool: currentTool.rawValue)
        state.selectedPartId = selectedPartIds.first
        return state
    }

    private var showInspector: Bool {
        // Show inspector whenever a part is selected — in any tool mode.
        // In browse mode you can double-click to select a part for editing.
        !selectedPartIds.isEmpty
    }

    var body: some View {
        mainContent
            .onAppear {
                currentCardId = document.document.sortedCards.first?.id
                // Dispatch stack and card lifecycle messages
                if let cardId = currentCardId {
                    let dispatcher = MessageDispatcher()
                    let _ = dispatcher.dispatch(message: "openStack", params: [], targetId: document.document.stack.id, document: document.document, currentCardId: cardId)
                    let _ = dispatcher.dispatch(message: "openCard", params: [], targetId: cardId, document: document.document, currentCardId: cardId)
                }
            }
            .modifier(NavigationHandlers(
                document: $document,
                currentCardId: $currentCardId,
                currentTool: $currentTool,
                selectedPartIds: $selectedPartIds,
                editingBackground: $editingBackground,
                showAI: $showAI
            ))
            .modifier(ArrangeHandlers(
                document: $document,
                selectedPartIds: $selectedPartIds
            ))
            .modifier(AlignmentHandlers(
                document: $document,
                selectedPartIds: $selectedPartIds
            ))
    }

    private var mainContent: some View {
        HSplitView {
            canvasArea
            sidePanels
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolPaletteButtons

                Spacer()

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

                Divider()

                Button(action: { showAI.toggle() }) {
                    Image(systemName: "sparkles")
                        .foregroundColor(showAI ? .accentColor : .primary)
                }
                .help("AI Assistant")
            }
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
                paintColorHex: paintColor.toHex()
            )
            .frame(
                minWidth: CGFloat(document.document.stack.width),
                minHeight: CGFloat(document.document.stack.height)
            )
            .background(Color.gray.opacity(0.3))

            // Status bar
            HStack {
                Text(cardInfoText)
                    .font(.system(size: 11))
                Spacer()
                // Paint color picker (shown for spray, bucket, pencil tools)
                if toolState.category == .paint && (currentTool == .spray || currentTool == .bucket) {
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
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    @ViewBuilder
    private var sidePanels: some View {
        if showInspector {
            PropertyInspector(document: $document, selectedPartIds: $selectedPartIds)
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

    /// Navigate to a new card, dispatching HypeTalk lifecycle messages.
    private func navigateToCard(_ newCardId: UUID) {
        let dispatcher = MessageDispatcher()
        let doc = document.document

        // Close old card and potentially old background
        if let oldCardId = currentCardId {
            let oldBgId = doc.cards.first(where: { $0.id == oldCardId })?.backgroundId
            let _ = dispatcher.dispatch(message: "closeCard", params: [], targetId: oldCardId, document: doc, currentCardId: oldCardId)

            // Background change?
            let newBgId = doc.cards.first(where: { $0.id == newCardId })?.backgroundId
            if oldBgId != newBgId {
                if let bid = oldBgId {
                    let _ = dispatcher.dispatch(message: "closeBackground", params: [], targetId: bid, document: doc, currentCardId: oldCardId)
                }
            }
        }

        currentCardId = newCardId
        selectedPartIds = []

        // Open new background if changed, then open new card
        if let oldCardId = document.document.sortedCards.first(where: { $0.id != newCardId })?.id {
            let oldBgId = doc.cards.first(where: { $0.id == oldCardId })?.backgroundId
            let newBgId = doc.cards.first(where: { $0.id == newCardId })?.backgroundId
            if oldBgId != newBgId, let bid = newBgId {
                let _ = dispatcher.dispatch(message: "openBackground", params: [], targetId: bid, document: document.document, currentCardId: newCardId)
            }
        }
        let _ = dispatcher.dispatch(message: "openCard", params: [], targetId: newCardId, document: document.document, currentCardId: newCardId)
    }

    // MARK: - Info text

    private var cardInfoText: String {
        guard let cardId = currentCardId else { return "No stack open" }
        let (index, count) = CardNavigator.cardPosition(currentCardId: cardId, document: document.document)
        let card = document.document.cards.first { $0.id == cardId }
        let name = card?.name.isEmpty == false ? card!.name : "Card \(index + 1)"
        let bgIndicator: String
        if editingBackground, let card = card {
            let bgName = document.document.backgroundForCard(card)?.name ?? "Background"
            bgIndicator = " [Editing Background: \(bgName)]"
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
}

// MARK: - Notification Handler Modifiers

/// Sub-modifier for navigation, tool, card, and background notifications.
private struct NavigationHandlers: ViewModifier {
    @Binding var document: HypeDocumentWrapper
    @Binding var currentCardId: UUID?
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>
    @Binding var editingBackground: Bool
    @Binding var showAI: Bool

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
                let count = document.document.backgrounds.count
                let _ = document.document.addBackground(name: "Background \(count + 1)")
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleEditBackground)) { notification in
                editingBackground = (notification.object as? Bool) ?? false
                selectedPartIds = []
            }
            .onReceive(NotificationCenter.default.publisher(for: .editPartProperties)) { notification in
                if let partId = notification.object as? UUID {
                    selectedPartIds = [partId]
                    currentTool = .select
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleAI)) { _ in
                showAI.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAllCards)) { _ in
                cycleAllCards()
            }
            .onReceive(NotificationCenter.default.publisher(for: .hypeQuit)) { _ in
                // Dispatch "quit" system message to the current card before app terminates
                if let cardId = currentCardId {
                    let dispatcher = MessageDispatcher()
                    let _ = dispatcher.dispatch(
                        message: "quit",
                        params: [],
                        targetId: cardId,
                        document: document.document,
                        currentCardId: cardId
                    )
                }
            }
    }

    /// Navigate to a new card, dispatching HypeTalk lifecycle messages.
    private func navigateToCard(_ newCardId: UUID) {
        let dispatcher = MessageDispatcher()
        let doc = document.document

        // Close old card and potentially old background
        if let oldCardId = currentCardId {
            let oldBgId = doc.cards.first(where: { $0.id == oldCardId })?.backgroundId
            let _ = dispatcher.dispatch(message: "closeCard", params: [], targetId: oldCardId, document: doc, currentCardId: oldCardId)

            let newBgId = doc.cards.first(where: { $0.id == newCardId })?.backgroundId
            if oldBgId != newBgId {
                if let bid = oldBgId {
                    let _ = dispatcher.dispatch(message: "closeBackground", params: [], targetId: bid, document: doc, currentCardId: oldCardId)
                }
            }
        }

        currentCardId = newCardId
        selectedPartIds = []

        // Open new card (and new background if changed)
        let _ = dispatcher.dispatch(message: "openCard", params: [], targetId: newCardId, document: document.document, currentCardId: newCardId)
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
        // Dispatch newCard message
        let dispatcher = MessageDispatcher()
        let _ = dispatcher.dispatch(message: "newCard", params: [], targetId: newCard.id, document: document.document, currentCardId: newCard.id)
        navigateToCard(newCard.id)
    }

    private func deleteCurrentCard() {
        guard let cardId = currentCardId else { return }
        guard document.document.cards.count > 1 else { return }
        // Dispatch deleteCard message before removing
        let dispatcher = MessageDispatcher()
        let _ = dispatcher.dispatch(message: "deleteCard", params: [], targetId: cardId, document: document.document, currentCardId: cardId)
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
            .onReceive(NotificationCenter.default.publisher(for: .bringForward)) { _ in
                if let id = selectedPartIds.first { document.document.bringForward(id: id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sendBackward)) { _ in
                if let id = selectedPartIds.first { document.document.sendBackward(id: id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bringToFront)) { _ in
                if let id = selectedPartIds.first { document.document.bringToFront(id: id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sendToBack)) { _ in
                if let id = selectedPartIds.first { document.document.sendToBack(id: id) }
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
        let ids = selectedPartIds
        guard ids.count >= 2 else { return }
        let parts = document.document.parts.filter { ids.contains($0.id) }
        guard parts.count >= 2 else { return }

        switch alignment {
        case .left:
            let minLeft = parts.map(\.left).min()!
            for id in ids { document.document.updatePart(id: id) { $0.left = minLeft } }
        case .right:
            let maxRight = parts.map { $0.left + $0.width }.max()!
            for id in ids { document.document.updatePart(id: id) { $0.left = maxRight - $0.width } }
        case .top:
            let minTop = parts.map(\.top).min()!
            for id in ids { document.document.updatePart(id: id) { $0.top = minTop } }
        case .bottom:
            let maxBottom = parts.map { $0.top + $0.height }.max()!
            for id in ids { document.document.updatePart(id: id) { $0.top = maxBottom - $0.height } }
        case .hCenter:
            let avgCenterX = parts.map { $0.left + $0.width / 2 }.reduce(0, +) / Double(parts.count)
            for id in ids { document.document.updatePart(id: id) { $0.left = avgCenterX - $0.width / 2 } }
        case .vCenter:
            let avgCenterY = parts.map { $0.top + $0.height / 2 }.reduce(0, +) / Double(parts.count)
            for id in ids { document.document.updatePart(id: id) { $0.top = avgCenterY - $0.height / 2 } }
        case .distributeH:
            let sorted = parts.sorted { $0.left < $1.left }
            guard sorted.count >= 3 else { return }
            let totalSpan = sorted.last!.left - sorted.first!.left
            let step = totalSpan / Double(sorted.count - 1)
            for (i, part) in sorted.enumerated() {
                if i > 0 && i < sorted.count - 1 {
                    document.document.updatePart(id: part.id) { $0.left = sorted.first!.left + step * Double(i) }
                }
            }
        case .distributeV:
            let sorted = parts.sorted { $0.top < $1.top }
            guard sorted.count >= 3 else { return }
            let totalSpan = sorted.last!.top - sorted.first!.top
            let step = totalSpan / Double(sorted.count - 1)
            for (i, part) in sorted.enumerated() {
                if i > 0 && i < sorted.count - 1 {
                    document.document.updatePart(id: part.id) { $0.top = sorted.first!.top + step * Double(i) }
                }
            }
        }
    }

}

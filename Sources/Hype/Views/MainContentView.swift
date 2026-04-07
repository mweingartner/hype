import SwiftUI
import HypeCore

struct MainContentView: View {
    @Binding var document: HypeDocumentWrapper
    @State private var currentCardId: UUID?
    @State private var currentTool: ToolName = .browse
    @State private var selectedPartId: UUID?
    @State private var editingBackground: Bool = false

    private var toolState: ToolState {
        var state = ToolState(currentTool: currentTool.rawValue)
        state.selectedPartId = selectedPartId
        return state
    }

    private var showInspector: Bool {
        // Show inspector whenever a part is selected — in any tool mode.
        // In browse mode you can double-click to select a part for editing.
        selectedPartId != nil
    }

    var body: some View {
        HSplitView {
            // Canvas area
            VStack(spacing: 0) {
                CardCanvasView(
                    document: $document,
                    currentCardId: currentCardId ?? document.document.sortedCards.first?.id ?? UUID(),
                    currentTool: currentTool,
                    selectedPartId: $selectedPartId,
                    editingBackground: editingBackground
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
                    Text(toolModeText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
            }

            // Property inspector sidebar
            if showInspector {
                PropertyInspector(document: $document, partId: selectedPartId, selectedPartId: $selectedPartId)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolPaletteButtons

                Spacer()

                // Navigation buttons
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
            }
        }
        .onAppear {
            currentCardId = document.document.sortedCards.first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateCard)) { notification in
            guard let direction = notification.object as? NavigationDirection,
                  let cardId = currentCardId else { return }
            if let newId = CardNavigator.navigate(direction: direction, currentCardId: cardId, document: document.document) {
                currentCardId = newId
                selectedPartId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTool)) { notification in
            guard let tool = notification.object as? ToolName else { return }
            currentTool = tool
            selectedPartId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCard)) { notification in
            // Script-driven navigation (e.g., "go next card" in a handler)
            guard let cardId = notification.object as? UUID else { return }
            currentCardId = cardId
            selectedPartId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .addNewCard)) { _ in
            addNewCard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteCurrentCard)) { _ in
            deleteCurrentCard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addNewBackground)) { _ in
            addNewBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditBackground)) { notification in
            editingBackground = (notification.object as? Bool) ?? false
            selectedPartId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .editPartProperties)) { notification in
            // Double-click in browse mode opens part properties
            if let partId = notification.object as? UUID {
                selectedPartId = partId
                // Switch to select tool so the inspector shows properly
                currentTool = .select
            }
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
        currentCardId = newId
        selectedPartId = nil
    }

    private func navigateNext() {
        guard let cardId = currentCardId,
              let newId = CardNavigator.navigate(direction: .next, currentCardId: cardId, document: document.document) else { return }
        currentCardId = newId
        selectedPartId = nil
    }

    // MARK: - Card Management

    private func addNewCard() {
        guard let cardId = currentCardId else { return }
        let sorted = document.document.sortedCards
        let currentIndex = sorted.firstIndex(where: { $0.id == cardId })
        let newCard = document.document.addCard(afterIndex: currentIndex)
        currentCardId = newCard.id
        selectedPartId = nil
    }

    private func deleteCurrentCard() {
        guard let cardId = currentCardId else { return }
        guard document.document.cards.count > 1 else { return } // Keep at least one card
        // Navigate to previous or next before deleting
        let sorted = document.document.sortedCards
        if let idx = sorted.firstIndex(where: { $0.id == cardId }) {
            let nextId = idx + 1 < sorted.count ? sorted[idx + 1].id :
                         idx > 0 ? sorted[idx - 1].id : nil
            // Remove all parts on this card
            let cardParts = document.document.partsForCard(cardId)
            for part in cardParts {
                document.document.removePart(id: part.id)
            }
            // Remove the card
            document.document.cards.removeAll { $0.id == cardId }
            currentCardId = nextId
            selectedPartId = nil
        }
    }

    private func addNewBackground() {
        let count = document.document.backgrounds.count
        let _ = document.document.addBackground(name: "Background \(count + 1)")
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
                selectedPartId = nil
            }) {
                Image(systemName: tool.systemImageName)
                    .foregroundColor(currentTool == tool ? .accentColor : .primary)
            }
            .help(tool.rawValue.capitalized)
        }
    }
}

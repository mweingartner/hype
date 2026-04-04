import SwiftUI
import HypeCore

struct MainContentView: View {
    @Binding var document: HypeDocumentWrapper
    @State private var currentCardId: UUID?
    @State private var currentTool: ToolName = .browse
    @State private var selectedPartId: UUID?

    var body: some View {
        HSplitView {
            // Canvas area
            VStack(spacing: 0) {
                CardCanvasView(
                    document: document.document,
                    currentCardId: currentCardId ?? document.document.sortedCards.first?.id ?? UUID(),
                    currentTool: currentTool,
                    selectedPartId: selectedPartId,
                    onPartSelected: { partId in
                        selectedPartId = partId
                    }
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
                    Text(currentTool.rawValue.capitalized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolPaletteButtons
            }
        }
        .onAppear {
            currentCardId = document.document.sortedCards.first?.id
        }
    }

    private var cardInfoText: String {
        guard let cardId = currentCardId else { return "No stack open" }
        let (index, count) = CardNavigator.cardPosition(currentCardId: cardId, document: document.document)
        let card = document.document.cards.first { $0.id == cardId }
        let name = card?.name.isEmpty == false ? card!.name : "Card \(index + 1)"
        return "\(name) -- \(index + 1) of \(count)"
    }

    @ViewBuilder
    private var toolPaletteButtons: some View {
        ForEach(ToolName.allCases, id: \.self) { tool in
            Button(action: { currentTool = tool }) {
                Image(systemName: tool.systemImageName)
                    .foregroundColor(currentTool == tool ? .accentColor : .primary)
            }
            .help(tool.rawValue.capitalized)
        }
    }
}

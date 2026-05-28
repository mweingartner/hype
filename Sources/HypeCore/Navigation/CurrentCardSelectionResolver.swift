import Foundation

/// Keeps UI selection state aligned with the current document model.
///
/// SwiftUI document windows can keep view-local `@State` while the bound
/// document value changes underneath them. Card IDs are document-scoped, so a
/// previously valid current-card ID must be validated before it is used for
/// rendering, scripting, or automation state.
public enum CurrentCardSelectionResolver {
    public static func resolvedCardId(preferred preferredId: UUID?, in document: HypeDocument) -> UUID? {
        if let preferredId,
           let preferredCard = document.cards.first(where: { $0.id == preferredId }),
           document.backgroundForCard(preferredCard) != nil {
            return preferredId
        }

        if let renderableCard = document.sortedCards.first(where: { document.backgroundForCard($0) != nil }) {
            return renderableCard.id
        }

        return document.sortedCards.first?.id
    }

    public static func containsRenderableCard(_ cardId: UUID?, in document: HypeDocument) -> Bool {
        guard let cardId,
              let card = document.cards.first(where: { $0.id == cardId }) else {
            return false
        }
        return document.backgroundForCard(card) != nil
    }
}

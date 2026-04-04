import Foundation

/// Manages card navigation within a document.
public struct CardNavigator: Sendable {

    /// Navigate to a direction relative to the current card.
    public static func navigate(
        direction: NavigationDirection,
        currentCardId: UUID,
        document: HypeDocument
    ) -> UUID? {
        let sorted = document.sortedCards
        guard !sorted.isEmpty else { return nil }

        switch direction {
        case .first:
            return sorted.first?.id
        case .last:
            return sorted.last?.id
        case .next:
            guard let idx = sorted.firstIndex(where: { $0.id == currentCardId }) else { return nil }
            let nextIdx = idx + 1
            return nextIdx < sorted.count ? sorted[nextIdx].id : nil
        case .previous:
            guard let idx = sorted.firstIndex(where: { $0.id == currentCardId }) else { return nil }
            let prevIdx = idx - 1
            return prevIdx >= 0 ? sorted[prevIdx].id : nil
        }
    }

    /// Get the index and count for display.
    public static func cardPosition(
        currentCardId: UUID,
        document: HypeDocument
    ) -> (index: Int, count: Int) {
        let sorted = document.sortedCards
        let idx = sorted.firstIndex(where: { $0.id == currentCardId }) ?? 0
        return (index: idx, count: sorted.count)
    }
}

/// Navigation directions.
public enum NavigationDirection: Sendable {
    case first, last, next, previous
}

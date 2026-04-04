import Foundation

/// A complete Hype document — contains all data for a .hype stack.
public struct HypeDocument: Codable, Sendable {
    public var stack: Stack
    public var backgrounds: [Background]
    public var cards: [Card]
    public var parts: [Part]

    public init(
        stack: Stack = Stack(),
        backgrounds: [Background] = [],
        cards: [Card] = [],
        parts: [Part] = []
    ) {
        self.stack = stack
        self.backgrounds = backgrounds
        self.cards = cards
        self.parts = parts
    }

    /// Create a new empty document with one default background and card.
    public static func newDocument(name: String = "Untitled") -> HypeDocument {
        let stack = Stack(name: name)
        let bg = Background(stackId: stack.id)
        let card = Card(stackId: stack.id, backgroundId: bg.id, name: "Card 1")
        return HypeDocument(stack: stack, backgrounds: [bg], cards: [card], parts: [])
    }

    /// Get cards sorted by sortKey.
    public var sortedCards: [Card] {
        cards.sorted { $0.sortKey < $1.sortKey }
    }

    /// Get parts for a specific card.
    public func partsForCard(_ cardId: UUID) -> [Part] {
        parts.filter { $0.cardId == cardId }
    }

    /// Get parts for a specific background.
    public func partsForBackground(_ backgroundId: UUID) -> [Part] {
        parts.filter { $0.backgroundId == backgroundId && $0.cardId == nil }
    }

    /// Get the background for a card.
    public func backgroundForCard(_ card: Card) -> Background? {
        backgrounds.first { $0.id == card.backgroundId }
    }

    /// Add a new card after the current one.
    @discardableResult
    public mutating func addCard(afterIndex: Int? = nil) -> Card {
        let bgId = backgrounds.first?.id ?? UUID()
        let index = (afterIndex ?? cards.count - 1) + 1
        let sortKey = String(format: "a%06d", index)
        let card = Card(stackId: stack.id, backgroundId: bgId, name: "", sortKey: sortKey)
        if index < cards.count {
            cards.insert(card, at: index)
        } else {
            cards.append(card)
        }
        return card
    }

    /// Add a part to the document.
    public mutating func addPart(_ part: Part) {
        parts.append(part)
    }

    /// Remove a part by ID.
    public mutating func removePart(id: UUID) {
        parts.removeAll { $0.id == id }
    }

    /// Update a part by ID.
    public mutating func updatePart(id: UUID, transform: (inout Part) -> Void) {
        if let index = parts.firstIndex(where: { $0.id == id }) {
            transform(&parts[index])
        }
    }
}

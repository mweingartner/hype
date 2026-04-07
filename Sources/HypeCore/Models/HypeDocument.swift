import Foundation

/// A complete Hype document — contains all data for a .hype stack.
public struct HypeDocument: Codable, Sendable {
    public var stack: Stack
    public var backgrounds: [Background]
    public var cards: [Card]
    public var parts: [Part]
    public var constraints: [LayoutConstraint]

    public init(
        stack: Stack = Stack(),
        backgrounds: [Background] = [],
        cards: [Card] = [],
        parts: [Part] = [],
        constraints: [LayoutConstraint] = []
    ) {
        self.stack = stack
        self.backgrounds = backgrounds
        self.cards = cards
        self.parts = parts
        self.constraints = constraints
    }

    // Custom decoder for backward compatibility — old documents lack `constraints`.
    enum CodingKeys: String, CodingKey {
        case stack, backgrounds, cards, parts, constraints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stack = try container.decode(Stack.self, forKey: .stack)
        backgrounds = try container.decode([Background].self, forKey: .backgrounds)
        cards = try container.decode([Card].self, forKey: .cards)
        parts = try container.decode([Part].self, forKey: .parts)
        constraints = try container.decodeIfPresent([LayoutConstraint].self, forKey: .constraints) ?? []
    }

    /// Create a new empty document with one default background and card.
    public static func newDocument(name: String = "Untitled") -> HypeDocument {
        let stack = Stack(name: name)
        let bg = Background(stackId: stack.id, name: "Background 1")
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

    /// Create a new background with the given name. Names must be unique in the stack.
    @discardableResult
    public mutating func addBackground(name: String) -> Background {
        var finalName = name
        var counter = 1
        while backgrounds.contains(where: { $0.name.lowercased() == finalName.lowercased() }) {
            counter += 1
            finalName = "\(name) \(counter)"
        }
        let bg = Background(stackId: stack.id, name: finalName, sortKey: String(format: "a%06d", backgrounds.count))
        backgrounds.append(bg)
        return bg
    }

    /// Find a background by name (case-insensitive).
    public func backgroundByName(_ name: String) -> Background? {
        backgrounds.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Get all cards that share a specific background.
    public func cardsForBackground(_ backgroundId: UUID) -> [Card] {
        cards.filter { $0.backgroundId == backgroundId }
    }

    /// Add a new card. Uses the specified background, or the current card's background, or the first background.
    @discardableResult
    public mutating func addCard(afterIndex: Int? = nil, backgroundId: UUID? = nil, backgroundName: String? = nil) -> Card {
        let bgId: UUID
        if let bid = backgroundId {
            bgId = bid
        } else if let bname = backgroundName, let bg = backgroundByName(bname) {
            bgId = bg.id
        } else if let afterIdx = afterIndex, afterIdx < sortedCards.count {
            bgId = sortedCards[afterIdx].backgroundId
        } else {
            bgId = backgrounds.first?.id ?? UUID()
        }
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

    // MARK: - Draw Order

    /// Move a part one position forward (draws later = on top).
    public mutating func bringForward(id: UUID) {
        guard let index = parts.firstIndex(where: { $0.id == id }),
              index + 1 < parts.count else { return }
        parts.swapAt(index, index + 1)
    }

    /// Move a part one position backward (draws earlier = behind).
    public mutating func sendBackward(id: UUID) {
        guard let index = parts.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        parts.swapAt(index, index - 1)
    }

    /// Move a part to the front (last in array = drawn on top of everything).
    public mutating func bringToFront(id: UUID) {
        guard let index = parts.firstIndex(where: { $0.id == id }) else { return }
        let part = parts.remove(at: index)
        parts.append(part)
    }

    /// Move a part to the back (first in array = drawn behind everything).
    public mutating func sendToBack(id: UUID) {
        guard let index = parts.firstIndex(where: { $0.id == id }) else { return }
        let part = parts.remove(at: index)
        parts.insert(part, at: 0)
    }

    // MARK: - Constraints

    /// Add a layout constraint to the document.
    public mutating func addConstraint(_ constraint: LayoutConstraint) {
        constraints.append(constraint)
    }

    /// Remove a layout constraint by ID.
    public mutating func removeConstraint(id: UUID) {
        constraints.removeAll { $0.id == id }
    }

    /// Get all constraints where the given part is the source.
    public func constraintsForPart(_ partId: UUID) -> [LayoutConstraint] {
        constraints.filter { $0.sourcePartId == partId }
    }

    /// Remove all constraints referencing a specific part (as source or target).
    public mutating func removeConstraintsForPart(_ partId: UUID) {
        constraints.removeAll { $0.sourcePartId == partId || $0.targetPartId == partId }
    }
}

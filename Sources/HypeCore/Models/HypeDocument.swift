import Foundation

/// A complete Hype document — contains all data for a .hype stack.
public struct HypeDocument: Codable, Sendable {
    public var stack: Stack
    public var backgrounds: [Background]
    public var cards: [Card]
    public var parts: [Part]
    public var paintLayers: [CardPaintLayer]
    public var constraints: [LayoutConstraint]
    public var spriteRepository: SpriteRepository
    /// Stack-scoped, user-curated files/images/directories/notes that the AI can
    /// search through narrow context tools. Stored in the document so whole-stack
    /// build context travels with the stack instead of relying on arbitrary file
    /// system access.
    public var aiContextLibrary: AIContextLibrary
    public var aiPromptHistory: [String]
    public var defaultBackgroundId: UUID?
    /// Optional metadata for documents converted from original
    /// HyperCard stacks. When present, it preserves the import report
    /// and, when size limits allow, the original data/resource forks
    /// for future importer passes and auditability.
    public var legacyImport: LegacyStackImportMetadata?

    /// User-defined themes that travel with this `.hype` document.
    /// Built-in themes (in `BuiltInThemes.all`) are NOT stored here —
    /// they're application-wide, baked into the binary, and always
    /// available regardless of which stack you open.
    ///
    /// Look up a theme by name via `theme(named:)` (defined in
    /// `Sources/HypeCore/Theme/ThemeResolver.swift`); resolve a
    /// card's effective theme via `effectiveTheme(forCard:)`.
    public var themes: [HypeTheme]

    /// HypeTalk `global` variables that outlive any single handler
    /// invocation. HyperCard's semantics: globals are initialised
    /// to empty on first reference and persist for the lifetime of
    /// the running stack (i.e. across every handler dispatch, every
    /// card / background / stack script, every idle tick). Before
    /// this field existed, each `MessageDispatcher.dispatch` call
    /// constructed a fresh interpreter with empty globals, so a
    /// script like `on idle / add 5 to rot / end idle` would read
    /// `rot` as empty on every tick and never accumulate. Now the
    /// interpreter seeds `env.globals` from this dictionary on
    /// entry and writes them back on exit, which is what HyperCard
    /// has always done.
    ///
    /// Not persisted: this field is intentionally excluded from
    /// encoding/decoding so globals don't leak between stack
    /// sessions via the `.hype` file. They live only for the
    /// running session.
    public var scriptGlobals: [String: String]

    public init(
        stack: Stack = Stack(),
        backgrounds: [Background] = [],
        cards: [Card] = [],
        parts: [Part] = [],
        paintLayers: [CardPaintLayer] = [],
        constraints: [LayoutConstraint] = [],
        spriteRepository: SpriteRepository = SpriteRepository(),
        aiContextLibrary: AIContextLibrary = AIContextLibrary(),
        aiPromptHistory: [String] = [],
        scriptGlobals: [String: String] = [:],
        defaultBackgroundId: UUID? = nil,
        legacyImport: LegacyStackImportMetadata? = nil,
        themes: [HypeTheme] = []
    ) {
        self.stack = stack
        self.backgrounds = backgrounds
        self.cards = cards
        self.parts = parts
        self.paintLayers = paintLayers
        self.constraints = constraints
        self.spriteRepository = spriteRepository
        self.aiContextLibrary = aiContextLibrary
        self.aiPromptHistory = aiPromptHistory
        self.scriptGlobals = scriptGlobals
        self.defaultBackgroundId = defaultBackgroundId
        self.legacyImport = legacyImport
        self.themes = themes
    }

    // Custom decoder for backward compatibility.
    enum CodingKeys: String, CodingKey {
        case stack, backgrounds, cards, parts, paintLayers, constraints, spriteRepository, aiContextLibrary, aiPromptHistory, defaultBackgroundId
        case legacyImport
        case themes
        // `scriptGlobals` is NOT in the coding keys — session-only.
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stack = try container.decode(Stack.self, forKey: .stack)
        backgrounds = try container.decode([Background].self, forKey: .backgrounds)
        cards = try container.decode([Card].self, forKey: .cards)
        let rawParts = try container.decode([Part].self, forKey: .parts)
        // Forward-compat: filter out parts with unknown types so future .hype
        // files containing newer part-types still load without crashing.
        let filteredParts = rawParts.filter { part in
            if part.partType == .unknown {
                HypeLogger.shared.warn("Skipping part '\(part.name)' with unrecognised partType — document may have been created by a newer Hype version", source: "HypeDocument.init(from:)")
                return false
            }
            return true
        }
        parts = filteredParts
        paintLayers = try container.decodeIfPresent([CardPaintLayer].self, forKey: .paintLayers) ?? []
        constraints = try container.decodeIfPresent([LayoutConstraint].self, forKey: .constraints) ?? []
        spriteRepository = try container.decodeIfPresent(SpriteRepository.self, forKey: .spriteRepository) ?? SpriteRepository()
        aiContextLibrary = try container.decodeIfPresent(AIContextLibrary.self, forKey: .aiContextLibrary) ?? AIContextLibrary()
        aiPromptHistory = try container.decodeIfPresent([String].self, forKey: .aiPromptHistory) ?? []
        defaultBackgroundId = try container.decodeIfPresent(UUID.self, forKey: .defaultBackgroundId)
        legacyImport = try container.decodeIfPresent(LegacyStackImportMetadata.self, forKey: .legacyImport)
        // Backward-compatible: pre-theme documents have no themes array.
        themes = try container.decodeIfPresent([HypeTheme].self, forKey: .themes) ?? []
        scriptGlobals = [:]  // session-only, always starts empty on load
    }

    /// Create a new empty document with one default background and card.
    public static func newDocument(name: String = "Untitled") -> HypeDocument {
        let stack = Stack(name: name)
        let bg = Background(stackId: stack.id, name: "Background 1")
        let card = Card(stackId: stack.id, backgroundId: bg.id, name: "Card 1")
        return HypeDocument(stack: stack, backgrounds: [bg], cards: [card], parts: [], defaultBackgroundId: bg.id)
    }

    /// Get cards sorted by sortKey.
    public var sortedCards: [Card] {
        cards.sorted { $0.sortKey < $1.sortKey }
    }

    /// Look up a part by its UUID. Returns nil if the part doesn't
    /// exist or has been removed.
    ///
    /// Today this is just a wrapped linear scan over `parts` —
    /// matching the pattern that 91 callsites in the Hype target
    /// already use (`parts.first(where: { $0.id == id })`). Routing
    /// those callsites through this helper is a step toward the
    /// audit's recommended `[UUID: Int]` index: once the indirection
    /// is in place, the underlying implementation can be swapped to
    /// an indexed lookup without touching the call sites again.
    /// Migration is opportunistic — new code uses this helper, old
    /// code can move over as it's touched for other reasons.
    public func part(byId id: UUID) -> Part? {
        return parts.first(where: { $0.id == id })
    }

    /// Look up a part's index in `parts` by UUID. Mirror of
    /// `part(byId:)`; same eventual-indexing rationale.
    public func partIndex(byId id: UUID) -> Int? {
        return parts.firstIndex(where: { $0.id == id })
    }

    /// Get parts for a specific card.
    public func partsForCard(_ cardId: UUID) -> [Part] {
        parts.filter { $0.cardId == cardId }
    }

    /// Get parts for a specific background.
    public func partsForBackground(_ backgroundId: UUID) -> [Part] {
        parts.filter { $0.backgroundId == backgroundId && $0.cardId == nil }
    }

    /// Get the effective visible parts for a card, including any
    /// background-shared parts owned by that card's background.
    public func effectivePartsForCard(_ cardId: UUID) -> [Part] {
        let cardParts = partsForCard(cardId)
        guard let card = cards.first(where: { $0.id == cardId }) else { return cardParts }
        return cardParts + partsForBackground(card.backgroundId)
    }

    /// Get the persisted paint layer snapshot for a card, if any.
    public func paintLayer(forCardId cardId: UUID) -> CardPaintLayer? {
        paintLayers.first { $0.cardId == cardId }
    }

    /// Store or replace a card paint layer snapshot.
    public mutating func setPaintLayer(_ layer: CardPaintLayer) {
        if layer.isEmpty {
            removePaintLayer(forCardId: layer.cardId)
            return
        }
        if let index = paintLayers.firstIndex(where: { $0.cardId == layer.cardId }) {
            paintLayers[index] = layer
        } else {
            paintLayers.append(layer)
        }
    }

    /// Remove a persisted paint layer from the document.
    public mutating func removePaintLayer(forCardId cardId: UUID) {
        paintLayers.removeAll { $0.cardId == cardId }
    }

    /// Get the background for a card.
    public func backgroundForCard(_ card: Card) -> Background? {
        backgrounds.first { $0.id == card.backgroundId }
    }

    /// The effective default background ID — validates that the stored
    /// ID still references a live background, falling back to the first.
    public var resolvedDefaultBackgroundId: UUID? {
        if let id = defaultBackgroundId, backgrounds.contains(where: { $0.id == id }) {
            return id
        }
        return backgrounds.first?.id
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

    /// Remove a background by ID. Refuses to delete the last background.
    /// Orphaned cards are reassigned to the resolved default background.
    /// If the deleted background was the default, promotes the first remaining.
    @discardableResult
    public mutating func removeBackground(id: UUID) -> Bool {
        guard backgrounds.count > 1 else { return false }
        backgrounds.removeAll { $0.id == id }
        // Remove parts owned by this background
        parts.removeAll { $0.backgroundId == id && $0.cardId == nil }
        // Reassign orphaned cards to the default
        let fallback = resolvedDefaultBackgroundId ?? backgrounds.first!.id
        for i in cards.indices where cards[i].backgroundId == id {
            cards[i].backgroundId = fallback
        }
        // If deleted was the default, promote first remaining
        if defaultBackgroundId == id {
            defaultBackgroundId = backgrounds.first?.id
        }
        return true
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
            bgId = resolvedDefaultBackgroundId ?? UUID()
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

    /// Remove a part and document-level references that cannot survive without it.
    ///
    /// `removePart(id:)` remains the raw array mutation for compatibility with
    /// low-level callers and tests. User-facing delete paths should prefer this
    /// helper so constraints do not retain stale source/target IDs after the part
    /// is gone.
    public mutating func deletePart(id: UUID) {
        removeConstraintsForPart(id)
        removePart(id: id)
    }

    /// Update a part by ID.
    public mutating func updatePart(id: UUID, transform: (inout Part) -> Void) {
        if let index = partIndex(byId: id) {
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

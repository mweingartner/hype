import Foundation

public struct ProjectNavigationTarget: Equatable, Sendable {
    public var stackEntryId: UUID
    public var stackName: String
    public var stackAlias: String
    public var packagePath: String?
    public var documentPath: String?
    public var legacyCardId: Int?
    public var cardName: String
    public var sortIndex: Int?
    public var hypeCardId: UUID?

    public init(
        stackEntryId: UUID,
        stackName: String,
        stackAlias: String,
        packagePath: String? = nil,
        documentPath: String? = nil,
        legacyCardId: Int? = nil,
        cardName: String = "",
        sortIndex: Int? = nil,
        hypeCardId: UUID? = nil
    ) {
        self.stackEntryId = stackEntryId
        self.stackName = stackName
        self.stackAlias = stackAlias
        self.packagePath = packagePath
        self.documentPath = documentPath
        self.legacyCardId = legacyCardId
        self.cardName = cardName
        self.sortIndex = sortIndex
        self.hypeCardId = hypeCardId
    }
}

public enum ProjectNavigationTargetResolver {
    public static func resolveCardId(
        for target: ProjectNavigationTarget,
        in document: HypeDocument
    ) -> UUID? {
        if let hypeCardId = target.hypeCardId,
           document.cards.contains(where: { $0.id == hypeCardId }) {
            return hypeCardId
        }

        if let libraryCardId = stackLibraryCardId(for: target, in: document) {
            return libraryCardId
        }

        if !target.cardName.isEmpty {
            let key = HypeStackLibrary.lookupKey(target.cardName)
            let matches = document.cards.filter { HypeStackLibrary.lookupKey($0.name) == key }
            if matches.count == 1 {
                return matches[0].id
            }
        }

        if let sortIndex = target.sortIndex {
            let cards = document.sortedCards
            if cards.indices.contains(sortIndex) {
                return cards[sortIndex].id
            }
        }

        return nil
    }

    private static func stackLibraryCardId(
        for target: ProjectNavigationTarget,
        in document: HypeDocument
    ) -> UUID? {
        guard let entry = document.stackLibrary.entries.first(where: { entry in
            entry.id == target.stackEntryId
                || HypeStackLibrary.lookupKey(entry.stackName) == HypeStackLibrary.lookupKey(target.stackName)
        }) else { return nil }

        let matches = entry.cardReferences.filter { reference in
            if let legacyCardId = target.legacyCardId,
               reference.legacyCardId == legacyCardId {
                return true
            }
            if !target.cardName.isEmpty,
               HypeStackLibrary.lookupKey(reference.name) == HypeStackLibrary.lookupKey(target.cardName) {
                return true
            }
            if let sortIndex = target.sortIndex,
               reference.sortIndex == sortIndex {
                return true
            }
            return false
        }

        let cardIds = matches.compactMap(\.hypeCardId).filter { cardId in
            document.cards.contains { $0.id == cardId }
        }
        let uniqueCardIds = Array(Set(cardIds))
        return uniqueCardIds.count == 1 ? uniqueCardIds[0] : nil
    }
}

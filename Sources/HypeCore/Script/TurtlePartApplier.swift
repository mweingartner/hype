import Foundation

/// The one document-mutation path for turtle output (design.md D4,
/// turtle-graphics). Converts a `TurtleEngine.Outcome` into `Part`
/// values and appends them to the document — the HypeTalk interpreter
/// (P2) and the `draw_with_turtle` AI tool (P3) both go through this so
/// naming, sort order, and deletion rules can never fork between
/// surfaces (Condition 1, Condition 8).
public enum TurtlePartApplier {
    /// Name prefixes a turtle-drawn part may carry, in
    /// `TurtleEngine.Emission.Kind` order (path, fill, dot). `clean`
    /// deletes every part on the target card whose name starts with
    /// one of these.
    public static let namePrefixes = ["turtle path", "turtle fill", "turtle dot"]

    /// Applies `outcome` to `document`: when `outcome.deletesTurtleParts`,
    /// first deletes every part on `cardId` whose name starts with one
    /// of `namePrefixes` (via `document.deletePart(id:)`, so dangling
    /// constraints are cleaned up too); then appends one `Part` per
    /// emission, in emission order, each named `"<prefix> N"` with `N`
    /// the smallest positive integer not already used with that prefix
    /// on `cardId`, sort-keyed via the existing next-part-sort-ordinal
    /// path. Returns the appended parts, in order.
    @discardableResult
    public static func apply(
        _ outcome: TurtleEngine.Outcome,
        to document: inout HypeDocument,
        cardId: UUID
    ) -> [Part] {
        if outcome.deletesTurtleParts {
            let idsToDelete = document.parts
                .filter { $0.cardId == cardId && isTurtleNamed($0.name) }
                .map(\.id)
            for id in idsToDelete {
                document.deletePart(id: id)
            }
        }

        guard !outcome.emissions.isEmpty else { return [] }

        var nextSortOrdinal = document.nextPartSortOrdinal()
        var appended: [Part] = []
        appended.reserveCapacity(outcome.emissions.count)
        for emission in outcome.emissions {
            let part = makePart(for: emission, cardId: cardId, document: document, appendedSoFar: appended, sortOrdinal: nextSortOrdinal)
            nextSortOrdinal += 1
            document.parts.append(part)
            appended.append(part)
        }
        return appended
    }

    private static func isTurtleNamed(_ name: String) -> Bool {
        namePrefixes.contains { name.hasPrefix($0) }
    }

    private static func prefix(for kind: TurtleEngine.Emission.Kind) -> String {
        switch kind {
        case .path: return "turtle path"
        case .fill: return "turtle fill"
        case .dot: return "turtle dot"
        }
    }

    /// Smallest positive integer `N` such that `"<prefix> N"` is not
    /// already used on `cardId`, checking both the live document and
    /// parts appended earlier in this same `apply` call (so two
    /// same-kind emissions in one outcome get distinct names).
    private static func nextName(prefix: String, cardId: UUID, document: HypeDocument, appendedSoFar: [Part]) -> String {
        var used = Set(document.parts.filter { $0.cardId == cardId }.map(\.name))
        used.formUnion(appendedSoFar.filter { $0.cardId == cardId }.map(\.name))
        var n = 1
        while used.contains("\(prefix) \(n)") {
            n += 1
        }
        return "\(prefix) \(n)"
    }

    private static func makePart(
        for emission: TurtleEngine.Emission,
        cardId: UUID,
        document: HypeDocument,
        appendedSoFar: [Part],
        sortOrdinal: Int
    ) -> Part {
        let namePrefix = prefix(for: emission.kind)
        let name = nextName(prefix: namePrefix, cardId: cardId, document: document, appendedSoFar: appendedSoFar)
        var part = Part(
            partType: .shape,
            cardId: cardId,
            name: name,
            sortKey: String(format: "a%06d", sortOrdinal),
            left: emission.frame.left,
            top: emission.frame.top,
            width: emission.frame.width,
            height: emission.frame.height
        )
        part.shapeType = emission.kind == .dot ? .oval : .freeform
        part.fillColor = emission.fillColor
        part.strokeColor = emission.strokeColor
        part.strokeWidth = emission.strokeWidth
        part.pathData = emission.pathData
        return part
    }
}

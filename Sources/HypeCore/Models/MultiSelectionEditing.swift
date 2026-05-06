import Foundation

/// Helpers for editing properties uniformly across a multi-part
/// selection. Lifted out of `PropertyInspector` so the math is
/// testable without spinning up a SwiftUI view tree.
///
/// The two operations the inspector cares about:
///
/// 1. **`commonValue(in:for:)`** — returns the value shared by every
///    part in the selection for a given KeyPath, or `nil` if the
///    parts disagree. Used to drive the inspector's "Multiple"
///    placeholder when the selected parts don't all share the same
///    value for a property.
///
/// 2. **`applyValue(_:to:in:)`** — apply a value uniformly to every
///    part in the selection. Centralized here so the bulk-update
///    contract has one canonical implementation that downstream
///    tools (HypeTalk's hypothetical future "set the X of selection",
///    AI tools wanting to bulk-edit, etc.) can share.
public enum MultiSelectionEditing {

    /// The value shared by every part in `parts` for `keyPath`, or
    /// `nil` if the values differ. Empty input yields `nil`.
    ///
    /// Linear-time in the size of `parts` — fine for the typical
    /// selection size (a few dozen parts at most). Stops early on
    /// the first divergence so a 1000-part selection with the first
    /// two parts disagreeing returns nil after two reads.
    public static func commonValue<T: Equatable>(
        in parts: [Part],
        for keyPath: KeyPath<Part, T>
    ) -> T? {
        guard let first = parts.first?[keyPath: keyPath] else { return nil }
        for p in parts.dropFirst() {
            if p[keyPath: keyPath] != first { return nil }
        }
        return first
    }

    /// Apply `value` to every part in `parts` (resolved by id) inside
    /// `document`. Returns the number of parts mutated.
    ///
    /// Ids that don't resolve to a part in the document are silently
    /// skipped — matches `HypeDocument.updatePart`'s contract.
    @discardableResult
    public static func applyValue<T>(
        _ value: T,
        to keyPath: WritableKeyPath<Part, T>,
        in document: inout HypeDocument,
        for ids: any Sequence<UUID>
    ) -> Int {
        var changed = 0
        for id in ids {
            let before = document.parts.first(where: { $0.id == id })
            document.updatePart(id: id) { $0[keyPath: keyPath] = value }
            // Count only ids that actually resolved to a part. Use
            // the before-snapshot since updatePart returns void.
            if before != nil { changed += 1 }
        }
        return changed
    }
}

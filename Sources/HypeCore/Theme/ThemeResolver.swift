import Foundation

/// Cascade resolution + theme registry helpers built on top of
/// `HypeDocument`.
///
/// The cascade for a card is:
///     card.themeName  →  background.themeName  →  stack.themeName
/// Stack.themeName is non-optional and defaults to
/// `BuiltInThemes.fallbackName`, so the chain always terminates.
///
/// If the cascade resolves to a name that no longer exists (e.g.
/// the user deleted the referenced theme), we fall through to the
/// next level. If even the stack's theme name is missing from the
/// catalog, we land on `BuiltInThemes.system` so views always have
/// SOMETHING to render.
public extension HypeDocument {

    // MARK: Lookup

    /// Look up a theme by case-insensitive name. Document-local
    /// (user) themes win over built-ins on collision — that lets a
    /// user override "System" with their own variant if they want.
    func theme(named: String?) -> HypeTheme? {
        guard let raw = named?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty
        else { return nil }
        let lower = raw.lowercased()
        if let user = themes.first(where: { $0.name.lowercased() == lower }) {
            return user
        }
        return BuiltInThemes.find(named: raw)
    }

    /// Every theme available to this document, in display order:
    /// built-ins first, then user themes alphabetized.
    var allAvailableThemes: [HypeTheme] {
        BuiltInThemes.all + themes.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Just the names — handy for HypeTalk's `the themes` accessor
    /// and for the Theme Designer's sidebar.
    var allThemeNames: [String] {
        allAvailableThemes.map(\.name)
    }

    // MARK: Cascade

    /// Resolve the effective theme for a given card id. Follows the
    /// card → background → stack chain, falling through any level
    /// whose name doesn't resolve. Always returns a value.
    func effectiveTheme(forCard cardId: UUID?) -> HypeTheme {
        if let cardId,
           let card = cards.first(where: { $0.id == cardId }) {
            if let cardTheme = theme(named: card.themeName) { return cardTheme }
            if let bg = backgrounds.first(where: { $0.id == card.backgroundId }),
               let bgTheme = theme(named: bg.themeName) {
                return bgTheme
            }
        }
        if let stackTheme = theme(named: stack.themeName) { return stackTheme }
        return BuiltInThemes.system
    }

    /// Same lookup but tells you which level provided the theme,
    /// useful for inspector hints ("inheriting from background X").
    func effectiveThemeOrigin(forCard cardId: UUID?)
        -> (theme: HypeTheme, origin: ThemeOrigin)
    {
        if let cardId,
           let card = cards.first(where: { $0.id == cardId }) {
            if let t = theme(named: card.themeName) {
                return (t, .card(cardId))
            }
            if let bg = backgrounds.first(where: { $0.id == card.backgroundId }),
               let t = theme(named: bg.themeName) {
                return (t, .background(bg.id))
            }
        }
        if let t = theme(named: stack.themeName) {
            return (t, .stack)
        }
        return (BuiltInThemes.system, .fallback)
    }

    // MARK: Mutation helpers

    /// Add a user theme. Rejects on name collision (case-insensitive)
    /// against any existing user theme OR built-in. Returns the new
    /// theme on success, nil on collision.
    @discardableResult
    mutating func addTheme(_ theme: HypeTheme) -> HypeTheme? {
        let lower = theme.name.lowercased()
        if BuiltInThemes.all.contains(where: { $0.name.lowercased() == lower }) {
            return nil
        }
        if themes.contains(where: { $0.name.lowercased() == lower }) {
            return nil
        }
        var stamped = theme
        stamped.isBuiltIn = false  // user themes are never marked built-in
        if stamped.createdAt == Date.distantPast { stamped.createdAt = Date() }
        stamped.modifiedAt = Date()
        themes.append(stamped)
        return stamped
    }

    /// Update an existing user theme by id. Refuses to update a
    /// built-in (returns false). On rename, refuses if the new
    /// name collides with another theme.
    @discardableResult
    mutating func updateTheme(id: UUID, _ transform: (inout HypeTheme) -> Void) -> Bool {
        guard let idx = themes.firstIndex(where: { $0.id == id }),
              !themes[idx].isBuiltIn
        else { return false }
        var t = themes[idx]
        let oldName = t.name
        transform(&t)
        // Reject rename collisions (compare against everything except
        // ourselves).
        if t.name.lowercased() != oldName.lowercased() {
            let lower = t.name.lowercased()
            if BuiltInThemes.all.contains(where: { $0.name.lowercased() == lower }) {
                return false
            }
            if themes.contains(where: { $0.id != id && $0.name.lowercased() == lower }) {
                return false
            }
            // Cascade-rename: every Stack/Background/Card that
            // references the old name now points at the new name.
            renameThemeReferences(from: oldName, to: t.name)
        }
        t.isBuiltIn = false
        t.modifiedAt = Date()
        themes[idx] = t
        return true
    }

    /// Delete a user theme by id. Refuses to delete a built-in.
    /// Cascades to clear references at every scope so views fall
    /// through the cascade safely.
    ///
    /// If the deleted theme was referenced by `stack.themeName`,
    /// that reference resets to `BuiltInThemes.fallbackName` to
    /// satisfy the invariant that the stack always has a theme.
    @discardableResult
    mutating func deleteTheme(id: UUID) -> Bool {
        guard let idx = themes.firstIndex(where: { $0.id == id }),
              !themes[idx].isBuiltIn
        else { return false }
        let removedName = themes[idx].name
        themes.remove(at: idx)
        clearThemeReferences(named: removedName)
        return true
    }

    /// Duplicate any theme (built-in or user) into a new user theme
    /// with a unique name. The default name follows "<original>
    /// Copy", "<original> Copy 2", etc.
    @discardableResult
    mutating func duplicateTheme(named: String, candidateName: String? = nil)
        -> HypeTheme?
    {
        guard let source = theme(named: named) else { return nil }
        let baseName = candidateName ?? "\(source.name) Copy"
        let unique = uniqueThemeName(starting: baseName)
        let copy = source.duplicate(named: unique)
        themes.append(copy)
        return copy
    }

    /// Generate a candidate theme name not in conflict with any
    /// existing theme (built-in or user). Appends " 2", " 3", … to
    /// the base name until a unique form is found.
    func uniqueThemeName(starting base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        let seed = trimmed.isEmpty ? "Untitled" : trimmed
        let lookup = Set(allThemeNames.map { $0.lowercased() })
        if !lookup.contains(seed.lowercased()) { return seed }
        var i = 2
        while lookup.contains("\(seed) \(i)".lowercased()) { i += 1 }
        return "\(seed) \(i)"
    }

    // MARK: Reference housekeeping

    /// Replace every `themeName == old` reference with `new` across
    /// stack, backgrounds, and cards. Used by `updateTheme` on
    /// rename so live references don't dangle.
    mutating func renameThemeReferences(from old: String, to new: String) {
        let oldLower = old.lowercased()
        if stack.themeName.lowercased() == oldLower { stack.themeName = new }
        for i in backgrounds.indices {
            if backgrounds[i].themeName?.lowercased() == oldLower {
                backgrounds[i].themeName = new
            }
        }
        for i in cards.indices {
            if cards[i].themeName?.lowercased() == oldLower {
                cards[i].themeName = new
            }
        }
    }

    /// Clear references to a now-deleted theme. Cards and backgrounds
    /// reset to nil (cascade falls through). The stack resets to
    /// the built-in fallback because stack.themeName is non-optional.
    mutating func clearThemeReferences(named name: String) {
        let lower = name.lowercased()
        if stack.themeName.lowercased() == lower {
            stack.themeName = BuiltInThemes.fallbackName
        }
        for i in backgrounds.indices {
            if backgrounds[i].themeName?.lowercased() == lower {
                backgrounds[i].themeName = nil
            }
        }
        for i in cards.indices {
            if cards[i].themeName?.lowercased() == lower {
                cards[i].themeName = nil
            }
        }
    }

    /// Count how many objects (cards/backgrounds/stack) currently
    /// reference a theme by name. Drives the Theme Designer's
    /// "Affected: 3 cards / 1 background / stack default" panel.
    func usageCount(themeName: String) -> ThemeUsage {
        let lower = themeName.lowercased()
        let cardCount = cards.filter { $0.themeName?.lowercased() == lower }.count
        let bgCount = backgrounds.filter { $0.themeName?.lowercased() == lower }.count
        let isStackDefault = stack.themeName.lowercased() == lower
        return ThemeUsage(
            cards: cardCount,
            backgrounds: bgCount,
            isStackDefault: isStackDefault
        )
    }
}

/// Where the resolved theme came from in the cascade.
public enum ThemeOrigin: Equatable, Sendable {
    case card(UUID)
    case background(UUID)
    case stack
    case fallback     // every level missed; resolved to BuiltInThemes.system

    public var description: String {
        switch self {
        case .card:        return "card"
        case .background:  return "background"
        case .stack:       return "stack"
        case .fallback:    return "fallback"
        }
    }
}

/// Summary of how many objects reference a given theme name.
public struct ThemeUsage: Equatable, Sendable {
    public var cards: Int
    public var backgrounds: Int
    public var isStackDefault: Bool

    public var total: Int {
        cards + backgrounds + (isStackDefault ? 1 : 0)
    }

    public var isInUse: Bool { total > 0 }

    public init(cards: Int, backgrounds: Int, isStackDefault: Bool) {
        self.cards = cards
        self.backgrounds = backgrounds
        self.isStackDefault = isStackDefault
    }
}

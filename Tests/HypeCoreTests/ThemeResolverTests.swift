import Testing
import Foundation
@testable import HypeCore

@Suite("Theme cascade resolver and document mutation helpers")
struct ThemeResolverTests {

    // MARK: - Helpers

    private func docWithThreeCardsTwoBackgrounds() -> HypeDocument {
        var doc = HypeDocument.newDocument(name: "Cascade Test")
        let stackId = doc.stack.id
        let bg2 = Background(stackId: stackId, name: "Background 2", sortKey: "a1")
        doc.backgrounds.append(bg2)
        let card2 = Card(stackId: stackId, backgroundId: doc.backgrounds[0].id,
                         name: "Card 2", sortKey: "a1")
        let card3 = Card(stackId: stackId, backgroundId: bg2.id,
                         name: "Card 3", sortKey: "a2")
        doc.cards.append(card2)
        doc.cards.append(card3)
        return doc
    }

    // MARK: - Cascade resolution

    @Test("effectiveTheme falls back to System when no level sets a theme")
    func cascadeFallsToFallback() {
        let doc = docWithThreeCardsTwoBackgrounds()
        let resolved = doc.effectiveTheme(forCard: doc.cards[0].id)
        // Stack defaults to themeName="System", so fallback resolves to System.
        #expect(resolved.name == "System")
    }

    @Test("Stack-level theme propagates to every card")
    func stackThemePropagatesToAllCards() {
        var doc = docWithThreeCardsTwoBackgrounds()
        doc.stack.themeName = "Sunset"
        for card in doc.cards {
            let resolved = doc.effectiveTheme(forCard: card.id)
            #expect(resolved.name == "Sunset",
                    "card \(card.name) should resolve to Sunset, got \(resolved.name)")
        }
    }

    @Test("Background-level theme overrides stack theme")
    func backgroundThemeOverridesStack() {
        var doc = docWithThreeCardsTwoBackgrounds()
        doc.stack.themeName = "Sunset"
        doc.backgrounds[1].themeName = "Modern Dark"   // Background 2

        // Card 1 + Card 2 use Background 1 (no themeName) → Sunset (from stack)
        // Card 3 uses Background 2 → Modern Dark
        let card1Theme = doc.effectiveTheme(forCard: doc.cards[0].id)
        let card3Theme = doc.effectiveTheme(forCard: doc.cards[2].id)
        #expect(card1Theme.name == "Sunset")
        #expect(card3Theme.name == "Modern Dark")
    }

    @Test("Card-level theme overrides background theme")
    func cardThemeOverridesBackground() {
        var doc = docWithThreeCardsTwoBackgrounds()
        doc.stack.themeName = "Sunset"
        doc.backgrounds[1].themeName = "Modern Dark"
        doc.cards[2].themeName = "Neon"   // Card 3 forces Neon

        let card3Theme = doc.effectiveTheme(forCard: doc.cards[2].id)
        #expect(card3Theme.name == "Neon")
    }

    @Test("Cascade falls through when a level references a missing theme")
    func cascadeFallsThroughMissingReferences() {
        var doc = docWithThreeCardsTwoBackgrounds()
        doc.stack.themeName = "Modern Dark"
        doc.cards[0].themeName = "DoesNotExist"     // missing — fall through
        doc.cards[0].backgroundId = doc.backgrounds[0].id
        // Background 1 has no themeName so we fall through to stack.
        let resolved = doc.effectiveTheme(forCard: doc.cards[0].id)
        #expect(resolved.name == "Modern Dark")
    }

    @Test("Cascade resolves user themes by case-insensitive name")
    func cascadeIsCaseInsensitive() {
        var doc = docWithThreeCardsTwoBackgrounds()
        let user = BuiltInThemes.sunset.duplicate(named: "MyBrand")
        doc.themes.append(user)
        doc.cards[0].themeName = "mybrand"
        let resolved = doc.effectiveTheme(forCard: doc.cards[0].id)
        #expect(resolved.name == "MyBrand")
    }

    @Test("effectiveThemeOrigin reports which level supplied the theme")
    func effectiveThemeOriginReportsSource() {
        var doc = docWithThreeCardsTwoBackgrounds()
        doc.stack.themeName = "Sunset"
        doc.backgrounds[1].themeName = "Modern Dark"
        doc.cards[2].themeName = "Neon"

        let (_, originCard3) = doc.effectiveThemeOrigin(forCard: doc.cards[2].id)
        let (_, originCard1) = doc.effectiveThemeOrigin(forCard: doc.cards[0].id)
        let cardId3 = doc.cards[2].id
        let stackOrigin: ThemeOrigin = .stack
        #expect(originCard3 == .card(cardId3))
        #expect(originCard1 == stackOrigin)
    }

    @Test("Empty stack themeName resolves to System fallback")
    func emptyStackThemeNameFallsBackToSystem() {
        var doc = docWithThreeCardsTwoBackgrounds()
        doc.stack.themeName = ""   // not the canonical default
        let resolved = doc.effectiveTheme(forCard: doc.cards[0].id)
        #expect(resolved.name == "System")
    }

    // MARK: - Lookup

    @Test("theme(named:) returns user themes preferring document over built-in")
    func userThemeWinsOverBuiltInWithSameName() {
        var doc = HypeDocument.newDocument(name: "Test")
        // User defines their own "Sunset" — document wins.
        var fakeSunset = BuiltInThemes.modernDark.duplicate(named: "Sunset")
        fakeSunset.isBuiltIn = false
        doc.themes.append(fakeSunset)
        let resolved = doc.theme(named: "Sunset")
        #expect(resolved?.id == fakeSunset.id)
        #expect(resolved?.isBuiltIn == false)
    }

    @Test("theme(named:) returns nil for empty/whitespace input")
    func themeLookupRejectsEmpty() {
        let doc = HypeDocument.newDocument(name: "Test")
        #expect(doc.theme(named: "") == nil)
        #expect(doc.theme(named: "   ") == nil)
        #expect(doc.theme(named: nil) == nil)
    }

    @Test("allAvailableThemes lists built-ins first, then sorted user themes")
    func allAvailableOrdering() {
        var doc = HypeDocument.newDocument(name: "Test")
        let zebra = BuiltInThemes.sunset.duplicate(named: "Zebra")
        let alpha = BuiltInThemes.modernLight.duplicate(named: "Alpha")
        doc.themes = [zebra, alpha]
        let names = doc.allAvailableThemes.map(\.name)
        // First six should be the six built-ins.
        let builtInCount = BuiltInThemes.all.count
        let trailing = Array(names.suffix(2))
        #expect(names.count == builtInCount + 2)
        #expect(trailing == ["Alpha", "Zebra"])
    }

    // MARK: - Mutation: addTheme

    @Test("addTheme accepts a unique name and stamps modifiedAt")
    func addThemeSucceedsOnUniqueName() {
        var doc = HypeDocument.newDocument(name: "Test")
        let candidate = BuiltInThemes.sunset.duplicate(named: "MyTheme")
        let added = doc.addTheme(candidate)
        #expect(added != nil)
        #expect(doc.themes.count == 1)
        #expect(doc.themes[0].name == "MyTheme")
    }

    @Test("addTheme rejects collision with another user theme")
    func addThemeRejectsCollision() {
        var doc = HypeDocument.newDocument(name: "Test")
        _ = doc.addTheme(BuiltInThemes.sunset.duplicate(named: "MyTheme"))
        let again = doc.addTheme(BuiltInThemes.neon.duplicate(named: "MyTheme"))
        #expect(again == nil)
        #expect(doc.themes.count == 1)
    }

    @Test("addTheme rejects collision with built-in name")
    func addThemeRejectsBuiltInCollision() {
        var doc = HypeDocument.newDocument(name: "Test")
        let attempt = BuiltInThemes.sunset.duplicate(named: "Sunset")
        let added = doc.addTheme(attempt)
        #expect(added == nil)
        #expect(doc.themes.isEmpty)
    }

    // MARK: - Mutation: updateTheme

    @Test("updateTheme rejects edits to a built-in")
    func updateThemeRefusesBuiltIn() {
        var doc = HypeDocument.newDocument(name: "Test")
        let ok = doc.updateTheme(id: BuiltInThemes.sunset.id) { t in
            t.accent = .hex("#FF00FF")
        }
        #expect(ok == false)
    }

    @Test("updateTheme renames cascade to all references")
    func updateThemeCascadesRename() {
        var doc = HypeDocument.newDocument(name: "Test")
        let user = doc.addTheme(BuiltInThemes.sunset.duplicate(named: "Old"))!
        // Reference it at every scope.
        doc.stack.themeName = "Old"
        let bgId = doc.backgrounds[0].id
        doc.backgrounds[0].themeName = "Old"
        let cardId = doc.cards[0].id
        doc.cards[0].themeName = "Old"

        let ok = doc.updateTheme(id: user.id) { t in
            t.name = "New"
        }
        #expect(ok)
        #expect(doc.stack.themeName == "New")
        #expect(doc.backgrounds.first { $0.id == bgId }?.themeName == "New")
        #expect(doc.cards.first { $0.id == cardId }?.themeName == "New")
    }

    @Test("updateTheme rejects rename collision")
    func updateThemeRejectsRenameCollision() {
        var doc = HypeDocument.newDocument(name: "Test")
        let a = doc.addTheme(BuiltInThemes.sunset.duplicate(named: "A"))!
        _ = doc.addTheme(BuiltInThemes.neon.duplicate(named: "B"))
        let ok = doc.updateTheme(id: a.id) { t in
            t.name = "B"
        }
        #expect(ok == false)
        #expect(doc.themes.first { $0.id == a.id }?.name == "A")
    }

    @Test("updateTheme also rejects rename to a built-in name")
    func updateThemeRejectsRenameToBuiltIn() {
        var doc = HypeDocument.newDocument(name: "Test")
        let a = doc.addTheme(BuiltInThemes.sunset.duplicate(named: "A"))!
        let ok = doc.updateTheme(id: a.id) { t in
            t.name = "Sunset"
        }
        #expect(ok == false)
    }

    // MARK: - Mutation: deleteTheme

    @Test("deleteTheme refuses built-ins")
    func deleteThemeRefusesBuiltIn() {
        var doc = HypeDocument.newDocument(name: "Test")
        #expect(doc.deleteTheme(id: BuiltInThemes.sunset.id) == false)
    }

    @Test("deleteTheme clears card/background references and resets stack to fallback")
    func deleteThemeCascadeClears() {
        var doc = HypeDocument.newDocument(name: "Test")
        let user = doc.addTheme(BuiltInThemes.sunset.duplicate(named: "Doomed"))!
        doc.stack.themeName = "Doomed"
        doc.backgrounds[0].themeName = "Doomed"
        doc.cards[0].themeName = "Doomed"

        let ok = doc.deleteTheme(id: user.id)
        #expect(ok)
        #expect(doc.themes.isEmpty)
        // Stack reset to fallback name; cards/backgrounds went nil.
        #expect(doc.stack.themeName == BuiltInThemes.fallbackName)
        #expect(doc.backgrounds[0].themeName == nil)
        #expect(doc.cards[0].themeName == nil)
    }

    // MARK: - Mutation: duplicateTheme

    @Test("duplicateTheme produces 'X Copy', then 'X Copy 2', etc.")
    func duplicateThemeUniqueNames() {
        var doc = HypeDocument.newDocument(name: "Test")
        let first = doc.duplicateTheme(named: "Sunset")
        let second = doc.duplicateTheme(named: "Sunset")
        let third = doc.duplicateTheme(named: "Sunset")
        #expect(first?.name == "Sunset Copy")
        #expect(second?.name == "Sunset Copy 2")
        #expect(third?.name == "Sunset Copy 3")
        #expect(first?.basedOn == "Sunset")
    }

    @Test("duplicateTheme returns nil for unknown source")
    func duplicateThemeUnknownSource() {
        var doc = HypeDocument.newDocument(name: "Test")
        #expect(doc.duplicateTheme(named: "DoesNotExist") == nil)
    }

    // MARK: - Usage counting

    @Test("usageCount counts cards/backgrounds/stack defaults")
    func usageCountAggregates() {
        var doc = HypeDocument.newDocument(name: "Test")
        // Add a second card sharing the same background.
        let stackId = doc.stack.id
        let bgId = doc.backgrounds[0].id
        doc.cards.append(Card(stackId: stackId, backgroundId: bgId,
                              name: "Card 2", sortKey: "a1"))
        let user = doc.addTheme(BuiltInThemes.sunset.duplicate(named: "Used"))!
        doc.stack.themeName = user.name
        doc.cards[0].themeName = user.name
        doc.cards[1].themeName = user.name
        doc.backgrounds[0].themeName = user.name

        let usage = doc.usageCount(themeName: "Used")
        #expect(usage.cards == 2)
        #expect(usage.backgrounds == 1)
        #expect(usage.isStackDefault == true)
        #expect(usage.total == 4)
        #expect(usage.isInUse)
    }
}

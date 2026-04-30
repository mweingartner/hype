import Testing
import Foundation
@testable import HypeCore

@Suite("Theme AI tools — list/create/duplicate/delete/set_theme_property + property accessors")
struct ThemeAIToolsTests {

    // MARK: list_themes

    @Test("list_themes lists every built-in plus user themes")
    func listThemesShowsAll() async {
        var doc = HypeDocument.newDocument(name: "Test")
        _ = doc.addTheme(BuiltInThemes.modernDark.duplicate(named: "MyDark"))

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "list_themes",
            arguments: [:],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        // Built-ins first, then user.
        for builtIn in BuiltInThemes.all {
            #expect(result.contains(builtIn.name),
                    "list_themes missing built-in '\(builtIn.name)' — got: \(result)")
        }
        #expect(result.contains("MyDark"),
                "list_themes missing user theme 'MyDark'")
        #expect(result.contains("based on Modern Dark"),
                "list_themes should show provenance for user themes")
    }

    // MARK: create_theme

    @Test("create_theme clones a built-in into a new user theme")
    func createThemeFromBuiltIn() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "create_theme",
            arguments: [
                "base_theme_name": "Sunset",
                "new_name": "MyBrand",
            ],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(!result.lowercased().contains("error"))
        #expect(result.lowercased().contains("created"))
        #expect(doc.themes.count == 1)
        let new = doc.themes[0]
        #expect(new.name == "MyBrand")
        #expect(new.basedOn == "Sunset")
        #expect(new.isBuiltIn == false)
        // Color values copied from source.
        #expect(new.cardBackground == BuiltInThemes.sunset.cardBackground)
    }

    @Test("create_theme applies overrides_json on top of the clone")
    func createThemeWithOverrides() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let executor = HypeToolExecutor()
        let overrides = """
        {"accent": "#FF00FF", "cornerRadiusMedium": "20", "defaultFontFamily": "Times New Roman"}
        """
        _ = await executor.execute(
            toolName: "create_theme",
            arguments: [
                "base_theme_name": "Modern Light",
                "new_name": "Custom",
                "overrides_json": overrides,
            ],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        let new = doc.themes.first { $0.name == "Custom" }
        #expect(new != nil)
        #expect(new?.accent == .hex("#FF00FF"))
        #expect(new?.cornerRadiusMedium == 20)
        #expect(new?.defaultFontFamily == "Times New Roman")
    }

    @Test("create_theme rejects collision with built-in name")
    func createThemeRejectsBuiltInCollision() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "create_theme",
            arguments: [
                "base_theme_name": "Sunset",
                "new_name": "Modern Light",   // collision with built-in
            ],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result.lowercased().contains("already exists"))
        #expect(doc.themes.isEmpty)
    }

    // MARK: duplicate_theme

    @Test("duplicate_theme defaults the name to '<source> Copy'")
    func duplicateThemeDefaultName() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "duplicate_theme",
            arguments: ["source_theme_name": "Sunset"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(doc.themes.contains { $0.name == "Sunset Copy" })
    }

    // MARK: delete_theme

    @Test("delete_theme refuses to delete a built-in")
    func deleteBuiltInRefused() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "delete_theme",
            arguments: ["theme_name": "System"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result.lowercased().contains("built-in"))
    }

    @Test("delete_theme cascades reference cleanup")
    func deleteThemeCascadeClears() async {
        var doc = HypeDocument.newDocument(name: "Test")
        _ = doc.addTheme(BuiltInThemes.sunset.duplicate(named: "Doomed"))
        doc.stack.themeName = "Doomed"
        doc.cards[0].themeName = "Doomed"

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "delete_theme",
            arguments: ["theme_name": "Doomed"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(doc.themes.isEmpty)
        #expect(doc.cards[0].themeName == nil)
        #expect(doc.stack.themeName == BuiltInThemes.fallbackName)
    }

    // MARK: set_theme_property

    @Test("set_theme_property edits a single field on a user theme")
    func setThemePropertyOnUser() async {
        var doc = HypeDocument.newDocument(name: "Test")
        _ = doc.addTheme(BuiltInThemes.modernLight.duplicate(named: "Mine"))

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_theme_property",
            arguments: [
                "theme_name": "Mine",
                "property": "accent",
                "value": "#00FF00",
            ],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(doc.themes.first?.accent == .hex("#00FF00"))
    }

    @Test("set_theme_property refuses to edit a built-in")
    func setThemePropertyRefusesBuiltIn() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_theme_property",
            arguments: [
                "theme_name": "Sunset",
                "property": "accent",
                "value": "#00FF00",
            ],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result.lowercased().contains("built-in"))
    }

    // MARK: get_stack_property + theme on set_card_property

    @Test("get_stack_property returns theme name")
    func getStackPropertyTheme() async {
        var doc = HypeDocument.newDocument(name: "Test")
        doc.stack.themeName = "Modern Dark"
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "theme"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        // Result format may include label like "theme of stack: Modern Dark".
        #expect(result.contains("Modern Dark"),
                "expected 'Modern Dark' in result, got: \(result)")
    }

    @Test("set_card_property theme writes to the card's themeName")
    func setCardPropertyTheme() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_card_property",
            arguments: ["property": "theme", "value": "Neon"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(doc.cards[0].themeName == "Neon")
    }

    @Test("set_card_property theme with empty value clears the override")
    func setCardPropertyThemeEmptyClears() async {
        var doc = HypeDocument.newDocument(name: "Test")
        doc.cards[0].themeName = "Sunset"
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_card_property",
            arguments: ["property": "theme", "value": ""],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(doc.cards[0].themeName == nil)
    }

    @Test("get_card_property effectiveTheme walks the cascade")
    func getCardPropertyEffectiveTheme() async {
        var doc = HypeDocument.newDocument(name: "Test")
        doc.stack.themeName = "Sunset"          // bottom of cascade
        doc.backgrounds[0].themeName = "Modern Dark"  // overrides stack
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_card_property",
            arguments: ["property": "effectiveTheme"],
            document: &doc,
            currentCardId: doc.cards[0].id
        )
        #expect(result.contains("Modern Dark"),
                "effectiveTheme should resolve through background to 'Modern Dark', got: \(result)")
    }
}

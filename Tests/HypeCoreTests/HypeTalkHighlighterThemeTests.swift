import Testing
import Foundation
@testable import HypeCore

@Suite("HypeTalk highlighter — token classification + theme color mapping")
struct HypeTalkHighlighterThemeTests {

    @Test("highlighter classifies keywords / commands / strings / comments")
    func highlighterCategoriesTokens() {
        let h = HypeTalkHighlighter()
        let source = """
        on mouseUp
          -- this is a comment
          put "hello" into score
          if score > 10 then go next
        end mouseUp
        """
        let tokens = h.highlight(source)

        // Should produce many tokens — at minimum: 'on', 'mouseUp',
        // comment, 'put', "hello" (string), 'into', identifier,
        // 'if', identifier, '>', number, 'then', 'go', 'next',
        // 'end', 'mouseUp'.
        #expect(tokens.count > 8, "expected many tokens, got \(tokens.count)")

        // Pluck out specific categories
        var sawKeyword = false
        var sawCommand = false
        var sawComment = false
        var sawString = false
        var sawNumber = false
        for t in tokens {
            switch t.category {
            case .keyword:       sawKeyword = true
            case .command:       sawCommand = true
            case .comment:       sawComment = true
            case .stringLiteral: sawString = true
            case .numberLiteral: sawNumber = true
            default:             break
            }
        }
        #expect(sawKeyword, "expected at least one keyword token (on/end/if/then)")
        #expect(sawCommand, "expected at least one command token (put/go)")
        #expect(sawComment, "expected the -- comment to be tokenized")
        #expect(sawString,  "expected the \"hello\" string literal")
        #expect(sawNumber,  "expected the 10 numeric literal")
    }

    @Test("HypeScriptTheme defaults provide a sensible palette")
    func scriptThemeDefaultsAreSensible() {
        let light = HypeScriptTheme.defaultLight
        let dark = HypeScriptTheme.defaultDark

        // Every category has a color — none are accidentally empty.
        for theme in [light, dark] {
            #expect(theme.background.rawDescription.isEmpty == false)
            #expect(theme.foreground.rawDescription.isEmpty == false)
            #expect(theme.keyword.rawDescription.isEmpty == false)
            #expect(theme.command.rawDescription.isEmpty == false)
            #expect(theme.stringLiteral.rawDescription.isEmpty == false)
            #expect(theme.numberLiteral.rawDescription.isEmpty == false)
            #expect(theme.comment.rawDescription.isEmpty == false)
            #expect(theme.fontSize > 0)
        }

        // Light + dark are visually distinct — at least the
        // backgrounds differ.
        #expect(light.background != dark.background,
                "light and dark script themes should have different backgrounds")
    }

    @Test("highlighter recognizes Phase 1+2 framework control object types")
    func highlighterRecognizesFrameworkControls() {
        let h = HypeTalkHighlighter()
        // One per kind so we can verify the .objectType category fires.
        let source = """
        set the selectedDate of calendar "due" to "2026-12-25"
        set the currentPage of pdf "manual" to 5
        set the maplocation of map "store" to "97537"
        set the color of colorWell "fill" to "#FF0000"
        set the value of stepper "qty" to 10
        set the value of slider "vol" to 0.5
        set the selectedSegment of segmented "tabs" to 1
        set the recording of recorder "memo" to true
        set the playing of recorder "memo" to true
        set the modelURL of scene3d "model" to "/path/to.usdz"
        play chart "graph"
        """
        let tokens = h.highlight(source)

        // Pluck the lowercased word for every .objectType token.
        let kinds = Set(tokens.compactMap { tok -> String? in
            guard tok.category == .objectType else { return nil }
            return String(source[tok.range]).lowercased()
        })

        let expected = [
            "calendar", "pdf", "map", "colorwell",
            "stepper", "slider", "segmented",
            "recorder", "scene3d", "chart",
            // toggle / link / menu / searchfield removed in dedup —
            // they're now button styles (.switch/.link/.popup) or
            // a field style (.search), referenced via the existing
            // `button "X"` / `field "X"` kind words.
        ]
        for kind in expected {
            #expect(kinds.contains(kind),
                    "highlighter did not classify '\(kind)' as .objectType — got kinds: \(kinds.sorted())")
        }
    }

    @Test("Each built-in theme carries a script theme with all fields populated")
    func everyBuiltInHasCompleteScriptTheme() {
        for theme in BuiltInThemes.all {
            let st = theme.scriptTheme
            #expect(st.fontSize > 0,
                    "\(theme.name)'s script theme must have a positive fontSize")
            // No accidentally-empty colors that would render
            // invisible text.
            #expect(st.foreground.rawDescription.isEmpty == false,
                    "\(theme.name) missing scriptTheme.foreground")
            #expect(st.background.rawDescription.isEmpty == false,
                    "\(theme.name) missing scriptTheme.background")
            #expect(st.keyword.rawDescription.isEmpty == false,
                    "\(theme.name) missing scriptTheme.keyword")
        }
    }
}

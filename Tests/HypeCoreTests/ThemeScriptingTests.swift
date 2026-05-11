import Testing
import Foundation
@testable import HypeCore

@Suite("Theme scripting")
struct ThemeScriptingTests {

    private final class CapturingDialogProvider: DialogProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var capturedPrompts: [String] = []

        var prompts: [String] {
            lock.withLock { capturedPrompts }
        }

        func showAnswer(prompt: String) -> String {
            lock.withLock { capturedPrompts.append(prompt) }
            return "OK"
        }

        func showAsk(prompt: String) -> String {
            ""
        }
    }

    private func parseHandler(_ source: String) throws -> Handler {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        return try #require(script.handlers.first)
    }

    @Test("answer the theme of this card reads the current card theme")
    func answerThemeOfThisCard() async throws {
        var doc = HypeDocument.newDocument(name: "Theme Script")
        let cardId = doc.cards[0].id
        doc.cards[0].themeName = "Neon"
        let button = Part(partType: .button, cardId: cardId, name: "theme_button")
        doc.addPart(button)
        let dialog = CapturingDialogProvider()
        let handler = try parseHandler("""
        on mouseUp
          answer the theme of this card
          pass mouseUp
        end mouseUp
        """)
        let context = ExecutionContext(
            targetId: button.id,
            currentCardId: cardId,
            document: doc,
            dialogProvider: dialog
        )

        _ = await Interpreter().executeAsync(handler: handler, params: [], context: context)

        #expect(dialog.prompts == ["Neon"])
    }

    @Test("answer the theme of this background/stack reads current scope themes")
    func answerThemeOfCurrentBackgroundAndStack() async throws {
        var doc = HypeDocument.newDocument(name: "Theme Script")
        let cardId = doc.cards[0].id
        doc.backgrounds[0].themeName = "Modern Dark"
        doc.stack.themeName = "Sunset"
        let button = Part(partType: .button, cardId: cardId, name: "theme_button")
        doc.addPart(button)
        let dialog = CapturingDialogProvider()
        let handler = try parseHandler("""
        on mouseUp
          answer the theme of this background
          answer the theme of this stack
        end mouseUp
        """)
        let context = ExecutionContext(
            targetId: button.id,
            currentCardId: cardId,
            document: doc,
            dialogProvider: dialog
        )

        _ = await Interpreter().executeAsync(handler: handler, params: [], context: context)

        #expect(dialog.prompts == ["Modern Dark", "Sunset"])
    }

    @Test("set the theme of this card/background/stack mutates the right scope")
    func setThemeOfCurrentScopes() async throws {
        var doc = HypeDocument.newDocument(name: "Theme Script")
        let cardId = doc.cards[0].id
        let backgroundId = doc.cards[0].backgroundId
        let button = Part(partType: .button, cardId: cardId, name: "theme_button")
        doc.addPart(button)
        let handler = try parseHandler("""
        on mouseUp
          set the theme of this card to "Neon"
          set the theme of this background to "Modern Dark"
          set the theme of this stack to "Sunset"
        end mouseUp
        """)
        let context = ExecutionContext(targetId: button.id, currentCardId: cardId, document: doc)

        let result = await Interpreter().executeAsync(handler: handler, params: [], context: context)
        let modified = try #require(result.modifiedDocument)

        #expect(modified.cards.first { $0.id == cardId }?.themeName == "Neon")
        #expect(modified.backgrounds.first { $0.id == backgroundId }?.themeName == "Modern Dark")
        #expect(modified.stack.themeName == "Sunset")
    }

    @Test("current card aliases read effective theme through cascade")
    func currentCardEffectiveThemeAlias() async throws {
        var doc = HypeDocument.newDocument(name: "Theme Script")
        let cardId = doc.cards[0].id
        let backgroundId = doc.cards[0].backgroundId
        doc.backgrounds[0].themeName = "Modern Dark"
        var button = Part(partType: .button, cardId: cardId, name: "theme_button")
        button.script = """
        on mouseUp
          put the effectiveTheme of current card into field "theme_output"
        end mouseUp
        """
        doc.addPart(button)
        doc.addPart(Part(partType: .field, cardId: cardId, name: "theme_output"))
        let dispatcher = MessageDispatcher()
        let targetId = button.id
        let dispatchDocument = doc

        let result = await runOnLargeStack {
            dispatcher.dispatch(
                message: "mouseUp",
                params: [],
                targetId: targetId,
                document: dispatchDocument,
                currentCardId: cardId
            )
        }
        let modified = try #require(result.modifiedDocument)

        #expect(modified.backgrounds.first { $0.id == backgroundId }?.themeName == "Modern Dark")
        #expect(modified.parts.first { $0.name == "theme_output" }?.textContent == "Modern Dark")
    }
}

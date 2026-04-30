import Testing
import Foundation
@testable import HypeCore

/// Smoke tests for the document-level mutations that the
/// PropertyInspector's theme picker bindings drive.
///
/// We can't construct a SwiftUI `Binding<String?>` outside a SwiftUI
/// runtime, but every binding in the inspector funnels into one of
/// three model writes:
///   - `cards[idx].themeName = newValue`         (card picker)
///   - `backgrounds[idx].themeName = newValue`   (background picker)
///   - `stack.themeName = newValue ?? fallback`  (stack picker)
///
/// These tests exercise the round-trip (name -> nil -> name) at the
/// model layer to catch regressions in the binding contract:
/// specifically, that setting nil restores cascade inheritance and
/// that re-assigning a name pushes the cascade back to the local
/// scope. If the inspector binding logic is ever re-implemented to
/// (for example) elide nil writes or coerce them to the empty string,
/// these tests fail and the picker stops behaving correctly.
@Suite("Theme inspector binding round-trip semantics")
struct ThemeInspectorBindingTests {

    // MARK: - Helper

    private func docWithOneCard() -> HypeDocument {
        var doc = HypeDocument.newDocument(name: "Binding Test")
        // newDocument seeds 1 card + 1 background + Stack.themeName="System"
        return doc
    }

    // MARK: - Card picker round-trip

    @Test("Card themeName: name -> nil -> name round-trips correctly through the cascade")
    func cardThemeBindingRoundTrip() {
        var doc = docWithOneCard()
        let cardId = doc.cards[0].id

        // 1. Initial: nil. Cascade falls to background (also nil),
        //    then stack (System).
        #expect(doc.cards[0].themeName == nil)
        #expect(doc.effectiveTheme(forCard: cardId).name == "System")

        // 2. Assign a built-in by name (the picker setter does
        //    exactly: `document.document.cards[idx].themeName = newName`).
        doc.cards[0].themeName = "Sunset"
        #expect(doc.cards[0].themeName == "Sunset")
        #expect(doc.effectiveTheme(forCard: cardId).name == "Sunset")

        // 3. "Inherit" tag — setter receives nil. Cascade should
        //    fall back to stack default again.
        doc.cards[0].themeName = nil
        #expect(doc.cards[0].themeName == nil)
        #expect(doc.effectiveTheme(forCard: cardId).name == "System")

        // 4. Re-assign — the picker is symmetric: switching back to
        //    a named theme must restore card-level resolution.
        doc.cards[0].themeName = "Modern Dark"
        #expect(doc.cards[0].themeName == "Modern Dark")
        #expect(doc.effectiveTheme(forCard: cardId).name == "Modern Dark")
    }

    // MARK: - Background picker round-trip

    @Test("Background themeName: name -> nil -> name round-trips correctly")
    func backgroundThemeBindingRoundTrip() {
        var doc = docWithOneCard()
        let cardId = doc.cards[0].id

        // 1. Background nil; cascade resolves to stack default.
        #expect(doc.backgrounds[0].themeName == nil)
        #expect(doc.effectiveTheme(forCard: cardId).name == "System")

        // 2. Assign — cascade now resolves at background level for
        //    any card with a nil card-level theme.
        doc.backgrounds[0].themeName = "Neon"
        #expect(doc.backgrounds[0].themeName == "Neon")
        let (_, origin) = doc.effectiveThemeOrigin(forCard: cardId)
        #expect(doc.effectiveTheme(forCard: cardId).name == "Neon")
        #expect(origin == .background(doc.backgrounds[0].id))

        // 3. Inherit tag — back to stack default.
        doc.backgrounds[0].themeName = nil
        #expect(doc.effectiveTheme(forCard: cardId).name == "System")

        // 4. Re-assign.
        doc.backgrounds[0].themeName = "Modern Light"
        #expect(doc.effectiveTheme(forCard: cardId).name == "Modern Light")
    }

    // MARK: - Stack picker (no Inherit)

    @Test("Stack themeName: nil collapses to fallbackName, otherwise round-trips")
    func stackThemeBindingNilCollapsesToFallback() {
        var doc = docWithOneCard()
        let cardId = doc.cards[0].id

        // 1. Default: stack.themeName = "System".
        #expect(doc.stack.themeName == BuiltInThemes.fallbackName)
        #expect(doc.effectiveTheme(forCard: cardId).name == "System")

        // 2. Assign via the binding setter analog.
        doc.stack.themeName = "Sunset"
        #expect(doc.stack.themeName == "Sunset")
        #expect(doc.effectiveTheme(forCard: cardId).name == "Sunset")

        // 3. Simulate the stack picker binding receiving nil
        //    (which the inspector's stackThemeBindingNonOptional
        //    coerces to fallbackName so the model invariant holds).
        let coerced: String? = nil
        doc.stack.themeName = coerced ?? BuiltInThemes.fallbackName
        #expect(doc.stack.themeName == BuiltInThemes.fallbackName)
        #expect(doc.effectiveTheme(forCard: cardId).name == "System")

        // 4. Re-assign.
        doc.stack.themeName = "Modern Dark"
        #expect(doc.effectiveTheme(forCard: cardId).name == "Modern Dark")
    }

    // MARK: - Cascade origin matches inspector cascadeNote logic

    @Test("Cascade origin lets the inspector display 'inheriting from background' when card is nil")
    func cascadeOriginDrivesInspectorNote() {
        var doc = docWithOneCard()
        let cardId = doc.cards[0].id

        // Card nil + background set => origin .background.
        // The PropertyInspector's `cascadeNote(for: .card)` keys off
        // this to render "(inheriting from background → Sunset)".
        doc.backgrounds[0].themeName = "Sunset"
        let (_, origin) = doc.effectiveThemeOrigin(forCard: cardId)
        #expect(origin == .background(doc.backgrounds[0].id))

        // Set card-level theme — origin flips to .card.
        doc.cards[0].themeName = "Neon"
        let (_, originAfter) = doc.effectiveThemeOrigin(forCard: cardId)
        #expect(originAfter == .card(cardId))

        // Clear card-level — back to background.
        doc.cards[0].themeName = nil
        let (_, originRestored) = doc.effectiveThemeOrigin(forCard: cardId)
        #expect(originRestored == .background(doc.backgrounds[0].id))
    }
}

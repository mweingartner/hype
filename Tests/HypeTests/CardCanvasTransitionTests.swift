import AppKit
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("Card canvas transitions")
struct CardCanvasTransitionTests {
    @Test("transition duration is clamped to a safe range")
    func transitionDurationIsClamped() {
        #expect(CardCanvasNSView.normalizedTransitionDuration(nil) == CardCanvasNSView.defaultTransitionDuration)
        #expect(CardCanvasNSView.normalizedTransitionDuration(-2) == 0)
        #expect(CardCanvasNSView.normalizedTransitionDuration(999) == CardCanvasNSView.maximumTransitionDuration)
    }

    @Test("zero-sized canvas declines transition so caller can navigate immediately")
    func zeroSizedCanvasDeclinesTransition() {
        var doc = HypeDocument.newDocument(name: "Transition")
        let first = doc.sortedCards[0]
        let second = doc.addCard()

        let view = CardCanvasNSView(frame: .zero)
        view.document = doc
        view.currentCardId = first.id

        let started = view.performCardTransition(to: second.id, effect: .dissolve, duration: 0.1)

        #expect(started == false)
        #expect(view.isTransitioning == false)
    }

    @Test("valid canvas starts SpriteKit transition")
    func validCanvasStartsTransition() {
        var doc = HypeDocument.newDocument(name: "Transition")
        let first = doc.sortedCards[0]
        let second = doc.addCard()

        let view = CardCanvasNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        view.document = doc
        view.currentCardId = first.id

        let started = view.performCardTransition(to: second.id, effect: .flipHorizontal, duration: 0)

        #expect(started == true)
        #expect(view.isTransitioning == true)
    }
}

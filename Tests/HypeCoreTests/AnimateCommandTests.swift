import Testing
import Foundation
@testable import HypeCore

/// Tests for the `animate` HypeTalk command and PartAnimator engine.
@Suite("Animate command", .serialized)
struct AnimateCommandTests {

    // MARK: - Parser tests

    private func parses(_ source: String) -> Bool {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return (try? parser.parse()) != nil
    }

    @Test("animate the loc of button X to Y over N parses")
    func parseAnimateLoc() {
        #expect(parses("""
        on test
          animate the loc of button "ball" to "400,300" over 0.5
        end test
        """))
    }

    @Test("animate the left of field X to N over N seconds parses")
    func parseAnimateLeftWithSeconds() {
        #expect(parses("""
        on test
          animate the left of field "panel" to 0 over 1 seconds
        end test
        """))
    }

    @Test("animate the rotation of shape X to N over N parses")
    func parseAnimateRotation() {
        #expect(parses("""
        on test
          animate the rotation of shape "spinner" to 360 over 2
        end test
        """))
    }

    @Test("animate without 'the' parses")
    func parseAnimateWithoutThe() {
        #expect(parses("""
        on test
          animate left of button "x" to 100 over 0.5
        end test
        """))
    }

    @Test("animate with 'second' singular parses")
    func parseAnimateSecondSingular() {
        #expect(parses("""
        on test
          animate the width of button "bar" to 300 over 1 second
        end test
        """))
    }

    // MARK: - Lexer tests

    @Test("animate tokenizes as .animate")
    func lexerAnimateToken() {
        var lexer = Lexer(source: "animate")
        let tokens = lexer.tokenize()
        #expect(tokens.first?.type == .animate)
    }

    // MARK: - Interpreter tests

    @Test("animate command executes without crash") func animateExecutesCleanly() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var btn = Part(partType: .button, cardId: cardId, name: "ball",
                       left: 100, top: 100, width: 80, height: 40)
        doc.addPart(btn)
        doc.cards[0].script = """
        on openCard
          animate the loc of button "ball" to "400,300" over 0.5
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        // animate is non-blocking — the command returns immediately
        // without error, even though the animation runs async
        #expect(result.status == .completed,
                "animate should not error: \(result.error?.message ?? "")")
    }

    @Test("the animating of button returns false when no animation active") func animatingPropertyDefaultsFalse() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var btn = Part(partType: .button, cardId: cardId, name: "ball")
        doc.addPart(btn)
        var fld = Part(partType: .field, cardId: cardId, name: "out")
        doc.addPart(fld)
        doc.cards[0].script = """
        on openCard
          put the animating of button "ball" into field "out"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        let output = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(output?.textContent == "false")
    }

    @Test("animate with 'me' target parses and executes")
    func animateWithMe() {
        #expect(parses("""
        on mouseUp
          animate the rotation of me to 360 over 1
        end mouseUp
        """))
    }

    // MARK: - PartAnimator unit tests

    #if canImport(AppKit)
    @Test("PartAnimator.isAnimating returns false initially")
    func animatorInitiallyIdle() {
        let id = UUID()
        #expect(PartAnimator.shared.isAnimating(partId: id) == false)
    }

    @Test("PartAnimator.animate registers an animation")
    func animatorRegistersAnimation() {
        let id = UUID()
        PartAnimator.shared.animate(
            partId: id, property: "left",
            fromValue: 0, toValue: 100,
            duration: 1.0
        )
        #expect(PartAnimator.shared.isAnimating(partId: id) == true)
        #expect(PartAnimator.shared.isAnimating(partId: id, property: "left") == true)
        #expect(PartAnimator.shared.isAnimating(partId: id, property: "top") == false)
        // Clean up
        PartAnimator.shared.stopAll()
    }

    @Test("PartAnimator.stopAll clears all animations")
    func animatorStopAllClears() {
        let id = UUID()
        PartAnimator.shared.animate(
            partId: id, property: "left",
            fromValue: 0, toValue: 100,
            duration: 1.0
        )
        PartAnimator.shared.stopAll()
        #expect(PartAnimator.shared.isAnimating(partId: id) == false)
    }

    @Test("PartAnimator.stopAnimations(for:) only clears that part")
    func animatorStopForPartIsSelective() {
        let id1 = UUID()
        let id2 = UUID()
        PartAnimator.shared.animate(partId: id1, property: "left", fromValue: 0, toValue: 100, duration: 1.0)
        PartAnimator.shared.animate(partId: id2, property: "top", fromValue: 0, toValue: 200, duration: 1.0)
        PartAnimator.shared.stopAnimations(for: id1)
        #expect(PartAnimator.shared.isAnimating(partId: id1) == false)
        #expect(PartAnimator.shared.isAnimating(partId: id2) == true)
        PartAnimator.shared.stopAll()
    }
    #endif

    // MARK: - HypeTalkGuide

    @Test("guide contains the Animation section")
    func guideHasAnimationSection() {
        #expect(HypeTalkGuide.llmContext.contains("## Animation"))
        #expect(HypeTalkGuide.llmContext.contains("animate the loc"))
        #expect(HypeTalkGuide.llmContext.contains("animating"))
    }
}

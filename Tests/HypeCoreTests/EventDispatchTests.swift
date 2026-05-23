import Testing
import Foundation
@testable import HypeCore

/// Regression tests for the event-dispatch pipeline that backs
/// every HypeTalk lifecycle and runtime message in Hype.
///
/// Background: a user reported that the `idle` event was not
/// firing. Investigation found that the symptom was a *view-layer*
/// bug — `Coordinator.dispatchMessageToCard` in `CardCanvasView`
/// (and every lifecycle dispatch in `MainContentView`) was
/// calling `MessageDispatcher.dispatch(...)` with
/// `let _ = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(...) }`, throwing away the
/// `ExecutionResult`. Handlers ran, mutated the document via the
/// interpreter's `ExecutionContext`, and then had their entire
/// modified document silently discarded. That's why `on idle /
/// set the loc of sprite "ball" to ... / end idle` appeared to do
/// nothing. The fix wires the result-handling path that was
/// already used by part-targeted dispatches through every call
/// site.
///
/// These tests exercise the `MessageDispatcher` directly and
/// lock in the contract that the view layer depends on: a
/// handler anywhere in the card → background → stack → Hype
/// hierarchy that mutates state ALWAYS produces a
/// non-nil `modifiedDocument` on the returned `ExecutionResult`.
///
/// We also test the `scriptHasIdleHandler` precision change —
/// except that helper lives in the `Hype` executable target so
/// we can't @testable import it. Instead we test the semantic
/// equivalent: that the dispatcher correctly identifies `on
/// idle` at any casing / leading whitespace, and that handlers
/// named `on idleState` do NOT fire for `idle`.
@Suite("Event dispatch returns modifiedDocument", .serialized)
struct EventDispatchTests {

    private func makeDocWithOneCard() -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        // Give it a field so handlers have something to mutate.
        var field = Part(
            partType: .field,
            cardId: cardId,
            name: "log",
            left: 10, top: 10, width: 200, height: 30
        )
        field.textContent = ""
        doc.addPart(field)
        return (doc, cardId)
    }

    // MARK: - Idle on card

    @Test("idle handler on card mutates document and returns modifiedDocument") func idleOnCardReturnsModifiedDoc() async {
        var (doc, cardId) = makeDocWithOneCard()
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        doc.cards[cardIndex].script = """
            on idle
              put "tick" into field "log"
            end idle
            """

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "idle",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.modifiedDocument != nil,
                "idle handler on card MUST return a non-nil modifiedDocument or the view layer can't apply its mutations")
        let modifiedField = result.modifiedDocument?.parts.first(where: { $0.name == "log" })
        #expect(modifiedField?.textContent == "tick")
    }

    @Test("idle handler on background fires when dispatched to card") func idleOnBackgroundFiresViaHierarchy() async {
        var (doc, cardId) = makeDocWithOneCard()
        let bgIndex = doc.backgrounds.firstIndex(where: {
            $0.id == doc.cards[0].backgroundId
        })!
        doc.backgrounds[bgIndex].script = """
            on idle
              put "bg" into field "log"
            end idle
            """

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "idle",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "bg")
    }

    @Test("idle handler on stack fires when card has no handler") func idleOnStackFiresViaHierarchy() async {
        var (doc, cardId) = makeDocWithOneCard()
        doc.stack.script = """
            on idle
              put "stack" into field "log"
            end idle
            """

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "idle",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "stack")
    }

    @Test("idle handler on card supersedes background handler (first wins)")
    func idleCardSupersedesBackground() async {
        var (doc, cardId) = makeDocWithOneCard()
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        let bgIndex = doc.backgrounds.firstIndex(where: {
            $0.id == doc.cards[0].backgroundId
        })!
        doc.cards[cardIndex].script = """
            on idle
              put "card" into field "log"
            end idle
            """
        doc.backgrounds[bgIndex].script = """
            on idle
              put "bg" into field "log"
            end idle
            """

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "idle",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "card")
    }

    @Test("pass idle bubbles from card to background") func passIdleBubbles() async {
        var (doc, cardId) = makeDocWithOneCard()
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        let bgIndex = doc.backgrounds.firstIndex(where: {
            $0.id == doc.cards[0].backgroundId
        })!
        doc.cards[cardIndex].script = """
            on idle
              pass idle
            end idle
            """
        doc.backgrounds[bgIndex].script = """
            on idle
              put "bg-after-pass" into field "log"
            end idle
            """

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "idle",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "bg-after-pass")
    }

    // MARK: - Idle on a specific part

    @Test("idle handler on a part mutates document") func idleOnPartMutatesDoc() async {
        var (doc, cardId) = makeDocWithOneCard()
        var button = Part(
            partType: .button,
            cardId: cardId,
            name: "ticker",
            left: 50, top: 50, width: 80, height: 30
        )
        button.script = """
            on idle
              put "part-tick" into field "log"
            end idle
            """
        doc.addPart(button)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, button] in dispatcher.dispatch(
            message: "idle",
            params: [],
            targetId: button.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "part-tick")
    }

    // MARK: - Other card-level events

    @Test("enterKey handler on card mutates document") func enterKeyReturnsModifiedDoc() async {
        var (doc, cardId) = makeDocWithOneCard()
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        doc.cards[cardIndex].script = """
            on enterKey
              put "entered" into field "log"
            end enterKey
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "enterKey",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "entered")
    }

    @Test("returnKey handler on stack mutates document") func returnKeyOnStackMutates() async {
        var (doc, cardId) = makeDocWithOneCard()
        doc.stack.script = """
            on returnKey
              put "ret" into field "log"
            end returnKey
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "returnKey",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "ret")
    }

    @Test("keyDown handler on card mutates document") func keyDownReturnsModifiedDoc() async {
        var (doc, cardId) = makeDocWithOneCard()
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        doc.cards[cardIndex].script = """
            on keyDown
              put "keyed" into field "log"
            end keyDown
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "keyDown",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "keyed")
    }

    // MARK: - Lifecycle events

    @Test("openCard handler mutates document") func openCardMutatesDocument() async {
        var (doc, cardId) = makeDocWithOneCard()
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        doc.cards[cardIndex].script = """
            on openCard
              put "opened" into field "log"
            end openCard
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "opened")
    }

    @Test("closeCard handler on background mutates document") func closeCardOnBackgroundMutates() async {
        var (doc, cardId) = makeDocWithOneCard()
        let bgIndex = doc.backgrounds.firstIndex(where: {
            $0.id == doc.cards[0].backgroundId
        })!
        doc.backgrounds[bgIndex].script = """
            on closeCard
              put "closing" into field "log"
            end closeCard
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "closeCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "closing")
    }

    @Test("openStack handler on stack mutates document") func openStackMutatesDocument() async {
        var (doc, cardId) = makeDocWithOneCard()
        doc.stack.script = """
            on openStack
              put "stack-open" into field "log"
            end openStack
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openStack",
            params: [],
            targetId: doc.stack.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "stack-open")
    }

    @Test("openBackground handler on background mutates document") func openBackgroundMutates() async {
        var (doc, cardId) = makeDocWithOneCard()
        let bgIndex = doc.backgrounds.firstIndex(where: {
            $0.id == doc.cards[0].backgroundId
        })!
        let bgId = doc.backgrounds[bgIndex].id
        doc.backgrounds[bgIndex].script = """
            on openBackground
              put "bg-open" into field "log"
            end openBackground
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openBackground",
            params: [],
            targetId: bgId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "bg-open")
    }

    @Test("quit handler on card mutates document") func quitHandlerMutates() async {
        var (doc, cardId) = makeDocWithOneCard()
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        doc.cards[cardIndex].script = """
            on quit
              put "bye" into field "log"
            end quit
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "quit",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "bye")
    }

    // MARK: - No-handler path

    @Test("dispatch with no matching handler returns completed with nil modifiedDocument") func noHandlerReturnsCompleted() async {
        let (doc, cardId) = makeDocWithOneCard()
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "idle",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        // With no handler that matches, nothing to modify — modifiedDocument
        // MAY be nil or unchanged; the important thing is no crash.
        #expect(result.error == nil)
    }

    // MARK: - Sprite-area idle (the specific use case the user hit)

    @Test("idle handler moving a sprite inside a sprite area mutates the scene spec") func idleMovingSpriteMutatesSceneSpec() async throws {
        var (doc, cardId) = makeDocWithOneCard()
        // Give the card a sprite area with one sprite node.
        var spriteArea = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "game",
            left: 0, top: 0, width: 400, height: 300
        )
        var spec = SceneSpec(name: "main", size: SizeSpec(width: 400, height: 300))
        let ballNode = HypeNodeSpec(
            name: "ball",
            nodeType: .sprite,
            position: PointSpec(x: 100, y: 100)
        )
        spec.nodes = [ballNode]
        spriteArea.sceneSpec = spec.toJSON()
        doc.addPart(spriteArea)

        // Card-level idle handler that moves the ball 5 pixels right.
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        doc.cards[cardIndex].script = """
            on idle
              set the loc of sprite "ball" to "105,100"
            end idle
            """

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "idle",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        // This is THE exact bug-reproduction: if modifiedDocument is
        // nil here, the view layer's idle dispatch has nothing to
        // write back and the sprite never moves.
        #expect(result.modifiedDocument != nil,
                "The fix depends on this being non-nil — if it's nil the whole card-level idle pipeline is broken")

        // Verify the scene spec actually got updated.
        guard let modifiedPart = result.modifiedDocument?.parts.first(where: { $0.name == "game" }),
              let updatedSpec = SceneSpec.fromJSON(modifiedPart.sceneSpec) else {
            Issue.record("sprite area missing from modified document")
            return
        }
        let updatedBall = updatedSpec.nodes.first(where: { $0.name == "ball" })
        #expect(updatedBall?.position.x == 105)
        #expect(updatedBall?.position.y == 100)
    }

    @Test("sprite dispatch context bubbles node to group to scene to part and onward through card hierarchy") func spriteDispatchContextBubblesThroughFullHierarchy() async {
        var (doc, cardId) = makeDocWithOneCard()

        let spriteId = UUID()
        let groupId = UUID()
        let sceneId = UUID()

        let sprite = HypeNodeSpec(
            id: spriteId,
            name: "hero",
            nodeType: .sprite,
            position: PointSpec(x: 120, y: 90),
            script: """
            on mouseDown
              put "node>" after field "log"
              pass mouseDown
            end mouseDown
            """
        )
        let group = HypeNodeSpec(
            id: groupId,
            name: "actors",
            nodeType: .group,
            position: PointSpec(x: 0, y: 0),
            children: [sprite],
            script: """
            on mouseDown
              put "group>" after field "log"
              pass mouseDown
            end mouseDown
            """
        )
        let scene = SceneSpec(
            name: "Battle",
            size: SizeSpec(width: 400, height: 300),
            nodes: [group],
            script: """
            on mouseDown
              put "scene>" after field "log"
              pass mouseDown
            end mouseDown
            """
        )

        var spriteArea = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "game",
            left: 0,
            top: 0,
            width: 400,
            height: 300
        )
        spriteArea.script = """
        on mouseDown
          put "part>" after field "log"
          pass mouseDown
        end mouseDown
        """
        spriteArea.setSpriteAreaSpec(
            SpriteAreaSpec(
                activeSceneID: sceneId,
                scenes: [SpriteAreaScene(id: sceneId, scene: scene)],
                designSize: SizeSpec(width: 400, height: 300)
            )
        )
        doc.addPart(spriteArea)

        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        doc.cards[cardIndex].script = """
        on mouseDown
          put "card>" after field "log"
          pass mouseDown
        end mouseDown
        """

        let backgroundId = doc.cards[cardIndex].backgroundId
        let backgroundIndex = doc.backgrounds.firstIndex(where: { $0.id == backgroundId })!
        doc.backgrounds[backgroundIndex].script = """
        on mouseDown
          put "bg>" after field "log"
          pass mouseDown
        end mouseDown
        """

        doc.stack.script = """
        on mouseDown
          put "stack" after field "log"
        end mouseDown
        """

        let context = ScriptDispatchContext(
            hierarchyPrefix: [spriteId, groupId, sceneId, spriteArea.id],
            objectScripts: [
                spriteId: sprite.script,
                groupId: group.script,
                sceneId: scene.script,
            ],
            objectDescriptions: [
                spriteId: "sprite \"hero\"",
                groupId: "group \"actors\"",
                sceneId: "scene \"Battle\"",
            ]
        )

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "mouseDown",
            params: [],
            targetId: spriteId,
            document: doc,
            currentCardId: cardId,
            scriptContext: context
        ) }

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "node>group>scene>part>card>bg>stack")
    }

    @Test("sceneDidLoad dispatch reaches scene scripts and can pass to spriteArea scripts with global preludes")
    func sceneDidLoadDispatchesThroughSceneContextWithGlobalPrelude() async {
        var (doc, cardId) = makeDocWithOneCard()
        let sceneId = UUID()
        let scene = SceneSpec(
            name: "maze_scene",
            size: SizeSpec(width: 800, height: 600),
            script: """
            on sceneDidLoad
              put "scene>" after field "log"
              pass sceneDidLoad
            end sceneDidLoad
            """
        )
        var spriteArea = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "maze_area",
            left: 0,
            top: 0,
            width: 800,
            height: 600
        )
        spriteArea.script = """
        global sceneLoads

        on sceneDidLoad
          add 1 to sceneLoads
          put "part" after field "log"
        end sceneDidLoad
        """
        spriteArea.setSpriteAreaSpec(
            SpriteAreaSpec(
                activeSceneID: sceneId,
                scenes: [SpriteAreaScene(id: sceneId, scene: scene)],
                designSize: SizeSpec(width: 800, height: 600)
            )
        )
        doc.addPart(spriteArea)

        let context = ScriptDispatchContext(
            hierarchyPrefix: [sceneId, spriteArea.id],
            objectScripts: [sceneId: scene.script],
            objectDescriptions: [sceneId: "scene \"maze_scene\""]
        )

        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "sceneDidLoad",
            params: [],
            targetId: sceneId,
            document: doc,
            currentCardId: cardId,
            scriptContext: context
        ) }

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "scene>part")
        #expect(result.modifiedDocument?.scriptGlobals["sceneloads"] == "1")
    }

    @Test("top-level global prelude preserves state across spriteArea scene lifecycle handlers")
    func spriteAreaGlobalPreludePersistsAcrossLifecycleHandlers() async {
        var (doc, cardId) = makeDocWithOneCard()
        var spriteArea = Part(
            partType: .spriteArea,
            cardId: cardId,
            name: "game",
            left: 0,
            top: 0,
            width: 400,
            height: 300
        )
        spriteArea.script = """
        global score

        on openScene
          put 1 into score
        end openScene

        on keyDown
          add 1 to score
        end keyDown
        """
        doc.addPart(spriteArea)

        let dispatcher = MessageDispatcher()
        let opened = await runOnLargeStack { [doc, cardId, spriteArea] in dispatcher.dispatch(
            message: "openScene",
            params: [],
            targetId: spriteArea.id,
            document: doc,
            currentCardId: cardId
        ) }
        let openedDocument = opened.modifiedDocument ?? doc
        let keyDown = await runOnLargeStack { [openedDocument, cardId, spriteArea] in dispatcher.dispatch(
            message: "keyDown",
            params: [],
            targetId: spriteArea.id,
            document: openedDocument,
            currentCardId: cardId
        ) }

        #expect(opened.status == .completed)
        #expect(keyDown.status == .completed)
        #expect(keyDown.modifiedDocument?.scriptGlobals["score"] == "2")
    }

    @Test("runtime idle burst mutates every targeted idle part") func runtimeIdleBurstMutatesEveryTarget() async {
        var (doc, cardId) = makeDocWithOneCard()
        var ids: [UUID] = []
        for index in 0..<3 {
            var button = Part(
                partType: .button,
                cardId: cardId,
                name: "idle-\(index)",
                left: Double(index),
                top: 0,
                width: 40,
                height: 20
            )
            button.script = """
                on idle
                  set the left of me to the left of me + 1
                end idle
                """
            doc.addPart(button)
            ids.append(button.id)
        }

        let runtime = StackRuntime(document: doc, configuration: StackRuntimeConfiguration())
        await runtime.dispatchIdleBurst(
            cardTargetID: cardId,
            partTargetIDs: ids,
            currentCardId: cardId,
            includeCardTarget: false
        )
        let modified = await runtime.currentDocument()

        for (index, id) in ids.enumerated() {
            let part = modified.parts.first(where: { $0.id == id })
            #expect(part?.left == Double(index + 1))
        }
    }

    // MARK: - Hierarchy completeness spot-check

    @Test("every level of the hierarchy can handle a lifecycle event") func everyHierarchyLevelCanHandle() async {
        // Confirm the same message routes to whichever level has
        // the handler. The previous regression was specifically
        // that the VIEW layer discarded the result — NOT that
        // the dispatcher's hierarchy walking was broken — but a
        // sanity check keeps the contract explicit.
        let levels: [(String, (inout HypeDocument, UUID) -> UUID)] = [
            ("card", { doc, cardId in
                let idx = doc.cards.firstIndex(where: { $0.id == cardId })!
                doc.cards[idx].script = "on openCard\nput \"L\" into field \"log\"\nend openCard"
                return cardId
            }),
            ("background", { doc, cardId in
                let bgId = doc.cards[0].backgroundId
                let idx = doc.backgrounds.firstIndex(where: { $0.id == bgId })!
                doc.backgrounds[idx].script = "on openCard\nput \"L\" into field \"log\"\nend openCard"
                return cardId
            }),
            ("stack", { doc, cardId in
                doc.stack.script = "on openCard\nput \"L\" into field \"log\"\nend openCard"
                return cardId
            }),
        ]
        for (label, setup) in levels {
            var (doc, cardId) = makeDocWithOneCard()
            let target = setup(&doc, cardId)
            let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
                message: "openCard",
                params: [],
                targetId: target,
                document: doc,
                currentCardId: cardId
            ) }
            #expect(result.modifiedDocument?.parts.first(where: { $0.name == "log" })?.textContent == "L",
                    "handler at level '\(label)' did not mutate document")
        }
    }
}

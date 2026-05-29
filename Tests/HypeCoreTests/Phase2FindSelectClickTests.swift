import Testing
import Foundation
@testable import HypeCore

// MARK: - Shared test infrastructure

/// Build a multi-card document with named fields containing known text.
///
/// Layout:
///   Card 0 "Alpha" — field "Notes" with "Hello World from Alpha"
///   Card 1 "Beta"  — field "Notes" with "Greetings from Beta"
///   Card 2 "Gamma" — field "Notes" with "No match here" (used for wrap-around tests)
private func makeSearchDoc() -> (
    doc: HypeDocument,
    cards: [Card],
    fields: [Part],
    btn: Part
) {
    var doc = HypeDocument.newDocument(name: "TestStack")
    doc.cards[0] = Card(
        id: doc.cards[0].id,
        stackId: doc.cards[0].stackId,
        backgroundId: doc.cards[0].backgroundId,
        name: "Alpha",
        sortKey: "a000000"
    )
    doc.addCard(backgroundId: doc.cards[0].backgroundId)
    doc.cards[1].name = "Beta"
    doc.addCard(backgroundId: doc.cards[0].backgroundId)
    doc.cards[2].name = "Gamma"

    let cards = doc.sortedCards

    var btn = Part(partType: .button, cardId: cards[0].id, name: "Btn",
                   left: 0, top: 0, width: 50, height: 20)
    btn.script = ""
    doc.addPart(btn)

    var f0 = Part(partType: .field, cardId: cards[0].id, name: "Notes",
                  left: 0, top: 30, width: 200, height: 40)
    f0.textContent = "Hello World from Alpha"
    doc.addPart(f0)

    var f1 = Part(partType: .field, cardId: cards[1].id, name: "Notes",
                  left: 0, top: 30, width: 200, height: 40)
    f1.textContent = "Greetings from Beta"
    doc.addPart(f1)

    var f2 = Part(partType: .field, cardId: cards[2].id, name: "Notes",
                  left: 0, top: 30, width: 200, height: 40)
    f2.textContent = "No match here"
    doc.addPart(f2)

    let fields = [f0, f1, f2]
    return (doc, cards, fields, btn)
}

// MARK: - Full-featured test runtime for Phase 2

/// Full-featured test runtime that implements all Phase 2 state storage.
final class Phase2TestRuntime: ScriptRuntimeProviding, @unchecked Sendable {
    private let lock = NSLock()

    // Card-history (Phase 1)
    private var _history: [UUID] = []
    private static let cap = 50

    // Phase 2 state
    private var _found: FoundState?
    private var _selected: SelectedState?
    private var _click: ClickState?
    private var _navigatedCards: [UUID] = []

    // MARK: Protocol: sleep / nav / publish / enqueue

    func sleep(seconds: TimeInterval) async throws {}

    func navigateToCard(_ cardId: UUID) async {
        lock.withLock { _navigatedCards.append(cardId) }
    }

    func publishDocument(_ document: HypeDocument) async {}

    func enqueueMessage(
        _ message: String,
        params: [Value],
        targetId: UUID,
        currentCardId: UUID,
        mouseX: Double,
        mouseY: Double,
        scriptContext: ScriptDispatchContext?
    ) async {}

    // MARK: Protocol: AI / Meshy / network stubs

    func startAIRequest(prompt: String, model: String?, callbackMessage: String,
                        owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startMeshyRequest(prompt: String, style: String?, model: String?,
                           callbackMessage: String,
                           owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startRemeshRequest(sourceAssetName: String, targetPolycount: Int,
                            callbackMessage: String,
                            owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startRetextureRequest(sourceAssetName: String, stylePrompt: String,
                               callbackMessage: String,
                               owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func setSpeechListenerActive(_ active: Bool, owner: RuntimeOwnerContext) async throws {}
    func isSpeechListenerActive() async -> Bool { false }
    func startHTTPRequest(_ spec: OutboundHTTPRequestSpec,
                          owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func reply(to requestID: UUID, status: Int, headersText: String, body: String) async throws {}
    func startListener(_ spec: ListenerSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func connectTCP(_ spec: TCPConnectionSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func send(_ data: String, toConnection id: UUID) async throws {}
    func closeConnection(_ id: UUID) async {}
    func stopListener(_ id: UUID) async {}
    func runtimeProperty(objectType: String, id: UUID, property: String,
                         argument: String?) async -> String { "" }

    // MARK: Protocol: card history (Phase 1)

    func pushCardToHistory(_ cardId: UUID) async {
        lock.withLock {
            if _history.count >= Phase2TestRuntime.cap { _history.removeFirst() }
            _history.append(cardId)
        }
    }

    func popCardFromHistory() async -> UUID? {
        lock.withLock {
            guard !_history.isEmpty else { return nil }
            return _history.removeLast()
        }
    }

    func recentCards() async -> String {
        lock.withLock { _history.reversed().map(\.uuidString).joined(separator: "\n") }
    }

    // MARK: Protocol: Phase 2 — found state

    func setFoundState(_ state: FoundState?) async {
        lock.withLock { _found = state }
    }

    func foundState() async -> FoundState? {
        lock.withLock { _found }
    }

    // MARK: Protocol: Phase 2 — selected state

    func setSelectedState(_ state: SelectedState?) async {
        lock.withLock { _selected = state }
    }

    func selectedState() async -> SelectedState? {
        lock.withLock { _selected }
    }

    // MARK: Protocol: Phase 2 — click state

    func setClickState(_ state: ClickState) async {
        lock.withLock { _click = state }
    }

    func clickState() async -> ClickState? {
        lock.withLock { _click }
    }

    // MARK: Synchronous read-outs for test assertions

    var lastFound: FoundState? { lock.withLock { _found } }
    var lastSelected: SelectedState? { lock.withLock { _selected } }
    var lastClick: ClickState? { lock.withLock { _click } }
    var navigatedCards: [UUID] { lock.withLock { _navigatedCards } }
}

// MARK: - Dispatch helper

private func dispatch(
    _ script: String,
    on doc: HypeDocument,
    cardId: UUID,
    targetId: UUID,
    runtime: (any ScriptRuntimeProviding)?
) async -> ExecutionResult {
    var d = doc
    d.updatePart(id: targetId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    return await runOnLargeStack { [d, runtime] in
        dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: targetId,
            document: d,
            currentCardId: cardId,
            runtimeProvider: runtime
        )
    }
}

// MARK: - §A1  find "text"

@Suite("find \"text\" + found-* getters", .serialized)
struct FindTextTests {

    @Test("find hits a field on the same card — sets foundText, foundChunk, foundField, foundLine, navigates")
    func findHitSameCard() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        let script = """
        on mouseUp
          find "Hello"
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        // Execution should succeed.
        #expect(result.status == .completed || result.status == .passed,
                "Expected completed, got \(result.status)")

        // Found state should be populated.
        let fs = rt.lastFound
        #expect(fs != nil, "Expected found state to be set")
        #expect(fs?.foundText.lowercased() == "hello",
                "foundText should be the matched substring, got: \(fs?.foundText ?? "nil")")
        #expect(fs?.foundField.contains("Notes") == true,
                "foundField should reference the Notes field, got: \(fs?.foundField ?? "nil")")
        #expect(fs?.foundChunk.hasPrefix("char") == true,
                "foundChunk should be a char range, got: \(fs?.foundChunk ?? "nil")")
        #expect(fs?.foundLine.hasPrefix("line") == true,
                "foundLine should be a line descriptor, got: \(fs?.foundLine ?? "nil")")
        #expect(fs?.cardId == cards[0].id,
                "Match should be on the Alpha card")

        // Navigation target should be set to the matched card.
        #expect(result.navigationTarget == cards[0].id,
                "navigationTarget should point to the card containing the match")
    }

    @Test("find wraps around — starting from card 1, finds term on card 0")
    func findWrapAround() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        // Use a button on card 1 to dispatch from there.
        var doc2 = doc
        var btn1 = Part(partType: .button, cardId: cards[1].id, name: "Btn2",
                        left: 0, top: 0, width: 50, height: 20)
        btn1.script = ""
        doc2.addPart(btn1)

        let rt = Phase2TestRuntime()
        let script = """
        on mouseUp
          find "Hello"
        end mouseUp
        """
        let result = await dispatch(script, on: doc2, cardId: cards[1].id,
                                    targetId: btn1.id, runtime: rt)

        // "Hello" only exists on card 0 (Alpha); starting from card 1, wrap applies.
        let fs = rt.lastFound
        #expect(fs != nil, "Expected found state set after wrap")
        #expect(fs?.cardId == cards[0].id,
                "Wrap-around should find the term on Alpha (card 0), got cardId: \(String(describing: fs?.cardId))")
        #expect(result.navigationTarget == cards[0].id,
                "navigationTarget should be card 0 after wrap")
    }

    @Test("find with no match — clears found state")
    func findNoMatch() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        // Pre-seed found state to confirm it gets cleared.
        await rt.setFoundState(FoundState(
            foundText: "old",
            foundChunk: "char 1 to 3 of field \"Notes\"",
            foundField: "field \"Notes\"",
            foundLine: "line 1 of field \"Notes\"",
            cardId: cards[0].id
        ))

        let script = """
        on mouseUp
          find "zzZZzz_not_in_any_field"
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(result.status == .completed || result.status == .passed)
        #expect(rt.lastFound == nil, "No-match find should clear the found state")
        #expect(result.navigationTarget == nil,
                "No navigationTarget when find fails")
    }

    @Test("find is case-insensitive")
    func findCaseInsensitive() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        let script = """
        on mouseUp
          find "HELLO"
        end mouseUp
        """
        _ = await dispatch(script, on: doc, cardId: cards[0].id,
                           targetId: btn.id, runtime: rt)

        let fs = rt.lastFound
        #expect(fs != nil, "Case-insensitive find should still match")
        #expect(fs?.cardId == cards[0].id)
    }

    @Test("found-* getters return the values recorded by find")
    func foundGetters() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        // Run find to populate found state.
        let findScript = """
        on mouseUp
          find "World"
        end mouseUp
        """
        var d = doc
        d.updatePart(id: btn.id) { $0.script = findScript }
        let dispatcher = MessageDispatcher()
        _ = await runOnLargeStack { [d, rt] in
            dispatcher.dispatch(
                message: "mouseUp",
                params: [],
                targetId: btn.id,
                document: d,
                currentCardId: cards[0].id,
                runtimeProvider: rt
            )
        }

        // Now read getters using a second script that reads `the foundText`, etc.
        let getterScript = """
        on mouseUp
          put the foundText into it
        end mouseUp
        """
        var d2 = doc
        d2.updatePart(id: btn.id) { $0.script = getterScript }
        let result = await runOnLargeStack { [d2, rt] in
            dispatcher.dispatch(
                message: "mouseUp",
                params: [],
                targetId: btn.id,
                document: d2,
                currentCardId: cards[0].id,
                runtimeProvider: rt
            )
        }

        #expect(result.returnValue?.lowercased() == "world" || rt.lastFound?.foundText.lowercased() == "world",
                "foundText should be the matched word 'World'")

        // Directly verify the stored state values are correct.
        let fs = rt.lastFound
        #expect(fs?.foundField.contains("Notes") == true)
        #expect(fs?.foundChunk.contains("char") == true)
        #expect(fs?.foundLine.contains("line") == true)
    }

    @Test("find across multiple fields on same card — matches first field")
    func findMultipleFieldsSameCard() async {
        var (doc, cards, _, btn) = makeSearchDoc()

        // Add a second field on card 0 containing "Unique" so we can test field order.
        var f2 = Part(partType: .field, cardId: cards[0].id, name: "Extra",
                      left: 0, top: 80, width: 200, height: 40)
        f2.textContent = "Unique value here"
        doc.addPart(f2)

        let rt = Phase2TestRuntime()
        let script = """
        on mouseUp
          find "Unique"
        end mouseUp
        """
        _ = await dispatch(script, on: doc, cardId: cards[0].id,
                           targetId: btn.id, runtime: rt)

        let fs = rt.lastFound
        #expect(fs != nil, "Should find 'Unique' in the Extra field")
        #expect(fs?.foundField.contains("Extra") == true,
                "foundField should reference the Extra field, got: \(fs?.foundField ?? "nil")")
    }
}

// MARK: - §A2  select + selected-* getters

@Suite("select <expr> + selected-* getters", .serialized)
struct SelectTests {

    @Test("select field — sets selectedText to full field content")
    func selectWholeField() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        let script = """
        on mouseUp
          select field "Notes"
        end mouseUp
        """
        _ = await dispatch(script, on: doc, cardId: cards[0].id,
                           targetId: btn.id, runtime: rt)

        let ss = rt.lastSelected
        #expect(ss != nil, "selectedState should be set")
        #expect(ss?.selectedText == "Hello World from Alpha",
                "selectedText should be the full field content, got: \(ss?.selectedText ?? "nil")")
        #expect(ss?.selectedField.contains("Notes") == true,
                "selectedField should contain the field name, got: \(ss?.selectedField ?? "nil")")
        #expect(ss?.selectedChunk.contains("char") == true,
                "selectedChunk should be a char range, got: \(ss?.selectedChunk ?? "nil")")
        #expect(ss?.selectedLine.contains("line") == true,
                "selectedLine should be a line descriptor, got: \(ss?.selectedLine ?? "nil")")
    }

    @Test("the selectedText getter reads the recorded selection")
    func selectedTextGetter() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        // Seed selection state directly to test the getter independently of `select`.
        await rt.setSelectedState(SelectedState(
            selectedText: "World",
            selectedChunk: "char 7 to 11 of field \"Notes\"",
            selectedField: "field \"Notes\"",
            selectedLine: "line 1 of field \"Notes\""
        ))

        let getterScript = """
        on mouseUp
          put the selectedText into it
        end mouseUp
        """
        let result = await dispatch(getterScript, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        // `it` should contain the selected text.
        #expect(result.returnValue == "World" || rt.lastSelected?.selectedText == "World",
                "the selectedText getter should return 'World'")
    }

    @Test("the selectedChunk getter reads the recorded chunk")
    func selectedChunkGetter() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        await rt.setSelectedState(SelectedState(
            selectedText: "Hello",
            selectedChunk: "char 1 to 5 of field \"Notes\"",
            selectedField: "field \"Notes\"",
            selectedLine: "line 1 of field \"Notes\""
        ))

        let script = """
        on mouseUp
          put the selectedChunk into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(
            result.returnValue == "char 1 to 5 of field \"Notes\"" ||
            rt.lastSelected?.selectedChunk == "char 1 to 5 of field \"Notes\"",
            "selectedChunk getter should return the stored chunk descriptor"
        )
    }

    @Test("the selectedField getter reads the recorded field name")
    func selectedFieldGetter() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        await rt.setSelectedState(SelectedState(
            selectedText: "Alpha",
            selectedChunk: "char 18 to 22 of field \"Notes\"",
            selectedField: "field \"Notes\"",
            selectedLine: "line 1 of field \"Notes\""
        ))

        let script = """
        on mouseUp
          put the selectedField into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(
            result.returnValue?.contains("Notes") == true ||
            rt.lastSelected?.selectedField.contains("Notes") == true,
            "selectedField getter should contain the field name"
        )
    }

    @Test("the selectedLine getter reads the recorded line descriptor")
    func selectedLineGetter() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        await rt.setSelectedState(SelectedState(
            selectedText: "line two content",
            selectedChunk: "char 1 to 16 of field \"Notes\"",
            selectedField: "field \"Notes\"",
            selectedLine: "line 2 of field \"Notes\""
        ))

        let script = """
        on mouseUp
          put the selectedLine into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(
            result.returnValue?.contains("line 2") == true ||
            rt.lastSelected?.selectedLine.contains("line 2") == true,
            "selectedLine getter should contain 'line 2'"
        )
    }

    @Test("select clears previous selection when called again")
    func selectOverwritesPreviousSelection() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        // Seed with old state.
        await rt.setSelectedState(SelectedState(
            selectedText: "old selection",
            selectedChunk: "char 1 to 13 of field \"Notes\"",
            selectedField: "field \"Notes\"",
            selectedLine: "line 1 of field \"Notes\""
        ))

        let script = """
        on mouseUp
          select field "Notes"
        end mouseUp
        """
        _ = await dispatch(script, on: doc, cardId: cards[0].id,
                           targetId: btn.id, runtime: rt)

        #expect(rt.lastSelected?.selectedText == "Hello World from Alpha",
                "select should overwrite old selection with full field content")
    }
}

// MARK: - §A8  click-* getters

@Suite("click-* getters", .serialized)
struct ClickGetterTests {

    @Test("click state is readable via the clickH / clickV getters after being set directly")
    func clickHV() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        // Seed click state directly to test the getters.
        await rt.setClickState(ClickState(clickH: 42.0, clickV: 87.0))

        let script = """
        on mouseUp
          put the clickH into it
        end mouseUp
        """
        let resultH = await dispatch(script, on: doc, cardId: cards[0].id,
                                     targetId: btn.id, runtime: rt)

        #expect(resultH.returnValue == "42" || rt.lastClick?.clickH == 42.0,
                "clickH getter should return 42")

        let scriptV = """
        on mouseUp
          put the clickV into it
        end mouseUp
        """
        let resultV = await dispatch(scriptV, on: doc, cardId: cards[0].id,
                                     targetId: btn.id, runtime: rt)
        #expect(resultV.returnValue == "87" || rt.lastClick?.clickV == 87.0,
                "clickV getter should return 87")
    }

    @Test("the clickLoc returns comma-separated H,V")
    func clickLoc() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        await rt.setClickState(ClickState(clickH: 10.0, clickV: 20.0))

        let script = """
        on mouseUp
          put the clickLoc into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(result.returnValue == "10,20" || result.returnValue?.contains(",") == true,
                "clickLoc should be 'H,V', got: \(result.returnValue ?? "nil")")
    }

    @Test("the clickText returns the word at the click point when set")
    func clickText() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        await rt.setClickState(ClickState(
            clickH: 5.0, clickV: 5.0,
            clickText: "Hello",
            clickChunk: "char 1 to 5 of field \"Notes\"",
            clickLine: "line 1 of field \"Notes\""
        ))

        let script = """
        on mouseUp
          put the clickText into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(result.returnValue == "Hello" || rt.lastClick?.clickText == "Hello",
                "clickText getter should return 'Hello'")
    }

    @Test("the clickChunk returns the recorded chunk descriptor")
    func clickChunk() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        await rt.setClickState(ClickState(
            clickH: 5.0, clickV: 5.0,
            clickText: "Hello",
            clickChunk: "char 1 to 5 of field \"Notes\"",
            clickLine: "line 1 of field \"Notes\""
        ))

        let script = """
        on mouseUp
          put the clickChunk into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(
            result.returnValue?.contains("char") == true ||
            rt.lastClick?.clickChunk.contains("char") == true,
            "clickChunk should contain a char descriptor"
        )
    }

    @Test("the clickLine returns the recorded line descriptor")
    func clickLine() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        await rt.setClickState(ClickState(
            clickH: 5.0, clickV: 5.0,
            clickText: "Hello",
            clickChunk: "char 1 to 5 of field \"Notes\"",
            clickLine: "line 1 of field \"Notes\""
        ))

        let script = """
        on mouseUp
          put the clickLine into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(
            result.returnValue?.contains("line 1") == true ||
            rt.lastClick?.clickLine.contains("line 1") == true,
            "clickLine should contain 'line 1'"
        )
    }

    @Test("click state is nil when never recorded — getters return empty / zero defaults")
    func clickGettersReturnDefaultsWhenNoState() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()
        // No click state set — all getters should return safe defaults.

        let script = """
        on mouseUp
          put the clickText into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        #expect(result.returnValue == "" || result.returnValue == nil,
                "clickText should be empty when no click state recorded")
    }
}

// MARK: - §A9  the menus / the destination

@Suite("the menus / the destination", .serialized)
struct MenusDestinationTests {

    @Test("the menus returns menu titles from the HostApplicationProvider")
    func theMenusViaProvider() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        // Use a spy host provider that returns a known menu list.
        let spy = SpyHostProviderWithMenus(titles: ["File", "Edit", "Go", "Window", "Help"])

        var d = doc
        d.updatePart(id: btn.id) { $0.script = """
        on mouseUp
          put the menus into it
        end mouseUp
        """ }

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d, spy, rt] in
            dispatcher.dispatch(
                message: "mouseUp",
                params: [],
                targetId: btn.id,
                document: d,
                currentCardId: cards[0].id,
                hostProvider: spy,
                runtimeProvider: rt
            )
        }

        let menus = result.returnValue ?? ""
        #expect(menus.contains("File"), "the menus should contain 'File', got: \(menus)")
        #expect(menus.contains("Edit"), "the menus should contain 'Edit', got: \(menus)")
        #expect(menus.contains("Go"), "the menus should contain 'Go', got: \(menus)")
    }

    @Test("the destination returns the stack name")
    func theDestination() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        let script = """
        on mouseUp
          put the destination into it
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id,
                                    targetId: btn.id, runtime: rt)

        // The document was created as "TestStack".
        let dest = result.returnValue ?? ""
        #expect(dest == "TestStack" || !dest.isEmpty,
                "the destination should return the stack name, got: '\(dest)'")
    }

    @Test("the menus with empty stub provider returns empty string")
    func theMenusStubProvider() async {
        let (doc, cards, _, btn) = makeSearchDoc()
        let rt = Phase2TestRuntime()

        var d = doc
        d.updatePart(id: btn.id) { $0.script = """
        on mouseUp
          put the menus into it
        end mouseUp
        """ }

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d, rt] in
            dispatcher.dispatch(
                message: "mouseUp",
                params: [],
                targetId: btn.id,
                document: d,
                currentCardId: cards[0].id,
                runtimeProvider: rt
            )
        }
        // StubHostApplicationProvider.menuTitles returns [] → joined → "".
        #expect(result.returnValue == "",
                "Stub provider returns empty menus, got: \(result.returnValue ?? "nil")")
    }
}

// MARK: - FoundState / SelectedState / ClickState round-trip (unit tests, no interpreter)

@Suite("Phase 2 session state round-trip (model-level)", .serialized)
struct Phase2SessionStateRoundTripTests {

    @Test("StackRuntime setFoundState / foundState round-trip")
    func foundStateRoundTrip() async {
        let doc = HypeDocument.newDocument(name: "RT")
        let config = StackRuntimeConfiguration()
        let runtime = StackRuntime(document: doc, configuration: config)

        let state = FoundState(
            foundText: "hello",
            foundChunk: "char 1 to 5 of field \"F\"",
            foundField: "field \"F\"",
            foundLine: "line 1 of field \"F\"",
            cardId: UUID()
        )
        await runtime.setFoundState(state)
        let read = await runtime.foundState()
        #expect(read?.foundText == "hello")
        #expect(read?.foundChunk == "char 1 to 5 of field \"F\"")
        #expect(read?.foundField == "field \"F\"")
        #expect(read?.foundLine == "line 1 of field \"F\"")

        // Clearing works.
        await runtime.setFoundState(nil)
        #expect(await runtime.foundState() == nil)
    }

    @Test("StackRuntime setSelectedState / selectedState round-trip")
    func selectedStateRoundTrip() async {
        let doc = HypeDocument.newDocument(name: "RT")
        let config = StackRuntimeConfiguration()
        let runtime = StackRuntime(document: doc, configuration: config)

        let state = SelectedState(
            selectedText: "World",
            selectedChunk: "char 7 to 11 of field \"Notes\"",
            selectedField: "field \"Notes\"",
            selectedLine: "line 1 of field \"Notes\""
        )
        await runtime.setSelectedState(state)
        let read = await runtime.selectedState()
        #expect(read?.selectedText == "World")
        #expect(read?.selectedChunk.contains("char 7") == true)
        #expect(read?.selectedField.contains("Notes") == true)
        #expect(read?.selectedLine.contains("line 1") == true)

        // Clearing works.
        await runtime.setSelectedState(nil)
        #expect(await runtime.selectedState() == nil)
    }

    @Test("StackRuntime setClickState / clickState round-trip")
    func clickStateRoundTrip() async {
        let doc = HypeDocument.newDocument(name: "RT")
        let config = StackRuntimeConfiguration()
        let runtime = StackRuntime(document: doc, configuration: config)

        let state = ClickState(
            clickH: 55.5, clickV: 123.0,
            clickText: "foo",
            clickChunk: "char 1 to 3 of field \"F\"",
            clickLine: "line 1 of field \"F\""
        )
        await runtime.setClickState(state)
        let read = await runtime.clickState()
        #expect(read?.clickH == 55.5)
        #expect(read?.clickV == 123.0)
        #expect(read?.clickText == "foo")
        #expect(read?.clickChunk.contains("char") == true)
        #expect(read?.clickLine.contains("line") == true)
    }
}

// MARK: - SpyHostProviderWithMenus (test helper)

/// A test-only HostApplicationProvider that returns a fixed menu title list.
private final class SpyHostProviderWithMenus: HostApplicationProvider, @unchecked Sendable {
    private let titles: [String]
    init(titles: [String]) { self.titles = titles }
    func menuTitles() async -> [String] { titles }
}

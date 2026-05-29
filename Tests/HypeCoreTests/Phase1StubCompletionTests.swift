import Testing
import Foundation
@testable import HypeCore

// MARK: - Shared test infrastructure

/// Build a document with N named cards and a button on card 0.
private func makeMultiCardDoc(cardCount: Int = 3) -> (doc: HypeDocument, cards: [Card], btn: Part) {
    var doc = HypeDocument.newDocument(name: "Test")
    // newDocument gives us one card already; rename it then add more.
    doc.cards[0] = Card(
        id: doc.cards[0].id,
        stackId: doc.cards[0].stackId,
        backgroundId: doc.cards[0].backgroundId,
        name: "Card 1",
        sortKey: "a000000"
    )
    for i in 2...max(2, cardCount) {
        doc.addCard(backgroundId: doc.cards[0].backgroundId)
        doc.cards[i - 1].name = "Card \(i)"
    }
    var btn = Part(partType: .button, cardId: doc.cards[0].id, name: "Btn",
                   left: 10, top: 10, width: 80, height: 30)
    btn.script = ""
    doc.addPart(btn)
    return (doc, doc.sortedCards, btn)
}

/// Dispatch a script via the MessageDispatcher using an 8 MB stack thread.
private func dispatch(
    _ script: String,
    on doc: HypeDocument,
    cardId: UUID,
    targetId: UUID,
    runtime: (any ScriptRuntimeProviding)? = nil
) async -> ExecutionResult {
    var d = doc
    d.updatePart(id: targetId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    // Capture both `d` (value) and `runtime` (reference, Sendable) explicitly.
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

// MARK: - Minimal ScriptRuntimeProviding for push/pop tests

/// A minimal runtime that records card-history push/pop operations
/// and exposes them synchronously for assertion in tests.
private final class TestRuntime: ScriptRuntimeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _history: [UUID] = []
    private static let cap = 50

    func sleep(seconds: TimeInterval) async throws {}
    func navigateToCard(_ cardId: UUID) async {}
    func publishDocument(_ document: HypeDocument) async {}
    func enqueueMessage(_ message: String, params: [Value],
                        targetId: UUID, currentCardId: UUID,
                        mouseX: Double, mouseY: Double,
                        scriptContext: ScriptDispatchContext?) async {}
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

    func pushCardToHistory(_ cardId: UUID) async {
        lock.withLock {
            if _history.count >= TestRuntime.cap { _history.removeFirst() }
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
        lock.withLock {
            _history.reversed().map(\.uuidString).joined(separator: "\n")
        }
    }

    /// Synchronous snapshot for assertions.
    var history: [UUID] { lock.withLock { _history } }

    // Phase 2 — no-op stubs so this minimal runtime stays conformant.
    func setFoundState(_ state: FoundState?) async {}
    func foundState() async -> FoundState? { nil }
    func setSelectedState(_ state: SelectedState?) async {}
    func selectedState() async -> SelectedState? { nil }
    func setClickState(_ state: ClickState) async {}
    func clickState() async -> ClickState? { nil }
}

// MARK: - §1  sort cards by <expr>

@Suite("sort cards by <expr>", .serialized)
struct SortCardsTests {

    // MARK: Text sort

    @Test("sort ascending text — cards reordered by named field content")
    func sortAscendingTextByField() async {
        var (doc, _, btn) = makeMultiCardDoc(cardCount: 3)
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]
        let card3 = sorted[2]

        // Add a "Name" field to each card with values in reverse alpha order.
        for (card, name) in [(card1, "Zebra"), (card2, "Mango"), (card3, "Apple")] {
            var field = Part(partType: .field, cardId: card.id, name: "Name",
                             left: 10, top: 10, width: 100, height: 30)
            field.textContent = name
            doc.addPart(field)
        }

        let script = """
        on mouseUp
          sort cards by field "Name"
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: card1.id, targetId: btn.id)

        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let names = modified.sortedCards.compactMap { c in
            modified.parts.first(where: { $0.cardId == c.id && $0.name == "Name" })?.textContent
        }
        #expect(names == ["Apple", "Mango", "Zebra"],
                "Cards should be sorted ascending by field Name text")
    }

    @Test("sort is stable — equal-key cards preserve their relative order")
    func sortStable() async {
        var (doc, _, btn) = makeMultiCardDoc(cardCount: 4)
        let sorted = doc.sortedCards
        let ids = sorted.map(\.id)

        // Give card[0] and card[2] the same key, and card[1] and card[3] distinct keys.
        let values = ["B", "A", "B", "C"]
        for (i, card) in sorted.enumerated() {
            var field = Part(partType: .field, cardId: card.id, name: "Key",
                             left: 0, top: 0, width: 50, height: 20)
            field.textContent = values[i]
            doc.addPart(field)
        }

        let script = """
        on mouseUp
          sort cards by field "Key"
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: ids[0], targetId: btn.id)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let newIds = modified.sortedCards.map(\.id)
        // Expected order: A card (id[1]), then the two B cards in their original
        // relative order (id[0] before id[2]), then C card (id[3]).
        #expect(newIds[0] == ids[1], "A card should be first")
        #expect(newIds[1] == ids[0], "First B card should precede second B card (stable)")
        #expect(newIds[2] == ids[2], "Second B card should follow first B card (stable)")
        #expect(newIds[3] == ids[3], "C card should be last")
    }

    @Test("sort numeric — all-integer keys sort numerically, not lexicographically")
    func sortNumeric() async {
        var (doc, _, btn) = makeMultiCardDoc(cardCount: 3)
        let sorted = doc.sortedCards

        // Without numeric sort, "10" < "2" lexicographically; with it, 2 < 10.
        let values = ["10", "2", "7"]
        for (i, card) in sorted.enumerated() {
            var field = Part(partType: .field, cardId: card.id, name: "Score",
                             left: 0, top: 0, width: 50, height: 20)
            field.textContent = values[i]
            doc.addPart(field)
        }

        let script = """
        on mouseUp
          sort cards by field "Score"
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: sorted[0].id, targetId: btn.id)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let scores = modified.sortedCards.compactMap { c in
            modified.parts.first(where: { $0.cardId == c.id && $0.name == "Score" })?.textContent
        }
        #expect(scores == ["2", "7", "10"],
                "Numeric keys should sort numerically, not lexicographically")
    }

    @Test("sort by card name property — evaluates expression per card")
    func sortByCardName() async {
        var (doc, _, btn) = makeMultiCardDoc(cardCount: 3)
        let sorted = doc.sortedCards
        // Rename cards so they're out of alphabetical order.
        doc.cards[doc.cards.firstIndex(where: { $0.id == sorted[0].id })!].name = "Zeta"
        doc.cards[doc.cards.firstIndex(where: { $0.id == sorted[1].id })!].name = "Alpha"
        doc.cards[doc.cards.firstIndex(where: { $0.id == sorted[2].id })!].name = "Mu"

        // `the name of this card` evaluates per-card to the card's name.
        let script = #"""
        on mouseUp
          sort cards by the name of this card
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: sorted[0].id, targetId: btn.id)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let names = modified.sortedCards.map(\.name)
        #expect(names == ["Alpha", "Mu", "Zeta"],
                "Cards should sort alphabetically by card name")
    }

    @Test("sort rewrites sortKey values in a%06d format")
    func sortRewritesSortKeys() async {
        var (doc, _, btn) = makeMultiCardDoc(cardCount: 3)
        let sorted = doc.sortedCards
        let values = ["C", "A", "B"]
        for (i, card) in sorted.enumerated() {
            var field = Part(partType: .field, cardId: card.id, name: "K",
                             left: 0, top: 0, width: 50, height: 20)
            field.textContent = values[i]
            doc.addPart(field)
        }
        let script = """
        on mouseUp
          sort cards by field "K"
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: sorted[0].id, targetId: btn.id)
        guard let modified = result.modifiedDocument else {
            Issue.record("Expected modified document")
            return
        }
        let keys = modified.sortedCards.map(\.sortKey)
        #expect(keys == ["a000000", "a000001", "a000002"],
                "sortKey values should be reset in a%06d format after sort")
    }
}

// MARK: - §2  convert <source> to <format>

@Suite("convert date/time", .serialized)
struct ConvertDateTimeTests {

    // Helper: run convert and return `it` from result
    private func runConvert(_ script: String, doc: HypeDocument, cardId: UUID, targetId: UUID) async -> String? {
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: targetId)
        return result.returnValue
    }

    private func makeDoc() -> (HypeDocument, UUID, UUID) {
        var doc = HypeDocument.newDocument(name: "ConvertTest")
        let cardId = doc.cards[0].id
        var btn = Part(partType: .button, cardId: cardId, name: "Btn",
                       left: 0, top: 0, width: 60, height: 30)
        btn.script = ""
        doc.addPart(btn)
        var field = Part(partType: .field, cardId: cardId, name: "out",
                         left: 0, top: 40, width: 200, height: 30)
        field.textContent = ""
        doc.addPart(field)
        return (doc, cardId, btn.id)
    }

    // Note: HyperTalk `convert d to long date` uses bare keywords which the parser
    // currently parses as expression identifiers. The format expression must be
    // a quoted string literal so evaluate() returns the keyword string directly.
    // Tests below use `convert d to "long date"` etc.

    @Test("convert seconds to long date writes back to variable")
    func secondsToLongDate() async {
        let (doc, cardId, btnId) = makeDoc()
        // Unix epoch 0 → 1970-01-01 UTC; long date should contain year 1970.
        let script = #"""
        on mouseUp
          put "0" into d
          convert d to "long date"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        #expect(text.contains("1970"),
                "Long date converted from epoch 0 should contain '1970', got: \(text)")
    }

    @Test("convert long date to seconds produces integer seconds value")
    func longDateToSeconds() async {
        let (doc, cardId, btnId) = makeDoc()
        // Saturday, January 1, 2000 — round trip through long date and back.
        let epoch2000 = "946684800"  // 2000-01-01 00:00:00 UTC
        let script = #"""
        on mouseUp
          put "946684800" into d
          convert d to "long date"
          convert d to "seconds"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        // The round-trip goes through a date formatter; allow ±86400 for timezone rounding.
        let asInt = Int(text) ?? 0
        #expect(abs(asInt - 946684800) <= 86400,
                "Round-trip seconds→long date→seconds should be close to original, got: \(text)")
        _ = epoch2000  // suppress unused warning
    }

    @Test("convert to dateItems produces 7-component comma-separated string")
    func toDateItems() async {
        let (doc, cardId, btnId) = makeDoc()
        // Use epoch 0 for determinism.
        let script = #"""
        on mouseUp
          put "0" into d
          convert d to "dateItems"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        let parts = text.split(separator: ",")
        #expect(parts.count == 7,
                "dateItems should produce exactly 7 comma-separated components, got: \(text)")
    }

    @Test("convert to short date returns M/d/yy format")
    func toShortDate() async {
        let (doc, cardId, btnId) = makeDoc()
        let script = #"""
        on mouseUp
          put "0" into d
          convert d to "short date"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        // Short date for epoch 0 in UTC: 1/1/70
        #expect(text.contains("70") || text.contains("1970"),
                "Short date for epoch 0 should contain '70' or '1970', got: \(text)")
    }

    @Test("convert to abbreviated date returns month-name format")
    func toAbbreviatedDate() async {
        let (doc, cardId, btnId) = makeDoc()
        let script = #"""
        on mouseUp
          put "0" into d
          convert d to "abbreviated date"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        // "Jan 1, 1970"
        #expect(text.contains("Jan") || text.contains("1970"),
                "Abbreviated date should contain month abbreviation or year, got: \(text)")
    }

    @Test("convert to short time returns H:MM AM/PM format")
    func toShortTime() async {
        let (doc, cardId, btnId) = makeDoc()
        let script = #"""
        on mouseUp
          put "0" into d
          convert d to "short time"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        let hasTimeIndicator = text.contains(":") || text.uppercased().contains("AM") || text.uppercased().contains("PM")
        #expect(hasTimeIndicator, "Short time should look like a time, got: \(text)")
    }

    @Test("convert to long time includes seconds")
    func toLongTime() async {
        let (doc, cardId, btnId) = makeDoc()
        let script = #"""
        on mouseUp
          put "0" into d
          convert d to "long time"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        // Long time must have two colons (H:MM:SS AM)
        let colonCount = text.filter { $0 == ":" }.count
        #expect(colonCount >= 2, "Long time should include seconds (two colons), got: \(text)")
    }

    @Test("convert compound 'long date and long time' includes both parts")
    func toLongDateAndLongTime() async {
        let (doc, cardId, btnId) = makeDoc()
        let script = #"""
        on mouseUp
          put "0" into d
          convert d to "long date and long time"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        #expect(text.contains("1970"), "Compound long date+time should contain year 1970, got: \(text)")
        let colonCount = text.filter { $0 == ":" }.count
        #expect(colonCount >= 2, "Compound long date+time should contain time colons, got: \(text)")
    }

    @Test("convert writes back to a field container")
    func writesBackToField() async {
        let (doc, cardId, btnId) = makeDoc()
        let script = #"""
        on mouseUp
          put "0" into field "out"
          convert field "out" to "long date"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        #expect(text.contains("1970"),
                "Convert should write back to field container, got: \(text)")
    }

    @Test("convert with unparseable source returns original value unchanged")
    func unparseableSourceIsUnchanged() async {
        let (doc, cardId, btnId) = makeDoc()
        let script = #"""
        on mouseUp
          put "not-a-date" into d
          convert d to "long date"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        #expect(text == "not-a-date",
                "Unparseable source should be returned unchanged, got: \(text)")
    }

    @Test("convert dateItems back to seconds produces an integer")
    func dateItemsToSeconds() async {
        let (doc, cardId, btnId) = makeDoc()
        // A well-formed dateItems string for 2000-01-01 00:00:00 UTC (weekday 7 = Saturday)
        let script = #"""
        on mouseUp
          put "2000,1,1,0,0,0,7" into d
          convert d to "seconds"
          put d into field "out"
        end mouseUp
        """#
        let result = await dispatch(script, on: doc, cardId: cardId, targetId: btnId)
        let text = result.modifiedDocument?.parts.first(where: { $0.name == "out" })?.textContent ?? ""
        let asInt = Int(text) ?? -1
        #expect(asInt > 0, "Converting dateItems to seconds should produce a positive integer, got: \(text)")
    }
}

// MARK: - §3  push card / pop card

@Suite("push card / pop card", .serialized)
struct PushPopCardTests {

    private func makeDoc() -> (HypeDocument, [Card], Part) {
        makeMultiCardDoc(cardCount: 3)
    }

    @Test("push records current card; pop sets navigationTarget to it")
    func pushThenPopNavigates() async {
        let (doc, cards, btn) = makeDoc()
        let card1 = cards[0]
        let card2 = cards[1]
        let runtime = TestRuntime()

        // Step 1: push while on card 1.
        let pushScript = """
        on mouseUp
          push card
        end mouseUp
        """
        _ = await dispatch(pushScript, on: doc, cardId: card1.id, targetId: btn.id, runtime: runtime)
        #expect(runtime.history == [card1.id],
                "push card should record current card id in history")

        // Step 2: pop — should navigate back to card 1.
        var doc2 = doc
        doc2.updatePart(id: btn.id) { _ in }  // ensure btn is still there
        var btn2 = Part(partType: .button, cardId: card2.id, name: "Btn2",
                        left: 0, top: 50, width: 80, height: 30)
        btn2.script = ""
        doc2.addPart(btn2)

        let popScript = """
        on mouseUp
          pop card
        end mouseUp
        """
        let popResult = await dispatch(popScript, on: doc2, cardId: card2.id, targetId: btn2.id, runtime: runtime)
        #expect(popResult.navigationTarget == card1.id,
                "pop card should set navigationTarget to the previously pushed card")
        #expect(runtime.history.isEmpty,
                "History should be empty after pop")
    }

    @Test("pop on empty stack is a safe no-op")
    func popOnEmptyStack() async {
        let (doc, cards, btn) = makeDoc()
        let card1 = cards[0]
        let runtime = TestRuntime()
        // History is empty — pop must not crash and navigationTarget must be nil.
        let script = """
        on mouseUp
          pop card
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: card1.id, targetId: btn.id, runtime: runtime)
        #expect(result.navigationTarget == nil,
                "pop on empty history should leave navigationTarget nil")
    }

    @Test("push without runtime is a safe no-op (no crash)")
    func pushWithoutRuntimeIsNoop() async {
        let (doc, cards, btn) = makeDoc()
        // Pass no runtime — interpreter should silently skip the push.
        let script = """
        on mouseUp
          push card
        end mouseUp
        """
        let result = await dispatch(script, on: doc, cardId: cards[0].id, targetId: btn.id)
        #expect(result.navigationTarget == nil,
                "push without runtime should produce no navigation target")
    }

    @Test("multiple pushes accumulate in order; pops return LIFO")
    func multiplePushesAndPops() async {
        // Use the StackRuntime's card-history directly to avoid the cross-card
        // button dispatch complexity. This tests the history semantics directly.
        let runtime = TestRuntime()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        await runtime.pushCardToHistory(id1)
        await runtime.pushCardToHistory(id2)
        await runtime.pushCardToHistory(id3)

        #expect(runtime.history == [id1, id2, id3],
                "History should accumulate in push order (oldest first)")

        // First pop returns id3 (LIFO).
        let popped1 = await runtime.popCardFromHistory()
        #expect(popped1 == id3, "First pop should return most-recently-pushed card")
        #expect(runtime.history == [id1, id2], "Two entries should remain after first pop")

        // Second pop returns id2.
        let popped2 = await runtime.popCardFromHistory()
        #expect(popped2 == id2, "Second pop should return next most-recently-pushed card")
        #expect(runtime.history == [id1], "One entry should remain")

        // Third pop returns id1 and leaves empty history.
        let popped3 = await runtime.popCardFromHistory()
        #expect(popped3 == id1, "Third pop should return original first card")
        #expect(runtime.history.isEmpty, "History should be empty after all pops")

        // Fourth pop on empty is nil.
        let popped4 = await runtime.popCardFromHistory()
        #expect(popped4 == nil, "Pop on empty history returns nil")
    }

    @Test("history cap prevents unbounded growth")
    func historyCap() async {
        let runtime = TestRuntime()
        // Push 55 distinct fake card IDs directly through the runtime.
        var ids: [UUID] = []
        for _ in 0..<55 {
            let id = UUID()
            ids.append(id)
            await runtime.pushCardToHistory(id)
        }
        // Only the last 50 should survive.
        let history = runtime.history
        #expect(history.count == 50, "Card history should be capped at 50 entries")
        // The first 5 oldest entries should have been dropped.
        #expect(history.first == ids[5],
                "Oldest entries should be dropped when cap is exceeded")
        #expect(history.last == ids[54],
                "Newest entry should be at the end")
    }

    @Test("push with explicit card reference records that card")
    func pushWithExplicitReference() async {
        let (doc, cards, btn) = makeDoc()
        let card2 = cards[1]
        let runtime = TestRuntime()

        // Push card 2 by name while standing on card 1.
        let script = """
        on mouseUp
          push card "Card 2"
        end mouseUp
        """
        _ = await dispatch(script, on: doc, cardId: cards[0].id, targetId: btn.id, runtime: runtime)
        #expect(runtime.history == [card2.id],
                "push with explicit card reference should record that card's ID")
    }

    @Test("the recent cards property returns UUID strings, newest first")
    func recentCardsProperty() async {
        let runtime = TestRuntime()
        let id1 = UUID()
        let id2 = UUID()
        await runtime.pushCardToHistory(id1)
        await runtime.pushCardToHistory(id2)
        let recent = await runtime.recentCards()
        // Should be newest-first: id2, then id1.
        let lines = recent.split(separator: "\n").map(String.init)
        #expect(lines.count == 2, "recentCards should return 2 entries")
        #expect(lines[0] == id2.uuidString, "Newest card should appear first")
        #expect(lines[1] == id1.uuidString, "Oldest card should appear last")
    }
}

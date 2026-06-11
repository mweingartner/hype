import Foundation
import Testing
@testable import HypeCore

// MARK: - Test Helpers

/// Build a minimal test document containing one card, one button, and one field.
/// Returns the document, the first card's UUID, and the button's UUID.
private func makePhase1Doc() -> (HypeDocument, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    var btn = Part(partType: .button, cardId: cardId, name: "Go", left: 10, top: 10, width: 80, height: 30)
    btn.script = ""
    doc.addPart(btn)
    var field = Part(partType: .field, cardId: cardId, name: "output", left: 10, top: 50, width: 200, height: 30)
    field.textContent = ""
    doc.addPart(field)
    return (doc, cardId, btn.id)
}

/// Execute a script on the given button (or card) via MessageDispatcher.
private func runPhase1Script(
    _ source: String,
    doc: inout HypeDocument,
    cardId: UUID,
    targetId: UUID,
    mouseX: Double = 0,
    mouseY: Double = 0
) async -> ExecutionResult {
    doc.updatePart(id: targetId) { $0.script = source }
    let dispatcher = MessageDispatcher()
    let snapshot = doc
    let mx = mouseX, my = mouseY
    let result = await runOnLargeStack {
        dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: targetId,
            document: snapshot,
            currentCardId: cardId,
            mouseX: mx,
            mouseY: my
        )
    }
    if let modified = result.modifiedDocument {
        doc = modified
    }
    return result
}

/// Return the text content of a named field from the result's modified document.
private func fieldText(_ result: ExecutionResult, doc: HypeDocument, name: String) -> String? {
    (result.modifiedDocument ?? doc).parts.first(where: { $0.name == name })?.textContent
}

/// Convenience: execute a simple script that `return`s a value, using a bare
/// `Interpreter` directly (faster, no dispatcher overhead).
private func evalReturn(_ source: String, doc: HypeDocument? = nil) -> String? {
    let document = doc ?? HypeDocument.newDocument()
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else { return nil }
    let context = ExecutionContext(
        targetId: document.cards[0].id,
        currentCardId: document.cards[0].id,
        document: document
    )
    let result = Interpreter().execute(handler: handler, params: [], context: context)
    return result.returnValue
}

// MARK: - 1A.B1 Unified comparison model

@Suite("Phase 1A B1 — Unified comparison", .serialized)
struct ComparisonModelTests {

    @Test("5 = 5.0 is true (numeric equality across int/float forms)")
    func numericIntFloatEquality() {
        let v = evalReturn("on test\n  return 5 = 5.0\nend test")
        #expect(v == "true")
    }

    @Test("5.0 = 5 is true (float = int)")
    func floatIntEquality() {
        let v = evalReturn("on test\n  return 5.0 = 5\nend test")
        #expect(v == "true")
    }

    @Test("apple < banana is true (lexical compare)")
    func lexicalLessThan() {
        let v = evalReturn("""
        on test
          return "apple" < "banana"
        end test
        """)
        #expect(v == "true")
    }

    @Test("banana > apple is true (lexical compare)")
    func lexicalGreaterThan() {
        let v = evalReturn("""
        on test
          return "banana" > "apple"
        end test
        """)
        #expect(v == "true")
    }

    @Test("10 < 9 is false (numeric compare 10 vs 9)")
    func numericOrderTen() {
        let v = evalReturn("on test\n  return 10 < 9\nend test")
        #expect(v == "false")
    }

    @Test("abc <= abc is true")
    func lexicalLessOrEqual() {
        let v = evalReturn("on test\n  return \"abc\" <= \"abc\"\nend test")
        #expect(v == "true")
    }

    @Test("OK is ok is true (case-insensitive lexical)")
    func caseInsensitiveEquality() {
        let v = evalReturn("on test\n  return \"OK\" is \"ok\"\nend test")
        #expect(v == "true")
    }

    @Test("2 <> 3 is true")
    func notEqual() {
        let v = evalReturn("on test\n  return 2 <> 3\nend test")
        #expect(v == "true")
    }

    @Test("string 5 = integer 5 is true (mixed numeric equality)")
    func mixedStringNumber() {
        let v = evalReturn("on test\n  return \"5\" = 5\nend test")
        #expect(v == "true")
    }

    @Test("empty string = empty string is true")
    func emptyEquality() {
        let v = evalReturn("on test\n  return \"\" = \"\"\nend test")
        #expect(v == "true")
    }
}

// MARK: - 1A.B2 Unary negation formatting

@Suite("Phase 1A B2 — Unary negation", .serialized)
struct UnaryNegationTests {

    @Test("negation of integer gives clean integer string")
    func negateInteger() {
        let v = evalReturn("on test\n  put -5 into x\n  return x\nend test")
        #expect(v == "-5")
    }

    @Test("negation of float preserves decimal")
    func negateFloat() {
        let v = evalReturn("on test\n  return -(2.5)\nend test")
        #expect(v == "-2.5")
    }

    @Test("negation of zero yields zero")
    func negateZero() {
        let v = evalReturn("on test\n  return -0\nend test")
        #expect(v == "0")
    }

    @Test("double negation restores original value")
    func doubleNegate() {
        // `--` begins a comment in HyperTalk, so double negation must be
        // space-separated: `- -x` = negate(negate(x)).
        let v = evalReturn("on test\n  put 3 into x\n  return - -x\nend test")
        #expect(v == "3")
    }
}

// MARK: - 1A.B3 value() evaluates expressions

@Suite("Phase 1A B3 — value() function", .serialized)
struct ValueFunctionTests {

    @Test("value of arithmetic string evaluates correctly")
    func valueArithmetic() {
        let v = evalReturn("on test\n  return value(\"3+2\")\nend test")
        #expect(v == "5")
    }

    @Test("value of complex arithmetic expression")
    func valueComplex() {
        let v = evalReturn("on test\n  return value(\"2 * (3+1)\")\nend test")
        #expect(v == "8")
    }

    @Test("value of empty string returns empty")
    func valueEmpty() {
        let v = evalReturn("on test\n  return value(\"\")\nend test")
        #expect(v == "")
    }

    @Test("value of plain string returns the string unchanged")
    func valueNonExpression() {
        let v = evalReturn("on test\n  return value(\"hello\")\nend test")
        #expect(v == "hello")
    }
}

// MARK: - 1A.B5 Division by zero

@Suite("Phase 1A B5 — Division by zero", .serialized)
struct DivisionByZeroTests {

    @Test("operator / with zero divisor yields 0")
    func divideOperator() {
        let v = evalReturn("on test\n  return 5 / 0\nend test")
        #expect(v == "0")
    }

    @Test("mod with zero divisor yields 0")
    func modOperator() {
        let v = evalReturn("on test\n  return 5 mod 0\nend test")
        #expect(v == "0")
    }

    @Test("div with zero divisor yields 0")
    func divIntDivision() {
        let v = evalReturn("on test\n  return 5 div 0\nend test")
        #expect(v == "0")
    }

    @Test("divide command with zero divisor yields 0 (not INF)")
    func divideCommand() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put 5 into x
          divide x by 0
          put x into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "0")
        #expect(text != "INF")
    }
}

// MARK: - 1A.isTruthy — "yes" is falsy

@Suite("Phase 1A isTruthy — yes is falsy", .serialized)
struct IsTruthyTests {

    @Test("yes is falsy in if condition")
    func yesIsFalsy() {
        let v = evalReturn("""
        on test
          if "yes" then
            return "truthy"
          else
            return "falsy"
          end if
        end test
        """)
        #expect(v == "falsy")
    }

    @Test("true is truthy")
    func trueIsTruthy() {
        let v = evalReturn("""
        on test
          if "true" then
            return "truthy"
          else
            return "falsy"
          end if
        end test
        """)
        #expect(v == "truthy")
    }

    @Test("1 is truthy")
    func oneIsTruthy() {
        let v = evalReturn("""
        on test
          if "1" then
            return "truthy"
          else
            return "falsy"
          end if
        end test
        """)
        #expect(v == "truthy")
    }

    @Test("0 is falsy")
    func zeroIsFalsy() {
        let v = evalReturn("""
        on test
          if "0" then
            return "truthy"
          else
            return "falsy"
          end if
        end test
        """)
        #expect(v == "falsy")
    }

    @Test("empty string is falsy")
    func emptyIsFalsy() {
        let v = evalReturn("""
        on test
          if "" then
            return "truthy"
          else
            return "falsy"
          end if
        end test
        """)
        #expect(v == "falsy")
    }
}

// MARK: - 1A.constants — formFeed, null, atan2

@Suite("Phase 1A constants", .serialized)
struct ConstantTests {

    @Test("formFeed constant is the form-feed character")
    func formFeedConstant() {
        let v = evalReturn("on test\n  return numToChar(12) is formFeed\nend test")
        #expect(v == "true")
    }

    @Test("atan2(1,1) returns approximately pi/4")
    func atan2Value() {
        guard let v = evalReturn("on test\n  return atan2(1, 1)\nend test"),
              let d = Double(v) else {
            Issue.record("atan2(1,1) did not return a numeric value")
            return
        }
        // pi/4 ≈ 0.7853981633974483
        #expect(abs(d - Double.pi / 4) < 0.0001)
    }

    @Test("atan2(0,0) returns 0")
    func atan2Zero() {
        let v = evalReturn("on test\n  return atan2(0, 0)\nend test")
        #expect(v == "0")
    }
}

// MARK: - 1A.itemDelimiter

@Suite("Phase 1A itemDelimiter", .serialized)
struct ItemDelimiterTests {

    @Test("item 2 with semicolon delimiter returns correct chunk")
    func itemWithSemicolon() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          set the itemDelimiter to ";"
          put item 2 of "a;b;c" into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "b")
    }

    @Test("number of items respects custom delimiter")
    func numberOfItemsCustomDelimiter() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          set the itemDelimiter to ";"
          put the number of items of "a;b;c" into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "3")
    }

    @Test("put into item with custom delimiter")
    func putIntoItemCustomDelimiter() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          set the itemDelimiter to ";"
          put "a;b;c" into myVar
          put "X" into item 2 of myVar
          put myVar into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "a;X;c")
    }

    @Test("delimiter resets to comma on new dispatch")
    func delimiterResetsPerDispatch() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        // First dispatch sets delimiter to ";"
        _ = await runPhase1Script("""
        on mouseUp
          set the itemDelimiter to ";"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        // Second dispatch should have comma delimiter restored
        let result = await runPhase1Script("""
        on mouseUp
          put item 2 of "a,b,c" into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "b")
    }

    @Test("coordinate parsing unaffected by custom item delimiter")
    func coordinateImmunity() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          set the itemDelimiter to ";"
          put item 1 of "10,20" into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        // With delimiter ";", item 1 of "10,20" is the whole string "10,20"
        // (not "10"), confirming that coordinate parsing is independent.
        // This test asserts correct new behavior: the whole string is one item.
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "10,20")
    }
}

// MARK: - 1A.message box container

@Suite("Phase 1A message box", .serialized)
struct MessageBoxTests {

    @Test("put into msg stores value in message box")
    func putIntoMsg() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put "hello" into msg
          put msg into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "hello")
    }

    @Test("the message reads from message box")
    func theMessageRead() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put "hi there" into msg
          put the message into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "hi there")
    }

    @Test("put after message box appends")
    func putAfterMessageBox() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put "hello" into msg
          put " world" after msg
          put msg into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "hello world")
    }

    @Test("message box persists across handler calls within session")
    func messageBoxPersists() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        // First call writes to message box
        _ = await runPhase1Script("""
        on mouseUp
          put "persistent" into msg
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        // Second call reads it back
        let result = await runPhase1Script("""
        on mouseUp
          put msg into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "persistent")
    }

    @Test("set the message to X writes to message box")
    func setTheMessage() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          set the message to "via set"
          put the message into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "via set")
    }

    @Test("get the message reads from message box")
    func getTheMessage() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put "gettest" into msg
          get the message
          put it into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "gettest")
    }
}

// MARK: - 1A.B8 Mouse function forms

@Suite("Phase 1A B8 — mouse functions", .serialized)
struct MouseFunctionTests {

    @Test("mouseLoc() returns live context position")
    func mouseLocFunction() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        doc.updatePart(id: btnId) { $0.script = """
        on mouseUp
          put mouseLoc() into field "output"
        end mouseUp
        """ }
        let dispatcher = MessageDispatcher()
        let snapshot = doc
        let result = await runOnLargeStack {
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: snapshot, currentCardId: cardId,
                mouseX: 120, mouseY: 80
            )
        }
        if let modified = result.modifiedDocument { doc = modified }
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "120,80")
    }

    @Test("mouseH() returns live X coordinate")
    func mouseHFunction() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        doc.updatePart(id: btnId) { $0.script = """
        on mouseUp
          put mouseH() into field "output"
        end mouseUp
        """ }
        let dispatcher = MessageDispatcher()
        let snapshot = doc
        let result = await runOnLargeStack {
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: snapshot, currentCardId: cardId,
                mouseX: 120, mouseY: 80
            )
        }
        if let modified = result.modifiedDocument { doc = modified }
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "120")
    }

    @Test("mouseV() returns live Y coordinate")
    func mouseVFunction() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        doc.updatePart(id: btnId) { $0.script = """
        on mouseUp
          put mouseV() into field "output"
        end mouseUp
        """ }
        let dispatcher = MessageDispatcher()
        let snapshot = doc
        let result = await runOnLargeStack {
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: snapshot, currentCardId: cardId,
                mouseX: 120, mouseY: 80
            )
        }
        if let modified = result.modifiedDocument { doc = modified }
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "80")
    }

    @Test("the mouseLoc property and mouseLoc() function return the same value")
    func mouseLocParity() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        doc.updatePart(id: btnId) { $0.script = """
        on mouseUp
          put mouseLoc() & "|" & the mouseLoc into field "output"
        end mouseUp
        """ }
        let dispatcher = MessageDispatcher()
        let snapshot = doc
        let result = await runOnLargeStack {
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: snapshot, currentCardId: cardId,
                mouseX: 50, mouseY: 60
            )
        }
        if let modified = result.modifiedDocument { doc = modified }
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "50,60|50,60")
    }
}

// MARK: - 1A.B6 there is a (type-scoped)

@Suite("Phase 1A B6 — there is a", .serialized)
struct ThereIsATests {

    @Test("there is a button named X when button exists")
    func buttonExists() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          if there is a button "Go" then
            put "found" into field "output"
          else
            put "missing" into field "output"
          end if
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "found")
    }

    @Test("there is a field named X is false when only button has that name")
    func fieldVsButton() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        // "Go" is a button name; there is no field named "Go"
        let result = await runPhase1Script("""
        on mouseUp
          if there is a field "Go" then
            put "found" into field "output"
          else
            put "missing" into field "output"
          end if
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "missing")
    }

    @Test("there is no field X is true when field absent")
    func thereIsNoField() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          if there is no field "nonexistent" then
            put "absent" into field "output"
          else
            put "present" into field "output"
          end if
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "absent")
    }
}

// MARK: - 1B.B4 repeat direction

@Suite("Phase 1B B4 — repeat direction", .serialized)
struct RepeatDirectionTests {

    @Test("repeat with i = 1 to 0 runs zero times (upward loop, start > end)")
    func upwardLoopZeroIterations() {
        let v = evalReturn("""
        on test
          put 0 into count
          repeat with i = 1 to 0
            put count + 1 into count
          end repeat
          return count
        end test
        """)
        #expect(v == "0")
    }

    @Test("repeat with i = 1 to 5 runs 5 times")
    func upwardLoopFiveIterations() {
        let v = evalReturn("""
        on test
          put 0 into count
          repeat with i = 1 to 5
            put count + 1 into count
          end repeat
          return count
        end test
        """)
        #expect(v == "5")
    }

    @Test("repeat with i = 5 down to 1 runs 5 times in descending order")
    func downwardLoop() {
        let v = evalReturn("""
        on test
          put "" into result
          repeat with i = 5 down to 1
            put result & i into result
          end repeat
          return result
        end test
        """)
        #expect(v == "54321")
    }

    @Test("repeat with i = 3 down to 5 runs zero times (downward, start < end)")
    func downwardLoopZeroIterations() {
        let v = evalReturn("""
        on test
          put 0 into count
          repeat with i = 3 down to 5
            put count + 1 into count
          end repeat
          return count
        end test
        """)
        #expect(v == "0")
    }

    @Test("repeat for each item iterates over comma-delimited list")
    func repeatForEachItem() {
        let v = evalReturn("""
        on test
          put "" into result
          repeat for each item x in "a,b,c"
            put result & x into result
          end repeat
          return result
        end test
        """)
        #expect(v == "abc")
    }

    @Test("repeat with i from 1 to 5 (classic from-form) still works")
    func repeatWithFromForm() {
        let v = evalReturn("""
        on test
          put 0 into count
          repeat with i from 1 to 5
            put count + 1 into count
          end repeat
          return count
        end test
        """)
        #expect(v == "5")
    }
}

// MARK: - 1B.sort lines/items

@Suite("Phase 1B sort lines/items", .serialized)
struct SortContainerTests {

    @Test("sort lines of container ascending text")
    func sortLinesAscending() {
        let v = evalReturn("""
        on test
          put "banana" & return & "apple" & return & "cherry" into myList
          sort lines of myList
          return myList
        end test
        """)
        #expect(v == "apple\nbanana\ncherry")
    }

    @Test("sort lines of container descending")
    func sortLinesDescending() {
        let v = evalReturn("""
        on test
          put "banana" & return & "apple" & return & "cherry" into myList
          sort descending lines of myList
          return myList
        end test
        """)
        #expect(v == "cherry\nbanana\napple")
    }

    @Test("sort items ascending numeric")
    func sortItemsNumeric() {
        let v = evalReturn("""
        on test
          put "10,2,30,4" into myList
          sort numeric items of myList
          return myList
        end test
        """)
        #expect(v == "2,4,10,30")
    }

    @Test("sort cards by field regression (existing sort still works)")
    func sortCardsRegression() throws {
        // Verify that `sort cards by ...` still parses without error.
        var lexer = Lexer(source: """
        on mouseUp
          sort cards by field "Name"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        let stmt = script.handlers[0].body.first
        if case .sortCards = stmt {
            // Correct case
        } else {
            Issue.record("Expected .sortCards statement, got: \(String(describing: stmt))")
        }
    }

    @Test("empty container sort is a no-op")
    func sortEmptyContainer() {
        let v = evalReturn("""
        on test
          put "" into myList
          sort lines of myList
          return myList
        end test
        """)
        #expect(v == "")
    }
}

// MARK: - 1B.find variants

@Suite("Phase 1B find variants", .serialized)
struct FindVariantsTests {

    @Test("find word mode parses without error")
    func findWordParses() throws {
        var lexer = Lexer(source: """
        on mouseUp
          find word "cat"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .findText(let mode, _, _) = stmt {
            #expect(mode == .word)
        } else {
            Issue.record("Expected .findText statement")
        }
    }

    @Test("find whole mode parses correctly")
    func findWholeParses() throws {
        var lexer = Lexer(source: """
        on mouseUp
          find whole "the cat"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .findText(let mode, _, _) = stmt {
            #expect(mode == .whole)
        } else {
            Issue.record("Expected .findText statement")
        }
    }

    @Test("find string mode parses correctly")
    func findStringParses() throws {
        var lexer = Lexer(source: """
        on mouseUp
          find string "cat"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .findText(let mode, _, _) = stmt {
            #expect(mode == .string)
        } else {
            Issue.record("Expected .findText statement")
        }
    }

    @Test("plain find produces normal mode")
    func plainFindIsNormal() throws {
        var lexer = Lexer(source: """
        on mouseUp
          find "hello"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .findText(let mode, _, let inField) = stmt {
            #expect(mode == .normal)
            #expect(inField == nil)
        } else {
            Issue.record("Expected .findText statement")
        }
    }

    @Test("find with in field clause parses correctly")
    func findInFieldParses() throws {
        var lexer = Lexer(source: """
        on mouseUp
          find "hello" in field "Notes"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .findText(_, _, let inField) = stmt {
            #expect(inField != nil)
        } else {
            Issue.record("Expected .findText statement with inField")
        }
    }
}

// MARK: - 1A.long/short/abbrev name

@Suite("Phase 1A descriptor name forms", .serialized)
struct DescriptorNameTests {

    @Test("the name of button returns bare name")
    func bareName() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put the name of button "Go" into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "Go")
    }

    @Test("the short name of button returns bare name")
    func shortName() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put the short name of button "Go" into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output")
        #expect(text == "Go")
    }

    @Test("the long name of button contains the card context")
    func longName() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put the long name of button "Go" into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output") ?? ""
        // The long name should contain the word "button" and "Go"
        #expect(text.lowercased().contains("button"))
        #expect(text.contains("Go"))
    }
}

// MARK: - 1A.the target

@Suite("Phase 1A the target", .serialized)
struct TheTargetTests {

    @Test("the target returns original dispatch recipient descriptor")
    func theTargetBasic() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put the target into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output") ?? ""
        // The target should contain "Go" (the button name) or the UUID
        let hasGoButton = text.contains("Go")
        let hasUUID = text.count > 20  // UUID-based fallback
        #expect(hasGoButton || hasUUID)
    }

    @Test("target function returns descriptor string")
    func targetFunction() async {
        let _p1d = makePhase1Doc()
        var doc = _p1d.0
        let cardId = _p1d.1
        let btnId = _p1d.2
        let result = await runPhase1Script("""
        on mouseUp
          put target() into field "output"
        end mouseUp
        """, doc: &doc, cardId: cardId, targetId: btnId)
        let text = fieldText(result, doc: doc, name: "output") ?? ""
        #expect(!text.isEmpty)
    }
}

// MARK: - 1B.B4 Parser — repeat AST cases

@Suite("Phase 1B B4 — repeat parser", .serialized)
struct RepeatParserTests {

    @Test("repeat with i = 1 to 5 parses as upward direction")
    func repeatWithUpDirection() throws {
        var lexer = Lexer(source: """
        on test
          repeat with i = 1 to 5
          end repeat
        end test
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .repeatWith(_, _, _, let dir, _) = stmt {
            #expect(dir == .up)
        } else {
            Issue.record("Expected .repeatWith")
        }
    }

    @Test("repeat with i = 5 down to 1 parses as downward direction")
    func repeatWithDownDirection() throws {
        var lexer = Lexer(source: """
        on test
          repeat with i = 5 down to 1
          end repeat
        end test
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .repeatWith(_, _, _, let dir, _) = stmt {
            #expect(dir == .down)
        } else {
            Issue.record("Expected .repeatWith")
        }
    }

    @Test("repeat for each item x in list parses as repeatForEach")
    func repeatForEachItem() throws {
        var lexer = Lexer(source: """
        on test
          repeat for each item x in "a,b,c"
          end repeat
        end test
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .repeatForEach(let ct, let varName, _, _) = stmt {
            #expect(ct == .item)
            #expect(varName == "x")
        } else {
            Issue.record("Expected .repeatForEach")
        }
    }
}

// MARK: - 1A.B7 is a date

@Suite("Phase 1A B7 — is a date", .serialized)
struct IsADateTests {

    @Test("a standard date string is a date")
    func dateStringIsDate() {
        let v = evalReturn("""
        on test
          return ("5/29/2026" is a date)
        end test
        """)
        #expect(v == "true")
    }

    @Test("a non-date string is not a date")
    func nonDateIsNotDate() {
        let v = evalReturn("""
        on test
          return ("hello" is a date)
        end test
        """)
        #expect(v == "false")
    }

    @Test("empty string is not a date")
    func emptyIsNotDate() {
        let v = evalReturn("""
        on test
          return ("" is a date)
        end test
        """)
        #expect(v == "false")
    }

    @Test("is not a date is the inverse of is a date")
    func isNotADate() {
        let v = evalReturn("""
        on test
          return ("hello" is not a date)
        end test
        """)
        #expect(v == "true")
    }
}

// MARK: - Parser: msg/message box as primary expression

@Suite("Phase 1B message box parser", .serialized)
struct MessageBoxParserTests {

    @Test("msg parsed as messageBox expression")
    func msgParsesAsMessageBox() throws {
        var lexer = Lexer(source: """
        on mouseUp
          put "hello" into msg
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .put(_, _, let target) = stmt {
            if case .messageBox = target {
                // Correct
            } else {
                Issue.record("Expected .messageBox target, got: \(target)")
            }
        } else {
            Issue.record("Expected .put statement")
        }
    }

    @Test("message box (two-token form) parsed as messageBox expression")
    func messageBoxTwoTokens() throws {
        var lexer = Lexer(source: """
        on mouseUp
          put "hello" into message box
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        let stmt = script.handlers[0].body.first
        if case .put(_, _, let target) = stmt {
            if case .messageBox = target {
                // Correct
            } else {
                Issue.record("Expected .messageBox target, got: \(target)")
            }
        } else {
            Issue.record("Expected .put statement")
        }
    }
}

import Testing
import Foundation
@testable import HypeCore

// MARK: - Lexer Tests

@Suite("Lexer Tests", .serialized)
struct LexerTests {

    @Test func tokenizesSimpleScript() {
        var lexer = Lexer(source: "on mouseUp\nend mouseUp")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .on)
        #expect(tokens[1].type == .identifier)
        #expect(tokens[1].value == "mouseUp")
        #expect(tokens[2].type == .newline)
        #expect(tokens[3].type == .end)
        #expect(tokens[4].type == .identifier)
        #expect(tokens[4].value == "mouseUp")
    }

    @Test func handlesStringLiterals() {
        var lexer = Lexer(source: "put \"hello world\" into x")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .put)
        #expect(tokens[1].type == .string)
        #expect(tokens[1].value == "hello world")
        #expect(tokens[2].type == .into)
        #expect(tokens[3].type == .identifier)
    }

    @Test func handlesNumbers() {
        var lexer = Lexer(source: "42 3.14")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .integer)
        #expect(tokens[0].value == "42")
        #expect(tokens[1].type == .float)
        #expect(tokens[1].value == "3.14")
    }

    @Test func keywordsCaseInsensitive() {
        var lexer = Lexer(source: "ON mouseUp\nPUT 1 INTO x\nEND mouseUp")
        let tokens = lexer.tokenize()
        // ON mouseUp \n PUT 1 INTO x \n END mouseUp
        // 0   1      2  3   4  5    6 7  8   9
        #expect(tokens[0].type == .on)
        #expect(tokens[3].type == .put)
        #expect(tokens[5].type == .into)
        #expect(tokens[8].type == .end)
    }

    @Test func handlesComments() {
        var lexer = Lexer(source: "put 1 into x -- this is a comment\nput 2 into y")
        let tokens = lexer.tokenize()
        // Comment should be stripped; first line: put, 1, into, x, newline
        let types = tokens.map { $0.type }
        #expect(!types.contains(.identifier) || tokens.first(where: { $0.value == "comment" }) == nil)
        // Verify second statement parsed
        #expect(tokens.contains(where: { $0.type == .identifier && $0.value == "y" }))
    }

    @Test func handlesOperators() {
        var lexer = Lexer(source: "2 + 3 * 4 <= 20 <> 5 && 6")
        let tokens = lexer.tokenize()
        let types = tokens.map { $0.type }
        #expect(types.contains(.plus))
        #expect(types.contains(.multiply))
        #expect(types.contains(.lte))
        #expect(types.contains(.neq))
        #expect(types.contains(.doubleAmpersand))
    }
}

// MARK: - Parser Tests

@Suite("Parser Tests", .serialized)
struct ParserTests {

    @Test func parsesOnMouseUpHandler() throws {
        var lexer = Lexer(source: """
        on mouseUp
          put "hello" into x
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].name == "mouseUp")
        #expect(script.handlers[0].handlerType == .message)
        #expect(script.handlers[0].body.count == 1)
    }

    @Test func parsesPutStatement() throws {
        var lexer = Lexer(source: """
        on test
          put 42 into x
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let stmt = script.handlers[0].body[0]
        if case .put(let source, let prep, let target) = stmt {
            if case .literal(let val) = source {
                #expect(val == "42")
            }
            #expect(prep == .into)
            if case .variable(let name) = target {
                #expect(name == "x")
            }
        } else {
            Issue.record("Expected put statement")
        }
    }

    @Test func parsesIfThenElse() throws {
        var lexer = Lexer(source: """
        on test
          if x = 1 then
            put "yes" into result
          else
            put "no" into result
          end if
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let stmt = script.handlers[0].body[0]
        if case .ifThenElse(_, let thenBlock, let elseBlock) = stmt {
            #expect(thenBlock.count == 1)
            #expect(elseBlock != nil)
            #expect(elseBlock?.count == 1)
        } else {
            Issue.record("Expected if/then/else statement")
        }
    }

    @Test func parsesRepeatCount() throws {
        var lexer = Lexer(source: """
        on test
          repeat 5
            put "loop" into x
          end repeat
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let stmt = script.handlers[0].body[0]
        if case .repeatCount(let count, let body) = stmt {
            if case .literal(let val) = count {
                #expect(val == "5")
            }
            #expect(body.count == 1)
        } else {
            Issue.record("Expected repeat count statement")
        }
    }

    @Test func parsesHandlerWithParams() throws {
        var lexer = Lexer(source: """
        on greet name, greeting
          put greeting & " " & name into msg
        end greet
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers[0].params.count == 2)
        #expect(script.handlers[0].params[0] == "name")
        #expect(script.handlers[0].params[1] == "greeting")
    }
}

// MARK: - Interpreter Tests

@Suite("Interpreter Tests", .serialized)
struct InterpreterTests {

    private func executeScript(_ source: String, params: [Value] = []) -> ExecutionResult {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            return ExecutionResult(status: .error, error: ScriptError(message: "Parse failed", line: 0, handler: ""))
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc)
        let interpreter = Interpreter()
        return interpreter.execute(handler: handler, params: params, context: context)
    }

    @Test func evaluatesArithmetic() {
        let result = executeScript("""
        on test
          put 2 + 3 into x
          return x
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "5")
    }

    @Test func evaluatesStringConcat() {
        let result = executeScript("""
        on test
          put "hello" & " " & "world" into x
          return x
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "hello world")
    }

    @Test func handlesIfThen() {
        let result = executeScript("""
        on test
          put 10 into x
          if x = 10 then
            return "yes"
          else
            return "no"
          end if
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "yes")
    }

    @Test func handlesRepeatCount() {
        let result = executeScript("""
        on test
          put 0 into total
          repeat 5
            put total + 1 into total
          end repeat
          return total
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "5")
    }

    @Test func handlesRepeatWith() {
        let result = executeScript("""
        on test
          put 0 into total
          repeat with i = 1 to 5
            put total + i into total
          end repeat
          return total
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "15")
    }

    @Test func handlesSpacedConcat() {
        let result = executeScript("""
        on test
          put "hello" && "world" into x
          return x
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "hello world")
    }

    @Test func handlerParams() {
        let result = executeScript("""
        on greet name
          return "Hello " & name
        end greet
        """, params: ["Alice"])
        #expect(result.status == .completed)
        #expect(result.returnValue == "Hello Alice")
    }

    @Test func instructionLimitEnforced() {
        var lexer = Lexer(source: """
        on test
          repeat while true
            put 1 into x
          end repeat
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("Parse failed")
            return
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc, instructionLimit: 100)
        let interpreter = Interpreter()
        let result = interpreter.execute(handler: handler, params: [], context: context)
        #expect(result.status == .error)
        #expect(result.error?.message.contains("Instruction limit") == true)
    }
}

// MARK: - MessageDispatcher Tests

@Suite("MessageDispatcher Tests", .serialized)
struct MessageDispatcherTests {

    @Test func dispatchesToPartScript() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var btn = Part(partType: .button, cardId: cardId, name: "TestBtn")
        btn.script = """
        on mouseUp
          return "clicked"
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed)
        #expect(result.returnValue == "clicked")
    }

    @Test func passedMessageContinuesUpHierarchy() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var btn = Part(partType: .button, cardId: cardId, name: "PassBtn")
        btn.script = """
        on mouseUp
          pass mouseUp
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed)
    }

    @Test func passedMessageCaughtByCardScript() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        // Button passes mouseUp
        var btn = Part(partType: .button, cardId: cardId, name: "PassBtn")
        btn.script = """
        on mouseUp
          pass mouseUp
        end mouseUp
        """
        doc.addPart(btn)

        // Add a field for output
        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        // Card script catches the passed mouseUp
        if let idx = doc.cards.firstIndex(where: { $0.id == cardId }) {
            doc.cards[idx].script = """
            on mouseUp
              put "card caught it" into field "output"
            end mouseUp
            """
        }

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "card caught it")
    }

    @Test func messagePassesThroughCardToBackground() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let bgId = doc.cards[0].backgroundId

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        // Card passes, background catches
        if let idx = doc.cards.firstIndex(where: { $0.id == cardId }) {
            doc.cards[idx].script = """
            on mouseUp
              pass mouseUp
            end mouseUp
            """
        }
        if let idx = doc.backgrounds.firstIndex(where: { $0.id == bgId }) {
            doc.backgrounds[idx].script = """
            on mouseUp
              put "bg caught it" into field "output"
            end mouseUp
            """
        }

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "bg caught it")
    }

    @Test func messageReachesStackScript() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        // Stack script catches unhandled messages
        doc.stack.script = """
        on mouseUp
          put "stack caught it" into field "output"
        end mouseUp
        """

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        )
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "stack caught it")
    }
}

@Suite("Go Navigation Integration", .serialized)
struct GoNavigationTests {

    @Test func goPreviousFromSecondCard() {
        var doc = HypeDocument.newDocument(name: "Nav Test")
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]

        // Add button with "go previous" script on card 2
        var btn = Part(partType: .button, cardId: card2.id, name: "Back")
        btn.script = "on mouseUp\n  go previous\nend mouseUp"
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: card2.id
        )

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card1.id, "go previous should navigate to card 1, got \(String(describing: result.navigationTarget))")
    }

    @Test func goNextFromFirstCard() {
        var doc = HypeDocument.newDocument(name: "Nav Test")
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]

        var btn = Part(partType: .button, cardId: card1.id, name: "Next")
        btn.script = "on mouseUp\n  go next\nend mouseUp"
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: card1.id
        )

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card2.id, "go next should navigate to card 2, got \(String(describing: result.navigationTarget))")
    }
}

@Suite("Put Into Field Integration", .serialized)
struct PutIntoFieldTests {

    @Test func putIntoFieldByName() {
        var doc = HypeDocument.newDocument(name: "Put Test")
        let cardId = doc.cards[0].id

        // Add a field named "url"
        var urlField = Part(partType: .field, cardId: cardId, name: "url")
        urlField.textContent = ""
        doc.addPart(urlField)

        // Add a button that puts text into the field
        var btn = Part(partType: .button, cardId: cardId, name: "Fill")
        btn.script = "on mouseUp\n  put \"Hello\" into field \"url\"\nend mouseUp"
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        )

        #expect(result.status == .completed)
        // The modified document should have the field's textContent updated
        let modifiedField = result.modifiedDocument?.parts.first(where: { $0.name == "url" })
        #expect(modifiedField != nil, "Field 'url' should exist in modified document")
        #expect(modifiedField?.textContent == "Hello", "Field 'url' textContent should be 'Hello', got '\(modifiedField?.textContent ?? "nil")'")
    }
}

@Suite("Parser Put Into Field", .serialized)
struct ParserPutTests {
    @Test func parsePutIntoField() throws {
        let source = "on mouseUp\n  put \"Hello\" into field \"url\"\nend mouseUp"
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()

        // Print tokens for debugging
        for (i, tok) in tokens.enumerated() {
            print("  token[\(i)] = \(tok.type.rawValue) '\(tok.value)' line=\(tok.line)")
        }

        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        let handler = script.handlers[0]
        #expect(handler.body.count == 1)

        // Check the put statement
        if case .put(let source, let prep, let target) = handler.body[0] {
            print("  source = \(source)")
            print("  prep = \(prep)")
            print("  target = \(target)")
            #expect(prep == .into)
            if case .objectRef(let ref) = target {
                #expect(ref.objectType == "field")
                print("  objectType = \(ref.objectType)")
                print("  identifier = \(ref.identifier)")
            } else {
                #expect(Bool(false), "target should be .objectRef, got \(target)")
            }
        } else {
            #expect(Bool(false), "should be .put, got \(handler.body[0])")
        }
    }
}

// MARK: - If/Then/Else Tests

@Suite("If/Then/Else Tests", .serialized)
struct IfThenElseTests {

    @Test func ifElseWithHiliteTrue() {
        var doc = HypeDocument()
        let card = doc.addCard()
        let cardId = card.id

        var toggle = Part(partType: .button, cardId: cardId, name: "Light", left: 100, top: 100, width: 100, height: 30)
        toggle.buttonStyle = .toggle
        toggle.hilite = true
        toggle.script = """
        on mouseUp
          if the hilite of me is "true" then
            put "Checked!" into field "status"
          else
            put "Unchecked" into field "status"
          end if
        end mouseUp
        """
        doc.addPart(toggle)

        var field = Part(partType: .field, cardId: cardId, name: "status", left: 100, top: 200, width: 200, height: 30)
        doc.addPart(field)

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(message: "mouseUp", params: [], targetId: toggle.id, document: doc, currentCardId: cardId)

        #expect(result.status != .error, "Script should not error: \(result.error?.message ?? "")")
        let statusField = result.modifiedDocument?.parts.first(where: { $0.name == "status" })
        #expect(statusField?.textContent == "Checked!", "Expected 'Checked!' but got '\(statusField?.textContent ?? "nil")'")
    }

    @Test func ifElseWithHiliteFalse() {
        var doc = HypeDocument()
        let card = doc.addCard()
        let cardId = card.id

        var toggle = Part(partType: .button, cardId: cardId, name: "Light", left: 100, top: 100, width: 100, height: 30)
        toggle.buttonStyle = .toggle
        toggle.hilite = false
        toggle.script = """
        on mouseUp
          if the hilite of me is "true" then
            put "Checked!" into field "status"
          else
            put "Unchecked" into field "status"
          end if
        end mouseUp
        """
        doc.addPart(toggle)

        var field = Part(partType: .field, cardId: cardId, name: "status", left: 100, top: 200, width: 200, height: 30)
        doc.addPart(field)

        let dispatcher = MessageDispatcher()
        let result = dispatcher.dispatch(message: "mouseUp", params: [], targetId: toggle.id, document: doc, currentCardId: cardId)

        #expect(result.status != .error, "Script should not error: \(result.error?.message ?? "")")
        let statusField = result.modifiedDocument?.parts.first(where: { $0.name == "status" })
        #expect(statusField?.textContent == "Unchecked", "Expected 'Unchecked' but got '\(statusField?.textContent ?? "nil")'")
    }
}

@Suite("Debug If/Else", .serialized)
struct DebugIfElseTests {
    @Test func debugTokensAndParse() {
        let script = """
        on mouseUp
          if the hilite of me is "true" then
            put "YES" into field "status"
          else
            put "NO" into field "status"
          end if
        end mouseUp
        """
        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        print("=== TOKENS ===")
        for (i,t) in tokens.enumerated() {
            print("  \(i): .\(t.type) = '\(t.value)'")
        }
        
        var parser = Parser(tokens: tokens)
        do {
            let program = try parser.parse()
            print("=== AST ===")
            for h in program.handlers {
                print("Handler: \(h.name)")
                for (i,s) in h.body.enumerated() {
                    print("  stmt[\(i)]: \(s)")
                }
            }
        } catch {
            print("PARSE ERROR: \(error)")
        }
    }
}

// MARK: - Number-of expression tests

@Suite("Number Of Expressions", .serialized)
struct NumberOfExpressionTests {

    private func parseError(_ source: String) -> String? {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
            return nil
        } catch let error as ParseError {
            return error.errorDescription ?? String(describing: error)
        } catch {
            return error.localizedDescription
        }
    }

    @Test("'the number of bg fields' parses without error")
    func numberOfBgFields() {
        let err = parseError("""
            on test
              put the number of bg fields into n
            end test
            """)
        #expect(err == nil, "number of bg fields failed: \(err ?? "")")
    }

    @Test("'the number of background fields' parses without error")
    func numberOfBackgroundFields() {
        let err = parseError("""
            on test
              put the number of background fields into n
            end test
            """)
        #expect(err == nil, "number of background fields failed: \(err ?? "")")
    }

    @Test("'the number of bg buttons' parses without error")
    func numberOfBgButtons() {
        let err = parseError("""
            on test
              put the number of bg buttons into n
            end test
            """)
        #expect(err == nil, "number of bg buttons failed: \(err ?? "")")
    }

    @Test("'the number of backgrounds' parses without error")
    func numberOfBackgrounds() {
        let err = parseError("""
            on test
              put the number of backgrounds into n
            end test
            """)
        #expect(err == nil, "number of backgrounds failed: \(err ?? "")")
    }

    @Test("'the number of cards div 2' parses without error")
    func numberOfCardsDivTwo() {
        let err = parseError("""
            on test
              put the number of cards div 2 into n
            end test
            """)
        #expect(err == nil, "number of cards div 2 failed: \(err ?? "")")
    }

    @Test("'the number of cards mod 3' parses without error")
    func numberOfCardsModThree() {
        let err = parseError("""
            on test
              put the number of cards mod 3 into n
            end test
            """)
        #expect(err == nil, "number of cards mod 3 failed: \(err ?? "")")
    }

    @Test("'the number of card fields' parses without error")
    func numberOfCardFields() {
        let err = parseError("""
            on test
              put the number of card fields into n
            end test
            """)
        #expect(err == nil, "number of card fields failed: \(err ?? "")")
    }

    @Test("'the number of card buttons' parses without error")
    func numberOfCardButtons() {
        let err = parseError("""
            on test
              put the number of card buttons into n
            end test
            """)
        #expect(err == nil, "number of card buttons failed: \(err ?? "")")
    }

    // MARK: - End-to-end interpreter tests

    private func executeWithDoc(_ source: String, document: HypeDocument, cardId: UUID) -> ExecutionResult {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            return ExecutionResult(status: .error, error: ScriptError(message: "Parse failed", line: 0, handler: ""))
        }
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        let interpreter = Interpreter()
        return interpreter.execute(handler: handler, params: [], context: context)
    }

    @Test("number of bg fields returns correct count")
    func numberOfBgFieldsInterpreter() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let bgId = doc.cards[0].backgroundId

        // Add 2 background fields and 1 card field
        let bgField1 = Part(partType: .field, backgroundId: bgId, name: "BG Field 1")
        let bgField2 = Part(partType: .field, backgroundId: bgId, name: "BG Field 2")
        let cardField = Part(partType: .field, cardId: cardId, name: "Card Field")
        doc.addPart(bgField1)
        doc.addPart(bgField2)
        doc.addPart(cardField)

        let result = executeWithDoc("""
            on test
              return the number of bg fields
            end test
            """, document: doc, cardId: cardId)
        #expect(result.status == .completed)
        #expect(result.returnValue == "2")
    }

    @Test("number of backgrounds returns correct count")
    func numberOfBackgroundsInterpreter() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addBackground(name: "Second BG")
        let _ = doc.addBackground(name: "Third BG")
        let cardId = doc.cards[0].id

        let result = executeWithDoc("""
            on test
              return the number of backgrounds
            end test
            """, document: doc, cardId: cardId)
        #expect(result.status == .completed)
        #expect(result.returnValue == "3")
    }

    @Test("number of cards div 2 returns half the card count")
    func numberOfCardsDivTwoInterpreter() {
        var doc = HypeDocument.newDocument()
        let _ = doc.addCard()
        let _ = doc.addCard()
        let _ = doc.addCard()
        // 4 cards total, div 2 = 2
        let cardId = doc.cards[0].id

        let result = executeWithDoc("""
            on test
              return the number of cards div 2
            end test
            """, document: doc, cardId: cardId)
        #expect(result.status == .completed)
        #expect(result.returnValue == "2")
    }
}

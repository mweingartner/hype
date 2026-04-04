import Testing
import Foundation
@testable import HypeCore

// MARK: - Lexer Tests

@Suite("Lexer Tests")
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

@Suite("Parser Tests")
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

@Suite("Interpreter Tests")
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

@Suite("MessageDispatcher Tests")
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

        // No card script (cards don't have scripts yet), so the message
        // should ultimately complete without a handler catching it.
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
}

import AppKit
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

    @Test func keepsSmartQuotesInsideStraightStringLiterals() {
        var lexer = Lexer(source: "answer \"Drag \u{201C}Myst\u{201D} to your hard disk\" with \"Quit\"")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .answer)
        #expect(tokens[1].type == .string)
        #expect(tokens[1].value == "Drag \u{201C}Myst\u{201D} to your hard disk")
        #expect(tokens[2].type == .with)
        #expect(tokens[3].type == .string)
        #expect(tokens[3].value == "Quit")
    }

    @Test func handlesSmartQuotedStringLiterals() {
        var lexer = Lexer(source: "put \u{201C}hello world\u{201D} into x")
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

    @Test func handlesClassicMacComments() {
        var lexer = Lexer(source: "put 1 into x -- this is a comment\rput 2 into y")
        let tokens = lexer.tokenize()
        #expect(tokens.first(where: { $0.value == "comment" }) == nil)
        #expect(tokens.contains(where: { $0.type == .identifier && $0.value == "y" }))
    }

    @Test func handlesClassicMacLineContinuation() {
        var lexer = Lexer(source: "put \"hello\" & \\\r\" world\" into message")
        let tokens = lexer.tokenize()
        let types = tokens.map(\.type)
        #expect(types.filter { $0 == .newline }.count == 1)
        #expect(tokens.contains(where: { $0.type == .string && $0.value == " world" }))
    }

    @Test func handlesClassicMacNotSignLineContinuation() {
        var lexer = Lexer(source: "play \"GR Ratchet\" tempo 100 c6 c6 \u{00AC}\rc6 c6")
        let tokens = lexer.tokenize()
        let c6Tokens = tokens.filter { $0.type == .identifier && $0.value == "c6" }
        #expect(c6Tokens.count == 4)
        #expect(tokens.filter { $0.type == .newline }.count == 1)
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

    @Test func handlesClassicComparisonGlyphOperators() {
        var lexer = Lexer(source: "if it \u{2265} 9 then\nif it \u{2264} 10 then\nif it \u{2260} 0 then")
        let tokens = lexer.tokenize()
        let types = tokens.map { $0.type }
        #expect(types.contains(.gte))
        #expect(types.contains(.lte))
        #expect(types.contains(.neq))
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

    @Test func parsesSceneDidLoadHandler() throws {
        var lexer = Lexer(source: """
        on sceneDidLoad
          put "loaded" into status
        end sceneDidLoad
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].name == "sceneDidLoad")
        #expect(script.handlers[0].handlerType == .message)
    }

    @Test func parsesClassicMacLineEndings() throws {
        var lexer = Lexer(source: "on mouseUp\r  put 1 into x -- comment\r  put 2 into y\rend mouseUp")
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].body.count == 2)
    }

    @Test func parsesWindowsLineEndingsAsSingleNewlines() throws {
        var lexer = Lexer(source: "on mouseUp\r\n  put 1 into x\r\n  put 2 into y\r\nend mouseUp")
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].body.count == 2)
    }

    @Test func parsesCrossStackGoStatement() throws {
        var lexer = Lexer(source: """
        on mouseUp
          go to card "black" of stack "Myst"
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .goInStack(let cardExpr, let stackExpr) = script.handlers[0].body[0] else {
            Issue.record("Expected goInStack statement")
            return
        }
        guard case .literal(let cardName) = cardExpr else {
            Issue.record("Expected literal card expression")
            return
        }
        guard case .literal(let stackName) = stackExpr else {
            Issue.record("Expected literal stack expression")
            return
        }
        #expect(cardName == "black")
        #expect(stackName == "Myst")
    }

    @Test func parsesClassicCrossStackGoVariants() throws {
        let cases = [
            ("go card 1 of stack \" Myst\"", "1", " Myst"),
            ("go card black in stack Myst", "black", "Myst"),
            ("go to stack charFile", "1", "charFile"),
        ]
        for (command, expectedCard, expectedStack) in cases {
            var lexer = Lexer(source: """
            on mouseUp
              \(command)
            end mouseUp
            """)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            let script = try parser.parse()
            guard case .goInStack(let cardExpr, let stackExpr) = script.handlers[0].body[0] else {
                Issue.record("Expected goInStack statement for \(command)")
                continue
            }
            guard case .literal(let cardValue) = cardExpr else {
                Issue.record("Expected literal card expression for \(command)")
                continue
            }
            let stackValue: String
            switch stackExpr {
            case .literal(let value), .variable(let value):
                stackValue = value
            default:
                Issue.record("Expected literal or variable stack expression for \(command)")
                continue
            }
            #expect(cardValue == expectedCard)
            #expect(stackValue == expectedStack)
        }
    }

    @Test func parsesZeroArgumentMystExternalCommands() throws {
        var lexer = Lexer(source: """
        on mouseUp
          closemoovs
          HTRemove
          vd
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .externalCommand(let name, let arguments) = script.handlers[0].body[0] else {
            Issue.record("Expected closemoovs external command")
            return
        }
        #expect(name == "closemoovs")
        #expect(arguments.isEmpty)
        guard case .externalCommand(let removeName, let removeArguments) = script.handlers[0].body[1] else {
            Issue.record("Expected HTRemove external command")
            return
        }
        #expect(removeName == "HTRemove")
        #expect(removeArguments.isEmpty)
        guard case .externalCommand(let visualName, let visualArguments) = script.handlers[0].body[2] else {
            Issue.record("Expected vd external command")
            return
        }
        #expect(visualName == "vd")
        #expect(visualArguments.isEmpty)
    }

    @Test func parsesClassicPlayQTAsQuickTimeExternalCommand() throws {
        var lexer = Lexer(source: """
        on mouseUp
          play QT "EV Wind/Water Mov", , loop, 250
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .externalCommand(let name, let arguments) = script.handlers[0].body[0] else {
            Issue.record("Expected playQT external command")
            return
        }
        #expect(name == "playQT")
        #expect(arguments.count == 3)
        guard case .literal(let movieName) = arguments[0] else {
            Issue.record("Expected movie-name literal")
            return
        }
        #expect(movieName == "EV Wind/Water Mov")
        guard case .variable(let loopFlag) = arguments[1] else {
            Issue.record("Expected bare loop flag")
            return
        }
        #expect(loopFlag == "loop")
        guard case .literal(let rate) = arguments[2] else {
            Issue.record("Expected playback-rate literal")
            return
        }
        #expect(rate == "250")
    }

    @Test func parsesClassicCameraAsExternalCommand() throws {
        var lexer = Lexer(source: """
        on mouseWithin
          camera SE_CameraID
        end mouseWithin
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()

        guard case .externalCommand(let name, let arguments) = script.handlers[0].body[0] else {
            Issue.record("Expected camera external command")
            return
        }
        #expect(name == "camera")
        #expect(arguments.count == 1)
        guard case .variable(let cameraVariable) = arguments[0] else {
            Issue.record("Expected camera variable argument")
            return
        }
        #expect(cameraVariable == "SE_CameraID")
    }

    @Test func parsesClassicPictureExternalCommandsWithParenthesizedArguments() throws {
        var lexer = Lexer(source: """
        on mouseUp
          HTAddPict (field "pict name" & " (open)"),¬
            the rect of card button marker, "srccopy"
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .externalCommand(let name, let arguments) = script.handlers[0].body[0] else {
            Issue.record("Expected HTAddPict external command")
            return
        }
        #expect(name == "HTAddPict")
        #expect(arguments.count == 3)
    }

    @Test func parsesClassicDoMenuAndSaveAsCommands() throws {
        var lexer = Lexer(source: """
        on mouseUp
          doMenu "next window"
          save stack "Myst:Myst Graphics:Template" as charFile
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .doMenuCmd(let item) = script.handlers[0].body[0] else {
            Issue.record("Expected doMenu command")
            return
        }
        guard case .literal(let itemName) = item else {
            Issue.record("Expected literal doMenu item")
            return
        }
        #expect(itemName == "next window")
        guard case .saveStack = script.handlers[0].body[1] else {
            Issue.record("Expected save stack command")
            return
        }
        #expect(script.handlers[0].body.count == 2)
    }

    @Test func parsesClassicOpenStateAsExpressionLiteral() throws {
        var lexer = Lexer(source: """
        on mouseUp
          if drawer is open then put closed into drawer
          put open into drawer
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers[0].body.count == 2)
        guard case .ifThenElse(let condition, _, _) = script.handlers[0].body[0],
              case .binary(_, let op, let rhs) = condition else {
            Issue.record("Expected open-state comparison")
            return
        }
        #expect(op == .equal)
        guard case .literal(let state) = rhs else {
            Issue.record("Expected open state literal")
            return
        }
        #expect(state == "open")
        guard case .put(let source, _, _) = script.handlers[0].body[1],
              case .literal(let putState) = source else {
            Issue.record("Expected put open literal")
            return
        }
        #expect(putState == "open")
    }

    @Test func parsesAskWithDefaultResponse() throws {
        var lexer = Lexer(source: """
        on mouseUp
          ask "go where?" with "0,0"
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .ask(let prompt, let defaultResponse) = script.handlers[0].body[0] else {
            Issue.record("Expected ask statement")
            return
        }
        guard case .literal(let promptValue) = prompt else {
            Issue.record("Expected literal prompt")
            return
        }
        guard case .literal(let defaultValue)? = defaultResponse else {
            Issue.record("Expected literal default response")
            return
        }
        #expect(promptValue == "go where?")
        #expect(defaultValue == "0,0")
    }

    @Test func parsesClassicAskFileWithDefault() throws {
        var lexer = Lexer(source: """
        on mouseUp
          ask File "Save Myst game as..." with it
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .ask(let prompt, let defaultResponse) = script.handlers[0].body[0] else {
            Issue.record("Expected ask file statement")
            return
        }
        guard case .literal(let promptValue) = prompt else {
            Issue.record("Expected literal file prompt")
            return
        }
        guard defaultResponse != nil else {
            Issue.record("Expected default response expression")
            return
        }
        #expect(promptValue == "Save Myst game as...")
    }

    @Test func parsesClassicFieldOfCardReference() throws {
        var lexer = Lexer(source: """
        on mouseUp
          put card field "Defaults" of card "Defaults" into RestoreData
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .put(let source, _, let target) = script.handlers[0].body[0] else {
            Issue.record("Expected put statement")
            return
        }
        guard case .scopedObjectRef(let object, let owner) = source else {
            Issue.record("Expected scoped field reference")
            return
        }
        #expect(object.objectType == "field")
        #expect(owner.objectType == "card")
        guard case .variable(let variableName) = target else {
            Issue.record("Expected RestoreData target variable")
            return
        }
        #expect(variableName == "RestoreData")
    }

    @Test func parsesClassicBarePropertyOfObjectReferences() throws {
        var lexer = Lexer(source: """
        on mouseUp
          if visible of card button openElevator is false then go to card id 41669
          get rect of card button thedoor
          get loc of me
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers[0].body.count == 3)
        guard case .ifThenElse(let condition, _, _) = script.handlers[0].body[0],
              case .binary(let lhs, let op, _) = condition,
              case .propertyAccess(let visibleProperty, let visibleTarget?) = lhs,
              case .scopedObjectRef(let visibleRef, let visibleOwner) = visibleTarget else {
            Issue.record("Expected visible property check")
            return
        }
        #expect(op == .equal)
        #expect(visibleProperty == "visible")
        #expect(visibleRef.objectType == "button")
        #expect(visibleOwner.objectType == "card")
        guard case .get(let rectExpr) = script.handlers[0].body[1],
              case .propertyAccess(let rectProperty, let rectTarget?) = rectExpr,
              case .scopedObjectRef(let rectRef, let rectOwner) = rectTarget else {
            Issue.record("Expected rect property get")
            return
        }
        #expect(rectProperty == "rect")
        #expect(rectRef.objectType == "button")
        #expect(rectOwner.objectType == "card")
        guard case .get(let locExpr) = script.handlers[0].body[2],
              case .propertyAccess(let locProperty, let locTarget?) = locExpr,
              case .me = locTarget else {
            Issue.record("Expected loc of me property get")
            return
        }
        #expect(locProperty == "loc")
    }

    @Test func parsesAnswerWithClassicButtonList() throws {
        var lexer = Lexer(source: """
        on mouseUp
          answer "Do you want to save this game before starting a new game?" with "Cancel" or "Don't Save" or "Save"
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .answer(let prompt, let buttons) = script.handlers[0].body[0] else {
            Issue.record("Expected answer statement")
            return
        }
        guard case .literal(let promptValue) = prompt else {
            Issue.record("Expected literal answer prompt")
            return
        }
        #expect(promptValue == "Do you want to save this game before starting a new game?")
        #expect(buttons.count == 1)
    }

    @Test func parsesMystAnswerWithSmartQuotesInsidePrompt() throws {
        var lexer = Lexer(source: """
        on startup
          answer "You have to start Myst from your hard disk. Drag \u{201C}Myst\u{201D} to your hard disk and try again. (Check instructions for more info.)" with "Quit"
        end startup
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .answer(let prompt, let buttons) = script.handlers[0].body[0] else {
            Issue.record("Expected answer statement")
            return
        }
        guard case .literal(let promptValue) = prompt else {
            Issue.record("Expected literal answer prompt")
            return
        }
        #expect(promptValue == "You have to start Myst from your hard disk. Drag \u{201C}Myst\u{201D} to your hard disk and try again. (Check instructions for more info.)")
        #expect(buttons.count == 1)
        guard case .literal(let buttonValue) = buttons[0] else {
            Issue.record("Expected literal answer button")
            return
        }
        #expect(buttonValue == "Quit")
    }

    @Test func parsesClassicAnswerFileOfType() throws {
        var lexer = Lexer(source: """
        on mouseUp
          answer File "Restore Myst to..." of type "STAK"
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .answer(let prompt, _) = script.handlers[0].body[0] else {
            Issue.record("Expected answer file statement")
            return
        }
        guard case .literal(let promptValue) = prompt else {
            Issue.record("Expected literal file prompt")
            return
        }
        #expect(promptValue == "Restore Myst to...")
    }

    @Test func parsesMystExternalCommandsWithClassicSpacing() throws {
        var lexer = Lexer(source: """
        on mouseUp
          htlock"bw"
          HTVisual "wipe right",,,1,32
          deCurse "override",2003,"color","nodelay"
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .externalCommand(let lockName, let lockArguments) = script.handlers[0].body[0],
              case .externalCommand(let visualName, let visualArguments) = script.handlers[0].body[1],
              case .externalCommand(let cursorName, let cursorArguments) = script.handlers[0].body[2] else {
            Issue.record("Expected Myst external commands")
            return
        }
        #expect(lockName == "htlock")
        #expect(lockArguments.count == 1)
        #expect(visualName == "HTVisual")
        #expect(visualArguments.count == 3)
        #expect(cursorName == "deCurse")
        #expect(cursorArguments.count == 4)
    }

    @Test func parsesMovieWindowPropertySet() throws {
        var lexer = Lexer(source: """
        on mouseUp
          set the loop of window TheMovieName to true
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .set(let property, let target, _) = script.handlers[0].body[0],
              case .objectRef(let ref) = target else {
            Issue.record("Expected movie window property set")
            return
        }
        #expect(property == "loop")
        #expect(ref.objectType == "window")
    }

    @Test func topLevelGlobalPreludeAppliesToEveryHandler() throws {
        var lexer = Lexer(source: """
        global moveDir, score
        global px

        on openScene
          put 1 into score
        end openScene

        on keyDown
          add 1 to score
        end keyDown
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers.count == 2)
        for handler in script.handlers {
            guard case .globalDecl(let names) = handler.body.first else {
                Issue.record("Expected top-level global prelude to be injected into \(handler.name)")
                continue
            }
            #expect(names == ["moveDir", "score", "px"])
        }
    }

    @Test func topLevelExecutableStatementsAreStillRejected() throws {
        var lexer = Lexer(source: """
        put 1 into score

        on openScene
          put score into field "status"
        end openScene
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        #expect(throws: ParseError.self) {
            try parser.parse()
        }
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

    @Test func parsesIfThenElse() async throws {
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

    @Test func parsesTrailingClassicIfClosedByHandlerEnd() throws {
        var lexer = Lexer(source: """
        on mouseUp
          global st_pump
          if st_pump is 3 then
            go to card id 21557
          else go to card id 13528
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].body.count == 2)
        guard case .ifThenElse(_, let thenBlock, let elseBlock) = script.handlers[0].body[1] else {
            Issue.record("Expected trailing if/then/else statement")
            return
        }
        #expect(thenBlock.count == 1)
        #expect(elseBlock?.count == 1)
    }

    @Test func parsesSingleLineIfWithFollowingLineElseIf() async throws {
        var lexer = Lexer(source: """
        on test
          if route is "P" then put "p" into result
          else if route is "Q" then put "q" into result
          else put "fallback" into result
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let stmt = script.handlers[0].body[0]
        guard case .ifThenElse(_, let thenBlock, let elseBlock) = stmt else {
            Issue.record("Expected if/then/else statement")
            return
        }
        #expect(thenBlock.count == 1)
        #expect(elseBlock?.count == 1)
        guard case .ifThenElse(_, let elseIfThenBlock, let elseIfElseBlock) = elseBlock?.first else {
            Issue.record("Expected nested else-if statement")
            return
        }
        #expect(elseIfThenBlock.count == 1)
        #expect(elseIfElseBlock?.count == 1)
    }

    @Test func parsesNestedSingleLineIfFollowingElseIfShape() async throws {
        var lexer = Lexer(source: """
        on test
          if branch is "B" then
            if bridge is "up" then
              if route is "P" then put "p" into result
              else if route is "Q" then put "q" into result
              else put "fallback" into result
            else
              put "bridge down" into result
            end if
          else
            put "branch fallback" into result
          end if
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers[0].body.count == 1)
    }

    @Test func parsesRepeatCount() async throws {
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

    @Test func parsesHandlerWithParams() async throws {
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

    @Test func parsesSendToStackAsMessageDispatch() throws {
        var lexer = Lexer(source: """
        on mouseUp
          send "doCamp" to this stack
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .send(let message, let target) = script.handlers[0].body[0] else {
            Issue.record("Expected send message statement")
            return
        }
        guard case .literal(let messageName) = message else {
            Issue.record("Expected literal message")
            return
        }
        #expect(messageName == "doCamp")
        guard case .objectRef(let ref)? = target else {
            Issue.record("Expected stack object reference")
            return
        }
        #expect(ref.objectType == "stack")
    }

    @Test func parsesClassicSendWithoutExplicitTarget() throws {
        var lexer = Lexer(source: """
        on mouseUp
          send closeStack
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .send(let message, let target) = script.handlers[0].body[0] else {
            Issue.record("Expected send message statement")
            return
        }
        let messageName: String
        switch message {
        case .literal(let name), .variable(let name):
            messageName = name
        default:
            Issue.record("Expected bare message name")
            return
        }
        #expect(messageName == "closeStack")
        #expect(target == nil)
    }

    @Test func parsesClassicSendToBareCardAsCurrentCardDispatch() throws {
        var lexer = Lexer(source: """
        on mouseUp
          send mouseDownInMovie to card
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .send(_, let target) = script.handlers[0].body[0] else {
            Issue.record("Expected send message statement")
            return
        }
        guard case .objectRef(let ref)? = target else {
            Issue.record("Expected current card object reference")
            return
        }
        #expect(ref.objectType == "card")
        guard case .literal(let identifier) = ref.identifier else {
            Issue.record("Expected current-card literal identifier")
            return
        }
        #expect(identifier == "current")
    }

    @Test func parsesClassicPushAndPopCard() throws {
        var lexer = Lexer(source: """
        on mouseUp
          push card
          pop card
        end mouseUp
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .push(nil) = script.handlers[0].body[0] else {
            Issue.record("Expected push card statement")
            return
        }
        guard case .pop = script.handlers[0].body[1] else {
            Issue.record("Expected pop card statement")
            return
        }
    }

    @Test func parsesClassicButtonCommandAsExternalCommand() throws {
        var lexer = Lexer(source: """
        on mouseDown
          button 2,-1
        end mouseDown
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .externalCommand(let name, let arguments) = script.handlers[0].body[0] else {
            Issue.record("Expected button external command")
            return
        }
        #expect(name == "button")
        #expect(arguments.count == 2)
    }

    @Test func parsesExplicitSendToConnectionAsNetworkDispatch() throws {
        var lexer = Lexer(source: """
        on sendPing
          send "ping" to connection connId
        end sendPing
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        guard case .sendToConnection(let data, let connection) = script.handlers[0].body[0] else {
            Issue.record("Expected sendToConnection statement")
            return
        }
        guard case .literal(let payload) = data else {
            Issue.record("Expected literal payload")
            return
        }
        #expect(payload == "ping")
        guard case .variable(let variableName) = connection else {
            Issue.record("Expected connection variable")
            return
        }
        #expect(variableName == "connId")
    }

    @Test func parsesClassicOnOffStateLiterals() throws {
        var lexer = Lexer(source: """
        on mouseDown
          put on into light
          if light is on then put off into light
        end mouseDown
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers[0].body.count == 2)
        guard case .put(.literal("on"), _, .variable("light")) = script.handlers[0].body[0] else {
            Issue.record("Expected classic on literal assignment")
            return
        }
    }
}

// MARK: - Interpreter Tests

@Suite("Interpreter Tests", .serialized)
struct InterpreterTests {

    private func executeScript(_ source: String, params: [Value] = []) -> ExecutionResult {
        executeScript(source, document: HypeDocument.newDocument(), params: params)
    }

    private func executeScript(_ source: String, document: HypeDocument, params: [Value] = []) -> ExecutionResult {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            return ExecutionResult(status: .error, error: ScriptError(message: "Parse failed", line: 0, handler: ""))
        }
        let context = ExecutionContext(targetId: document.cards[0].id, currentCardId: document.cards[0].id, document: document)
        let interpreter = Interpreter()
        return interpreter.execute(handler: handler, params: params, context: context)
    }

    @Test func evaluatesArithmetic() async {
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

    @Test func evaluatesClassicOnOffStateLiterals() {
        let result = executeScript("""
        on test
          put on into light
          if light is on then put off into light
          return light
        end test
        """)
        #expect(result.status == .completed)
        #expect(result.returnValue == "off")
    }

    @Test func startUsingStackUpdatesImportedStackLibrary() {
        var doc = HypeDocument.newDocument()
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "ALLRes",
                aliases: ["ALL Res", "ALLRes.xstk"],
                source: .importedStackPackage,
                packagePath: "exports/stacks/ALLRes.xstk"
            )
        ])

        let result = executeScript("""
        on test
          start using "all-res"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "ALL Res")
        #expect(result.modifiedDocument?.stackLibrary.usedStackAliases == ["ALL Res"])
    }

    @Test func stopUsingStackUpdatesImportedStackLibrary() {
        var doc = HypeDocument.newDocument()
        doc.stackLibrary = HypeStackLibrary(
            entries: [
                HypeStackLibraryEntry(
                    stackName: "ALLRes",
                    aliases: ["ALL Res", "ALLRes.xstk"],
                    source: .importedStackPackage,
                    packagePath: "exports/stacks/ALLRes.xstk"
                )
            ],
            usedStackAliases: ["ALL Res"]
        )

        let result = executeScript("""
        on test
          stop using "ALLRes.xstk"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "ALL Res")
        #expect(result.modifiedDocument?.stackLibrary.usedStackAliases.isEmpty == true)
    }

    @Test func startUsingMissingStackReturnsScriptError() {
        let result = executeScript("""
        on test
          start using "INRes1"
        end test
        """)

        #expect(result.status == .error)
        #expect(result.error?.message == "Stack not found: INRes1")
    }

    @Test func startUsingAmbiguousStackReturnsScriptError() {
        var doc = HypeDocument.newDocument()
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(stackName: " Myst", aliases: ["Myst"], source: .importedStackPackage),
            HypeStackLibraryEntry(stackName: "Myst", aliases: ["Myst"], source: .importedStackPackage)
        ])

        let result = executeScript("""
        on test
          start using "myst"
        end test
        """, document: doc)

        #expect(result.status == .error)
        #expect(result.error?.message == "Ambiguous stack name 'myst': Myst, Myst")
    }

    @Test func goToCardInStackResolvesProjectNavigationTargetByName() {
        var doc = HypeDocument.newDocument()
        let myst = HypeStackLibraryEntry(
            stackName: "Myst",
            aliases: ["Myst Island"],
            source: .importedStackPackage,
            packagePath: "exports/stacks/Myst.xstk",
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 3656, name: "black", sortIndex: 1),
                HypeStackLibraryCardReference(legacyCardId: 44018, name: "Dock", sortIndex: 2)
            ]
        )
        doc.stackLibrary = HypeStackLibrary(entries: [myst])

        let result = executeScript("""
        on test
          go to card "black" of stack "Myst Island"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == nil)
        #expect(result.projectNavigationTarget?.stackName == "Myst")
        #expect(result.projectNavigationTarget?.legacyCardId == 3656)
        #expect(result.projectNavigationTarget?.cardName == "black")
    }

    @Test func goToCardInStackResolvesProjectNavigationTargetByLegacyId() {
        var doc = HypeDocument.newDocument()
        let myst = HypeStackLibraryEntry(
            stackName: "Myst",
            source: .importedStackPackage,
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 44018, name: "Dock", sortIndex: 2)
            ]
        )
        doc.stackLibrary = HypeStackLibrary(entries: [myst])

        let result = executeScript("""
        on test
          go to card id 44018 of stack "Myst"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.projectNavigationTarget?.legacyCardId == 44018)
        #expect(result.projectNavigationTarget?.cardName == "Dock")
    }

    @Test func goToStackResolvesProjectNavigationTargetToFirstCard() {
        var doc = HypeDocument.newDocument()
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "charFile",
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 100, name: "Start", sortIndex: 0),
                    HypeStackLibraryCardReference(legacyCardId: 101, name: "Next", sortIndex: 1),
                ]
            )
        ])

        let result = executeScript("""
        on test
          go to stack charFile
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.projectNavigationTarget?.stackName == "charFile")
        #expect(result.projectNavigationTarget?.legacyCardId == 100)
        #expect(result.projectNavigationTarget?.cardName == "Start")
    }

    @Test func goToStackUsesVariableWhenPresent() {
        var doc = HypeDocument.newDocument()
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "RestoredGame",
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 200, name: "Restore Start", sortIndex: 0)
                ]
            )
        ])

        let result = executeScript("""
        on test
          put "RestoredGame" into charFile
          go to stack charFile
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.projectNavigationTarget?.stackName == "RestoredGame")
        #expect(result.projectNavigationTarget?.legacyCardId == 200)
    }

    @Test func goToCardInAmbiguousStackPrefersExactStackName() {
        var doc = HypeDocument.newDocument()
        let app = HypeStackLibraryEntry(
            stackName: " Myst",
            aliases: ["Myst", "Myst-Application"],
            source: .importedStackPackage,
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 3656, name: "black", sortIndex: 1)
            ]
        )
        let island = HypeStackLibraryEntry(
            stackName: "Myst",
            aliases: ["Myst"],
            source: .importedStackPackage,
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 23444, name: "black", sortIndex: 301)
            ]
        )
        doc.stackLibrary = HypeStackLibrary(entries: [app, island])

        let islandResult = executeScript("""
        on test
          go to card "black" of stack "Myst"
        end test
        """, document: doc)

        #expect(islandResult.status == .completed)
        #expect(islandResult.projectNavigationTarget?.stackName == "Myst")
        #expect(islandResult.projectNavigationTarget?.legacyCardId == 23444)

        let appResult = executeScript("""
        on test
          go to card "black" of stack " Myst"
        end test
        """, document: doc)

        #expect(appResult.status == .completed)
        #expect(appResult.projectNavigationTarget?.stackName == " Myst")
        #expect(appResult.projectNavigationTarget?.legacyCardId == 3656)
    }

    @Test func goToMissingCardInStackReturnsScriptError() {
        var doc = HypeDocument.newDocument()
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "Myst",
                source: .importedStackPackage,
                cardReferences: [HypeStackLibraryCardReference(legacyCardId: 44018, name: "Dock", sortIndex: 2)]
            )
        ])

        let result = executeScript("""
        on test
          go to card "black" of stack "Myst"
        end test
        """, document: doc)

        #expect(result.status == .error)
        #expect(result.error?.message == "Card not found in stack 'Myst': black")
    }

    @Test func goCurrentCardFormsResolveToCurrentCard() {
        let doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        for command in ["go card", "go this card", "go to this card"] {
            let result = executeScript("""
            on test
              \(command)
            end test
            """, document: doc)

            #expect(result.status == .completed)
            #expect(result.navigationTarget == cardId)
        }
    }

    @Test func goToNextMarkedCardNavigatesToNextMarkedCard() {
        var doc = HypeDocument.newDocument()
        let second = doc.addCard()
        let third = doc.addCard()
        doc.cards = doc.cards.map { card in
            var copy = card
            if card.id == second.id {
                copy.name = "Second"
            }
            if card.id == third.id {
                copy.name = "Third"
            }
            copy.marked = card.id == third.id
            return copy
        }

        let result = executeScript("""
        on test
          go to next marked card
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == third.id)
    }

    @Test func goToCardUsesLoopVariableIndex() {
        var doc = HypeDocument.newDocument()
        let second = doc.addCard()
        let third = doc.addCard()

        let result = executeScript("""
        on test
          repeat with x = 1 to the number of cards
            go to card x
          end repeat
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == third.id)
        #expect(second.id != third.id)
    }

    @Test func singleLineIfCanNavigateToNamedCard() {
        var doc = HypeDocument.newDocument()
        let dock = doc.addCard()
        doc.cards = doc.cards.map { card in
            var copy = card
            if card.id == dock.id {
                copy.name = "dock"
            }
            return copy
        }

        let result = executeScript("""
        on test
          put "new" into start_Game
          if start_Game is "new" then go to card "dock"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == dock.id)
    }

    @Test func seededScriptGlobalsAreCaseInsensitiveForDeclaredGlobals() {
        var doc = HypeDocument.newDocument()
        let dock = doc.addCard()
        doc.scriptGlobals = ["Start_Game": "new"]
        doc.cards = doc.cards.map { card in
            var copy = card
            if card.id == dock.id {
                copy.name = "dock"
            }
            return copy
        }

        let result = executeScript("""
        on test
          global start_Game
          if start_Game is "new" then go to card "dock"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == dock.id)
        #expect(result.modifiedDocument?.scriptGlobals["start_game"] == "new")
    }

    @Test func classicSingleLineIfWithMultilineElseIfElseParsesLauncherBranch() {
        var doc = HypeDocument.newDocument(name: " Myst")
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "Myst",
                aliases: ["Myst"],
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 8336, name: "dock", sortIndex: 22)
                ]
            )
        ])
        doc.scriptGlobals = [
            "Start_Game": "new",
            "MY_RedBook": "000000",
            "MY_BlueBook": "000000",
            "DU_End": "",
        ]

        let result = executeScript("""
        on test
          global start_Game,MY_RedBook,MY_BlueBook,DU_End
          if char 6 of MY_RedBook = "1" and DU_End ≠ "win" then go card id 80371
          else if char 6 of MY_BlueBook = "1" and DU_End ≠ "win" then go card id 81655
          else
          wait until the sound is "done"
          play "transport"
          if start_Game is "new" then go to card "dock"
          else
          go to card "reStart"
          end if
          end if
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.projectNavigationTarget?.stackName == "Myst")
        #expect(result.projectNavigationTarget?.legacyCardId == 8336)
    }

    @Test func importedIfBlockCanCloseAtNextHandlerBoundary() throws {
        var lexer = Lexer(source: """
        on openCard
          if field "truepath" is not empty then
            if checkpath() then
              if word 2 of field "truepath" is "P" then playqt "L1 Slosh/Run/Motor Mov",,loop,100
              else playqt "L1 slosh Mov",,loop,100
              end if
            else playqt "L1 slosh Mov",,loop,100
            end if
          hide msg
          pass openCard
        end openCard

        on openStack
          start using stack "CHRes1"
        end openStack
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()

        #expect(script.handlers.map(\.name) == ["openCard", "openStack"])
    }

    @Test func implicitNamedCardGoResolvesUniqueProjectCard() {
        var doc = HypeDocument.newDocument(name: "ALLRes")
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "ALLRes",
                source: .importedStackPackage,
                cardReferences: []
            ),
            HypeStackLibraryEntry(
                stackName: " Myst",
                aliases: ["Myst-Application"],
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 4981, name: "finalBookOpen", sortIndex: 2)
                ]
            )
        ])

        let result = executeScript("""
        on test
          go to card "finalBookOpen"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == nil)
        #expect(result.projectNavigationTarget?.stackName == " Myst")
        #expect(result.projectNavigationTarget?.legacyCardId == 4981)
    }

    @Test func implicitNamedCardGoPrefersCurrentProjectStack() {
        var doc = HypeDocument.newDocument(name: " Myst")
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: " Myst",
                aliases: ["Myst-Application"],
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 3656, name: "black", sortIndex: 0)
                ]
            ),
            HypeStackLibraryEntry(
                stackName: "Myst",
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 23444, name: "Black", sortIndex: 0)
                ]
            )
        ])

        let result = executeScript("""
        on test
          go to card "black"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == nil)
        #expect(result.projectNavigationTarget?.stackName == " Myst")
        #expect(result.projectNavigationTarget?.legacyCardId == 3656)
    }

    @Test func implicitNamedCardGoFindsUniqueCardInOtherProjectStack() {
        var doc = HypeDocument.newDocument(name: " Myst")
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: " Myst",
                aliases: ["Myst-Application"],
                source: .importedStackPackage,
                cardReferences: []
            ),
            HypeStackLibraryEntry(
                stackName: "Myst",
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 23444, name: "Black", sortIndex: 0),
                    HypeStackLibraryCardReference(legacyCardId: 44018, name: "restart", sortIndex: 10)
                ]
            ),
            HypeStackLibraryEntry(
                stackName: "Channelwood Age",
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 28497, name: "restart", sortIndex: 20)
                ]
            )
        ])

        let result = executeScript("""
        on test
          go to card Black in stack Myst
          go to card "reStart"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == nil)
        #expect(result.projectNavigationTarget?.stackName == "Myst")
        #expect(result.projectNavigationTarget?.legacyCardId == 44018)
    }

    @Test func doBlockExecutesGeneratedLocalGo() {
        var doc = HypeDocument.newDocument()
        _ = doc.addCard()
        let blackCard = doc.addCard()
        doc.cards = doc.cards.map { card in
            var copy = card
            if card.id == blackCard.id {
                copy.name = "Black"
            }
            return copy
        }

        let result = executeScript("""
        on test
          put "Black q1" into it
          do ("go to card" && word 1 of it)
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == blackCard.id)
    }

    @Test func doBlockExecutesGeneratedCrossStackGo() {
        var doc = HypeDocument.newDocument()
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "Myst",
                source: .importedStackPackage,
                cardReferences: [HypeStackLibraryCardReference(legacyCardId: 23444, name: "Black", sortIndex: 1)]
            )
        ])

        let result = executeScript("""
        on test
          put "Myst" into ALL_CurrStack
          do ("go to card Black in stack " & ALL_CurrStack)
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.projectNavigationTarget?.stackName == "Myst")
        #expect(result.projectNavigationTarget?.legacyCardId == 23444)
    }

    @Test func askWithDefaultResponseSetsItToDefaultInHeadlessRuntime() {
        let result = executeScript("""
        on test
          ask "go where?" with "0,0"
          return it
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "0,0")
    }

    @Test func htLockRecordsCompatibilityMode() {
        let result = executeScript("""
        on test
          HTLock false
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "false")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htlock.mode"] == "false")
    }

    @Test func htVisualCarriesVisualEffectIntent() {
        let result = executeScript("""
        on test
          HTVisual "wipe right",,,1,32
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.visualEffect == "wipe right")
        #expect(result.visualEffectDuration == 32.0 / 60.0)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htvisual.effect"] == "wipe right")
    }

    @Test func mystVdUsesTransitionGlobalForDefaultVisualEffect() {
        let result = executeScript("""
        on test
          global Trans
          put 2 into Trans
          vd
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.visualEffect == "tdfBlend5")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.vd.trans"] == "2")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.vd.effect"] == "tdfBlend5")
    }

    @Test func mystVsUsesTransitionGlobalForDirectionalVisualEffect() {
        let result = executeScript("""
        on test
          global Trans
          put 1 into Trans
          vs right
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.visualEffect == "scroll right")
        #expect(result.visualEffectDuration == 64.0 / 60.0)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.vs.trans"] == "1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.vs.direction"] == "right")
    }

    @Test func mystPlanetariumArrowUpdatesDateTimeCompatibilityState() {
        var document = HypeDocument.newDocument()
        let cardId = document.cards[0].id
        var field = Part(partType: .field, cardId: cardId, name: "Month")
        field.textContent = "11"
        document.addPart(field)

        let result = executeScript("""
        on test
          arrow Month,1,12,1
        end test
        """, document: document)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["MY_PlaMonth"] == "12")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.arrow.month.value"] == "12")
        let updatedField = result.modifiedDocument?.parts.first {
            $0.partType == .field && $0.name == "Month"
        }
        #expect(updatedField?.textContent == "12")
    }

    @Test func mystPlanetariumArrowClampsAndHonorsInitMode() {
        let result = executeScript("""
        on test
          global MY_PlaTime
          put 1439 into MY_PlaTime
          arrow Time,0,1439,1,true
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["MY_PlaTime"] == "1439")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.arrow.time.init"] == "true")
    }

    @Test func mystPlanetariumSlideKnobPreservesCurrentValueWithinRange() {
        let result = executeScript("""
        on test
          global MY_PlaDay
          put 31 into MY_PlaDay
          slideKnob Day,1,31
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["MY_PlaDay"] == "31")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.slideknob.day.value"] == "31")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.slideknob.day.range"] == "1,31")
    }

    @Test func mystChannelwoodValveHelpersSetValveAndNavigateToRouteCards() {
        var document = HypeDocument.newDocument()
        document.stack.name = "Channelwood Age"
        let intake = document.addCard()
        let left = document.addCard()
        let right = document.addCard()
        document.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "Channelwood Age",
                aliases: ["Channelwood-Age"],
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(
                        legacyCardId: 86839,
                        name: "Valve Intake",
                        sortIndex: 1,
                        hypeCardId: intake.id
                    ),
                    HypeStackLibraryCardReference(
                        legacyCardId: 87418,
                        name: "Valve Left",
                        sortIndex: 2,
                        hypeCardId: left.id
                    ),
                    HypeStackLibraryCardReference(
                        legacyCardId: 87249,
                        name: "Valve Right",
                        sortIndex: 3,
                        hypeCardId: right.id
                    )
                ]
            )
        ])

        let intakeResult = executeScript("""
        on test
          doValveI 5
        end test
        """, document: document)
        #expect(intakeResult.status == .completed)
        #expect(intakeResult.returnValue == "5")
        #expect(intakeResult.navigationTarget == intake.id)
        #expect(intakeResult.projectNavigationTarget?.legacyCardId == 86839)
        #expect(intakeResult.projectNavigationTarget?.cardName == "Valve Intake")
        #expect(intakeResult.modifiedDocument?.scriptGlobals["CH_Valve"] == "5")
        #expect(intakeResult.modifiedDocument?.scriptGlobals["hypercard.channelwood.valve.route"] == "I")

        let leftResult = executeScript("""
        on test
          doValveL 6
        end test
        """, document: document)
        #expect(leftResult.status == .completed)
        #expect(leftResult.navigationTarget == left.id)
        #expect(leftResult.projectNavigationTarget?.legacyCardId == 87418)
        #expect(leftResult.modifiedDocument?.scriptGlobals["CH_Valve"] == "6")
        #expect(leftResult.modifiedDocument?.scriptGlobals["hypercard.channelwood.valve.route"] == "L")

        let rightResult = executeScript("""
        on test
          doValveR 7
        end test
        """, document: document)
        #expect(rightResult.status == .completed)
        #expect(rightResult.navigationTarget == right.id)
        #expect(rightResult.projectNavigationTarget?.legacyCardId == 87249)
        #expect(rightResult.modifiedDocument?.scriptGlobals["CH_Valve"] == "7")
        #expect(rightResult.modifiedDocument?.scriptGlobals["hypercard.channelwood.valve.route"] == "R")
    }

    @Test func deCurseRecordsCursorCompatibilityState() {
        let result = executeScript("""
        on test
          deCurse "override",2003,"color","nodelay"
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "override")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.decurse.mode"] == "override")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.decurse.resource"] == "2003")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.decurse.kind"] == "color")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.decurse.options"] == "nodelay")
    }

    @Test func moveCursorRecordsCompatibilityPoint() {
        let result = executeScript("""
        on test
          moveCursor 10,20
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "10,20")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.movecursor.loc"] == "10,20")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.cursor.mode"] == "move")
    }

    @Test func xWindowFrameCreatesCompatibilityWindowState() {
        let result = executeScript("""
        on test
          xWindowFrame
          if there is a window "frame" then return the result
          return "missing"
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "frame")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.frame.exists"] == "true")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.frame.visible"] == "true")
    }

    @Test func quickTimeWindowMessagesAreNoOpSafeAndUpdatePlaybackState() {
        let asset = Asset(
            name: "Elevator1.MooV",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data([1]),
            width: 80,
            height: 60,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "Elevator1.MooV")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [asset])

        let result = executeScript("""
        on test
          put "Elevator1.MooV" into TheMovieName
          Movie TheMovieName,"borderless","10,20","invisible","Floating"
          send play to window TheMovieName
          send movieIdle to window TheMovieName
          send pause to window TheMovieName
          return the lastMessage of window TheMovieName
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "pause")
        let modified = result.modifiedDocument
        #expect(modified?.scriptGlobals["hypercard.window.elevator1.message.play.count"] == "1")
        #expect(modified?.scriptGlobals["hypercard.window.elevator1.message.movieidle.count"] == "1")
        #expect(modified?.scriptGlobals["hypercard.window.elevator1.message.pause.count"] == "1")
        #expect(modified?.scriptGlobals["hypercard.window.elevator1.rate"] == "0.0")
        let video = modified?.parts.first { $0.partType == .video && $0.name == "Elevator1.MooV" }
        #expect(video?.videoAutoplay == false)
        #expect(video?.left == 10)
        #expect(video?.top == 20)
    }

    @Test func thereIsNotAWindowParsesAsMissingCompatibilityCheck() {
        let result = executeScript("""
        on test
          if there is not a window "frame" then return "missing"
          return "open"
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "missing")
    }

    @Test func barePutStoresValueInItForClassicDebugHandlers() {
        let result = executeScript("""
        on test
          put "debug value"
          return it
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "debug value")
    }

    @Test func openStateLiteralSupportsClassicStateChecks() {
        let result = executeScript("""
        on test
          put open into drawer
          if drawer is open then return "drawer-open"
          return "closed"
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "drawer-open")
    }

    @Test func barePropertyOfObjectReferencesEvaluateLikeThePropertyForm() {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var button = Part(partType: .button, cardId: cardId, name: "openElevator", left: 10, top: 20, width: 40, height: 20)
        button.visible = false
        doc.addPart(button)

        let result = executeScript("""
        on test
          if visible of card button openElevator is false then return rect of card button openElevator
          return "visible"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "10,20,50,40")
    }

    @Test func shortNameOfThisStackReturnsStackName() {
        let doc = HypeDocument.newDocument(name: " Myst")
        let result = executeScript("""
        on test
          return the short name of this stack
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == " Myst")
    }

    @Test func shortIdOfThisCardReturnsImportedLegacyCardId() {
        var doc = HypeDocument.newDocument(name: "Dunny Age")
        let cardId = doc.cards[0].id
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "Dunny Age",
                aliases: ["Dunny Age"],
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(
                        legacyCardId: 4840,
                        name: "Father-Out",
                        sortIndex: 0,
                        hypeCardId: cardId
                    )
                ]
            )
        ])

        let result = executeScript("""
        on test
          if the short id of this card is 4840 then
            return "legacy"
          end if
          return "missing"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "legacy")
    }

    @Test func classicMenuPutWithMenuMsgParsesAsCompatibilityNoOp() {
        let result = executeScript("""
        on test
          put "New Game" after menu File with menuMsg NewIt
          put "About Myst" into menuItem 1 of menu Apple with menuMsg about
          return it
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "About Myst")
    }

    @Test func xAboutRecordsCompatibilityIntent() {
        let result = executeScript("""
        on test
          xAbout
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xabout.invoked"] == "true")
    }

    @Test func xClipRecordsQuickDrawClipRectIntent() {
        let result = executeScript("""
        on test
          xClip "10,20,110,220"
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "10,20,110,220")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xclip.rect"] == "10,20,110,220")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.quickdraw.clipRect"] == "10,20,110,220")
    }

    @Test func xLineRecordsQuickDrawLineIntent() {
        let result = executeScript("""
        on test
          xClip "0,0,200,200"
          xLine "1,2","101,202",2,137
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "1,2,101,202,2,137")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xline.count"] == "1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xline.start"] == "1,2")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xline.end"] == "101,202")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xline.penSize"] == "2")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xline.color"] == "137")
        #expect(Int(result.modifiedDocument?.scriptGlobals["hypercard.xline.renderedPixels"] ?? "0") ?? 0 > 0)
        #expect(result.modifiedDocument?.paintLayer(forCardId: result.modifiedDocument?.cards.first?.id ?? UUID())?.isEmpty == false)
    }

    @Test func xLineRendersIntoCurrentCardPaintLayerWithClipRect() {
        let result = executeScript("""
        on test
          xClip "10,0,13,10"
          xLine "0,0","20,0",1,255
          return the result
        end test
        """)

        let document = result.modifiedDocument
        let cardId = document?.cards.first?.id
        let layer = cardId.flatMap { document?.paintLayer(forCardId: $0) }
        let data = layer?.normalizedRGBAData ?? Data()
        func alphaAt(_ x: Int, _ y: Int) -> UInt8 {
            guard let layer else { return 0 }
            let offset = (y * layer.width + x) * 4 + 3
            guard data.indices.contains(offset) else { return 0 }
            return data[offset]
        }

        #expect(result.status == .completed)
        #expect(result.returnValue == "0,0,20,0,1,255")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xline.renderedPixels"] == "3")
        #expect(alphaAt(9, 0) == 0)
        #expect(alphaAt(10, 0) == 255)
        #expect(alphaAt(11, 0) == 255)
        #expect(alphaAt(12, 0) == 255)
        #expect(alphaAt(13, 0) == 0)
    }

    @Test func xLineUsesActiveHTUDefPalPaletteColorIndex() throws {
        let paletteAsset = Asset(
            name: "Line Palette",
            kind: .placeholderAsset,
            mimeType: "application/json",
            data: Data("""
            {"entries":[
              {"red":0,"green":0,"blue":0},
              {"red":65535,"green":32768,"blue":0}
            ]}
            """.utf8),
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "pltt"),
                AssetMetadataEntry(key: "resource_id", value: "7001")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [paletteAsset])

        let result = executeScript("""
        on test
          HTUDefPal 7001
          xLine "2,2","2,2",1,1
          return the result
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "2,2,2,2,1,1")
        let document = try #require(result.modifiedDocument)
        let cardId = try #require(document.cards.first?.id)
        let layer = try #require(document.paintLayer(forCardId: cardId))
        let data = layer.normalizedRGBAData
        let offset = (2 * layer.width + 2) * 4
        #expect(data[offset] == 255)
        #expect(data[offset + 1] == 128)
        #expect(data[offset + 2] == 0)
        #expect(data[offset + 3] == 255)
        #expect(document.scriptGlobals["hypercard.htudefpal.colors"] == "#000000\t#FF8000")
        #expect(document.scriptGlobals["hypercard.xline.color"] == "1")
    }

    @Test func htTB1TSRecordsTempBufferTileCopyIntent() {
        let result = executeScript("""
        on test
          HTTB1TS "15,14,50,52","35,38,70,76","novbl"
          HTTB1TS "50,14,85,52","70,38,105,76","srcXor","novbl"
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "50,14,85,52")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.httb1ts.count"] == "2")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.httb1ts.destinationRect"] == "50,14,85,52")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.httb1ts.sourceRect"] == "70,38,105,76")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.httb1ts.transferMode"] == "srcXor")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.httb1ts.vbl"] == "false")
    }

    @Test func xMemoryFunctionReturnsDeterministicPositiveValue() {
        let result = executeScript("""
        on test
          return xMemory(1)
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "16777216")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xmemory.query"] == "1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xmemory.value"] == "16777216")
    }

    @Test func xMemoryCommandRecordsDeterministicPositiveValue() {
        let result = executeScript("""
        on test
          xMemory 1
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "16777216")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xmemory.query"] == "1")
    }

    @Test func xVirtualFunctionReturnsDeterministicFalseValue() {
        let result = executeScript("""
        on test
          return xVirtual()
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "0")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xvirtual.value"] == "0")
    }

    @Test func xDepthDefaultsToClassicColorDepth() {
        let result = executeScript("""
        on test
          return xDepth()
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "8")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xdepth.value"] == "8")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.setmode.depth"] == "8")
    }

    @Test func xDepthReturnsSetModeDepth() {
        let result = executeScript("""
        on test
          SetMode c,4
          return xDepth()
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "4")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xdepth.value"] == "4")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.setmode.depth"] == "4")
    }

    @Test func variantReturnsHyperCardCompatibleVersion() {
        let result = executeScript("""
        on test
          if variant() >= 2.1 then return "pass"
          return "block"
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "pass")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.variant.value"] == "2.1")
    }

    @Test func classicComparisonGlyphsParseInImportedConditionals() {
        let result = executeScript("""
        on test
          get 9
          if it \u{2265} 9 then return "gte"
          return "block"
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "gte")
    }

    @Test func movieInfoReturnsRepositoryBackedMovieMetadata() {
        let movie = Asset(
            name: "Intro Wind Mov-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 160,
            height: 90,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "Intro Wind Mov"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("Intro Wind Mov")),
                AssetMetadataEntry(key: "size", value: "2048")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          return movieInfo("Myst:Myst Graphics:Myst:Intro Wind Mov")
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue?.contains("name:\tIntro Wind Mov") == true)
        #expect(result.returnValue?.contains("asset:\tIntro Wind Mov-modern.mov") == true)
        #expect(result.returnValue?.contains("bytes:\t2048") == true)
        #expect(result.returnValue?.contains("bounds:\t0,0,160,90") == true)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.movieinfo.found"] == "true")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.movieinfo.name"] == "Intro Wind Mov")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.movieinfo.path"] == "Myst:Myst Graphics:Myst:Intro Wind Mov")
    }

    @Test func movieInfoMissingAssetSetsDiagnosticResult() {
        let result = executeScript("""
        on test
          get movieInfo("Missing.MooV")
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "File not found.")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.movieinfo.found"] == "false")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.movieinfo.name"] == "Missing")
    }

    @Test func xGetSoundVolDefaultsToClassicMaxVolume() {
        let result = executeScript("""
        on test
          return xGetSoundVol()
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "255")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.sound.volume"] == "255")
    }

    @Test func xSetSoundVolClampsAndFeedsXGetSoundVol() {
        let result = executeScript("""
        on test
          xSetSoundVol 300
          return xGetSoundVol()
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "255")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.sound.volume"] == "255")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.xsetsoundvol.arguments"] == "300")
    }

    @Test func xSetSoundVolFunctionUsesEvaluatedVariable() {
        let result = executeScript("""
        on test
          put 42 into origVol
          get xSetSoundVol(origVol)
          return xGetSoundVol()
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "42")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.sound.volume"] == "42")
    }

    @Test func xSetSoundVolUpdatesCompatibilityVideoVolume() {
        let movie = Asset(name: "Intro Wind Mov", kind: .videoClip, mimeType: "video/quicktime", data: Data("movie".utf8))
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          playQT "Intro Wind Mov"
          xSetSoundVol 128
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.videoVolume == 128.0 / 255.0)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.sound.volume"] == "128")
    }

    @Test func setModeRecordsDisplayCompatibilityState() {
        let result = executeScript("""
        on test
          SetMode c,8
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.setmode.mode"] == "c")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.setmode.depth"] == "8")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.setmode.value"] == "c,8")
    }

    @Test func getModeDefaultsToClassicColorDepth() {
        let result = executeScript("""
        on test
          return GetMode()
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "c,8")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.setmode.value"] == "c,8")
    }

    @Test func getModeReturnsSetModeState() {
        let result = executeScript("""
        on test
          SetMode "bw",1
          return GetMode()
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "bw,1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.setmode.mode"] == "bw")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.setmode.depth"] == "1")
    }

    @Test func htAddPictCreatesCompatibilityImagePart() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let asset = Asset(
            name: "Lever Down PICT",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 40,
            height: 20,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "Lever Down"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("Lever Down"))
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [asset])

        let result = executeScript("""
        on test
          HTAddPict "Lever Down","10,20,50,40","srccopy"
          return the result
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "Lever Down PICT")
        let part = result.modifiedDocument?.parts.first { $0.helpText == "hypercard-htaddpict" }
        #expect(part?.partType == .image)
        #expect(part?.left == 10)
        #expect(part?.top == 20)
        #expect(part?.width == 40)
        #expect(part?.height == 20)
        #expect(part?.imageData == imageData)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htaddpict.transferMode"] == "srcCopy")
    }

    @Test func htAddPictAppliesClassicSourceRectCrop() throws {
        let sourceImage = try testPNG(width: 2, height: 1, pixels: [
            (255, 0, 0, 255),
            (0, 0, 255, 255)
        ])
        let expectedCrop = try testPNG(width: 1, height: 1, pixels: [
            (0, 0, 255, 255)
        ])
        let asset = Asset(
            name: "Switch Strip",
            kind: .imageTexture,
            mimeType: "image/png",
            data: sourceImage,
            width: 2,
            height: 1,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "Switch Strip")]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [asset])

        let result = executeScript("""
        on test
          HTAddPict "Switch Strip","10,20,30,40","srccopy","srcRect","1,0,2,1"
          return the result
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "Switch Strip")
        let part = try #require(result.modifiedDocument?.parts.first { $0.helpText == "hypercard-htaddpict" })
        #expect(part.left == 10)
        #expect(part.top == 20)
        #expect(part.width == 20)
        #expect(part.height == 20)
        #expect(NSImage(data: part.imageData ?? Data())?.size == NSImage(data: expectedCrop)?.size)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htaddpict.sourceRect"] == "1,0,2,1")
    }

    @Test func htAddPictCompositesClassicTransferModeIntoPaintLayer() throws {
        let sourceImage = try testPNG(width: 1, height: 1, pixels: [
            (15, 15, 15, 255)
        ])
        let asset = Asset(
            name: "Xor Patch",
            kind: .imageTexture,
            mimeType: "image/png",
            data: sourceImage,
            width: 1,
            height: 1,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "Xor Patch")]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [asset])

        let result = executeScript("""
        on test
          xLine "10,10","10,10",1,240
          HTAddPict "Xor Patch","10,10,11,11","srcXor"
          return the result
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "Xor Patch")
        let document = try #require(result.modifiedDocument)
        let cardId = try #require(document.cards.first?.id)
        let layer = try #require(document.paintLayer(forCardId: cardId))
        let offset = (10 * layer.width + 10) * 4
        let data = layer.normalizedRGBAData
        #expect(data[offset] == 255)
        #expect(data[offset + 1] == 255)
        #expect(data[offset + 2] == 255)
        #expect(data[offset + 3] == 255)
        let part = try #require(document.parts.first { $0.helpText == "hypercard-htaddpict" })
        #expect(part.visible == false)
        #expect(document.scriptGlobals["hypercard.htaddpict.transferMode"] == "srcXor")
        #expect(document.scriptGlobals["hypercard.htaddpict.compositedPixels"] == "1")
    }

    @Test func htSavePictAndClipboardRestoreRemoveCompatibilityOverlayInRect() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let asset = Asset(
            name: "Vault controlpanel down",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 20,
            height: 20,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "Vault controlpanel down")]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [asset])

        let result = executeScript("""
        on test
          HTSavePict "10,20,30,40","clipboard","srccopy","backdrop"
          HTAddPict "Vault controlpanel down","10,20,30,40","srccopy"
          HTAddPict "","10,20,30,40","srccopy","clipboard"
          return the result
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "clipboard")
        let overlays = result.modifiedDocument?.parts.filter { $0.helpText == "hypercard-htaddpict" } ?? []
        #expect(overlays.isEmpty)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htsavepict.destination"] == "clipboard")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htsavepict.rect"] == "10,20,30,40")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htsavepict.transferMode"] == "srcCopy")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htaddpict.clipboardRect"] == "10,20,30,40")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htaddpict.removedOverlayCount"] == "1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htaddpict.transferMode"] == "srcCopy")
    }

    @Test func htSavePictCapturesPaintLayerClipboardAndRestoresOverlay() throws {
        let result = executeScript("""
        on test
          xLine "10,10","14,10",1,255
          HTSavePict "10,10,15,11","clipboard","srccopy"
          HTAddPict "","20,30,25,31","srccopy","clipboard"
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "clipboard")
        let document = try #require(result.modifiedDocument)
        let clipboardAsset = try #require(document.assetRepository.asset(byClassicMediaName: "clipboard", kind: .imageTexture))
        #expect(clipboardAsset.width == 5)
        #expect(clipboardAsset.height == 1)
        #expect(NSImage(data: clipboardAsset.data) != nil)

        let overlay = try #require(document.parts.first {
            $0.helpText == "hypercard-htaddpict" && $0.name == "HTAddPict Clipboard"
        })
        #expect(overlay.left == 20)
        #expect(overlay.top == 30)
        #expect(overlay.width == 5)
        #expect(overlay.height == 1)
        #expect(overlay.imageData == clipboardAsset.data)
        #expect(document.scriptGlobals["hypercard.htsavepict.captured"] == "true")
        #expect(document.scriptGlobals["hypercard.htsavepict.asset"] == "clipboard")
        #expect(document.scriptGlobals["hypercard.htaddpict.restoredClipboardAsset"] == "clipboard")
    }

    @Test func hyperTintPaletteAndRemoveRecordCompatibilityStateAndClearTransientParts() {
        let imageAsset = Asset(
            name: "Control Panel",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([1]),
            width: 20,
            height: 20,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "Control Panel")]
        )
        let iconAsset = Asset(
            name: "cicn_500",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([2]),
            width: 16,
            height: 16,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "cicn"),
                AssetMetadataEntry(key: "resource_id", value: "500")
            ]
        )
        let paletteAsset = Asset(
            name: "Myst User Palette",
            kind: .placeholderAsset,
            mimeType: "application/json",
            data: Data("""
            {"entries":[
              {"red":0,"green":0,"blue":0},
              {"red":65535,"green":32768,"blue":0},
              {"red":65535,"green":65535,"blue":65535}
            ]}
            """.utf8),
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "pltt"),
                AssetMetadataEntry(key: "resource_id", value: "9002"),
                AssetMetadataEntry(key: "resource_path", value: "resources/pltt_9002.json"),
                AssetMetadataEntry(key: "resource_artifact_format", value: "json")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [imageAsset, iconAsset, paletteAsset])

        let result = executeScript("""
        on test
          HTUDefPal 9002
          HyperTint "later","delay","iRes5","NoTEOpt"
          HTAddPict "Control Panel","10,20,30,40","srccopy"
          xCIcon3 "30,40",500
          HTRemove
          return the result
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "2")
        let transientParts = result.modifiedDocument?.parts.filter {
            ["hypercard-htaddpict", "hypercard-htchangepict", "hypercard-xcicon3", "hypercard-playqt"].contains($0.helpText)
        } ?? []
        #expect(transientParts.isEmpty)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.palette"] == "9002")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.status"] == "resolved")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.assetName"] == "Myst User Palette")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.resourceType"] == "pltt")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.resourcePath"] == "resources/pltt_9002.json")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.artifactFormat"] == "json")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.payloadStatus"] == "parsed")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.colorCount"] == "3")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.firstColor"] == "#000000")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.lastColor"] == "#FFFFFF")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.colors"] == "#000000\t#FF8000\t#FFFFFF")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.hypertint.timing"] == "later")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.hypertint.delay"] == "delay")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.hypertint.options"] == "iRes5\tNoTEOpt")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htremove.removedCount"] == "2")
    }

    @Test func htUDefPalRecordsMissingPaletteAssetState() {
        let result = executeScript("""
        on test
          HTUDefPal 42
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.palette"] == "42")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.status"] == "missing")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.htudefpal.assetName"] == nil)
    }

    @Test func htChangePictReplacesPriorCompatibilityImagePart() {
        let first = Asset(
            name: "First Screen",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([1]),
            metadata: [AssetMetadataEntry(key: "classic_name", value: "First Screen")]
        )
        let second = Asset(
            name: "Second Screen",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([2]),
            metadata: [AssetMetadataEntry(key: "classic_name", value: "Second Screen")]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [first, second])

        let result = executeScript("""
        on test
          HTChangePict "First Screen","0,0,20,20"
          HTChangePict "Second Screen","1,2,31,42"
          return the result
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "Second Screen")
        let parts = result.modifiedDocument?.parts.filter { $0.helpText == "hypercard-htchangepict" } ?? []
        #expect(parts.count == 1)
        #expect(parts.first?.imageData == Data([2]))
        #expect(parts.first?.left == 1)
        #expect(parts.first?.top == 2)
        #expect(parts.first?.width == 30)
        #expect(parts.first?.height == 40)
    }

    @Test func xCIcon3CreatesIconOverlayByResourceId() {
        let asset = Asset(
            name: "cicn_3000",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([3]),
            width: 16,
            height: 12,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "cicn"),
                AssetMetadataEntry(key: "resource_id", value: "3000")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [asset])

        let result = executeScript("""
        on test
          xCIcon3 "20,30",3000
          return the result
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "cicn_3000")
        let part = result.modifiedDocument?.parts.first { $0.helpText == "hypercard-xcicon3" }
        #expect(part?.left == 12)
        #expect(part?.top == 24)
        #expect(part?.width == 16)
        #expect(part?.height == 12)
        #expect(part?.transparentBackground == true)
    }

    @Test func pictureCreatesScrollableCompatibilityWindow() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let asset = Asset(
            name: "TowerScroll PICT",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 640,
            height: 480,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "TowerScroll")]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [asset])

        let result = executeScript("""
        on test
          Picture "TowerScroll",resource,rect,false,4
          if there is no window "TowerScroll" then return "missing"
          set the rect of window "TowerScroll" to "10,20,110,80"
          set the scroll of window "TowerScroll" to "30,40"
          set the dithering of window "TowerScroll" to false
          show window "TowerScroll"
          return the scroll of window "TowerScroll"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "30,40")
        let part = result.modifiedDocument?.parts.first { $0.helpText == "hypercard-picture" }
        #expect(part?.partType == .image)
        #expect(part?.name == "TowerScroll")
        #expect(part?.left == 10)
        #expect(part?.top == 20)
        #expect(part?.width == 100)
        #expect(part?.height == 60)
        #expect(part?.visible == true)
        #expect(part?.imageData == imageData)
        let windowKey = AssetRepository.classicMediaLookupKey("TowerScroll")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).exists"] == "true")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).visible"] == "true")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).scroll"] == "30,40")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).dithering"] == "false")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.picture.depth"] == "4")
    }

    @Test func closeWindowRemovesPictureCompatibilityWindow() {
        let asset = Asset(
            name: "Telescope Frame",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([4]),
            width: 320,
            height: 240,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "telescope4")]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [asset])

        let result = executeScript("""
        on test
          Picture "telescope4",resource,rect,false,4
          close window "telescope4"
          if there is a window "telescope4" then return "open"
          return "closed"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.returnValue == "closed")
        #expect(result.modifiedDocument?.parts.contains { $0.helpText == "hypercard-picture" } == false)
        let windowKey = AssetRepository.classicMediaLookupKey("telescope4")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).exists"] == "false")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).visible"] == "false")
    }

    @Test func pictureMissingAssetSetsResultDiagnostic() {
        let result = executeScript("""
        on test
          Picture "MissingPict",resource,rect,false
          return the result
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.returnValue == "Picture asset not found: MissingPict")
        #expect(result.modifiedDocument?.parts.contains { $0.helpText == "hypercard-picture" } == false)
        let windowKey = AssetRepository.classicMediaLookupKey("MissingPict")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).exists"] == "false")
    }

    private func testPNG(
        width: Int,
        height: Int,
        pixels: [(UInt8, UInt8, UInt8, UInt8)]
    ) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ))
        for y in 0..<height {
            for x in 0..<width {
                let pixel = pixels[y * width + x]
                rep.setColor(
                    NSColor(
                        calibratedRed: CGFloat(pixel.0) / 255.0,
                        green: CGFloat(pixel.1) / 255.0,
                        blue: CGFloat(pixel.2) / 255.0,
                        alpha: CGFloat(pixel.3) / 255.0
                    ),
                    atX: x,
                    y: y
                )
            }
        }
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func playQTCreatesRepositoryBackedVideoPartByClassicName() {
        let movie = Asset(
            name: "AtrusWrite-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "AtrusWrite"),
                AssetMetadataEntry(key: "lookup_key", value: "atruswrite")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          xSetSoundVol 128
          playQT "AtrusWrite", "loop"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.cardId == doc.cards[0].id)
        #expect(videoPart?.name == "AtrusWrite")
        #expect(videoPart?.videoAssetRef?.id == movie.id)
        #expect(videoPart?.videoURL == "asset://\(movie.id.uuidString)")
        #expect(videoPart?.videoAutoplay == true)
        #expect(videoPart?.videoLoop == true)
        #expect(videoPart?.videoVolume == 128.0 / 255.0)
    }

    @Test func playQTTreatsBareLoopTokenAsClassicFlag() {
        let movie = Asset(
            name: "AtrusWrite-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "AtrusWrite"),
                AssetMetadataEntry(key: "lookup_key", value: "atruswrite")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          playQT "AtrusWrite",,loop,30
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.name == "AtrusWrite")
        #expect(videoPart?.videoAutoplay == true)
        #expect(videoPart?.videoLoop == true)
    }

    @Test func playQTTreatsTwoWordClassicQTCommandAsVideoPlayback() {
        let movie = Asset(
            name: "EV Wind Water-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "EV Wind/Water Mov"),
                AssetMetadataEntry(key: "lookup_key", value: "ev wind water mov")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          play QT "EV Wind/Water Mov", , loop, 250
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.name == "EV Wind/Water Mov")
        #expect(videoPart?.videoAssetRef?.id == movie.id)
        #expect(videoPart?.videoAutoplay == true)
        #expect(videoPart?.videoLoop == true)
    }

    @Test func playQTTreatsAudioOnlyQuickTimeAsHiddenPlaybackPart() {
        let movie = Asset(
            name: "Intro Wind Mov-modern-audio.m4a",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("audio".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "Intro Wind Mov"),
                AssetMetadataEntry(key: "lookup_key", value: "intro wind mov"),
                AssetMetadataEntry(key: "quicktime_audio_only", value: "true")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          playQT "Intro Wind Mov"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.name == "Intro Wind Mov")
        #expect(videoPart?.width == 1)
        #expect(videoPart?.height == 1)
        #expect(videoPart?.helpText.contains("audioOnly=true") == true)
        #expect(videoPart?.videoAssetRef?.id == movie.id)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.playqt.audioOnly"] == "true")
    }

    @Test func playQTTracksActiveMystSoundMovieGlobal() {
        let movie = Asset(
            name: "EL GenAll MoV-modern-audio.m4a",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("audio".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "EL GenAll MoV"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("EL GenAll MoV")),
                AssetMetadataEntry(key: "classic_alias", value: "El GenRun"),
                AssetMetadataEntry(key: "quicktime_audio_only", value: "true")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          playQT "El GenRun",,loop,150
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["soundMooV"] == "El GenRun")
        #expect(result.modifiedDocument?.scriptGlobals["soundmoov"] == "El GenRun")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.playqt.asset"] == movie.name)
    }

    @Test func mystSoundTimeRetimesActiveSoundMoviePart() {
        let movie = Asset(
            name: "EL GenAll MoV-modern-audio.m4a",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("audio".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "EL GenAll MoV"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("EL GenAll MoV")),
                AssetMetadataEntry(key: "quicktime_audio_only", value: "true")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          playQT "EL GenAll MoV",,loop,150
          soundTime "5,05","0","0","9,30"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.name == "EL GenAll MoV")
        #expect(videoPart?.videoCurrentTime == 0)
        #expect(videoPart?.videoDuration == 9.5)
        #expect(videoPart?.videoAutoplay == true)
        #expect(videoPart?.videoPlayRate == 1)
        let globals = result.modifiedDocument?.scriptGlobals ?? [:]
        #expect(globals["hypercard.soundtime.window"] == "EL GenAll MoV")
        #expect(globals["hypercard.window.el genall mov.starttime"] == "5.083333333333333")
        #expect(globals["hypercard.window.el genall mov.currtime"] == "0")
        #expect(globals["hypercard.window.el genall mov.endtime"] == "9.5")
    }

    @Test func mystSoundStopStopsActiveSoundMoviePart() {
        let movie = Asset(
            name: "EL GenAll MoV-modern-audio.m4a",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("audio".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "EL GenAll MoV"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("EL GenAll MoV")),
                AssetMetadataEntry(key: "quicktime_audio_only", value: "true")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          playQT "EL GenAll MoV",,loop,150
          soundStop
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.videoAutoplay == false)
        #expect(videoPart?.videoPlayRate == 0)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.soundstop.count"] == "1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.sound.state"] == "done")
    }

    @Test func buzzerCreatesHiddenAudioPlaybackPartByClassicName() {
        let sound = Asset(
            name: "SW Buzzer-modern-audio.m4a",
            kind: .audioClip,
            mimeType: "audio/mp4",
            data: Data("sound".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "SW Buzzer"),
                AssetMetadataEntry(key: "lookup_key", value: "sw buzzer")
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [sound])

        let result = executeScript("""
        on test
          Buzzer 128
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.cardId == doc.cards[0].id)
        #expect(videoPart?.name == "SW Buzzer")
        #expect(videoPart?.width == 1)
        #expect(videoPart?.height == 1)
        #expect(videoPart?.videoAssetRef?.id == sound.id)
        #expect(videoPart?.videoURL == "asset://\(sound.id.uuidString)")
        #expect(videoPart?.videoAutoplay == true)
        #expect(videoPart?.videoLoop == false)
        #expect(videoPart?.videoVolume == 128.0 / 255.0)
        #expect(videoPart?.helpText.contains("hypercard-buzzer") == true)
        #expect(videoPart?.helpText.contains("audioOnly=true") == true)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.buzzer.asset"] == sound.name)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.buzzer.volume"] == "128")
    }

    @Test func dplayQueuesDelayedSoundNamesForImportedOpenCardHandlers() {
        let result = executeScript("""
        on test
          dplay "DR wood open"
          dplay "DR wood shut"
        end test
        """)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["hcsounds"] == "DR wood open\rDR wood shut\r")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.dplay.lastSound"] == "DR wood shut")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.dplay.queueDepth"] == "2")
    }

    @Test func movieCreatesRepositoryBackedVideoPartAtClassicPoint() {
        let movie = Asset(
            name: "MystLib-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 160,
            height: 90,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "MystLib.MooV"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("MystLib.MooV"))
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          Movie "MystLib.MooV","borderless","230,173","invisible","Floating"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.name == "MystLib.MooV")
        #expect(videoPart?.videoAssetRef?.id == movie.id)
        #expect(videoPart?.left == 230)
        #expect(videoPart?.top == 173)
        #expect(videoPart?.width == 160)
        #expect(videoPart?.height == 90)
        #expect(videoPart?.videoAutoplay == true)
    }

    @Test func movieWindowPropertySetsUpdateCompatibilityVideoPart() {
        let movie = Asset(
            name: "MystLib-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 160,
            height: 90,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "MystLib.MooV"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("MystLib.MooV"))
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          put "MystLib.MooV" into TheMovieName
          Movie TheMovieName,"borderless","230,173","invisible","Floating"
          set the loop of window TheMovieName to true
          set the rate of window TheMovieName to "0.0"
          set the audioLevel of window TheMovieName to "64"
          set the mute of window TheMovieName to true
          set the windowRect of window TheMovieName to "10,20,170,110"
          set the windowName of window TheMovieName to "MystLibWindow"
        end test
        """, document: doc)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.name == "MystLibWindow")
        #expect(videoPart?.videoLoop == true)
        #expect(videoPart?.videoAutoplay == false)
        #expect(videoPart?.videoVolume == 0)
        #expect(videoPart?.left == 10)
        #expect(videoPart?.top == 20)
        #expect(videoPart?.width == 160)
        #expect(videoPart?.height == 90)
        let windowKey = AssetRepository.classicMediaLookupKey("MystLib.MooV")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).loop"] == "true")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).rate"] == "0.0")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).audiolevel"] == "64")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).mute"] == "true")
    }

    @Test func quickTimeFadeHelpersUpdateImportedMovieWindowState() {
        let movie = Asset(
            name: "MystLib-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 160,
            height: 90,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "MystLib.MooV"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("MystLib.MooV"))
            ]
        )
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let fadedIn = executeScript("""
        on test
          Movie "MystLib.MooV","borderless","230,173","invisible","Floating"
          set the rate of window "MystLib.MooV" to "0.0"
          fadein "MystLib.MooV",150
        end test
        """, document: doc)

        #expect(fadedIn.status == .completed)
        #expect(fadedIn.visualEffect == "fade in")
        let activeVideo = fadedIn.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(activeVideo?.videoAutoplay == true)
        #expect(activeVideo?.videoVolume == 150.0 / 255.0)
        let windowKey = AssetRepository.classicMediaLookupKey("MystLib.MooV")
        #expect(fadedIn.modifiedDocument?.scriptGlobals["hypercard.fadein.window"] == "MystLib.MooV")
        #expect(fadedIn.modifiedDocument?.scriptGlobals["hypercard.fadein.volume"] == "150")
        #expect(fadedIn.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).rate"] == "1.0")

        guard let document = fadedIn.modifiedDocument else {
            Issue.record("fadein did not return a modified document")
            return
        }
        let fadedOut = executeScript("""
        on test
          fadeout
        end test
        """, document: document)

        #expect(fadedOut.status == .completed)
        #expect(fadedOut.visualEffect == "fade out")
        let stoppedVideo = fadedOut.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(stoppedVideo?.videoAutoplay == false)
        #expect(stoppedVideo?.videoVolume == 0)
        #expect(fadedOut.modifiedDocument?.scriptGlobals["hypercard.fadeout.count"] == "1")
    }

    @Test func closeMoovsRemovesCompatibilityVideoParts() {
        let movie = Asset(name: "Intro Wind Mov", kind: .videoClip, mimeType: "video/quicktime", data: Data("movie".utf8))
        var doc = HypeDocument.newDocument()
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          playQT "Intro Wind Mov"
          closemoovs
        end test
        """, document: doc)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.parts.contains { $0.partType == .video } == false)
    }

    @Test func exposesClassicHandlerParameterAccessors() {
        let result = executeScript("""
        on test firstName, lastName
          put the paramCount & ":" & param 1 & ":" & param(2) & ":" & the params into summary
          return summary
        end test
        """, params: ["Ada", "Lovelace"])

        #expect(result.status == .completed)
        #expect(result.returnValue == "2:Ada:Lovelace:Ada\rLovelace")
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

    @Test func dispatchesToPartScript() async {
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
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        #expect(result.returnValue == "clicked")
    }

    @Test func commandStyleHandlerCallDispatchesWithArgumentsBeforeExternalFallback() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var btn = Part(partType: .button, cardId: cardId, name: "BuzzerButton")
        btn.script = """
        on mouseUp
          Buzzer 4
        end mouseUp
        """
        doc.stack.script = """
        on Buzzer amount
          global buzzerAmount
          put amount into buzzerAmount
        end Buzzer
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["buzzeramount"] == "4")
    }

    @Test func bareHandlerCommandDispatchesWithoutArguments() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var btn = Part(partType: .button, cardId: cardId, name: "ResetButton")
        btn.script = """
        on mouseUp
          resetDrawers
        end mouseUp
        """
        doc.stack.script = """
        on resetDrawers
          global drawersReset
          put "true" into drawersReset
        end resetDrawers
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["drawersreset"] == "true")
    }

    @Test func functionCallDispatchesThroughMessagePath() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)
        var btn = Part(partType: .button, cardId: cardId, name: "FunctionButton")
        btn.script = """
        on mouseUp
          put doubleIt(5) into field "output"
        end mouseUp
        """
        doc.stack.script = """
        function doubleIt amount
          return amount * 2
        end doubleIt
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        let output = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(output?.textContent == "10")
    }

    @Test func functionCallAfterLocalGoUsesDestinationCardContext() async {
        var doc = HypeDocument.newDocument()
        let firstCard = doc.cards[0]
        let bookCard = Card(
            stackId: doc.stack.id,
            backgroundId: firstCard.backgroundId,
            name: "Book",
            sortKey: "a1",
            script: """
            function pageName
              return "Page1"
            end pageName
            """
        )
        doc.cards.append(bookCard)
        var btn = Part(partType: .button, cardId: firstCard.id, name: "OpenBook")
        btn.script = """
        on mouseUp
          global resultName
          go to card "Book"
          put pageName() into resultName
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, firstCard, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: firstCard.id
        ) }

        #expect(result.status == .completed)
        #expect(result.navigationTarget == bookCard.id)
        #expect(result.modifiedDocument?.scriptGlobals["resultname"] == "Page1")
    }

    @Test func localHandlerCommandAfterLocalGoUsesDestinationCardContext() async {
        var doc = HypeDocument.newDocument()
        let firstCard = doc.cards[0]
        let bookCard = Card(
            stackId: doc.stack.id,
            backgroundId: firstCard.backgroundId,
            name: "Book",
            sortKey: "a1"
        )
        doc.cards.append(bookCard)
        doc.addPart(Part(partType: .field, cardId: bookCard.id, name: "output"))
        var btn = Part(partType: .button, cardId: firstCard.id, name: "OpenBook")
        btn.script = """
        on mouseUp
          go to card "Book"
          UpdateBook
        end mouseUp

        on UpdateBook
          put "arrived" into field "output"
        end UpdateBook
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, firstCard, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: firstCard.id
        ) }

        #expect(result.status == .completed)
        #expect(result.navigationTarget == bookCard.id)
        let output = result.modifiedDocument?.parts.first { $0.name == "output" }
        #expect(output?.textContent == "arrived")
    }

    @Test func mystPillarClickTogglesStateAndRefreshesMarkerIcon() async {
        let offIcon = Asset(
            name: "cicn_2012",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0x20, 0x12]),
            width: 10,
            height: 8,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "cicn"),
                AssetMetadataEntry(key: "resource_id", value: "2012")
            ]
        )
        let onIcon = Asset(
            name: "cicn_2002",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0x20, 0x02]),
            width: 10,
            height: 8,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "cicn"),
                AssetMetadataEntry(key: "resource_id", value: "2002")
            ]
        )
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.assetRepository = AssetRepository(assets: [offIcon, onIcon])
        var marker = Part(
            partType: .button,
            cardId: cardId,
            name: "Marker2",
            left: 40,
            top: 50,
            width: 20,
            height: 10
        )
        marker.script = """
        on mouseUp
          pillarClick 2
        end mouseUp
        """
        doc.addPart(marker)

        let dispatcher = MessageDispatcher()
        let first = await runOnLargeStack { [doc, cardId, marker] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: marker.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(first.status == .completed)
        #expect(first.modifiedDocument?.scriptGlobals["MY_Pillars"] == "off,on,off,off,off,off,off,off")
        #expect(first.modifiedDocument?.scriptGlobals["MY_boat"] == "")
        #expect(first.modifiedDocument?.scriptGlobals["hypercard.myst.pillar.icon"] == "2002")
        let firstOverlay = first.modifiedDocument?.parts.first { $0.helpText == "hypercard-xcicon3" }
        #expect(firstOverlay?.name == "xCIcon3 cicn_2002")
        #expect(firstOverlay?.left == 45)
        #expect(firstOverlay?.top == 51)

        let secondDocument = first.modifiedDocument ?? doc
        let second = await runOnLargeStack { [secondDocument, cardId, marker] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: marker.id,
            document: secondDocument,
            currentCardId: cardId
        ) }
        #expect(second.status == .completed)
        #expect(second.modifiedDocument?.scriptGlobals["MY_Pillars"] == "off,off,off,off,off,off,off,off")
        #expect(second.modifiedDocument?.scriptGlobals["hypercard.myst.pillar.icon"] == "2012")
    }

    @Test func mystPillarClickRaisesAndLowersBoatStateForSolutionPattern() async {
        let onIcon = Asset(
            name: "cicn_2008",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0x20, 0x08]),
            width: 8,
            height: 8,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "cicn"),
                AssetMetadataEntry(key: "resource_id", value: "2008")
            ]
        )
        let offIcon = Asset(
            name: "cicn_2018",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0x20, 0x18]),
            width: 8,
            height: 8,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "cicn"),
                AssetMetadataEntry(key: "resource_id", value: "2018")
            ]
        )
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.assetRepository = AssetRepository(assets: [onIcon, offIcon])
        doc.scriptGlobals["MY_Pillars"] = "off,on,off,off,on,on,off,on"
        doc.scriptGlobals["MY_boat"] = "up"
        var marker = Part(partType: .button, cardId: cardId, name: "Marker8")
        marker.script = """
        on mouseUp
          pillarClick 8
        end mouseUp
        """
        doc.addPart(marker)

        let dispatcher = MessageDispatcher()
        let raised = await runOnLargeStack { [doc, cardId, marker] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: marker.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(raised.status == .completed)
        #expect(raised.modifiedDocument?.scriptGlobals["MY_Pillars"] == "off,on,off,off,on,on,off,off")
        #expect(raised.modifiedDocument?.scriptGlobals["MY_boat"] == "up")

        let loweredDocument = raised.modifiedDocument ?? doc
        let lowered = await runOnLargeStack { [loweredDocument, cardId, marker] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: marker.id,
            document: loweredDocument,
            currentCardId: cardId
        ) }
        #expect(lowered.status == .completed)
        #expect(lowered.modifiedDocument?.scriptGlobals["MY_Pillars"] == "off,on,off,off,on,on,off,on")
        #expect(lowered.modifiedDocument?.scriptGlobals["MY_boat"] == "down")
    }

    @Test func mystPushKeyRefreshesPressedKeyIconAndMaskLocation() async {
        let keyIcon = Asset(
            name: "cicn_1005",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0x10, 0x05]),
            width: 14,
            height: 10,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "cicn"),
                AssetMetadataEntry(key: "resource_id", value: "1005")
            ]
        )
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.assetRepository = AssetRepository(assets: [keyIcon])
        var key = Part(
            partType: .button,
            cardId: cardId,
            name: "5",
            left: 100,
            top: 80,
            width: 20,
            height: 12
        )
        key.script = """
        on mouseDown
          pushKey the short name of me
        end mouseDown
        """
        let mask = Part(partType: .button, cardId: cardId, name: "mask", left: 0, top: 0, width: 4, height: 4)
        doc.addPart(key)
        doc.addPart(mask)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, key] in dispatcher.dispatch(
            message: "mouseDown",
            params: [],
            targetId: key.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.returnValue == "5")
        #expect(result.modifiedDocument?.scriptGlobals["keyCounter"] == "0")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.myst.pushkey.key"] == "5")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.myst.pushkey.icon"] == "1005")
        let updatedMask = result.modifiedDocument?.parts.first { $0.name == "mask" }
        #expect(updatedMask?.left == 110)
        #expect(updatedMask?.top == 86)
        let overlay = result.modifiedDocument?.parts.first { $0.helpText == "hypercard-xcicon3" }
        #expect(overlay?.name == "xCIcon3 cicn_1005")
        #expect(overlay?.left == 103)
        #expect(overlay?.top == 81)
    }

    @Test func mystClockGearHelpersPrepareAndAdvanceGearWindows() async {
        let gearMovie = Asset(
            name: "Clock1-W Gear1-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 90,
            height: 80,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "Clock1-W Gear1.MooV"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("Clock1-W Gear1.MooV"))
            ]
        )
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.assetRepository = AssetRepository(assets: [gearMovie])
        var marker = Part(partType: .button, cardId: cardId, name: "gear1", left: 42, top: 73, width: 20, height: 20)
        marker.visible = false
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = """
        on mouseDown
          PreGear 1,2
          gear 1
        end mouseDown
        """
        doc.addPart(marker)
        doc.addPart(button)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, button] in dispatcher.dispatch(
            message: "mouseDown",
            params: [],
            targetId: button.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.returnValue == "900")
        let windowKey = AssetRepository.classicMediaLookupKey("Clock1-W Gear1.MooV")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.myst.gear.which"] == "1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.myst.gear.action"] == "gear")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).currtime"] == "900")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).starttime"] == "600")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).endtime"] == "900")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.\(windowKey).rate"] == "0")
        let video = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(video?.name == "Clock1-W Gear1.MooV")
        #expect(video?.left == 42)
        #expect(video?.top == 73)
        #expect(video?.videoAssetRef?.id == gearMovie.id)
        #expect(video?.videoAutoplay == false)
    }

    @Test func mystClassicButtonCommandRecordsCompatibilityState() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var button = Part(partType: .button, cardId: cardId, name: "bookPage")
        button.script = """
        on mouseDown
          button 2,-1
        end mouseDown
        """
        doc.addPart(button)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, button] in dispatcher.dispatch(
            message: "mouseDown",
            params: [],
            targetId: button.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.returnValue == "2,-1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.button.last"] == "2,-1")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.button.index"] == "2")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.button.direction"] == "-1")
    }

    @Test func mystSeleniticShipMoveRecordsMovieRouteAndUpdatesWindow() async {
        let shipMovie = Asset(
            name: "*Left11-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 120,
            height: 80,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "*Left11"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("*Left11"))
            ]
        )
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.assetRepository = AssetRepository(assets: [shipMovie])
        var button = Part(partType: .button, cardId: cardId, name: "markerR")
        button.script = """
        on mouseDown
          shipMove "Left11"
        end mouseDown
        """
        doc.addPart(button)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, button] in dispatcher.dispatch(
            message: "mouseDown",
            params: [],
            targetId: button.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.returnValue == "*Left11")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.selenitic.shipMove.route"] == "Left11")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.selenitic.shipMove.movie"] == "*Left11")
        let video = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(video?.name == "Ship-Motion.MooV")
        #expect(video?.videoAssetRef?.id == shipMovie.id)
        #expect(video?.videoAutoplay == true)
    }

    @Test func mystSeleniticTowerScrollUpdatesHeadingAndCameraState() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.scriptGlobals["theScroll"] = "10"
        doc.scriptGlobals["SE_CameraID"] = "2"
        doc.scriptGlobals["SE_Headings"] = "0\n10\n20"
        var offsets = Part(partType: .field, cardId: cardId, name: "offsets")
        offsets.textContent = "100\n200\n300"
        var heading = Part(partType: .field, cardId: cardId, name: "heading")
        heading.textContent = "2"
        var button = Part(partType: .button, cardId: cardId, name: "rght")
        button.script = """
        on mouseDown
          scrollTower 5
        end mouseDown
        """
        doc.addPart(offsets)
        doc.addPart(heading)
        doc.addPart(button)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, button] in dispatcher.dispatch(
            message: "mouseDown",
            params: [],
            targetId: button.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.returnValue == "15")
        #expect(result.modifiedDocument?.scriptGlobals["theScroll"] == "15")
        #expect(result.modifiedDocument?.scriptGlobals["SE_Headings"] == "0\n15\n20")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.towerscroll.scroll"] == "15,200")
        let updatedHeading = result.modifiedDocument?.parts.first { $0.name == "heading" }
        #expect(updatedHeading?.textContent == "3")
    }

    @Test func mystSeleniticCameraCommandUpdatesCameraState() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.scriptGlobals["SE_CameraID"] = "2"
        var button = Part(partType: .button, cardId: cardId, name: "mic")
        button.script = """
        on mouseDown
          camera 5
        end mouseDown
        """
        doc.addPart(button)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, button] in dispatcher.dispatch(
            message: "mouseDown",
            params: [],
            targetId: button.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.returnValue == "5")
        #expect(result.modifiedDocument?.scriptGlobals["SE_CameraID"] == "5")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.selenitic.camera"] == "5")
    }

    @Test func mystStoneshipTelescopeScrollWrapsClassicRange() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.scriptGlobals["theScroll"] = "3239"
        var button = Part(partType: .button, cardId: cardId, name: "left")
        button.script = """
        on mouseDown
          scrollTelescope 1
        end mouseDown
        """
        doc.addPart(button)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, button] in dispatcher.dispatch(
            message: "mouseDown",
            params: [],
            targetId: button.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.returnValue == "0")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.window.telescope4.scroll"] == "0,0")
    }

    @Test func updateCursorRecordsAgeCursorMode() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var button = Part(partType: .button, cardId: cardId, name: "cursor")
        button.script = """
        on mouseDown
          updateCursor ML
        end mouseDown
        """
        doc.addPart(button)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, button] in dispatcher.dispatch(
            message: "mouseDown",
            params: [],
            targetId: button.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.updateCursor.mode"] == "ML")
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.cursor.mode"] == "ML")
    }

    @Test func scopedFieldOfCardReferenceReadsAndWritesTargetCardField() async {
        var doc = HypeDocument.newDocument()
        let firstCard = doc.cards[0]
        let targetCard = Card(
            stackId: doc.stack.id,
            backgroundId: firstCard.backgroundId,
            name: "Defaults",
            sortKey: "a1"
        )
        doc.cards.append(targetCard)
        var defaultsField = Part(partType: .field, cardId: targetCard.id, name: "Defaults")
        defaultsField.textContent = "Myst defaults"
        doc.addPart(defaultsField)
        var outputField = Part(partType: .field, cardId: firstCard.id, name: "Output")
        doc.addPart(outputField)
        var btn = Part(partType: .button, cardId: firstCard.id, name: "Loader")
        btn.script = """
        on mouseUp
          put card field "Defaults" of card "Defaults" into RestoreData
          put RestoreData into card field "Output" of card 1
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, btn, firstCard] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: firstCard.id
        ) }

        #expect(result.status == .completed)
        let modified = result.modifiedDocument
        let output = modified?.parts.first(where: { $0.name == "Output" })
        #expect(output?.textContent == "Myst defaults")
    }

    @Test func scopedFieldOfCardIdReferenceReadsAndWritesMystPlanetariumFields() async {
        var doc = HypeDocument.newDocument(name: "Myst")
        let firstCard = doc.cards[0]
        let targetCard = Card(
            stackId: doc.stack.id,
            backgroundId: firstCard.backgroundId,
            name: "Planetarium",
            sortKey: "a1"
        )
        doc.cards.append(targetCard)
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "Myst",
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(
                        legacyCardId: 41677,
                        name: "Planetarium",
                        hypeCardId: targetCard.id
                    )
                ]
            )
        ])
        var sourceField = Part(partType: .field, cardId: targetCard.id, name: "month")
        sourceField.textContent = "7"
        doc.addPart(sourceField)
        var outputField = Part(partType: .field, cardId: firstCard.id, name: "month")
        doc.addPart(outputField)
        var btn = Part(partType: .button, cardId: firstCard.id, name: "PlanetariumLoader")
        btn.script = """
        on mouseUp
          put card field month of card id 41677 into card field month
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, btn, firstCard] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: firstCard.id
        ) }

        #expect(result.status == .completed)
        let output = result.modifiedDocument?.parts.first(where: { $0.name == "month" && $0.cardId == firstCard.id })
        #expect(output?.textContent == "7")
    }

    @Test func passedMessageContinuesUpHierarchy() async {
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
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
    }

    @Test func passedMessageCaughtByCardScript() async {
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
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "card caught it")
    }

    @Test func passedMessageCaughtByUsedStackScript() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var btn = Part(partType: .button, cardId: cardId, name: "PassBtn")
        btn.script = """
        on mouseUp
          pass mouseUp
        end mouseUp
        """
        doc.addPart(btn)

        let field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        let libraryStack = HypeStackLibraryEntry(
            stackName: "ALLRes",
            aliases: ["ALL Res"],
            source: .importedStackPackage,
            stackScript: """
            on mouseUp
              put "library caught it" into field "output"
            end mouseUp
            """
        )
        doc.stackLibrary = HypeStackLibrary(entries: [libraryStack], usedStackAliases: ["ALLRes"])

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "library caught it")
    }

    @Test func unusedStackScriptDoesNotCatchPassedMessage() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var btn = Part(partType: .button, cardId: cardId, name: "PassBtn")
        btn.script = """
        on mouseUp
          pass mouseUp
        end mouseUp
        """
        doc.addPart(btn)

        let field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        let libraryStack = HypeStackLibraryEntry(
            stackName: "ALLRes",
            source: .importedStackPackage,
            stackScript: """
            on mouseUp
              put "library caught it" into field "output"
            end mouseUp
            """
        )
        doc.stackLibrary = HypeStackLibrary(entries: [libraryStack])

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId,
            appScript: """
            on mouseUp
              put "app caught it" into field "output"
            end mouseUp
            """
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "app caught it")
    }

    @Test func messagePassesThroughCardToBackground() async {
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
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "bg caught it")
    }

    @Test func messageReachesStackScript() async {
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
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "stack caught it")
    }

    @Test func sendToThisStackInvokesStackHandler() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        var btn = Part(partType: .button, cardId: cardId, name: "Camp")
        btn.script = """
        on mouseUp
          send "doCamp" to this stack
        end mouseUp
        """
        doc.addPart(btn)

        doc.stack.script = """
        on doCamp
          put "camped" into field "output"
        end doCamp
        """

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "camped")
    }

    @Test func sendToThisCardInvokesCardHandler() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        var btn = Part(partType: .button, cardId: cardId, name: "Source")
        btn.script = """
        on mouseUp
          send "doCard" to this card
        end mouseUp
        """
        doc.addPart(btn)

        if let idx = doc.cards.firstIndex(where: { $0.id == cardId }) {
            doc.cards[idx].script = """
            on doCard
              put "card handled" into field "output"
            end doCard
            """
        }

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "card handled")
    }

    @Test func sendToBareCardInvokesCurrentCardHandler() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        var btn = Part(partType: .button, cardId: cardId, name: "Source")
        btn.script = """
        on mouseUp
          send doCard to card
        end mouseUp
        """
        doc.addPart(btn)

        if let idx = doc.cards.firstIndex(where: { $0.id == cardId }) {
            doc.cards[idx].script = """
            on doCard
              put "bare card handled" into field "output"
            end doCard
            """
        }

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "bare card handled")
    }

    @Test func sendToThisBackgroundInvokesBackgroundHandler() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let bgId = doc.cards[0].backgroundId

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        var btn = Part(partType: .button, cardId: cardId, name: "Source")
        btn.script = """
        on mouseUp
          send "doBackground" to this background
        end mouseUp
        """
        doc.addPart(btn)

        if let idx = doc.backgrounds.firstIndex(where: { $0.id == bgId }) {
            doc.backgrounds[idx].script = """
            on doBackground
              put "background handled" into field "output"
            end doBackground
            """
        }

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "background handled")
    }

    @Test func sendToNamedButtonInvokesThatButtonHandler() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        var source = Part(partType: .button, cardId: cardId, name: "Source")
        source.script = """
        on mouseUp
          send "doTarget" to button "Target"
        end mouseUp
        """
        doc.addPart(source)

        var target = Part(partType: .button, cardId: cardId, name: "Target")
        target.script = """
        on doTarget
          put "target handled" into field "output"
        end doTarget
        """
        doc.addPart(target)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId, source] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: source.id,
            document: doc,
            currentCardId: cardId
        ) }
        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "target handled")
    }
}

@Suite("Go Navigation Integration", .serialized)
struct GoNavigationTests {

    @Test func goPreviousFromSecondCard() async {
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
        let result = await runOnLargeStack { [doc, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: card2.id
        ) }

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card1.id, "go previous should navigate to card 1, got \(String(describing: result.navigationTarget))")
    }

    @Test func goNextFromFirstCard() async {
        var doc = HypeDocument.newDocument(name: "Nav Test")
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]

        var btn = Part(partType: .button, cardId: card1.id, name: "Next")
        btn.script = "on mouseUp\n  go next\nend mouseUp"
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: card1.id
        ) }

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card2.id, "go next should navigate to card 2, got \(String(describing: result.navigationTarget))")
    }

    @Test func goToLocalLegacyCardIdUsesStackLibraryReference() async {
        var doc = HypeDocument.newDocument(name: "Myst")
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "Myst",
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 21776, name: "Dock", sortIndex: 0, hypeCardId: card1.id),
                    HypeStackLibraryCardReference(legacyCardId: 22764, name: "Forward", sortIndex: 1, hypeCardId: card2.id)
                ]
            )
        ])

        var btn = Part(partType: .button, cardId: card1.id, name: "Forward")
        btn.script = """
        on mouseUp
          go to card id 22764
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: card1.id
        ) }

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card2.id)
    }

    @Test func goToLocalLegacyCardIdChoosesCurrentEntryWhenStackNamesCollide() async {
        var doc = HypeDocument.newDocument(name: "Myst")
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]
        let applicationCardId = UUID()
        doc.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: " Myst",
                aliases: ["Myst", "Myst-Application"],
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 22764, name: "Application", sortIndex: 0, hypeCardId: applicationCardId)
                ]
            ),
            HypeStackLibraryEntry(
                stackName: " Myst",
                aliases: ["Myst"],
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(legacyCardId: 21776, name: "Dock", sortIndex: 0, hypeCardId: card1.id),
                    HypeStackLibraryCardReference(legacyCardId: 22764, name: "Forward", sortIndex: 1, hypeCardId: card2.id)
                ]
            )
        ])

        var btn = Part(partType: .button, cardId: card1.id, name: "Forward")
        btn.script = """
        on mouseUp
          go to card id 22764
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: card1.id
        ) }

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card2.id)
    }

    @Test func visualEffectIsCarriedWithNavigation() async {
        var doc = HypeDocument.newDocument(name: "Transition Test")
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]

        var btn = Part(partType: .button, cardId: card1.id, name: "Next")
        btn.script = """
        on mouseUp
          visual effect wipe left 1.5
          go next
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: card1.id
        ) }

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card2.id)
        #expect(result.visualEffect == "wipe left")
        #expect(result.visualEffectDuration == 1.5)
    }

    @Test func visualEffectSurvivesPassAfterNavigation() async {
        var doc = HypeDocument.newDocument(name: "Transition Pass Test")
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]

        var btn = Part(partType: .button, cardId: card1.id, name: "Next")
        btn.script = """
        on mouseUp
          visual effect flip horizontal 0.25
          go next
          pass mouseUp
        end mouseUp
        """
        doc.addPart(btn)

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: card1.id
        ) }

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card2.id)
        #expect(result.visualEffect == "flip horizontal")
        #expect(result.visualEffectDuration == 0.25)
    }
}

@Suite("Put Into Field Integration", .serialized)
struct PutIntoFieldTests {

    @Test func putIntoFieldByName() async {
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
        let result = await runOnLargeStack { [doc, cardId, btn] in dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btn.id,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        // The modified document should have the field's textContent updated
        let modifiedField = result.modifiedDocument?.parts.first(where: { $0.name == "url" })
        #expect(modifiedField != nil, "Field 'url' should exist in modified document")
        #expect(modifiedField?.textContent == "Hello", "Field 'url' textContent should be 'Hello', got '\(modifiedField?.textContent ?? "nil")'")
    }
}

@Suite("Parser Put Into Field", .serialized)
struct ParserPutTests {
    @Test func parsePutIntoField() async throws {
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

    @Test func ifElseWithHiliteTrue() async {
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
        let result = await runOnLargeStack { [doc, cardId, toggle] in dispatcher.dispatch(message: "mouseUp", params: [], targetId: toggle.id, document: doc, currentCardId: cardId) }

        #expect(result.status != .error, "Script should not error: \(result.error?.message ?? "")")
        let statusField = result.modifiedDocument?.parts.first(where: { $0.name == "status" })
        #expect(statusField?.textContent == "Checked!", "Expected 'Checked!' but got '\(statusField?.textContent ?? "nil")'")
    }

    @Test func ifElseWithHiliteFalse() async {
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
        let result = await runOnLargeStack { [doc, cardId, toggle] in dispatcher.dispatch(message: "mouseUp", params: [], targetId: toggle.id, document: doc, currentCardId: cardId) }

        #expect(result.status != .error, "Script should not error: \(result.error?.message ?? "")")
        let statusField = result.modifiedDocument?.parts.first(where: { $0.name == "status" })
        #expect(statusField?.textContent == "Unchecked", "Expected 'Unchecked' but got '\(statusField?.textContent ?? "nil")'")
    }
}

@Suite("Debug If/Else", .serialized)
struct DebugIfElseTests {
    @Test func debugTokensAndParse() async {
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

    @Test("'the number of bg fields' parses without error") func numberOfBgFields() async {
        let err = parseError("""
            on test
              put the number of bg fields into n
            end test
            """)
        #expect(err == nil, "number of bg fields failed: \(err ?? "")")
    }

    @Test("'the number of background fields' parses without error") func numberOfBackgroundFields() async {
        let err = parseError("""
            on test
              put the number of background fields into n
            end test
            """)
        #expect(err == nil, "number of background fields failed: \(err ?? "")")
    }

    @Test("'the number of bg buttons' parses without error") func numberOfBgButtons() async {
        let err = parseError("""
            on test
              put the number of bg buttons into n
            end test
            """)
        #expect(err == nil, "number of bg buttons failed: \(err ?? "")")
    }

    @Test("'the number of backgrounds' parses without error") func numberOfBackgrounds() async {
        let err = parseError("""
            on test
              put the number of backgrounds into n
            end test
            """)
        #expect(err == nil, "number of backgrounds failed: \(err ?? "")")
    }

    @Test("'the number of cards div 2' parses without error") func numberOfCardsDivTwo() async {
        let err = parseError("""
            on test
              put the number of cards div 2 into n
            end test
            """)
        #expect(err == nil, "number of cards div 2 failed: \(err ?? "")")
    }

    @Test("'the number of cards mod 3' parses without error") func numberOfCardsModThree() async {
        let err = parseError("""
            on test
              put the number of cards mod 3 into n
            end test
            """)
        #expect(err == nil, "number of cards mod 3 failed: \(err ?? "")")
    }

    @Test("'the number of card fields' parses without error") func numberOfCardFields() async {
        let err = parseError("""
            on test
              put the number of card fields into n
            end test
            """)
        #expect(err == nil, "number of card fields failed: \(err ?? "")")
    }

    @Test("'the number of card buttons' parses without error") func numberOfCardButtons() async {
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

    @Test("number of bg fields returns correct count") func numberOfBgFieldsInterpreter() async {
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

    @Test("number of backgrounds returns correct count") func numberOfBackgroundsInterpreter() async {
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

    @Test("number of cards div 2 returns half the card count") func numberOfCardsDivTwoInterpreter() async {
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

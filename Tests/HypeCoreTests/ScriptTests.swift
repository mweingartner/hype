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
        guard case .objectRef(let ref) = target else {
            Issue.record("Expected stack object reference")
            return
        }
        #expect(ref.objectType == "stack")
    }

    @Test func parsesClassicCrossStackGoStatement() throws {
        var lexer = Lexer(source: """
        on mouseUp
          go card "Dock" of stack "Myst"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        guard case .goInStack(let card, let stack) = script.handlers[0].body[0] else {
            Issue.record("Expected goInStack statement")
            return
        }
        guard case .literal(let cardName) = card,
              case .literal(let stackName) = stack else {
            Issue.record("Expected literal card and stack names")
            return
        }
        #expect(cardName == "Dock")
        #expect(stackName == "Myst")
    }

    @Test func parsesClassicDialogAndSendForms() throws {
        var lexer = Lexer(source: """
        on mouseUp
          ask "Where?" with "dock"
          answer "Go?" with "OK"
          send "openCard"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        #expect(script.handlers[0].body.count == 3)
        guard case .ask(_, let defaultResponse) = script.handlers[0].body[0],
              case .literal(let defaultValue) = defaultResponse else {
            Issue.record("Expected ask default response")
            return
        }
        #expect(defaultValue == "dock")
        guard case .answer(_, let buttons) = script.handlers[0].body[1] else {
            Issue.record("Expected answer buttons")
            return
        }
        #expect(buttons.count == 1)
        guard case .send(_, let target) = script.handlers[0].body[2] else {
            Issue.record("Expected bare send")
            return
        }
        #expect(target == nil)
    }

    @Test func parsesClassicFieldOfCardReference() throws {
        var lexer = Lexer(source: """
        on mouseUp
          put "open" into field "state" of card "Dock"
        end mouseUp
        """)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        guard case .put(_, _, let target) = script.handlers[0].body[0],
              case .scopedObjectRef(let object, let owner) = target else {
            Issue.record("Expected scoped field reference")
            return
        }
        #expect(object.objectType == "field")
        #expect(owner.objectType == "card")
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

    private func executeScript(_ source: String, document: HypeDocument, cardId: UUID) -> ExecutionResult {
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            return ExecutionResult(status: .error, error: ScriptError(message: "Parse failed", line: 0, handler: ""))
        }
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        return Interpreter().execute(handler: handler, params: [], context: context)
    }

    @Test func movieInfoReturnsRepositoryBackedMovieMetadata() async {
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
        let cardId = doc.cards[0].id
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          return movieInfo("Myst:Myst Graphics:Myst:Intro Wind Mov")
        end test
        """, document: doc, cardId: cardId)

        #expect(result.status == .completed)
        #expect(result.returnValue?.contains("name:\tIntro Wind Mov") == true)
        #expect(result.returnValue?.contains("asset:\tIntro Wind Mov-modern.mov") == true)
        #expect(result.returnValue?.contains("bytes:\t2048") == true)
        #expect(result.returnValue?.contains("bounds:\t0,0,160,90") == true)
        #expect(result.modifiedDocument?.scriptGlobals["hypercard.movieinfo.found"] == "true")
    }

    @Test func playQTCreatesRepositoryBackedVideoPartByClassicName() async {
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
        let cardId = doc.cards[0].id
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          xSetSoundVol 128
          playQT "AtrusWrite", "loop"
        end test
        """, document: doc, cardId: cardId)

        #expect(result.status == .completed)
        let videoPart = result.modifiedDocument?.parts.first { $0.partType == .video }
        #expect(videoPart?.cardId == cardId)
        #expect(videoPart?.name == "AtrusWrite")
        #expect(videoPart?.videoAssetRef?.id == movie.id)
        #expect(videoPart?.videoURL == "asset://\(movie.id.uuidString)")
        #expect(videoPart?.videoAutoplay == true)
        #expect(videoPart?.videoLoop == true)
        #expect(videoPart?.videoVolume == 128.0 / 255.0)
    }

    @Test func movieWindowPropertySetsUpdateCompatibilityVideoPart() async {
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
        let cardId = doc.cards[0].id
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
        """, document: doc, cardId: cardId)

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
    }

    @Test func closeMoovsRemovesCompatibilityVideoParts() async {
        let movie = Asset(name: "Intro Wind Mov", kind: .videoClip, mimeType: "video/quicktime", data: Data("movie".utf8))
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.assetRepository = AssetRepository(assets: [movie])

        let result = executeScript("""
        on test
          playQT "Intro Wind Mov"
          closemoovs
        end test
        """, document: doc, cardId: cardId)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.parts.contains { $0.partType == .video } == false)
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

    @Test func goToCardInStackResolvesProjectNavigationTargetByName() {
        var doc = HypeDocument.newDocument(name: "Myst")
        let cardId = doc.cards[0].id
        let entry = HypeStackLibraryEntry(
            stackName: "Myst",
            source: .importedStackPackage,
            packagePath: "Myst.xstk",
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 44018, name: "Dock", sortIndex: 0, hypeCardId: cardId)
            ]
        )
        doc.stackLibrary = HypeStackLibrary(entries: [entry])

        let result = executeScript("""
        on mouseUp
          go card "Dock" of stack "Myst"
        end mouseUp
        """, document: doc, cardId: cardId)

        #expect(result.status == .completed)
        #expect(result.projectNavigationTarget?.stackEntryId == entry.id)
        #expect(result.projectNavigationTarget?.cardName == "Dock")
        #expect(result.projectNavigationTarget?.legacyCardId == 44018)
    }

    @Test func doBlockExecutesGeneratedCrossStackGo() {
        var doc = HypeDocument.newDocument(name: "Myst")
        let cardId = doc.cards[0].id
        let entry = HypeStackLibraryEntry(
            stackName: "Myst",
            source: .importedStackPackage,
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 46439, name: "Black", sortIndex: 1, hypeCardId: cardId)
            ]
        )
        doc.stackLibrary = HypeStackLibrary(entries: [entry])

        let result = executeScript("""
        on mouseUp
          do "go card id 46439 of stack Myst"
        end mouseUp
        """, document: doc, cardId: cardId)

        #expect(result.status == .completed)
        #expect(result.projectNavigationTarget?.cardName == "Black")
        #expect(result.projectNavigationTarget?.legacyCardId == 46439)
    }

    @Test func scopedFieldOfCardReferenceWritesTargetCardField() {
        var doc = HypeDocument.newDocument(name: "Myst")
        let firstCard = doc.cards[0]
        let secondCard = Card(stackId: doc.stack.id, backgroundId: firstCard.backgroundId, name: "Dock", sortKey: "a1")
        doc.cards.append(secondCard)
        let field = Part(partType: .field, cardId: secondCard.id, name: "state")
        doc.addPart(field)

        let result = executeScript("""
        on mouseUp
          put "open" into field "state" of card "Dock"
        end mouseUp
        """, document: doc, cardId: firstCard.id)

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.parts.first(where: { $0.id == field.id })?.textContent == "open")
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

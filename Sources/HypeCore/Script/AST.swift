import Foundation

// MARK: - Expressions

/// An expression in the HypeTalk AST.
public indirect enum Expression: Sendable {
    case literal(Value)
    case variable(String)
    case it
    case me
    case this  // the current part's content (textContent for fields, name for buttons)
    case binary(Expression, BinaryOp, Expression)
    case unary(UnaryOp, Expression)
    case functionCall(String, [Expression])
    case propertyAccess(String, Expression?)     // "the name of card 1"
    case chunk(ChunkType, ChunkRange, Expression) // "word 3 of field 1"
    case objectRef(ObjectRefExpr)
    case not(Expression)
    case contains(Expression, Expression)         // "x contains y"
    case stringConcat(Expression, Expression)     // x & y
    case spacedConcat(Expression, Expression)     // x && y
    case empty
    case isIn(Expression, Expression)             // "x" is in "xyz"
    case isNotIn(Expression, Expression)          // "x" is not in "xyz"
    case isWithin(Expression, Expression)         // point is within rect
    case isNotWithin(Expression, Expression)      // point is not within rect
    case isA(Expression, String)                  // x is a number
    case isNotA(Expression, String)               // x is not a number
    case thereIsA(String, Expression)             // there is a button "OK"
    case thereIsNo(String, Expression)            // there is no button "OK"
}

/// Binary operators.
public enum BinaryOp: String, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case power = "^"
    case modulo = "mod"
    case intDiv = "div"
    case equal = "="
    case notEqual = "<>"
    case lessThan = "<"
    case greaterThan = ">"
    case lessOrEqual = "<="
    case greaterOrEqual = ">="
    case and, or
}

/// Unary operators.
public enum UnaryOp: String, Sendable {
    case negate = "-"
    case not
}

/// Chunk types for text addressing.
public enum ChunkType: String, Sendable {
    case word, char, character, item, line
}

/// A chunk range — either a single index or a range.
public enum ChunkRange: Sendable {
    case single(Expression)
    case range(Expression, Expression)
}

/// An object reference expression (e.g. "card 1", "button \"OK\"").
public struct ObjectRefExpr: Sendable {
    public var objectType: String   // "card", "field", "button", etc.
    public var identifier: Expression  // name or number

    public init(objectType: String, identifier: Expression) {
        self.objectType = objectType
        self.identifier = identifier
    }
}

// MARK: - Statements

/// A statement in the HypeTalk AST.
public indirect enum Statement: Sendable {
    case put(source: Expression, preposition: Preposition, target: Expression)
    case get(Expression)
    case set(property: String, of: Expression?, to: Expression)
    case go(destination: Expression)
    case ifThenElse(condition: Expression, thenBlock: [Statement], elseBlock: [Statement]?)
    case repeatCount(count: Expression, body: [Statement])
    case repeatWhile(condition: Expression, body: [Statement])
    case repeatWith(variable: String, from: Expression, to: Expression, body: [Statement])
    case exitRepeat
    case nextRepeat
    case passMessage(String)
    case exitHandler(String)
    case returnValue(Expression)
    case globalDecl([String])
    case ask(prompt: Expression)
    case answer(prompt: Expression)
    case visual(effectName: Expression)
    case send(message: String, target: Expression)
    case expressionStatement(Expression)
    case doBlock(Expression)
    case wait(Expression)
    case beep(Expression?)
    case play(Expression)
    case createCard(backgroundName: Expression?)  // "create a new card [with background "name"]"
    case createBackground(name: Expression)        // "create background "name""
    case showAllCards                              // "show all cards"
    case addTo(value: Expression, variable: Expression)          // add 5 to x
    case subtractFrom(value: Expression, variable: Expression)   // subtract 1 from x
    case multiplyBy(variable: Expression, value: Expression)     // multiply x by 2
    case divideBy(variable: Expression, value: Expression)       // divide x by 3
    case deleteObject(Expression)                                // delete button 1
    case findText(Expression)                                    // find "hello"
    case selectObject(Expression)                                // select field 1
    case sortCards(by: Expression)                               // sort cards by field "Name"
    case hideObject(Expression)                                  // hide field 1
    case showObject(Expression)                                  // show field 1
    case lockScreen                                              // lock screen
    case unlockScreen                                            // unlock screen
    case openStack(Expression)                                   // open stack "file"

    // Phase 2: HypeTalk compliance commands
    case convert(Expression, Expression)                         // convert X to Y
    case closeWindow                                             // close window
    case saveStack                                               // save this stack
    case quitApp                                                 // quit
    case editScriptOf(Expression)                                // edit script of button 1
    case chooseTool(Expression)                                  // choose browse tool
    case markCard(Expression?)                                   // mark this card
    case unmarkCard(Expression?)                                 // unmark this card
    case typeText(Expression)                                    // type "hello"

    // Stub commands (recognized but no-op)
    case push(Expression?)                                       // push card
    case pop                                                     // pop card
    case clickAt(Expression)                                     // click at 100,200
    case dragFrom(Expression, Expression)                        // drag from x to y
    case doMenuCmd(Expression)                                   // doMenu "item"
    case disableCmd(Expression)                                  // disable menu
    case enableCmd(Expression)                                   // enable menu
    case helpCmd                                                 // help
    case debugCmd                                                // debug
    case dialCmd(Expression)                                     // dial "number"
    case resetCmd(Expression?)                                   // reset
    case printCmd(Expression?)                                   // print card
    case readCmd(Expression)                                     // read from file
    case writeCmd(Expression, Expression)                        // write to file
    case replyCmd(Expression)                                    // reply
    case requestCmd(Expression)                                  // request
    case runCmd(Expression)                                      // run
    case startUsing(Expression)                                  // start using stack
    case stopUsing(Expression)                                   // stop using stack
    case copyTemplate                                            // copy template
    case exportPaint(Expression)                                 // export paint
    case importPaint(Expression)                                 // import paint
}

/// Preposition for put statements.
public enum Preposition: String, Sendable {
    case into, after, before
}

// MARK: - Handlers & Script

/// A single handler (message or function).
public struct Handler: Sendable {
    public var name: String
    public var handlerType: HandlerType
    public var params: [String]
    public var body: [Statement]
    public var line: Int

    public init(name: String, handlerType: HandlerType, params: [String], body: [Statement], line: Int) {
        self.name = name
        self.handlerType = handlerType
        self.params = params
        self.body = body
        self.line = line
    }
}

/// Whether a handler is a message handler or a function.
public enum HandlerType: String, Sendable {
    case message, function
}

/// A complete parsed script — zero or more handlers.
public struct Script: Sendable {
    public var handlers: [Handler]

    public init(handlers: [Handler]) {
        self.handlers = handlers
    }
}

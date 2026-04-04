import Foundation

// MARK: - Expressions

/// An expression in the HypeTalk AST.
public indirect enum Expression: Sendable {
    case literal(Value)
    case variable(String)
    case it
    case me
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
}

/// Binary operators.
public enum BinaryOp: String, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case power = "^"
    case modulo = "mod"
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

import Foundation

/// All token types recognized by the HypeTalk lexer.
public enum TokenType: String, Sendable {
    // Literals
    case integer, float, string, identifier

    // Keywords — handlers & control flow
    case on, end, `if`, then, `else`, `repeat`, put, get, set
    case go, ask, answer, visual, effect, pass, exit, next, `return`
    case global, function, `true`, `false`, not, and, or

    // Comparison & containment
    case `is`, contains, into, after, before

    // Articles & prepositions
    case the, of, to, with

    // Special identifiers
    case it, me, this, empty

    // Chunk types
    case word, char, character, item, line, number

    // Ordinals
    case first, second, third, last, middle, any

    // Arithmetic operators
    case plus, minus, multiply, divide, mod, power
    case ampersand, doubleAmpersand

    // Comparison operators
    case eq, neq, lt, gt, lte, gte

    // Punctuation
    case lparen, rparen, comma, newline, eof

    // Object references
    case card, background, stack, field, button, webpage

    // Commands
    case create, show

    // AI (Phase 5 placeholder)
    case ai
}

/// A single token produced by the HypeTalk lexer.
public struct Token: Sendable {
    public let type: TokenType
    public let value: String
    public let line: Int

    public init(type: TokenType, value: String, line: Int) {
        self.type = type
        self.value = value
        self.line = line
    }
}

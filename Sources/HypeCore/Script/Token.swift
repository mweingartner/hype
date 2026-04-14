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
    case it, me, this, empty, await

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
    case create, show, add, subtract, delete, find, select, sort
    case hide, lock, unlock, open, intDiv

    // Phase 2 commands
    case choose, close, save, quit, mark, unmark, push, pop
    case click, drag, run, print, help, debug, reset
    case export, `import`, copy, disable, enable, edit, dial
    case request, reply, start, stop, using, template, paint, report, file, printing
    case convert, typeText
    case method, headers, body, username, password, host, port, message, listen, http, tcp, connection, listener, status, tls, connect, send

    // Prepositions & modifiers
    case by, from, times, down

    // SpriteKit object types
    case sprite, scene, spritearea, emitter, action, tilemap, camera, transition, tile, joint, constrain

    // Audio & animation commands
    case play, beep, wait, animate

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

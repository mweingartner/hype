import Foundation

/// Hand-written tokenizer for HypeTalk source code.
/// Case-insensitive keyword matching, single-line `--` comments, `\` line continuation.
public struct Lexer: Sendable {
    private let source: [Character]
    private var pos: Int = 0
    private var currentLine: Int = 1
    private var tokens: [Token] = []

    /// Map of lowercase keyword strings to their token types.
    private static let keywords: [String: TokenType] = [
        "on": .on, "end": .end, "if": .if, "then": .then, "else": .else,
        "repeat": .repeat, "put": .put, "get": .get, "set": .set,
        "go": .go, "ask": .ask, "answer": .answer, "visual": .visual,
        "effect": .effect, "pass": .pass, "exit": .exit, "next": .next,
        "return": .return, "global": .global, "function": .function,
        "true": .true, "false": .false, "not": .not, "and": .and, "or": .or,
        "is": .is, "contains": .contains, "into": .into, "after": .after,
        "before": .before, "the": .the, "of": .of, "to": .to, "with": .with,
        "it": .it, "me": .me, "this": .this, "empty": .empty,
        "word": .word, "char": .char, "character": .character,
        "item": .item, "line": .line, "number": .number,
        "first": .first, "second": .second, "third": .third,
        "last": .last, "middle": .middle, "any": .any,
        "card": .card, "background": .background, "bg": .background,
        "stack": .stack, "field": .field, "fld": .field,
        "button": .button, "btn": .button,
        "webpage": .webpage,
        "mod": .mod, "create": .create, "ai": .ai,
    ]

    public init(source: String) {
        self.source = Array(source)
    }

    /// Tokenize the entire source and return the token list.
    public mutating func tokenize() -> [Token] {
        tokens = []
        pos = 0
        currentLine = 1

        while pos < source.count {
            let ch = source[pos]

            // Skip spaces and tabs (not newlines).
            if ch == " " || ch == "\t" {
                pos += 1
                continue
            }

            // Line continuation: backslash immediately before newline.
            if ch == "\\" && pos + 1 < source.count && source[pos + 1] == "\n" {
                pos += 2
                currentLine += 1
                continue
            }

            // Comments: -- to end of line.
            if ch == "-" && pos + 1 < source.count && source[pos + 1] == "-" {
                while pos < source.count && source[pos] != "\n" {
                    pos += 1
                }
                continue
            }

            // Newlines.
            if ch == "\n" || ch == "\r" {
                // Collapse consecutive newlines into one token.
                if let last = tokens.last, last.type != .newline {
                    tokens.append(Token(type: .newline, value: "\\n", line: currentLine))
                }
                if ch == "\r" && pos + 1 < source.count && source[pos + 1] == "\n" {
                    pos += 1
                }
                currentLine += 1
                pos += 1
                continue
            }

            // String literals (handle smart/curly quotes too).
            if ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}" {
                scanString()
                continue
            }

            // Numbers.
            if ch.isNumber || (ch == "." && pos + 1 < source.count && source[pos + 1].isNumber) {
                scanNumber()
                continue
            }

            // Identifiers and keywords.
            if ch.isLetter || ch == "_" {
                scanIdentifier()
                continue
            }

            // Two-character operators.
            if pos + 1 < source.count {
                let next = source[pos + 1]
                let pair = String([ch, next])
                if let tokType = twoCharOp(pair) {
                    tokens.append(Token(type: tokType, value: pair, line: currentLine))
                    pos += 2
                    continue
                }
            }

            // Single-character operators.
            if let tokType = singleCharOp(ch) {
                tokens.append(Token(type: tokType, value: String(ch), line: currentLine))
                pos += 1
                continue
            }

            // Unknown character — skip.
            pos += 1
        }

        // Ensure trailing newline before EOF.
        if let last = tokens.last, last.type != .newline {
            tokens.append(Token(type: .newline, value: "\\n", line: currentLine))
        }
        tokens.append(Token(type: .eof, value: "", line: currentLine))
        return tokens
    }

    // MARK: - Scanning helpers

    /// Check if a character is any kind of double quote (straight or curly).
    private func isQuote(_ ch: Character) -> Bool {
        ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}"
    }

    private mutating func scanString() {
        pos += 1 // skip opening quote (straight or curly)
        var result: [Character] = []
        while pos < source.count && !isQuote(source[pos]) {
            if source[pos] == "\n" {
                break // unterminated string at newline
            }
            result.append(source[pos])
            pos += 1
        }
        if pos < source.count && isQuote(source[pos]) {
            pos += 1 // skip closing quote (straight or curly)
        }
        tokens.append(Token(type: .string, value: String(result), line: currentLine))
    }

    private mutating func scanNumber() {
        let start = pos
        var isFloat = false
        while pos < source.count && (source[pos].isNumber || source[pos] == ".") {
            if source[pos] == "." {
                if isFloat { break } // second dot — stop
                isFloat = true
            }
            pos += 1
        }
        let value = String(source[start..<pos])
        tokens.append(Token(type: isFloat ? .float : .integer, value: value, line: currentLine))
    }

    private mutating func scanIdentifier() {
        let start = pos
        while pos < source.count && (source[pos].isLetter || source[pos].isNumber || source[pos] == "_") {
            pos += 1
        }
        let word = String(source[start..<pos])
        let lower = word.lowercased()

        if let keyword = Self.keywords[lower] {
            tokens.append(Token(type: keyword, value: word, line: currentLine))
        } else {
            tokens.append(Token(type: .identifier, value: word, line: currentLine))
        }
    }

    private func twoCharOp(_ pair: String) -> TokenType? {
        switch pair {
        case "&&": return .doubleAmpersand
        case "<>": return .neq
        case "<=": return .lte
        case ">=": return .gte
        default: return nil
        }
    }

    private func singleCharOp(_ ch: Character) -> TokenType? {
        switch ch {
        case "+": return .plus
        case "-": return .minus
        case "*": return .multiply
        case "/": return .divide
        case "^": return .power
        case "&": return .ampersand
        case "=": return .eq
        case "<": return .lt
        case ">": return .gt
        case "(": return .lparen
        case ")": return .rparen
        case ",": return .comma
        case "\u{2260}": return .neq // ≠
        default: return nil
        }
    }
}

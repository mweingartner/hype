import Foundation

/// Color categories for syntax highlighting.
public enum TokenCategory: Sendable {
    case keyword          // on, end, if, then, else, repeat, return, pass, exit, next, function, global
    case command          // put, get, set, go, create, show, hide, delete, ask, answer, etc.
    case objectType       // card, background, field, button, sprite, scene, spritearea, stack, webpage, emitter
    case constant         // true, false, empty, it, me, this
    case stringLiteral    // "quoted strings"
    case numberLiteral    // 42, 3.14
    case comment          // -- line comments
    case operator_        // and, or, not, is, contains, mod, div, plus operators
    case plain            // identifiers, whitespace, everything else
}

/// A highlighted range in source code.
public struct HighlightToken: Sendable {
    public let range: Range<String.Index>
    public let category: TokenCategory

    public init(range: Range<String.Index>, category: TokenCategory) {
        self.range = range
        self.category = category
    }
}

/// Tokenizes HypeTalk source and maps tokens to color categories.
///
/// This performs its own character-level scan (rather than using ``Lexer``)
/// because we need accurate ``Range<String.Index>`` values that the Lexer
/// does not track.
public struct HypeTalkHighlighter: Sendable {

    // MARK: - Keyword classification tables

    private static let keywords: Set<String> = [
        "on", "end", "if", "then", "else", "repeat", "return", "pass",
        "exit", "next", "function", "global", "with", "to", "from",
        "by", "times", "down",
    ]

    private static let commands: Set<String> = [
        "put", "get", "set", "go", "create", "show", "hide", "delete",
        "ask", "answer", "add", "subtract", "multiply", "divide", "sort",
        "find", "select", "lock", "unlock", "open", "close", "save",
        "run", "mark", "unmark", "play", "beep", "wait", "visual", "effect",
        "send", "do", "push", "pop", "click", "drag", "print", "help",
        "debug", "reset", "export", "import", "copy", "disable", "enable",
        "edit", "choose", "quit", "dial", "request", "reply", "start",
        "stop", "using", "template", "report", "convert", "animate",
    ]

    private static let objectTypes: Set<String> = [
        // Original HyperCard-style object kinds.
        "card", "background", "bg", "field", "fld", "button", "btn",
        "sprite", "scene", "spritearea", "stack", "webpage", "image", "video", "emitter",
        "action", "ai", "paint", "file", "printing",
        // Phase 1 framework controls (Calendar / PDF / Map / ColorWell)
        // and the chart part — referenced in HypeTalk as
        // `the X of map "store"`, `the centerLat of map "X"`, etc.
        "chart", "calendar", "pdf", "map", "colorwell",
        // Phase 2 form controls.
        "stepper", "slider", "segmented",
        // Phase 2 media + 3D.
        "audiorecorder", "recorder", "scene3d", "model3d",
        // Phase 3 UI controls.
        "progressview", "progress", "gauge", "divider",
        // Removed in dedup: toggle, link, menu, searchfield, search.
        // These are now button styles (.toggle, .link, .popup) and
        // a field style (.search) — referenced via `button "X"` /
        // `field "X"` in HypeTalk.
    ]

    private static let constants: Set<String> = [
        "true", "false", "empty", "it", "me", "this",
    ]

    private static let operators: Set<String> = [
        "and", "or", "not", "is", "contains", "into", "after", "before",
        "the", "of", "mod", "div", "number", "word", "char", "character",
        "item", "line", "first", "second", "third", "last", "middle", "any",
    ]

    public init() {}

    /// Highlight the given HypeTalk source, returning an array of tokens with
    /// their character ranges and color categories.
    public func highlight(_ source: String) -> [HighlightToken] {
        guard !source.isEmpty else { return [] }

        var tokens: [HighlightToken] = []
        var index = source.startIndex

        while index < source.endIndex {
            let ch = source[index]

            // -- Comments: `--` to end of line
            if ch == "-" {
                let next = source.index(after: index)
                if next < source.endIndex && source[next] == "-" {
                    let start = index
                    var end = next
                    // Advance to end of line
                    while end < source.endIndex {
                        let afterEnd = source.index(after: end)
                        if afterEnd >= source.endIndex { break }
                        if source[afterEnd] == "\n" { break }
                        end = afterEnd
                    }
                    // end is now the last char before newline (or endIndex - 1)
                    let tokenEnd = source.index(after: end)
                    tokens.append(HighlightToken(range: start..<tokenEnd, category: .comment))
                    index = tokenEnd
                    continue
                }
            }

            // -- String literals: straight or curly quotes
            if ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}" {
                let start = index
                index = source.index(after: index) // skip opening quote
                while index < source.endIndex {
                    let sc = source[index]
                    if sc == "\"" || sc == "\u{201C}" || sc == "\u{201D}" {
                        index = source.index(after: index) // skip closing quote
                        break
                    }
                    if sc == "\n" { break } // unterminated
                    index = source.index(after: index)
                }
                tokens.append(HighlightToken(range: start..<index, category: .stringLiteral))
                continue
            }

            // -- Numbers
            if ch.isNumber || (ch == "." && peek(after: index, in: source)?.isNumber == true) {
                let start = index
                var hasDecimal = false
                while index < source.endIndex && (source[index].isNumber || source[index] == ".") {
                    if source[index] == "." {
                        if hasDecimal { break }
                        hasDecimal = true
                    }
                    index = source.index(after: index)
                }
                tokens.append(HighlightToken(range: start..<index, category: .numberLiteral))
                continue
            }

            // -- Identifiers and keywords
            if ch.isLetter || ch == "_" {
                let start = index
                while index < source.endIndex && (source[index].isLetter || source[index].isNumber || source[index] == "_") {
                    index = source.index(after: index)
                }
                let word = String(source[start..<index])
                let lower = word.lowercased()
                let category = classify(lower)
                tokens.append(HighlightToken(range: start..<index, category: category))
                continue
            }

            // Everything else (whitespace, operators, punctuation) → skip (plain)
            index = source.index(after: index)
        }

        return tokens
    }

    // MARK: - Helpers

    private func peek(after index: String.Index, in source: String) -> Character? {
        let next = source.index(after: index)
        guard next < source.endIndex else { return nil }
        return source[next]
    }

    private func classify(_ lowercasedWord: String) -> TokenCategory {
        if Self.keywords.contains(lowercasedWord) { return .keyword }
        if Self.commands.contains(lowercasedWord) { return .command }
        if Self.objectTypes.contains(lowercasedWord) { return .objectType }
        if Self.constants.contains(lowercasedWord) { return .constant }
        if Self.operators.contains(lowercasedWord) { return .operator_ }
        return .plain
    }
}

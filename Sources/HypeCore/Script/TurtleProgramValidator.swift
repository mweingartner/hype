import Foundation

/// Validates a `draw_with_turtle` AI-tool program before any document
/// mutation (design.md D7, turtle-graphics — the AI sandbox boundary).
///
/// `validate(program:)` never mutates a document and never invokes a
/// user-defined function. It caps the program size, lexes and parses it
/// with the REAL HypeTalk `Lexer`/`Parser` (so an accepted program is
/// byte-for-byte the same grammar as the HypeTalk surface — Condition 1:
/// no second geometry/grammar implementation), then walks the parsed AST
/// against a narrow structural allowlist: turtle commands, turtle
/// property sets, `reset turtle`, and `repeat N times` / `repeat with i
/// = a to b` loops with arithmetic-only expressions. Anything else
/// refuses with an E9 message naming the first offending line.
///
/// **Security C4 — the load-bearing sandbox boundary.** The
/// allowed-expression validator runs on EVERY expression position in
/// every allowed statement — external-command arguments, the `set`
/// value expression, and both the `repeatCount` count and the
/// `repeatWith` from/to bounds — not only "arguments" and "bodies". A
/// `functionCall` (or any other non-arithmetic, non-turtle-property
/// expression) in ANY of those positions refuses, so a validated
/// program can never invoke a user-authored HypeTalk function.
public enum TurtleProgramValidator {
    /// `menuItems`-cap precedent (design-mock §7.3).
    public static let maxProgramBytes = 64 * 1024

    /// Pre-parse token-nesting cap (Security A2). The recursive-descent
    /// `Parser` SIGBUSes on deeply nested constructs around 800 levels
    /// even on an 8 MB thread stack (measured empirically against
    /// parenthesized expressions — see `InterpreterFuzzTests`'s
    /// `TurtleSecurityRobustnessTests`, probed to 700-safe/800-traps).
    /// 200 is a wide safety margin under that threshold. This guard
    /// runs BEFORE any recursive parse (over the raw token stream, with
    /// a flat loop — never recursive itself), so a pathological program
    /// is refused cleanly instead of letting the parser crash the
    /// process. It counts both parenthesized-expression nesting
    /// (`(`/`)`) and `if`/`repeat` block nesting — every construct in
    /// the grammar that makes the parser recurse into a nested body —
    /// since either one can drive the same unbounded parser recursion
    /// regardless of whether the resulting statement would later be
    /// accepted or refused by the allowlist walk below.
    static let maxNestingDepth = 200

    /// The outcome of validating a `draw_with_turtle` program.
    public enum Verdict: Sendable {
        /// The program is entirely turtle vocabulary; the parsed
        /// statements are ready to execute.
        case ok([Statement])
        /// The program was refused before any execution — the E9 text
        /// or the size/nesting-cap text. Zero mutation ever happened.
        case refused(String)
    }

    /// Validates `program`. Never throws and never touches a document —
    /// the caller (the `draw_with_turtle` executor) only proceeds to
    /// execute when this returns `.ok`.
    public static func validate(program: String) -> Verdict {
        guard program.utf8.count <= maxProgramBytes else {
            return .refused(TurtleEngine.ErrorCopy.programTooLarge)
        }

        var lexer = Lexer(source: program)
        let tokens = lexer.tokenize()

        if let depthRefusal = nestingDepthRefusal(tokens: tokens) {
            return .refused(depthRefusal)
        }

        var parser = Parser(tokens: tokens)
        let statements: [Statement]
        do {
            statements = try parser.parseStatements()
        } catch let parseError as ParseError {
            switch parseError {
            case .unexpected(let token, _):
                return .refused(notATurtleCommand(line: token.line, program: program))
            }
        } catch {
            // `Parser` only ever throws `ParseError`; this branch is
            // unreachable defensive coverage so `validate` never
            // propagates an unrecognized error type.
            return .refused(notATurtleCommand(line: 1, program: program))
        }

        var cursor = LineCursor(lines: segmentLines(tokens: tokens))
        if let refusal = refusal(forStatements: statements, cursor: &cursor, program: program) {
            return .refused(refusal)
        }
        return .ok(statements)
    }

    // MARK: - Security A2: pre-parse nesting-depth guard

    /// Scans the token stream once, front to back, with a flat integer
    /// counter — never recurses, so this function itself can never be
    /// the thing that overflows the stack. `.lparen`/`.rparen` track
    /// expression nesting; `.if`/`.repeat` track block nesting, using
    /// the same "preceded by `.end`" test the parser itself uses to
    /// tell an opening `if`/`repeat` from the `if`/`repeat` half of an
    /// `end if`/`end repeat` pair.
    private static func nestingDepthRefusal(tokens: [Token]) -> String? {
        var depth = 0
        for (index, token) in tokens.enumerated() {
            switch token.type {
            case .lparen:
                depth += 1
            case .rparen:
                depth = max(0, depth - 1)
            case .repeat, .if:
                if index > 0, tokens[index - 1].type == .end {
                    depth = max(0, depth - 1)
                } else {
                    depth += 1
                }
            default:
                break
            }
            if depth > maxNestingDepth {
                return TurtleEngine.ErrorCopy.nestingTooDeep(line: token.line)
            }
        }
        return nil
    }

    // MARK: - Token-segment line cursor

    /// One entry per source line that carries real tokens, in order.
    /// Comment-only and blank lines never appear here — the lexer
    /// collapses them away before this runs, and consecutive newline
    /// tokens are already collapsed to one. Every allowed statement is
    /// single-line-headed (a simple statement is one segment; a
    /// `repeat` header is one segment; its `end repeat` is one more),
    /// so walking this list in lockstep with the parsed `[Statement]`
    /// tree recovers the exact source line for the first offending
    /// statement even though the AST itself carries no line numbers.
    private static func segmentLines(tokens: [Token]) -> [Int] {
        var lines: [Int] = []
        var atSegmentStart = true
        for token in tokens {
            switch token.type {
            case .newline:
                atSegmentStart = true
            case .eof:
                break
            default:
                if atSegmentStart {
                    lines.append(token.line)
                    atSegmentStart = false
                }
            }
        }
        return lines
    }

    private struct LineCursor {
        let lines: [Int]
        var index = 0

        mutating func next() -> Int {
            guard index < lines.count else { return lines.last ?? 1 }
            defer { index += 1 }
            return lines[index]
        }
    }

    // MARK: - Allowlist walk

    private static func refusal(forStatements statements: [Statement], cursor: inout LineCursor, program: String) -> String? {
        for statement in statements {
            let line = cursor.next()
            if let refusal = refusal(forStatement: statement, line: line, cursor: &cursor, program: program) {
                return refusal
            }
        }
        return nil
    }


    private static func refusal(forStatement statement: Statement, line: Int, cursor: inout LineCursor, program: String) -> String? {
        switch statement {
        case .externalCommand(let name, let arguments):
            guard TurtleVocabulary.isTurtleVerb(name.lowercased()), arguments.allSatisfy(isAllowedExpression) else {
                return notATurtleCommand(line: line, program: program)
            }
            return nil

        case .set(_, let of, let to):
            // Strictly the canonical `of the turtle` form (R12) — the
            // same shape the interpreter's own `.set`/`evaluateProperty`
            // branches match.
            guard isTurtleTarget(of), isAllowedExpression(to) else {
                return notATurtleCommand(line: line, program: program)
            }
            return nil

        case .resetCmd(let expr):
            guard let expr, isTurtleWord(expr) else {
                return notATurtleCommand(line: line, program: program)
            }
            return nil

        case .repeatCount(let count, let body):
            guard isAllowedExpression(count) else {
                return notATurtleCommand(line: line, program: program)
            }
            if let bodyRefusal = refusal(forStatements: body, cursor: &cursor, program: program) {
                return bodyRefusal
            }
            _ = cursor.next()  // "end repeat"
            return nil

        case .repeatWith(_, let from, let to, _, let body):
            guard isAllowedExpression(from), isAllowedExpression(to) else {
                return notATurtleCommand(line: line, program: program)
            }
            if let bodyRefusal = refusal(forStatements: body, cursor: &cursor, program: program) {
                return bodyRefusal
            }
            _ = cursor.next()  // "end repeat"
            return nil

        default:
            // Everything else — `go`, `if`, `repeatForever`,
            // `repeatWhile`, `repeatForEach`, part/property mutation
            // outside `the turtle`, file/network/host commands, and so
            // on — is not turtle vocabulary.
            return notATurtleCommand(line: line, program: program)
        }
    }

    // MARK: - Allowed-expression validator (Security C4)
    //
    // Applied to EVERY expression position reached above: external-
    // command arguments, the `set` value expression, and both the
    // `repeatCount` count and the `repeatWith` from/to bounds.

    private static let allowedArithmeticOps: Set<BinaryOp> = [.add, .subtract, .multiply, .divide, .modulo, .intDiv, .power]

    private static func isAllowedExpression(_ expression: Expression) -> Bool {
        switch expression {
        case .literal:
            return true
        case .variable:
            return true
        case .unary(.negate, let inner):
            return isAllowedExpression(inner)
        case .binary(let lhs, let op, let rhs):
            return allowedArithmeticOps.contains(op) && isAllowedExpression(lhs) && isAllowedExpression(rhs)
        case .propertyAccess(_, let target):
            return isTurtleTarget(target)
        default:
            // `functionCall` (and everything else — chunks, contains,
            // string concat, `ask meshy`, object refs, …) refuses here.
            // This is the load-bearing line: a `functionCall` in any
            // expression position never matches any case above it.
            return false
        }
    }

    /// `the <anything> of the turtle` — matches the exact shape the real
    /// parser produces for `the turtle` as a property target
    /// (`.propertyAccess("turtle", nil)`; no `turtle` case exists in the
    /// interpreter's global-property switch, so this can never collide
    /// with a built-in global property name).
    private static func isTurtleTarget(_ expression: Expression?) -> Bool {
        guard let expression, case .propertyAccess(let name, nil) = expression else { return false }
        return name.lowercased() == "turtle"
    }

    /// `reset turtle` (bare word — the parser's fallback idiom resolves
    /// it to the variable name at evaluation time) or `reset "turtle"`
    /// (string literal) — the only `resetCmd` forms the allowlist
    /// accepts.
    private static func isTurtleWord(_ expression: Expression) -> Bool {
        switch expression {
        case .variable(let name):
            return name.lowercased() == "turtle"
        case .literal(let value):
            return value.lowercased() == "turtle"
        default:
            return false
        }
    }

    // MARK: - E9 composition

    private static func notATurtleCommand(line: Int, program: String) -> String {
        TurtleEngine.ErrorCopy.notATurtleCommand(line: line, text: sourceLine(program, line))
    }

    /// The trimmed source text of 1-indexed `line`, or `""` when out of
    /// range. `TurtleEngine.ErrorCopy.notATurtleCommand` clips this to
    /// 200 characters, so a pathologically long single line is still
    /// safe to embed in the refusal message.
    private static func sourceLine(_ program: String, _ line: Int) -> String {
        let lines = program.components(separatedBy: "\n")
        guard line >= 1, line <= lines.count else { return "" }
        return lines[line - 1].trimmingCharacters(in: .whitespaces)
    }
}

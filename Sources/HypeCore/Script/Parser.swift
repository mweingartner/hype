import Foundation

/// Recursive descent parser for HypeTalk scripts.
public struct Parser: Sendable {
    private let tokens: [Token]
    private var pos: Int = 0

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    // MARK: - Token helpers

    private var current: Token {
        pos < tokens.count ? tokens[pos] : Token(type: .eof, value: "", line: 0)
    }

    private mutating func advance() -> Token {
        let tok = current
        if pos < tokens.count { pos += 1 }
        return tok
    }

    private mutating func expect(_ type: TokenType) throws -> Token {
        if current.type == type {
            return advance()
        }
        throw ParseError.unexpected(current, expected: type.rawValue)
    }

    private mutating func match(_ type: TokenType) -> Bool {
        if current.type == type {
            pos += 1
            return true
        }
        return false
    }

    private mutating func skipNewlines() {
        while current.type == .newline { pos += 1 }
    }

    // MARK: - Top-level

    /// Parse the full script into handler declarations.
    public mutating func parse() throws -> Script {
        var handlers: [Handler] = []
        skipNewlines()
        while current.type != .eof {
            let handler = try parseHandler()
            handlers.append(handler)
            skipNewlines()
        }
        return Script(handlers: handlers)
    }

    // MARK: - Handler

    private mutating func parseHandler() throws -> Handler {
        let startLine = current.line
        let handlerType: HandlerType
        if current.type == .on {
            handlerType = .message
        } else if current.type == .function {
            handlerType = .function
        } else {
            throw ParseError.unexpected(current, expected: "on or function")
        }
        _ = advance()

        let nameTok = advance()
        let name = nameTok.value

        // Optional parameter list.
        var params: [String] = []
        while current.type == .identifier || current.type == .comma {
            if current.type == .comma { _ = advance(); continue }
            params.append(advance().value)
        }
        skipNewlines()

        // Body statements until `end <name>`.
        var body: [Statement] = []
        while !isEndOfHandler(name) && current.type != .eof {
            let stmt = try parseStatement()
            body.append(stmt)
            skipNewlines()
        }

        // Consume `end <name>`.
        _ = try expect(.end)
        if current.type == .identifier || current.value.lowercased() == name.lowercased() {
            _ = advance()
        }
        skipNewlines()

        return Handler(name: name, handlerType: handlerType, params: params, body: body, line: startLine)
    }

    private func isEndOfHandler(_ name: String) -> Bool {
        current.type == .end
    }

    // MARK: - Statement dispatch

    private mutating func parseStatement() throws -> Statement {
        skipNewlines()
        switch current.type {
        case .put:      return try parsePutStatement()
        case .get:      return try parseGetStatement()
        case .set:      return try parseSetStatement()
        case .go:       return try parseGoStatement()
        case .if:       return try parseIfStatement()
        case .repeat:   return try parseRepeatStatement()
        case .exit:     return try parseExitStatement()
        case .next:     return try parseNextStatement()
        case .pass:     return try parsePassStatement()
        case .return:   return try parseReturnStatement()
        case .global:   return try parseGlobalStatement()
        case .ask:      return try parseAskStatement()
        case .answer:   return try parseAnswerStatement()
        case .visual:   return try parseVisualStatement()
        default:
            // Bare expression (function call, etc.)
            let expr = try parseExpression()
            skipNewlines()
            return .expressionStatement(expr)
        }
    }

    // MARK: - Individual statement parsers

    private mutating func parsePutStatement() throws -> Statement {
        _ = try expect(.put)
        let source = try parseExpression()

        var preposition: Preposition = .into
        if current.type == .into { preposition = .into; _ = advance() }
        else if current.type == .after { preposition = .after; _ = advance() }
        else if current.type == .before { preposition = .before; _ = advance() }

        let target = try parseExpression()
        skipNewlines()
        return .put(source: source, preposition: preposition, target: target)
    }

    private mutating func parseGetStatement() throws -> Statement {
        _ = try expect(.get)
        let expr = try parseExpression()
        skipNewlines()
        return .get(expr)
    }

    private mutating func parseSetStatement() throws -> Statement {
        _ = try expect(.set)
        // `set the <property> of <target> to <value>`
        _ = match(.the)
        let propTok = advance()
        let property = propTok.value

        var target: Expression? = nil
        if current.type == .of {
            _ = advance()
            target = try parseExpression()
        }

        _ = try expect(.to)
        let value = try parseExpression()
        skipNewlines()
        return .set(property: property, of: target, to: value)
    }

    private mutating func parseGoStatement() throws -> Statement {
        _ = try expect(.go)
        _ = match(.to) // optional "to"
        let dest = try parseExpression()
        skipNewlines()
        return .go(destination: dest)
    }

    private mutating func parseIfStatement() throws -> Statement {
        _ = try expect(.if)
        let condition = try parseExpression()
        _ = try expect(.then)

        // Single-line if: `if cond then stmt [else stmt]`
        if current.type != .newline && current.type != .eof {
            let thenStmt = try parseStatement()
            var elseBlock: [Statement]? = nil
            if current.type == .else {
                _ = advance()
                let elseStmt = try parseStatement()
                elseBlock = [elseStmt]
            }
            return .ifThenElse(condition: condition, thenBlock: [thenStmt], elseBlock: elseBlock)
        }

        // Multi-line if block.
        skipNewlines()
        var thenBlock: [Statement] = []
        while current.type != .else && current.type != .end && current.type != .eof {
            let stmt = try parseStatement()
            thenBlock.append(stmt)
            skipNewlines()
        }

        var elseBlock: [Statement]? = nil
        if current.type == .else {
            _ = advance()
            skipNewlines()
            var elseStmts: [Statement] = []
            while current.type != .end && current.type != .eof {
                let stmt = try parseStatement()
                elseStmts.append(stmt)
                skipNewlines()
            }
            elseBlock = elseStmts
        }

        _ = try expect(.end)
        _ = match(.if) // `end if`
        skipNewlines()
        return .ifThenElse(condition: condition, thenBlock: thenBlock, elseBlock: elseBlock)
    }

    private mutating func parseRepeatStatement() throws -> Statement {
        _ = try expect(.repeat)

        // `repeat with i = from to to`
        if current.type == .with {
            _ = advance()
            let varName = advance().value
            _ = try expect(.eq)
            let fromExpr = try parseExpression()
            _ = try expect(.to)
            let toExpr = try parseExpression()
            skipNewlines()
            let body = try parseRepeatBody()
            return .repeatWith(variable: varName, from: fromExpr, to: toExpr, body: body)
        }

        // `repeat while <cond>`
        if current.value.lowercased() == "while" {
            _ = advance()
            let cond = try parseExpression()
            skipNewlines()
            let body = try parseRepeatBody()
            return .repeatWhile(condition: cond, body: body)
        }

        // `repeat <count>` or `repeat for <count>`
        if current.value.lowercased() == "for" {
            _ = advance()
        }
        let count = try parseExpression()
        skipNewlines()
        let body = try parseRepeatBody()
        return .repeatCount(count: count, body: body)
    }

    private mutating func parseRepeatBody() throws -> [Statement] {
        var body: [Statement] = []
        while current.type != .end && current.type != .eof {
            let stmt = try parseStatement()
            body.append(stmt)
            skipNewlines()
        }
        _ = try expect(.end)
        _ = match(.repeat) // `end repeat`
        skipNewlines()
        return body
    }

    private mutating func parseExitStatement() throws -> Statement {
        _ = try expect(.exit)
        if current.type == .repeat {
            _ = advance()
            skipNewlines()
            return .exitRepeat
        }
        let name = advance().value
        skipNewlines()
        return .exitHandler(name)
    }

    private mutating func parseNextStatement() throws -> Statement {
        _ = try expect(.next)
        _ = try expect(.repeat)
        skipNewlines()
        return .nextRepeat
    }

    private mutating func parsePassStatement() throws -> Statement {
        _ = try expect(.pass)
        let name = advance().value
        skipNewlines()
        return .passMessage(name)
    }

    private mutating func parseReturnStatement() throws -> Statement {
        _ = try expect(.return)
        let expr = try parseExpression()
        skipNewlines()
        return .returnValue(expr)
    }

    private mutating func parseGlobalStatement() throws -> Statement {
        _ = try expect(.global)
        var names: [String] = []
        while current.type == .identifier || current.type == .comma {
            if current.type == .comma { _ = advance(); continue }
            names.append(advance().value)
        }
        skipNewlines()
        return .globalDecl(names)
    }

    private mutating func parseAskStatement() throws -> Statement {
        _ = try expect(.ask)
        let expr = try parseExpression()
        skipNewlines()
        return .ask(prompt: expr)
    }

    private mutating func parseAnswerStatement() throws -> Statement {
        _ = try expect(.answer)
        let expr = try parseExpression()
        skipNewlines()
        return .answer(prompt: expr)
    }

    private mutating func parseVisualStatement() throws -> Statement {
        _ = try expect(.visual)
        _ = match(.effect)
        let expr = try parseExpression()
        skipNewlines()
        return .visual(effectName: expr)
    }

    // MARK: - Expression parsing (precedence climbing)

    /// Parse a full expression.
    public mutating func parseExpression() throws -> Expression {
        return try parseOr()
    }

    private mutating func parseOr() throws -> Expression {
        var left = try parseAnd()
        while current.type == .or {
            _ = advance()
            let right = try parseAnd()
            left = .binary(left, .or, right)
        }
        return left
    }

    private mutating func parseAnd() throws -> Expression {
        var left = try parseNot()
        while current.type == .and {
            _ = advance()
            let right = try parseNot()
            left = .binary(left, .and, right)
        }
        return left
    }

    private mutating func parseNot() throws -> Expression {
        if current.type == .not {
            _ = advance()
            let expr = try parseNot()
            return .not(expr)
        }
        return try parseComparison()
    }

    private mutating func parseComparison() throws -> Expression {
        var left = try parseConcatenation()

        // `contains`
        if current.type == .contains {
            _ = advance()
            let right = try parseConcatenation()
            return .contains(left, right)
        }

        // `is`
        if current.type == .is {
            _ = advance()
            // `is not` -> notEqual
            if current.type == .not {
                _ = advance()
                let right = try parseConcatenation()
                return .binary(left, .notEqual, right)
            }
            let right = try parseConcatenation()
            return .binary(left, .equal, right)
        }

        while current.type == .eq || current.type == .neq ||
              current.type == .lt || current.type == .gt ||
              current.type == .lte || current.type == .gte {
            let op = advance()
            let binOp: BinaryOp
            switch op.type {
            case .eq:  binOp = .equal
            case .neq: binOp = .notEqual
            case .lt:  binOp = .lessThan
            case .gt:  binOp = .greaterThan
            case .lte: binOp = .lessOrEqual
            case .gte: binOp = .greaterOrEqual
            default: binOp = .equal
            }
            let right = try parseConcatenation()
            left = .binary(left, binOp, right)
        }
        return left
    }

    private mutating func parseConcatenation() throws -> Expression {
        var left = try parseAddition()
        while current.type == .ampersand || current.type == .doubleAmpersand {
            let op = advance()
            let right = try parseAddition()
            if op.type == .doubleAmpersand {
                left = .spacedConcat(left, right)
            } else {
                left = .stringConcat(left, right)
            }
        }
        return left
    }

    private mutating func parseAddition() throws -> Expression {
        var left = try parseMultiplication()
        while current.type == .plus || current.type == .minus {
            let op = advance()
            let binOp: BinaryOp = op.type == .plus ? .add : .subtract
            let right = try parseMultiplication()
            left = .binary(left, binOp, right)
        }
        return left
    }

    private mutating func parseMultiplication() throws -> Expression {
        var left = try parsePower()
        while current.type == .multiply || current.type == .divide || current.type == .mod {
            let op = advance()
            let binOp: BinaryOp
            switch op.type {
            case .multiply: binOp = .multiply
            case .divide:   binOp = .divide
            case .mod:      binOp = .modulo
            default:        binOp = .multiply
            }
            let right = try parsePower()
            left = .binary(left, binOp, right)
        }
        return left
    }

    private mutating func parsePower() throws -> Expression {
        var left = try parseUnary()
        while current.type == .power {
            _ = advance()
            let right = try parseUnary()
            left = .binary(left, .power, right)
        }
        return left
    }

    private mutating func parseUnary() throws -> Expression {
        if current.type == .minus {
            _ = advance()
            let expr = try parseUnary()
            return .unary(.negate, expr)
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> Expression {
        switch current.type {
        case .integer, .float:
            let tok = advance()
            return .literal(tok.value)

        case .string:
            let tok = advance()
            return .literal(tok.value)

        case .true:
            _ = advance()
            return .literal("true")

        case .false:
            _ = advance()
            return .literal("false")

        case .it:
            _ = advance()
            return .it

        case .me:
            _ = advance()
            return .me

        case .empty:
            _ = advance()
            return .empty

        case .the:
            return try parseTheExpression()

        case .card, .background, .field, .button, .stack:
            return try parseObjectReference()

        case .lparen:
            _ = advance()
            let expr = try parseExpression()
            _ = try expect(.rparen)
            return expr

        case .identifier:
            let tok = advance()
            // Check for function call: name(args)
            if current.type == .lparen {
                _ = advance()
                var args: [Expression] = []
                if current.type != .rparen {
                    args.append(try parseExpression())
                    while current.type == .comma {
                        _ = advance()
                        args.append(try parseExpression())
                    }
                }
                _ = try expect(.rparen)
                return .functionCall(tok.value, args)
            }
            return .variable(tok.value)

        case .first, .second, .third, .last, .middle, .any:
            return try parseOrdinalChunk()

        case .next:
            // "next" used as a value (e.g., "go next")
            let tok = advance()
            return .literal(tok.value)

        case .number:
            // `number of ...`
            _ = advance()
            if current.type == .of {
                _ = advance()
                let expr = try parseExpression()
                return .propertyAccess("number", expr)
            }
            return .variable("number")

        default:
            throw ParseError.unexpected(current, expected: "expression")
        }
    }

    private mutating func parseTheExpression() throws -> Expression {
        _ = try expect(.the)
        let propTok = advance()
        let property = propTok.value

        // `the <property> of <expr>`
        if current.type == .of {
            _ = advance()
            let target = try parseExpression()
            return .propertyAccess(property, target)
        }

        // `the <property>` (global property like `the date`, `the time`)
        return .propertyAccess(property, nil)
    }

    private mutating func parseObjectReference() throws -> Expression {
        let typeTok = advance()
        let objType = typeTok.value.lowercased()
        let ident = try parsePrimary()
        return .objectRef(ObjectRefExpr(objectType: objType, identifier: ident))
    }

    private mutating func parseOrdinalChunk() throws -> Expression {
        let ordTok = advance()
        let ordinal = ordinalToExpression(ordTok.type)

        // Expect chunk type: word, char, character, item, line
        guard let chunkType = chunkTypeFromToken(current.type) else {
            // Could be ordinal used as plain expression
            return ordinal
        }
        _ = advance()

        _ = try expect(.of)
        let source = try parseExpression()
        return .chunk(chunkType, .single(ordinal), source)
    }

    private func ordinalToExpression(_ type: TokenType) -> Expression {
        switch type {
        case .first:  return .literal("1")
        case .second: return .literal("2")
        case .third:  return .literal("3")
        case .last:   return .literal("-1")  // sentinel for last
        case .middle: return .literal("0")   // sentinel for middle
        case .any:    return .literal("-2")   // sentinel for any
        default:      return .literal("1")
        }
    }

    private func chunkTypeFromToken(_ type: TokenType) -> ChunkType? {
        switch type {
        case .word:                return .word
        case .char, .character:    return .char
        case .item:                return .item
        case .line:                return .line
        default:                   return nil
        }
    }
}

// MARK: - Parse error

/// Errors that can occur during parsing.
public enum ParseError: Error, LocalizedError, Sendable {
    case unexpected(Token, expected: String)

    public var errorDescription: String? {
        switch self {
        case .unexpected(let tok, let expected):
            return "Line \(tok.line): expected \(expected), got '\(tok.value)' (\(tok.type.rawValue))"
        }
    }
}

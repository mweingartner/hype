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
        case .create:   return try parseCreateStatement()
        case .show:     return try parseShowStatement()
        case .add:      return try parseAddStatement()
        case .subtract: return try parseSubtractStatement()
        case .multiply: return try parseMultiplyCmd()
        case .divide:   return try parseDivideCmd()
        case .delete:   return try parseDeleteStatement()
        case .find:     return try parseFindStatement()
        case .select:   return try parseSelectStatement()
        case .sort:     return try parseSortStatement()
        case .hide:     return try parseHideStatement()
        case .lock:     return try parseLockStatement()
        case .unlock:   return try parseUnlockStatement()
        case .open:     return try parseOpenStatement()
        case .choose:   return try parseChooseStatement()
        case .close:    return try parseCloseStatement()
        case .save:     return try parseSaveStatement()
        case .quit:     _ = advance(); skipNewlines(); return .quitApp
        case .mark:     return try parseMarkStatement()
        case .unmark:   return try parseUnmarkStatement()
        case .edit:     return try parseEditStatement()
        case .typeText: return try parseTypeStatement()
        case .push:     return try parsePushStatement()
        case .pop:      _ = advance(); skipNewlines(); return .pop
        case .click:    return try parseClickStatement()
        case .drag:     return try parseDragStatement()
        case .help:     _ = advance(); skipNewlines(); return .helpCmd
        case .debug:    _ = advance(); skipNewlines(); return .debugCmd
        case .dial:     return try parseDialStatement()
        case .reset:    return try parseResetStatement()
        case .print:    return try parsePrintStatement()
        case .disable:  return try parseDisableStatement()
        case .enable:   return try parseEnableStatement()
        case .run:      return try parseRunStatement()
        case .request:  return try parseRequestStatement()
        case .reply:    return try parseReplyStatement()
        case .start:    return try parseStartStatement()
        case .stop:     return try parseStopStatement()
        case .copy:     return try parseCopyStatement()
        case .export:   return try parseExportStatement()
        case .import:   return try parseImportStatement()
        case .convert:  return try parseConvertStatement()
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

        // Handle navigation keywords directly as literal values.
        // "go next", "go previous", "go first", "go last" need special handling
        // because these tokens have their own TokenType and wouldn't parse
        // correctly as general expressions.
        switch current.type {
        case .next:
            let tok = advance()
            skipNewlines()
            return .go(destination: .literal(tok.value))
        case .first:
            let tok = advance()
            // Check if this is "first card" etc. vs just "first"
            if current.type == .card || current.type == .background {
                let objType = advance()
                skipNewlines()
                return .go(destination: .literal("\(tok.value) \(objType.value)"))
            }
            skipNewlines()
            return .go(destination: .literal(tok.value))
        case .last:
            let tok = advance()
            if current.type == .card || current.type == .background {
                let objType = advance()
                skipNewlines()
                return .go(destination: .literal("\(tok.value) \(objType.value)"))
            }
            skipNewlines()
            return .go(destination: .literal(tok.value))
        case .identifier:
            // Handle "previous", "prev", "back" which are not keywords
            let lower = current.value.lowercased()
            if lower == "previous" || lower == "prev" || lower == "back" {
                let tok = advance()
                skipNewlines()
                return .go(destination: .literal(tok.value))
            }
            // Fall through to general expression parsing
            let dest = try parseExpression()
            skipNewlines()
            return .go(destination: dest)
        default:
            let dest = try parseExpression()
            skipNewlines()
            return .go(destination: dest)
        }
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

    private mutating func parseCreateStatement() throws -> Statement {
        _ = try expect(.create)

        // "create background "name""
        if current.type == .background {
            _ = advance()
            let name = try parseExpression()
            skipNewlines()
            return .createBackground(name: name)
        }

        // "create a new card [with background "name"]" or "create card [with background "name"]"
        // Skip optional "a" and "new"
        if current.type == .identifier && current.value.lowercased() == "a" { _ = advance() }
        if current.type == .identifier && current.value.lowercased() == "new" { _ = advance() }

        if current.type == .card {
            _ = advance()
            // Check for "with background "name""
            var bgName: Expression? = nil
            if current.type == .with {
                _ = advance()
                if current.type == .background {
                    _ = advance()
                    bgName = try parseExpression()
                }
            }
            skipNewlines()
            return .createCard(backgroundName: bgName)
        }

        throw ParseError.unexpected(current, expected: "card or background")
    }

    private mutating func parseShowStatement() throws -> Statement {
        _ = try expect(.show)
        // "show all cards" — "all" is an identifier, "cards" could be .card or identifier "cards"
        if current.type == .identifier && current.value.lowercased() == "all" {
            _ = advance()
            if current.type == .card || (current.type == .identifier && current.value.lowercased() == "cards") {
                _ = advance()
                skipNewlines()
                return .showAllCards
            }
        }
        // "show <object>" — show field 1, show button "OK", etc.
        let expr = try parseExpression()
        skipNewlines()
        return .showObject(expr)
    }

    // MARK: - HypeTalk compliance commands

    private mutating func parseAddStatement() throws -> Statement {
        _ = try expect(.add)
        let value = try parseExpression()
        _ = try expect(.to)
        let target = try parseExpression()
        skipNewlines()
        return .addTo(value: value, variable: target)
    }

    private mutating func parseSubtractStatement() throws -> Statement {
        _ = try expect(.subtract)
        let value = try parseExpression()
        _ = try expect(.from)
        let target = try parseExpression()
        skipNewlines()
        return .subtractFrom(value: value, variable: target)
    }

    private mutating func parseMultiplyCmd() throws -> Statement {
        _ = try expect(.multiply)
        let target = try parseExpression()
        _ = try expect(.by)
        let value = try parseExpression()
        skipNewlines()
        return .multiplyBy(variable: target, value: value)
    }

    private mutating func parseDivideCmd() throws -> Statement {
        _ = try expect(.divide)
        let target = try parseExpression()
        _ = try expect(.by)
        let value = try parseExpression()
        skipNewlines()
        return .divideBy(variable: target, value: value)
    }

    private mutating func parseDeleteStatement() throws -> Statement {
        _ = try expect(.delete)
        let target = try parseExpression()
        skipNewlines()
        return .deleteObject(target)
    }

    private mutating func parseFindStatement() throws -> Statement {
        _ = try expect(.find)
        let text = try parseExpression()
        skipNewlines()
        return .findText(text)
    }

    private mutating func parseSelectStatement() throws -> Statement {
        _ = try expect(.select)
        let target = try parseExpression()
        skipNewlines()
        return .selectObject(target)
    }

    private mutating func parseSortStatement() throws -> Statement {
        _ = try expect(.sort)
        // skip optional "cards"
        if current.type == .card { _ = advance() }
        if current.type == .identifier && current.value.lowercased() == "cards" { _ = advance() }
        _ = try expect(.by)
        let expr = try parseExpression()
        skipNewlines()
        return .sortCards(by: expr)
    }

    private mutating func parseHideStatement() throws -> Statement {
        _ = try expect(.hide)
        let target = try parseExpression()
        skipNewlines()
        return .hideObject(target)
    }

    private mutating func parseLockStatement() throws -> Statement {
        _ = try expect(.lock)
        // "lock screen"
        if current.type == .identifier && current.value.lowercased() == "screen" {
            _ = advance()
            skipNewlines()
            return .lockScreen
        }
        let target = try parseExpression()
        skipNewlines()
        return .expressionStatement(target) // fallback
    }

    private mutating func parseUnlockStatement() throws -> Statement {
        _ = try expect(.unlock)
        if current.type == .identifier && current.value.lowercased() == "screen" {
            _ = advance()
            skipNewlines()
            return .unlockScreen
        }
        let target = try parseExpression()
        skipNewlines()
        return .expressionStatement(target)
    }

    private mutating func parseOpenStatement() throws -> Statement {
        _ = try expect(.open)
        if current.type == .stack {
            _ = advance()
            let name = try parseExpression()
            skipNewlines()
            return .openStack(name)
        }
        let target = try parseExpression()
        skipNewlines()
        return .expressionStatement(target)
    }

    // MARK: - Phase 2 command parsers

    private mutating func parseChooseStatement() throws -> Statement {
        _ = try expect(.choose)
        let tool = try parseExpression()
        // Skip optional "tool" keyword
        if current.type == .identifier && current.value.lowercased() == "tool" { _ = advance() }
        skipNewlines()
        return .chooseTool(tool)
    }

    private mutating func parseCloseStatement() throws -> Statement {
        _ = try expect(.close)
        // "close window" or "close <expr>"
        if current.type == .identifier && current.value.lowercased() == "window" {
            _ = advance()
            skipNewlines()
            return .closeWindow
        }
        let _ = try parseExpression()
        skipNewlines()
        return .closeWindow
    }

    private mutating func parseSaveStatement() throws -> Statement {
        _ = try expect(.save)
        // Skip optional "this"
        _ = match(.this)
        // Skip optional "stack"
        _ = match(.stack)
        skipNewlines()
        return .saveStack
    }

    private mutating func parseMarkStatement() throws -> Statement {
        _ = try expect(.mark)
        if current.type == .newline || current.type == .eof {
            skipNewlines()
            return .markCard(nil)
        }
        let expr = try parseExpression()
        skipNewlines()
        return .markCard(expr)
    }

    private mutating func parseUnmarkStatement() throws -> Statement {
        _ = try expect(.unmark)
        if current.type == .newline || current.type == .eof {
            skipNewlines()
            return .unmarkCard(nil)
        }
        let expr = try parseExpression()
        skipNewlines()
        return .unmarkCard(expr)
    }

    private mutating func parseEditStatement() throws -> Statement {
        _ = try expect(.edit)
        // "edit script of <expr>" or "edit <expr>"
        if current.type == .identifier && current.value.lowercased() == "script" {
            _ = advance()
            _ = match(.of)
        }
        let target = try parseExpression()
        skipNewlines()
        return .editScriptOf(target)
    }

    private mutating func parseTypeStatement() throws -> Statement {
        _ = try expect(.typeText)
        let text = try parseExpression()
        skipNewlines()
        return .typeText(text)
    }

    private mutating func parsePushStatement() throws -> Statement {
        _ = try expect(.push)
        if current.type == .newline || current.type == .eof {
            skipNewlines()
            return .push(nil)
        }
        let expr = try parseExpression()
        skipNewlines()
        return .push(expr)
    }

    private mutating func parseClickStatement() throws -> Statement {
        _ = try expect(.click)
        // Skip optional "at"
        if current.type == .identifier && current.value.lowercased() == "at" { _ = advance() }
        let loc = try parseExpression()
        skipNewlines()
        return .clickAt(loc)
    }

    private mutating func parseDragStatement() throws -> Statement {
        _ = try expect(.drag)
        // Skip optional "from"
        _ = match(.from)
        let fromExpr = try parseExpression()
        _ = try expect(.to)
        let toExpr = try parseExpression()
        skipNewlines()
        return .dragFrom(fromExpr, toExpr)
    }

    private mutating func parseDialStatement() throws -> Statement {
        _ = try expect(.dial)
        let expr = try parseExpression()
        skipNewlines()
        return .dialCmd(expr)
    }

    private mutating func parseResetStatement() throws -> Statement {
        _ = try expect(.reset)
        if current.type == .newline || current.type == .eof {
            skipNewlines()
            return .resetCmd(nil)
        }
        let expr = try parseExpression()
        skipNewlines()
        return .resetCmd(expr)
    }

    private mutating func parsePrintStatement() throws -> Statement {
        _ = try expect(.print)
        if current.type == .newline || current.type == .eof {
            skipNewlines()
            return .printCmd(nil)
        }
        let expr = try parseExpression()
        skipNewlines()
        return .printCmd(expr)
    }

    private mutating func parseDisableStatement() throws -> Statement {
        _ = try expect(.disable)
        let expr = try parseExpression()
        skipNewlines()
        return .disableCmd(expr)
    }

    private mutating func parseEnableStatement() throws -> Statement {
        _ = try expect(.enable)
        let expr = try parseExpression()
        skipNewlines()
        return .enableCmd(expr)
    }

    private mutating func parseRunStatement() throws -> Statement {
        _ = try expect(.run)
        let expr = try parseExpression()
        skipNewlines()
        return .runCmd(expr)
    }

    private mutating func parseRequestStatement() throws -> Statement {
        _ = try expect(.request)
        let expr = try parseExpression()
        skipNewlines()
        return .requestCmd(expr)
    }

    private mutating func parseReplyStatement() throws -> Statement {
        _ = try expect(.reply)
        let expr = try parseExpression()
        skipNewlines()
        return .replyCmd(expr)
    }

    private mutating func parseStartStatement() throws -> Statement {
        _ = try expect(.start)
        _ = match(.using)
        let expr = try parseExpression()
        skipNewlines()
        return .startUsing(expr)
    }

    private mutating func parseStopStatement() throws -> Statement {
        _ = try expect(.stop)
        _ = match(.using)
        let expr = try parseExpression()
        skipNewlines()
        return .stopUsing(expr)
    }

    private mutating func parseCopyStatement() throws -> Statement {
        _ = try expect(.copy)
        // "copy template" or just "copy"
        if current.type == .template {
            _ = advance()
            skipNewlines()
            return .copyTemplate
        }
        // Consume remaining expression if any
        if current.type != .newline && current.type != .eof {
            let _ = try parseExpression()
        }
        skipNewlines()
        return .copyTemplate
    }

    private mutating func parseExportStatement() throws -> Statement {
        _ = try expect(.export)
        // Skip optional "paint"
        _ = match(.paint)
        let expr = try parseExpression()
        skipNewlines()
        return .exportPaint(expr)
    }

    private mutating func parseImportStatement() throws -> Statement {
        _ = try expect(.import)
        // Skip optional "paint"
        _ = match(.paint)
        let expr = try parseExpression()
        skipNewlines()
        return .importPaint(expr)
    }

    private mutating func parseConvertStatement() throws -> Statement {
        _ = try expect(.convert)
        let source = try parseExpression()
        _ = try expect(.to)
        let target = try parseExpression()
        skipNewlines()
        return .convert(source, target)
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
            // `is not` variants
            if current.type == .not {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "in" {
                    _ = advance()
                    let right = try parseAddition()
                    return .isNotIn(left, right)
                }
                if current.type == .identifier && current.value.lowercased() == "within" {
                    _ = advance()
                    let right = try parseAddition()
                    return .isNotWithin(left, right)
                }
                if current.type == .identifier && (current.value.lowercased() == "a" || current.value.lowercased() == "an") {
                    _ = advance()
                    let typeName = advance().value
                    return .isNotA(left, typeName)
                }
                // Regular "is not" (inequality)
                let right = try parseConcatenation()
                return .binary(left, .notEqual, right)
            }
            if current.type == .identifier && current.value.lowercased() == "in" {
                _ = advance()
                let right = try parseAddition()
                return .isIn(left, right)
            }
            if current.type == .identifier && current.value.lowercased() == "within" {
                _ = advance()
                let right = try parseAddition()
                return .isWithin(left, right)
            }
            if current.type == .identifier && (current.value.lowercased() == "a" || current.value.lowercased() == "an") {
                _ = advance()
                let typeName = advance().value
                return .isA(left, typeName)
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
        while current.type == .multiply || current.type == .divide || current.type == .mod || current.type == .intDiv {
            let op = advance()
            let binOp: BinaryOp
            switch op.type {
            case .multiply: binOp = .multiply
            case .divide:   binOp = .divide
            case .mod:      binOp = .modulo
            case .intDiv:   binOp = .intDiv
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

        case .this:
            _ = advance()
            return .this

        case .empty:
            _ = advance()
            return .empty

        case .the:
            return try parseTheExpression()

        case .card, .background, .field, .button, .stack, .webpage:
            return try parseObjectReference()

        case .lparen:
            _ = advance()
            let expr = try parseExpression()
            _ = try expect(.rparen)
            return expr

        case .identifier where current.value.lowercased() == "there":
            _ = advance() // consume "there"
            _ = match(.is)
            let negated = current.type == .identifier && current.value.lowercased() == "no"
            if negated { _ = advance() }
            let hasArticle = current.type == .identifier && (current.value.lowercased() == "a" || current.value.lowercased() == "an")
            if hasArticle { _ = advance() }
            let objectType = advance().value
            let nameExpr = try parseExpression()
            return negated ? .thereIsNo(objectType, nameExpr) : .thereIsA(objectType, nameExpr)

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

        case .down:
            let tok = advance()
            return .literal(tok.value)

        case .from, .by, .times,
             .choose, .close, .save, .quit, .mark, .unmark, .push, .pop,
             .click, .drag, .run, .print, .help, .debug, .reset,
             .export, .import, .copy, .disable, .enable, .edit, .dial,
             .request, .reply, .start, .stop, .using, .template, .paint,
             .report, .file, .printing, .convert, .typeText:
            // These keywords can appear as identifiers in some contexts.
            let tok = advance()
            return .literal(tok.value)

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

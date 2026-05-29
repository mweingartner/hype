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

    /// Check for trailing "on background" / "on bg" after a create
    /// button/field statement. Consumes the tokens if matched.
    private mutating func checkOnBackground() -> Bool {
        if current.type == .on {
            let cp = pos
            _ = advance()  // on
            if current.type == .background {
                _ = advance()  // background / bg
                return true
            }
            pos = cp  // rewind — not "on background"
        }
        return false
    }

    /// Non-destructive lookahead. `peek(0)` returns `current`,
    /// `peek(1)` returns the next token, etc. Returns `nil` past
    /// the end of the token stream rather than the EOF token — the
    /// caller can distinguish "no such token" from "EOF reached".
    /// Used by statement dispatch for identifier keywords (e.g.
    /// `fill` / `clear`) that are only reserved when followed by a
    /// specific next token like `.tilemap`.
    private func peek(_ offset: Int) -> Token? {
        let index = pos + offset
        guard index >= 0 && index < tokens.count else { return nil }
        return tokens[index]
    }

    private func isAppleMusicPhrase(startingAt offset: Int = 0) -> Bool {
        guard let first = peek(offset),
              first.type == .identifier else { return false }
        let value = first.value.lowercased()
        if value == "applemusic" { return true }
        guard value == "apple",
              let second = peek(offset + 1),
              second.type == .identifier else { return false }
        return second.value.lowercased() == "music"
    }

    @discardableResult
    private mutating func consumeAppleMusicPhrase() -> Bool {
        guard current.type == .identifier else { return false }
        let value = current.value.lowercased()
        if value == "applemusic" {
            _ = advance()
            return true
        }
        if value == "apple",
           peek(1)?.type == .identifier,
           peek(1)?.value.lowercased() == "music" {
            _ = advance()
            _ = advance()
            return true
        }
        return false
    }

    // MARK: - Top-level

    /// Parse the full script into handler declarations.
    public mutating func parse() throws -> Script {
        var handlers: [Handler] = []
        var topLevelGlobalNames: [String] = []
        skipNewlines()
        while current.type != .eof {
            if current.type == .global {
                let statement = try parseGlobalStatement()
                if case .globalDecl(let names) = statement {
                    topLevelGlobalNames.append(contentsOf: names)
                }
                skipNewlines()
                continue
            }
            let handler = try parseHandler()
            handlers.append(handler)
            skipNewlines()
        }
        if !topLevelGlobalNames.isEmpty {
            let globals = stableUnique(topLevelGlobalNames)
            handlers = handlers.map { handler in
                Handler(
                    name: handler.name,
                    handlerType: handler.handlerType,
                    params: handler.params,
                    body: [.globalDecl(globals)] + handler.body,
                    line: handler.line
                )
            }
        }
        return Script(handlers: handlers)
    }

    private func stableUnique(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for name in names {
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(name)
        }
        return result
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
        case .say:      return try parseSayStatement()
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
        case .pop:
            _ = advance()
            // Skip optional `card` keyword — `pop card` is the idiomatic HyperCard form.
            if current.type == .card { _ = advance() }
            skipNewlines()
            return .pop
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
        case .listen:   return try parseListenStatement()
        case .connect:  return try parseConnectStatement()
        case .send:     return try parseSendStatement()
        case .start:    return try parseStartStatement()
        case .stop:     return try parseStopStatement()
        case .copy:     return try parseCopyStatement()
        case .export:   return try parseExportStatement()
        case .import:   return try parseImportStatement()
        case .convert:  return try parseConvertStatement()
        case .constrain: return try parseConstrainStatement()
        case .play:     return try parsePlayStatement()
        case .beep:     return try parseBeepStatement()
        case .wait:     return try parseWaitStatement()
        case .animate:   return try parseAnimateStatement()
        case .remesh:    return try parseRemeshAssetStatement()
        case .retexture: return try parseRetextureAssetStatement()
        case .identifier:
            // Check for SpriteKit commands and aliases
            switch current.value.lowercased() {
            case "new":
                // "new card" → alias for "create a new card"
                if peek(1)?.type == .card {
                    _ = advance()  // new
                    _ = advance()  // card
                    var bgName: Expression? = nil
                    if current.type == .with {
                        _ = advance()
                        if current.type == .background { _ = advance() }
                        bgName = try parseExpression()
                    }
                    skipNewlines()
                    return .createCard(backgroundName: bgName)
                }
                let expr = try parseExpression()
                skipNewlines()
                return .expressionStatement(expr)
            case "nextcard":
                _ = advance()
                skipNewlines()
                return .go(destination: .literal("next"))
            case "prevcard", "previouscard":
                _ = advance()
                skipNewlines()
                return .go(destination: .literal("previous"))
            case "pause":
                if isAppleMusicPhrase(startingAt: 1) {
                    return try parsePauseAppleMusicStatement()
                }
                if peek(1)?.type == .identifier && peek(1)?.value.lowercased() == "music" {
                    return try parsePauseMusicStatement()
                }
                return try parsePauseSceneStatement()
            case "resume":
                if isAppleMusicPhrase(startingAt: 1) {
                    return try parseResumeAppleMusicStatement()
                }
                if peek(1)?.type == .identifier && peek(1)?.value.lowercased() == "music" {
                    return try parseResumeMusicStatement()
                }
                return try parseResumeSceneStatement()
            case "authorize":
                if isAppleMusicPhrase(startingAt: 1) {
                    return try parseAuthorizeAppleMusicStatement()
                }
                let expr = try parseExpression()
                skipNewlines()
                return .expressionStatement(expr)
            case "search":
                if isAppleMusicPhrase(startingAt: 1) {
                    return try parseSearchAppleMusicStatement()
                }
                let expr = try parseExpression()
                skipNewlines()
                return .expressionStatement(expr)
            case "seek", "position":
                if isAppleMusicPhrase(startingAt: 1) {
                    return try parseSeekAppleMusicStatement()
                }
                let expr = try parseExpression()
                skipNewlines()
                return .expressionStatement(expr)
            case "loop":
                if peek(1)?.type == .identifier && peek(1)?.value.lowercased() == "pattern" {
                    return try parseLoopMusicPatternStatement()
                }
                let expr = try parseExpression()
                skipNewlines()
                return .expressionStatement(expr)
            case "remove":
                return try parseRemoveSpriteStatement()
            case "apply":
                return try parseApplyStatement()
            case "fill":
                // `fill tilemap "X" with N` — bulk-paint every cell
                // of a tile map. Only consume the `fill` identifier
                // when followed by the `.tilemap` token; otherwise
                // leave it for the bare-expression fallback so
                // `fill` keeps working as an identifier elsewhere.
                if peek(1)?.type == .tilemap {
                    return try parseFillTileMapStatement()
                }
                let expr = try parseExpression()
                skipNewlines()
                return .expressionStatement(expr)
            case "clear":
                // `clear tilemap "X"` — clear every cell of a tile
                // map (equivalent to `fill tilemap "X" with -1`).
                // Same peek-gate as `fill` so `clear` remains
                // available as a variable name.
                if peek(1)?.type == .tilemap {
                    return try parseClearTileMapStatement()
                }
                let expr = try parseExpression()
                skipNewlines()
                return .expressionStatement(expr)
            case "activatelistener":
                return try parseActivateListenerStatement()
            default:
                if shouldParseExternalCommandStatement() {
                    return try parseExternalCommandStatement()
                }
                // Bare expression (function call, etc.)
                let expr = try parseExpression()
                skipNewlines()
                return .expressionStatement(expr)
            }
        default:
            // Bare expression (function call, etc.)
            let expr = try parseExpression()
            skipNewlines()
            return .expressionStatement(expr)
        }
    }

    private func shouldParseExternalCommandStatement() -> Bool {
        guard current.type == .identifier, let next = peek(1) else { return false }
        if next.type == .newline || next.type == .eof || next.type == .lparen {
            return false
        }
        switch next.type {
        case .string, .integer, .float, .identifier, .comma,
             .the, .it, .me, .this, .empty, .await,
             .word, .char, .character, .item, .line, .number,
             .first, .second, .third, .last, .middle, .any,
             .not,
             .card, .background, .field, .button, .stack, .webpage,
             .image, .video, .sprite, .scene, .spritearea, .request,
             .connection, .listener:
            return true
        default:
            return false
        }
    }

    private mutating func parseExternalCommandStatement() throws -> Statement {
        let name = advance().value
        var arguments: [Expression] = []
        while current.type != .newline && current.type != .eof && current.type != .end && current.type != .else {
            if current.type == .comma {
                _ = advance()
                continue
            }
            arguments.append(try parseExpression())
            if current.type == .comma {
                _ = advance()
            } else if current.type != .newline && current.type != .eof && current.type != .end && current.type != .else {
                // Classic external commands use whitespace-separated
                // or comma-separated parameters. Continue while the
                // next token can start another argument; otherwise
                // let the outer parser surface the syntax error.
                if !Self.canStartPrimaryExpression(current.type) {
                    break
                }
            }
        }
        skipNewlines()
        return .externalCommand(name: name, arguments: arguments)
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
        // Extension: `get <expr> into <target>` is accepted as sugar
        // for `put <expr> into <target>`. Classic HyperTalk didn't
        // have this form — `get` always put the value in `it` — but
        // users intuitively reach for it (and the user who reported
        // this bug wrote it that way), and supporting it costs one
        // branch here. The desugared put is what the interpreter
        // already knows how to execute, so no runtime changes are
        // needed.
        if current.type == .into {
            _ = advance()
            let target = try parseExpression()
            skipNewlines()
            return .put(source: expr, preposition: .into, target: target)
        }
        skipNewlines()
        return .get(expr)
    }

    private mutating func parseSetStatement() throws -> Statement {
        _ = try expect(.set)
        // `set tile col,row of tilemap "name" to tileIndex`
        if current.type == .tile {
            _ = advance()
            let col = try parseExpression()
            _ = try expect(.comma)
            let row = try parseExpression()
            _ = try expect(.of)
            _ = match(.tilemap)
            let tilemap = try parseExpression()
            _ = try expect(.to)
            let tileIndex = try parseExpression()
            skipNewlines()
            return .setTile(column: col, row: row, tilemap: tilemap, tileIndex: tileIndex)
        }
        // `set the <property> of <target> to <value>`
        _ = match(.the)
        let propTok = advance()
        let property = propTok.value

        var target: Expression? = nil
        if current.type == .of {
            _ = advance()
            skipTransparentOfChain()
            target = try parseExpression()
        }

        _ = try expect(.to)
        let value = try parseExpression()
        skipNewlines()
        return .set(property: property, of: target, to: value)
    }

    /// Swallow `physicsBody of` (and similar natural-language
    /// pass-through wrappers) immediately after an `of` keyword so
    /// that `set the velocityX of physicsBody of sprite "player"`
    /// parses equivalently to `set the velocityX of sprite "player"`.
    ///
    /// Background: physics properties (velocity, friction, mass,
    /// bounce, etc.) are conceptually on the SpriteKit `physicsBody`
    /// of a sprite node, but HypeTalk flattens them onto the sprite
    /// node itself — there's no separate `physicsBody` object to
    /// reference. Local LLMs (gemma, llama) generating HypeTalk
    /// naturally write `the velocityX of physicsBody of sprite "X"`
    /// because that mirrors the Swift API shape. Rather than
    /// systematically re-training every model, we accept the
    /// transparent wrapper and drop it in the parser. The
    /// interpreter sees the canonical `velocityX of sprite "X"`
    /// form either way.
    ///
    /// Handles repeated wrappers too (`of physicsBody of physicsBody
    /// of sprite "X"`) so robust-to-the-point-of-weird inputs also
    /// work.
    private mutating func skipTransparentOfChain() {
        while current.type == .identifier,
              current.value.lowercased() == "physicsbody",
              pos + 1 < tokens.count,
              tokens[pos + 1].type == .of {
            _ = advance()   // physicsBody
            _ = advance()   // of
        }
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
                let elseToken = advance()
                let elseStmt: Statement
                if current.type == .if && current.line == elseToken.line {
                    elseStmt = try parseIfStatement()
                } else {
                    elseStmt = try parseStatement()
                }
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
            let elseToken = advance()
            if current.type == .if && current.line == elseToken.line {
                let elseIfStatement = try parseIfStatement()
                skipNewlines()
                return .ifThenElse(condition: condition, thenBlock: thenBlock, elseBlock: [elseIfStatement])
            }
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

        // `repeat with i = 1 to 10` or `repeat with i from 1 to 10`
        if current.type == .with {
            _ = advance()
            let varName = advance().value
            if !match(.eq) {
                _ = try expect(.from)
            }
            let fromExpr = try parseExpression()
            _ = match(.down)
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
        if current.type == .card {
            _ = advance()
            skipNewlines()
            return .go(destination: .literal("next"))
        }
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

        // Existing: `ask ai "<prompt>" [with model <m>] [with message <msg>]`
        if current.type == .ai {
            _ = advance()
            let prompt = try parseExpression()
            var model: Expression? = nil
            var callback: Expression? = nil
            if current.type == .with || current.type == .using {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "model" {
                    _ = advance()
                    model = try parseExpression()
                    if current.type == .with {
                        _ = advance()
                    }
                }
                if current.type == .message || (current.type == .identifier && current.value.lowercased() == "message") {
                    _ = advance()
                    callback = try parseExpression()
                }
            }
            skipNewlines()
            return .askAI(prompt: prompt, model: model, callback: callback)
        }

        // Phase 3: `ask meshy "<prompt>" [with style <s>] [with model <m>] [with message <msg>]`
        //
        // Modifiers may appear in any order. The while loop accepts any number
        // of `with <field> <value>` clauses until the next non-`with` token.
        if current.type == .meshy {
            _ = advance()
            let prompt = try parseExpression()
            var style: Expression? = nil
            var model: Expression? = nil
            var callback: Expression? = nil

            while current.type == .with || current.type == .using {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "style" {
                    _ = advance()
                    style = try parseExpression()
                } else if current.type == .identifier && current.value.lowercased() == "model" {
                    _ = advance()
                    model = try parseExpression()
                } else if current.type == .message
                    || (current.type == .identifier && current.value.lowercased() == "message") {
                    _ = advance()
                    callback = try parseExpression()
                } else {
                    // Unrecognised modifier — bail; the outer parser will pick up the token.
                    throw ParseError.unexpected(current, expected: "style, model, or message")
                }
            }

            skipNewlines()
            return .askMeshy(prompt: prompt, style: style, model: model, callback: callback)
        }

        // Existing fallback: plain `ask "<prompt>"`.
        let expr = try parseExpression()
        skipNewlines()
        return .ask(prompt: expr)
    }

    /// Parse `remesh asset "<name>" to <polycount> [with message <msg>]`
    ///
    /// Phase 4 grammar. `remesh` is consumed by the caller via the switch case.
    /// `asset` must follow as an identifier keyword, then the name expression,
    /// then `to`, then the polycount expression, then an optional
    /// `with message <callbackName>` modifier.
    private mutating func parseRemeshAssetStatement() throws -> Statement {
        _ = try expect(.remesh)
        // Expect the `asset` identifier keyword.
        guard current.type == .identifier && current.value.lowercased() == "asset" else {
            throw ParseError.unexpected(current, expected: "asset")
        }
        _ = advance()
        let nameExpr = try parseExpression()
        // Expect `to`.
        guard current.type == .to else {
            throw ParseError.unexpected(current, expected: "to")
        }
        _ = advance()
        let polyExpr = try parseExpression()
        var callback: Expression? = nil
        if current.type == .with || current.type == .using {
            _ = advance()
            if current.type == .message
                || (current.type == .identifier && current.value.lowercased() == "message") {
                _ = advance()
                callback = try parseExpression()
            } else {
                throw ParseError.unexpected(current, expected: "message")
            }
        }
        skipNewlines()
        return .remeshAsset(sourceName: nameExpr, targetPolycount: polyExpr, callback: callback)
    }

    /// Parse `retexture asset "<name>" with prompt "<text>" [with message <msg>]`
    ///
    /// Phase 4 grammar. `retexture` is consumed by the caller.
    /// Modifiers `with prompt` and `with message` may appear in either order.
    private mutating func parseRetextureAssetStatement() throws -> Statement {
        _ = try expect(.retexture)
        // Expect the `asset` identifier keyword.
        guard current.type == .identifier && current.value.lowercased() == "asset" else {
            throw ParseError.unexpected(current, expected: "asset")
        }
        _ = advance()
        let nameExpr = try parseExpression()
        var stylePrompt: Expression? = nil
        var callback: Expression? = nil
        while current.type == .with || current.type == .using {
            _ = advance()
            let lex = current.value.lowercased()
            guard current.type == .identifier || current.type == .message else {
                throw ParseError.unexpected(current, expected: "prompt or message")
            }
            _ = advance()
            switch lex {
            case "prompt":  stylePrompt = try parseExpression()
            case "message": callback = try parseExpression()
            default: throw ParseError.unexpected(current, expected: "prompt or message")
            }
        }
        guard let prompt = stylePrompt else {
            throw ParseError.unexpected(current, expected: "with prompt <text>")
        }
        skipNewlines()
        return .retextureAsset(sourceName: nameExpr, stylePrompt: prompt, callback: callback)
    }

    private mutating func parseAnswerStatement() throws -> Statement {
        _ = try expect(.answer)
        let expr = try parseExpression()
        skipNewlines()
        return .answer(prompt: expr)
    }

    private mutating func parseSayStatement() throws -> Statement {
        _ = try expect(.say)
        let expr = try parseExpression()
        skipNewlines()
        return .say(expr)
    }

    private mutating func parseActivateListenerStatement() throws -> Statement {
        _ = advance()
        _ = match(.to)
        let expr = try parseExpression()
        skipNewlines()
        return .activateListener(expr)
    }

    /// Parse: `visual [effect] <name> [<duration>]`
    ///
    /// The effect name is consumed as a **literal string**, not
    /// evaluated as an expression. `visual effect dissolve` means
    /// the literal word "dissolve", not a variable named `dissolve`.
    /// This matches HyperCard's syntax where effect names are
    /// unquoted keywords. Multi-word names like "wipe left" are
    /// joined: we consume identifier tokens until we hit a number
    /// (duration), newline, or EOF.
    ///
    /// Quoted strings also work: `visual effect "dissolve"`.
    ///
    /// Examples:
    ///   visual effect dissolve
    ///   visual effect dissolve 1.5
    ///   visual effect wipe left
    ///   visual effect "push" 2
    private mutating func parseVisualStatement() throws -> Statement {
        _ = try expect(.visual)
        _ = match(.effect) // optional "effect" keyword

        // If it's a quoted string, parse it normally
        let expr: Expression
        if current.type == .string {
            expr = try parsePrimary()
        } else {
            // Consume one or more tokens as a literal effect name.
            // Effect names like "dissolve", "push", "wipe left",
            // "iris open", "flip horizontal" may contain words that
            // the lexer maps to keyword tokens (push → .push,
            // open → .open, down → .down, etc.). We accept ANY
            // token that isn't a number, newline, or EOF as part
            // of the effect name so all combinations work unquoted.
            var nameParts: [String] = []
            while current.type != .newline &&
                  current.type != .eof &&
                  current.type != .integer &&
                  current.type != .float {
                nameParts.append(advance().value)
            }
            if nameParts.isEmpty {
                throw ParseError.unexpected(current, expected: "effect name")
            }
            expr = .literal(nameParts.joined(separator: " "))
        }

        // Optional duration (number literal on the same line)
        var duration: Expression? = nil
        if current.type == .integer || current.type == .float {
            duration = try parsePrimary()
        }
        skipNewlines()
        return .visual(effectName: expr, duration: duration)
    }

    private mutating func parseCreateStatement() throws -> Statement {
        _ = try expect(.create)

        // "create music pattern "name" with instrument "piano" tempo 120 notes "c4q e4q""
        if current.type == .identifier && current.value.lowercased() == "music" {
            _ = advance()
            if current.type == .identifier && current.value.lowercased() == "pattern" {
                return try parseCreateMusicPatternTail()
            }
            throw ParseError.unexpected(current, expected: "pattern")
        }

        // Shorthand: "create pattern "name" ..."
        if current.type == .identifier && current.value.lowercased() == "pattern" {
            return try parseCreateMusicPatternTail()
        }

        // "create button "name" [on background]"
        // "create btn "name" [on background]"
        if current.type == .button {
            _ = advance()
            let name = try parsePrimary()
            let onBg = checkOnBackground()
            skipNewlines()
            return .createButton(name: name, onBackground: onBg)
        }

        // "create field "name" [on background]" / "create fld "name" [on background]"
        if current.type == .field {
            _ = advance()
            let name = try parsePrimary()
            let onBg = checkOnBackground()
            skipNewlines()
            return .createField(name: name, onBackground: onBg)
        }

        // "create background "name""
        if current.type == .background {
            _ = advance()
            let name = try parseExpression()
            skipNewlines()
            return .createBackground(name: name)
        }

        // "create group "name" [in group "parentName"]"
        if current.type == .identifier && current.value.lowercased() == "group" {
            _ = advance()
            let name = try parseExpression()
            var parentExpr: Expression? = nil
            if current.type == .identifier && current.value.lowercased() == "in" {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "group" { _ = advance() }
                parentExpr = try parseExpression()
            }
            skipNewlines()
            return .createGroup(name: name, parent: parentExpr)
        }

        // "create shape "name" [in scene/group "target"] [with type rect]"
        if current.type == .identifier && current.value.lowercased() == "shape" {
            _ = advance()
            let name = try parseExpression()
            var sceneExpr: Expression? = nil
            if current.type == .identifier && current.value.lowercased() == "in" {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "group" { _ = advance() }
                _ = match(.scene)
                sceneExpr = try parseExpression()
            }
            var shapeTypeExpr: Expression? = nil
            if current.type == .with {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "type" { _ = advance() }
                if current.type == .identifier {
                    shapeTypeExpr = .literal(current.value)
                    _ = advance()
                } else {
                    shapeTypeExpr = try parseExpression()
                }
            }
            skipNewlines()
            return .createShape(name: name, scene: sceneExpr, shapeType: shapeTypeExpr)
        }

        // "create sprite "name" [in scene/group "sceneName"] [with asset "assetName"]"
        if current.type == .sprite {
            _ = advance()
            let name = try parseExpression()
            var sceneExpr: Expression? = nil
            if current.type == .identifier && current.value.lowercased() == "in" {
                _ = advance()
                // Accept both "in scene X" and "in group X"
                if current.type == .identifier && current.value.lowercased() == "group" {
                    _ = advance()
                }
                _ = match(.scene)
                sceneExpr = try parseExpression()
            }
            var assetExpr: Expression? = nil
            if current.type == .with {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "asset" { _ = advance() }
                assetExpr = try parseExpression()
            }
            skipNewlines()
            return .createSprite(name: name, scene: sceneExpr, asset: assetExpr)
        }

        // "create scene "name" [in spritearea "areaName"] [with size W,H]"
        if current.type == .scene {
            _ = advance()
            let name = try parseExpression()
            var inAreaExpr: Expression? = nil
            if current.type == .identifier && current.value.lowercased() == "in" {
                _ = advance()
                _ = match(.spritearea)
                inAreaExpr = try parseExpression()
            }
            var widthExpr: Expression? = nil
            var heightExpr: Expression? = nil
            if current.type == .with {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "size" { _ = advance() }
                widthExpr = try parseExpression()
                _ = match(.comma)
                heightExpr = try parseExpression()
            }
            skipNewlines()
            return .createSpriteScene(name: name, inArea: inAreaExpr, width: widthExpr, height: heightExpr)
        }

        // "create spritearea "name" [at rect L,T,W,H]"
        if current.type == .spritearea {
            _ = advance()
            let name = try parseExpression()
            var rectExpr: Expression? = nil
            if current.type == .identifier && current.value.lowercased() == "at" {
                _ = advance()
                if current.type == .identifier && current.value.lowercased() == "rect" { _ = advance() }
                rectExpr = try parseExpression()
            }
            skipNewlines()
            return .createSpriteArea(name: name, rect: rectExpr)
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

        // "create tilemap "name" [columns N] [rows N] [tilesize N] [with tileset "name"]"
        if current.type == .tilemap {
            _ = advance()
            let name = try parseExpression()
            var cols: Expression? = nil
            var rows: Expression? = nil
            var tileSize: Expression? = nil
            var tileset: Expression? = nil
            while current.type == .identifier || current.type == .with {
                let kw = current.value.lowercased()
                if kw == "columns" { _ = advance(); cols = try parseExpression() }
                else if kw == "rows" { _ = advance(); rows = try parseExpression() }
                else if kw == "tilesize" { _ = advance(); tileSize = try parseExpression() }
                else if kw == "with" || kw == "tileset" {
                    _ = advance()
                    if current.type == .identifier && current.value.lowercased() == "tileset" { _ = advance() }
                    tileset = try parseExpression()
                }
                else { break }
            }
            skipNewlines()
            return .createTileMap(name: name, columns: cols, rows: rows, tileSize: tileSize, tileset: tileset)
        }

        // "create camera "name""
        if current.type == .camera {
            _ = advance()
            let name = try parseExpression()
            skipNewlines()
            return .createCamera(name: name)
        }

        // "create physicsfield "name" type linearGravity [strength N] [direction X,Y]"
        if current.type == .identifier && current.value.lowercased() == "physicsfield" {
            _ = advance()
            let name = try parseExpression()
            var typeExpr: Expression = .literal("linearGravity")
            if current.type == .identifier && current.value.lowercased() == "type" {
                _ = advance()
                typeExpr = try parseExpression()
            }
            var strengthExpr: Expression? = nil
            if current.type == .identifier && current.value.lowercased() == "strength" {
                _ = advance()
                strengthExpr = try parseExpression()
            }
            var directionExpr: Expression? = nil
            if current.type == .identifier && current.value.lowercased() == "direction" {
                _ = advance()
                directionExpr = try parseExpression()
            }
            skipNewlines()
            return .createPhysicsField(name: name, type: typeExpr, strength: strengthExpr, direction: directionExpr)
        }

        // "create joint "name" type pin from sprite "a" to sprite "b""
        if current.type == .joint {
            _ = advance()
            let name = try parseExpression()
            // Expect "type <jointType>"
            var typeExpr: Expression = .literal("pin")
            if current.type == .identifier && current.value.lowercased() == "type" {
                _ = advance()
                typeExpr = try parseExpression()
            }
            // Expect "from sprite <nodeA>"
            if current.type == .from { _ = advance() }
            if current.type == .sprite { _ = advance() }
            let nodeA = try parseExpression()
            // Expect "to sprite <nodeB>"
            _ = try expect(.to)
            if current.type == .sprite { _ = advance() }
            let nodeB = try parseExpression()
            skipNewlines()
            return .createJoint(name: name, type: typeExpr, nodeA: nodeA, nodeB: nodeB)
        }

        throw ParseError.unexpected(current, expected: "card, background, sprite, shape, scene, spritearea, tilemap, camera, or joint")
    }

    /// Parse: `constrain sprite "enemy" distance 50 to 200 from sprite "player"`
    private mutating func parseConstrainStatement() throws -> Statement {
        _ = try expect(.constrain)
        // source node: "sprite <name>"
        if current.type == .sprite { _ = advance() }
        let source = try parseExpression()
        // constraint type: "distance", "orient", "position"
        let typeExpr = try parseExpression()
        // optional min and max: "50 to 200"
        var minExpr: Expression? = nil
        var maxExpr: Expression? = nil
        if current.type == .integer || current.type == .float {
            minExpr = try parseExpression()
            if current.type == .to {
                _ = advance()
                maxExpr = try parseExpression()
            }
        }
        // "from sprite <target>"
        if current.type == .from { _ = advance() }
        if current.type == .sprite { _ = advance() }
        let target = try parseExpression()
        skipNewlines()
        return .createConstraint(type: typeExpr, source: source, target: target, min: minExpr, max: maxExpr)
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
        if !match(.from) {
            // The canonical HypeTalk form is "subtract 3 from x".
            // AI-generated scripts and users sometimes mirror the
            // "add 3 to x" shape as "subtract 3 to x"; accept it as
            // the same mutating subtraction rather than surfacing a
            // misleading parse error.
            _ = try expect(.to)
        }
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
        // "open scene "name" [with transition "fade" [duration 1.0]]"
        if current.type == .scene {
            _ = advance()
            let name = try parseExpression()
            var transitionExpr: Expression? = nil
            var durationExpr: Expression? = nil
            if current.type == .with {
                _ = advance()
                if current.type == .transition { _ = advance() }
                transitionExpr = try parseExpression()
                if current.type == .identifier && current.value.lowercased() == "duration" {
                    _ = advance()
                    durationExpr = try parseExpression()
                }
            }
            skipNewlines()
            return .openScene(name: name, transition: transitionExpr, duration: durationExpr)
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
        if current.type == .connection {
            _ = advance()
            let expr = try parseExpression()
            skipNewlines()
            return .closeConnection(expr)
        }
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
        // `push card` with no identifier means "push the current card".
        // HyperCard treats bare `card` as the current card — consume the
        // keyword and emit push(nil) rather than trying to parse an objectRef.
        if current.type == .card {
            let next = pos + 1 < tokens.count ? tokens[pos + 1] : Token(type: .eof, value: "", line: 0)
            if next.type == .newline || next.type == .eof {
                _ = advance()  // consume `card`
                skipNewlines()
                return .push(nil)
            }
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
        if current.type == .ai {
            _ = advance()
            if current.type == .identifier && current.value.lowercased() == "session" {
                _ = advance()
            }
            skipNewlines()
            return .resetCmd(.literal("ai session"))
        }
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
        // "run action "name" on sprite "spriteName""
        if current.type == .action {
            _ = advance()
            let actionExpr = try parseExpression()
            // expect "on"
            if current.type == .on {
                _ = advance()
            }
            // skip optional "sprite" keyword
            _ = match(.sprite)
            let nodeExpr = try parseExpression()
            skipNewlines()
            return .runSpriteAction(action: actionExpr, node: nodeExpr)
        }
        let expr = try parseExpression()
        skipNewlines()
        return .runCmd(expr)
    }

    private mutating func parseRequestStatement() throws -> Statement {
        _ = try expect(.request)
        if current.type == .identifier && current.value.lowercased() == "appleevent" {
            let expr = try parseExpression()
            skipNewlines()
            return .runCmd(expr)
        }
        let url = try parseExpression()
        var method: Expression? = nil
        var headers: Expression? = nil
        var body: Expression? = nil
        var username: Expression? = nil
        var password: Expression? = nil
        var callback: Expression? = nil
        while current.type != .newline && current.type != .eof {
            switch current.type {
            case .method:
                _ = advance()
                method = try parseExpression()
            case .headers:
                _ = advance()
                headers = try parseExpression()
            case .body:
                _ = advance()
                body = try parseExpression()
            case .username:
                _ = advance()
                username = try parseExpression()
            case .password:
                _ = advance()
                password = try parseExpression()
            case .with:
                _ = advance()
                if current.type == .message || (current.type == .identifier && current.value.lowercased() == "message") {
                    _ = advance()
                }
                callback = try parseExpression()
            default:
                let _ = try parseExpression()
            }
        }
        skipNewlines()
        return .requestURL(url: url, method: method, headers: headers, body: body, username: username, password: password, callback: callback)
    }

    private mutating func parseReplyStatement() throws -> Statement {
        _ = try expect(.reply)
        _ = match(.to)
        _ = match(.request)
        let request = try parseExpression()
        _ = match(.with)
        if current.type == .status {
            _ = advance()
        }
        let status = try parseExpression()
        var headers: Expression? = nil
        var body: Expression? = nil
        while current.type != .newline && current.type != .eof {
            switch current.type {
            case .headers:
                _ = advance()
                headers = try parseExpression()
            case .body:
                _ = advance()
                body = try parseExpression()
            default:
                let _ = try parseExpression()
            }
        }
        skipNewlines()
        return .replyRequest(request: request, status: status, headers: headers, body: body)
    }

    private mutating func parseListenStatement() throws -> Statement {
        _ = try expect(.listen)
        if current.type == .identifier && current.value.lowercased() == "for" {
            _ = advance()
        }
        if current.type == .http {
            _ = advance()
            _ = match(.on)
            _ = match(.port)
            let port = try parseExpression()
            var host: Expression? = nil
            var method: Expression? = nil
            var path: Expression? = nil
            var callback: Expression?
            while current.type != .newline && current.type != .eof {
                switch current.type {
                case .host:
                    _ = advance()
                    host = try parseExpression()
                case .method:
                    _ = advance()
                    method = try parseExpression()
                case .identifier where current.value.lowercased() == "path":
                    _ = advance()
                    path = try parseExpression()
                case .with:
                    _ = advance()
                    if current.type == .message || (current.type == .identifier && current.value.lowercased() == "message") {
                        _ = advance()
                    }
                    callback = try parseExpression()
                default:
                    let _ = try parseExpression()
                }
            }
            skipNewlines()
            guard let callback else {
                throw ParseError.unexpected(current, expected: "callback message")
            }
            return .listenHTTP(port: port, host: host, method: method, path: path, callback: callback)
        }
        if current.type == .tcp {
            _ = advance()
            _ = match(.on)
            _ = match(.port)
            let port = try parseExpression()
            var host: Expression? = nil
            var callback: Expression?
            while current.type != .newline && current.type != .eof {
                switch current.type {
                case .host:
                    _ = advance()
                    host = try parseExpression()
                case .with:
                    _ = advance()
                    if current.type == .message || (current.type == .identifier && current.value.lowercased() == "message") {
                        _ = advance()
                    }
                    callback = try parseExpression()
                default:
                    let _ = try parseExpression()
                }
            }
            skipNewlines()
            guard let callback else {
                throw ParseError.unexpected(current, expected: "callback message")
            }
            return .listenTCP(port: port, host: host, callback: callback)
        }
        throw ParseError.unexpected(current, expected: "http or tcp")
    }

    private mutating func parseConnectStatement() throws -> Statement {
        _ = try expect(.connect)
        _ = match(.to)
        _ = match(.host)
        let host = try parseExpression()
        _ = match(.on)
        _ = match(.port)
        let port = try parseExpression()
        var tls: Expression? = nil
        var callback: Expression?
        while current.type != .newline && current.type != .eof {
            switch current.type {
            case .tls:
                _ = advance()
                tls = try parseExpression()
            case .with:
                _ = advance()
                if current.type == .message || (current.type == .identifier && current.value.lowercased() == "message") {
                    _ = advance()
                }
                callback = try parseExpression()
            default:
                let _ = try parseExpression()
            }
        }
        skipNewlines()
        guard let callback else {
            throw ParseError.unexpected(current, expected: "callback message")
        }
        return .connectTCP(host: host, port: port, tls: tls, callback: callback)
    }

    private mutating func parseSendStatement() throws -> Statement {
        _ = try expect(.send)
        let data = try parseExpression()
        _ = try expect(.to)
        if match(.connection) {
            let connection = try parseExpression()
            skipNewlines()
            return .sendToConnection(data: data, connection: connection)
        }
        let connection = try parseExpression()
        skipNewlines()
        return .send(message: data, target: connection)
    }

    private mutating func parseStartStatement() throws -> Statement {
        _ = try expect(.start)
        // "start the animation of <expr>" — GIF playback command.
        // Security Finding 10: use expect(.of) after advancing past
        // .the and .animation so malformed input like
        // "start the animation from X" produces a clear ParseError
        // instead of silently consuming "from" as the expression.
        if current.type == .the,
           peek(1)?.type == .animation,
           peek(2)?.type == .of {
            _ = advance()               // .the
            _ = advance()               // .animation
            _ = try expect(.of)         // throws on typo like "from X"
            let expr = try parseExpression()
            skipNewlines()
            return .startAnimation(expr)
        }
        _ = match(.using)
        let expr = try parseExpression()
        skipNewlines()
        return .startUsing(expr)
    }

    private mutating func parseStopStatement() throws -> Statement {
        _ = try expect(.stop)
        if consumeAppleMusicPhrase() {
            skipNewlines()
            return .stopAppleMusic
        }
        if current.type == .identifier && current.value.lowercased() == "music" {
            _ = advance()
            skipNewlines()
            return .stopMusic
        }
        if current.type == .listener {
            _ = advance()
            let expr = try parseExpression()
            skipNewlines()
            return .stopListener(expr)
        }
        // "stop the animation of <expr>" — GIF playback command.
        // Security Finding 10: use expect(.of) for strict grammar.
        if current.type == .the,
           peek(1)?.type == .animation,
           peek(2)?.type == .of {
            _ = advance()               // .the
            _ = advance()               // .animation
            _ = try expect(.of)         // throws on typo like "from X"
            let expr = try parseExpression()
            skipNewlines()
            return .stopAnimation(expr)
        }
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
        if current.type == .identifier && current.value.lowercased() == "pattern" {
            _ = advance()
            let pattern = try parseExpression()
            _ = try expect(.to)
            if current.type == .identifier && current.value.lowercased() == "audio" { _ = advance() }
            if current.type == .identifier && current.value.lowercased() == "asset" { _ = advance() }
            let asset = try parseExpression()
            skipNewlines()
            return .exportMusicPattern(name: pattern, assetName: asset)
        }
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

    // MARK: - Sound command parsers

    private mutating func parsePlayStatement() throws -> Statement {
        _ = try expect(.play)
        // play stop
        if current.type == .stop {
            _ = advance()
            skipNewlines()
            return .playStop
        }
        // play pattern "name" [loop]
        if current.type == .identifier && current.value.lowercased() == "pattern" {
            _ = advance()
            let name = try parseExpression()
            var loop = false
            if current.type == .identifier && current.value.lowercased() == "loop" {
                _ = advance()
                loop = true
            }
            skipNewlines()
            return .playMusicPattern(name: name, loop: loop)
        }
        // play appleMusic song|album|playlist|station "id"
        // play apple music song|album|playlist|station "id"
        if consumeAppleMusicPhrase() {
            let typeToken = current.type == .identifier ? current.value : "song"
            if current.type == .identifier { _ = advance() }
            let id = try parseExpression()
            skipNewlines()
            return .playAppleMusic(source: MusicSourceKind.appleMusicCatalog.rawValue, itemType: typeToken, id: id)
        }
        // play <soundExpr> [tempo N] [<notesExpr>]
        let sound = try parseExpression()
        var tempo: Expression? = nil
        var notes: Expression? = nil
        // Check for optional "tempo N"
        if current.type == .identifier && current.value.lowercased() == "tempo" {
            _ = advance()
            tempo = try parsePrimary()
        }
        // Check for optional notes string (must be on the same logical line)
        if current.type == .string {
            notes = try parsePrimary()
        }
        skipNewlines()
        return .playSound(sound: sound, notes: notes, tempo: tempo)
    }

    private mutating func parseBeepStatement() throws -> Statement {
        _ = try expect(.beep)
        // beep [N]
        if current.type == .integer || current.type == .float || current.type == .identifier || current.type == .lparen {
            let count = try parseExpression()
            skipNewlines()
            return .beep(count)
        }
        skipNewlines()
        return .beep(nil)
    }

    private mutating func parseCreateMusicPatternTail() throws -> Statement {
        _ = advance() // pattern
        let name = try parseExpression()
        var instrument: Expression?
        var notes: Expression?
        var tempo: Expression?
        var loop: Expression?
        while current.type != .newline && current.type != .eof {
            if current.type == .with || current.type == .using {
                _ = advance()
                continue
            }
            guard current.type == .identifier else {
                _ = advance()
                continue
            }
            switch current.value.lowercased() {
            case "instrument":
                _ = advance()
                instrument = try parseExpression()
            case "notes", "sequence":
                _ = advance()
                notes = try parseExpression()
            case "tempo":
                _ = advance()
                tempo = try parsePrimary()
            case "loop", "looping":
                _ = advance()
                if current.type != .newline && current.type != .eof {
                    loop = try parsePrimary()
                } else {
                    loop = .literal("true")
                }
            default:
                _ = advance()
            }
        }
        skipNewlines()
        return .createMusicPattern(name: name, instrument: instrument, notes: notes, tempo: tempo, loop: loop)
    }

    private mutating func parseLoopMusicPatternStatement() throws -> Statement {
        _ = advance() // loop
        _ = advance() // pattern
        let name = try parseExpression()
        skipNewlines()
        return .playMusicPattern(name: name, loop: true)
    }

    private mutating func parsePauseMusicStatement() throws -> Statement {
        _ = advance() // pause
        _ = advance() // music
        skipNewlines()
        return .pauseMusic
    }

    private mutating func parseResumeMusicStatement() throws -> Statement {
        _ = advance() // resume
        _ = advance() // music
        skipNewlines()
        return .resumeMusic
    }

    private mutating func parseAuthorizeAppleMusicStatement() throws -> Statement {
        _ = advance() // authorize
        _ = consumeAppleMusicPhrase()
        skipNewlines()
        return .authorizeAppleMusic
    }

    private mutating func parseSearchAppleMusicStatement() throws -> Statement {
        _ = advance() // search
        _ = consumeAppleMusicPhrase()
        var scope = AppleMusicSearchScope.catalog.rawValue
        if current.type == .identifier && current.value.lowercased() == "library" {
            scope = AppleMusicSearchScope.library.rawValue
            _ = advance()
        }
        if current.type == .identifier && current.value.lowercased() == "for" {
            _ = advance()
        }
        let term = try parseExpression()
        var itemType: String?
        var limit: Expression?
        while current.type != .newline && current.type != .eof {
            switch current.value.lowercased() {
            case "type", "kind":
                _ = advance()
                if current.type != .newline && current.type != .eof {
                    itemType = current.value
                    _ = advance()
                }
            case "scope":
                _ = advance()
                if current.type != .newline && current.type != .eof {
                    scope = current.value
                    _ = advance()
                }
            case "limit":
                _ = advance()
                limit = try parsePrimary()
            default:
                _ = advance()
            }
        }
        skipNewlines()
        return .searchAppleMusic(term: term, scope: scope, itemType: itemType, limit: limit)
    }

    private mutating func parseSeekAppleMusicStatement() throws -> Statement {
        _ = advance() // seek / position
        _ = consumeAppleMusicPhrase()
        if current.type == .to || (current.type == .identifier && ["to", "at"].contains(current.value.lowercased())) {
            _ = advance()
        }
        if current.type == .identifier {
            let label = current.value.lowercased()
            if label == "position" || label == "time" || label == "seconds" {
                _ = advance()
            }
        }
        let position = try parseExpression()
        skipNewlines()
        return .seekAppleMusic(position: position)
    }

    private mutating func parsePauseAppleMusicStatement() throws -> Statement {
        _ = advance() // pause
        _ = consumeAppleMusicPhrase()
        skipNewlines()
        return .pauseAppleMusic
    }

    private mutating func parseResumeAppleMusicStatement() throws -> Statement {
        _ = advance() // resume
        _ = consumeAppleMusicPhrase()
        skipNewlines()
        return .resumeAppleMusic
    }

    private mutating func parseWaitStatement() throws -> Statement {
        _ = try expect(.wait)

        if current.type == .identifier && current.value.lowercased() == "for" {
            _ = advance()
        }

        // wait until <condition>
        if current.type == .identifier && current.value.lowercased() == "until" {
            _ = advance()
            let condition = try parseExpression()
            skipNewlines()
            return .waitCondition(condition, mode: .untilTrue)
        }

        // wait while <condition>
        if current.type == .identifier && current.value.lowercased() == "while" {
            _ = advance()
            let condition = try parseExpression()
            skipNewlines()
            return .waitCondition(condition, mode: .whileTrue)
        }

        // wait [for] <duration> [seconds|ticks]
        // HyperCard defaults to ticks when the unit is omitted.
        let duration = try parseExpression()
        var unit: WaitDurationUnit = .ticks
        if isWaitSecondsUnit(current) {
            unit = .seconds
            _ = advance()
        } else if current.type == .identifier {
            let value = current.value.lowercased()
            if value == "ticks" || value == "tick" {
                unit = .ticks
                _ = advance()
            }
        }
        skipNewlines()
        return .waitDuration(duration, unit: unit)
    }

    private func isWaitSecondsUnit(_ token: Token) -> Bool {
        if token.type == .second {
            return true
        }
        guard token.type == .identifier else {
            return false
        }
        let value = token.value.lowercased()
        return value == "seconds" || value == "secs" || value == "sec"
    }

    /// Parse: `animate [the] <property> of <target> to <value> over <duration> [seconds]`
    private mutating func parseAnimateStatement() throws -> Statement {
        _ = try expect(.animate)
        _ = match(.the)  // optional "the"
        let propTok = advance()
        let property = propTok.value
        _ = try expect(.of)
        let target = try parseExpression()
        _ = try expect(.to)
        let toValue = try parseExpression()
        // Expect "over" keyword
        guard current.type == .identifier && current.value.lowercased() == "over" else {
            throw ParseError.unexpected(current, expected: "over")
        }
        _ = advance()
        let duration = try parseExpression()
        // Optional "seconds" / "second" unit
        if current.type == .identifier {
            let unit = current.value.lowercased()
            if unit == "seconds" || unit == "second" {
                _ = advance()
            }
        }
        skipNewlines()
        return .animateProperty(property: property, target: target, toValue: toValue, duration: duration)
    }

    // MARK: - SpriteKit command parsers

    /// Parse `pause scene ["name"]`
    private mutating func parsePauseSceneStatement() throws -> Statement {
        _ = advance() // consume "pause"
        _ = match(.scene) // optional "scene" keyword
        var nameExpr: Expression? = nil
        if current.type != .newline && current.type != .eof {
            nameExpr = try parseExpression()
        }
        skipNewlines()
        return .pauseScene(nameExpr)
    }

    /// Parse `resume scene ["name"]`
    private mutating func parseResumeSceneStatement() throws -> Statement {
        _ = advance() // consume "resume"
        _ = match(.scene) // optional "scene" keyword
        var nameExpr: Expression? = nil
        if current.type != .newline && current.type != .eof {
            nameExpr = try parseExpression()
        }
        skipNewlines()
        return .resumeScene(nameExpr)
    }

    /// Parse `remove sprite "name"`
    private mutating func parseRemoveSpriteStatement() throws -> Statement {
        _ = advance() // consume "remove"
        _ = match(.sprite) // optional "sprite" keyword
        let nameExpr = try parseExpression()
        skipNewlines()
        return .removeSpriteNode(nameExpr)
    }

    /// Parse `apply force "10,20" to sprite "ball"` or `apply impulse "5,0" to sprite "ball"`
    private mutating func parseApplyStatement() throws -> Statement {
        _ = advance() // consume "apply"
        let typeWord = current.value.lowercased()
        _ = advance() // consume "force" or "impulse"
        let value = try parseExpression()
        _ = match(.to) // consume "to"
        _ = match(.sprite) // optional "sprite" keyword
        let node = try parseExpression()
        skipNewlines()
        if typeWord == "force" {
            return .applyForce(node: node, force: value)
        } else {
            return .applyImpulse(node: node, impulse: value)
        }
    }

    /// Parse `fill tilemap "X" with N` — paint every cell of a
    /// tile map with the same tile index. The `fill` keyword is
    /// handled in the identifier-dispatch branch of
    /// `parseStatement` so it only activates when followed by the
    /// `.tilemap` token, keeping `fill` free as an identifier in
    /// other contexts.
    private mutating func parseFillTileMapStatement() throws -> Statement {
        _ = advance() // consume "fill"
        _ = try expect(.tilemap)
        let tilemapExpr = try parseExpression()
        // Accept either `with N` (preferred) or bare `N`.
        if current.type == .with {
            _ = advance()
        }
        let tileIndexExpr = try parseExpression()
        skipNewlines()
        return .fillTileMap(tilemap: tilemapExpr, tileIndex: tileIndexExpr)
    }

    /// Parse `clear tilemap "X"` — sugar for `fill tilemap "X"
    /// with -1`. Same identifier-dispatch gate as `fill`.
    private mutating func parseClearTileMapStatement() throws -> Statement {
        _ = advance() // consume "clear"
        _ = try expect(.tilemap)
        let tilemapExpr = try parseExpression()
        skipNewlines()
        return .clearTileMap(tilemap: tilemapExpr)
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
        if current.type == .await {
            _ = advance()
            let expr = try parseUnary()
            return .await(expr)
        }
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
            if let scopedRef = parseCurrentScopeReference(scopeWord: "this") {
                return scopedRef
            }
            return .this

        case .empty:
            _ = advance()
            return .empty

        case .the:
            return try parseTheExpression()

        case .word, .char, .character, .item, .line:
            // Chunk expressions:
            //   "item 1 of x"           single chunk
            //   "word 2 to 4 of x"      inclusive range chunk
            //   "lines 1 to N of y"     plural keyword + range
            //
            // Plural chunk tokens (items/words/chars/lines) share
            // the same token type as their singular forms thanks to
            // the lexer aliases, so grammar here is identical for
            // both spellings.
            let chunkType = chunkTypeFromToken(current.type)!
            _ = advance()
            let fromExpr = try parsePrimary()
            if current.type == .to {
                _ = advance()  // consume "to"
                let toExpr = try parsePrimary()
                _ = try expect(.of)
                let source = try parsePrimary()
                return .chunk(chunkType, .range(fromExpr, toExpr), source)
            }
            _ = try expect(.of)
            let source = try parsePrimary()
            return .chunk(chunkType, .single(fromExpr), source)

        case .card, .background, .field, .button, .stack, .webpage, .image, .video, .sprite, .spritearea, .scene, .request, .connection, .listener:
            return try parseObjectReference()

        case .identifier where ["label", "shape", "audio", "chart", "calendar", "pdf", "map", "colorwell", "color_well", "stepper", "slider", "segmented", "recorder", "audiorecorder", "musicplayer", "music", "pianokeyboard", "keyboard", "stepsequencer", "sequencer", "musicmixer", "mixer", "applemusicbrowser", "musicbrowser", "musicqueue", "scene3d", "scene3D", "model3d", "model3D", "progressview", "progress", "gauge", "divider"].contains(current.value.lowercased()):
            // Scene node types and HypeTalk part types recognized as
            // object references. Two-word kinds ("color well") aren't
            // tokenized as identifiers so we only accept the
            // single-token form here ("colorwell" or "color_well").
            return try parseObjectReference()

        case .identifier where current.value.lowercased() == "current":
            _ = advance()
            if let scopedRef = parseCurrentScopeReference(scopeWord: "current") {
                return scopedRef
            }
            return .variable("current")

        case .identifier where current.value.lowercased() == "data":
            // Possible compound data-point reference:
            //   data point <ref> [of series <ref>] (of|in) chart <ref>
            //
            // "data" is NOT a lexer keyword — matched by value so
            // existing scripts using "data" as a variable name
            // still work. Only enter the compound-ref path when the
            // next token is the identifier "point"; otherwise treat
            // "data" as a plain variable.
            let nextTok = pos + 1 < tokens.count ? tokens[pos + 1] : Token(type: .eof, value: "", line: 0)
            if nextTok.type == .identifier && nextTok.value.lowercased() == "point" {
                _ = advance()  // data
                _ = advance()  // point
                return try parseChartDataPointRest()
            }
            let tok = advance()
            return .variable(tok.value)

        case .identifier where current.value.lowercased() == "point":
            // Alternative short form of the data-point reference:
            //   point <ref> [of series <ref>] (of|in) chart <ref>
            //
            // Users (including the original bug reporter) reach for
            // `point i of chart "X"` without the leading "data" —
            // accept that as a synonym so the grammar matches the
            // HyperTalk-style sentences people actually write.
            // As with `data`, we only enter this path when followed
            // by an index and a chart clause; lone `point` keeps
            // working as a variable name.
            //
            // Disambiguation: the token after `point` must be a
            // number or a string literal (the point reference). If
            // it's something else, treat `point` as a plain
            // variable.
            let pointNext = pos + 1 < tokens.count ? tokens[pos + 1] : Token(type: .eof, value: "", line: 0)
            let looksLikePointRef = (
                pointNext.type == .integer ||
                pointNext.type == .float ||
                pointNext.type == .string ||
                pointNext.type == .identifier
            )
            if looksLikePointRef {
                _ = advance()  // point
                return try parseChartDataPointRest()
            }
            let pointTok = advance()
            return .variable(pointTok.value)

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
            // HyperTalk-era prefix-function syntax: `random 5`,
            // `abs -5`, `sqrt 16`, `length "hello"` — a unary
            // built-in followed by a single primary-expression
            // argument, no parens required. This is what users
            // (and LLMs trained on HyperTalk docs) naturally reach
            // for. We keep the match narrow: only names in a known
            // unary-builtins set, and only when the next token can
            // start a primary expression (number, string, paren,
            // the, me, it, this, another identifier, chunk/ordinal
            // keyword). That avoids accidentally swallowing normal
            // subsequent tokens like `into`, `then`, `is`, binary
            // operators, or end-of-statement.
            if Self.unaryPrefixBuiltins.contains(tok.value.lowercased()),
               Self.canStartPrimaryExpression(current.type) {
                let arg = try parsePrimary()
                return .functionCall(tok.value, [arg])
            }
            return .variable(tok.value)

        case .first, .second, .third, .last, .middle, .any:
            return try parseOrdinalChunk()

        case .next:
            // "next" used as a value (e.g., "go next")
            let tok = advance()
            return .literal(tok.value)

        case .number:
            // `number of ...` — counts various collections. Beyond
            // the existing support for number-of-cards / buttons /
            // fields / backgrounds, this now also recognises:
            //
            //   the number of points (of|in) chart "X"
            //   the number of data points (of|in) chart "X"
            //
            // which return the data-point count of the chart's
            // first series. These two forms intercept the parser
            // here and produce a dedicated `numberOfPoints`
            // property access whose target is the chart reference,
            // bypassing the generic `parseExpression()` path that
            // would otherwise choke on the `in chart` continuation.
            _ = advance()  // number
            if current.type == .of {
                _ = advance()  // of

                // Try to match `points` or `data points` followed by
                // an `(of|in) chart <ref>` clause.
                let checkpoint = pos
                let matchedPoints: Bool = {
                    // Consume `data` if present so the singular and
                    // `data points` forms both work.
                    if current.type == .identifier && current.value.lowercased() == "data" {
                        _ = advance()
                    }
                    if current.type == .identifier && current.value.lowercased() == "points" {
                        _ = advance()
                        return true
                    }
                    return false
                }()
                if matchedPoints {
                    // Next we need `(of|in) chart <ref>`.
                    let linkOK = (current.type == .of ||
                                  (current.type == .identifier && current.value.lowercased() == "in"))
                    if linkOK {
                        _ = advance()
                        if current.type == .identifier && current.value.lowercased() == "chart" {
                            _ = advance()
                            let chartExpr = try parsePrimary()
                            return .propertyAccess("numberOfPoints", chartExpr)
                        }
                    }
                    // Not the chart form — rewind so the generic
                    // `number of <expr>` branch runs below.
                    pos = checkpoint
                }

                // Chunk counts: `the number of lines in x`,
                // `the number of items of field "list"`, etc.
                if let chunkType = chunkTypeFromToken(current.type) {
                    let cp = pos
                    _ = advance()
                    let linkOK = current.type == .of ||
                        (current.type == .identifier && current.value.lowercased() == "in")
                    if linkOK {
                        _ = advance()
                        let source = try parsePrimary()
                        switch chunkType {
                        case .word: return .propertyAccess("numberOfWords", source)
                        case .char, .character: return .propertyAccess("numberOfChars", source)
                        case .item: return .propertyAccess("numberOfItems", source)
                        case .line: return .propertyAccess("numberOfLines", source)
                        }
                    }
                    pos = cp
                }

                // Compound collection names: `bg fields`, `bg buttons`,
                // `card fields`, `card buttons`. The singular keyword
                // tokens (.background, .card, .field, .button) would
                // otherwise trigger parseObjectReference() and fail, so
                // we intercept them here and emit a literal string that
                // the interpreter's "number" handler recognises.
                if current.type == .background {
                    let cp = pos
                    _ = advance()  // bg / background
                    let next = current.type
                    let nextVal = current.value.lowercased()
                    if next == .field || (next == .identifier && nextVal == "fields") {
                        _ = advance()
                        return .propertyAccess("number", .literal("bg fields"))
                    } else if next == .button || (next == .identifier && nextVal == "buttons") {
                        _ = advance()
                        return .propertyAccess("number", .literal("bg buttons"))
                    }
                    pos = cp  // rewind — not a compound bg form
                }
                if current.type == .card {
                    let cp = pos
                    _ = advance()  // card
                    let next = current.type
                    let nextVal = current.value.lowercased()
                    if next == .field || (next == .identifier && nextVal == "fields") {
                        _ = advance()
                        return .propertyAccess("number", .literal("card fields"))
                    } else if next == .button || (next == .identifier && nextVal == "buttons") {
                        _ = advance()
                        return .propertyAccess("number", .literal("card buttons"))
                    }
                    pos = cp  // rewind — not a compound card form
                }

                // Known collection identifiers must be emitted as
                // literals so the interpreter matches them by name.
                // Without this, `backgrounds` would be parsed as
                // `.variable("backgrounds")` which evaluates to "" (an
                // undefined variable), breaking the number-of lookup.
                if current.type == .identifier {
                    switch current.value.lowercased() {
                    case "cards", "backgrounds", "buttons", "fields",
                         "parts", "windows", "menus", "marked":
                        let tok = advance()
                        return .propertyAccess("number", .literal(tok.value))
                    default: break
                    }
                }

                // Use parsePrimary() — NOT parseExpression() — so that
                // operators like `div` bind to the *result* of the
                // property access instead of being swallowed as part of
                // the target. E.g. `the number of cards div 2` parses
                // as `(the number of cards) div 2`.
                let expr = try parsePrimary()
                return .propertyAccess("number", expr)
            }
            return .variable("number")

        case .down:
            let tok = advance()
            return .literal(tok.value)

        case .return:
            let tok = advance()
            return .variable(tok.value)

        case .from, .by, .times,
             .choose, .close, .save, .quit, .mark, .unmark, .push, .pop,
             .click, .drag, .run, .print, .help, .debug, .reset,
             .export, .import, .copy, .disable, .enable, .edit, .dial,
             .reply, .start, .stop, .using, .template, .paint,
             .report, .file, .printing, .convert, .typeText,
             .emitter, .action, .joint, .constrain, .listen, .http,
             .tcp, .message, .method, .headers, .body, .username,
             .password, .host, .port, .status, .tls, .connect, .send:
            // These keywords can appear as identifiers in some contexts.
            let tok = advance()
            return .literal(tok.value)

        case .ask:
            // Expression form: `ask meshy "<prompt>" [with style <s>]`
            //
            // Recognized ONLY when `.ask` is immediately followed by `.meshy`
            // (both tokens must be present). The sync-only expression form
            // omits the `with message` callback clause — async generation
            // stays in the statement form. If the next token is NOT `.meshy`,
            // the `.ask` token is treated as an unresolvable keyword and a
            // parse error is thrown so the caller can surface it cleanly.
            if pos + 1 < tokens.count && tokens[pos + 1].type == .meshy {
                _ = advance()  // ask
                _ = advance()  // meshy
                let prompt = try parseExpression()
                var style: Expression? = nil
                if current.type == .with || current.type == .using {
                    let savedPos = pos
                    _ = advance()  // with / using
                    if current.type == .identifier && current.value.lowercased() == "style" {
                        _ = advance()
                        style = try parseExpression()
                    } else {
                        // Not a `with style` clause — rewind so the caller
                        // sees the `with` token and can handle it (e.g. the
                        // outer put/get statement may have its own `with`).
                        pos = savedPos
                    }
                }
                return .askMeshy(prompt: prompt, style: style)
            }
            throw ParseError.unexpected(current, expected: "expression")

        default:
            throw ParseError.unexpected(current, expected: "expression")
        }
    }

    private mutating func parseTheExpression() throws -> Expression {
        _ = try expect(.the)

        // HyperTalk idiom: several expression forms may be preceded
        // by an optional article `the`. Previously this function
        // swallowed whatever token came next as a property name,
        // which broke:
        //
        //   the item 1 of "a,b,c"          (chunk expression)
        //   the items 2 to 4 of X          (chunk range)
        //   the first word of "hello w"    (ordinal chunk)
        //   the number of cards            (number-of-X)
        //   the number of points in chart "X"
        //
        // because tokens like `.item` and `.number` got consumed as
        // property names and the chunk/ordinal/number-of-X parser
        // branches (which live in parsePrimary) were never reached.
        //
        // Fix: when the token after `the` is one of the special
        // forms that parsePrimary already knows how to parse, just
        // delegate back to parsePrimary. The `the` article is
        // syntactic sugar — parsePrimary's chunk/ordinal/number
        // branches produce the same AST either way.
        //
        switch current.type {
        case .word, .char, .character, .item, .line, .number,
             .first, .second, .third, .last, .middle, .any:
            return try parsePrimary()
        default:
            break
        }

        // `the short time`, `the abbrev time`, `the long time`,
        // `the English time`. Keep the adjective attached to the
        // global property so the interpreter can choose the right
        // formatter.
        if current.type == .identifier,
           isTimeAdjective(current.value),
           pos + 1 < tokens.count,
           tokens[pos + 1].type == .identifier,
           tokens[pos + 1].value.lowercased() == "time" {
            let adjective = advance().value
            _ = advance() // time
            return .propertyAccess("\(adjective) time", nil)
        }

        // `the tile at <col>,<row> of tilemap "X"` — read a single
        // cell from a tile map. We intercept the `.tile` token here
        // so it isn't mistaken for a generic property name, and so
        // the `at` + comma + `of tilemap` scaffolding has somewhere
        // structured to live. `at` is a plain identifier (not a
        // reserved token type) so we gate on the identifier value.
        if current.type == .tile {
            _ = advance()  // tile
            // Accept either `at col,row` or bare `col,row`; the
            // `at` word is ergonomic but optional.
            if current.type == .identifier && current.value.lowercased() == "at" {
                _ = advance()
            }
            let colExpr = try parsePrimary()
            _ = try expect(.comma)
            let rowExpr = try parsePrimary()
            _ = try expect(.of)
            _ = match(.tilemap)
            let tilemapExpr = try parsePrimary()
            return .tileAt(column: colExpr, row: rowExpr, tilemap: tilemapExpr)
        }

        if current.type == .identifier && current.value.lowercased() == "header" {
            _ = advance()
            let headerName = try parseExpression()
            _ = try expect(.of)
            let target = try parsePrimary()
            return .headerAccess(headerName, target)
        }

        let propTok = advance()
        let property = propTok.value

        // `the <property> of <expr>`
        if current.type == .of {
            _ = advance()
            // Pass through `of physicsBody of <ref>` as a synonym for
            // `of <ref>` — AI-generated HypeTalk often reaches for
            // this chain because it mirrors SpriteKit's Swift API
            // shape. See `skipTransparentOfChain` in
            // `parseSetStatement` for the full rationale.
            skipTransparentOfChain()
            // Use parsePrimary so we don't consume comparison operators (is, =, etc.)
            // e.g. `the hilite of me is "true"` → target is `me`, not `me is "true"`
            let target = try parsePrimary()
            return .propertyAccess(property, target)
        }

        // `the <property>` (global property like `the date`, `the time`)
        return .propertyAccess(property, nil)
    }

    private func isTimeAdjective(_ value: String) -> Bool {
        switch value.lowercased() {
        case "short", "abbrev", "abbreviated", "abbr", "long", "english":
            return true
        default:
            return false
        }
    }

    private mutating func parseObjectReference() throws -> Expression {
        let typeTok = advance()
        let objType = typeTok.value.lowercased()
        // `stack` is a singleton — there's only one per document,
        // so it doesn't take an identifier after it (unlike
        // `card "Card 1"` or `button "OK"`). Trying to parse one
        // would consume the next real token (e.g. `into`) and throw.
        if objType == "stack" {
            return .objectRef(ObjectRefExpr(objectType: "stack", identifier: .literal("stack")))
        }
        let ident = try parsePrimary()
        return .objectRef(ObjectRefExpr(objectType: objType, identifier: ident))
    }

    private mutating func parseCurrentScopeReference(scopeWord: String) -> Expression? {
        switch current.type {
        case .card:
            _ = advance()
            return .objectRef(ObjectRefExpr(objectType: "card", identifier: .literal(scopeWord)))
        case .background:
            _ = advance()
            return .objectRef(ObjectRefExpr(objectType: "background", identifier: .literal(scopeWord)))
        case .stack:
            _ = advance()
            return .objectRef(ObjectRefExpr(objectType: "stack", identifier: .literal("stack")))
        default:
            return nil
        }
    }

    /// Parse the remainder of a compound data-point reference after
    /// `data point` / `point` has already been consumed.
    ///
    /// Grammar:
    ///
    ///     [data] point <pointRef> [(of|in) series <seriesRef>] (of|in) chart <chartRef>
    ///
    /// `<pointRef>` / `<seriesRef>` / `<chartRef>` are primary
    /// expressions — typically a number literal (1-based index) or
    /// a string literal (name). The `(of|in) series <...>` clause
    /// is optional; when omitted we default to series 1 so
    /// single-series charts read naturally
    /// (`the color of point 3 of chart "Sales"`).
    ///
    /// Both `of` and `in` are accepted as the link preposition so
    /// users can write `point 1 in chart "Sales"` or `point 1 of
    /// chart "Sales"` interchangeably — HyperTalk-era scripts used
    /// both.
    private mutating func parseChartDataPointRest() throws -> Expression {
        let pointExpr = try parsePrimary()

        // Require either `of` (a reserved keyword) or the identifier
        // `in` as the preposition that links the point to its
        // container.
        try expectOfOrIn()

        var seriesExpr: Expression = .literal("1")
        if current.type == .identifier && current.value.lowercased() == "series" {
            _ = advance()  // series
            seriesExpr = try parsePrimary()
            try expectOfOrIn()
        }

        // Expect the word "chart" next. It may arrive either as the
        // .identifier "chart" or (if ever promoted to a keyword) as
        // its own token type — check both.
        if current.type == .identifier && current.value.lowercased() == "chart" {
            _ = advance()
        } else {
            throw ParseError.unexpected(current, expected: "chart")
        }
        let chartExpr = try parsePrimary()

        return .chartDataPointRef(chart: chartExpr, series: seriesExpr, point: pointExpr)
    }

    /// Consume either an `.of` token or the identifier `in`, or
    /// throw a parse error mentioning both as valid. Used by the
    /// data-point reference parser where users reach for either
    /// preposition interchangeably.
    private mutating func expectOfOrIn() throws {
        if current.type == .of {
            _ = advance()
            return
        }
        if current.type == .identifier && current.value.lowercased() == "in" {
            _ = advance()
            return
        }
        throw ParseError.unexpected(current, expected: "of or in")
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

    /// HyperTalk-era unary built-in functions that accept prefix
    /// syntax (`abs -5`, `sqrt 16`, `random 10`) in addition to the
    /// paren-call form (`abs(-5)`, `sqrt(16)`, `random(10)`).
    ///
    /// Any name in this set, when it appears as an identifier
    /// followed immediately by something that can start a primary
    /// expression, is parsed as a single-argument function call.
    /// Names lookup is lowercased for case-insensitive matching.
    private static let unaryPrefixBuiltins: Set<String> = [
        "random", "abs", "round", "trunc", "sqrt",
        "sin", "cos", "tan", "atan", "exp", "ln", "log2",
        "chartonum", "numtochar", "length", "value", "ollama", "param",
    ]

    /// Can the given token type start a *primary* expression?
    ///
    /// Used by the prefix-function heuristic to decide whether to
    /// consume the next token as a unary built-in's argument.
    /// Intentionally excludes:
    ///
    /// - binary operators (`+`, `-`, `*`, `/`, `mod`, etc.) — those
    ///   bind tighter than prefix-function calls, so `abs - 5`
    ///   should parse as `(abs) - 5` not `abs(-5)`. Users who want
    ///   negative arguments can write `abs(-5)` explicitly.
    /// - statement terminators (`newline`, `eof`) and connectives
    ///   (`into`, `to`, `then`, `is`, `of`, `end`, `else`, etc.)
    ///
    /// If we return `false` the identifier falls through to the
    /// variable-reference case, preserving every existing script
    /// that uses these names as variables or method targets.
    private static func canStartPrimaryExpression(_ type: TokenType) -> Bool {
        switch type {
        case .integer, .float, .string, .identifier, .lparen,
             .the, .it, .me, .this, .empty, .await,
             .word, .char, .character, .item, .line, .number,
             .first, .second, .third, .last, .middle, .any,
             .not,
             .card, .background, .field, .button, .stack, .webpage,
             .sprite, .spritearea, .request, .connection, .listener:
            return true
        default:
            return false
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

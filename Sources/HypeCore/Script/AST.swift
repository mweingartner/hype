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
    case await(Expression)
    case functionCall(String, [Expression])
    case propertyAccess(String, Expression?)     // "the name of card 1"
    case headerAccess(Expression, Expression)    // the header "X" of request id
    case chunk(ChunkType, ChunkRange, Expression) // "word 3 of field 1"
    case objectRef(ObjectRefExpr)
    case scopedObjectRef(object: ObjectRefExpr, owner: ObjectRefExpr) // field "X" of card "Y"
    /// A nested reference to a single data point inside a chart's series.
    ///
    /// Produced by the grammar `data point <ref> [of series <ref>] of chart <ref>`
    /// and used exclusively as the `of` target of a `propertyAccess` or a
    /// `set` statement. The three sub-expressions each resolve to a string
    /// at runtime: the chart name or 1-based index, the series name or
    /// 1-based index (defaults to `"1"` when the grammar omits `of series`),
    /// and the data point name or 1-based index. The interpreter locates
    /// the target `ChartDataPoint` inside `Part.chartData`'s encoded
    /// `ChartConfig` on each access, so reads and writes always see the
    /// live value.
    case chartDataPointRef(chart: Expression, series: Expression, point: Expression)
    /// Read a tile index from a tile map at a given column/row.
    ///
    /// Produced by the grammar `the tile at <col>,<row> of tilemap "X"`.
    /// The interpreter resolves the sprite area + tile map node on the
    /// current card, reads the indexed cell from `TileMapSpec.tileData`,
    /// and returns the tile index as a string. Returns `"-1"` when the
    /// cell is out of bounds or empty — callers can treat that as the
    /// "no tile" sentinel. Used both for game-logic introspection
    /// (`if the tile at 5,3 of tilemap "map" is 7 then ...`) and for
    /// debugging tilemap contents at runtime.
    case tileAt(column: Expression, row: Expression, tilemap: Expression)
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
    /// `ask meshy "<prompt>" [with style <s>]` used as an expression.
    ///
    /// Synchronous-only expression form — no `with message` callback.
    /// Evaluates to the new asset name on success, `""` on gate refusal or
    /// error (same degradation contract as the statement form).
    case askMeshy(prompt: Expression, style: Expression?)
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

/// Units accepted by HyperTalk's `wait` command.
public enum WaitDurationUnit: Sendable {
    case ticks
    case seconds
}

/// Conditional forms accepted by HyperTalk's `wait` command.
public enum WaitConditionMode: Sendable {
    case untilTrue
    case whileTrue
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
    case goInStack(card: Expression, stack: Expression)
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
    case ask(prompt: Expression, defaultResponse: Expression?)
    case askAI(prompt: Expression, model: Expression?, callback: Expression?)
    /// `ask meshy "<prompt>" [with style <s>] [with model <m>] [with message <msg>]`
    ///
    /// All three modifiers are optional and may appear in any order.
    /// The `style` resolves to `MeshyArtStyle` at evaluation time (default `.realistic`).
    /// The `model` resolves to `MeshyAIModel` at evaluation time (default `.meshy6`).
    case askMeshy(
        prompt: Expression,
        style: Expression?,
        model: Expression?,
        callback: Expression?
    )
    /// `remesh asset "<name>" to <polycount> [with message <msg>]`
    ///
    /// Remesh an existing Meshy-generated model3D asset to a new polycount.
    /// Synchronous form sets `it` + `the result` to the new asset name.
    /// Async form (with message) sets `it` to the request UUID.
    case remeshAsset(
        sourceName: Expression,
        targetPolycount: Expression,
        callback: Expression?
    )

    /// `retexture asset "<name>" with prompt "<text>" [with message <msg>]`
    ///
    /// Apply a new texture to an existing Meshy-generated model3D asset.
    /// Same sync/async contract as `remeshAsset`.
    case retextureAsset(
        sourceName: Expression,
        stylePrompt: Expression,
        callback: Expression?
    )

    case answer(prompt: Expression, buttons: [Expression])
    case say(Expression)
    case activateListener(Expression)
    case visual(effectName: Expression, duration: Expression?)
    case send(message: Expression, target: Expression?)
    case expressionStatement(Expression)
    case doBlock(Expression)
    // Animation
    case animateProperty(property: String, target: Expression, toValue: Expression, duration: Expression)

    // Sound commands
    case playSound(sound: Expression, notes: Expression?, tempo: Expression?)
    case playStop
    case createMusicPattern(name: Expression, instrument: Expression?, notes: Expression?, tempo: Expression?, loop: Expression?)
    case playMusicPattern(name: Expression, loop: Bool)
    case stopMusic
    case pauseMusic
    case resumeMusic
    case exportMusicPattern(name: Expression, assetName: Expression)
    case authorizeAppleMusic
    case searchAppleMusic(term: Expression, scope: String, itemType: String?, limit: Expression?)
    case playAppleMusic(source: String, itemType: String, id: Expression)
    case seekAppleMusic(position: Expression)
    case pauseAppleMusic
    case resumeAppleMusic
    case stopAppleMusic
    case beep(Expression?)
    // Wait commands
    case waitDuration(Expression, unit: WaitDurationUnit)
    case waitCondition(Expression, mode: WaitConditionMode)
    case createCard(backgroundName: Expression?)  // "create a new card [with background "name"]"
    case createBackground(name: Expression)        // "create background "name""
    case createButton(name: Expression, onBackground: Bool)  // "create button "name" [on background]"
    case createField(name: Expression, onBackground: Bool)   // "create field "name" [on background]"
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
    case externalCommand(name: String, arguments: [Expression])  // XCMD-style unknown command call

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

    // SpriteKit commands
    case createSprite(name: Expression, scene: Expression?, asset: Expression?)
    case createGroup(name: Expression, parent: Expression?)
    case createShape(name: Expression, scene: Expression?, shapeType: Expression?)
    case createSpriteScene(name: Expression, inArea: Expression?, width: Expression?, height: Expression?)
    case createSpriteArea(name: Expression, rect: Expression?)
    case setSpriteNodeProperty(property: String, node: Expression, value: Expression)
    case runSpriteAction(action: Expression, node: Expression)
    case removeSpriteNode(Expression)
    case pauseScene(Expression?)
    case resumeScene(Expression?)
    case createTileMap(name: Expression, columns: Expression?, rows: Expression?, tileSize: Expression?, tileset: Expression?)
    case createCamera(name: Expression)
    case createJoint(name: Expression, type: Expression, nodeA: Expression, nodeB: Expression)
    case createConstraint(type: Expression, source: Expression, target: Expression, min: Expression?, max: Expression?)
    case createPhysicsField(name: Expression, type: Expression, strength: Expression?, direction: Expression?)
    case openScene(name: Expression, transition: Expression?, duration: Expression?)
    case setTile(column: Expression, row: Expression, tilemap: Expression, tileIndex: Expression)
    /// Fill every cell of the named tile map with the given tile
    /// index. Grammar: `fill tilemap "X" with N`. An `N` of -1 clears
    /// the tile map. Used for painting base layers before stamping
    /// obstacles with `set tile col,row of tilemap "X" to N`.
    case fillTileMap(tilemap: Expression, tileIndex: Expression)
    /// Clear every cell of the named tile map. Grammar: `clear
    /// tilemap "X"`. Equivalent to `fill tilemap "X" with -1`.
    case clearTileMap(tilemap: Expression)
    case applyForce(node: Expression, force: Expression)      // apply force 10,20 to sprite "ball"
    case applyImpulse(node: Expression, impulse: Expression)  // apply impulse 5,0 to sprite "ball"

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
    case replyRequest(request: Expression, status: Expression, headers: Expression?, body: Expression?)
    case requestURL(url: Expression, method: Expression?, headers: Expression?, body: Expression?, username: Expression?, password: Expression?, callback: Expression?)
    case listenHTTP(port: Expression, host: Expression?, method: Expression?, path: Expression?, callback: Expression)
    case listenTCP(port: Expression, host: Expression?, callback: Expression)
    case connectTCP(host: Expression, port: Expression, tls: Expression?, callback: Expression)
    case sendToConnection(data: Expression, connection: Expression)
    case closeConnection(Expression)
    case stopListener(Expression)
    case runCmd(Expression)                                      // run
    case startUsing(Expression)                                  // start using stack
    case stopUsing(Expression)                                   // stop using stack
    case startAnimation(Expression)                              // start the animation of image "foo"
    case stopAnimation(Expression)                               // stop the animation of image "foo"
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

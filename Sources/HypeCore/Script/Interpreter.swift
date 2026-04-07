import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// HypeTalk values are all strings, coerced to numbers for arithmetic.
public typealias Value = String

/// Context for script execution.
public struct ExecutionContext: Sendable {
    public var targetId: UUID
    public var currentCardId: UUID
    public var document: HypeDocument
    public var instructionLimit: Int

    public init(targetId: UUID, currentCardId: UUID, document: HypeDocument, instructionLimit: Int = 1_000_000) {
        self.targetId = targetId
        self.currentCardId = currentCardId
        self.document = document
        self.instructionLimit = instructionLimit
    }
}

/// The result of executing a handler.
public struct ExecutionResult: Sendable {
    public var status: ExecutionStatus
    public var returnValue: Value?
    public var modifiedDocument: HypeDocument?
    public var error: ScriptError?
    public var navigationTarget: UUID?
    public var showAllCards: Bool

    public init(
        status: ExecutionStatus,
        returnValue: Value? = nil,
        modifiedDocument: HypeDocument? = nil,
        error: ScriptError? = nil,
        navigationTarget: UUID? = nil,
        showAllCards: Bool = false
    ) {
        self.status = status
        self.returnValue = returnValue
        self.modifiedDocument = modifiedDocument
        self.error = error
        self.navigationTarget = navigationTarget
        self.showAllCards = showAllCards
    }
}

/// Execution outcome.
public enum ExecutionStatus: Sendable {
    case completed, passed, error
}

/// A runtime script error.
public struct ScriptError: Error, Sendable {
    public var message: String
    public var line: Int
    public var handler: String

    public init(message: String, line: Int, handler: String) {
        self.message = message
        self.line = line
        self.handler = handler
    }
}

// MARK: - Environment

/// Mutable variable environment for script execution.
private struct Environment {
    var locals: [String: Value] = [:]
    var globals: [String: Value]
    var it: Value = ""
    var globalNames: Set<String> = []

    mutating func getVariable(_ name: String) -> Value {
        let key = name.lowercased()
        if globalNames.contains(key) {
            return globals[key] ?? ""
        }
        return locals[key] ?? ""
    }

    mutating func setVariable(_ name: String, _ value: Value) {
        let key = name.lowercased()
        if globalNames.contains(key) {
            globals[key] = value
        } else {
            locals[key] = value
        }
    }
}

// MARK: - Control flow signals

/// Signals used for control flow during interpretation.
private enum ControlSignal: Error {
    case exitRepeat
    case nextRepeat
    case exitHandler(Value?)
    case passMessage(String)
    case showAllCards
}

// MARK: - Interpreter

/// Tree-walking interpreter for HypeTalk scripts.
public struct Interpreter: Sendable {

    public init() {}

    /// Execute a handler with the given parameters and context.
    public func execute(handler: Handler, params: [Value], context: ExecutionContext) -> ExecutionResult {
        var env = Environment(globals: [:])
        var instructionCount = 0
        var document = context.document
        var navigationTarget: UUID? = nil

        // Bind parameters.
        for (i, paramName) in handler.params.enumerated() {
            let value = i < params.count ? params[i] : ""
            env.locals[paramName.lowercased()] = value
        }

        do {
            for stmt in handler.body {
                try executeStatement(stmt, env: &env, document: &document,
                                     context: context, instructionCount: &instructionCount,
                                     navigationTarget: &navigationTarget, handler: handler)
            }
        } catch ControlSignal.passMessage {
            return ExecutionResult(status: .passed, modifiedDocument: document)
        } catch ControlSignal.exitHandler(let returnVal) {
            return ExecutionResult(status: .completed, returnValue: returnVal,
                                   modifiedDocument: document, navigationTarget: navigationTarget)
        } catch ControlSignal.showAllCards {
            return ExecutionResult(status: .completed, modifiedDocument: document, showAllCards: true)
        } catch let error as ScriptError {
            return ExecutionResult(status: .error, error: error)
        } catch {
            let scriptError = ScriptError(message: error.localizedDescription, line: handler.line, handler: handler.name)
            return ExecutionResult(status: .error, error: scriptError)
        }

        return ExecutionResult(status: .completed, returnValue: env.it,
                               modifiedDocument: document, navigationTarget: navigationTarget)
    }

    // MARK: - Statement execution

    private func executeStatement(
        _ stmt: Statement,
        env: inout Environment,
        document: inout HypeDocument,
        context: ExecutionContext,
        instructionCount: inout Int,
        navigationTarget: inout UUID?,
        handler: Handler
    ) throws {
        instructionCount += 1
        if instructionCount > context.instructionLimit {
            throw ScriptError(message: "Instruction limit exceeded", line: handler.line, handler: handler.name)
        }

        switch stmt {
        case .put(let source, let prep, let target):
            let value = try evaluate(source, env: &env, document: document, context: context)
            switch target {
            case .variable(let name):
                switch prep {
                case .into:
                    env.setVariable(name, value)
                case .after:
                    let existing = env.getVariable(name)
                    env.setVariable(name, existing + value)
                case .before:
                    let existing = env.getVariable(name)
                    env.setVariable(name, value + existing)
                }
            case .it:
                switch prep {
                case .into:  env.it = value
                case .after: env.it = env.it + value
                case .before: env.it = value + env.it
                }
            case .objectRef(let ref):
                // Put into a field or button by name/number
                let ident = try evaluate(ref.identifier, env: &env, document: document, context: context)
                if let partIndex = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    switch prep {
                    case .into:
                        document.parts[partIndex].textContent = value
                    case .after:
                        document.parts[partIndex].textContent += value
                    case .before:
                        document.parts[partIndex].textContent = value + document.parts[partIndex].textContent
                    }
                }
                env.it = value

            default:
                // Unknown target — store in `it`
                env.it = value
            }

        case .get(let expr):
            env.it = try evaluate(expr, env: &env, document: document, context: context)

        case .set(let property, let target, let toExpr):
            let value = try evaluate(toExpr, env: &env, document: document, context: context)
            if let targetExpr = target {
                // Try to resolve target as an object reference
                if case .objectRef(let ref) = targetExpr {
                    let ident = try evaluate(ref.identifier, env: &env, document: document, context: context)
                    if let partIndex = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                        // Set the property on the part
                        switch property.lowercased() {
                        case "url":
                            document.parts[partIndex].url = value
                        case "name":
                            document.parts[partIndex].name = value
                        case "textcontent", "text":
                            document.parts[partIndex].textContent = value
                        case "visible":
                            document.parts[partIndex].visible = isTruthy(value)
                        case "enabled":
                            document.parts[partIndex].enabled = isTruthy(value)
                        case "textalign":
                            document.parts[partIndex].textAlign = TextAlignment(rawValue: value.lowercased()) ?? .left
                        case "textfont", "font":
                            document.parts[partIndex].textFont = value
                        case "textsize", "size":
                            document.parts[partIndex].textSize = toNumber(value)
                        case "fillcolor":
                            document.parts[partIndex].fillColor = value
                        case "strokecolor":
                            document.parts[partIndex].strokeColor = value
                        case "left", "left_pos":
                            document.parts[partIndex].left = toNumber(value)
                        case "top", "top_pos":
                            document.parts[partIndex].top = toNumber(value)
                        case "width":
                            document.parts[partIndex].width = toNumber(value)
                        case "height":
                            document.parts[partIndex].height = toNumber(value)
                        case "hilite":
                            document.parts[partIndex].hilite = isTruthy(value)
                        case "autohilite":
                            document.parts[partIndex].autoHilite = isTruthy(value)
                        case "showname":
                            document.parts[partIndex].showName = isTruthy(value)
                        case "locktext":
                            document.parts[partIndex].lockText = isTruthy(value)
                        case "dontwrap":
                            document.parts[partIndex].dontWrap = isTruthy(value)
                        case "widemargins":
                            document.parts[partIndex].wideMargins = isTruthy(value)
                        case "style":
                            if document.parts[partIndex].partType == .button {
                                document.parts[partIndex].buttonStyle = ButtonStyle(rawValue: value) ?? .roundRect
                            } else if document.parts[partIndex].partType == .field {
                                document.parts[partIndex].fieldStyle = FieldStyle(rawValue: value) ?? .rectangle
                            }
                        case "script":
                            document.parts[partIndex].script = value
                        case "family":
                            document.parts[partIndex].family = Int(toNumber(value))
                        case "textstyle":
                            document.parts[partIndex].textStyle = value
                        case "rect", "rectangle":
                            let components = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                            if components.count == 4 {
                                document.parts[partIndex].left = components[0]
                                document.parts[partIndex].top = components[1]
                                document.parts[partIndex].width = components[2] - components[0]
                                document.parts[partIndex].height = components[3] - components[1]
                            }
                        case "loc", "location":
                            let components = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                            if components.count == 2 {
                                document.parts[partIndex].left = components[0] - document.parts[partIndex].width / 2
                                document.parts[partIndex].top = components[1] - document.parts[partIndex].height / 2
                            }
                        case "marked":
                            if let idx = document.cards.firstIndex(where: { $0.id == context.currentCardId }) {
                                document.cards[idx].marked = isTruthy(value)
                            }
                        case "right":
                            let newRight = toNumber(value)
                            document.parts[partIndex].width = newRight - document.parts[partIndex].left
                        case "bottom":
                            let newBottom = toNumber(value)
                            document.parts[partIndex].height = newBottom - document.parts[partIndex].top
                        case "topleft":
                            let components = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                            if components.count >= 2 {
                                document.parts[partIndex].left = components[0]
                                document.parts[partIndex].top = components[1]
                            }
                        case "bottomright":
                            let components = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                            if components.count >= 2 {
                                document.parts[partIndex].width = components[0] - document.parts[partIndex].left
                                document.parts[partIndex].height = components[1] - document.parts[partIndex].top
                            }
                        case "icon":
                            if let uuid = UUID(uuidString: value) {
                                document.parts[partIndex].iconId = uuid
                            }
                        case "scroll", "scrollpos":
                            break  // Would need scroll position tracking
                        case "sharedtext":
                            break  // Would need shared text model field
                        case "sharedhilite":
                            break  // Would need shared hilite model field
                        case "showlines":
                            break  // Would need field property
                        case "showpict":
                            break  // Would need show picture property
                        case "fixedlineheight":
                            break  // Would need model property
                        case "multiplelines":
                            break  // Would need model property
                        case "dontsearch":
                            break  // Would need model property
                        case "autoselect":
                            break  // Would need model property
                        case "autotab":
                            break  // Would need model property
                        case "textheight":
                            document.parts[partIndex].textSize = toNumber(value) / 1.3
                        case "cantdelete":
                            break  // Would need model property
                        case "cantmodify":
                            break  // Would need model property
                        case "centered":
                            document.parts[partIndex].textAlign = isTruthy(value) ? .center : .left
                        case "fill_color":
                            document.parts[partIndex].fillColor = value
                        case "stroke_color":
                            document.parts[partIndex].strokeColor = value
                        case "strokewidth", "stroke_width":
                            document.parts[partIndex].strokeWidth = toNumber(value)
                        case "cornerradius", "corner_radius":
                            document.parts[partIndex].cornerRadius = toNumber(value)
                        case "shapetype", "shape_type":
                            if let st = ShapeType(rawValue: value) {
                                document.parts[partIndex].shapeType = st
                            }
                        case "richtext", "rich_text":
                            document.parts[partIndex].richText = isTruthy(value)
                        case "enterkeyenabled":
                            document.parts[partIndex].enterKeyEnabled = isTruthy(value)
                        case "invertonclick":
                            document.parts[partIndex].invertOnClick = isTruthy(value)
                        default:
                            env.setVariable(property, value)
                        }
                    } else {
                        env.setVariable(property, value)
                    }
                } else {
                    env.setVariable(property, value)
                }
            } else {
                env.setVariable(property, value)
            }

        case .go(let dest):
            let destValue = try evaluate(dest, env: &env, document: document, context: context)
            // Try to resolve destination to a card UUID.
            if let uuid = UUID(uuidString: destValue) {
                navigationTarget = uuid
            } else {
                // Try to find by name or navigation keyword.
                let resolved = resolveNavigation(destValue, document: document, currentCardId: context.currentCardId)
                navigationTarget = resolved
            }

        case .ifThenElse(let cond, let thenBlock, let elseBlock):
            let condValue = try evaluate(cond, env: &env, document: document, context: context)
            if isTruthy(condValue) {
                for s in thenBlock {
                    try executeStatement(s, env: &env, document: &document, context: context,
                                         instructionCount: &instructionCount,
                                         navigationTarget: &navigationTarget, handler: handler)
                }
            } else if let elseStmts = elseBlock {
                for s in elseStmts {
                    try executeStatement(s, env: &env, document: &document, context: context,
                                         instructionCount: &instructionCount,
                                         navigationTarget: &navigationTarget, handler: handler)
                }
            }

        case .repeatCount(let countExpr, let body):
            let countStr = try evaluate(countExpr, env: &env, document: document, context: context)
            let count = Int(toNumber(countStr))
            for _ in 0..<max(0, count) {
                do {
                    for s in body {
                        try executeStatement(s, env: &env, document: &document, context: context,
                                             instructionCount: &instructionCount,
                                             navigationTarget: &navigationTarget, handler: handler)
                    }
                } catch ControlSignal.exitRepeat {
                    break
                } catch ControlSignal.nextRepeat {
                    continue
                }
            }

        case .repeatWhile(let cond, let body):
            while true {
                let condValue = try evaluate(cond, env: &env, document: document, context: context)
                if !isTruthy(condValue) { break }
                do {
                    for s in body {
                        try executeStatement(s, env: &env, document: &document, context: context,
                                             instructionCount: &instructionCount,
                                             navigationTarget: &navigationTarget, handler: handler)
                    }
                } catch ControlSignal.exitRepeat {
                    break
                } catch ControlSignal.nextRepeat {
                    continue
                }
            }

        case .repeatWith(let varName, let fromExpr, let toExpr, let body):
            let fromVal = Int(toNumber(try evaluate(fromExpr, env: &env, document: document, context: context)))
            let toVal = Int(toNumber(try evaluate(toExpr, env: &env, document: document, context: context)))
            let step = fromVal <= toVal ? 1 : -1
            var i = fromVal
            while (step > 0 && i <= toVal) || (step < 0 && i >= toVal) {
                env.setVariable(varName, String(i))
                do {
                    for s in body {
                        try executeStatement(s, env: &env, document: &document, context: context,
                                             instructionCount: &instructionCount,
                                             navigationTarget: &navigationTarget, handler: handler)
                    }
                } catch ControlSignal.exitRepeat {
                    break
                } catch ControlSignal.nextRepeat {
                    // fall through to increment
                }
                i += step
            }

        case .exitRepeat:
            throw ControlSignal.exitRepeat

        case .nextRepeat:
            throw ControlSignal.nextRepeat

        case .passMessage:
            throw ControlSignal.passMessage(handler.name)

        case .exitHandler:
            throw ControlSignal.exitHandler(nil)

        case .returnValue(let expr):
            let value = try evaluate(expr, env: &env, document: document, context: context)
            throw ControlSignal.exitHandler(value)

        case .globalDecl(let names):
            for name in names {
                env.globalNames.insert(name.lowercased())
            }

        case .ask(let prompt):
            let value = try evaluate(prompt, env: &env, document: document, context: context)
            env.it = value // In a real implementation, this would show a dialog.

        case .answer(let prompt):
            let value = try evaluate(prompt, env: &env, document: document, context: context)
            env.it = value // In a real implementation, this would show a dialog.

        case .visual(let effectExpr):
            // Visual effects are a presentation concern — record but do not act.
            _ = try evaluate(effectExpr, env: &env, document: document, context: context)

        case .expressionStatement(let expr):
            _ = try evaluate(expr, env: &env, document: document, context: context)

        case .doBlock(let expr):
            let scriptText = try evaluate(expr, env: &env, document: document, context: context)
            // Simplified: parse and execute inline. Not fully implemented.
            _ = scriptText

        case .createCard(let bgNameExpr):
            var bgName: String? = nil
            if let expr = bgNameExpr {
                bgName = try evaluate(expr, env: &env, document: document, context: context)
            }
            let newCard = document.addCard(
                afterIndex: document.sortedCards.firstIndex(where: { $0.id == context.currentCardId }),
                backgroundName: bgName
            )
            navigationTarget = newCard.id

        case .createBackground(let nameExpr):
            let name = try evaluate(nameExpr, env: &env, document: document, context: context)
            let _ = document.addBackground(name: name)

        case .showAllCards:
            // Signal the UI to cycle through all cards with animation.
            // The actual cycling is handled by the UI layer since it requires timed delays.
            throw ControlSignal.showAllCards

        case .addTo(let valueExpr, let targetExpr):
            let value = try evaluate(valueExpr, env: &env, document: document, context: context)
            if case .variable(let name) = targetExpr {
                let existing = env.getVariable(name)
                env.setVariable(name, formatNumber(toNumber(existing) + toNumber(value)))
            } else if case .objectRef(let ref) = targetExpr {
                let ident = try evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    let existing = document.parts[idx].textContent
                    document.parts[idx].textContent = formatNumber(toNumber(existing) + toNumber(value))
                }
            }

        case .subtractFrom(let valueExpr, let targetExpr):
            let value = try evaluate(valueExpr, env: &env, document: document, context: context)
            if case .variable(let name) = targetExpr {
                let existing = env.getVariable(name)
                env.setVariable(name, formatNumber(toNumber(existing) - toNumber(value)))
            }

        case .multiplyBy(let targetExpr, let valueExpr):
            let value = try evaluate(valueExpr, env: &env, document: document, context: context)
            if case .variable(let name) = targetExpr {
                let existing = env.getVariable(name)
                env.setVariable(name, formatNumber(toNumber(existing) * toNumber(value)))
            }

        case .divideBy(let targetExpr, let valueExpr):
            let value = try evaluate(valueExpr, env: &env, document: document, context: context)
            if case .variable(let name) = targetExpr {
                let existing = env.getVariable(name)
                let divisor = toNumber(value)
                env.setVariable(name, divisor != 0 ? formatNumber(toNumber(existing) / divisor) : "INF")
            }

        case .deleteObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    document.parts.remove(at: idx)
                }
            }

        case .findText(let expr):
            // Stub: find is complex — for now store the search text in `it`.
            let text = try evaluate(expr, env: &env, document: document, context: context)
            env.it = text

        case .selectObject:
            break // UI operation — stub

        case .sortCards(let byExpr):
            // Sort cards by evaluating the expression for each card.
            let _ = try evaluate(byExpr, env: &env, document: document, context: context)
            // Complex — stub for now

        case .hideObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    document.parts[idx].visible = false
                }
            }

        case .showObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    document.parts[idx].visible = true
                }
            }

        case .lockScreen, .unlockScreen:
            break // UI operation — stub

        case .openStack:
            break // Complex — stub

        case .send, .wait, .beep, .play:
            // Stubs for future implementation.
            break

        // Phase 2: Implemented commands

        case .chooseTool(let expr):
            let toolName = try evaluate(expr, env: &env, document: document, context: context)
            env.it = toolName

        case .markCard(let expr):
            if let cardExpr = expr {
                let ident = try evaluate(cardExpr, env: &env, document: document, context: context)
                if let idx = document.cards.firstIndex(where: { $0.name.lowercased() == ident.lowercased() }) {
                    document.cards[idx].marked = true
                } else if let uuid = UUID(uuidString: ident),
                          let idx = document.cards.firstIndex(where: { $0.id == uuid }) {
                    document.cards[idx].marked = true
                }
            } else {
                if let idx = document.cards.firstIndex(where: { $0.id == context.currentCardId }) {
                    document.cards[idx].marked = true
                }
            }

        case .unmarkCard(let expr):
            if let cardExpr = expr {
                let ident = try evaluate(cardExpr, env: &env, document: document, context: context)
                if let idx = document.cards.firstIndex(where: { $0.name.lowercased() == ident.lowercased() }) {
                    document.cards[idx].marked = false
                } else if let uuid = UUID(uuidString: ident),
                          let idx = document.cards.firstIndex(where: { $0.id == uuid }) {
                    document.cards[idx].marked = false
                }
            } else {
                if let idx = document.cards.firstIndex(where: { $0.id == context.currentCardId }) {
                    document.cards[idx].marked = false
                }
            }

        case .typeText(let expr):
            let text = try evaluate(expr, env: &env, document: document, context: context)
            env.it = text

        case .convert(let sourceExpr, let targetExpr):
            let _ = try evaluate(sourceExpr, env: &env, document: document, context: context)
            let _ = try evaluate(targetExpr, env: &env, document: document, context: context)
            // Stub: conversion between date/time formats not yet implemented

        case .closeWindow, .saveStack, .quitApp, .editScriptOf:
            break // UI operations — stubs requiring platform integration

        // Phase 2: Stub commands (recognized but no-op)
        case .push, .pop, .clickAt, .dragFrom, .doMenuCmd, .disableCmd, .enableCmd,
             .helpCmd, .debugCmd, .dialCmd, .resetCmd, .printCmd, .readCmd, .writeCmd,
             .replyCmd, .requestCmd, .runCmd, .startUsing, .stopUsing,
             .copyTemplate, .exportPaint, .importPaint:
            break
        }
    }

    // MARK: - Expression evaluation

    private func evaluate(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) throws -> Value {
        switch expr {
        case .literal(let val):
            return val

        case .variable(let name):
            // Check constants first.
            switch name.lowercased() {
            case "empty": return ""
            case "quote": return "\""
            case "space": return " "
            case "tab": return "\t"
            case "return", "cr": return "\r"
            case "linefeed", "lf": return "\n"
            case "comma": return ","
            case "colon": return ":"
            case "pi": return String(Double.pi)
            case "zero": return "0"
            case "one": return "1"
            case "two": return "2"
            case "three": return "3"
            case "four": return "4"
            case "five": return "5"
            case "six": return "6"
            case "seven": return "7"
            case "eight": return "8"
            case "nine": return "9"
            case "ten": return "10"
            case "up": return "up"
            case "down": return "down"
            default: break
            }
            return env.getVariable(name)

        case .it:
            return env.it

        case .me:
            return context.targetId.uuidString

        case .this:
            // `this` returns the current part's primary content:
            // - For fields: textContent
            // - For buttons: name (the label)
            // - For other parts: name
            if let part = document.parts.first(where: { $0.id == context.targetId }) {
                switch part.partType {
                case .field:
                    return part.textContent
                case .button:
                    return part.showName ? part.name : part.textContent
                default:
                    return part.name
                }
            }
            return ""

        case .empty:
            return ""

        case .binary(let left, let op, let right):
            let lVal = try evaluate(left, env: &env, document: document, context: context)
            let rVal = try evaluate(right, env: &env, document: document, context: context)
            return evaluateBinary(lVal, op, rVal)

        case .unary(let op, let operand):
            let val = try evaluate(operand, env: &env, document: document, context: context)
            switch op {
            case .negate: return String(-toNumber(val))
            case .not:    return isTruthy(val) ? "false" : "true"
            }

        case .not(let operand):
            let val = try evaluate(operand, env: &env, document: document, context: context)
            return isTruthy(val) ? "false" : "true"

        case .contains(let left, let right):
            let lVal = try evaluate(left, env: &env, document: document, context: context)
            let rVal = try evaluate(right, env: &env, document: document, context: context)
            return lVal.lowercased().contains(rVal.lowercased()) ? "true" : "false"

        case .stringConcat(let left, let right):
            let lVal = try evaluate(left, env: &env, document: document, context: context)
            let rVal = try evaluate(right, env: &env, document: document, context: context)
            return lVal + rVal

        case .spacedConcat(let left, let right):
            let lVal = try evaluate(left, env: &env, document: document, context: context)
            let rVal = try evaluate(right, env: &env, document: document, context: context)
            return lVal + " " + rVal

        case .functionCall(let name, let args):
            let evaluatedArgs = try args.map { try evaluate($0, env: &env, document: document, context: context) }
            return evaluateBuiltIn(name, args: evaluatedArgs)

        case .propertyAccess(let property, let target):
            return try evaluateProperty(property, target: target, env: &env, document: document, context: context)

        case .chunk(let chunkType, let range, let source):
            let sourceVal = try evaluate(source, env: &env, document: document, context: context)
            return evaluateChunk(chunkType, range: range, source: sourceVal, env: &env, document: document, context: context)

        case .objectRef(let ref):
            let identVal = try evaluate(ref.identifier, env: &env, document: document, context: context)
            return resolveObjectRef(ref.objectType, identifier: identVal, document: document, context: context)

        case .isIn(let left, let right):
            let lVal = try evaluate(left, env: &env, document: document, context: context)
            let rVal = try evaluate(right, env: &env, document: document, context: context)
            return rVal.lowercased().contains(lVal.lowercased()) ? "true" : "false"

        case .isNotIn(let left, let right):
            let lVal = try evaluate(left, env: &env, document: document, context: context)
            let rVal = try evaluate(right, env: &env, document: document, context: context)
            return rVal.lowercased().contains(lVal.lowercased()) ? "false" : "true"

        case .isWithin(let left, let right):
            let lVal = try evaluate(left, env: &env, document: document, context: context)
            let rVal = try evaluate(right, env: &env, document: document, context: context)
            let point = lVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            let rect = rVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if point.count >= 2 && rect.count >= 4 {
                let inside = point[0] >= rect[0] && point[0] <= rect[2] && point[1] >= rect[1] && point[1] <= rect[3]
                return inside ? "true" : "false"
            }
            return "false"

        case .isNotWithin(let left, let right):
            let lVal = try evaluate(left, env: &env, document: document, context: context)
            let rVal = try evaluate(right, env: &env, document: document, context: context)
            let point = lVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            let rect = rVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if point.count >= 2 && rect.count >= 4 {
                let inside = point[0] >= rect[0] && point[0] <= rect[2] && point[1] >= rect[1] && point[1] <= rect[3]
                return inside ? "false" : "true"
            }
            return "true"

        case .isA(let expr, let typeName):
            let val = try evaluate(expr, env: &env, document: document, context: context)
            switch typeName.lowercased() {
            case "number", "integer", "float": return Double(val) != nil ? "true" : "false"
            case "logical", "boolean", "bool": return (val.lowercased() == "true" || val.lowercased() == "false") ? "true" : "false"
            case "point": return val.split(separator: ",").count == 2 ? "true" : "false"
            case "rect", "rectangle": return val.split(separator: ",").count == 4 ? "true" : "false"
            case "date": return "false"
            case "empty": return val.isEmpty ? "true" : "false"
            default: return "false"
            }

        case .isNotA(let expr, let typeName):
            let val = try evaluate(expr, env: &env, document: document, context: context)
            switch typeName.lowercased() {
            case "number", "integer", "float": return Double(val) != nil ? "false" : "true"
            case "logical", "boolean", "bool": return (val.lowercased() == "true" || val.lowercased() == "false") ? "false" : "true"
            case "point": return val.split(separator: ",").count == 2 ? "false" : "true"
            case "rect", "rectangle": return val.split(separator: ",").count == 4 ? "false" : "true"
            case "date": return "true"
            case "empty": return val.isEmpty ? "false" : "true"
            default: return "true"
            }

        case .thereIsA(_, let nameExpr):
            let name = try evaluate(nameExpr, env: &env, document: document, context: context)
            let found = document.parts.contains { $0.name.lowercased() == name.lowercased() }
            return found ? "true" : "false"

        case .thereIsNo(_, let nameExpr):
            let name = try evaluate(nameExpr, env: &env, document: document, context: context)
            let found = document.parts.contains { $0.name.lowercased() == name.lowercased() }
            return found ? "false" : "true"
        }
    }

    // MARK: - Binary operations

    private func evaluateBinary(_ lVal: Value, _ op: BinaryOp, _ rVal: Value) -> Value {
        switch op {
        case .add:            return formatNumber(toNumber(lVal) + toNumber(rVal))
        case .subtract:       return formatNumber(toNumber(lVal) - toNumber(rVal))
        case .multiply:       return formatNumber(toNumber(lVal) * toNumber(rVal))
        case .divide:
            let r = toNumber(rVal)
            return r == 0 ? "0" : formatNumber(toNumber(lVal) / r)
        case .power:          return formatNumber(pow(toNumber(lVal), toNumber(rVal)))
        case .modulo:
            let r = toNumber(rVal)
            return r == 0 ? "0" : formatNumber(toNumber(lVal).truncatingRemainder(dividingBy: r))
        case .intDiv:
            let divisor = toNumber(rVal)
            return divisor != 0 ? String(Int(toNumber(lVal) / divisor)) : "0"
        case .equal:          return lVal.lowercased() == rVal.lowercased() ? "true" : "false"
        case .notEqual:       return lVal.lowercased() != rVal.lowercased() ? "true" : "false"
        case .lessThan:       return toNumber(lVal) < toNumber(rVal) ? "true" : "false"
        case .greaterThan:    return toNumber(lVal) > toNumber(rVal) ? "true" : "false"
        case .lessOrEqual:    return toNumber(lVal) <= toNumber(rVal) ? "true" : "false"
        case .greaterOrEqual: return toNumber(lVal) >= toNumber(rVal) ? "true" : "false"
        case .and:            return (isTruthy(lVal) && isTruthy(rVal)) ? "true" : "false"
        case .or:             return (isTruthy(lVal) || isTruthy(rVal)) ? "true" : "false"
        }
    }

    // MARK: - Built-in functions

    private func evaluateBuiltIn(_ name: String, args: [Value]) -> Value {
        switch name.lowercased() {
        case "length":
            return String(args.first?.count ?? 0)
        case "offset":
            guard args.count >= 2 else { return "0" }
            if let range = args[1].lowercased().range(of: args[0].lowercased()) {
                return String(args[1].distance(from: args[1].startIndex, to: range.lowerBound) + 1)
            }
            return "0"
        case "random":
            guard let max = args.first.flatMap({ Int($0) }), max > 0 else { return "0" }
            return String(Int.random(in: 1...max))
        case "abs":
            return formatNumber(abs(toNumber(args.first ?? "0")))
        case "round":
            return String(Int(toNumber(args.first ?? "0").rounded()))
        case "trunc":
            return String(Int(toNumber(args.first ?? "0")))
        case "min":
            guard args.count >= 2 else { return args.first ?? "0" }
            return formatNumber(min(toNumber(args[0]), toNumber(args[1])))
        case "max":
            guard args.count >= 2 else { return args.first ?? "0" }
            return formatNumber(max(toNumber(args[0]), toNumber(args[1])))

        // Math functions
        case "sin": return formatNumber(Foundation.sin(toNumber(args.first ?? "0")))
        case "cos": return formatNumber(Foundation.cos(toNumber(args.first ?? "0")))
        case "tan": return formatNumber(Foundation.tan(toNumber(args.first ?? "0")))
        case "atan": return formatNumber(Foundation.atan(toNumber(args.first ?? "0")))
        case "sqrt": return formatNumber(Foundation.sqrt(toNumber(args.first ?? "0")))
        case "exp": return formatNumber(Foundation.exp(toNumber(args.first ?? "0")))
        case "ln": return formatNumber(Foundation.log(toNumber(args.first ?? "0")))
        case "log2": return formatNumber(Foundation.log2(toNumber(args.first ?? "0")))

        // String functions
        case "chartonum":
            let str = args.first ?? ""
            return str.isEmpty ? "0" : String(Int(str.unicodeScalars.first?.value ?? 0))
        case "numtochar":
            let num = Int(toNumber(args.first ?? "0"))
            return num > 0 && num < 65536 ? String(Character(UnicodeScalar(num)!)) : ""
        case "value":
            return args.first ?? ""

        // Date and time functions
        case "date":
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: Date())
        case "time":
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            return formatter.string(from: Date())
        case "ticks":
            return String(Int(Date().timeIntervalSince1970 * 60))
        case "seconds":
            return String(Int(Date().timeIntervalSince1970))
        case "number":
            return args.first ?? "0"

        // Mouse functions (return static defaults since we're not in a live event loop)
        case "mouse": return "up"
        case "mouseclick": return "false"
        case "mouseh": return "0"
        case "mousev": return "0"
        case "mouseloc": return "0,0"

        // Key functions
        case "shiftkey":
            #if canImport(AppKit)
            return NSEvent.modifierFlags.contains(.shift) ? "down" : "up"
            #else
            return "up"
            #endif
        case "commandkey":
            #if canImport(AppKit)
            return NSEvent.modifierFlags.contains(.command) ? "down" : "up"
            #else
            return "up"
            #endif
        case "optionkey":
            #if canImport(AppKit)
            return NSEvent.modifierFlags.contains(.option) ? "down" : "up"
            #else
            return "up"
            #endif

        // Other (stubs — full implementation requires runtime context)
        case "target": return ""
        case "result": return ""
        case "param": return args.first ?? ""
        case "paramcount": return "0"
        case "params": return ""

        // Sum and average
        case "sum":
            let total = args.reduce(0.0) { $0 + toNumber($1) }
            return formatNumber(total)
        case "average":
            let total = args.reduce(0.0) { $0 + toNumber($1) }
            return args.isEmpty ? "0" : formatNumber(total / Double(args.count))

        // Financial functions
        case "annuity":
            let rate = toNumber(args.first ?? "0")
            let periods = toNumber(args.count > 1 ? args[1] : "0")
            return rate == 0 ? formatNumber(periods) : formatNumber((1 - pow(1 + rate, -periods)) / rate)
        case "compound":
            let rate = toNumber(args.first ?? "0")
            let periods = toNumber(args.count > 1 ? args[1] : "0")
            return formatNumber(pow(1 + rate, periods))

        // Math extras
        case "exp1":
            return formatNumber(Foundation.exp(toNumber(args.first ?? "0")) - 1)
        case "exp2":
            return formatNumber(pow(2, toNumber(args.first ?? "0")))
        case "ln1":
            return formatNumber(Foundation.log(1 + toNumber(args.first ?? "0")))

        // System info
        case "screenrect":
            #if canImport(AppKit)
            if let screen = NSScreen.main {
                let r = screen.frame
                return "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.maxX)),\(Int(r.maxY))"
            }
            #endif
            return "0,0,1920,1080"
        case "diskspace":
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
               let space = attrs[.systemFreeSize] as? Int64 {
                return String(space)
            }
            return "0"
        case "systemversion":
            return ProcessInfo.processInfo.operatingSystemVersionString
        case "version":
            return "Hype 2.0"
        case "heapspace", "stackspace":
            return String(ProcessInfo.processInfo.physicalMemory)
        case "environment":
            return "Hype"
        case "tool":
            return "browse"
        case "windows":
            return "Hype"

        // Click/selection/find stubs
        case "clickchunk", "clickh", "clickv", "clickline", "clickloc", "clicktext":
            return ""
        case "foundchunk", "foundfield", "foundline", "foundtext":
            return ""
        case "selectedbutton", "selectedchunk", "selectedfield", "selectedline", "selectedloc", "selectedtext":
            return ""
        case "sound":
            return "done"
        case "programs":
            return "Hype"
        case "menus":
            return ""
        case "destination":
            return ""
        case "stacks":
            return "Hype"

        default:
            return ""
        }
    }

    // MARK: - Property access

    private func evaluateProperty(
        _ property: String,
        target: Expression?,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) throws -> Value {
        let lower = property.lowercased()

        // Global properties (no target).
        if target == nil {
            switch lower {
            case "date":
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: Date())
            case "time":
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                return formatter.string(from: Date())
            case "ticks":
                return String(Int(Date().timeIntervalSince1970 * 60))
            case "seconds":
                return String(Int(Date().timeIntervalSince1970))
            case "itemdelimiter":
                return ","
            case "numberformat":
                return "0.######"
            case "lockscreen":
                return "false"
            case "editbkgnd":
                return "false"
            case "userlevel":
                return "5"
            case "version":
                return "Hype 2.0"
            case "environment":
                return "Hype"
            case "language", "scriptinglanguage":
                return "HyperTalk"
            case "cursor":
                return "hand"
            case "lockmessages":
                return "false"
            case "lockerrordialogs":
                return "false"
            case "lockrecent":
                return "false"
            case "dragspeed":
                return "0"
            case "powerkeys":
                return "true"
            case "blindtyping":
                return "false"
            case "textarrows":
                return "true"
            case "dialingtime":
                return "0"
            case "dialingvolume":
                return "0"
            case "address":
                return ""
            case "longwindowtitles":
                return "false"
            case "multispace":
                return "false"
            case "reporttemplates":
                return ""
            case "scripteditor":
                return ""
            case "scripttextfont":
                return "Monaco"
            case "scripttextsize":
                return "12"
            case "stacksinuse":
                return ""
            case "suspended":
                return "false"
            case "tracedelay":
                return "0"
            case "messagewatcher":
                return "false"
            case "variablewatcher":
                return "false"
            case "freesize":
                return "0"
            case "size":
                return "0"
            case "brush":
                return "8"
            case "filled":
                return "false"
            case "grid":
                return "false"
            case "linesize":
                return "1"
            case "pattern":
                return "1"
            case "centered":
                return "false"
            case "polysides":
                return "4"
            case "commandchar":
                return ""
            case "markchar", "checkmark":
                return "\u{2713}"
            case "menumessage":
                return ""
            default:
                return env.getVariable(property)
            }
        }

        // Property of target.
        let targetExpr = target!
        let targetVal = try evaluate(targetExpr, env: &env, document: document, context: context)

        // "the number of cards/buttons/fields"
        if lower == "number" {
            switch targetVal.lowercased() {
            case "cards":
                return String(document.cards.count)
            case "backgrounds":
                return String(document.backgrounds.count)
            case "buttons", "card buttons":
                return String(document.partsForCard(context.currentCardId).filter { $0.partType == .button }.count)
            case "fields", "card fields":
                return String(document.partsForCard(context.currentCardId).filter { $0.partType == .field }.count)
            default: break
            }
        }

        // Property of a specific part via object reference.
        if case .objectRef(let ref) = targetExpr {
            let ident = try evaluate(ref.identifier, env: &env, document: document, context: context)
            if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                let part = document.parts[idx]
                switch lower {
                case "name":        return part.name
                case "id":          return part.id.uuidString
                case "left":        return formatNumber(part.left)
                case "top":         return formatNumber(part.top)
                case "width":       return formatNumber(part.width)
                case "height":      return formatNumber(part.height)
                case "right":       return formatNumber(part.left + part.width)
                case "bottom":      return formatNumber(part.top + part.height)
                case "loc", "location":
                    return "\(formatNumber(part.left + part.width / 2)),\(formatNumber(part.top + part.height / 2))"
                case "rect", "rectangle":
                    return "\(formatNumber(part.left)),\(formatNumber(part.top)),\(formatNumber(part.left + part.width)),\(formatNumber(part.top + part.height))"
                case "visible":     return part.visible ? "true" : "false"
                case "enabled":     return part.enabled ? "true" : "false"
                case "hilite":      return part.hilite ? "true" : "false"
                case "style":
                    return part.partType == .button ? part.buttonStyle.rawValue : part.fieldStyle.rawValue
                case "textfont", "font": return part.textFont
                case "textsize", "size": return formatNumber(part.textSize)
                case "textstyle":   return part.textStyle
                case "textalign":   return part.textAlign.rawValue
                case "script":      return part.script
                case "showname":    return part.showName ? "true" : "false"
                case "autohilite":  return part.autoHilite ? "true" : "false"
                case "locktext":    return part.lockText ? "true" : "false"
                case "widemargins": return part.wideMargins ? "true" : "false"
                case "dontwrap":    return part.dontWrap ? "true" : "false"
                case "url":         return part.url
                case "text", "textcontent": return part.textContent
                case "topleft":
                    return "\(formatNumber(part.left)),\(formatNumber(part.top))"
                case "bottomright":
                    return "\(formatNumber(part.left + part.width)),\(formatNumber(part.top + part.height))"
                case "number", "partnumber":
                    let allParts = document.partsForCard(context.currentCardId)
                    if let pidx = allParts.firstIndex(where: { $0.id == part.id }) {
                        return String(pidx + 1)
                    }
                    return "0"
                case "owner":
                    if let cardId = part.cardId, let card = document.cards.first(where: { $0.id == cardId }) {
                        return card.name.isEmpty ? "card id \(cardId)" : "card \"\(card.name)\""
                    }
                    if let bgId = part.backgroundId, let bg = document.backgrounds.first(where: { $0.id == bgId }) {
                        return bg.name.isEmpty ? "bkgnd id \(bgId)" : "bkgnd \"\(bg.name)\""
                    }
                    return ""
                case "family":       return String(part.family)
                case "scroll", "scrollpos": return "0"
                case "sharedtext":   return "false"
                case "sharedhilite": return "false"
                case "showlines":    return "false"
                case "showpict":     return "true"
                case "fixedlineheight": return "false"
                case "multiplelines": return "true"
                case "dontsearch":   return "false"
                case "autoselect":   return "false"
                case "autotab":      return "false"
                case "textheight":   return formatNumber(part.textSize * 1.3)
                case "marked":
                    if let card = document.cards.first(where: { $0.id == context.currentCardId }) {
                        return card.marked ? "true" : "false"
                    }
                    return "false"
                case "cantdelete":   return "false"
                case "cantmodify":   return "false"
                case "centered":
                    return part.textAlign == .center ? "true" : "false"
                case "filled":
                    return part.partType == .shape ? (part.fillColor != "#FFFFFF" && part.fillColor != "#00000000" ? "true" : "false") : "false"
                case "linesize":
                    return formatNumber(part.strokeWidth)
                case "icon":
                    return part.iconId?.uuidString ?? "0"
                case "size":
                    return "\(formatNumber(part.width)),\(formatNumber(part.height))"
                case "fillcolor", "fill_color":
                    return part.fillColor
                case "strokecolor", "stroke_color":
                    return part.strokeColor
                case "strokewidth", "stroke_width":
                    return formatNumber(part.strokeWidth)
                case "cornerradius", "corner_radius":
                    return formatNumber(part.cornerRadius)
                case "shapetype", "shape_type":
                    return part.shapeType.rawValue
                case "richtext", "rich_text":
                    return part.richText ? "true" : "false"
                case "enterkeyenabled":
                    return part.enterKeyEnabled ? "true" : "false"
                case "invertonclick":
                    return part.invertOnClick ? "true" : "false"
                default:            return ""
                }
            }
        }

        // Fallback: try to find the part by name or UUID.
        if let part = findPart(targetVal, document: document) {
            switch lower {
            case "name":     return part.name
            case "id":       return part.id.uuidString
            case "visible":  return part.visible ? "true" : "false"
            case "enabled":  return part.enabled ? "true" : "false"
            case "hilite":   return part.hilite ? "true" : "false"
            case "left":     return formatNumber(part.left)
            case "top":      return formatNumber(part.top)
            case "width":    return formatNumber(part.width)
            case "height":   return formatNumber(part.height)
            case "textfont": return part.textFont
            case "textsize": return formatNumber(part.textSize)
            default:         return ""
            }
        }

        return ""
    }

    // MARK: - Chunk expressions

    private func evaluateChunk(
        _ chunkType: ChunkType,
        range: ChunkRange,
        source: Value,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) -> Value {
        let parts: [String]
        switch chunkType {
        case .word:
            parts = source.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        case .char, .character:
            parts = source.map(String.init)
        case .item:
            parts = source.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        case .line:
            parts = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }

        switch range {
        case .single(let indexExpr):
            // Evaluate index — but we may already have a literal from ordinal parsing.
            let indexStr: String
            if case .literal(let v) = indexExpr {
                indexStr = v
            } else {
                indexStr = "1"
            }
            let idx = Int(toNumber(indexStr))
            if idx == -1 {
                // "last"
                return parts.last ?? ""
            } else if idx == 0 {
                // "middle"
                return parts.isEmpty ? "" : parts[parts.count / 2]
            } else if idx == -2 {
                // "any"
                return parts.isEmpty ? "" : parts[Int.random(in: 0..<parts.count)]
            } else if idx >= 1 && idx <= parts.count {
                return parts[idx - 1]
            }
            return ""

        case .range(let fromExpr, let toExpr):
            let fromStr: String
            if case .literal(let v) = fromExpr { fromStr = v } else { fromStr = "1" }
            let toStr: String
            if case .literal(let v) = toExpr { toStr = v } else { toStr = "1" }
            let from = max(1, Int(toNumber(fromStr)))
            let to = min(parts.count, Int(toNumber(toStr)))
            guard from <= to, from >= 1 else { return "" }
            let separator: String
            switch chunkType {
            case .word: separator = " "
            case .char, .character: separator = ""
            case .item: separator = ","
            case .line: separator = "\n"
            }
            return parts[(from - 1)..<to].joined(separator: separator)
        }
    }

    // MARK: - Object reference resolution

    private func resolveObjectRef(_ objectType: String, identifier: Value, document: HypeDocument, context: ExecutionContext) -> Value {
        switch objectType {
        case "card":
            if let card = document.cards.first(where: { $0.name.lowercased() == identifier.lowercased() }) {
                return card.id.uuidString
            }
            if let idx = Int(identifier), idx >= 1, idx <= document.sortedCards.count {
                return document.sortedCards[idx - 1].id.uuidString
            }
        case "field", "fld":
            if let part = document.parts.first(where: { $0.partType == .field && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "button", "btn":
            if let part = document.parts.first(where: { $0.partType == .button && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        default:
            break
        }
        return ""
    }

    // MARK: - Navigation resolution

    private func resolveNavigation(_ dest: String, document: HypeDocument, currentCardId: UUID) -> UUID? {
        let lower = dest.lowercased()
        switch lower {
        case "next":
            return CardNavigator.navigate(direction: .next, currentCardId: currentCardId, document: document)
        case "previous", "prev", "back":
            return CardNavigator.navigate(direction: .previous, currentCardId: currentCardId, document: document)
        case "first":
            return CardNavigator.navigate(direction: .first, currentCardId: currentCardId, document: document)
        case "last":
            return CardNavigator.navigate(direction: .last, currentCardId: currentCardId, document: document)
        default:
            // Try by card name.
            if let card = document.cards.first(where: { $0.name.lowercased() == lower }) {
                return card.id
            }
            return nil
        }
    }

    // MARK: - Helpers

    private func findPart(_ identifier: Value, document: HypeDocument) -> Part? {
        if let idx = findPartIndexGeneral(identifier, document: document) {
            return document.parts[idx]
        }
        return nil
    }

    /// Find a part's index by object type and identifier, scoped to the current card.
    private func findPartIndex(
        _ objectType: String,
        identifier: Value,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Int? {
        let targetType: PartType? = objectType == "field" ? .field :
                                     objectType == "button" ? .button :
                                     objectType == "btn" ? .button :
                                     objectType == "fld" ? .field :
                                     objectType == "webpage" ? .webpage :
                                     objectType == "shape" ? .shape : nil

        // Get parts on the current card + its background
        let cardParts = document.partsForCard(currentCardId)
        let card = document.cards.first(where: { $0.id == currentCardId })
        let bgParts = card.map { document.partsForBackground($0.backgroundId) } ?? []
        let allParts = cardParts + bgParts

        // Try by name first
        let lower = identifier.lowercased()
        if let part = allParts.first(where: {
            (targetType == nil || $0.partType == targetType) &&
            $0.name.lowercased() == lower
        }) {
            return document.parts.firstIndex(where: { $0.id == part.id })
        }

        // Try by number (1-based)
        if let num = Int(identifier), num > 0 {
            let typed = allParts.filter { targetType == nil || $0.partType == targetType }
            if num <= typed.count {
                let part = typed[num - 1]
                return document.parts.firstIndex(where: { $0.id == part.id })
            }
        }

        return nil
    }

    /// Find a part index by identifier without type filtering.
    private func findPartIndexGeneral(_ identifier: Value, document: HypeDocument) -> Int? {
        if let uuid = UUID(uuidString: identifier) {
            return document.parts.firstIndex(where: { $0.id == uuid })
        }
        return document.parts.firstIndex(where: { $0.name.lowercased() == identifier.lowercased() })
    }

    /// Convert a HypeTalk value to a number. Non-numeric strings become 0.
    private func toNumber(_ value: Value) -> Double {
        Double(value) ?? 0
    }

    /// Format a number, dropping .0 for integers.
    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded(.towardZero) && !n.isInfinite && !n.isNaN {
            return String(Int(n))
        }
        return String(n)
    }

    /// Check if a HypeTalk value is truthy.
    private func isTruthy(_ value: Value) -> Bool {
        let lower = value.lowercased()
        return lower == "true" || lower == "yes" || (Double(value).map { $0 != 0 } ?? false)
    }
}

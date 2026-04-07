import Foundation

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

    public init(
        status: ExecutionStatus,
        returnValue: Value? = nil,
        modifiedDocument: HypeDocument? = nil,
        error: ScriptError? = nil,
        navigationTarget: UUID? = nil
    ) {
        self.status = status
        self.returnValue = returnValue
        self.modifiedDocument = modifiedDocument
        self.error = error
        self.navigationTarget = navigationTarget
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

        case .send, .wait, .beep, .play:
            // Stubs for future implementation.
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
            return env.getVariable(name)

        case .it:
            return env.it

        case .me:
            return context.targetId.uuidString

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
            default:
                return env.getVariable(property)
            }
        }

        // Property of target.
        let targetVal = try evaluate(target!, env: &env, document: document, context: context)
        // Try to find the part by name or UUID.
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

import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// HypeTalk values are all strings, coerced to numbers for arithmetic.
public typealias Value = String

/// Provider for UI dialogs (ask/answer) — injected by the UI layer.
public protocol DialogProvider: Sendable {
    /// Show an alert dialog with a message. Returns the button clicked ("OK", "Cancel", etc.)
    func showAnswer(prompt: String) -> String
    /// Show an input dialog with a prompt. Returns the user's input, or empty if cancelled.
    func showAsk(prompt: String) -> String
}

public extension DialogProvider {
    func showAnswerAsync(prompt: String) async -> String {
        await MainActor.run {
            showAnswer(prompt: prompt)
        }
    }

    func showAskAsync(prompt: String) async -> String {
        await MainActor.run {
            showAsk(prompt: prompt)
        }
    }
}

/// Default dialog provider that just returns the prompt (used when no UI is available).
public struct StubDialogProvider: DialogProvider, Sendable {
    public init() {}
    public func showAnswer(prompt: String) -> String { return "OK" }
    public func showAsk(prompt: String) -> String { return "" }
}

/// Protocol for bitmap drawing from scripts (e.g. `drag from x,y to x,y`).
public protocol DrawingProvider: Sendable {
    func drawLine(from: (Int, Int), to: (Int, Int), radius: Int, colorHex: String)
}

public extension DrawingProvider {
    func drawLineAsync(from: (Int, Int), to: (Int, Int), radius: Int, colorHex: String) async {
        await MainActor.run {
            drawLine(from: from, to: to, radius: radius, colorHex: colorHex)
        }
    }
}

/// Default drawing provider that does nothing (used when no UI is available).
public struct StubDrawingProvider: DrawingProvider, Sendable {
    public init() {}
    public func drawLine(from: (Int, Int), to: (Int, Int), radius: Int, colorHex: String) {}
}

/// Context for script execution.
public struct ExecutionContext: Sendable {
    public var targetId: UUID
    public var currentCardId: UUID
    public var document: HypeDocument
    public var instructionLimit: Int
    public var dialogProvider: DialogProvider
    public var drawingProvider: DrawingProvider
    public var aiProvider: any AIScriptingProvider
    public var speechOutputProvider: SpeechOutputProvider
    public var runtimeProvider: (any ScriptRuntimeProviding)?
    /// Phase 3: Meshy scripting provider for `ask meshy` statements.
    /// `nil` degrades gracefully — `ask meshy` sets `it = ""` and returns.
    public var meshyProvider: (any MeshyScriptingProvider)?
    public var mouseX: Double
    public var mouseY: Double
    public var scriptContext: ScriptDispatchContext?
    public var appScript: String
    public var nestedSendDepth: Int

    public init(targetId: UUID, currentCardId: UUID, document: HypeDocument, instructionLimit: Int = 1_000_000,
                dialogProvider: DialogProvider = StubDialogProvider(),
                drawingProvider: DrawingProvider = StubDrawingProvider(),
                aiProvider: any AIScriptingProvider = StubAIScriptingProvider(),
                speechOutputProvider: SpeechOutputProvider = StubSpeechOutputProvider(),
                runtimeProvider: (any ScriptRuntimeProviding)? = nil,
                meshyProvider: (any MeshyScriptingProvider)? = nil,
                mouseX: Double = 0, mouseY: Double = 0,
                appScript: String = "",
                nestedSendDepth: Int = 0) {
        self.targetId = targetId
        self.currentCardId = currentCardId
        self.document = document
        self.instructionLimit = instructionLimit
        self.dialogProvider = dialogProvider
        self.drawingProvider = drawingProvider
        self.aiProvider = aiProvider
        self.speechOutputProvider = speechOutputProvider
        self.runtimeProvider = runtimeProvider
        self.meshyProvider = meshyProvider
        self.mouseX = mouseX
        self.mouseY = mouseY
        self.scriptContext = nil
        self.appScript = appScript
        self.nestedSendDepth = nestedSendDepth
    }

    public init(targetId: UUID, currentCardId: UUID, document: HypeDocument, instructionLimit: Int = 1_000_000,
                dialogProvider: DialogProvider = StubDialogProvider(),
                drawingProvider: DrawingProvider = StubDrawingProvider(),
                aiProvider: any AIScriptingProvider = StubAIScriptingProvider(),
                speechOutputProvider: SpeechOutputProvider = StubSpeechOutputProvider(),
                runtimeProvider: (any ScriptRuntimeProviding)? = nil,
                meshyProvider: (any MeshyScriptingProvider)? = nil,
                mouseX: Double = 0, mouseY: Double = 0,
                scriptContext: ScriptDispatchContext? = nil,
                appScript: String = "",
                nestedSendDepth: Int = 0) {
        self.targetId = targetId
        self.currentCardId = currentCardId
        self.document = document
        self.instructionLimit = instructionLimit
        self.dialogProvider = dialogProvider
        self.drawingProvider = drawingProvider
        self.aiProvider = aiProvider
        self.speechOutputProvider = speechOutputProvider
        self.runtimeProvider = runtimeProvider
        self.meshyProvider = meshyProvider
        self.mouseX = mouseX
        self.mouseY = mouseY
        self.scriptContext = scriptContext
        self.appScript = appScript
        self.nestedSendDepth = nestedSendDepth
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
    /// The visual effect name requested by a `visual effect` statement, if any.
    public var visualEffect: String?
    /// Duration in seconds for the visual effect transition.
    /// `nil` means use the default (1.0 seconds).
    public var visualEffectDuration: Double?

    public init(
        status: ExecutionStatus,
        returnValue: Value? = nil,
        modifiedDocument: HypeDocument? = nil,
        error: ScriptError? = nil,
        navigationTarget: UUID? = nil,
        showAllCards: Bool = false,
        visualEffect: String? = nil,
        visualEffectDuration: Double? = nil
    ) {
        self.status = status
        self.returnValue = returnValue
        self.modifiedDocument = modifiedDocument
        self.error = error
        self.navigationTarget = navigationTarget
        self.showAllCards = showAllCards
        self.visualEffect = visualEffect
        self.visualEffectDuration = visualEffectDuration
    }
}

/// Execution outcome.
public enum ExecutionStatus: Sendable {
    case completed, passed, error
}

/// A runtime script error.
///
/// The `objectId` field identifies which script-owning object
/// (part, card, background, stack, or the app-level "Hype" sentinel)
/// produced the error. It is populated by `MessageDispatcher.dispatch`
/// after the interpreter returns — the interpreter itself doesn't set
/// it, because errors thrown from deep inside `executeStatement` have
/// no convenient hook to the dispatch-level context. Having the owner
/// ID on the error lets the view layer (`CardCanvasView.Coordinator`)
/// post a `.showScriptError` notification with enough context for
/// `MainContentView` to open the script editor for the right object
/// and highlight the offending line.
public struct ScriptError: Error, Sendable {
    public var message: String
    public var line: Int
    public var handler: String
    public var objectId: UUID?

    public init(message: String, line: Int, handler: String, objectId: UUID? = nil) {
        self.message = message
        self.line = line
        self.handler = handler
        self.objectId = objectId
    }
}

// MARK: - Environment

/// Mutable variable environment for script execution.
private struct Environment {
    var locals: [String: Value] = [:]
    var globals: [String: Value]
    var handlerParams: [Value] = []
    var it: Value = ""
    /// Phase 3: `the result` — set by `ask meshy` on success. Mirrors `it`.
    var result: Value = ""
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

    func handlerParam(at oneBasedIndex: Int) -> Value {
        guard oneBasedIndex > 0, oneBasedIndex <= handlerParams.count else { return "" }
        return handlerParams[oneBasedIndex - 1]
    }

    var joinedHandlerParams: Value {
        handlerParams.joined(separator: "\r")
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

private final class _InterpreterResultBox<T: Sendable>: @unchecked Sendable {
    var value: T?
}

private enum _InterpreterSyncGate {
    static let semaphore = DispatchSemaphore(value: 1)
}

// MARK: - Interpreter

/// Tree-walking interpreter for HypeTalk scripts.
public struct Interpreter: Sendable {

    public init() {}

    /// Execute a handler with the given parameters and context.
    public func execute(handler: Handler, params: [Value], context: ExecutionContext) -> ExecutionResult {
        blockingWait {
            await executeAsync(handler: handler, params: params, context: context)
        }
    }

    public func executeAsync(handler: Handler, params: [Value], context: ExecutionContext) async -> ExecutionResult {
        var document = context.document
        // Seed the environment's globals from the document's
        // session-level scriptGlobals. This is the fix for "on idle
        // / add 5 to rot / end idle" — without this, `rot` would
        // reset to empty on every dispatch and never accumulate.
        // HypeTalk globals live for the stack session (until the
        // stack closes), matching classic HyperCard semantics.
        var env = Environment(globals: document.scriptGlobals, handlerParams: params)
        var instructionCount = 0
        var navigationTarget: UUID? = nil
        var visualEffect: String? = nil

        // Bind parameters.
        for (i, paramName) in handler.params.enumerated() {
            let value = i < params.count ? params[i] : ""
            env.locals[paramName.lowercased()] = value
        }

        // Expose first-param implicit synonyms for a handful of
        // handler-local HypeTalk properties that the HypeTalk guide
        // documents but that previously returned empty because the
        // interpreter had no way to back them.
        //
        // Reported as "keyDown event doesn't work": the guide shows
        //   `on keyDown / if the key is "w" then … / end keyDown`
        // but `the key` fell through to `env.getVariable("key")`
        // which returned empty unless the user declared a parameter
        // called `key`. The event WAS being dispatched to the scene
        // script with the character in `params[0]` — the script just
        // had no way to read it without redeclaring the handler.
        //
        // `the key` now resolves to params[0] in `on keyDown` and
        // `on keyUp` handlers regardless of the declared parameter
        // list. Likewise `the otherNode` for contact handlers so
        // scripts can write `if the otherNode is "player" then …`.
        let handlerLower = handler.name.lowercased()
        if (handlerLower == "keydown" || handlerLower == "keyup"),
           !params.isEmpty {
            // Do NOT overwrite a user's explicit `on keyDown key`
            // param binding (which is already params[0]).
            if env.locals["key"] == nil {
                env.locals["key"] = params[0]
            }
        }
        if (handlerLower == "begincontact" || handlerLower == "endcontact"),
           !params.isEmpty {
            if env.locals["othernode"] == nil {
                env.locals["othernode"] = params[0]
            }
            if env.locals["contactnode"] == nil {
                env.locals["contactnode"] = params[0]
            }
        }

        do {
            for stmt in handler.body {
                try await executeStatement(stmt, env: &env, document: &document,
                                           context: context, instructionCount: &instructionCount,
                                           navigationTarget: &navigationTarget, handler: handler)
            }
        } catch ControlSignal.passMessage {
            document.scriptGlobals = env.globals
            // Carry visual effect and navigation target through
            // even when the handler passes the message. A script
            // like `visual effect dissolve / go next / pass mouseUp`
            // sets both before passing — dropping them here makes
            // the transition invisible.
            visualEffect = env.locals["_visualEffect"]
            let veDuration = Double(env.locals["_visualEffectDuration"] ?? "")
            return ExecutionResult(status: .passed, modifiedDocument: document,
                                   navigationTarget: navigationTarget,
                                   visualEffect: visualEffect, visualEffectDuration: veDuration)
        } catch ControlSignal.exitHandler(let returnVal) {
            document.scriptGlobals = env.globals
            visualEffect = env.locals["_visualEffect"]
            let veDuration = Double(env.locals["_visualEffectDuration"] ?? "")
            return ExecutionResult(status: .completed, returnValue: returnVal,
                                   modifiedDocument: document, navigationTarget: navigationTarget,
                                   visualEffect: visualEffect, visualEffectDuration: veDuration)
        } catch ControlSignal.showAllCards {
            document.scriptGlobals = env.globals
            return ExecutionResult(status: .completed, modifiedDocument: document, showAllCards: true)
        } catch let error as ScriptError {
            return ExecutionResult(status: .error, error: error)
        } catch {
            let scriptError = ScriptError(message: error.localizedDescription, line: handler.line, handler: handler.name)
            return ExecutionResult(status: .error, error: scriptError)
        }

        // Normal completion: write accumulated globals back so the
        // next dispatch (e.g. the next idle tick) reads the
        // mutated values.
        document.scriptGlobals = env.globals
        visualEffect = env.locals["_visualEffect"]
        let veDuration = Double(env.locals["_visualEffectDuration"] ?? "")
        return ExecutionResult(status: .completed, returnValue: env.it,
                               modifiedDocument: document, navigationTarget: navigationTarget,
                               visualEffect: visualEffect, visualEffectDuration: veDuration)
    }

    private func blockingWait<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T {
        _InterpreterSyncGate.semaphore.wait()
        defer { _InterpreterSyncGate.semaphore.signal() }
        let semaphore = DispatchSemaphore(value: 0)
        let box = _InterpreterResultBox<T>()
        if Thread.isMainThread {
            Task.detached {
                box.value = await operation()
                semaphore.signal()
            }
        } else {
            Task { @MainActor in
                box.value = await operation()
                semaphore.signal()
            }
        }
        semaphore.wait()
        return box.value!
    }

    private func evaluateOptional(
        _ expr: Expression?,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value? {
        guard let expr else { return nil }
        return try await evaluate(expr, env: &env, document: document, context: context)
    }

    private func sleepOutsideRuntime(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func isActivateListenerProperty(_ property: String) -> Bool {
        switch property.lowercased().replacingOccurrences(of: "_", with: "") {
        case "activatelistener", "speechlistener", "listeneractive":
            return true
        default:
            return false
        }
    }

    private func setSpeechListenerActive(
        _ activeValue: Value,
        context: ExecutionContext,
        handler: Handler
    ) async throws {
        guard let runtime = context.runtimeProvider else {
            throw ScriptError(
                message: "Speech listener runtime is unavailable",
                line: handler.line,
                handler: handler.name
            )
        }
        try await runtime.setSpeechListenerActive(
            isTruthy(activeValue),
            owner: RuntimeOwnerContext(
                targetId: context.currentCardId,
                currentCardId: context.currentCardId,
                scriptContext: nil
            )
        )
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
    ) async throws {
        instructionCount += 1
        if instructionCount > context.instructionLimit {
            throw ScriptError(message: "Instruction limit exceeded", line: handler.line, handler: handler.name)
        }

        switch stmt {
        case .put(let source, let prep, let target):
            let value = try await evaluate(source, env: &env, document: document, context: context)
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
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
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
            env.it = try await evaluate(expr, env: &env, document: document, context: context)

        case .set(let property, let target, let toExpr):
            let value = try await evaluate(toExpr, env: &env, document: document, context: context)
            if target == nil, isActivateListenerProperty(property) {
                try await setSpeechListenerActive(value, context: context, handler: handler)
                env.it = isTruthy(value) ? "true" : "false"
                break
            }
            if let targetExpr = target {
                // Chart data-point reference set path:
                //   set the color of data point N of [series N of] chart "X" to "#FF0000"
                //
                // This branch is delegated to a separate helper
                // (`applyChartDataPointSet`) because Swift allocates
                // locals for ALL cases of a `switch` at function
                // entry — inlining the ChartPointLocation /
                // ChartConfig handling here bloats executeStatement's
                // stack frame enough to push deeply-recursive scripts
                // (e.g. nested-if handlers) past the test thread's
                // guard page. Keeping it in a leaf helper confines
                // those locals to that helper's own, shallow frame.
                if case .chartDataPointRef = targetExpr {
                    try await applyChartDataPointSet(
                        property: property,
                        target: targetExpr,
                        value: value,
                        env: &env,
                        document: &document,
                        context: context
                    )
                    break
                }
                // Try to resolve target as an object reference
                if case .objectRef(let ref) = targetExpr {
                    // Handle scene node property setting via SceneSpec (sprite, label, shape, etc.)
                    // If the node isn't found, fall through to try as a Part (handles ambiguous
                    // types like "video" which can be both a scene node and a card-level Part).
                    let sceneNodeTypes = ["sprite", "label", "shape", "emitter", "audio", "tilemap", "camera", "video", "crop", "effect", "light", "group"]
                    var handledAsNode = false
                    if sceneNodeTypes.contains(ref.objectType) {
                        let nodeName = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                        if let location = nodeLocation(
                            named: nodeName,
                            objectType: ref.objectType,
                            document: document,
                            currentCardId: context.currentCardId
                        ) {
                            _ = mutateActiveScene(partIndex: location.partIndex, document: &document) { spec in
                                _ = spec.updateNode(id: location.node.id) { node in
                                    applyNodePropertySet(property: property, value: value, to: &node)
                                }
                            }
                            handledAsNode = true
                        }
                    }
                    if !handledAsNode && ref.objectType == "scene" {
                        let sceneName = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                        if let location = sceneLocation(named: sceneName, document: document, currentCardId: context.currentCardId) {
                            _ = mutateSpriteAreaSpec(partIndex: location.partIndex, document: &document) { areaSpec in
                                if let index = areaSpec.scenes.firstIndex(where: { $0.scene.name.lowercased() == sceneName.lowercased() }) {
                                    switch property.lowercased() {
                                    case "name":
                                        areaSpec.scenes[index].scene.name = value
                                    case "backgroundcolor":
                                        areaSpec.scenes[index].scene.backgroundColor = value
                                    case "gravity":
                                        let comps = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                                        if comps.count >= 2 {
                                            areaSpec.scenes[index].scene.gravity = VectorSpec(dx: comps[0], dy: comps[1])
                                        }
                                    case "paused", "ispaused":
                                        areaSpec.scenes[index].scene.isPaused = isTruthy(value)
                                    case "width":
                                        areaSpec.scenes[index].scene.size.width = Double(value) ?? areaSpec.scenes[index].scene.size.width
                                    case "height":
                                        areaSpec.scenes[index].scene.size.height = Double(value) ?? areaSpec.scenes[index].scene.size.height
                                    default:
                                        break
                                    }
                                    if areaSpec.scenes[index].id == areaSpec.activeSceneID {
                                        areaSpec.setActiveScene(areaSpec.scenes[index].scene)
                                    }
                                }
                            }
                        }
                    } else if !handledAsNode && ref.objectType == "card" {
                    // Card-level property set:
                    //   `set the background of card "X" to "bgName"`
                    //   `set the theme of card "X" to "Sunset"`
                    //   `set the marked of card "X" to true`
                    //   `set the name of card "X" to "intro"`
                    let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                    let cardIndex = cardIndex(
                        forIdentifier: ident,
                        document: document,
                        currentCardId: context.currentCardId
                    )
                    if let ci = cardIndex {
                        switch property.lowercased() {
                        case "background":
                            if let bg = document.backgroundByName(value) {
                                document.cards[ci].backgroundId = bg.id
                            }
                        case "theme", "themename", "theme_name":
                            // Empty/`the empty` clears the override
                            // and lets the cascade fall through to
                            // background → stack.
                            let trimmed = value.trimmingCharacters(in: .whitespaces)
                            document.cards[ci].themeName = trimmed.isEmpty ? nil : trimmed
                        case "name":
                            document.cards[ci].name = value
                        case "marked":
                            document.cards[ci].marked = isTruthy(value)
                        case "script":
                            document.cards[ci].script = value
                        default:
                            break
                        }
                    }
                    } else if !handledAsNode && ref.objectType == "background" {
                    // Background-level property set:
                    //   `set the theme of background "menu" to "Modern Dark"`
                    //   `set the name of background "menu" to "main_menu"`
                    //   `set the script of background "menu" to "..."`
                    let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                    let bgIndex = backgroundIndex(
                        forIdentifier: ident,
                        document: document,
                        currentCardId: context.currentCardId
                    )
                    if let bi = bgIndex {
                        switch property.lowercased() {
                        case "theme", "themename", "theme_name":
                            let trimmed = value.trimmingCharacters(in: .whitespaces)
                            document.backgrounds[bi].themeName = trimmed.isEmpty ? nil : trimmed
                        case "name":
                            document.backgrounds[bi].name = value
                        case "script":
                            document.backgrounds[bi].script = value
                        default:
                            break
                        }
                    }
                    } else if !handledAsNode && ref.objectType == "stack" {
                    // Stack-level property set: `set the defaultFont of stack to "Helvetica"`
                    switch property.lowercased() {
                    case "name":
                        document.stack.name = value
                    case "defaultfont", "default_font", "textfont", "font":
                        document.stack.defaultFont = value
                    case "aicontextcloudsharingallowed", "ai_context_cloud_sharing_allowed", "contextcloudsharingallowed":
                        document.stack.aiContextCloudSharingAllowed = value.lowercased() == "true"
                    case "theme", "themename", "theme_name":
                        // Empty / `the empty` resets to the built-in
                        // fallback so the cascade always terminates.
                        let trimmed = value.trimmingCharacters(in: .whitespaces)
                        document.stack.themeName = trimmed.isEmpty
                            ? BuiltInThemes.fallbackName
                            : trimmed
                    default:
                        break
                    }
                    } else if !handledAsNode {
                    let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                    if let partIndex = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                        applyPartPropertySet(
                            partIndex: partIndex,
                            property: property,
                            value: value,
                            env: &env,
                            document: &document,
                            context: context
                        )
                    } else {
                        env.setVariable(property, value)
                    }
                    } // close else (non-sprite objectRef)
                } else if case .me = targetExpr {
                    if let partIndex = document.parts.firstIndex(where: { $0.id == context.targetId }) {
                        applyPartPropertySet(
                            partIndex: partIndex,
                            property: property,
                            value: value,
                            env: &env,
                            document: &document,
                            context: context
                        )
                    } else if let spriteTarget = locateSpriteTarget(id: context.targetId, document: document, currentCardId: context.currentCardId) {
                        if let nodeId = spriteTarget.nodeId {
                            _ = mutateActiveScene(partIndex: spriteTarget.partIndex, document: &document) { spec in
                                _ = spec.updateNode(id: nodeId) { node in
                                    applyNodePropertySet(property: property, value: value, to: &node)
                                }
                            }
                        } else {
                            _ = mutateActiveScene(partIndex: spriteTarget.partIndex, document: &document) { scene in
                                switch property.lowercased() {
                                case "name":
                                    scene.name = value
                                case "backgroundcolor":
                                    scene.backgroundColor = value
                                case "gravity":
                                    let comps = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                                    if comps.count >= 2 {
                                        scene.gravity = VectorSpec(dx: comps[0], dy: comps[1])
                                    }
                                case "paused", "ispaused":
                                    scene.isPaused = isTruthy(value)
                                default:
                                    break
                                }
                            }
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
            let destValue = try await evaluate(dest, env: &env, document: document, context: context)
            // Try to resolve destination to a card UUID.
            if let uuid = UUID(uuidString: destValue) {
                navigationTarget = uuid
            } else {
                // Try to find by name or navigation keyword.
                let resolved = resolveNavigation(destValue, document: document, currentCardId: context.currentCardId)
                navigationTarget = resolved
            }

        case .ifThenElse(let cond, let thenBlock, let elseBlock):
            let condValue = try await evaluate(cond, env: &env, document: document, context: context)
            if isTruthy(condValue) {
                for s in thenBlock {
                    try await executeStatement(s, env: &env, document: &document, context: context,
                                         instructionCount: &instructionCount,
                                         navigationTarget: &navigationTarget, handler: handler)
                }
            } else if let elseStmts = elseBlock {
                for s in elseStmts {
                    try await executeStatement(s, env: &env, document: &document, context: context,
                                         instructionCount: &instructionCount,
                                         navigationTarget: &navigationTarget, handler: handler)
                }
            }

        case .repeatCount(let countExpr, let body):
            let countStr = try await evaluate(countExpr, env: &env, document: document, context: context)
            let count = Int(toNumber(countStr))
            for _ in 0..<max(0, count) {
                do {
                    for s in body {
                        try await executeStatement(s, env: &env, document: &document, context: context,
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
                let condValue = try await evaluate(cond, env: &env, document: document, context: context)
                if !isTruthy(condValue) { break }
                do {
                    for s in body {
                        try await executeStatement(s, env: &env, document: &document, context: context,
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
            let fromVal = Int(toNumber(try await evaluate(fromExpr, env: &env, document: document, context: context)))
            let toVal = Int(toNumber(try await evaluate(toExpr, env: &env, document: document, context: context)))
            let step = fromVal <= toVal ? 1 : -1
            var i = fromVal
            while (step > 0 && i <= toVal) || (step < 0 && i >= toVal) {
                env.setVariable(varName, String(i))
                do {
                    for s in body {
                        try await executeStatement(s, env: &env, document: &document, context: context,
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
            let value = try await evaluate(expr, env: &env, document: document, context: context)
            throw ControlSignal.exitHandler(value)

        case .globalDecl(let names):
            for name in names {
                env.globalNames.insert(name.lowercased())
            }

        case .ask(let prompt):
            let promptText = try await evaluate(prompt, env: &env, document: document, context: context)
            let userInput = await context.dialogProvider.showAskAsync(prompt: promptText)
            env.it = userInput

        case .askAI(let prompt, let modelExpr, let callbackExpr):
            let promptText = try await evaluate(prompt, env: &env, document: document, context: context)
            let modelName = try await evaluateOptional(modelExpr, env: &env, document: document, context: context)
            if let callbackExpr, let runtime = context.runtimeProvider {
                let callbackName = try await evaluate(callbackExpr, env: &env, document: document, context: context)
                let requestID = try await runtime.startAIRequest(
                    prompt: promptText,
                    model: modelName,
                    callbackMessage: callbackName,
                    owner: RuntimeOwnerContext(
                        targetId: context.targetId,
                        currentCardId: context.currentCardId,
                        scriptContext: context.scriptContext
                    )
                )
                env.it = requestID.uuidString
            } else {
                env.it = try await generateAIResponse(prompt: promptText, model: modelName, context: context)
            }

        case .askMeshy(let promptExpr, let styleExpr, let modelExpr, let callbackExpr):
            // Phase 3 — `ask meshy "<prompt>" [with style <s>] [with model <m>] [with message <msg>]`
            //
            // Sync form (no callback): blocks until generation completes; sets `it` + `result` to the
            // new asset's name. Async form: fires `startMeshyRequest` and sets `it` to the request UUID.
            // Gate refusal (no provider): degrades gracefully — sets `it = ""`.
            //
            // OQ-C1: both `env.it` and `env.result` are set, matching the `askAI` precedent.
            let promptText = try await evaluate(promptExpr, env: &env, document: document, context: context)
            let styleText = try await evaluateOptional(styleExpr, env: &env, document: document, context: context)
            let modelText = try await evaluateOptional(modelExpr, env: &env, document: document, context: context)

            if let callbackExpr, let runtime = context.runtimeProvider {
                // Async form: hand off to the runtime, return the request UUID in `it`.
                let callbackName = try await evaluate(callbackExpr, env: &env, document: document, context: context)
                let requestID = try await runtime.startMeshyRequest(
                    prompt: promptText,
                    style: styleText,
                    model: modelText,
                    callbackMessage: callbackName,
                    owner: RuntimeOwnerContext(
                        targetId: context.targetId,
                        currentCardId: context.currentCardId,
                        scriptContext: context.scriptContext
                    )
                )
                env.it = requestID.uuidString
            } else if let provider = context.meshyProvider {
                // Sync form: block until the provider generates the asset.
                let assetName = try await provider.generateSync(
                    prompt: promptText,
                    style: styleText,
                    model: modelText,
                    document: document
                )
                env.it = assetName
                env.result = assetName
            } else {
                // No provider — degrade gracefully.
                env.it = ""
                env.result = ""
            }

        case .answer(let prompt):
            let promptText = try await evaluate(prompt, env: &env, document: document, context: context)
            let response = await context.dialogProvider.showAnswerAsync(prompt: promptText)
            env.it = response

        case .say(let prompt):
            let promptText = try await evaluate(prompt, env: &env, document: document, context: context)
            await context.speechOutputProvider.speakScriptText(promptText, source: "HypeTalk say")
            env.it = promptText

        case .activateListener(let activeExpr):
            let activeValue = try await evaluate(activeExpr, env: &env, document: document, context: context)
            try await setSpeechListenerActive(activeValue, context: context, handler: handler)
            env.it = isTruthy(activeValue) ? "true" : "false"

        case .visual(let effectExpr, let durationExpr):
            // Record the requested visual effect name (and optional
            // duration) so the presentation layer can apply it as a
            // SpriteKit transition on the next card navigation.
            let effectName = try await evaluate(effectExpr, env: &env, document: document, context: context)
            env.locals["_visualEffect"] = effectName
            if let durExpr = durationExpr {
                let dur = try await evaluate(durExpr, env: &env, document: document, context: context)
                env.locals["_visualEffectDuration"] = dur
            }

        case .expressionStatement(let expr):
            _ = try await evaluate(expr, env: &env, document: document, context: context)

        case .doBlock(let expr):
            let scriptText = try await evaluate(expr, env: &env, document: document, context: context)
            // Simplified: parse and execute inline. Not fully implemented.
            _ = scriptText

        case .createCard(let bgNameExpr):
            var bgName: String? = nil
            if let expr = bgNameExpr {
                bgName = try await evaluate(expr, env: &env, document: document, context: context)
            }
            let newCard = document.addCard(
                afterIndex: document.sortedCards.firstIndex(where: { $0.id == context.currentCardId }),
                backgroundName: bgName
            )
            navigationTarget = newCard.id

        case .createBackground(let nameExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let _ = document.addBackground(name: name)

        case .createButton(let nameExpr, let onBackground):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            var part: Part
            if onBackground {
                let bgId = document.cards.first(where: { $0.id == context.currentCardId })?.backgroundId
                part = Part(partType: .button, backgroundId: bgId, name: name)
            } else {
                part = Part(partType: .button, cardId: context.currentCardId, name: name)
            }
            let stackFont = document.stack.defaultFont
            if !stackFont.isEmpty { part.textFont = stackFont }
            document.addPart(part)

        case .createField(let nameExpr, let onBackground):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            var part: Part
            if onBackground {
                let bgId = document.cards.first(where: { $0.id == context.currentCardId })?.backgroundId
                part = Part(partType: .field, backgroundId: bgId, name: name)
            } else {
                part = Part(partType: .field, cardId: context.currentCardId, name: name)
            }
            let stackFont = document.stack.defaultFont
            if !stackFont.isEmpty { part.textFont = stackFont }
            document.addPart(part)

        case .showAllCards:
            // Signal the UI to cycle through all cards with animation.
            // The actual cycling is handled by the UI layer since it requires timed delays.
            throw ControlSignal.showAllCards

        case .addTo(let valueExpr, let targetExpr):
            let value = try await evaluate(valueExpr, env: &env, document: document, context: context)
            if case .variable(let name) = targetExpr {
                let existing = env.getVariable(name)
                env.setVariable(name, formatNumber(toNumber(existing) + toNumber(value)))
            } else if case .objectRef(let ref) = targetExpr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    let existing = document.parts[idx].textContent
                    document.parts[idx].textContent = formatNumber(toNumber(existing) + toNumber(value))
                }
            }

        case .subtractFrom(let valueExpr, let targetExpr):
            let value = try await evaluate(valueExpr, env: &env, document: document, context: context)
            if case .variable(let name) = targetExpr {
                let existing = env.getVariable(name)
                env.setVariable(name, formatNumber(toNumber(existing) - toNumber(value)))
            }

        case .multiplyBy(let targetExpr, let valueExpr):
            let value = try await evaluate(valueExpr, env: &env, document: document, context: context)
            if case .variable(let name) = targetExpr {
                let existing = env.getVariable(name)
                env.setVariable(name, formatNumber(toNumber(existing) * toNumber(value)))
            }

        case .divideBy(let targetExpr, let valueExpr):
            let value = try await evaluate(valueExpr, env: &env, document: document, context: context)
            if case .variable(let name) = targetExpr {
                let existing = env.getVariable(name)
                let divisor = toNumber(value)
                env.setVariable(name, divisor != 0 ? formatNumber(toNumber(existing) / divisor) : "INF")
            }

        case .deleteObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    document.parts.remove(at: idx)
                }
            }

        case .findText(let expr):
            // Stub: find is complex — for now store the search text in `it`.
            let text = try await evaluate(expr, env: &env, document: document, context: context)
            env.it = text

        case .selectObject:
            break // UI operation — stub

        case .sortCards(let byExpr):
            // Sort cards by evaluating the expression for each card.
            let _ = try await evaluate(byExpr, env: &env, document: document, context: context)
            // Complex — stub for now

        case .hideObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    document.parts[idx].visible = false
                }
            }

        case .showObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    document.parts[idx].visible = true
                }
            }

        case .lockScreen, .unlockScreen:
            break // UI operation — stub

        case .openStack:
            break // Complex — stub

        case .send(let messageExpr, let targetExpr):
            guard context.nestedSendDepth < 32 else {
                throw ScriptError(message: "Nested send depth exceeded", line: handler.line, handler: handler.name)
            }
            let message = try await evaluate(messageExpr, env: &env, document: document, context: context)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                throw ScriptError(message: "Cannot send an empty message", line: handler.line, handler: handler.name)
            }
            guard let targetID = try await resolveSendTarget(
                targetExpr,
                env: &env,
                document: document,
                context: context
            ) else {
                throw ScriptError(message: "Cannot resolve send target", line: handler.line, handler: handler.name)
            }

            document.scriptGlobals = env.globals
            let result = await MessageDispatcher().dispatchAsync(
                message: message,
                params: [],
                targetId: targetID,
                document: document,
                currentCardId: context.currentCardId,
                dialogProvider: context.dialogProvider,
                drawingProvider: context.drawingProvider,
                aiProvider: context.aiProvider,
                speechOutputProvider: context.speechOutputProvider,
                appScript: context.appScript,
                mouseX: context.mouseX,
                mouseY: context.mouseY,
                scriptContext: context.scriptContext,
                runtimeProvider: context.runtimeProvider,
                nestedSendDepth: context.nestedSendDepth + 1
            )
            if let modifiedDocument = result.modifiedDocument {
                document = modifiedDocument
                env.globals = modifiedDocument.scriptGlobals
            }
            if let resultNavigationTarget = result.navigationTarget {
                navigationTarget = resultNavigationTarget
            }
            if let visualEffect = result.visualEffect {
                env.locals["_visualEffect"] = visualEffect
            }
            if let visualEffectDuration = result.visualEffectDuration {
                env.locals["_visualEffectDuration"] = String(visualEffectDuration)
            }
            if result.showAllCards {
                throw ControlSignal.showAllCards
            }
            if result.status == .error {
                throw result.error ?? ScriptError(
                    message: "Send failed",
                    line: handler.line,
                    handler: handler.name
                )
            }

        case .playSound(let soundExpr, let notesExpr, let tempoExpr):
            let soundName = try await evaluate(soundExpr, env: &env, document: document, context: context)
            #if canImport(AppKit)
            // `SoundPlayer` is @MainActor-isolated because
            // `NSSoundDelegate` methods fire synchronously on whichever
            // thread called `stop()` — and those methods are @MainActor
            // in modern AppKit. The Interpreter runs on a cooperative
            // task thread, so we must hop before any play/stop call.
            // Capturing the document inside the closure via a local
            // let keeps the isolation transfer safe.
            let capturedDocument = document
            if let notesExprVal = notesExpr {
                let noteString = try await evaluate(notesExprVal, env: &env, document: document, context: context)
                let tempo: Int
                if let tExpr = tempoExpr {
                    tempo = Int(toNumber(try await evaluate(tExpr, env: &env, document: document, context: context)))
                } else {
                    tempo = 120
                }
                await MainActor.run {
                    SoundPlayer.shared.playNotes(instrument: soundName, noteString: noteString, tempo: tempo, document: capturedDocument)
                }
            } else {
                await MainActor.run {
                    SoundPlayer.shared.play(name: soundName, document: capturedDocument)
                }
            }
            #endif

        case .playStop:
            #if canImport(AppKit)
            await MainActor.run {
                SoundPlayer.shared.stop()
            }
            #endif

        case .beep(let countExpr):
            #if canImport(AppKit)
            let count: Int
            if let expr = countExpr {
                count = max(1, Int(toNumber(try await evaluate(expr, env: &env, document: document, context: context))))
            } else {
                count = 1
            }
            // NSSound.beep() is @MainActor in modern AppKit SDKs; hop
            // to main so it can be invoked from the interpreter's
            // cooperative task thread without an executor assertion.
            await MainActor.run {
                for _ in 0..<count {
                    NSSound.beep()
                }
            }
            #endif

        case .waitDuration(let expr):
            let val = try await evaluate(expr, env: &env, document: document, context: context)
            let seconds = toNumber(val)
            if seconds > 0 {
                if let runtime = context.runtimeProvider {
                    try await runtime.sleep(seconds: min(seconds, 300))
                } else {
                    try await sleepOutsideRuntime(seconds: min(seconds, 300))
                }
            }

        case .waitUntil(let condition):
            // Poll the condition every 50ms, cap at 30 seconds.
            let maxWait = 30.0
            let start = Date()
            while Date().timeIntervalSince(start) < maxWait {
                let condVal = try await evaluate(condition, env: &env, document: document, context: context)
                if isTruthy(condVal) { break }
                if let runtime = context.runtimeProvider {
                    try await runtime.sleep(seconds: 0.05)
                } else {
                    try await sleepOutsideRuntime(seconds: 0.05)
                }
            }

        // Animation
        case .animateProperty(let property, let targetExpr, let toValueExpr, let durationExpr):
            let toValueStr = try await evaluate(toValueExpr, env: &env, document: document, context: context)
            let durationVal = toNumber(try await evaluate(durationExpr, env: &env, document: document, context: context))

            // Resolve the target part
            if case .objectRef(let ref) = targetExpr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let partIndex = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                    let part = document.parts[partIndex]
                    let prop = property.lowercased()

                    #if canImport(AppKit)
                    if prop == "loc" || prop == "location" {
                        // Point animation: parse current loc and target loc
                        let currentX = part.left + part.width / 2
                        let currentY = part.top + part.height / 2
                        let components = toValueStr.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                        if components.count >= 2 {
                            PartAnimator.shared.animate(
                                partId: part.id,
                                property: "loc",
                                fromValue: currentX,
                                toValue: components[0],
                                fromValueY: currentY,
                                toValueY: components[1],
                                duration: durationVal
                            )
                        }
                    } else {
                        // Scalar animation (left, top, width, height, rotation)
                        let fromValue: Double
                        switch prop {
                        case "left":     fromValue = part.left
                        case "top":      fromValue = part.top
                        case "width":    fromValue = part.width
                        case "height":   fromValue = part.height
                        case "rotation": fromValue = part.rotation
                        default:         fromValue = 0
                        }
                        let toVal = toNumber(toValueStr)
                        PartAnimator.shared.animate(
                            partId: part.id,
                            property: prop,
                            fromValue: fromValue,
                            toValue: toVal,
                            duration: durationVal
                        )
                    }
                    #endif
                }
            } else if case .me = targetExpr,
                      let partIndex = document.parts.firstIndex(where: { $0.id == context.targetId }) {
                let part = document.parts[partIndex]
                let prop = property.lowercased()
                #if canImport(AppKit)
                if prop == "loc" || prop == "location" {
                    let currentX = part.left + part.width / 2
                    let currentY = part.top + part.height / 2
                    let components = toValueStr.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                    if components.count >= 2 {
                        PartAnimator.shared.animate(
                            partId: part.id, property: "loc",
                            fromValue: currentX, toValue: components[0],
                            fromValueY: currentY, toValueY: components[1],
                            duration: durationVal
                        )
                    }
                } else {
                    let fromValue: Double
                    switch prop {
                    case "left":     fromValue = part.left
                    case "top":      fromValue = part.top
                    case "width":    fromValue = part.width
                    case "height":   fromValue = part.height
                    case "rotation": fromValue = part.rotation
                    default:         fromValue = 0
                    }
                    PartAnimator.shared.animate(
                        partId: part.id, property: prop,
                        fromValue: fromValue, toValue: toNumber(toValueStr),
                        duration: durationVal
                    )
                }
                #endif
            }

        // Phase 2: Implemented commands

        case .chooseTool(let expr):
            let toolName = try await evaluate(expr, env: &env, document: document, context: context)
            env.it = toolName

        case .markCard(let expr):
            if let cardExpr = expr {
                let ident = try await evaluate(cardExpr, env: &env, document: document, context: context)
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
                let ident = try await evaluate(cardExpr, env: &env, document: document, context: context)
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
            let text = try await evaluate(expr, env: &env, document: document, context: context)
            env.it = text

        case .convert(let sourceExpr, let targetExpr):
            let _ = try await evaluate(sourceExpr, env: &env, document: document, context: context)
            let _ = try await evaluate(targetExpr, env: &env, document: document, context: context)
            // Stub: conversion between date/time formats not yet implemented

        case .closeWindow, .saveStack, .quitApp, .editScriptOf:
            break // UI operations — stubs requiring platform integration

        case .dragFrom(let fromExpr, let toExpr):
            let fromVal = try await evaluate(fromExpr, env: &env, document: document, context: context)
            let toVal = try await evaluate(toExpr, env: &env, document: document, context: context)
            let fromParts = fromVal.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let toParts = toVal.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if fromParts.count >= 2 && toParts.count >= 2 {
                let x0 = Int(Double(fromParts[0]) ?? 0)
                let y0 = Int(Double(fromParts[1]) ?? 0)
                let x1 = Int(Double(toParts[0]) ?? 0)
                let y1 = Int(Double(toParts[1]) ?? 0)
                let radius = Int(toNumber(env.getVariable("pencilsize")))
                let colorHex = env.getVariable("pencilcolor")
                await context.drawingProvider.drawLineAsync(from: (x0, y0), to: (x1, y1),
                                                            radius: max(1, radius == 0 ? 2 : radius),
                                                            colorHex: colorHex.isEmpty ? "#000000" : colorHex)
            }

        case .requestURL(let urlExpr, let methodExpr, let headersExpr, let bodyExpr, let usernameExpr, let passwordExpr, let callbackExpr):
            guard let runtime = context.runtimeProvider else {
                throw ScriptError(message: "Network runtime is unavailable", line: handler.line, handler: handler.name)
            }
            let url = try await evaluate(urlExpr, env: &env, document: document, context: context)
            let method = try await evaluateOptional(methodExpr, env: &env, document: document, context: context) ?? "GET"
            let headers = try await evaluateOptional(headersExpr, env: &env, document: document, context: context) ?? ""
            let body = try await evaluateOptional(bodyExpr, env: &env, document: document, context: context) ?? ""
            let username = try await evaluateOptional(usernameExpr, env: &env, document: document, context: context)
            let password = try await evaluateOptional(passwordExpr, env: &env, document: document, context: context)
            let callback = try await evaluateOptional(callbackExpr, env: &env, document: document, context: context)
            let id = try await runtime.startHTTPRequest(
                OutboundHTTPRequestSpec(url: url, method: method, headersText: headers, body: body, username: username, password: password, callbackMessage: callback),
                owner: RuntimeOwnerContext(targetId: context.targetId, currentCardId: context.currentCardId, scriptContext: context.scriptContext)
            )
            env.it = id.uuidString

        case .replyRequest(let requestExpr, let statusExpr, let headersExpr, let bodyExpr):
            guard let runtime = context.runtimeProvider else {
                throw ScriptError(message: "Network runtime is unavailable", line: handler.line, handler: handler.name)
            }
            let requestID = UUID(uuidString: try await evaluate(requestExpr, env: &env, document: document, context: context))
            guard let requestID else {
                throw ScriptError(message: "Invalid request handle", line: handler.line, handler: handler.name)
            }
            let status = Int(toNumber(try await evaluate(statusExpr, env: &env, document: document, context: context)))
            let headers = try await evaluateOptional(headersExpr, env: &env, document: document, context: context) ?? ""
            let body = try await evaluateOptional(bodyExpr, env: &env, document: document, context: context) ?? ""
            try await runtime.reply(to: requestID, status: status, headersText: headers, body: body)
            env.it = requestID.uuidString

        case .listenHTTP(let portExpr, let hostExpr, let methodExpr, let pathExpr, let callbackExpr):
            guard let runtime = context.runtimeProvider else {
                throw ScriptError(message: "Network runtime is unavailable", line: handler.line, handler: handler.name)
            }
            let port = Int(toNumber(try await evaluate(portExpr, env: &env, document: document, context: context)))
            let host = try await evaluateOptional(hostExpr, env: &env, document: document, context: context) ?? "127.0.0.1"
            let method = try await evaluateOptional(methodExpr, env: &env, document: document, context: context)
            let path = try await evaluateOptional(pathExpr, env: &env, document: document, context: context)
            let callback = try await evaluate(callbackExpr, env: &env, document: document, context: context)
            let listenerID = try await runtime.startListener(
                ListenerSpec(transport: .http, host: host, port: port, bindScope: .loopback, callbackMessage: callback, httpMethod: method, httpPath: path),
                owner: RuntimeOwnerContext(targetId: context.targetId, currentCardId: context.currentCardId, scriptContext: context.scriptContext)
            )
            env.it = listenerID.uuidString

        case .listenTCP(let portExpr, let hostExpr, let callbackExpr):
            guard let runtime = context.runtimeProvider else {
                throw ScriptError(message: "Network runtime is unavailable", line: handler.line, handler: handler.name)
            }
            let port = Int(toNumber(try await evaluate(portExpr, env: &env, document: document, context: context)))
            let host = try await evaluateOptional(hostExpr, env: &env, document: document, context: context) ?? "127.0.0.1"
            let callback = try await evaluate(callbackExpr, env: &env, document: document, context: context)
            let listenerID = try await runtime.startListener(
                ListenerSpec(transport: .tcp, host: host, port: port, bindScope: .loopback, callbackMessage: callback),
                owner: RuntimeOwnerContext(targetId: context.targetId, currentCardId: context.currentCardId, scriptContext: context.scriptContext)
            )
            env.it = listenerID.uuidString

        case .connectTCP(let hostExpr, let portExpr, let tlsExpr, let callbackExpr):
            guard let runtime = context.runtimeProvider else {
                throw ScriptError(message: "Network runtime is unavailable", line: handler.line, handler: handler.name)
            }
            let host = try await evaluate(hostExpr, env: &env, document: document, context: context)
            let port = Int(toNumber(try await evaluate(portExpr, env: &env, document: document, context: context)))
            let tlsValue = try await evaluateOptional(tlsExpr, env: &env, document: document, context: context)
            let tls = tlsValue.map(isTruthy) ?? false
            let callback = try await evaluate(callbackExpr, env: &env, document: document, context: context)
            let connectionID = try await runtime.connectTCP(
                TCPConnectionSpec(host: host, port: port, tls: tls, callbackMessage: callback),
                owner: RuntimeOwnerContext(targetId: context.targetId, currentCardId: context.currentCardId, scriptContext: context.scriptContext)
            )
            env.it = connectionID.uuidString

        case .sendToConnection(let dataExpr, let connectionExpr):
            guard let runtime = context.runtimeProvider else {
                throw ScriptError(message: "Network runtime is unavailable", line: handler.line, handler: handler.name)
            }
            let data = try await evaluate(dataExpr, env: &env, document: document, context: context)
            let connectionID = UUID(uuidString: try await evaluate(connectionExpr, env: &env, document: document, context: context))
            guard let connectionID else {
                throw ScriptError(message: "Invalid connection handle", line: handler.line, handler: handler.name)
            }
            try await runtime.send(data, toConnection: connectionID)
            env.it = connectionID.uuidString

        case .closeConnection(let connectionExpr):
            guard let runtime = context.runtimeProvider else { break }
            if let connectionID = UUID(uuidString: try await evaluate(connectionExpr, env: &env, document: document, context: context)) {
                await runtime.closeConnection(connectionID)
                env.it = connectionID.uuidString
            }

        case .stopListener(let listenerExpr):
            guard let runtime = context.runtimeProvider else { break }
            if let listenerID = UUID(uuidString: try await evaluate(listenerExpr, env: &env, document: document, context: context)) {
                await runtime.stopListener(listenerID)
                env.it = listenerID.uuidString
            }

        // MARK: SpriteKit commands

        case .createSpriteArea(let nameExpr, let rectExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            var newPart = Part(partType: .spriteArea, cardId: context.currentCardId, name: name)
            if let rExpr = rectExpr {
                let rectStr = try await evaluate(rExpr, env: &env, document: document, context: context)
                let comps = rectStr.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                if comps.count >= 4 {
                    newPart.left = comps[0]
                    newPart.top = comps[1]
                    newPart.width = comps[2]
                    newPart.height = comps[3]
                }
            } else {
                newPart.width = 400
                newPart.height = 300
            }
            let defaultAreaSpec = SpriteAreaSpec(
                defaultSceneNamed: name,
                fallbackSize: SizeSpec(width: newPart.width, height: newPart.height)
            )
            newPart.setSpriteAreaSpec(defaultAreaSpec)
            document.addPart(newPart)

        case .createSpriteScene(let nameExpr, let inAreaExpr, let widthExpr, let heightExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let areaName = inAreaExpr != nil
                ? try await evaluate(inAreaExpr!, env: &env, document: document, context: context)
                : nil
            if let idx = resolveSpriteAreaPartIndex(named: areaName, document: document, currentCardId: context.currentCardId) {
                let width = widthExpr != nil
                    ? toNumber(try await evaluate(widthExpr!, env: &env, document: document, context: context))
                    : nil
                let height = heightExpr != nil
                    ? toNumber(try await evaluate(heightExpr!, env: &env, document: document, context: context))
                    : nil
                _ = mutateSpriteAreaSpec(partIndex: idx, document: &document) { areaSpec in
                    let fallbackSize = SizeSpec(
                        width: width ?? areaSpec.designSize.width,
                        height: height ?? areaSpec.designSize.height
                    )
                    let template = areaSpec.activeScene ?? SceneSpec(size: fallbackSize, scaleMode: areaSpec.scaleMode)
                    var entry = areaSpec.addScene(named: name, basedOn: template)
                    var scene = entry.scene
                    if let width { scene.size.width = width }
                    if let height { scene.size.height = height }
                    scene.scaleMode = areaSpec.scaleMode
                    scene.showsPhysics = areaSpec.showsPhysics
                    scene.showsFPS = areaSpec.showsFPS
                    scene.showsNodeCount = areaSpec.showsNodeCount
                    entry.scene = scene
                    if let entryIndex = areaSpec.scenes.firstIndex(where: { $0.id == entry.id }) {
                        areaSpec.scenes[entryIndex] = entry
                    }
                    areaSpec.activeSceneID = entry.id
                    areaSpec.setActiveScene(scene)
                }
            }

        case .createGroup(let nameExpr, let parentExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let parentName = parentExpr != nil
                ? try await evaluate(parentExpr!, env: &env, document: document, context: context)
                : nil
            if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: idx, document: &document) { spec in
                    let newNode = HypeNodeSpec(name: name, nodeType: .group, position: PointSpec(x: 0, y: 0))
                    if let parentName {
                        if !Self.addNodeToParent(node: newNode, parentName: parentName, nodes: &spec.nodes) {
                            spec.nodes.append(newNode)
                        }
                    } else {
                        spec.nodes.append(newNode)
                    }
                }
            }

        case .createShape(let nameExpr, let sceneExpr, let shapeTypeExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let shapeTypeName = shapeTypeExpr != nil
                ? try await evaluate(shapeTypeExpr!, env: &env, document: document, context: context)
                : "rect"
            let shapeType = SpriteShapeType.tolerantValue(shapeTypeName, default: .rect)
            let parentGroupName: String?
            let partIndex: Int?
            if let sExpr = sceneExpr {
                let targetName = try await evaluate(sExpr, env: &env, document: document, context: context)
                let areaIndex = resolveSpriteAreaPartIndex(
                    named: targetName,
                    document: document,
                    currentCardId: context.currentCardId
                )
                if let ai = areaIndex {
                    partIndex = ai
                    parentGroupName = nil
                } else {
                    partIndex = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId)
                    parentGroupName = targetName
                }
            } else {
                partIndex = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId)
                parentGroupName = nil
            }
            if let idx = partIndex {
                _ = mutateActiveScene(partIndex: idx, document: &document) { spec in
                    let newNode = HypeNodeSpec(
                        name: name,
                        nodeType: .shape,
                        size: SizeSpec(width: 50, height: 50),
                        shapeSpec: ShapeNodeSpec(shapeType: shapeType)
                    )
                    if let groupName = parentGroupName {
                        if !Self.addNodeToParent(node: newNode, parentName: groupName, nodes: &spec.nodes) {
                            spec.nodes.append(newNode)
                        }
                    } else {
                        spec.nodes.append(newNode)
                    }
                }
            }

        case .createSprite(let nameExpr, let sceneExpr, let assetExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let parentGroupName: String?
            let partIndex: Int?
            if let sExpr = sceneExpr {
                let targetName = try await evaluate(sExpr, env: &env, document: document, context: context)
                // First check if it matches a sprite area name
                let areaIndex = resolveSpriteAreaPartIndex(
                    named: targetName,
                    document: document,
                    currentCardId: context.currentCardId
                )
                if let ai = areaIndex {
                    partIndex = ai
                    parentGroupName = nil
                } else {
                    // Treat as a parent group name within the first sprite area
                    partIndex = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId)
                    parentGroupName = targetName
                }
            } else {
                partIndex = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId)
                parentGroupName = nil
            }
            let assetName = assetExpr != nil
                ? try await evaluate(assetExpr!, env: &env, document: document, context: context)
                : nil
            let spriteAsset: (assetRef: AssetRef, size: SizeSpec)? = {
                guard let assetName,
                      let asset = document.spriteRepository.asset(byName: assetName) else {
                    return nil
                }
                return (
                    assetRef: document.spriteRepository.assetRef(for: asset),
                    size: SizeSpec(width: Double(asset.width), height: Double(asset.height))
                )
            }()
            if let idx = partIndex {
                _ = mutateActiveScene(partIndex: idx, document: &document) { spec in
                    var newNode = HypeNodeSpec(name: name, nodeType: .sprite)
                    if let spriteAsset {
                        newNode.assetRef = spriteAsset.assetRef
                        newNode.size = spriteAsset.size
                    }
                    if let groupName = parentGroupName {
                        if !Self.addNodeToParent(node: newNode, parentName: groupName, nodes: &spec.nodes) {
                            spec.nodes.append(newNode)
                        }
                    } else {
                        spec.nodes.append(newNode)
                    }
                }
            }

        case .removeSpriteNode(let expr):
            let name = try await evaluate(expr, env: &env, document: document, context: context)
            if let areaIndex = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: areaIndex, document: &document) { spec in
                    if let node = spec.node(named: name) {
                        _ = spec.removeNode(id: node.id)
                    }
                }
            }

        case .pauseScene(let expr):
            let sceneName = expr != nil ? try await evaluate(expr!, env: &env, document: document, context: context) : nil
            if let sceneName,
               let location = sceneLocation(named: sceneName, document: document, currentCardId: context.currentCardId) {
                _ = mutateSpriteAreaSpec(partIndex: location.partIndex, document: &document) { areaSpec in
                    if let index = areaSpec.scenes.firstIndex(where: { $0.scene.name.lowercased() == sceneName.lowercased() }) {
                        areaSpec.scenes[index].scene.isPaused = true
                        if areaSpec.scenes[index].id == areaSpec.activeSceneID {
                            areaSpec.setActiveScene(areaSpec.scenes[index].scene)
                        }
                    }
                }
            } else if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: idx, document: &document) { $0.isPaused = true }
            }

        case .resumeScene(let expr):
            let sceneName = expr != nil ? try await evaluate(expr!, env: &env, document: document, context: context) : nil
            if let sceneName,
               let location = sceneLocation(named: sceneName, document: document, currentCardId: context.currentCardId) {
                _ = mutateSpriteAreaSpec(partIndex: location.partIndex, document: &document) { areaSpec in
                    if let index = areaSpec.scenes.firstIndex(where: { $0.scene.name.lowercased() == sceneName.lowercased() }) {
                        areaSpec.scenes[index].scene.isPaused = false
                        if areaSpec.scenes[index].id == areaSpec.activeSceneID {
                            areaSpec.setActiveScene(areaSpec.scenes[index].scene)
                        }
                    }
                }
            } else if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: idx, document: &document) { $0.isPaused = false }
            }

        case .runSpriteAction(let actionExpr, let nodeExpr):
            let actionName = try await evaluate(actionExpr, env: &env, document: document, context: context)
            let nodeName: String
            if case .objectRef(let ref) = nodeExpr {
                nodeName = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            } else {
                nodeName = try await evaluate(nodeExpr, env: &env, document: document, context: context)
            }
            if let location = nodeLocation(named: nodeName, document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: location.partIndex, document: &document) { spec in
                    guard spec.node(id: location.node.id) != nil else { return }
                    // Parse simple action description: "moveTo x:200 y:300" or just a name
                    var action = ActionSpec(actionType: .moveTo, name: actionName)
                    let parts = actionName.lowercased().split(separator: " ").map(String.init)
                    if let actionType = ActionType(rawValue: parts.first ?? "") {
                        action.actionType = actionType
                        for index in stride(from: 1, to: parts.count, by: 2) {
                            if index + 1 < parts.count {
                                action.parameters[parts[index]] = parts[index + 1]
                            }
                        }
                    }
                    _ = spec.updateNode(id: location.node.id) { $0.actions.append(action) }
                }
            }

        case .applyForce(let nodeExpr, let forceExpr):
            let forceVal = try await evaluate(forceExpr, env: &env, document: document, context: context)
            let comps = forceVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if comps.count >= 2 {
                let resolvedName: String
                if case .objectRef(let ref) = nodeExpr {
                    resolvedName = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                } else {
                    resolvedName = try await evaluate(nodeExpr, env: &env, document: document, context: context)
                }
                if let location = nodeLocation(named: resolvedName, document: document, currentCardId: context.currentCardId) {
                    _ = mutateActiveScene(partIndex: location.partIndex, document: &document) { spec in
                        _ = spec.updateNode(id: location.node.id) { node in
                            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                            let curVx = node.physicsBody?.velocityX ?? 0
                            let curVy = node.physicsBody?.velocityY ?? 0
                            node.physicsBody?.velocityX = curVx + comps[0]
                            node.physicsBody?.velocityY = curVy + comps[1]
                        }
                    }
                }
            }

        case .applyImpulse(let nodeExpr, let impulseExpr):
            let impulseVal = try await evaluate(impulseExpr, env: &env, document: document, context: context)
            let comps = impulseVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if comps.count >= 2 {
                let resolvedName: String
                if case .objectRef(let ref) = nodeExpr {
                    resolvedName = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                } else {
                    resolvedName = try await evaluate(nodeExpr, env: &env, document: document, context: context)
                }
                if let location = nodeLocation(named: resolvedName, document: document, currentCardId: context.currentCardId) {
                    _ = mutateActiveScene(partIndex: location.partIndex, document: &document) { spec in
                        _ = spec.updateNode(id: location.node.id) { node in
                            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                            node.physicsBody?.velocityX = comps[0]
                            node.physicsBody?.velocityY = comps[1]
                        }
                    }
                }
            }

        case .setSpriteNodeProperty(let property, let nodeExpr, let valueExpr):
            let nodeName = try await evaluate(nodeExpr, env: &env, document: document, context: context)
            let value = try await evaluate(valueExpr, env: &env, document: document, context: context)
            if let location = nodeLocation(named: nodeName, document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: location.partIndex, document: &document) { spec in
                    _ = spec.updateNode(id: location.node.id) { node in
                        applyNodePropertySet(property: property, value: value, to: &node)
                    }
                }
            }

        case .createTileMap(let nameExpr, let colsExpr, let rowsExpr, let tileSizeExpr, let tilesetExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let cols = colsExpr != nil ? Int(toNumber(try await evaluate(colsExpr!, env: &env, document: document, context: context))) : 10
            let rows = rowsExpr != nil ? Int(toNumber(try await evaluate(rowsExpr!, env: &env, document: document, context: context))) : 10
            let explicitTileSize: Double? = tileSizeExpr != nil
                ? toNumber(try await evaluate(tileSizeExpr!, env: &env, document: document, context: context))
                : nil
            let tilesetName: String? = tilesetExpr != nil ? try await evaluate(tilesetExpr!, env: &env, document: document, context: context) : nil
            let tileMapAsset: (assetRef: AssetRef, tileColumns: Int, tileWidth: Double, tileHeight: Double, isTileSet: Bool)? = {
                guard let tilesetName,
                      let asset = document.spriteRepository.asset(byName: tilesetName) else {
                    return nil
                }
                return (
                    assetRef: document.spriteRepository.assetRef(for: asset),
                    tileColumns: asset.tileColumns,
                    tileWidth: Double(asset.tileWidth),
                    tileHeight: Double(asset.tileHeight),
                    isTileSet: asset.isTileSet
                )
            }()

            if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: idx, document: &document) { spec in
                    // Default tile size (32) is overridden by the asset
                    // metadata below when the referenced asset is a
                    // classified tile set and the user didn't pass an
                    // explicit `tilesize N`.
                    let initialTileSize = explicitTileSize ?? 32.0
                    var tmSpec = TileMapSpec(columns: cols, rows: rows, tileWidth: initialTileSize, tileHeight: initialTileSize)
                    tmSpec.tileData = Array(repeating: Array(repeating: -1, count: cols), count: rows)
                    if let tileMapAsset {
                        tmSpec.tileSetAssetRef = tileMapAsset.assetRef
                        // If the asset is a classified tileSet, copy its
                        // tile metadata onto the new TileMapSpec. This
                        // is the fix for multi-column tilesets rendering
                        // as a single vertical strip: SceneBridge reads
                        // `tileSetColumns` from the spec to slice the
                        // texture, and before this wire-up it always
                        // defaulted to 1.
                        if tileMapAsset.isTileSet {
                            tmSpec.tileSetColumns = tileMapAsset.tileColumns
                            // Honour the user's explicit `tilesize N` if
                            // they passed one — otherwise pick up the
                            // asset's native tile size so the tilemap
                            // matches the sprite sheet grid exactly.
                            if explicitTileSize == nil {
                                tmSpec.tileWidth = tileMapAsset.tileWidth
                                tmSpec.tileHeight = tileMapAsset.tileHeight
                            }
                        }
                    }
                    var node = HypeNodeSpec(name: name, nodeType: .tileMap, position: PointSpec(x: 0, y: 0))
                    node.tileMapSpec = tmSpec
                    spec.nodes.append(node)
                }
            }

        case .createCamera(let nameExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: idx, document: &document) { spec in
                    let camNode = HypeNodeSpec(name: name, nodeType: .camera, position: PointSpec(x: spec.size.width / 2, y: spec.size.height / 2))
                    spec.nodes.append(camNode)
                }
            }

        case .createJoint(let nameExpr, let typeExpr, let nodeAExpr, let nodeBExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let jointTypeStr = try await evaluate(typeExpr, env: &env, document: document, context: context)
            let nodeAName = try await evaluate(nodeAExpr, env: &env, document: document, context: context)
            let nodeBName = try await evaluate(nodeBExpr, env: &env, document: document, context: context)
            if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: idx, document: &document) { spec in
                    let jType = JointType(rawValue: jointTypeStr.lowercased()) ?? .pin
                    var joint = JointSpec(jointType: jType, nodeA: nodeAName, nodeB: nodeBName)
                    joint.id = UUID()
                    _ = name
                    spec.joints.append(joint)
                }
            }

        case .createConstraint(let typeExpr, let sourceExpr, let targetExpr, let minExpr, let maxExpr):
            let constraintTypeStr = try await evaluate(typeExpr, env: &env, document: document, context: context)
            let sourceName = try await evaluate(sourceExpr, env: &env, document: document, context: context)
            let targetName = try await evaluate(targetExpr, env: &env, document: document, context: context)
            let minVal: Double? = minExpr != nil ? toNumber(try await evaluate(minExpr!, env: &env, document: document, context: context)) : nil
            let maxVal: Double? = maxExpr != nil ? toNumber(try await evaluate(maxExpr!, env: &env, document: document, context: context)) : nil
            if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: idx, document: &document) { spec in
                    let cType = SceneConstraintType(rawValue: constraintTypeStr.lowercased()) ?? .distance
                    let constraint = SceneConstraintSpec(
                        constraintType: cType,
                        sourceNode: sourceName,
                        targetNode: targetName,
                        minDistance: minVal,
                        maxDistance: maxVal
                    )
                    spec.sceneConstraints.append(constraint)
                }
            }

        case .createPhysicsField(let nameExpr, let typeExpr, let strengthExpr, let directionExpr):
            let fieldName = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let fieldTypeStr = try await evaluate(typeExpr, env: &env, document: document, context: context)
            let strength: Double = strengthExpr != nil ? toNumber(try await evaluate(strengthExpr!, env: &env, document: document, context: context)) : 1.0
            let directionValue = directionExpr != nil
                ? try await evaluate(directionExpr!, env: &env, document: document, context: context)
                : nil
            if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: idx, document: &document) { spec in
                    let fType = FieldType(rawValue: fieldTypeStr) ?? .linearGravity
                    var fieldSpec = FieldSpec(fieldType: fType, strength: strength)
                    if let directionValue {
                        let comps = directionValue.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                        if comps.count >= 2 {
                            fieldSpec.direction = PointSpec(x: comps[0], y: comps[1])
                        }
                    }
                    _ = fieldName
                    spec.fields.append(fieldSpec)
                }
            }

        case .openScene(let nameExpr, _, _):
            let sceneName = try await evaluate(nameExpr, env: &env, document: document, context: context)
            if let location = sceneLocation(named: sceneName, document: document, currentCardId: context.currentCardId) {
                _ = mutateSpriteAreaSpec(partIndex: location.partIndex, document: &document) { areaSpec in
                    _ = areaSpec.activateScene(named: sceneName)
                }
            } else if let idx = resolveSpriteAreaPartIndex(document: document, currentCardId: context.currentCardId) {
                _ = mutateSpriteAreaSpec(partIndex: idx, document: &document) { areaSpec in
                    let template = areaSpec.activeScene
                    _ = areaSpec.addScene(named: sceneName, basedOn: template)
                }
            }
            env.it = sceneName

        case .setTile(let colExpr, let rowExpr, let tilemapExpr, let tileIndexExpr):
            let col = Int(toNumber(try await evaluate(colExpr, env: &env, document: document, context: context)))
            let row = Int(toNumber(try await evaluate(rowExpr, env: &env, document: document, context: context)))
            let tilemapName = try await evaluate(tilemapExpr, env: &env, document: document, context: context)
            let tileIndex = Int(toNumber(try await evaluate(tileIndexExpr, env: &env, document: document, context: context)))

            if let location = nodeLocation(named: tilemapName, objectType: "tilemap", document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: location.partIndex, document: &document) { spec in
                    _ = spec.updateNode(id: location.node.id) { node in
                        guard var tmSpec = node.tileMapSpec else { return }
                        while tmSpec.tileData.count <= row {
                            tmSpec.tileData.append(Array(repeating: -1, count: tmSpec.columns))
                        }
                        while tmSpec.tileData[row].count <= col {
                            tmSpec.tileData[row].append(-1)
                        }
                        tmSpec.tileData[row][col] = tileIndex
                        node.tileMapSpec = tmSpec
                    }
                }
            }

        case .fillTileMap(let tilemapExpr, let tileIndexExpr):
            // Paint every cell of the named tile map with the
            // given tile index. Unlike setTile we don't pad
            // tileData — we rebuild it to the full spec
            // dimensions, which is both the shortest path and the
            // safer one for fill operations (no gaps left over
            // from a previously smaller map).
            let tilemapName = try await evaluate(tilemapExpr, env: &env, document: document, context: context)
            let tileIndex = Int(toNumber(try await evaluate(tileIndexExpr, env: &env, document: document, context: context)))
            if let location = nodeLocation(named: tilemapName, objectType: "tilemap", document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: location.partIndex, document: &document) { spec in
                    _ = spec.updateNode(id: location.node.id) { node in
                        guard var tmSpec = node.tileMapSpec else { return }
                        tmSpec.tileData = Array(
                            repeating: Array(repeating: tileIndex, count: tmSpec.columns),
                            count: tmSpec.rows
                        )
                        node.tileMapSpec = tmSpec
                    }
                }
            }

        case .clearTileMap(let tilemapExpr):
            // Syntactic sugar for `fill tilemap "X" with -1`.
            let tilemapName = try await evaluate(tilemapExpr, env: &env, document: document, context: context)
            if let location = nodeLocation(named: tilemapName, objectType: "tilemap", document: document, currentCardId: context.currentCardId) {
                _ = mutateActiveScene(partIndex: location.partIndex, document: &document) { spec in
                    _ = spec.updateNode(id: location.node.id) { node in
                        guard var tmSpec = node.tileMapSpec else { return }
                        tmSpec.tileData = Array(
                            repeating: Array(repeating: -1, count: tmSpec.columns),
                            count: tmSpec.rows
                        )
                        node.tileMapSpec = tmSpec
                    }
                }
            }

        // GIF animation commands
        case .startAnimation(let targetExpr):
            #if canImport(AppKit)
            try await executeStartAnimation(targetExpr: targetExpr, env: &env, document: document, context: context)
            #endif

        case .stopAnimation(let targetExpr):
            #if canImport(AppKit)
            try await executeStopAnimation(targetExpr: targetExpr, env: &env, document: document, context: context)
            #endif

        // Phase 2: Stub commands (recognized but no-op)
        case .push, .pop, .clickAt, .doMenuCmd, .disableCmd, .enableCmd,
             .helpCmd, .debugCmd, .dialCmd, .resetCmd, .printCmd, .readCmd, .writeCmd,
             .runCmd, .startUsing, .stopUsing,
             .copyTemplate, .exportPaint, .importPaint:
            break
        }
    }

    // MARK: - GIF animation helpers

    /// Resolve the image part referenced by `targetExpr` and start
    /// its GIF animation.  Silently ignores non-image parts and
    /// missing image data (early-return, no error per spec §15).
    ///
    /// Dispatches the animator call to main — see the SET case in
    /// `applyPartPropertySet` for the full race-condition rationale
    /// (interpreter runs on background Task; GIFAnimator's Dictionary
    /// is also mutated by main-thread Timer.tick).
    private func executeStartAnimation(
        targetExpr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws {
        guard let partIndex = try await resolveImagePartIndex(targetExpr: targetExpr, env: &env, document: document, context: context) else {
            return
        }
        let part = document.parts[partIndex]
        guard let data = part.imageData else { return }
        #if canImport(AppKit)
        let partId = part.id
        DispatchQueue.main.async {
            GIFAnimator.shared.start(partId: partId, imageData: data)
        }
        #endif
    }

    /// Resolve the image part referenced by `targetExpr` and stop
    /// its GIF animation.  Silently ignores non-image parts (early-return).
    private func executeStopAnimation(
        targetExpr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws {
        guard let partIndex = try await resolveImagePartIndex(targetExpr: targetExpr, env: &env, document: document, context: context) else {
            return
        }
        let part = document.parts[partIndex]
        #if canImport(AppKit)
        let partId = part.id
        DispatchQueue.main.async {
            GIFAnimator.shared.stop(partId: partId)
        }
        #endif
    }

    /// Resolve a `targetExpr` to the index of an image part in
    /// `document.parts`.  Returns `nil` for non-image parts or
    /// unresolvable expressions (bare string, objectRef, or anything
    /// else — all treated gracefully with no error).
    private func resolveImagePartIndex(
        targetExpr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Int? {
        let partIndex: Int?
        switch targetExpr {
        case .objectRef(let ref):
            let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            partIndex = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId)
        default:
            let ident = try await evaluate(targetExpr, env: &env, document: document, context: context)
            partIndex = findPartIndexGeneral(ident, document: document)
        }
        guard let idx = partIndex else { return nil }
        guard document.parts[idx].partType == .image else { return nil }
        return idx
    }

    // MARK: - Expression evaluation

    private func evaluate(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
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
            // Well-known HyperTalk system properties accepted as
            // bare identifiers (no `the` prefix required). Users
            // and AI models routinely write `put mouseLoc into m`
            // or `put ticks into t` rather than the more formal
            // `put the mouseLoc into m`. Fall through to the
            // property evaluator when the variable name matches one
            // of these so the bare form produces the same value as
            // the articled form. A user-declared local or global of
            // the same name takes precedence (checked below via
            // `env.globalNames` / `env.locals` lookups).
            case "mouseloc", "mouseh", "mousev",
                 "date", "time", "ticks", "seconds",
                 "paramcount", "params",
                 "hoveredsprite", "spriteundermouse", "hoveredspritename":
                if !env.locals.keys.contains(name.lowercased())
                    && !env.globalNames.contains(name.lowercased()) {
                    return try await evaluateProperty(
                        name, target: nil,
                        env: &env, document: document, context: context
                    )
                }
            default: break
            }
            return env.getVariable(name)

        case .it:
            return env.it

        case .me:
            return context.targetId.uuidString

        case .this:
            // `this` returns the current part's primary content value:
            // - For fields: textContent (what the user typed)
            // - For popup buttons: textContent (the selected menu item)
            // - For other buttons: name if showName, else textContent
            // - For other parts: name
            if let part = document.parts.first(where: { $0.id == context.targetId }) {
                switch part.partType {
                case .field:
                    return part.textContent
                case .button:
                    if part.buttonStyle == .popup {
                        return part.textContent  // Selected popup item
                    }
                    return part.showName ? part.name : part.textContent
                default:
                    return part.name
                }
            }
            if let spriteTarget = locateSpriteTarget(id: context.targetId, document: document, currentCardId: context.currentCardId) {
                if let nodeId = spriteTarget.nodeId,
                   let scene = activeScene(partIndex: spriteTarget.partIndex, document: document),
                   let node = scene.node(id: nodeId) {
                    return node.name
                }
                if let scene = activeScene(partIndex: spriteTarget.partIndex, document: document) {
                    return scene.name
                }
            }
            return ""

        case .empty:
            return ""

        case .binary(let left, let op, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            return evaluateBinary(lVal, op, rVal)

        case .unary(let op, let operand):
            let val = try await evaluate(operand, env: &env, document: document, context: context)
            switch op {
            case .negate: return String(-toNumber(val))
            case .not:    return isTruthy(val) ? "false" : "true"
            }

        case .await(let expr):
            return try await evaluate(expr, env: &env, document: document, context: context)

        case .not(let operand):
            let val = try await evaluate(operand, env: &env, document: document, context: context)
            return isTruthy(val) ? "false" : "true"

        case .contains(let left, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            return lVal.lowercased().contains(rVal.lowercased()) ? "true" : "false"

        case .stringConcat(let left, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            return lVal + rVal

        case .spacedConcat(let left, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            return lVal + " " + rVal

        case .functionCall(let name, let args):
            var evaluatedArgs: [Value] = []
            for arg in args {
                evaluatedArgs.append(try await evaluate(arg, env: &env, document: document, context: context))
            }
            return try await evaluateBuiltIn(name, args: evaluatedArgs, env: &env, context: context)

        case .propertyAccess(let property, let target):
            return try await evaluateProperty(property, target: target, env: &env, document: document, context: context)

        case .headerAccess(let nameExpr, let target):
            let headerName = try await evaluate(nameExpr, env: &env, document: document, context: context)
            if case .objectRef(let ref) = target {
                let idValue = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let id = UUID(uuidString: idValue), let runtime = context.runtimeProvider {
                    return await runtime.runtimeProperty(objectType: ref.objectType, id: id, property: "header", argument: headerName)
                }
            }
            return ""

        case .chunk(let chunkType, let range, let source):
            let sourceVal = try await evaluate(source, env: &env, document: document, context: context)
            return await evaluateChunk(chunkType, range: range, source: sourceVal, env: &env, document: document, context: context)

        case .objectRef(let ref):
            let identVal = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            return resolveObjectRef(ref.objectType, identifier: identVal, document: document, context: context)

        case .chartDataPointRef:
            // A data-point reference is not a standalone value — it's
            // only meaningful as the `of` target of a propertyAccess
            // or a set statement. Delegated to a leaf helper so its
            // pattern-match bindings don't inflate `evaluate`'s
            // stack frame for every recursive call.
            return try await describeChartDataPointRef(expr, env: &env, document: document, context: context)

        case .tileAt(let colExpr, let rowExpr, let tilemapExpr):
            // Read a tile index from a named tile map at (col,row).
            // Returns "-1" when the cell is out of bounds or empty
            // — scripts can treat that as the "no tile" sentinel.
            // We look only on the current card (like setTile),
            // which mirrors the other tile-map commands' scope.
            let col = Int(toNumber(try await evaluate(colExpr, env: &env, document: document, context: context)))
            let row = Int(toNumber(try await evaluate(rowExpr, env: &env, document: document, context: context)))
            let tilemapName = try await evaluate(tilemapExpr, env: &env, document: document, context: context)
            let cardParts = document.partsForCard(context.currentCardId)
            guard let area = cardParts.first(where: { $0.partType == .spriteArea }),
                  let spec = SceneSpec.fromJSON(area.sceneSpec),
                  let node = spec.nodes.first(where: {
                      $0.name.lowercased() == tilemapName.lowercased() && $0.nodeType == .tileMap
                  }),
                  let tmSpec = node.tileMapSpec
            else {
                return "-1"
            }
            guard row >= 0, row < tmSpec.tileData.count,
                  col >= 0, col < tmSpec.tileData[row].count
            else {
                return "-1"
            }
            return String(tmSpec.tileData[row][col])

        case .isIn(let left, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            return rVal.lowercased().contains(lVal.lowercased()) ? "true" : "false"

        case .isNotIn(let left, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            return rVal.lowercased().contains(lVal.lowercased()) ? "false" : "true"

        case .isWithin(let left, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            let point = lVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            let rect = rVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if point.count >= 2 && rect.count >= 4 {
                let inside = point[0] >= rect[0] && point[0] <= rect[2] && point[1] >= rect[1] && point[1] <= rect[3]
                return inside ? "true" : "false"
            }
            return "false"

        case .isNotWithin(let left, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            let point = lVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            let rect = rVal.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if point.count >= 2 && rect.count >= 4 {
                let inside = point[0] >= rect[0] && point[0] <= rect[2] && point[1] >= rect[1] && point[1] <= rect[3]
                return inside ? "false" : "true"
            }
            return "true"

        case .isA(let expr, let typeName):
            let val = try await evaluate(expr, env: &env, document: document, context: context)
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
            let val = try await evaluate(expr, env: &env, document: document, context: context)
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
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let found = document.parts.contains { $0.name.lowercased() == name.lowercased() }
            return found ? "true" : "false"

        case .thereIsNo(_, let nameExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
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

    private func generateAIResponse(
        prompt: String,
        model: String?,
        context: ExecutionContext
    ) async throws -> Value {
        let response = try await context.aiProvider.generate(prompt: prompt, model: model)
        await context.speechOutputProvider.speakAIResponse(response, source: "HypeTalk AI")
        return response
    }

    // MARK: - Built-in functions

    private func evaluateBuiltIn(
        _ name: String,
        args: [Value],
        env: inout Environment,
        context: ExecutionContext
    ) async throws -> Value {
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

        case "ollama":
            switch args.count {
            case 1:
                return try await generateAIResponse(prompt: args[0], model: nil, context: context)
            case 2:
                return try await generateAIResponse(prompt: args[1], model: args[0], context: context)
            default:
                return ""
            }
        case "aimodel", "ollamamodel":
            return context.aiProvider.currentModel()
        case "aimodels", "ollamamodels":
            return try await context.aiProvider.availableModels().joined(separator: "\n")

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
        case "result": return env.result
        case "param":
            let index = Int(toNumber(args.first ?? "1"))
            return env.handlerParam(at: index)
        case "paramcount":
            return String(env.handlerParams.count)
        case "params":
            return env.joinedHandlerParams

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
            #if canImport(AppKit)
            // SoundPlayer is @MainActor — hop before touching it.
            return await MainActor.run { SoundPlayer.shared.soundName }
            #else
            return "done"
            #endif
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
    ) async throws -> Value {
        let lower = property.lowercased()

        // Global properties (no target).
        if target == nil {
            switch lower {
            case "aimodel", "currentaimodel", "ollamamodel":
                return context.aiProvider.currentModel()
            case "aimodels", "availableaimodels", "ollamamodels":
                return try await context.aiProvider.availableModels().joined(separator: "\n")
            case "activatelistener", "speechlistener", "listeneractive":
                return (await context.runtimeProvider?.isSpeechListenerActive()) == true ? "true" : "false"
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
            case "paramcount":
                return String(env.handlerParams.count)
            case "params":
                return env.joinedHandlerParams
            case "mouseloc", "the mouseloc":
                return "\(formatNumber(context.mouseX)),\(formatNumber(context.mouseY))"
            case "hoveredsprite", "spriteundermouse", "hoveredspritename":
                // Name of the sprite currently under the cursor in
                // the active sprite-area scene — the correct HypeTalk
                // idiom for "is the cursor over a specific sprite?"
                // Replaces the pattern AI models invent
                // (`the name of node at mouse location`), which is
                // unparseable. Empty string when no sprite is under
                // the cursor. Updated by the view layer's
                // mouseWithin dispatch.
                return await MainActor.run {
                    SpriteSceneMouseState.shared.hoveredSprite
                }
            case "mouseh":
                return formatNumber(context.mouseX)
            case "mousev":
                return formatNumber(context.mouseY)
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
            case "sound":
                #if canImport(AppKit)
                // SoundPlayer is @MainActor — hop before touching it.
                return await MainActor.run { SoundPlayer.shared.soundName }
                #else
                return "done"
                #endif
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
            // Phase 3 OQ-C1: `the result` returns the value set by `ask meshy` (and `ask ai`).
            case "result":
                return env.result
            case "brush", "pencilsize":
                let v = env.getVariable("pencilsize")
                return v.isEmpty ? "2" : v
            case "pencilcolor":
                let v = env.getVariable("pencilcolor")
                return v.isEmpty ? "#000000" : v
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

        // `the number of points (of|in) chart "X"` — delegated to
        // a leaf helper so the locals don't bloat evaluateProperty's
        // frame.
        if lower == "numberofpoints" || lower == "number_of_points" {
            return try await numberOfPointsProperty(targetExpr, env: &env, document: document, context: context)
        }
        if let chunkType = chunkCountProperty(lower) {
            let value = try await evaluate(targetExpr, env: &env, document: document, context: context)
            return String(countChunks(chunkType, in: value))
        }

        // Chart data-point reference property get — delegated to a
        // leaf helper for the same stack-frame reason. evaluateProperty
        // is on the hot recursive path; any large local allocated at
        // its function entry multiplies by recursion depth and can
        // overflow the test thread's stack guard page.
        if case .chartDataPointRef = targetExpr {
            return try await getChartDataPointProperty(property, target: targetExpr, env: &env, document: document, context: context)
        }

        if case .objectRef(let ref) = targetExpr,
           ["request", "listener", "connection"].contains(ref.objectType.lowercased()),
           let runtime = context.runtimeProvider {
            let idValue = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            if let id = UUID(uuidString: idValue) {
                return await runtime.runtimeProperty(objectType: ref.objectType, id: id, property: property, argument: nil)
            }
        }

        let targetVal = try await evaluate(targetExpr, env: &env, document: document, context: context)

        // Stack-level properties: `the defaultFont of stack`, `the name of stack`, etc.
        let isStackObjectReference: Bool
        if case .objectRef(let ref) = targetExpr, ref.objectType == "stack" {
            isStackObjectReference = true
        } else {
            isStackObjectReference = false
        }
        if targetVal.lowercased() == "stack" || isStackObjectReference {
            switch lower {
            case "name":        return document.stack.name
            case "defaultfont", "default_font", "textfont", "font":
                return document.stack.defaultFont
            case "width":       return String(document.stack.width)
            case "height":      return String(document.stack.height)
            case "script":      return document.stack.script
            case "aicontextcount", "ai_context_count", "contextcount", "context_count":
                return String(document.aiContextLibrary.itemCount)
            case "aicontextsummary", "ai_context_summary", "contextsummary", "context_summary":
                return document.aiContextLibrary.promptSummary(maxItems: 20)
            case "aicontextcloudsharingallowed", "ai_context_cloud_sharing_allowed", "contextcloudsharingallowed":
                return String(document.stack.aiContextCloudSharingAllowed)
            // Theme is non-optional on the stack — always returns a name.
            case "theme", "themename", "theme_name":
                return document.stack.themeName
            default: break
            }
        }

        // `the themes` — comma-separated list of every available theme
        // name (built-ins + this stack's user themes). No "of <X>"
        // qualifier needed; it's a stack-global accessor like `the
        // backgrounds`.
        if lower == "themes" {
            return document.allThemeNames.joined(separator: ", ")
        }

        // "the number of cards/buttons/fields/backgrounds/bg fields/bg buttons"
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
            case "bg buttons", "background buttons":
                if let bgId = document.cards.first(where: { $0.id == context.currentCardId })?.backgroundId {
                    return String(document.partsForBackground(bgId).filter { $0.partType == .button }.count)
                }
                return "0"
            case "bg fields", "background fields":
                if let bgId = document.cards.first(where: { $0.id == context.currentCardId })?.backgroundId {
                    return String(document.partsForBackground(bgId).filter { $0.partType == .field }.count)
                }
                return "0"
            default: break
            }
        }

        // Property of a scene node (sprite, label, shape, etc.) via object reference.
        // If the node isn't found, fall through to try as a Part (handles ambiguous
        // types like "video" which can be both a scene node and a card-level Part).
        let sceneNodeTypes = ["sprite", "label", "shape", "emitter", "audio", "tilemap", "camera", "video", "crop", "effect", "light", "group"]
        if case .objectRef(let ref) = targetExpr, sceneNodeTypes.contains(ref.objectType) {
            let nodeName = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            if let location = nodeLocation(
                named: nodeName,
                objectType: ref.objectType,
                document: document,
                currentCardId: context.currentCardId
            ) {
                return nodePropertyValue(location.node, property: lower)
            }
            // Don't return "" — fall through to try as a card-level Part
        }

        if case .objectRef(let ref) = targetExpr, ref.objectType == "scene" {
            let sceneName = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            if let location = sceneLocation(named: sceneName, document: document, currentCardId: context.currentCardId),
               let scene = location.areaSpec.scene(named: sceneName) {
                switch lower {
                case "name": return scene.name
                case "backgroundcolor": return scene.backgroundColor
                case "gravity": return "\(formatNumber(scene.gravity.dx)),\(formatNumber(scene.gravity.dy))"
                case "paused", "ispaused": return scene.isPaused ? "true" : "false"
                case "width": return formatNumber(scene.size.width)
                case "height": return formatNumber(scene.size.height)
                default: return ""
                }
            }
        }

        // Card-level property access via object reference.
        // `the background of card "X"` returns the background's name.
        // `the theme of card "X"` returns this card's themeName (may
        // be empty when inheriting from background/stack).
        // `the effectiveTheme of card "X"` walks the cascade and
        // returns the resolved theme's name.
        if case .objectRef(let ref) = targetExpr, ref.objectType == "card" {
            let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            let card = cardIndex(
                forIdentifier: ident,
                document: document,
                currentCardId: context.currentCardId
            ).map { document.cards[$0] }
            switch lower {
            case "background":
                if let card = card,
                   let bg = document.backgrounds.first(where: { $0.id == card.backgroundId }) {
                    return bg.name
                }
                return ""
            case "theme", "themename", "theme_name":
                return card?.themeName ?? ""
            case "effectivetheme", "effective_theme":
                if let card = card {
                    return document.effectiveTheme(forCard: card.id).name
                }
                return ""
            case "name":
                return card?.name ?? ""
            case "marked":
                return (card?.marked ?? false) ? "true" : "false"
            case "script":
                return card?.script ?? ""
            default: break
            }
        }

        // Background-level property access via object reference.
        // `the theme of background "menu"`, `the script of background X`, etc.
        if case .objectRef(let ref) = targetExpr, ref.objectType == "background" {
            let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            let bg = backgroundIndex(
                forIdentifier: ident,
                document: document,
                currentCardId: context.currentCardId
            ).map { document.backgrounds[$0] }
            switch lower {
            case "theme", "themename", "theme_name":
                return bg?.themeName ?? ""
            case "name":
                return bg?.name ?? ""
            case "script":
                return bg?.script ?? ""
            case "cardcount", "card_count":
                guard let bg = bg else { return "0" }
                return String(document.cards.filter { $0.backgroundId == bg.id }.count)
            default: break
            }
        }

        // Property of a specific part via object reference.
        if case .objectRef(let ref) = targetExpr {
            let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            if let idx = findPartIndex(ref.objectType, identifier: ident, document: document, currentCardId: context.currentCardId) {
                return partPropertyValue(document.parts[idx], property: property, document: document, context: context)
            }
        }

        // `me` as target: the part whose script is currently
        // executing. `the loc of me`, `the rotation of me`, etc.
        // resolve against `context.targetId`. This is the
        // canonical HypeTalk way for a handler to read its own
        // host part's properties.
        if case .me = targetExpr,
           let part = document.parts.first(where: { $0.id == context.targetId }) {
            return partPropertyValue(part, property: property, document: document, context: context)
        }

        if case .me = targetExpr,
           let spriteTarget = locateSpriteTarget(id: context.targetId, document: document, currentCardId: context.currentCardId) {
            if let nodeId = spriteTarget.nodeId,
               let scene = activeScene(partIndex: spriteTarget.partIndex, document: document),
               let node = scene.node(id: nodeId) {
                return nodePropertyValue(node, property: lower)
            }
            if let scene = activeScene(partIndex: spriteTarget.partIndex, document: document) {
                switch lower {
                case "name": return scene.name
                case "backgroundcolor": return scene.backgroundColor
                case "gravity": return "\(formatNumber(scene.gravity.dx)),\(formatNumber(scene.gravity.dy))"
                case "paused", "ispaused": return scene.isPaused ? "true" : "false"
                case "width": return formatNumber(scene.size.width)
                case "height": return formatNumber(scene.size.height)
                default: break
                }
            }
        }

        // Fallback: the target expression evaluated to something
        // that looks like a part identifier (a name or UUID
        // string, or the UUID that the `me` path produces).
        if let part = findPart(targetVal, document: document) {
            return partPropertyValue(part, property: property, document: document, context: context)
        }

        return ""
    }

    /// Resolve a single part property by name. Shared between the
    /// `objectRef` path, the `me` path, and the final fallback
    /// `findPart` path so every way of naming a part produces the
    /// same surface. Extracted from the inline property switch
    /// that used to live in `evaluateProperty`'s objectRef branch.
    private func partPropertyValue(
        _ part: Part,
        property: String,
        document: HypeDocument,
        context: ExecutionContext
    ) -> Value {
        // Chart-specific properties (title, xAxisLabel, etc.) take
        // precedence over the generic part-property switch so
        // `the title of chart "Sales"` resolves to the chart's
        // title field rather than the part name.
        if let chartProp = chartLevelProperty(property, part: part) {
            return chartProp
        }
        switch property.lowercased() {
        case "name":        return part.name
        case "id":          return part.id.uuidString
        case "left", "left_pos":  return formatNumber(part.left)
        case "top", "top_pos":    return formatNumber(part.top)
        case "width":       return formatNumber(part.width)
        case "height":      return formatNumber(part.height)
        case "right":       return formatNumber(part.left + part.width)
        case "bottom":      return formatNumber(part.top + part.height)
        case "loc", "location":
            // Map parts overload `location` to mean the geocoded
            // place-name field when one is set. `loc` always returns
            // the geometric centre. `location` on a map without a
            // place name set falls back to the geometric centre so
            // existing scripts that read `the location of map "X"`
            // for layout never silently break.
            if property.lowercased() == "location" && part.partType == .map && !part.mapLocation.isEmpty {
                return part.mapLocation
            }
            return "\(formatNumber(part.left + part.width / 2)),\(formatNumber(part.top + part.height / 2))"
        case "rect", "rectangle":
            return "\(formatNumber(part.left)),\(formatNumber(part.top)),\(formatNumber(part.left + part.width)),\(formatNumber(part.top + part.height))"
        case "rotation":    return formatNumber(part.rotation)
        case "visible":     return part.visible ? "true" : "false"
        case "enabled":     return part.enabled ? "true" : "false"
        case "hilite":      return part.hilite ? "true" : "false"
        case "style":
            return part.partType == .button ? part.buttonStyle.rawValue : part.fieldStyle.rawValue
        case "textfont", "font": return part.textFont
        case "textsize", "size": return formatNumber(part.textSize)
        case "textstyle", "text_style":   return part.textStyle
        case "textalign":   return part.textAlign.rawValue
        // Foreground (font) color. Aliases mirror the AI tool
        // surface: `fontColor` is the canonical key, `textColor`
        // and the bare `color` map to the same property. Empty
        // string means "auto / contrast-aware against fill" — the
        // renderer's fallback path. We surface the literal stored
        // value (including ""), so a script can detect "auto" by
        // testing `the fontColor of cd btn 1 is empty`.
        case "fontcolor", "font_color", "textcolor", "text_color":
            return part.fontColor
        // Hover help bubble. Aliases mirror what the AI tool
        // surface accepts. Empty string means "no bubble".
        case "helptext", "help_text", "tooltip", "tool_tip", "help":
            return part.helpText
        case "script":      return part.script
        case "showname":    return part.showName ? "true" : "false"
        case "autohilite":  return part.autoHilite ? "true" : "false"
        case "locktext":    return part.lockText ? "true" : "false"
        case "widemargins": return part.wideMargins ? "true" : "false"
        case "dontwrap":    return part.dontWrap ? "true" : "false"
        case "url":         return part.url
        case "chartdata", "chart_data": return part.chartData
        case "selecteddate", "selected_date":   return part.selectedDate
        case "displaymonth", "display_month":   return part.displayMonth
        case "mindate", "min_date":             return part.minDate
        case "maxdate", "max_date":             return part.maxDate
        case "calendarstyle", "calendar_style": return part.calendarStyle
        // PDF
        case "pdfurl", "pdf_url":               return part.pdfURL
        case "currentpage", "current_page":     return String(part.pdfCurrentPage)
        case "displaymode", "display_mode":     return part.pdfDisplayMode
        case "autoscales", "auto_scales":       return part.pdfAutoScales ? "true" : "false"
        case "pagecount", "page_count":
            // PageCount is observable only when the live PDFView
            // has loaded the document; for the model layer we
            // return 0 so HypeTalk doesn't crash. The runtime
            // layer can later override this from PDFHostNSView.
            return "0"
        // Map
        case "centerlat", "center_lat":         return formatNumber(part.mapCenterLat)
        case "centerlon", "center_lon":         return formatNumber(part.mapCenterLon)
        case "span":                            return formatNumber(part.mapSpan)
        case "maptype", "map_type":             return part.mapType
        case "annotations":                     return part.mapAnnotationsJSON
        case "maplocation", "map_location":     return part.mapLocation
        // ColorWell
        case "color", "colorhex", "color_hex":  return part.colorWellHex
        case "interactive":                     return part.colorWellInteractive ? "true" : "false"
        // Form controls (stepper, slider, toggle, segmented).
        // Toggle's `on` returns boolean; segmented's `selectedSegment`
        // returns the integer index. Stepper/slider use `value`.
        case "value":
            if part.partType == .progressView { return formatNumber(part.progressValue) }
            if part.partType == .gauge { return formatNumber(part.gaugeValue) }
            if part.partType == .toggle { return part.controlValue >= 0.5 ? "true" : "false" }
            if part.partType == .segmented { return String(Int(part.controlValue)) }
            // For text fields `the value of <field>` returns the
            // textContent — what the user typed. This matches the
            // common-sense expectation. Numeric form controls
            // (stepper / slider) still use controlValue.
            if part.partType == .field { return part.textContent }
            return formatNumber(part.controlValue)
        case "on":
            return part.controlValue >= 0.5 ? "true" : "false"
        case "min", "minvalue", "min_value":     return formatNumber(part.controlMin)
        case "max", "maxvalue", "max_value":     return formatNumber(part.controlMax)
        case "step", "increment":                return formatNumber(part.controlStep)
        case "segments", "segmentitems":         return part.segmentItems
        case "selectedsegment", "selected_segment": return String(Int(part.controlValue))
        // AudioRecorder
        case "recording":           return part.audioRecording ? "true" : "false"
        case "playing":             return part.audioPlaying ? "true" : "false"
        case "duration":            return formatNumber(part.audioDuration)
        case "outputpath", "output_path", "filepath", "file_path": return part.audioOutputPath
        case "format":              return part.audioFormat
        // Scene3D
        case "imagefilter", "image_filter", "filter": return part.imageFilter
        case "imagefilterintensity", "image_filter_intensity", "filterintensity", "filter_intensity": return formatNumber(part.imageFilterIntensity)
        case "object":
            // Return the author-visible source path when set; fall back to
            // the resolved scene3DURL so older documents still read correctly.
            return part.scene3DSourceURL.isEmpty ? part.scene3DURL : part.scene3DSourceURL
        case "modelurl", "model_url", "sceneurl", "scene_url": return part.scene3DURL
        case "allowscameracontrol", "allows_camera_control", "cameracontrol": return part.scene3DAllowsCameraControl ? "true" : "false"
        case "autolighting", "auto_lighting", "defaultlighting": return part.scene3DAutoLighting ? "true" : "false"
        case "antialiasing", "anti_aliasing": return part.scene3DAntialiasing
        case "background3d", "background_3d", "scenebackground": return part.scene3DBackground
        case "text", "textcontent":
            // Security condition 2: mask secure field text in HypeTalk reads.
            if part.partType == .field && part.fieldStyle == .secure {
                return "(masked)"
            }
            return part.textContent
        // ProgressView
        case "progressvalue", "progress_value":     return formatNumber(part.progressValue)
        case "progresstotal", "progress_total":     return formatNumber(part.progressTotal)
        case "progresscircular", "progress_circular", "circular", "iscircular":
            return part.progressIsCircular ? "true" : "false"
        case "progressindeterminate", "progress_indeterminate", "indeterminate":
            return part.progressIsIndeterminate ? "true" : "false"
        case "progresslabel", "progress_label":     return part.progressLabel
        case "progresstint", "progress_tint":       return part.progressTint
        // Gauge
        case "gaugevalue", "gauge_value":           return formatNumber(part.gaugeValue)
        case "gaugemin", "gauge_min":               return formatNumber(part.gaugeMin)
        case "gaugemax", "gauge_max":               return formatNumber(part.gaugeMax)
        case "gaugestyle", "gauge_style":           return part.gaugeStyle
        case "gaugetint", "gauge_tint":             return part.gaugeTint
        case "gaugelabel", "gauge_label":           return part.gaugeLabel
        case "gaugeminlabel", "gauge_min_label":    return part.gaugeMinLabel
        case "gaugemaxlabel", "gauge_max_label":    return part.gaugeMaxLabel
        case "gaugedecimals", "gauge_decimals":     return formatNumber(Double(part.gaugeDecimals))
        case "progressdecimals", "progress_decimals": return formatNumber(Double(part.progressDecimals))
        case "decimals":
            // Shared alias — dispatch by part type so progressView
            // and gauge each read their own field. Other types
            // return "0" (no decimals concept).
            if part.partType == .gauge { return formatNumber(Double(part.gaugeDecimals)) }
            if part.partType == .progressView { return formatNumber(Double(part.progressDecimals)) }
            return "0"
        // Menu
        case "menuitems", "menu_items", "items":    return part.menuItems
        case "menutitle", "menu_title":             return part.menuTitle
        // SearchField
        case "searchtext", "search_text":           return part.searchText
        case "searchprompt", "search_prompt", "prompt": return part.searchPrompt
        case "searchsendsimmediately", "search_sends_immediately", "immediate":
            return part.searchSendsImmediately ? "true" : "false"
        // Divider
        case "dividerorientation", "divider_orientation", "orientation":
            return part.dividerOrientation
        case "dividerthickness", "divider_thickness", "thickness":
            return formatNumber(part.dividerThickness)
        case "dividercolor", "divider_color":       return part.dividerColor
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
        case "animated", "animation", "animate":
            // `animation` / `animate` are synonyms for `animated` so scripts
            // like `set the animation of image "chick" to false` work
            // (reported regression — users reach for `animation` because
            // the command form is `start the animation of`). All three
            // names read the same underlying `Part.animated` flag.
            return part.animated ? "true" : "false"
        case "transparentbackground", "transparent_background", "transparent",
             "transparentbg", "alpha":
            // Image-only flag that asks the renderer to chroma-key out
            // the corner-pixel color so the card shows through.
            // Synonyms cover natural authoring forms:
            //   `the transparent of image "X"`
            //   `the alpha of image "X"`
            //   `the transparent_background of image "X"`
            return part.transparentBackground ? "true" : "false"
        case "animating":
            #if canImport(AppKit)
            let tweening = PartAnimator.shared.isAnimating(partId: part.id)
            let gifPlaying = GIFAnimator.shared.isAnimating(partId: part.id)
            return (tweening || gifPlaying) ? "true" : "false"
            #else
            return "false"
            #endif
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
        case "videourl", "video_url":
            return part.videoURL
        case "popupitems", "popup_items":
            return part.popupItems
        case "htmlcontent", "html_content":
            return part.htmlContent
        // SpriteArea-specific properties (read from SpriteAreaSpec JSON)
        case "scalemode", "scale_mode":
            if let spec = part.spriteAreaSpecModel { return spec.scaleMode.rawValue }
            return ""
        case "showsphysics", "shows_physics":
            if let spec = part.spriteAreaSpecModel { return spec.showsPhysics ? "true" : "false" }
            return "false"
        case "showsfps", "shows_fps":
            if let spec = part.spriteAreaSpecModel { return spec.showsFPS ? "true" : "false" }
            return "false"
        case "showsnodecount", "shows_node_count":
            if let spec = part.spriteAreaSpecModel { return spec.showsNodeCount ? "true" : "false" }
            return "false"
        case "scenename", "scene_name", "activescene", "active_scene":
            if let spec = part.spriteAreaSpecModel { return spec.activeScene?.name ?? "" }
            return ""
        case "scenecount", "scene_count":
            if let spec = part.spriteAreaSpecModel { return String(spec.scenes.count) }
            return "0"
        default:            return ""
        }
    }

    // MARK: - Chunk expressions

    private func evaluateChunk(
        _ chunkType: ChunkType,
        range: ChunkRange,
        source: Value,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async -> Value {
        // Trim whitespace after the separator for item chunks so
        // "a, b, c" yields ["a", "b", "c"] not ["a", " b", " c"].
        // Matches HyperTalk's item chunk semantics.
        let parts: [String]
        switch chunkType {
        case .word:
            parts = source.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        case .char, .character:
            parts = source.map(String.init)
        case .item:
            parts = source.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        case .line:
            parts = splitLines(source)
        }

        /// Helper that evaluates a chunk-index expression to an
        /// integer. Previously this code only unwrapped `.literal`
        /// cases, which meant `item currentIndex of X` silently
        /// resolved to `item 1 of X` because `currentIndex` is a
        /// `.variable`, not a literal. Now we evaluate whatever
        /// expression the parser produced and coerce to an int.
        ///
        /// **Important**: this function is *non-throwing* and uses
        /// `try?` internally. Earlier we made `evaluateChunk` itself
        /// `throws`, which propagated chunk-eval errors as runtime
        /// throws. That turned out to be catastrophic under test:
        /// Swift Testing installs a `swift_willThrow` hook that
        /// captures a backtrace on every thrown error, and the
        /// backtrace capture recursively invokes libswiftCore's
        /// type-metadata parser (`_gatherGenericParameterCounts` →
        /// `decodeMangledType`). The combined stack depth of the
        /// interpreter's recursive `executeStatement` calls + the
        /// throw-capture backtrace + libswiftCore type-metadata
        /// recursion blew the test thread's stack guard page and
        /// crashed with SIGBUS. Keeping this non-throwing
        /// contains the consequences of a bad chunk index (degrade
        /// to 0, return empty string) rather than escalating a
        /// throw through the whole call stack.
        func indexValue(_ expr: Expression) async -> Int {
            let str = (try? await evaluate(expr, env: &env, document: document, context: context)) ?? ""
            return Int(toNumber(str))
        }

        switch range {
        case .single(let indexExpr):
            let idx = await indexValue(indexExpr)
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
            let from = max(1, await indexValue(fromExpr))
            let to = min(parts.count, await indexValue(toExpr))
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

    private func chunkCountProperty(_ property: String) -> ChunkType? {
        switch property {
        case "numberofwords", "number_of_words":
            return .word
        case "numberofchars", "numberofcharacters", "number_of_chars", "number_of_characters":
            return .char
        case "numberofitems", "number_of_items":
            return .item
        case "numberoflines", "number_of_lines":
            return .line
        default:
            return nil
        }
    }

    private func countChunks(_ chunkType: ChunkType, in source: Value) -> Int {
        switch chunkType {
        case .word:
            return source.split(separator: " ", omittingEmptySubsequences: true).count
        case .char, .character:
            return source.count
        case .item:
            return source.split(separator: ",", omittingEmptySubsequences: false).count
        case .line:
            return splitLines(source).count
        }
    }

    private func splitLines(_ source: Value) -> [String] {
        guard !source.isEmpty else { return [] }
        return source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    // MARK: - Object reference resolution

    private func isCurrentCardIdentifier(_ identifier: Value) -> Bool {
        let lower = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "this" || lower == "this card" || lower == "current" || lower == "current card"
    }

    private func isCurrentBackgroundIdentifier(_ identifier: Value) -> Bool {
        let lower = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "this" || lower == "this background" || lower == "this bg"
            || lower == "current" || lower == "current background" || lower == "current bg"
    }

    private func cardIndex(
        forIdentifier identifier: Value,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Int? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCurrentCardIdentifier(trimmed) {
            return document.cards.firstIndex(where: { $0.id == currentCardId })
        }
        if let ci = document.cards.firstIndex(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return ci
        }
        if let num = Int(trimmed), num >= 1, num <= document.sortedCards.count {
            let cardId = document.sortedCards[num - 1].id
            return document.cards.firstIndex(where: { $0.id == cardId })
        }
        return nil
    }

    private func backgroundIndex(
        forIdentifier identifier: Value,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Int? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCurrentBackgroundIdentifier(trimmed) {
            guard let card = document.cards.first(where: { $0.id == currentCardId }) else { return nil }
            return document.backgrounds.firstIndex(where: { $0.id == card.backgroundId })
        }
        return document.backgrounds.firstIndex {
            $0.name.lowercased() == trimmed.lowercased()
        }
    }

    private func resolveObjectRef(_ objectType: String, identifier: Value, document: HypeDocument, context: ExecutionContext) -> Value {
        switch objectType {
        case "card":
            if isCurrentCardIdentifier(identifier) {
                return context.currentCardId.uuidString
            }
            if let card = document.cards.first(where: { $0.name.lowercased() == identifier.lowercased() }) {
                return card.id.uuidString
            }
            if let idx = Int(identifier), idx >= 1, idx <= document.sortedCards.count {
                return document.sortedCards[idx - 1].id.uuidString
            }
        case "background", "bg":
            if let idx = backgroundIndex(forIdentifier: identifier, document: document, currentCardId: context.currentCardId) {
                return document.backgrounds[idx].id.uuidString
            }
        case "stack":
            return document.stack.id.uuidString
        case "field", "fld":
            if let part = document.parts.first(where: { $0.partType == .field && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "button", "btn":
            if let part = document.parts.first(where: { $0.partType == .button && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "spritearea":
            if let part = document.parts.first(where: { $0.partType == .spriteArea && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
            // Also try by number
            let spriteAreas = document.partsForCard(context.currentCardId).filter { $0.partType == .spriteArea }
            if let idx = Int(identifier), idx >= 1, idx <= spriteAreas.count {
                return spriteAreas[idx - 1].id.uuidString
            }
        case "webpage":
            if let part = document.parts.first(where: { $0.partType == .webpage && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "image":
            if let part = document.parts.first(where: { $0.partType == .image && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "video":
            if let part = document.parts.first(where: { $0.partType == .video && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "chart":
            if let part = document.parts.first(where: { $0.partType == .chart && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "progressview", "progress":
            if let part = document.parts.first(where: { $0.partType == .progressView && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "gauge":
            if let part = document.parts.first(where: { $0.partType == .gauge && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        // `link`, `menu`, `searchfield` once had their own PartType
        // values; `Part.init(from:)` (Part.swift:610-648) migrates
        // any decoded part with those types to its canonical form
        // (button with .link / .popup style; field with .search
        // style). After migration, no live Part has
        // `partType == .link / .menu / .searchField`, so the old
        // dispatch branches matched nothing and returned "" via the
        // default case below. Removed; matching by the new canonical
        // form is `case "button"` / `case "field"` plus a style
        // check at the call site.
        case "divider":
            if let part = document.parts.first(where: { $0.partType == .divider && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "scene":
            if let location = sceneLocation(named: identifier, document: document, currentCardId: context.currentCardId),
               let activeSceneEntry = location.areaSpec.scenes.first(where: { $0.scene.name.lowercased() == identifier.lowercased() }) {
                return activeSceneEntry.id.uuidString
            }
        case "sprite", "label", "shape", "emitter", "audio", "video", "tilemap", "camera", "crop", "effect", "light", "group":
            if let location = nodeLocation(
                named: identifier,
                objectType: objectType,
                document: document,
                currentCardId: context.currentCardId
            ) {
                return location.node.id.uuidString
            }
        default:
            break
        }
        return ""
    }

    private func resolveSendTarget(
        _ target: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> UUID? {
        switch target {
        case .me:
            return context.targetId
        case .objectRef(let ref):
            let identifier = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            let resolved = resolveObjectRef(
                ref.objectType,
                identifier: identifier,
                document: document,
                context: context
            )
            return UUID(uuidString: resolved)
        default:
            let value = try await evaluate(target, env: &env, document: document, context: context)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = UUID(uuidString: value) {
                return id
            }
            switch value.lowercased() {
            case "stack", "this stack", "current stack":
                return document.stack.id
            case "card", "this card", "current card":
                return context.currentCardId
            case "background", "bg", "this background", "this bg", "current background", "current bg":
                return document.cards.first(where: { $0.id == context.currentCardId })?.backgroundId
            default:
                return nil
            }
        }
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
        let targetType: PartType?
        switch objectType {
        case "field", "fld": targetType = .field
        case "button", "btn": targetType = .button
        case "webpage": targetType = .webpage
        case "shape": targetType = .shape
        case "image": targetType = .image
        case "video": targetType = .video
        case "chart": targetType = .chart
        case "spritearea": targetType = .spriteArea
        case "calendar": targetType = .calendar
        case "pdf": targetType = .pdf
        case "map": targetType = .map
        case "colorwell", "color_well": targetType = .colorWell
        case "stepper": targetType = .stepper
        case "slider": targetType = .slider
        case "toggle": targetType = .toggle
        case "segmented": targetType = .segmented
        case "recorder", "audiorecorder": targetType = .audioRecorder
        case "scene3d", "model3d": targetType = .scene3D
        case "progressview", "progress": targetType = .progressView
        case "gauge": targetType = .gauge
        case "link": targetType = .link
        case "menu": targetType = .menu
        case "searchfield", "search": targetType = .searchField
        case "divider": targetType = .divider
        default: targetType = nil
        }

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

    // MARK: - Chart data-point resolution

    /// Resolved location of a single `ChartDataPoint` inside a chart
    /// part, together with the parsed `ChartConfig` so the caller can
    /// read or mutate and re-serialize atomically.
    private struct ChartPointLocation {
        var partIndex: Int
        var config: ChartConfig
        var seriesIndex: Int
        var pointIndex: Int
    }

    /// Resolve a `chartDataPointRef` (chart, series, point) to the
    /// concrete part/series/point indices, returning `nil` if any
    /// step fails (unknown chart name/number, unknown series, unknown
    /// point, or malformed `chartData` JSON).
    ///
    /// Lookup rules:
    /// - `chart` is resolved by `findPartIndex(objectType: "chart", ...)`.
    /// - `series` accepts a 1-based integer index or a case-insensitive
    ///   series name. An empty / missing ref defaults to index 1.
    /// - `point` accepts a 1-based integer index or a case-insensitive
    ///   point name.
    private func resolveChartDataPointLocation(
        chartExpr: Expression,
        seriesExpr: Expression,
        pointExpr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> ChartPointLocation? {
        let chartIdent = try await evaluate(chartExpr, env: &env, document: document, context: context)
        guard let partIdx = findPartIndex(
            "chart",
            identifier: chartIdent,
            document: document,
            currentCardId: context.currentCardId
        ) else {
            return nil
        }

        let chartDataJSON = document.parts[partIdx].chartData
        guard let config = ChartConfig.fromJSON(chartDataJSON) else {
            // Chart part has empty / malformed JSON (e.g. brand-new
            // chart before series have been added). Callers that want
            // create-on-demand behaviour can catch the nil themselves.
            return nil
        }

        // Resolve series index: accept a 1-based integer index or a
        // case-insensitive series name.
        let seriesIdent = try await evaluate(seriesExpr, env: &env, document: document, context: context)
        let seriesIdx: Int
        if let num = Int(seriesIdent), num > 0, num <= config.series.count {
            seriesIdx = num - 1
        } else if let idx = config.series.firstIndex(where: {
            $0.name.lowercased() == seriesIdent.lowercased()
        }) {
            seriesIdx = idx
        } else {
            return nil
        }

        // Resolve point index inside that series: accept a 1-based
        // integer index or a case-insensitive point name.
        let pointIdent = try await evaluate(pointExpr, env: &env, document: document, context: context)
        let pointIdx: Int
        if let num = Int(pointIdent), num > 0, num <= config.series[seriesIdx].data.count {
            pointIdx = num - 1
        } else if let idx = config.series[seriesIdx].data.firstIndex(where: {
            $0.name.lowercased() == pointIdent.lowercased()
        }) {
            pointIdx = idx
        } else {
            return nil
        }

        return ChartPointLocation(
            partIndex: partIdx,
            config: config,
            seriesIndex: seriesIdx,
            pointIndex: pointIdx
        )
    }

    /// Evaluate `the number of (data) points (of|in) chart "X"`.
    /// Extracted from `evaluateProperty` so its locals stay in a
    /// leaf frame instead of bloating the main property-access path.
    private func numberOfPointsProperty(
        _ targetExpr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
        let chartIdent = try await evaluate(targetExpr, env: &env, document: document, context: context)
        guard let idx = findPartIndex(
            "chart",
            identifier: chartIdent,
            document: document,
            currentCardId: context.currentCardId
        ), let config = ChartConfig.fromJSON(document.parts[idx].chartData) else {
            return "0"
        }
        return String(config.series.first?.data.count ?? 0)
    }

    /// Read a property from a chart data-point reference. Extracted
    /// from `evaluateProperty` so the ChartPointLocation /
    /// ChartConfig locals live in a shallow leaf frame instead of
    /// inflating the main property-access path.
    private func getChartDataPointProperty(
        _ property: String,
        target: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
        guard case .chartDataPointRef(let chartExpr, let seriesExpr, let pointExpr) = target else {
            return ""
        }
        guard let loc = try await resolveChartDataPointLocation(
            chartExpr: chartExpr,
            seriesExpr: seriesExpr,
            pointExpr: pointExpr,
            env: &env,
            document: document,
            context: context
        ) else {
            return ""
        }
        let point = loc.config.series[loc.seriesIndex].data[loc.pointIndex]
        let series = loc.config.series[loc.seriesIndex]
        switch property.lowercased() {
        case "color", "fillcolor", "fill_color":
            // Resolve per-point color with fallback to series color,
            // matching the ChartHostView rendering logic.
            return point.color.isEmpty ? series.color : point.color
        case "rawcolor", "raw_color":
            return point.color
        case "value":
            return formatNumber(point.value)
        case "name":
            return point.name
        default:
            return ""
        }
    }

    /// Evaluate a standalone `chartDataPointRef` expression to a
    /// human-readable debug string. Kept as a leaf helper so the
    /// pattern-match locals don't inflate `evaluate`'s main stack
    /// frame — `evaluate` is called recursively many times per
    /// script and any bloat there multiplies with recursion depth.
    private func describeChartDataPointRef(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
        guard case .chartDataPointRef(let chartExpr, let seriesExpr, let pointExpr) = expr else {
            return ""
        }
        let chartName = try await evaluate(chartExpr, env: &env, document: document, context: context)
        let seriesName = try await evaluate(seriesExpr, env: &env, document: document, context: context)
        let pointName = try await evaluate(pointExpr, env: &env, document: document, context: context)
        return "data point \(pointName) of series \(seriesName) of chart \(chartName)"
    }

    /// Apply a `set the <property> of <target> to <value>` mutation
    /// once the target has been resolved to a part index. Shared
    /// between the `objectRef` path and the `me` path so both
    /// writers end up at the same switch table. Extracted from the
    /// inline set case in `executeStatement` so the locals don't
    /// inflate that function's stack frame (which is already ~99 KB
    /// and recursion-sensitive — see the earlier stack-overflow
    /// investigation in the event-dispatch fix).
    ///
    /// For properties the switch doesn't recognise, this helper
    /// falls back to `env.setVariable` so unknown-property writes
    /// still land in a local variable (matching the previous
    /// default-case behaviour).
    private func applyPartPropertySet(
        partIndex: Int,
        property: String,
        value: Value,
        env: inout Environment,
        document: inout HypeDocument,
        context: ExecutionContext
    ) {
        // Chart-specific properties (title, xAxisLabel, etc.) take
        // precedence so `set the title of chart "Sales" to "…"`
        // writes the chart's ChartConfig.
        if setChartLevelProperty(property, value: value, partIndex: partIndex, document: &document) {
            return
        }
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
        case "fillcolor", "fill_color":
            document.parts[partIndex].fillColor = value
        case "strokecolor", "stroke_color":
            document.parts[partIndex].strokeColor = value
        case "left", "left_pos":
            document.parts[partIndex].left = toNumber(value)
        case "top", "top_pos":
            document.parts[partIndex].top = toNumber(value)
        case "width":
            document.parts[partIndex].width = toNumber(value)
        case "height":
            document.parts[partIndex].height = toNumber(value)
        case "rotation":
            document.parts[partIndex].rotation = toNumber(value)
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
            switch document.parts[partIndex].partType {
            case .button:
                document.parts[partIndex].buttonStyle = ButtonStyle(rawValue: value) ?? .roundRect
            case .field:
                document.parts[partIndex].fieldStyle = FieldStyle(rawValue: value) ?? .rectangle
            case .shape:
                document.parts[partIndex].shapeType = ShapeType(rawValue: value) ?? .rectangle
            default:
                break
            }
        case "chartdata", "chart_data":
            document.parts[partIndex].chartData = value
        case "script":
            document.parts[partIndex].script = value
        case "family":
            document.parts[partIndex].family = Int(toNumber(value))
        case "textstyle", "text_style":
            // Normalize the input through TextStyleFlags so any
            // alias the user wrote ("strike", "underlined", "BOLD,
            // italic ") collapses to the canonical
            // "bold, italic, ..." rawString form. This keeps round
            // trips through HypeTalk → renderer → HypeTalk stable
            // and avoids "the textStyle of X is bold,italic" failing
            // a "is" comparison after normalization elsewhere.
            document.parts[partIndex].textStyle = TextStyleFlags(string: value).rawString
        case "fontcolor", "font_color", "textcolor", "text_color":
            // Empty string is meaningful — "" means "revert to auto
            // contrast-aware text color". We let the user clear back
            // to auto by setting "" (or "empty" via the existing HypeTalk
            // empty literal). Hex parsing happens in the renderer at
            // draw time, so any string is accepted here; an invalid
            // hex would silently fall back to the contrast-aware
            // default at draw time.
            document.parts[partIndex].fontColor = value
        // Hover help bubble — shown on hover in browse mode via
        // a native `NSToolTip`. Empty string disables the bubble.
        // Multi-line is supported (embed `\n` for line breaks);
        // the system tooltip wraps long lines automatically.
        case "helptext", "help_text", "tooltip", "tool_tip", "help":
            document.parts[partIndex].helpText = value
        case "rect", "rectangle":
            let components = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if components.count == 4 {
                document.parts[partIndex].left = components[0]
                document.parts[partIndex].top = components[1]
                document.parts[partIndex].width = components[2] - components[0]
                document.parts[partIndex].height = components[3] - components[1]
            }
        case "loc", "location":
            // Map parts overload `location` to mean the geocoded
            // place-name field — `set the location of map "X" to "97537"`.
            // We detect the overload by trying to parse the value as
            // an "x,y" coordinate pair: if it parses cleanly, we use
            // the geometric meaning; otherwise we route to
            // `mapLocation`. This keeps backward-compat for scripts
            // that move map parts via `set the loc of map "X" to
            // "100,200"` while making the human-friendly form work.
            // Non-map parts always get the geometric meaning.
            let components = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            let parsedAsCoords = components.count == 2 && components.allSatisfy { $0 != nil }
            if document.parts[partIndex].partType == .map && !parsedAsCoords {
                document.parts[partIndex].mapLocation = String(value.prefix(256))
            } else if parsedAsCoords {
                document.parts[partIndex].left = components[0]! - document.parts[partIndex].width / 2
                document.parts[partIndex].top = components[1]! - document.parts[partIndex].height / 2
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
            break
        case "sharedtext", "sharedhilite", "showlines", "showpict",
             "fixedlineheight", "multiplelines", "dontsearch",
             "autoselect", "autotab", "cantdelete", "cantmodify":
            break  // model-property gaps — no-op
        case "textheight":
            document.parts[partIndex].textSize = toNumber(value) / 1.3
        case "centered":
            document.parts[partIndex].textAlign = isTruthy(value) ? .center : .left
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
        case "transparentbackground", "transparent_background", "transparent",
             "transparentbg", "alpha":
            // Toggle the chroma-key path in `ImageRenderer`. Only
            // meaningful for image parts (other partTypes ignore
            // the flag at render time). All five synonyms map to
            // the same `Part.transparentBackground` bool.
            document.parts[partIndex].transparentBackground = isTruthy(value)
        case "animated", "animation", "animate":
            // `animation` / `animate` are accepted synonyms for `animated`
            // (see matching GET case). Users reasonably reach for
            // `animation` because the command form is
            // `start the animation of X`.
            let newValue = isTruthy(value)
            document.parts[partIndex].animated = newValue
            #if canImport(AppKit)
            // Thread-safety: `applyPartPropertySet` runs on the
            // interpreter's background Task, but `GIFAnimator.shared`
            // mutates a plain Swift Dictionary that is also read and
            // written by the main-thread Timer.tick callback. A BG
            // write here can race with a main-thread read, producing
            // the "toggles once then stops" symptom where `isRunning`
            // silently flips back to its prior value as the tick
            // overwrites our write. Dispatching to main serialises
            // all mutation against the tick. Capture partId and data
            // locally so the async block doesn't read from an
            // already-mutated `document`.
            let partId = document.parts[partIndex].id
            let capturedData = document.parts[partIndex].imageData
            DispatchQueue.main.async {
                if newValue {
                    if let data = capturedData {
                        GIFAnimator.shared.start(partId: partId, imageData: data)
                    }
                } else {
                    GIFAnimator.shared.stop(partId: partId)
                }
            }
            #endif
        case "videourl", "video_url":
            document.parts[partIndex].videoURL = value
        // Calendar-specific writes — settable on .calendar parts.
        // Empty string clears the bound (NSDatePicker.minDate/maxDate accept nil).
        case "selecteddate", "selected_date":
            document.parts[partIndex].selectedDate = value
        case "displaymonth", "display_month":
            document.parts[partIndex].displayMonth = value
        case "mindate", "min_date":
            document.parts[partIndex].minDate = value
        case "maxdate", "max_date":
            document.parts[partIndex].maxDate = value
        case "calendarstyle", "calendar_style":
            document.parts[partIndex].calendarStyle = value
        // PDF
        case "pdfurl", "pdf_url":
            document.parts[partIndex].pdfURL = value
        case "currentpage", "current_page":
            document.parts[partIndex].pdfCurrentPage = Int(toNumber(value))
        case "displaymode", "display_mode":
            document.parts[partIndex].pdfDisplayMode = value
        case "autoscales", "auto_scales":
            document.parts[partIndex].pdfAutoScales = isTruthy(value)
        // Map
        case "centerlat", "center_lat":
            document.parts[partIndex].mapCenterLat = toNumber(value)
        case "centerlon", "center_lon":
            document.parts[partIndex].mapCenterLon = toNumber(value)
        case "span":
            document.parts[partIndex].mapSpan = toNumber(value)
        case "maptype", "map_type":
            document.parts[partIndex].mapType = value
        case "annotations":
            document.parts[partIndex].mapAnnotationsJSON = value
        case "maplocation", "map_location":
            // `location` is already claimed as the geometry center-point
            // alias ("loc/location") at the top of this switch, so map
            // geocoding uses the unambiguous `maplocation` / `map_location`
            // names in HypeTalk. The AI tool and inspector layers still
            // accept "location" since those switches have no geometry case.
            // Clamp to 256 chars — anything longer is bogus and would just
            // bloat the document without helping geocoding.
            document.parts[partIndex].mapLocation = String(value.prefix(256))
        // ColorWell
        case "color", "colorhex", "color_hex":
            document.parts[partIndex].colorWellHex = value
        case "interactive":
            document.parts[partIndex].colorWellInteractive = isTruthy(value)
        // Form-control writes (stepper / slider / segmented) and
        // text-field text writes via the `value` alias.
        case "value":
            let pt = document.parts[partIndex].partType
            if pt == .toggle {
                document.parts[partIndex].controlValue = isTruthy(value) ? 1 : 0
            } else if pt == .progressView {
                // Route through the canonical setProgressValue
                // helper — clamps to [0, progressTotal] and rounds
                // to progressDecimals. Previously this branch
                // rounded but didn't clamp; the gauge branch did
                // neither. The audit flagged three different
                // behaviors for "set the value of …" depending on
                // surface; routing through Part.setProgressValue /
                // setGaugeValue collapses them to one.
                document.parts[partIndex].setProgressValue(toNumber(value))
            } else if pt == .gauge {
                document.parts[partIndex].setGaugeValue(toNumber(value))
            } else if pt == .field {
                // `set the value of field "X" to "..."` — same as
                // `set the text of field "X" to "..."`. Symmetrical
                // with the getter overload above.
                document.parts[partIndex].textContent = value
            } else {
                document.parts[partIndex].controlValue = toNumber(value)
            }
        case "on":
            document.parts[partIndex].controlValue = isTruthy(value) ? 1 : 0
        case "min", "minvalue", "min_value":
            document.parts[partIndex].controlMin = toNumber(value)
        case "max", "maxvalue", "max_value":
            document.parts[partIndex].controlMax = toNumber(value)
        case "step", "increment":
            document.parts[partIndex].controlStep = toNumber(value)
        case "segments", "segmentitems":
            document.parts[partIndex].segmentItems = value
        case "selectedsegment", "selected_segment":
            document.parts[partIndex].controlValue = toNumber(value)
        // AudioRecorder
        case "recording":
            document.parts[partIndex].audioRecording = isTruthy(value)
        case "playing":
            document.parts[partIndex].audioPlaying = isTruthy(value)
        case "outputpath", "output_path", "filepath", "file_path":
            document.parts[partIndex].audioOutputPath = value
        case "format":
            document.parts[partIndex].audioFormat = value
        // Scene3D
        case "imagefilter", "image_filter", "filter":
            document.parts[partIndex].imageFilter = value.lowercased() == "none" ? "" : value.lowercased()
        case "imagefilterintensity", "image_filter_intensity", "filterintensity", "filter_intensity":
            document.parts[partIndex].imageFilterIntensity = max(0, min(1, toNumber(value)))
        case "object":
            // Store the author-visible source path, then resolve to the
            // working URL (converting STL → OBJ via cache if needed).
            document.parts[partIndex].scene3DSourceURL = value
            document.parts[partIndex].scene3DURL = resolveScene3DPath(
                value, partId: document.parts[partIndex].id, context: context
            )
        case "modelurl", "model_url", "sceneurl", "scene_url":
            // Legacy alias: route through the resolver so STL files auto-
            // convert whether the author uses `object` or `modelURL`.
            document.parts[partIndex].scene3DSourceURL = value
            document.parts[partIndex].scene3DURL = resolveScene3DPath(
                value, partId: document.parts[partIndex].id, context: context
            )
        case "allowscameracontrol", "allows_camera_control", "cameracontrol":
            document.parts[partIndex].scene3DAllowsCameraControl = isTruthy(value)
        case "autolighting", "auto_lighting", "defaultlighting":
            document.parts[partIndex].scene3DAutoLighting = isTruthy(value)
        case "antialiasing", "anti_aliasing":
            document.parts[partIndex].scene3DAntialiasing = value
        case "background3d", "background_3d", "scenebackground":
            document.parts[partIndex].scene3DBackground = value
        case "popupitems", "popup_items":
            document.parts[partIndex].popupItems = value
        // ProgressView setters (security condition 5: clamp values).
        // Routes through Part.setProgressValue so this and `case
        // "value"` produce identical clamp+round results.
        case "progressvalue", "progress_value":
            document.parts[partIndex].setProgressValue(toNumber(value))
        case "progresstotal", "progress_total":
            document.parts[partIndex].progressTotal = max(1e-10, toNumber(value))
        case "progressdecimals", "progress_decimals":
            let n = Int(toNumber(value))
            document.parts[partIndex].progressDecimals = max(0, min(10, n))
        case "decimals":
            // Shared alias — dispatch by part type. Mirrors the
            // gauge.decimals contract for both: 0 = integral steps
            // (default), capped at 10 for sane formatting.
            let n = Int(toNumber(value))
            let clamped = max(0, min(10, n))
            switch document.parts[partIndex].partType {
            case .gauge:        document.parts[partIndex].gaugeDecimals = clamped
            case .progressView: document.parts[partIndex].progressDecimals = clamped
            default: break
            }
        case "progresscircular", "progress_circular", "circular", "iscircular":
            document.parts[partIndex].progressIsCircular = isTruthy(value)
        case "progressindeterminate", "progress_indeterminate", "indeterminate":
            document.parts[partIndex].progressIsIndeterminate = isTruthy(value)
        case "progresslabel", "progress_label":
            // Security condition 6: cap at 256 chars.
            document.parts[partIndex].progressLabel = String(value.prefix(256))
        case "progresstint", "progress_tint":
            document.parts[partIndex].progressTint = value
        // Gauge setters (security condition 5: enforce max > min).
        // Routes through Part.setGaugeValue — same drift fix as
        // progressvalue above. Previously this branch clamped but
        // didn't round, while `case "value"` rounded but didn't
        // clamp. They're now identical.
        case "gaugevalue", "gauge_value":
            document.parts[partIndex].setGaugeValue(toNumber(value))
        case "gaugemin", "gauge_min":
            document.parts[partIndex].gaugeMin = toNumber(value)
        case "gaugemax", "gauge_max":
            let newMax = toNumber(value)
            let gMin = document.parts[partIndex].gaugeMin
            document.parts[partIndex].gaugeMax = newMax > gMin ? newMax : gMin + 1
        case "gaugestyle", "gauge_style":
            document.parts[partIndex].gaugeStyle = value
        case "gaugetint", "gauge_tint", "tint":
            document.parts[partIndex].gaugeTint = value
        case "gaugelabel", "gauge_label":
            document.parts[partIndex].gaugeLabel = String(value.prefix(256))
        case "gaugeminlabel", "gauge_min_label":
            document.parts[partIndex].gaugeMinLabel = String(value.prefix(256))
        case "gaugemaxlabel", "gauge_max_label":
            document.parts[partIndex].gaugeMaxLabel = String(value.prefix(256))
        case "gaugedecimals", "gauge_decimals":
            // Disambiguated form — `decimals` (without the
            // `gauge` prefix) is handled in the shared dispatch
            // case above so progressView + gauge can share it.
            let n = Int(toNumber(value))
            document.parts[partIndex].gaugeDecimals = max(0, min(10, n))
        // Menu setters.
        case "menuitems", "menu_items":
            // Security condition 6: cap at 64 KB.
            // Security condition 3: per-item scripts (after `||`)
            // must parse cleanly. The AI executor enforces this at
            // create_menu / set_part_property time. Here we mirror
            // it for HypeTalk so a script can't write a malformed
            // inline action via `set the menuitems of menu "X" to
            // "Save||not real script{{{"` and surface a runtime
            // ScriptError when the user opens the menu — rejected-
            // at-write is friendlier than rejected-at-execute.
            //
            // On failure we silently leave the existing value
            // unchanged (matches HypeTalk's existing tolerant
            // setters — bad input is a no-op, not a thrown error).
            let capped = String(value.prefix(65536))
            var allItemsValid = true
            for line in capped.split(separator: "\n", omittingEmptySubsequences: true) {
                let s = String(line)
                guard let pipeRange = s.range(of: "||") else { continue }
                let inlineScript = String(s[pipeRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if inlineScript.isEmpty { continue }
                let wrapped = "on menuItemAction\n  \(inlineScript)\nend menuItemAction"
                var lex = Lexer(source: wrapped)
                let tokens = lex.tokenize()
                var parser = Parser(tokens: tokens)
                if (try? parser.parse()) == nil {
                    allItemsValid = false
                    break
                }
            }
            if allItemsValid {
                document.parts[partIndex].menuItems = capped
            }
        case "menutitle", "menu_title":
            document.parts[partIndex].menuTitle = String(value.prefix(256))
        // SearchField setters.
        case "searchtext", "search_text":
            // Security condition 6: cap at 1 KB.
            document.parts[partIndex].searchText = String(value.prefix(1024))
        case "searchprompt", "search_prompt", "prompt":
            document.parts[partIndex].searchPrompt = String(value.prefix(256))
        case "searchsendsimmediately", "search_sends_immediately", "immediate":
            document.parts[partIndex].searchSendsImmediately = isTruthy(value)
        // Divider setters.
        case "dividerorientation", "divider_orientation", "orientation":
            document.parts[partIndex].dividerOrientation = (value.lowercased() == "vertical") ? "vertical" : "horizontal"
        case "dividerthickness", "divider_thickness", "thickness":
            document.parts[partIndex].dividerThickness = max(0.5, toNumber(value))
        case "dividercolor", "divider_color":
            document.parts[partIndex].dividerColor = value
        case "htmlcontent", "html_content":
            document.parts[partIndex].htmlContent = value
        case "linesize":
            document.parts[partIndex].strokeWidth = toNumber(value)
        // SpriteArea-specific properties (write to SpriteAreaSpec JSON)
        case "scalemode", "scale_mode":
            if document.parts[partIndex].partType == .spriteArea {
                document.parts[partIndex].updateSpriteAreaSpec { spec in
                    if let mode = SceneScaleMode(rawValue: value) { spec.scaleMode = mode }
                }
            }
        case "showsphysics", "shows_physics":
            if document.parts[partIndex].partType == .spriteArea {
                document.parts[partIndex].updateSpriteAreaSpec { spec in spec.showsPhysics = isTruthy(value) }
            }
        case "showsfps", "shows_fps":
            if document.parts[partIndex].partType == .spriteArea {
                document.parts[partIndex].updateSpriteAreaSpec { spec in spec.showsFPS = isTruthy(value) }
            }
        case "showsnodecount", "shows_node_count":
            if document.parts[partIndex].partType == .spriteArea {
                document.parts[partIndex].updateSpriteAreaSpec { spec in spec.showsNodeCount = isTruthy(value) }
            }
        default:
            env.setVariable(property, value)
        }
    }

    /// Resolve a raw 3D model path for storage in `Part.scene3DURL`.
    ///
    /// - Returns the `raw` path unchanged for non-STL files.
    /// - For `.stl` files, calls `STLConverter.convert` which writes
    ///   (or cache-hits) an OBJ under `~/Library/Caches/…/stl-cache/`
    ///   and returns that path.
    /// - On empty input, returns `""`.
    /// - On conversion failure, logs the error and returns `""` so the
    ///   3D view shows empty rather than a stale corrupt path.
    private func resolveScene3DPath(_ raw: String, partId: UUID, context: ExecutionContext) -> String {
        guard !raw.isEmpty else { return "" }
        guard STLConverter.isSTL(path: raw) else { return raw }
        do {
            return try STLConverter.convert(stlPath: raw)
        } catch let stlError as STLConverter.Error {
            // Log only the structural reason — never the user-supplied
            // path, which on shared/crash-report systems would leak
            // home-directory layout into application logs.
            HypeLogger.shared.error("STL conversion failed: \(stlError.sanitizedReason)", source: "Interpreter")
            return ""
        } catch {
            HypeLogger.shared.error("STL conversion failed: unknown error", source: "Interpreter")
            return ""
        }
    }

    /// Apply a `set` statement whose target is a chartDataPointRef.
    ///
    /// Extracted from the giant `executeStatement` `switch` so its
    /// locals (`ChartPointLocation`, a copy of `ChartConfig`, etc.)
    /// live in a small leaf frame instead of bloating the main
    /// executeStatement frame for every recursive call.
    private func applyChartDataPointSet(
        property: String,
        target: Expression,
        value: Value,
        env: inout Environment,
        document: inout HypeDocument,
        context: ExecutionContext
    ) async throws {
        guard case .chartDataPointRef(let chartExpr, let seriesExpr, let pointExpr) = target else {
            return
        }
        guard let loc = try await resolveChartDataPointLocation(
            chartExpr: chartExpr,
            seriesExpr: seriesExpr,
            pointExpr: pointExpr,
            env: &env,
            document: document,
            context: context
        ) else {
            return
        }
        var config = loc.config
        switch property.lowercased() {
        case "color", "fillcolor", "fill_color", "rawcolor", "raw_color":
            config.series[loc.seriesIndex].data[loc.pointIndex].color = value
        case "value":
            config.series[loc.seriesIndex].data[loc.pointIndex].value = toNumber(value)
        case "name":
            config.series[loc.seriesIndex].data[loc.pointIndex].name = value
        default:
            // Unknown property on a data point — ignore silently
            // rather than clobbering the chart.
            return
        }
        document.parts[loc.partIndex].chartData = config.toJSON()
    }

    /// Chart-level properties readable via `the <prop> of chart "X"`.
    /// Returns `nil` if the property is not a recognised chart-level
    /// attribute so the caller can fall through to generic part
    /// property handling.
    private func chartLevelProperty(
        _ property: String,
        part: Part
    ) -> Value? {
        guard part.partType == .chart,
              let config = ChartConfig.fromJSON(part.chartData) else {
            return nil
        }
        switch property.lowercased() {
        case "title":
            return config.title
        case "xaxislabel", "x_axis_label", "xlabel", "x_label":
            return config.xAxisLabel
        case "yaxislabel", "y_axis_label", "ylabel", "y_label":
            return config.yAxisLabel
        case "showlegend", "show_legend":
            return config.showLegend ? "true" : "false"
        case "showgrid", "show_grid":
            return config.showGrid ? "true" : "false"
        case "charttype", "chart_type":
            return config.chartType.rawValue
        case "seriescount", "series_count":
            return String(config.series.count)
        default:
            return nil
        }
    }

    /// Apply a chart-level property set. Returns `true` if the property
    /// was recognised and applied (even if the value coerces to a
    /// default), `false` to let the caller fall through to generic
    /// part-property handling.
    private func setChartLevelProperty(
        _ property: String,
        value: Value,
        partIndex: Int,
        document: inout HypeDocument
    ) -> Bool {
        guard document.parts[partIndex].partType == .chart else { return false }
        var config = ChartConfig.fromJSON(document.parts[partIndex].chartData) ?? ChartConfig()
        switch property.lowercased() {
        case "title":
            config.title = value
        case "xaxislabel", "x_axis_label", "xlabel", "x_label":
            config.xAxisLabel = value
        case "yaxislabel", "y_axis_label", "ylabel", "y_label":
            config.yAxisLabel = value
        case "showlegend", "show_legend":
            config.showLegend = isTruthy(value)
        case "showgrid", "show_grid":
            config.showGrid = isTruthy(value)
        case "charttype", "chart_type":
            if let t = ChartType(rawValue: value.lowercased()) {
                config.chartType = t
            } else {
                return false
            }
        default:
            return false
        }
        document.parts[partIndex].chartData = config.toJSON()
        return true
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

    // MARK: - Sprite Area Helpers

    private struct SpriteTargetLocation {
        var partIndex: Int
        var sceneId: UUID
        var nodeId: UUID?
    }

    private func spriteAreaPartIndices(document: HypeDocument, currentCardId: UUID) -> [Int] {
        let cardParts = document.partsForCard(currentCardId)
        let bgParts = document.cards
            .first(where: { $0.id == currentCardId })
            .map { document.partsForBackground($0.backgroundId) } ?? []
        let ids = Set((cardParts + bgParts).filter { $0.partType == .spriteArea }.map(\.id))
        return document.parts.indices.filter { ids.contains(document.parts[$0].id) }
    }

    private func resolveSpriteAreaPartIndex(
        named areaName: String? = nil,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Int? {
        if let areaName, !areaName.isEmpty {
            return document.parts.firstIndex(where: {
                $0.partType == .spriteArea && $0.name.lowercased() == areaName.lowercased()
            })
        }
        return spriteAreaPartIndices(document: document, currentCardId: currentCardId).first
    }

    private func spriteAreaSpec(
        partIndex: Int,
        document: HypeDocument
    ) -> SpriteAreaSpec? {
        guard document.parts.indices.contains(partIndex) else { return nil }
        return document.parts[partIndex].spriteAreaSpecModel
    }

    private func activeScene(
        partIndex: Int,
        document: HypeDocument
    ) -> SceneSpec? {
        spriteAreaSpec(partIndex: partIndex, document: document)?.activeScene
    }

    @discardableResult
    private func mutateSpriteAreaSpec(
        partIndex: Int,
        document: inout HypeDocument,
        transform: (inout SpriteAreaSpec) -> Void
    ) -> Bool {
        guard document.parts.indices.contains(partIndex) else { return false }
        var part = document.parts[partIndex]
        var spec = part.spriteAreaSpecModel ?? SpriteAreaSpec(
            defaultSceneNamed: part.name.isEmpty ? "main" : part.name,
            fallbackSize: SizeSpec(width: part.width, height: part.height)
        )
        transform(&spec)
        part.setSpriteAreaSpec(spec)
        document.parts[partIndex] = part
        return true
    }

    @discardableResult
    private func mutateActiveScene(
        partIndex: Int,
        document: inout HypeDocument,
        transform: (inout SceneSpec) -> Void
    ) -> Bool {
        mutateSpriteAreaSpec(partIndex: partIndex, document: &document) { spec in
            var scene = spec.activeScene ?? SceneSpec(size: spec.designSize, scaleMode: spec.scaleMode)
            transform(&scene)
            spec.setActiveScene(scene)
        }
    }

    private func locateSpriteTarget(
        id: UUID,
        document: HypeDocument,
        currentCardId: UUID
    ) -> SpriteTargetLocation? {
        for partIndex in spriteAreaPartIndices(document: document, currentCardId: currentCardId) {
            guard let areaSpec = spriteAreaSpec(partIndex: partIndex, document: document),
                  let activeScene = areaSpec.activeScene,
                  let sceneEntry = areaSpec.activeSceneEntry else {
                continue
            }
            if sceneEntry.id == id {
                return SpriteTargetLocation(partIndex: partIndex, sceneId: sceneEntry.id, nodeId: nil)
            }
            if activeScene.node(id: id) != nil {
                return SpriteTargetLocation(partIndex: partIndex, sceneId: sceneEntry.id, nodeId: id)
            }
        }
        return nil
    }

    private func nodeLocation(
        named name: String,
        objectType: String? = nil,
        document: HypeDocument,
        currentCardId: UUID
    ) -> (partIndex: Int, node: HypeNodeSpec)? {
        for partIndex in spriteAreaPartIndices(document: document, currentCardId: currentCardId) {
            guard let scene = activeScene(partIndex: partIndex, document: document),
                  let node = scene.node(named: name) else {
                continue
            }
            if let objectType,
               !objectType.isEmpty,
               objectType.lowercased() != node.nodeType.rawValue.lowercased(),
               !(objectType.lowercased() == "group" && node.nodeType == .group) {
                continue
            }
            return (partIndex, node)
        }
        return nil
    }

    private func sceneLocation(
        named name: String,
        document: HypeDocument,
        currentCardId: UUID
    ) -> (partIndex: Int, areaSpec: SpriteAreaSpec)? {
        for partIndex in spriteAreaPartIndices(document: document, currentCardId: currentCardId) {
            guard let areaSpec = spriteAreaSpec(partIndex: partIndex, document: document) else { continue }
            if areaSpec.scenes.contains(where: { $0.scene.name.lowercased() == name.lowercased() }) {
                return (partIndex, areaSpec)
            }
        }
        return nil
    }

    private func effectiveNodeSize(_ node: HypeNodeSpec) -> SizeSpec {
        if let size = node.size { return size }
        if node.nodeType == .shape { return SizeSpec(width: 50, height: 50) }
        return SizeSpec(width: 0, height: 0)
    }

    private func ensureNodeSize(_ node: inout HypeNodeSpec) {
        if node.size == nil {
            node.size = effectiveNodeSize(node)
        }
    }

    private func applyNodePropertySet(
        property: String,
        value: Value,
        to node: inout HypeNodeSpec
    ) {
        switch property.lowercased() {
        case "loc", "location", "position":
            let comps = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if comps.count >= 2 {
                node.position = PointSpec(x: comps[0], y: comps[1])
            }
        case "left", "left_pos":
            ensureNodeSize(&node)
            let size = effectiveNodeSize(node)
            node.position.x = toNumber(value) + size.width / 2
        case "top", "top_pos":
            ensureNodeSize(&node)
            let size = effectiveNodeSize(node)
            node.position.y = toNumber(value) + size.height / 2
        case "right":
            ensureNodeSize(&node)
            let size = effectiveNodeSize(node)
            node.position.x = toNumber(value) - size.width / 2
        case "bottom":
            ensureNodeSize(&node)
            let size = effectiveNodeSize(node)
            node.position.y = toNumber(value) - size.height / 2
        case "rotation":
            node.rotation = toNumber(value)
        case "alpha":
            node.alpha = toNumber(value)
        case "xscale":
            node.xScale = toNumber(value)
        case "yscale":
            node.yScale = toNumber(value)
        case "zposition":
            node.zPosition = toNumber(value)
        case "hidden":
            node.isHidden = isTruthy(value)
        case "name":
            node.name = value
        case "text", "contents", "textcontent":
            node.text = value
        case "fontname", "font":
            node.fontName = value
        case "fontsize", "textsize":
            node.fontSize = toNumber(value)
        case "fontcolor", "textcolor", "color":
            node.fontColor = value
        case "textstyle", "text_style":
            // Normalize through TextStyleFlags so the stored
            // rawString is canonical ("bold, italic"). Empty /
            // "plain" both clear styling — `applyLabelTextStyle`
            // sees `isPlain` and resets `attributedText = nil`,
            // restoring the simple text path on SKLabelNode.
            node.textStyle = TextStyleFlags(string: value).rawString
        case "width":
            let oldSize = effectiveNodeSize(node)
            let left = node.position.x - oldSize.width / 2
            ensureNodeSize(&node)
            let newWidth = toNumber(value)
            node.size?.width = newWidth
            node.position.x = left + newWidth / 2
        case "height":
            let oldSize = effectiveNodeSize(node)
            let top = node.position.y - oldSize.height / 2
            ensureNodeSize(&node)
            let newHeight = toNumber(value)
            node.size?.height = newHeight
            node.position.y = top + newHeight / 2
        case "fillcolor", "fill":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            node.shapeSpec?.fillColor = value
        case "strokecolor", "stroke":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            node.shapeSpec?.strokeColor = value
        case "linewidth", "strokewidth":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            node.shapeSpec?.lineWidth = toNumber(value)
        case "cornerradius":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            node.shapeSpec?.cornerRadius = toNumber(value)
        case "shapetype":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            let fallback = node.shapeSpec?.shapeType ?? .rect
            node.shapeSpec?.shapeType = SpriteShapeType.tolerantValue(value, default: fallback)
        case "size":
            let comps = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if comps.count >= 2 {
                node.size = SizeSpec(width: comps[0], height: comps[1])
            }
        case "audioloop", "loop":
            node.audioLoop = isTruthy(value)
        case "audiovolume", "volume":
            node.audioVolume = toNumber(value)
        case "audioautoplay", "autoplay":
            node.audioAutoplay = isTruthy(value)
        case "audiopositional", "positional":
            node.audioPositional = isTruthy(value)
        case "videoloop":
            node.videoLoop = isTruthy(value)
        case "videoautoplay":
            node.videoAutoplay = isTruthy(value)
        case "cameratarget", "target":
            node.cameraTarget = value
        case "zoom":
            node.xScale = toNumber(value)
            node.yScale = toNumber(value)
        case "columns":
            if node.tileMapSpec != nil {
                node.tileMapSpec?.columns = Int(toNumber(value))
            }
        case "rows":
            if node.tileMapSpec != nil {
                node.tileMapSpec?.rows = Int(toNumber(value))
            }
        case "tilesize":
            if node.tileMapSpec != nil {
                let size = toNumber(value)
                node.tileMapSpec?.tileWidth = size
                node.tileMapSpec?.tileHeight = size
            }
        case "particlebirthrate", "birthrate":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.particleBirthRate = toNumber(value)
        case "particlelifetime", "lifetime" where node.nodeType == .emitter:
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.particleLifetime = toNumber(value)
        case "particlespeed", "speed" where node.nodeType == .emitter:
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.particleSpeed = toNumber(value)
        case "emissionangle":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.emissionAngle = toNumber(value)
        case "emissionanglerange":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.emissionAngleRange = toNumber(value)
        case "particlealpha" where node.nodeType == .emitter:
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.particleAlpha = toNumber(value)
        case "particlescale":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.particleScale = toNumber(value)
        case "particlecolor":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.particleColor = value
        case "velocity":
            let comps = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if comps.count >= 2 {
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                node.physicsBody?.velocityX = comps[0]
                node.physicsBody?.velocityY = comps[1]
            }
        case "velocityx", "velocity_x":
            // Scalar X-component setter. Preserves Y. AI models and
            // humans writing physics scripts naturally reach for
            // `velocityX` separately from `velocityY` rather than
            // composing a "x,y" string — support both forms.
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.velocityX = toNumber(value)
        case "velocityy", "velocity_y":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.velocityY = toNumber(value)
        case "angularvelocity":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.angularVelocity = toNumber(value)
        case "density":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.density = toNumber(value)
        case "lineardamping", "damping":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.linearDamping = toNumber(value)
        case "angulardamping":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.angularDamping = toNumber(value)
        case "mass":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.mass = toNumber(value)
        case "friction":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.friction = toNumber(value)
        case "restitution", "bounce":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.restitution = toNumber(value)
        case "isdynamic", "dynamic":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.isDynamic = isTruthy(value)
        case "affectedbygravity":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.affectedByGravity = isTruthy(value)
        case "allowsrotation":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.allowsRotation = isTruthy(value)
        case "categorybitmask", "category":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.categoryBitmask = UInt32(toNumber(value))
        case "contacttestbitmask", "contacttest":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.contactTestBitmask = UInt32(toNumber(value))
        case "collisionbitmask", "collision":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.collisionBitmask = UInt32(toNumber(value))
        default:
            break
        }
    }

    private func nodePropertyValue(_ node: HypeNodeSpec, property: String) -> Value {
        switch property.lowercased() {
        case "name":        return node.name
        case "loc", "location", "position":
            return "\(formatNumber(node.position.x)),\(formatNumber(node.position.y))"
        case "left", "left_pos":
            return formatNumber(node.position.x - effectiveNodeSize(node).width / 2)
        case "top", "top_pos":
            return formatNumber(node.position.y - effectiveNodeSize(node).height / 2)
        case "right":
            return formatNumber(node.position.x + effectiveNodeSize(node).width / 2)
        case "bottom":
            return formatNumber(node.position.y + effectiveNodeSize(node).height / 2)
        case "rotation":    return formatNumber(node.rotation)
        case "alpha":       return formatNumber(node.alpha)
        case "xscale":      return formatNumber(node.xScale)
        case "yscale":      return formatNumber(node.yScale)
        case "zposition":   return formatNumber(node.zPosition)
        case "hidden":      return node.isHidden ? "true" : "false"
        case "width":       return formatNumber(node.size?.width ?? 0)
        case "height":      return formatNumber(node.size?.height ?? 0)
        case "size":
            return "\(formatNumber(node.size?.width ?? 0)),\(formatNumber(node.size?.height ?? 0))"
        case "text", "contents", "textcontent": return node.text ?? ""
        case "fontname", "font":    return node.fontName ?? ""
        case "fontsize", "textsize": return formatNumber(node.fontSize ?? 14)
        case "fontcolor", "textcolor", "color": return node.fontColor ?? "#000000"
        case "textstyle", "text_style": return node.textStyle ?? "plain"
        case "fillcolor", "fill":   return node.shapeSpec?.fillColor ?? ""
        case "strokecolor", "stroke": return node.shapeSpec?.strokeColor ?? ""
        case "linewidth", "strokewidth": return formatNumber(node.shapeSpec?.lineWidth ?? 1)
        case "cornerradius": return formatNumber(node.shapeSpec?.cornerRadius ?? 0)
        case "shapetype": return node.shapeSpec?.shapeType.rawValue ?? ""
        case "audioloop", "loop": return (node.audioLoop ?? false) ? "true" : "false"
        case "audiovolume", "volume": return formatNumber(node.audioVolume ?? 1.0)
        case "audioautoplay", "autoplay": return (node.audioAutoplay ?? true) ? "true" : "false"
        case "audiopositional", "positional": return (node.audioPositional ?? false) ? "true" : "false"
        case "videoloop": return (node.videoLoop ?? false) ? "true" : "false"
        case "videoautoplay": return (node.videoAutoplay ?? true) ? "true" : "false"
        case "columns": return node.tileMapSpec != nil ? String(node.tileMapSpec!.columns) : "0"
        case "rows": return node.tileMapSpec != nil ? String(node.tileMapSpec!.rows) : "0"
        case "tilesize": return node.tileMapSpec != nil ? formatNumber(node.tileMapSpec!.tileWidth) : "0"
        case "cameratarget", "target": return node.cameraTarget ?? ""
        case "zoom": return formatNumber(node.xScale)
        case "particlebirthrate", "birthrate":
            return formatNumber(node.emitterSpec?.particleBirthRate ?? 50)
        case "particlelifetime", "lifetime" where node.nodeType == .emitter:
            return formatNumber(node.emitterSpec?.particleLifetime ?? 2)
        case "particlespeed", "speed" where node.nodeType == .emitter:
            return formatNumber(node.emitterSpec?.particleSpeed ?? 100)
        case "emissionangle":
            return formatNumber(node.emitterSpec?.emissionAngle ?? 90)
        case "emissionanglerange":
            return formatNumber(node.emitterSpec?.emissionAngleRange ?? 360)
        case "particlealpha" where node.nodeType == .emitter:
            return formatNumber(node.emitterSpec?.particleAlpha ?? 1)
        case "particlescale":
            return formatNumber(node.emitterSpec?.particleScale ?? 0.3)
        case "particlecolor":
            return node.emitterSpec?.particleColor ?? "#FFFFFF"
        case "velocity":
            let vx = node.physicsBody?.velocityX ?? 0
            let vy = node.physicsBody?.velocityY ?? 0
            return "\(formatNumber(vx)),\(formatNumber(vy))"
        case "velocityx", "velocity_x":
            return formatNumber(node.physicsBody?.velocityX ?? 0)
        case "velocityy", "velocity_y":
            return formatNumber(node.physicsBody?.velocityY ?? 0)
        case "angularvelocity": return formatNumber(node.physicsBody?.angularVelocity ?? 0)
        case "density": return formatNumber(node.physicsBody?.density ?? 1)
        case "lineardamping", "damping": return formatNumber(node.physicsBody?.linearDamping ?? 0.1)
        case "angulardamping": return formatNumber(node.physicsBody?.angularDamping ?? 0.1)
        case "mass": return formatNumber(node.physicsBody?.mass ?? 1)
        case "friction": return formatNumber(node.physicsBody?.friction ?? 0.2)
        case "restitution", "bounce": return formatNumber(node.physicsBody?.restitution ?? 0.2)
        case "isdynamic", "dynamic": return (node.physicsBody?.isDynamic ?? true) ? "true" : "false"
        case "affectedbygravity": return (node.physicsBody?.affectedByGravity ?? true) ? "true" : "false"
        case "allowsrotation": return (node.physicsBody?.allowsRotation ?? true) ? "true" : "false"
        case "categorybitmask", "category": return String(node.physicsBody?.categoryBitmask ?? 0xFFFFFFFF)
        case "contacttestbitmask", "contacttest": return String(node.physicsBody?.contactTestBitmask ?? 0)
        case "collisionbitmask", "collision": return String(node.physicsBody?.collisionBitmask ?? 0xFFFFFFFF)
        default: return ""
        }
    }

    // MARK: - Node Hierarchy Helpers

    /// Recursively search for a parent node by name and add a child node to it.
    /// Returns true if the parent was found and the child was added.
    private static func addNodeToParent(node: HypeNodeSpec, parentName: String, nodes: inout [HypeNodeSpec]) -> Bool {
        for i in 0..<nodes.count {
            if nodes[i].name.lowercased() == parentName.lowercased() {
                nodes[i].children.append(node)
                return true
            }
            if addNodeToParent(node: node, parentName: parentName, nodes: &nodes[i].children) {
                return true
            }
        }
        return false
    }

    /// Recursively find a node by name in a node tree. Returns the node if found.
    private static func findNode(name: String, in nodes: [HypeNodeSpec]) -> HypeNodeSpec? {
        for node in nodes {
            if node.name.lowercased() == name.lowercased() { return node }
            if let found = findNode(name: name, in: node.children) { return found }
        }
        return nil
    }

    /// Recursively remove a node by name from a node tree. Returns the removed node if found.
    @discardableResult
    private static func removeNode(name: String, from nodes: inout [HypeNodeSpec]) -> HypeNodeSpec? {
        if let idx = nodes.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            return nodes.remove(at: idx)
        }
        for i in 0..<nodes.count {
            if let removed = removeNode(name: name, from: &nodes[i].children) {
                return removed
            }
        }
        return nil
    }
}

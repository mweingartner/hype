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
    /// Show an input dialog with a prompt and prefilled default value.
    func showAsk(prompt: String, defaultValue: String) -> String
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

    func showAsk(prompt: String, defaultValue: String) -> String {
        showAsk(prompt: prompt)
    }

    func showAskAsync(prompt: String, defaultValue: String) async -> String {
        await MainActor.run {
            showAsk(prompt: prompt, defaultValue: defaultValue)
        }
    }
}

/// Default dialog provider that just returns the prompt (used when no UI is available).
public struct StubDialogProvider: DialogProvider, Sendable {
    public init() {}
    public func showAnswer(prompt: String) -> String { return "OK" }
    public func showAsk(prompt: String) -> String { return "" }
    public func showAsk(prompt: String, defaultValue: String) -> String { return defaultValue }
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

/// Protocol for system-level operations (beep, play sound, etc.) — injected by the UI layer.
public protocol SystemProvider: Sendable {
    func beep(count: Int) async
    func playSound(name: String, document: HypeDocument) async
    func playNotes(instrument: String, noteString: String, tempo: Int, document: HypeDocument) async
    func stopSound() async
    func currentSoundName() async -> String
    func playMusicPattern(_ pattern: MusicPatternSpec, loop: Bool, document: HypeDocument) async
    func playSustainedMusicNote(_ note: MusicSustainedNoteSpec, document: HypeDocument) async
    func stopSustainedMusicNote(id: UUID) async
    func stopSustainedMusicNotes(forPart partId: UUID?) async
    func stopMusic() async
    func pauseMusic() async
    func resumeMusic() async
    func currentMusicState() async -> String
    func appleMusicAuthorizationStatus() async -> AppleMusicAuthorizationState
    func authorizeAppleMusic() async -> AppleMusicAuthorizationState
    func appleMusicCapabilities() async -> AppleMusicCapabilities
    func searchAppleMusic(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef]
    func playAppleMusic(_ item: AppleMusicItemRef, engine: AppleMusicPlaybackEngine) async throws
    func pauseAppleMusic(engine: AppleMusicPlaybackEngine) async
    func resumeAppleMusic(engine: AppleMusicPlaybackEngine) async throws
    func stopAppleMusic(engine: AppleMusicPlaybackEngine) async
    func currentAppleMusicState(engine: AppleMusicPlaybackEngine) async -> String
    func seekAppleMusic(to position: Double, engine: AppleMusicPlaybackEngine) async throws
    func currentAppleMusicPosition(engine: AppleMusicPlaybackEngine) async -> Double
}

public extension SystemProvider {
    func beep(count: Int) async {}
    func playSound(name: String, document: HypeDocument) async {}
    func playNotes(instrument: String, noteString: String, tempo: Int, document: HypeDocument) async {}
    func stopSound() async {}
    func currentSoundName() async -> String { "done" }
    func playMusicPattern(_ pattern: MusicPatternSpec, loop: Bool, document: HypeDocument) async {}
    func playSustainedMusicNote(_ note: MusicSustainedNoteSpec, document: HypeDocument) async {}
    func stopSustainedMusicNote(id: UUID) async {}
    func stopSustainedMusicNotes(forPart partId: UUID?) async {}
    func stopMusic() async {}
    func pauseMusic() async {}
    func resumeMusic() async {}
    func currentMusicState() async -> String { "stopped" }
    func appleMusicAuthorizationStatus() async -> AppleMusicAuthorizationState { .unavailable }
    func authorizeAppleMusic() async -> AppleMusicAuthorizationState { .unavailable }
    func appleMusicCapabilities() async -> AppleMusicCapabilities { AppleMusicCapabilities() }
    func searchAppleMusic(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef] { throw AppleMusicProviderError.unavailable }
    func playAppleMusic(_ item: AppleMusicItemRef, engine: AppleMusicPlaybackEngine) async throws { throw AppleMusicProviderError.unavailable }
    func pauseAppleMusic(engine: AppleMusicPlaybackEngine) async {}
    func resumeAppleMusic(engine: AppleMusicPlaybackEngine) async throws { throw AppleMusicProviderError.unavailable }
    func stopAppleMusic(engine: AppleMusicPlaybackEngine) async {}
    func currentAppleMusicState(engine: AppleMusicPlaybackEngine) async -> String { "unavailable" }
    func seekAppleMusic(to position: Double, engine: AppleMusicPlaybackEngine) async throws { throw AppleMusicProviderError.unavailable }
    func currentAppleMusicPosition(engine: AppleMusicPlaybackEngine) async -> Double { 0 }
}

/// Default system provider that does nothing (used when no UI is available).
public struct StubSystemProvider: SystemProvider, Sendable {
    public init() {}
}

// MARK: - HostApplicationProvider

/// The target object for `print card` / `print field` commands.
public enum HostPrintTarget: Sendable {
    /// Print the current card as a rendered image.
    case card
    /// Print the text content of a named or numbered field.
    case field(String)
}

/// Protocol for application-shell operations that require platform UI access —
/// injected by the UI layer, mirroring the `SystemProvider` pattern.
///
/// Every method has a default no-op implementation in the extension below so
/// the stub and CLI paths continue to compile without changes.
public protocol HostApplicationProvider: Sendable {
    /// Suppress canvas redraws for the duration of a visual batch.
    func lockScreen() async
    /// Re-enable canvas redraws and refresh the display.
    func unlockScreen() async
    /// Open a `.hype` stack at the given absolute path.
    func openStack(path: String) async
    /// Save the frontmost stack document.
    func saveStack() async
    /// Close the frontmost window.
    func closeWindow() async
    /// Terminate the application.
    func quitApp() async
    /// Open the Script Editor for the object identified by `objectId`.
    /// `nil` falls back to editing the current card's script.
    func editScript(ofObjectId: UUID?) async
    /// Print a card or field.
    func print(target: HostPrintTarget) async
    /// Perform a named menu item from the curated allowlist.
    /// Returns `true` if the item was recognised and handled, `false` otherwise.
    /// Unknown or destructive items always return `false` without side-effects.
    func doMenu(item: String) async -> Bool
    /// Return the titles of every top-level menu in the application's menu bar.
    /// Used by `the menus` HypeTalk property.
    /// The stub returns `[]`; the AppKit implementation reads `NSApplication.shared.mainMenu`.
    func menuTitles() async -> [String]
}

public extension HostApplicationProvider {
    func lockScreen() async {}
    func unlockScreen() async {}
    func openStack(path: String) async {}
    func saveStack() async {}
    func closeWindow() async {}
    func quitApp() async {}
    func editScript(ofObjectId: UUID?) async {}
    func print(target: HostPrintTarget) async {}
    func doMenu(item: String) async -> Bool { false }
    func menuTitles() async -> [String] { [] }
}

/// Default host provider that silently no-ops all operations.
/// Used by CLI tools, benchmarks, and test paths that have no UI context.
public struct StubHostApplicationProvider: HostApplicationProvider, Sendable {
    public init() {}
}

/// Context for script execution.
public struct ExecutionContext: Sendable {
    public var targetId: UUID
    /// The object that *originally* received the message at the top of the dispatch
    /// chain. Distinct from `targetId` (which advances up the pass-up chain); this
    /// stays fixed so `the target` always returns the initial recipient.
    public var originalTargetId: UUID
    public var currentCardId: UUID
    public var document: HypeDocument
    public var instructionLimit: Int
    public var dialogProvider: DialogProvider
    public var drawingProvider: DrawingProvider
    public var systemProvider: SystemProvider
    /// Provider for application-shell commands (`open stack`, `save stack`, `quit`, etc.).
    public var hostProvider: any HostApplicationProvider
    public var aiProvider: any AIScriptingProvider
    public var speechOutputProvider: SpeechOutputProvider
    public var runtimeProvider: (any ScriptRuntimeProviding)?
    public var externalRegistry: HyperCardExternalRegistry
    /// Phase 3: Meshy scripting provider for `ask meshy` statements.
    /// `nil` degrades gracefully — `ask meshy` sets `it = ""` and returns.
    public var meshyProvider: (any MeshyScriptingProvider)?
    public var mouseX: Double
    public var mouseY: Double
    public var scriptContext: ScriptDispatchContext?
    public var appScript: String
    public var nestedSendDepth: Int
    public var profiler: HypeTalkExecutionProfiler?
    /// Provider for sandboxed `read from file` / `write to file` operations.
    /// `StubFileAccessProvider` (deny-by-default) is used when file access is disabled.
    public var fileProvider: any FileAccessProvider
    /// Current nesting depth of `do <expr>` evaluation.
    /// Counted independently of `nestedSendDepth`; capped at `Interpreter.maxNestedEvalDepth`.
    public var nestedEvalDepth: Int

    /// Consolidated initializer.
    ///
    /// Two near-identical inits previously existed (one from the
    /// HyperCard-import work that took a `scriptContext`, one from
    /// the benchmark/CLI optimization work that added `profiler`).
    /// Both parameters are optional so callers from either era stay
    /// source-compatible; only one init now exists so the compiler
    /// stops complaining about ambiguous use.
    public init(targetId: UUID, currentCardId: UUID, document: HypeDocument, instructionLimit: Int = 1_000_000,
                dialogProvider: DialogProvider = StubDialogProvider(),
                drawingProvider: DrawingProvider = StubDrawingProvider(),
                systemProvider: SystemProvider = StubSystemProvider(),
                hostProvider: any HostApplicationProvider = StubHostApplicationProvider(),
                aiProvider: any AIScriptingProvider = StubAIScriptingProvider(),
                speechOutputProvider: SpeechOutputProvider = StubSpeechOutputProvider(),
                runtimeProvider: (any ScriptRuntimeProviding)? = nil,
                externalRegistry: HyperCardExternalRegistry = .default,
                meshyProvider: (any MeshyScriptingProvider)? = nil,
                mouseX: Double = 0, mouseY: Double = 0,
                scriptContext: ScriptDispatchContext? = nil,
                appScript: String = "",
                nestedSendDepth: Int = 0,
                profiler: HypeTalkExecutionProfiler? = nil,
                fileProvider: any FileAccessProvider = StubFileAccessProvider(),
                nestedEvalDepth: Int = 0,
                originalTargetId: UUID? = nil) {
        self.targetId = targetId
        self.originalTargetId = originalTargetId ?? targetId
        self.currentCardId = currentCardId
        self.document = document
        self.instructionLimit = instructionLimit
        self.dialogProvider = dialogProvider
        self.drawingProvider = drawingProvider
        self.systemProvider = systemProvider
        self.hostProvider = hostProvider
        self.aiProvider = aiProvider
        self.speechOutputProvider = speechOutputProvider
        self.runtimeProvider = runtimeProvider
        self.externalRegistry = externalRegistry
        self.meshyProvider = meshyProvider
        self.mouseX = mouseX
        self.mouseY = mouseY
        self.scriptContext = scriptContext
        self.appScript = appScript
        self.nestedSendDepth = nestedSendDepth
        self.profiler = profiler
        self.fileProvider = fileProvider
        self.nestedEvalDepth = nestedEvalDepth
    }
}

/// The result of executing a handler.
public struct ExecutionResult: Sendable {
    public var status: ExecutionStatus
    public var returnValue: Value?
    public var modifiedDocument: HypeDocument?
    public var error: ScriptError?
    public var navigationTarget: UUID?
    public var projectNavigationTarget: ProjectNavigationTarget?
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
        projectNavigationTarget: ProjectNavigationTarget? = nil,
        showAllCards: Bool = false,
        visualEffect: String? = nil,
        visualEffectDuration: Double? = nil
    ) {
        self.status = status
        self.returnValue = returnValue
        self.modifiedDocument = modifiedDocument
        self.error = error
        self.navigationTarget = navigationTarget
        self.projectNavigationTarget = projectNavigationTarget
        self.showAllCards = showAllCards
        self.visualEffect = visualEffect
        self.visualEffectDuration = visualEffectDuration
    }
}

/// Execution outcome.
public enum ExecutionStatus: Sendable {
    case completed, passed, error, cancelled
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

private struct PartLookupKey: Hashable {
    var objectType: String
    var identifier: String
    var currentCardId: UUID
}

/// Mutable variable environment for script execution.
private struct Environment {
    var locals: [String: Value] = [:]
    var globals: [String: Value]
    var handlerParams: [Value] = []
    var partLookupCache: [PartLookupKey: Int] = [:]
    var it: Value = ""
    /// Phase 3: `the result` — set by `ask meshy` on success. Mirrors `it`.
    var result: Value = ""
    var globalNames: Set<String> = []
    var effectiveCurrentCardId: UUID?
    /// A `wait` followed by `send "... " to me` is commonly used as
    /// a timer-loop idiom. Defer exactly that next self-send through
    /// StackRuntime so it does not grow nested synchronous send depth.
    var deferNextSelfSend = false
    /// The current item delimiter. Classic HyperCard resets this to "," at each idle
    /// (i.e. each top-level dispatch / fresh Environment). Single character per spec.
    var itemDelimiter: String = ","
    /// Whether `lock screen` is in effect.  While true, per-statement publish
    /// and yield calls are suppressed entirely; a single flush publish fires at
    /// `unlock screen`.
    var screenLocked: Bool = false

    init(globals: [String: Value], handlerParams: [Value] = []) {
        self.globals = globals.reduce(into: [String: Value]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
        self.handlerParams = handlerParams
    }

    mutating func getVariable(_ name: String) -> Value {
        let key = name.lowercased()
        return getVariableKey(key)
    }

    /// Retrieve a variable value using an already-lowercased key.
    /// Avoids re-lowercasing in hot paths where the key was computed once.
    mutating func getVariableKey(_ key: String) -> Value {
        if globalNames.contains(key) {
            return globals[key] ?? ""
        }
        return locals[key] ?? ""
    }

    mutating func setVariable(_ name: String, _ value: Value) {
        let key = name.lowercased()
        setVariableKey(key, value)
    }

    mutating func setVariableKey(_ key: String, _ value: Value) {
        if globalNames.contains(key) {
            globals[key] = value
        } else {
            locals[key] = value
        }
    }

    mutating func invalidatePartLookupCache() {
        partLookupCache.removeAll(keepingCapacity: true)
    }

    func currentCardId(fallback: UUID) -> UUID {
        effectiveCurrentCardId ?? fallback
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

private final class SpriteAreaMutationBatch: @unchecked Sendable {
    private final class Entry: @unchecked Sendable {
        var spec: SpriteAreaSpec
        var dirty: Bool

        init(spec: SpriteAreaSpec, dirty: Bool) {
            self.spec = spec
            self.dirty = dirty
        }
    }

    private var entries: [UUID: Entry] = [:]

    func spriteAreaSpec(partIndex: Int, document: HypeDocument) -> SpriteAreaSpec? {
        entry(partIndex: partIndex, document: document)?.spec
    }

    private func entry(partIndex: Int, document: HypeDocument) -> Entry? {
        guard document.parts.indices.contains(partIndex) else { return nil }
        let part = document.parts[partIndex]
        if let entry = entries[part.id] {
            return entry
        }
        guard let spec = part.spriteAreaSpecModel else { return nil }
        let entry = Entry(spec: spec, dirty: false)
        entries[part.id] = entry
        return entry
    }

    func mutateSpriteAreaSpec(
        partIndex: Int,
        document: HypeDocument,
        transform: (inout SpriteAreaSpec) -> Void
    ) -> Bool {
        guard document.parts.indices.contains(partIndex) else { return false }
        let part = document.parts[partIndex]
        let entry = entry(partIndex: partIndex, document: document) ?? Entry(
            spec: SpriteAreaSpec(
                defaultSceneNamed: part.name.isEmpty ? "main" : part.name,
                fallbackSize: SizeSpec(width: part.width, height: part.height)
            ),
            dirty: false
        )
        entries[part.id] = entry
        transform(&entry.spec)
        entry.dirty = true
        return true
    }

    func mutateActiveScene(
        partIndex: Int,
        document: HypeDocument,
        transform: (inout SceneSpec) -> Void
    ) -> Bool {
        guard document.parts.indices.contains(partIndex) else { return false }
        let part = document.parts[partIndex]
        let entry = entry(partIndex: partIndex, document: document) ?? Entry(
            spec: SpriteAreaSpec(
                defaultSceneNamed: part.name.isEmpty ? "main" : part.name,
                fallbackSize: SizeSpec(width: part.width, height: part.height)
            ),
            dirty: false
        )
        entries[part.id] = entry

        if entry.spec.scenes.isEmpty {
            let scene = SceneSpec(size: entry.spec.designSize, scaleMode: entry.spec.scaleMode)
            let sceneEntry = SpriteAreaScene(scene: scene)
            entry.spec.scenes = [sceneEntry]
            entry.spec.activeSceneID = sceneEntry.id
        }

        let activeIndex = entry.spec.scenes.firstIndex(where: { $0.id == entry.spec.activeSceneID }) ?? 0
        entry.spec.activeSceneID = entry.spec.scenes[activeIndex].id

        entry.spec.scenes[activeIndex].scene.size = entry.spec.designSize
        entry.spec.scenes[activeIndex].scene.scaleMode = entry.spec.scaleMode
        entry.spec.scenes[activeIndex].scene.showsPhysics = entry.spec.showsPhysics
        entry.spec.scenes[activeIndex].scene.showsFPS = entry.spec.showsFPS
        entry.spec.scenes[activeIndex].scene.showsNodeCount = entry.spec.showsNodeCount

        transform(&entry.spec.scenes[activeIndex].scene)

        let activeScene = entry.spec.scenes[activeIndex].scene
        entry.spec.designSize = activeScene.size
        entry.spec.scaleMode = activeScene.scaleMode
        entry.spec.showsPhysics = activeScene.showsPhysics
        entry.spec.showsFPS = activeScene.showsFPS
        entry.spec.showsNodeCount = activeScene.showsNodeCount
        entry.dirty = true
        return true
    }

    func flush(to document: inout HypeDocument) {
        for (partId, entry) in entries where entry.dirty {
            guard let partIndex = document.parts.firstIndex(where: { $0.id == partId }) else { continue }
            document.parts[partIndex].setSpriteAreaSpec(entry.spec)
        }
    }
}

private enum SpriteAreaMutationScope {
    @TaskLocal static var current: SpriteAreaMutationBatch?
}

// MARK: - Interpreter

/// Tree-walking interpreter for HypeTalk scripts.
public struct Interpreter: Sendable {

    public init() {}

    // MARK: - Security limits for `do <expr>` eval

    /// Maximum nesting depth for `do`-inside-`do` evaluation.
    /// Counted independently of `nestedSendDepth` (the `send` budget).
    static let maxNestedEvalDepth = 8

    /// Maximum UTF-8 byte count of a string passed to `do`.
    /// Limits parse-time work, which runs outside the instruction budget.
    static let maxDoEvalBytes = 64 * 1024

    /// Reserved global key for the HyperCard-style Message Box container.
    /// Accessible as `msg`, `the message`, or `message box` in scripts.
    /// MUST be all-lowercase: `Environment.init(globals:)` lowercases every
    /// global key when seeding from `document.scriptGlobals`, so a mixed-case
    /// key would not survive a round-trip across handler dispatches (the
    /// message box must persist for the whole session).
    static let messageBoxKey = "__messagebox"

    /// Execute a handler with the given parameters and context.
    public func execute(handler: Handler, params: [Value], context: ExecutionContext) -> ExecutionResult {
        blockingWait {
            await executeAsync(handler: handler, params: params, context: context)
        }
    }

    public func executeAsync(handler: Handler, params: [Value], context: ExecutionContext) async -> ExecutionResult {
        let spriteAreaMutationBatch = SpriteAreaMutationBatch()
        return await SpriteAreaMutationScope.$current.withValue(spriteAreaMutationBatch) {
            await executeAsyncImpl(
                handler: handler,
                params: params,
                context: context,
                spriteAreaMutationBatch: spriteAreaMutationBatch
            )
        }
    }

    private func executeAsyncImpl(
        handler: Handler,
        params: [Value],
        context: ExecutionContext,
        spriteAreaMutationBatch: SpriteAreaMutationBatch
    ) async -> ExecutionResult {
        context.profiler?.recordHandlerInvocation(handler.name)
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
        var projectNavigationTarget: ProjectNavigationTarget? = nil
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
        if handlerLower == "chartchange" {
            if !params.isEmpty {
                if env.locals["dataset"] == nil { env.locals["dataset"] = params[0] }
                if env.locals["datasetname"] == nil { env.locals["datasetname"] = params[0] }
                if env.locals["chartseries"] == nil { env.locals["chartseries"] = params[0] }
                if env.locals["series"] == nil { env.locals["series"] = params[0] }
            }
            if params.count > 1 {
                if env.locals["datapoint"] == nil { env.locals["datapoint"] = params[1] }
                if env.locals["datapointname"] == nil { env.locals["datapointname"] = params[1] }
                env.it = params[1]
            } else if !params.isEmpty {
                env.it = params[0]
            }
            if params.count > 2 {
                if env.locals["chartvalue"] == nil { env.locals["chartvalue"] = params[2] }
                if env.locals["value"] == nil { env.locals["value"] = params[2] }
            }
        }

        do {
            try Task.checkCancellation()
            for stmt in handler.body {
                try await executeStatementAndPublish(
                    stmt,
                    env: &env,
                    document: &document,
                    context: context,
                    instructionCount: &instructionCount,
                    navigationTarget: &navigationTarget,
                    projectNavigationTarget: &projectNavigationTarget,
                    handler: handler
                )
            }
        } catch ControlSignal.passMessage {
            document.scriptGlobals = env.globals
            // Carry visual effect and navigation target through
            // even when the handler passes the message. A script
            // like `visual effect dissolve / go next / pass mouseUp`
            // sets both before passing — dropping them here makes
            // the transition invisible.
            spriteAreaMutationBatch.flush(to: &document)
            visualEffect = env.locals["_visualEffect"]
            let veDuration = Double(env.locals["_visualEffectDuration"] ?? "")
            return ExecutionResult(status: .passed, modifiedDocument: document,
                                   navigationTarget: navigationTarget,
                                   projectNavigationTarget: projectNavigationTarget,
                                   visualEffect: visualEffect, visualEffectDuration: veDuration)
        } catch ControlSignal.exitHandler(let returnVal) {
            spriteAreaMutationBatch.flush(to: &document)
            document.scriptGlobals = env.globals
            visualEffect = env.locals["_visualEffect"]
            let veDuration = Double(env.locals["_visualEffectDuration"] ?? "")
            return ExecutionResult(status: .completed, returnValue: returnVal,
                                   modifiedDocument: document, navigationTarget: navigationTarget,
                                   projectNavigationTarget: projectNavigationTarget,
                                   visualEffect: visualEffect, visualEffectDuration: veDuration)
        } catch ControlSignal.showAllCards {
            spriteAreaMutationBatch.flush(to: &document)
            document.scriptGlobals = env.globals
            return ExecutionResult(status: .completed, modifiedDocument: document, showAllCards: true)
        } catch let error as ScriptError {
            return ExecutionResult(status: .error, error: error)
        } catch is CancellationError {
            return ExecutionResult(
                status: .cancelled,
                modifiedDocument: document
            )
        } catch {
            let scriptError = ScriptError(message: error.localizedDescription, line: handler.line, handler: handler.name)
            return ExecutionResult(status: .error, error: scriptError)
        }

        // Normal completion: write accumulated globals back so the
        // next dispatch (e.g. the next idle tick) reads the
        // mutated values.
        spriteAreaMutationBatch.flush(to: &document)
        document.scriptGlobals = env.globals
        visualEffect = env.locals["_visualEffect"]
        let veDuration = Double(env.locals["_visualEffectDuration"] ?? "")
        return ExecutionResult(status: .completed, returnValue: env.it,
                               modifiedDocument: document, navigationTarget: navigationTarget,
                               projectNavigationTarget: projectNavigationTarget,
                               visualEffect: visualEffect, visualEffectDuration: veDuration)
    }

    /// Returns `true` when a statement may produce a visible change on-screen
    /// that should be published immediately so the user sees progressive updates.
    ///
    /// The predicate is **conservative**: when in doubt return `true` so
    /// correctness always wins over speed.  The performance win comes from the
    /// pure-compute statements that safely return `false`.
    ///
    /// Statements that return `false` (no visible effect, pure compute):
    /// - `put` into a variable / `it` / message-box (not into a part)
    /// - `get` (sets `it`, no part mutation)
    /// - `add` / `subtract` / `multiply` / `divide` targeting a variable
    /// - `global` declaration
    /// - `exit repeat` / `next repeat` / `pass` / `exit` / `return` (control signals)
    /// - `if` / `repeat` control constructs (their bodies are themselves gated)
    ///
    /// Everything else — `put` into a field/part, `set` of any property,
    /// `show`/`hide`, `go`, `visual`, `create*`, `delete`, sprite mutations,
    /// `animate`, etc. — returns `true`.
    private func statementProducesVisibleEffect(_ stmt: Statement) -> Bool {
        switch stmt {
        case .put(_, _, let target):
            // A put into a variable, `it`, or the message box has no visible
            // effect.  Puts into part refs, scoped refs, property accesses, or
            // chunk-of-part refs DO mutate rendered content.
            switch target {
            case .variable, .it:
                return false
            case .messageBox:
                // Message box is visible in the HyperCard-style message box
                // widget; treat as visible to be conservative.
                return true
            default:
                return true
            }

        case .get:
            // `get` only sets `it` — no part mutation.
            return false

        case .addTo(_, let targetExpr):
            // Arithmetic on variables is pure compute.
            if case .variable = targetExpr { return false }
            if case .it = targetExpr { return false }
            return true

        case .subtractFrom(_, let targetExpr):
            if case .variable = targetExpr { return false }
            if case .it = targetExpr { return false }
            return true

        case .multiplyBy(let targetExpr, _):
            if case .variable = targetExpr { return false }
            if case .it = targetExpr { return false }
            return true

        case .divideBy(let targetExpr, _):
            if case .variable = targetExpr { return false }
            if case .it = targetExpr { return false }
            return true

        case .globalDecl:
            return false

        // Control structures: their bodies are gated individually.
        case .ifThenElse:
            return false
        case .repeatForever:
            return false
        case .repeatCount:
            return false
        case .repeatWhile:
            return false
        case .repeatWith:
            return false
        case .repeatForEach:
            return false

        // Pure control-flow signals: no state change.
        case .exitRepeat:
            return false
        case .nextRepeat:
            return false
        case .passMessage:
            return false
        case .exitHandler:
            return false
        case .returnValue:
            return false

        // All remaining statements may produce visible changes.
        default:
            return true
        }
    }

    /// Execute a statement and conditionally publish the document to the runtime.
    ///
    /// **Two-tier scheme:**
    /// 1. If `lock screen` is active: run the statement, sync `scriptGlobals`,
    ///    but suppress ALL publishing and yields.  A single flush happens at
    ///    `unlock screen` inside `executeStatement(.unlockScreen)`.
    /// 2. If the statement is a visible-effect statement (field/part mutation,
    ///    `set`, `show`/`hide`, `go`, etc.): run then `publishDocument` so the
    ///    UI sees the change immediately (animation / progressive update path).
    ///    `publishDocument` in `StackRuntime` now does only `Task.yield()`, not
    ///    the old 16.67ms sleep.
    /// 3. Pure-compute statements (arithmetic, variable writes, control flow):
    ///    run then `Task.yield()` only — no publish, no sleep — so pure loops
    ///    run at CPU speed while still allowing cooperative cancellation.
    private func executeStatementAndPublish(
        _ stmt: Statement,
        env: inout Environment,
        document: inout HypeDocument,
        context: ExecutionContext,
        instructionCount: inout Int,
        navigationTarget: inout UUID?,
        projectNavigationTarget: inout ProjectNavigationTarget?,
        handler: Handler
    ) async throws {
        try await executeStatement(
            stmt,
            env: &env,
            document: &document,
            context: context,
            instructionCount: &instructionCount,
            navigationTarget: &navigationTarget,
            projectNavigationTarget: &projectNavigationTarget,
            handler: handler
        )
        // Always sync scriptGlobals — the next dispatch (e.g. idle tick)
        // reads mutated globals from the document, and the message box
        // widget reads __messagebox from here.  This is cheap.
        document.scriptGlobals = env.globals

        // Screen-locked mode: suppress all mid-handler publishing.
        // When unlock screen executes, it sets env.screenLocked = false, so
        // this guard does not fire for that statement and publishDocument is
        // called once below (unlock screen is a visible-effect statement → true).
        if env.screenLocked {
            return
        }

        if statementProducesVisibleEffect(stmt) {
            // Visible mutation: publish so the UI reflects the change
            // progressively (field-update animation idiom).
            await context.runtimeProvider?.publishDocument(document)
        } else {
            // Pure compute: just yield to allow cancellation / UI events
            // without incurring any publish overhead.
            try Task.checkCancellation()
            await Task.yield()
        }
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

    private func waitDurationSeconds(from value: Double, unit: WaitDurationUnit) -> TimeInterval {
        switch unit {
        case .ticks:
            return value / 60.0
        case .seconds:
            return value
        }
    }

    private enum HyperCardTimeStyle {
        case short
        case long
        case english
    }

    private func formatHyperCardTime(style: HyperCardTimeStyle) -> String {
        let formatter = DateFormatter()
        switch style {
        case .short:
            formatter.timeStyle = .short
        case .long:
            formatter.timeStyle = .medium
        case .english:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "h:mm:ss a"
        }
        return formatter.string(from: Date())
    }

    private func isActivateListenerProperty(_ property: String) -> Bool {
        switch property.lowercased().replacingOccurrences(of: "_", with: "") {
        case "activatelistener", "speechlistener", "listeneractive":
            return true
        default:
            return false
        }
    }

    private func isUserLevelProperty(_ property: String) -> Bool {
        switch property.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "") {
        case "userlevel":
            return true
        default:
            return false
        }
    }

    private func isItemDelimiterProperty(_ property: String) -> Bool {
        switch property.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "") {
        case "itemdelimiter":
            return true
        default:
            return false
        }
    }

    /// Returns `true` when `property` refers to the message-box container
    /// (`message`, `msg`, `messagebox`, `message box`).
    private func isMessageBoxProperty(_ property: String) -> Bool {
        switch property.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "") {
        case "message", "msg", "messagebox":
            return true
        default:
            return false
        }
    }

    private func resolvedUserLevel(from value: Value, handler: Handler) throws -> HypeUserLevel {
        if let level = HypeUserLevel.parse(value) {
            return level
        }
        throw ScriptError(
            message: "Invalid userLevel '\(value)' (expected 1-5 or browsing, typing, painting, authoring, scripting)",
            line: handler.line,
            handler: handler.name
        )
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

    private func dispatchHandlerCommandIfAvailable(
        name: String,
        args: [Value],
        env: inout Environment,
        document: inout HypeDocument,
        context: ExecutionContext,
        navigationTarget: inout UUID?,
        projectNavigationTarget: inout ProjectNavigationTarget?,
        handler: Handler
    ) async throws -> Bool {
        let dispatcher = MessageDispatcher()
        let activeCardId = env.currentCardId(fallback: context.currentCardId)
        guard dispatcher.hasHandler(
            message: name,
            targetId: context.targetId,
            document: document,
            currentCardId: activeCardId,
            appScript: context.appScript,
            scriptContext: context.scriptContext,
            handlerType: .message
        ) else {
            return false
        }
        guard context.nestedSendDepth < 32 else {
            throw ScriptError(message: "Nested handler command depth exceeded", line: handler.line, handler: handler.name)
        }

        document.scriptGlobals = env.globals
        let result = await dispatcher.dispatchAsync(
            message: name,
            params: args,
            targetId: context.targetId,
            document: document,
            currentCardId: activeCardId,
            dialogProvider: context.dialogProvider,
            drawingProvider: context.drawingProvider,
            systemProvider: context.systemProvider,
            aiProvider: context.aiProvider,
            speechOutputProvider: context.speechOutputProvider,
            appScript: context.appScript,
            mouseX: context.mouseX,
            mouseY: context.mouseY,
            scriptContext: context.scriptContext,
            runtimeProvider: context.runtimeProvider,
            nestedSendDepth: context.nestedSendDepth + 1,
            handlerType: .message
        )
        if let modifiedDocument = result.modifiedDocument {
            document = modifiedDocument
            env.globals = modifiedDocument.scriptGlobals
        }
        if let resultNavigationTarget = result.navigationTarget {
            navigationTarget = resultNavigationTarget
            env.effectiveCurrentCardId = resultNavigationTarget
        }
        if let resultProjectNavigationTarget = result.projectNavigationTarget {
            projectNavigationTarget = resultProjectNavigationTarget
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
                message: "Handler command failed",
                line: handler.line,
                handler: handler.name
            )
        }
        if result.status == .cancelled {
            throw CancellationError()
        }
        // Callee return value surfaces via `the result`; `it` is handler-local
        // per classic HyperCard semantics — callee must not clobber caller's `it`.
        // TODO(it-hygiene): distinguish explicit vs implicit return if a future test needs it.
        env.result = result.returnValue ?? ""
        document.scriptGlobals = env.globals
        return true
    }

    private func evaluateHandlerFunctionIfAvailable(
        name: String,
        args: [Value],
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext,
        handler: Handler
    ) async throws -> Value? {
        let dispatcher = MessageDispatcher()
        let functionCardId = env.currentCardId(fallback: context.currentCardId)
        guard dispatcher.hasHandler(
            message: name,
            targetId: functionCardId,
            document: document,
            currentCardId: functionCardId,
            appScript: context.appScript,
            scriptContext: context.scriptContext,
            handlerType: .function
        ) else {
            return nil
        }
        guard context.nestedSendDepth < 32 else {
            throw ScriptError(message: "Nested function call depth exceeded", line: handler.line, handler: handler.name)
        }

        var callDocument = document
        callDocument.scriptGlobals = env.globals
        let result = await dispatcher.dispatchAsync(
            message: name,
            params: args,
            targetId: functionCardId,
            document: callDocument,
            currentCardId: functionCardId,
            dialogProvider: context.dialogProvider,
            drawingProvider: context.drawingProvider,
            systemProvider: context.systemProvider,
            aiProvider: context.aiProvider,
            speechOutputProvider: context.speechOutputProvider,
            appScript: context.appScript,
            mouseX: context.mouseX,
            mouseY: context.mouseY,
            scriptContext: context.scriptContext,
            runtimeProvider: context.runtimeProvider,
            nestedSendDepth: context.nestedSendDepth + 1,
            handlerType: .function
        )
        if let modifiedDocument = result.modifiedDocument {
            env.globals = modifiedDocument.scriptGlobals
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
                message: "Function call failed",
                line: handler.line,
                handler: handler.name
            )
        }
        if result.status == .cancelled {
            throw CancellationError()
        }
        return result.returnValue
    }

    // MARK: - Statement execution

    private func executeStatement(
        _ stmt: Statement,
        env: inout Environment,
        document: inout HypeDocument,
        context: ExecutionContext,
        instructionCount: inout Int,
        navigationTarget: inout UUID?,
        projectNavigationTarget: inout ProjectNavigationTarget?,
        handler: Handler
    ) async throws {
        try Task.checkCancellation()
        instructionCount += 1
        context.profiler?.recordStatement(statementKind(stmt))
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
            case .messageBox:
                let existing = env.globals[Self.messageBoxKey] ?? ""
                switch prep {
                case .into:   env.globals[Self.messageBoxKey] = value
                case .after:  env.globals[Self.messageBoxKey] = existing + value
                case .before: env.globals[Self.messageBoxKey] = value + existing
                }
            case .objectRef(let ref):
                // Put into a field or button by name/number
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let partIndex = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                    switch prep {
                    case .into:
                        document.parts[partIndex].textContent = value
                    case .after:
                        document.parts[partIndex].textContent += value
                    case .before:
                        document.parts[partIndex].textContent = value + document.parts[partIndex].textContent
                    }
                }

            case .scopedObjectRef(let object, let owner):
                if let partIndex = try await findScopedPartIndex(
                    object: object,
                    owner: owner,
                    env: &env,
                    document: document,
                    context: context
                ) {
                    switch prep {
                    case .into:
                        document.parts[partIndex].textContent = value
                    case .after:
                        document.parts[partIndex].textContent += value
                    case .before:
                        document.parts[partIndex].textContent = value + document.parts[partIndex].textContent
                    }
                }

            case .propertyAccess(let property, let targetExpr):
                context.profiler?.recordPropertyWrite(property)
                // `put X into the <property> of <part-ref>`
                //
                // Handles `put "asset-name" into the model of scene3d "Viewer"` by
                // routing through the same smart resolver as `set the model of scene3d
                // "Viewer" to "asset-name"`. Only the `.into` preposition is supported
                // for property container writes; `.after` / `.before` fall through to
                // `it` since there is no sensible concatenation semantic for a model ref.
                if prep == .into, case .objectRef(let ref) = targetExpr {
                    let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                    if ref.objectType == "window" {
                        applyHyperCardWindowPropertySet(
                            windowName: ident,
                            property: property,
                            value: value,
                            env: &env,
                            document: &document,
                            currentCardId: context.currentCardId
                        )
                    } else if let partIndex = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                        applyPartPropertySet(
                            partIndex: partIndex,
                            property: property,
                            value: value,
                            env: &env,
                            document: &document,
                            context: context
                        )
                    }
                }

            case .chunk(let chunkType, let chunkRange, let chunkSource):
                try await performChunkPut(
                    chunkType: chunkType,
                    range: chunkRange,
                    source: chunkSource,
                    preposition: prep,
                    value: value,
                    env: &env,
                    document: &document,
                    context: context,
                    handler: handler
                )

            default:
                throw ScriptError(message: "Can't put into that container", line: handler.line, handler: handler.name)
            }

        case .get(let expr):
            env.it = try await evaluate(expr, env: &env, document: document, context: context)

        case .set(let property, let target, let toExpr):
            context.profiler?.recordPropertyWrite(property)
            let value = try await evaluate(toExpr, env: &env, document: document, context: context)
            if target == nil, isUserLevelProperty(property) {
                let level = try resolvedUserLevel(from: value, handler: handler)
                document.stack.userLevel = level.rawValue
                env.it = String(level.rawValue)
                break
            }
            if target == nil, isActivateListenerProperty(property) {
                try await setSpeechListenerActive(value, context: context, handler: handler)
                env.it = isTruthy(value) ? "true" : "false"
                break
            }
            if target == nil, isItemDelimiterProperty(property) {
                // Single-character item delimiter per the HyperTalk Reference.
                // Empty value resets to default comma.
                env.itemDelimiter = value.isEmpty ? "," : String(value.unicodeScalars.first.map(Character.init) ?? ",")
                break
            }
            if target == nil, isMessageBoxProperty(property) {
                // `set the message to X` — writes the message-box container.
                env.globals[Self.messageBoxKey] = value
                env.it = value
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
                    } else if !handledAsNode && ref.objectType == "window" {
                    let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                    applyHyperCardWindowPropertySet(
                        windowName: ident,
                        property: property,
                        value: value,
                        env: &env,
                        document: &document,
                        currentCardId: context.currentCardId
                    )
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
                    case "webassetsallowed", "web_assets_allowed":
                        document.stack.webAssetsAllowed = isTruthy(value)
                    case "aicontextcloudsharingallowed", "ai_context_cloud_sharing_allowed", "contextcloudsharingallowed":
                        document.stack.aiContextCloudSharingAllowed = isTruthy(value)
                    case "runtimemode", "runtime_mode", "runtimemodeenabled", "runtime_mode_enabled":
                        document.stack.runtimeModeEnabled = isTruthy(value)
                    case "userlevel", "user_level":
                        let level = try resolvedUserLevel(from: value, handler: handler)
                        document.stack.userLevel = level.rawValue
                    case "runtimeaiproviderpolicy", "runtime_ai_provider_policy", "aiproviderpolicy":
                        if let policy = RuntimeAIProviderPolicy.parse(value) {
                            document.stack.runtimeAISettings.providerPolicy = policy
                        }
                    case "runtimeaitoolsallowed", "runtime_ai_tools_allowed":
                        document.stack.runtimeAISettings.allowRuntimeSideEffectTools = isTruthy(value)
                    case "runtimeaiallowedtools", "runtime_ai_allowed_tools":
                        document.stack.runtimeAISettings.allowedToolNames = value
                            .split(separator: ",")
                            .map { String($0) }
                        document.stack.runtimeAISettings.normalize()
                    case "runtimeaipersisttranscript", "runtime_ai_persist_transcript":
                        document.stack.runtimeAISettings.persistTranscript = isTruthy(value)
                    case "targetplatforms", "target_platforms":
                        let platforms = value
                            .split(separator: ",")
                            .compactMap { HypeTargetPlatform(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        if !platforms.isEmpty {
                            document.stack.deploymentTargets = StackDeploymentTargets(
                                selectedPlatforms: platforms,
                                primaryPlatform: document.stack.deploymentTargets.primaryPlatform,
                                selectionPromptAcknowledged: true,
                                supportedOrientations: document.stack.deploymentTargets.supportedOrientations,
                                layoutPolicy: document.stack.deploymentTargets.layoutPolicy
                            )
                        }
                    case "primarytargetplatform", "primary_target_platform":
                        if let platform = HypeTargetPlatform(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                           document.stack.deploymentTargets.selectedPlatforms.contains(platform) {
                            document.stack.deploymentTargets.primaryPlatform = platform
                        }
                    case "layoutpolicy", "targetlayoutpolicy", "target_layout_policy":
                        if let policy = TargetLayoutPolicy.parse(value) {
                            document.stack.deploymentTargets.layoutPolicy = policy
                        }
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
                    if let partIndex = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
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
            let projectFallbackValue: Value
            if destValue.isEmpty,
               case .objectRef(let ref) = dest,
               ref.objectType == "card" {
                projectFallbackValue = try await evaluateObjectRefIdentifier(ref.identifier, env: &env, document: document, context: context)
            } else {
                projectFallbackValue = destValue
            }
            let sourceCardId = navigationTarget ?? context.currentCardId
            // Try to resolve destination to a card UUID.
            if let uuid = UUID(uuidString: destValue) {
                navigationTarget = uuid
                env.effectiveCurrentCardId = uuid
                HypeLogger.shared.log(
                    .info,
                    "go direct card id from \(cardLogLabel(sourceCardId, document: document)) resolved \(cardLogLabel(uuid, document: document))",
                    source: "HypeTalk Runtime",
                    actionTitle: cardActionTitle(uuid, document: document),
                    actionURL: cardReferenceURL(stackId: document.stack.id, cardId: uuid)
                )
                await context.runtimeProvider?.navigateToCard(uuid)
            } else {
                // Try to find by name or navigation keyword.
                let resolved = resolveNavigation(destValue, document: document, currentCardId: sourceCardId)
                navigationTarget = resolved
                if let resolved {
                    env.effectiveCurrentCardId = resolved
                }
                if resolved == nil,
                   let target = implicitProjectNavigationTarget(
                    cardValue: projectFallbackValue,
                    preferredStackName: projectNavigationTarget?.stackName ?? env.getVariable("ALL_CurrStack"),
                    document: document
                   ) {
                    projectNavigationTarget = target
                    env.it = target.cardName
                    env.result = env.it
                }
                let targetLabel = resolved.map { cardLogLabel($0, document: document) } ?? "no card"
                HypeLogger.shared.log(
                    .info,
                    "go \(destValue) from \(cardLogLabel(sourceCardId, document: document)) resolved \(targetLabel)",
                    source: "HypeTalk Runtime",
                    actionTitle: resolved.map { cardActionTitle($0, document: document) },
                    actionURL: resolved.flatMap { cardReferenceURL(stackId: document.stack.id, cardId: $0) }
                )
                if let resolved {
                    await context.runtimeProvider?.navigateToCard(resolved)
                }
            }

        case .goInStack(let cardExpr, let stackExpr):
            let cardValue = try await evaluateNavigationExpression(cardExpr, env: &env, document: document, context: context)
            let stackValue = try await evaluateNavigationExpression(stackExpr, env: &env, document: document, context: context)
            projectNavigationTarget = try resolveProjectNavigationTarget(
                cardValue: cardValue,
                stackValue: stackValue,
                document: document,
                handler: handler
            )
            env.it = projectNavigationTarget?.cardName ?? ""
            env.result = env.it

        case .ifThenElse(let cond, let thenBlock, let elseBlock):
            let condValue = try await evaluate(cond, env: &env, document: document, context: context)
            if isTruthy(condValue) {
                for s in thenBlock {
                    try await executeStatementAndPublish(s, env: &env, document: &document, context: context,
                                                         instructionCount: &instructionCount,
                                                         navigationTarget: &navigationTarget,
                                                         projectNavigationTarget: &projectNavigationTarget,
                                                         handler: handler)
                }
            } else if let elseStmts = elseBlock {
                for s in elseStmts {
                    try await executeStatementAndPublish(s, env: &env, document: &document, context: context,
                                                         instructionCount: &instructionCount,
                                                         navigationTarget: &navigationTarget,
                                                         projectNavigationTarget: &projectNavigationTarget,
                                                         handler: handler)
                }
            }

        case .repeatForever(let body):
            while true {
                instructionCount += 1
                if instructionCount > context.instructionLimit {
                    throw ScriptError(message: "Instruction limit exceeded", line: handler.line, handler: handler.name)
                }
                context.profiler?.recordLoopIteration("repeatForever")
                do {
                    for s in body {
                        try await executeStatementAndPublish(s, env: &env, document: &document, context: context,
                                                             instructionCount: &instructionCount,
                                                             navigationTarget: &navigationTarget,
                                                             projectNavigationTarget: &projectNavigationTarget,
                                                             handler: handler)
                    }
                } catch ControlSignal.exitRepeat {
                    break
                } catch ControlSignal.nextRepeat {
                    continue
                }
            }

        case .repeatCount(let countExpr, let body):
            let countStr = try await evaluate(countExpr, env: &env, document: document, context: context)
            let count = clampedInt(toNumber(countStr))
            for _ in 0..<max(0, count) {
                context.profiler?.recordLoopIteration("repeatCount")
                do {
                    for s in body {
                        try await executeStatementAndPublish(s, env: &env, document: &document, context: context,
                                                             instructionCount: &instructionCount,
                                                             navigationTarget: &navigationTarget,
                                                             projectNavigationTarget: &projectNavigationTarget,
                                                             handler: handler)
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
                context.profiler?.recordLoopIteration("repeatWhile")
                do {
                    for s in body {
                        try await executeStatementAndPublish(s, env: &env, document: &document, context: context,
                                                             instructionCount: &instructionCount,
                                                             navigationTarget: &navigationTarget,
                                                             projectNavigationTarget: &projectNavigationTarget,
                                                             handler: handler)
                    }
                } catch ControlSignal.exitRepeat {
                    break
                } catch ControlSignal.nextRepeat {
                    continue
                }
            }

        case .repeatWith(let varName, let fromExpr, let toExpr, let direction, let body):
            let fromVal = Int(toNumber(try await evaluate(fromExpr, env: &env, document: document, context: context)))
            let toVal = Int(toNumber(try await evaluate(toExpr, env: &env, document: document, context: context)))
            let varKey = varName.lowercased()
            // Classic HyperCard:
            //   `repeat with i = 1 to N`   → step +1; start > end yields zero iterations
            //   `repeat with i = N down to 1` → step -1; start < end yields zero iterations
            let step: Int
            let shouldRun: Bool
            switch direction {
            case .up:
                step = 1
                shouldRun = fromVal <= toVal
            case .down:
                step = -1
                shouldRun = fromVal >= toVal
            }
            if shouldRun {
                var i = fromVal
                let condition: () -> Bool = direction == .up ? { i <= toVal } : { i >= toVal }
                while condition() {
                    context.profiler?.recordLoopIteration("repeatWith")
                    env.setVariableKey(varKey, String(i))
                    do {
                        for s in body {
                            try await executeStatementAndPublish(s, env: &env, document: &document, context: context,
                                                                 instructionCount: &instructionCount,
                                                                 navigationTarget: &navigationTarget,
                                                                 projectNavigationTarget: &projectNavigationTarget,
                                                                 handler: handler)
                        }
                    } catch ControlSignal.exitRepeat {
                        break
                    } catch ControlSignal.nextRepeat {
                        // fall through to increment
                    }
                    i += step
                }
            }

        case .repeatForEach(let chunkType, let varName, let listExpr, let body):
            let listVal = try await evaluate(listExpr, env: &env, document: document, context: context)
            let varKey = varName.lowercased()
            // Split the list using the current itemDelimiter (for .item chunks) or fixed delimiters.
            let elements: [String]
            switch chunkType {
            case .word:
                elements = listVal.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            case .char, .character:
                elements = listVal.map(String.init)
            case .item:
                let delimChar = env.itemDelimiter.first ?? ","
                elements = listVal.isEmpty ? [] :
                    listVal.split(separator: delimChar, omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
            case .line:
                elements = splitLines(listVal)
            }
            for element in elements {
                context.profiler?.recordLoopIteration("repeatForEach")
                env.setVariableKey(varKey, element)
                do {
                    for s in body {
                        try await executeStatementAndPublish(s, env: &env, document: &document, context: context,
                                                             instructionCount: &instructionCount,
                                                             navigationTarget: &navigationTarget,
                                                             projectNavigationTarget: &projectNavigationTarget,
                                                             handler: handler)
                    }
                } catch ControlSignal.exitRepeat {
                    break
                } catch ControlSignal.nextRepeat {
                    continue
                }
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

        case .ask(let prompt, let defaultResponse):
            let promptText = try await evaluate(prompt, env: &env, document: document, context: context)
            let defaultValue = try await evaluateOptional(defaultResponse, env: &env, document: document, context: context)
            let userInput: String
            if let defaultValue {
                userInput = await context.dialogProvider.showAskAsync(prompt: promptText, defaultValue: defaultValue)
            } else {
                userInput = await context.dialogProvider.showAskAsync(prompt: promptText)
            }
            env.it = userInput

        case .askAI(let prompt, let modelExpr, let callbackExpr):
            let promptText = try await evaluate(prompt, env: &env, document: document, context: context)
            let modelName = try await evaluateOptional(modelExpr, env: &env, document: document, context: context)
            if let callbackExpr, let runtime = context.runtimeProvider {
                let callbackName = try await evaluate(callbackExpr, env: &env, document: document, context: context)
                context.profiler?.recordCallbackRequest("askAI")
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
                env.it = try await generateAIResponse(prompt: promptText, model: modelName, document: document, context: context)
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
                context.profiler?.recordCallbackRequest("askMeshy")
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

        case .remeshAsset(let sourceNameExpr, let polycountExpr, let callbackExpr):
            // Phase 4 — `remesh asset "<name>" to <polycount> [with message <msg>]`
            //
            // Sync form (no callback): blocks until remesh completes; sets `it` + `result` to
            // the new asset's name. Async form: fires `startRemeshRequest` and sets `it` to the
            // request UUID. Gate refusal degrades gracefully — sets `it = ""`.
            let sourceNameText = try await evaluate(sourceNameExpr, env: &env, document: document, context: context)
            let polycountText = try await evaluate(polycountExpr, env: &env, document: document, context: context)
            let targetPolycount = Int(polycountText.trimmingCharacters(in: .whitespaces)) ?? 30_000

            if let callbackExpr, let runtime = context.runtimeProvider {
                let callbackName = try await evaluate(callbackExpr, env: &env, document: document, context: context)
                context.profiler?.recordCallbackRequest("remeshAsset")
                let requestID = try await runtime.startRemeshRequest(
                    sourceAssetName: sourceNameText,
                    targetPolycount: targetPolycount,
                    callbackMessage: callbackName,
                    owner: RuntimeOwnerContext(
                        targetId: context.targetId,
                        currentCardId: context.currentCardId,
                        scriptContext: context.scriptContext
                    )
                )
                env.it = requestID.uuidString
            } else if let provider = context.meshyProvider {
                let assetName = try await provider.remeshSync(
                    sourceAssetName: sourceNameText,
                    targetPolycount: targetPolycount,
                    document: document
                )
                env.it = assetName
                env.result = assetName
            } else {
                env.it = ""
                env.result = ""
            }

        case .retextureAsset(let sourceNameExpr, let stylePromptExpr, let callbackExpr):
            // Phase 4 — `retexture asset "<name>" with prompt "<text>" [with message <msg>]`
            //
            // Same sync/async contract as `remeshAsset`.
            let sourceNameText = try await evaluate(sourceNameExpr, env: &env, document: document, context: context)
            let stylePromptText = try await evaluate(stylePromptExpr, env: &env, document: document, context: context)

            if let callbackExpr, let runtime = context.runtimeProvider {
                let callbackName = try await evaluate(callbackExpr, env: &env, document: document, context: context)
                context.profiler?.recordCallbackRequest("retextureAsset")
                let requestID = try await runtime.startRetextureRequest(
                    sourceAssetName: sourceNameText,
                    stylePrompt: stylePromptText,
                    callbackMessage: callbackName,
                    owner: RuntimeOwnerContext(
                        targetId: context.targetId,
                        currentCardId: context.currentCardId,
                        scriptContext: context.scriptContext
                    )
                )
                env.it = requestID.uuidString
            } else if let provider = context.meshyProvider {
                let assetName = try await provider.retextureSync(
                    sourceAssetName: sourceNameText,
                    stylePrompt: stylePromptText,
                    document: document
                )
                env.it = assetName
                env.result = assetName
            } else {
                env.it = ""
                env.result = ""
            }

        case .answer(let prompt, _):
            let promptText = try await evaluate(prompt, env: &env, document: document, context: context)
            let response = await context.dialogProvider.showAnswerAsync(prompt: promptText)
            env.it = response

        case .say(let prompt):
            let promptText = try await evaluate(prompt, env: &env, document: document, context: context)
            await context.speechOutputProvider.speakScriptText(promptText, source: "HypeTalk say")
            // `say` must not set `it` per classic HyperCard semantics.

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
            if case .variable(let name) = expr,
               try await dispatchHandlerCommandIfAvailable(
                   name: name,
                   args: [],
                   env: &env,
                   document: &document,
                   context: context,
                   navigationTarget: &navigationTarget,
                   projectNavigationTarget: &projectNavigationTarget,
                   handler: handler
               ) {
                break
            }
            _ = try await evaluate(expr, env: &env, document: document, context: context)

        case .doBlock(let expr):
            // SECURITY: depth gate FIRST (Finding 1/2). Independent counter;
            // separate from nestedSendDepth so send-depth budget cannot be
            // exhausted via do-nesting, and vice-versa.
            guard context.nestedEvalDepth < Self.maxNestedEvalDepth else {
                throw ScriptError(message: "do-eval nesting too deep", line: handler.line, handler: handler.name)
            }
            let scriptText = try await evaluate(expr, env: &env, document: document, context: context)
            guard scriptText.utf8.count <= Self.maxDoEvalBytes else {
                throw ScriptError(message: "do: script too large", line: handler.line, handler: handler.name)
            }
            var lexer = Lexer(source: scriptText)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            let stmts: [Statement]
            do {
                stmts = try parser.parseStatements()
            } catch let e as ParseError {
                throw ScriptError(message: "do: \(e.errorDescription ?? "parse error")", line: handler.line, handler: handler.name)
            }
            var childContext = context
            childContext.nestedEvalDepth = context.nestedEvalDepth + 1
            for s in stmts {
                try await executeStatementAndPublish(
                    s,
                    env: &env,
                    document: &document,
                    context: childContext,
                    instructionCount: &instructionCount,
                    navigationTarget: &navigationTarget,
                    projectNavigationTarget: &projectNavigationTarget,
                    handler: handler
                )
            }

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
            env.invalidatePartLookupCache()

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
            env.invalidatePartLookupCache()

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
                if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
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
                // Consistent sentinel "0" for divide-by-zero across all four division paths
                // (/, mod, div, divide command). Classic HyperCard raises an error; the
                // non-throwing evalBinary path uses "0" and we mirror that here to avoid
                // the SIGBUS-under-deep-recursion issue documented at evaluateChunk:5449-5464.
                env.setVariable(name, divisor != 0 ? formatNumber(toNumber(existing) / divisor) : "0")
            }

        case .deleteObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                    document.parts.remove(at: idx)
                    env.invalidatePartLookupCache()
                }
            }

        case .findText(let mode, let queryExpr, let inFieldExpr):
            // HyperCard `find [mode] "text" [in field "X"]` — case-insensitive search.
            // Sets the runtime's found state and navigates to the matching card.
            let searchTerm = try await evaluate(queryExpr, env: &env, document: document, context: context)
            env.it = searchTerm
            let inFieldName: String?
            if let expr = inFieldExpr {
                inFieldName = try await evaluate(expr, env: &env, document: document, context: context)
            } else {
                inFieldName = nil
            }
            if let found = findTextInDocument(
                searchTerm,
                mode: mode,
                document: document,
                startingCardId: context.currentCardId,
                inFieldName: inFieldName
            ) {
                await context.runtimeProvider?.setFoundState(found)
                navigationTarget = found.cardId
                await context.runtimeProvider?.navigateToCard(found.cardId)
            } else {
                await context.runtimeProvider?.setFoundState(nil)
            }

        case .selectObject(let expr):
            // HyperCard `select <expr>` — record selection state so that
            // `the selectedText` / `selectedChunk` / `selectedField` / `selectedLine`
            // return the right values.  Model state is fully implemented;
            // UI highlight (field-editor range selection) is a follow-up (see report).
            if let selected = await resolveSelectExpression(
                expr,
                env: &env,
                document: document,
                context: context
            ) {
                await context.runtimeProvider?.setSelectedState(selected)
            }

        case .sortCards(let byExpr):
            // Evaluate the key expression once per card, in that card's context,
            // then stably sort ascending. Numeric order is used when every key
            // parses as a finite number; otherwise case-insensitive text order.
            var cardKeys: [(cardId: UUID, key: String)] = []
            for card in document.sortedCards {
                var cardContext = context
                cardContext.currentCardId = card.id
                let key = try await evaluateSortKey(byExpr, env: &env, document: document, context: cardContext)
                cardKeys.append((cardId: card.id, key: key))
            }
            let allNumeric = cardKeys.allSatisfy {
                let d = Double($0.key)
                return d != nil && d!.isFinite
            }
            let sortedIds: [UUID]
            if allNumeric {
                sortedIds = cardKeys.sorted { Double($0.key)! < Double($1.key)! }.map(\.cardId)
            } else {
                sortedIds = cardKeys.sorted {
                    $0.key.compare($1.key, options: .caseInsensitive) == .orderedAscending
                }.map(\.cardId)
            }
            // Rewrite sortKeys as evenly-spaced "a%06d" strings matching the
            // scheme used by HypeDocument.addCard.
            for (index, cardId) in sortedIds.enumerated() {
                if let i = document.cards.firstIndex(where: { $0.id == cardId }) {
                    document.cards[i].sortKey = String(format: "a%06d", index)
                }
            }

        case .sortContainer(let chunkType, let containerExpr, let direction, let style, let byExpr):
            // `sort [lines|items] of <container> [ascending|descending] [text|numeric] [by <expr>]`
            // Split the container, evaluate sort keys, sort, write back.
            try await executeSortContainer(
                chunkType: chunkType,
                containerExpr: containerExpr,
                direction: direction,
                style: style,
                byExpr: byExpr,
                env: &env,
                document: &document,
                context: context,
                handler: handler,
                instructionCount: &instructionCount,
                navigationTarget: &navigationTarget,
                projectNavigationTarget: &projectNavigationTarget
            )

        case .hideObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if ref.objectType == "window" {
                    setHyperCardWindowVisibility(
                        windowName: ident,
                        visible: false,
                        env: &env,
                        document: &document,
                        currentCardId: context.currentCardId
                    )
                } else if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                    document.parts[idx].visible = false
                }
            }

        case .showObject(let expr):
            if case .objectRef(let ref) = expr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if ref.objectType == "window" {
                    setHyperCardWindowVisibility(
                        windowName: ident,
                        visible: true,
                        env: &env,
                        document: &document,
                        currentCardId: context.currentCardId
                    )
                } else if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                    document.parts[idx].visible = true
                }
            }

        case .lockScreen:
            env.screenLocked = true
            await context.hostProvider.lockScreen()

        case .unlockScreen:
            env.screenLocked = false
            await context.hostProvider.unlockScreen()
            // The publish for unlock screen is handled by executeStatementAndPublish:
            // since screenLocked is now false and unlockScreen is a visible-effect
            // statement (default branch), it will publish exactly once after this
            // statement returns.  No explicit publish here avoids a double-publish.

        case .openStack(let pathExpr):
            let path = try await evaluate(pathExpr, env: &env, document: document, context: context)
            await context.hostProvider.openStack(path: path)

        case .externalCommand(let name, let argumentExprs):
            var args: [Value] = []
            for expr in argumentExprs {
                args.append(try await evaluateExternalArgumentExpression(expr, env: &env, document: document, context: context))
            }

            let normalizedName = name.lowercased()
            if normalizedName == "domenu" {
                let item = args.first ?? ""
                _ = await context.hostProvider.doMenu(item: item)
                break
            }

            if try await dispatchHandlerCommandIfAvailable(
                name: name,
                args: args,
                env: &env,
                document: &document,
                context: context,
                navigationTarget: &navigationTarget,
                projectNavigationTarget: &projectNavigationTarget,
                handler: handler
            ) {
                break
            }
            if handleClassicBuiltInCommand(
                normalizedName: normalizedName,
                args: args,
                document: document,
                context: context,
                navigationTarget: &navigationTarget,
                env: &env
            ) {
                break
            }
            document.scriptGlobals = env.globals
            let activeCardId = env.currentCardId(fallback: context.currentCardId)
            let result = await context.externalRegistry.invoke(
                HyperCardExternalCall(name: name, kind: .xcmd, arguments: args),
                context: HyperCardExternalCallContext(
                    targetId: context.targetId,
                    currentCardId: activeCardId,
                    document: document
                )
            )
            if let modified = result.modifiedDocument {
                document = modified
            }
            for (key, value) in result.runtimeGlobals {
                env.globals[key] = value
                env.globals[key.lowercased()] = value
            }
            if let visualEffect = result.visualEffect {
                env.locals["_visualEffect"] = visualEffect
            }
            if let visualEffectDuration = result.visualEffectDuration {
                env.locals["_visualEffectDuration"] = String(visualEffectDuration)
            }
            if let resultNavigationTarget = result.navigationTarget {
                navigationTarget = resultNavigationTarget
                env.effectiveCurrentCardId = resultNavigationTarget
            }
            if let resultProjectNavigationTarget = result.projectNavigationTarget {
                projectNavigationTarget = resultProjectNavigationTarget
            }
            document.scriptGlobals = env.globals
            env.it = result.value
            env.result = result.result
            if result.passMessage {
                throw ControlSignal.passMessage(handler.name)
            }

        case .send(let messageExpr, let targetExpr):
            guard context.nestedSendDepth < 32 else {
                throw ScriptError(message: "Nested send depth exceeded", line: handler.line, handler: handler.name)
            }
            let message = try await evaluateSendMessageExpression(messageExpr, env: &env, document: document, context: context)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                throw ScriptError(message: "Cannot send an empty message", line: handler.line, handler: handler.name)
            }
            if let targetExpr,
               case .objectRef(let ref) = targetExpr,
               ref.objectType == "window" {
                let windowName = try await evaluateObjectRefIdentifier(
                    ref.identifier,
                    env: &env,
                    document: document,
                    context: context
                )
                applyHyperCardWindowMessage(
                    message: message,
                    windowName: windowName,
                    env: &env,
                    document: &document,
                    currentCardId: context.currentCardId
                )
                document.scriptGlobals = env.globals
                break
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
            if env.deferNextSelfSend,
               targetID == context.targetId,
               let runtime = context.runtimeProvider {
                env.deferNextSelfSend = false
                await runtime.enqueueMessage(
                    message,
                    params: [],
                    targetId: targetID,
                    currentCardId: context.currentCardId,
                    mouseX: context.mouseX,
                    mouseY: context.mouseY,
                    scriptContext: context.scriptContext
                )
                break
            }
            env.deferNextSelfSend = false

            let result = await MessageDispatcher().dispatchAsync(
                message: message,
                params: [],
                targetId: targetID,
                document: document,
                currentCardId: context.currentCardId,
                dialogProvider: context.dialogProvider,
                drawingProvider: context.drawingProvider,
                systemProvider: context.systemProvider,
                hostProvider: context.hostProvider,
                aiProvider: context.aiProvider,
                speechOutputProvider: context.speechOutputProvider,
                appScript: context.appScript,
                mouseX: context.mouseX,
                mouseY: context.mouseY,
                scriptContext: context.scriptContext,
                runtimeProvider: context.runtimeProvider,
                nestedSendDepth: context.nestedSendDepth + 1,
                fileProvider: context.fileProvider
            )
            if let modifiedDocument = result.modifiedDocument {
                document = modifiedDocument
                env.globals = modifiedDocument.scriptGlobals
            }
            if let resultNavigationTarget = result.navigationTarget {
                navigationTarget = resultNavigationTarget
            }
            if let resultProjectNavigationTarget = result.projectNavigationTarget {
                projectNavigationTarget = resultProjectNavigationTarget
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
            if result.status == .cancelled {
                throw CancellationError()
            }

        case .playSound(let soundExpr, let notesExpr, let tempoExpr):
            let soundName = try await evaluate(soundExpr, env: &env, document: document, context: context)
            if let notesExprVal = notesExpr {
                let noteString = try await evaluate(notesExprVal, env: &env, document: document, context: context)
                let tempo: Int
                if let tExpr = tempoExpr {
                    tempo = MusicTempo.clamp(toNumber(try await evaluate(tExpr, env: &env, document: document, context: context)))
                } else {
                    tempo = MusicTempo.defaultBPM
                }
                await context.systemProvider.playNotes(instrument: soundName, noteString: noteString, tempo: tempo, document: document)
            } else {
                await context.systemProvider.playSound(name: soundName, document: document)
            }

        case .playStop:
            await context.systemProvider.stopSound()

        case .createMusicPattern(let nameExpr, let instrumentExpr, let notesExpr, let tempoExpr, let loopExpr):
            let rawName = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Music Pattern" : rawName
            let instrument: String
            if let instrumentExpr {
                instrument = try await evaluate(instrumentExpr, env: &env, document: document, context: context)
            } else {
                instrument = "Acoustic Grand Piano"
            }
            let notes: String
            if let notesExpr {
                notes = try await evaluate(notesExpr, env: &env, document: document, context: context)
            } else {
                notes = ""
            }
            let tempo: Int
            if let tempoExpr {
                tempo = MusicTempo.clamp(toNumber(try await evaluate(tempoExpr, env: &env, document: document, context: context)))
            } else {
                tempo = MusicTempo.defaultBPM
            }
            let shouldLoop: Bool
            if let loopExpr {
                shouldLoop = isTruthy(try await evaluate(loopExpr, env: &env, document: document, context: context))
            } else {
                shouldLoop = false
            }
            let resolvedInstrument = MusicInstrumentCatalog.resolve(instrument).name
            let pattern = MusicPatternSpec.singleTrack(
                name: name,
                instrument: resolvedInstrument,
                tempo: tempo,
                notes: notes,
                loop: shouldLoop
            )
            document.musicLibrary.upsertPattern(pattern)
            env.it = name
            env.result = name

        case .playMusicPattern(let nameExpr, let loop):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            guard let pattern = document.musicLibrary.pattern(named: name) else {
                throw ScriptError(message: "Music pattern '\(name)' not found", line: handler.line, handler: handler.name)
            }
            await context.systemProvider.playMusicPattern(pattern, loop: loop || pattern.loop, document: document)
            env.it = pattern.name
            env.result = pattern.name

        case .stopMusic:
            await context.systemProvider.stopMusic()
            env.it = "stopped"
            env.result = "stopped"

        case .pauseMusic:
            await context.systemProvider.pauseMusic()
            env.it = "paused"
            env.result = "paused"

        case .resumeMusic:
            await context.systemProvider.resumeMusic()
            env.it = "playing"
            env.result = "playing"

        case .authorizeAppleMusic:
            guard document.stack.appleMusicAllowed else {
                throw ScriptError(message: "Apple Music is disabled for this stack", line: handler.line, handler: handler.name)
            }
            let status = await context.systemProvider.authorizeAppleMusic()
            env.it = status.rawValue
            env.result = status.rawValue

        case .searchAppleMusic(let termExpr, let scopeRaw, let itemTypeRaw, let limitExpr):
            guard document.stack.appleMusicAllowed else {
                throw ScriptError(message: "Apple Music is disabled for this stack", line: handler.line, handler: handler.name)
            }
            let term = try await evaluate(termExpr, env: &env, document: document, context: context)
            let limit = limitExpr == nil
                ? 10
                : max(1, clampedInt(toNumber(try await evaluate(limitExpr!, env: &env, document: document, context: context))))
            let scope = AppleMusicSearchScope(rawValue: scopeRaw.lowercased()) ?? .catalog
            let kinds = itemTypeRaw.flatMap { AppleMusicItemKind.parse($0) }.map { [$0] }
                ?? [.song, .album, .artist, .playlist, .station]
            let request = AppleMusicSearchRequest(term: term, scope: scope, itemKinds: kinds, limit: limit)
            do {
                let refs = try await context.systemProvider.searchAppleMusic(request)
                for ref in refs {
                    document.musicLibrary.upsertAppleMusicItem(ref)
                }
                let encoded = encodeAppleMusicRefs(refs)
                env.it = encoded
                env.result = encoded
            } catch {
                throw ScriptError(message: "Apple Music search failed: \(error.localizedDescription)", line: handler.line, handler: handler.name)
            }

        case .playAppleMusic(let sourceRaw, let itemTypeRaw, let idExpr):
            guard document.stack.appleMusicAllowed else {
                throw ScriptError(message: "Apple Music is disabled for this stack", line: handler.line, handler: handler.name)
            }
            let id = try await evaluate(idExpr, env: &env, document: document, context: context)
            let source = MusicSourceKind.parse(sourceRaw)
            let kind = AppleMusicItemKind.parse(itemTypeRaw) ?? .song
            let ref = document.musicLibrary.appleMusicItem(id: id, kind: kind)
                ?? AppleMusicItemRef(id: id, kind: kind, source: source, titleSnapshot: id)
            do {
                try await context.systemProvider.playAppleMusic(ref, engine: .application)
                env.it = ref.encodedSource
                env.result = ref.encodedSource
            } catch {
                throw ScriptError(message: "Apple Music playback failed: \(error.localizedDescription)", line: handler.line, handler: handler.name)
            }

        case .seekAppleMusic(let positionExpr):
            guard document.stack.appleMusicAllowed else {
                throw ScriptError(message: "Apple Music is disabled for this stack", line: handler.line, handler: handler.name)
            }
            let position = max(0, toNumber(try await evaluate(positionExpr, env: &env, document: document, context: context)))
            do {
                try await context.systemProvider.seekAppleMusic(to: position, engine: .application)
                env.it = formatNumber(position)
                env.result = formatNumber(position)
            } catch {
                throw ScriptError(message: "Apple Music seek failed: \(error.localizedDescription)", line: handler.line, handler: handler.name)
            }

        case .stopAppleMusic:
            await context.systemProvider.stopAppleMusic(engine: .application)
            env.it = "stopped"
            env.result = "stopped"

        case .pauseAppleMusic:
            await context.systemProvider.pauseAppleMusic(engine: .application)
            env.it = "paused"
            env.result = "paused"

        case .resumeAppleMusic:
            do {
                try await context.systemProvider.resumeAppleMusic(engine: .application)
                env.it = "playing"
                env.result = "playing"
            } catch {
                throw ScriptError(message: "Apple Music resume failed: \(error.localizedDescription)", line: handler.line, handler: handler.name)
            }

        case .exportMusicPattern(let nameExpr, let assetNameExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let assetNameValue = try await evaluate(assetNameExpr, env: &env, document: document, context: context)
            guard let pattern = document.musicLibrary.pattern(named: name) else {
                throw ScriptError(message: "Music pattern '\(name)' not found", line: handler.line, handler: handler.name)
            }
            let exportedName = upsertMusicAsset(
                pattern: pattern,
                requestedName: assetNameValue,
                document: &document
            )
            env.it = exportedName
            env.result = exportedName

        case .beep(let countExpr):
            let count: Int
            if let expr = countExpr {
                count = max(1, clampedInt(toNumber(try await evaluate(expr, env: &env, document: document, context: context))))
            } else {
                count = 1
            }
            await context.systemProvider.beep(count: count)

        case .waitDuration(let expr, let unit):
            let val = try await evaluate(expr, env: &env, document: document, context: context)
            let numericValue = toNumber(val)
            let seconds = waitDurationSeconds(from: numericValue, unit: unit)
            if seconds > 0 {
                let cappedSeconds = min(seconds, 300)
                let unitName = unit == .ticks ? "ticks" : "seconds"
                HypeLogger.shared.info(
                    "wait \(formatNumber(numericValue)) \(unitName) -> \(formatNumber(seconds))s (sleep \(formatNumber(cappedSeconds))s)",
                    source: "HypeTalk Runtime"
                )
                if let runtime = context.runtimeProvider {
                    try await runtime.sleep(seconds: cappedSeconds)
                } else {
                    try await sleepOutsideRuntime(seconds: cappedSeconds)
                }
                env.deferNextSelfSend = true
            }

        case .waitCondition(let condition, let mode):
            // Poll the condition every 50ms, cap at 30 seconds.
            let maxWait = 30.0
            let start = Date()
            while Date().timeIntervalSince(start) < maxWait {
                let condVal = try await evaluate(condition, env: &env, document: document, context: context)
                let truthy = isTruthy(condVal)
                if (mode == .untilTrue && truthy) || (mode == .whileTrue && !truthy) {
                    break
                }
                if let runtime = context.runtimeProvider {
                    try await runtime.sleep(seconds: 0.05)
                } else {
                    try await sleepOutsideRuntime(seconds: 0.05)
                }
            }
            env.deferNextSelfSend = true

        // Animation
        case .animateProperty(let property, let targetExpr, let toValueExpr, let durationExpr):
            let toValueStr = try await evaluate(toValueExpr, env: &env, document: document, context: context)
            let durationVal = toNumber(try await evaluate(durationExpr, env: &env, document: document, context: context))

            // Resolve the target part
            if case .objectRef(let ref) = targetExpr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let partIndex = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
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
            _ = toolName  // `choose` must not set `it` per classic HyperCard semantics.

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
            _ = text  // `type` must not set `it` per classic HyperCard semantics.

        case .convert(let sourceExpr, let targetExpr):
            // Read the source value directly from the container rather than via
            // evaluate(), which returns the Part's UUID string for objectRefs.
            let sourceValue: String
            switch sourceExpr {
            case .variable(let name):
                sourceValue = env.getVariable(name)
            case .it:
                sourceValue = env.it
            case .objectRef(let ref):
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                    sourceValue = document.parts[idx].textContent
                } else {
                    sourceValue = try await evaluate(sourceExpr, env: &env, document: document, context: context)
                }
            default:
                // Bare literal, chunk expression, etc. — evaluate normally.
                sourceValue = try await evaluate(sourceExpr, env: &env, document: document, context: context)
            }
            let formatValue = try await evaluate(targetExpr, env: &env, document: document, context: context)
            let converted = convertDateTime(sourceValue, toFormat: formatValue)
            // Write the converted value back into the source container, mirroring
            // the `put X into <container>` assignment path.
            switch sourceExpr {
            case .variable(let name):
                env.setVariable(name, converted)
            case .it:
                env.it = converted
            case .objectRef(let ref):
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                    document.parts[idx].textContent = converted
                }
            default:
                // Bare literal or unrecognised container — store in `it`
                env.it = converted
            }

        case .saveStack:
            await context.hostProvider.saveStack()

        case .closeWindow(let expr):
            if let expr {
                let windowName = try await evaluate(expr, env: &env, document: document, context: context)
                closeHyperCardWindow(
                    windowName: windowName,
                    env: &env,
                    document: &document,
                    currentCardId: context.currentCardId
                )
            } else {
                await context.hostProvider.closeWindow()
            }

        case .quitApp:
            await context.hostProvider.quitApp()

        case .editScriptOf(let targetExpr):
            let objectId: UUID?
            if case .objectRef(let ref) = targetExpr {
                let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                    objectId = document.parts[idx].id
                } else {
                    objectId = nil
                }
            } else {
                objectId = nil
            }
            await context.hostProvider.editScript(ofObjectId: objectId)

        case .dragFrom(let fromExpr, let toExpr):
            let fromVal = try await evaluate(fromExpr, env: &env, document: document, context: context)
            let toVal = try await evaluate(toExpr, env: &env, document: document, context: context)
            let fromParts = fromVal.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let toParts = toVal.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if fromParts.count >= 2 && toParts.count >= 2 {
                let x0 = clampedInt(Double(fromParts[0]) ?? 0)
                let y0 = clampedInt(Double(fromParts[1]) ?? 0)
                let x1 = clampedInt(Double(toParts[0]) ?? 0)
                let y1 = clampedInt(Double(toParts[1]) ?? 0)
                let radius = clampedInt(toNumber(env.getVariable("pencilsize")))
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
            if callback != nil {
                context.profiler?.recordCallbackRequest("requestURL")
            }
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
            let status = clampedInt(toNumber(try await evaluate(statusExpr, env: &env, document: document, context: context)))
            let headers = try await evaluateOptional(headersExpr, env: &env, document: document, context: context) ?? ""
            let body = try await evaluateOptional(bodyExpr, env: &env, document: document, context: context) ?? ""
            try await runtime.reply(to: requestID, status: status, headersText: headers, body: body)
            env.it = requestID.uuidString

        case .listenHTTP(let portExpr, let hostExpr, let methodExpr, let pathExpr, let callbackExpr):
            guard let runtime = context.runtimeProvider else {
                throw ScriptError(message: "Network runtime is unavailable", line: handler.line, handler: handler.name)
            }
            let port = clampedInt(toNumber(try await evaluate(portExpr, env: &env, document: document, context: context)))
            let host = try await evaluateOptional(hostExpr, env: &env, document: document, context: context) ?? "127.0.0.1"
            let method = try await evaluateOptional(methodExpr, env: &env, document: document, context: context)
            let path = try await evaluateOptional(pathExpr, env: &env, document: document, context: context)
            let callback = try await evaluate(callbackExpr, env: &env, document: document, context: context)
            context.profiler?.recordCallbackRequest("listenHTTP")
            let listenerID = try await runtime.startListener(
                ListenerSpec(transport: .http, host: host, port: port, bindScope: .loopback, callbackMessage: callback, httpMethod: method, httpPath: path),
                owner: RuntimeOwnerContext(targetId: context.targetId, currentCardId: context.currentCardId, scriptContext: context.scriptContext)
            )
            env.it = listenerID.uuidString

        case .listenTCP(let portExpr, let hostExpr, let callbackExpr):
            guard let runtime = context.runtimeProvider else {
                throw ScriptError(message: "Network runtime is unavailable", line: handler.line, handler: handler.name)
            }
            let port = clampedInt(toNumber(try await evaluate(portExpr, env: &env, document: document, context: context)))
            let host = try await evaluateOptional(hostExpr, env: &env, document: document, context: context) ?? "127.0.0.1"
            let callback = try await evaluate(callbackExpr, env: &env, document: document, context: context)
            context.profiler?.recordCallbackRequest("listenTCP")
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
            let port = clampedInt(toNumber(try await evaluate(portExpr, env: &env, document: document, context: context)))
            let tlsValue = try await evaluateOptional(tlsExpr, env: &env, document: document, context: context)
            let tls = tlsValue.map(isTruthy) ?? false
            let callback = try await evaluate(callbackExpr, env: &env, document: document, context: context)
            context.profiler?.recordCallbackRequest("connectTCP")
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
                      let asset = document.assetRepository.asset(byName: assetName) else {
                    return nil
                }
                return (
                    assetRef: document.assetRepository.assetRef(for: asset),
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
            let cols = colsExpr != nil ? clampedInt(toNumber(try await evaluate(colsExpr!, env: &env, document: document, context: context))) : 10
            let rows = rowsExpr != nil ? clampedInt(toNumber(try await evaluate(rowsExpr!, env: &env, document: document, context: context))) : 10
            let explicitTileSize: Double? = tileSizeExpr != nil
                ? toNumber(try await evaluate(tileSizeExpr!, env: &env, document: document, context: context))
                : nil
            let tilesetName: String? = tilesetExpr != nil ? try await evaluate(tilesetExpr!, env: &env, document: document, context: context) : nil
            let tileMapAsset: (assetRef: AssetRef, tileColumns: Int, tileWidth: Double, tileHeight: Double, isTileSet: Bool)? = {
                guard let tilesetName,
                      let asset = document.assetRepository.asset(byName: tilesetName) else {
                    return nil
                }
                return (
                    assetRef: document.assetRepository.assetRef(for: asset),
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
                    let mapWidth = max(0, Double(tmSpec.columns)) * max(1, tmSpec.tileWidth)
                    let mapHeight = max(0, Double(tmSpec.rows)) * max(1, tmSpec.tileHeight)
                    spec.size = SizeSpec(
                        width: max(spec.size.width, node.position.x + mapWidth),
                        height: max(spec.size.height, node.position.y + mapHeight)
                    )
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
            let col = clampedInt(toNumber(try await evaluate(colExpr, env: &env, document: document, context: context)))
            let row = clampedInt(toNumber(try await evaluate(rowExpr, env: &env, document: document, context: context)))
            let tilemapName = try await evaluate(tilemapExpr, env: &env, document: document, context: context)
            let tileIndex = clampedInt(toNumber(try await evaluate(tileIndexExpr, env: &env, document: document, context: context)))

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
            let tileIndex = clampedInt(toNumber(try await evaluate(tileIndexExpr, env: &env, document: document, context: context)))
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

        case .resetCmd(let expr):
            if let expr {
                let target = try await evaluate(expr, env: &env, document: document, context: context)
                if target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ai session" {
                    env.it = "ok"
                    env.result = "ok"
                }
            }

        case .push(let cardExpr):
            let cardId: UUID
            if let expr = cardExpr {
                let refValue = try await evaluate(expr, env: &env, document: document, context: context)
                if let uuid = UUID(uuidString: refValue) {
                    cardId = uuid
                } else if let resolved = resolveNavigation(refValue, document: document, currentCardId: context.currentCardId) {
                    cardId = resolved
                } else {
                    cardId = context.currentCardId
                }
            } else {
                cardId = context.currentCardId
            }
            await context.runtimeProvider?.pushCardToHistory(cardId)

        case .pop:
            if let poppedId = await context.runtimeProvider?.popCardFromHistory() {
                navigationTarget = poppedId
                await context.runtimeProvider?.navigateToCard(poppedId)
            }

        case .printCmd(let expr):
            let target: HostPrintTarget
            if let expr = expr {
                if case .objectRef(let ref) = expr {
                    let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
                    let ltype = ref.objectType.lowercased()
                    if (ltype == "field" || ltype == "fld"),
                       let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                        target = .field(document.parts[idx].textContent)
                    } else {
                        let val = try await evaluate(expr, env: &env, document: document, context: context)
                        target = .field(val)
                    }
                } else {
                    let val = try await evaluate(expr, env: &env, document: document, context: context)
                    target = .field(val)
                }
            } else {
                target = .card
            }
            await context.hostProvider.print(target: target)

        case .doMenuCmd(let expr):
            let item = try await evaluate(expr, env: &env, document: document, context: context)
            _ = await context.hostProvider.doMenu(item: item)

        case .startUsing(let stackExpr):
            let alias = try await evaluate(stackExpr, env: &env, document: document, context: context)
            switch document.stackLibrary.startUsing(alias) {
            case .started(let entry):
                env.it = entry.primaryAlias
                env.result = entry.primaryAlias
            case .missing(let missingAlias):
                throw ScriptError(message: "Stack not found: \(missingAlias)", line: handler.line, handler: handler.name)
            case .ambiguous(let ambiguousAlias, let candidates):
                let names = stackLibraryCandidateSummary(candidates)
                throw ScriptError(
                    message: "Ambiguous stack name '\(ambiguousAlias)': \(names)",
                    line: handler.line,
                    handler: handler.name
                )
            case .stopped:
                break
            }

        case .stopUsing(let stackExpr):
            let alias = try await evaluate(stackExpr, env: &env, document: document, context: context)
            switch document.stackLibrary.stopUsing(alias) {
            case .stopped(let entry):
                env.it = entry.primaryAlias
                env.result = entry.primaryAlias
            case .missing(let missingAlias):
                throw ScriptError(message: "Stack not found: \(missingAlias)", line: handler.line, handler: handler.name)
            case .ambiguous(let ambiguousAlias, let candidates):
                let names = stackLibraryCandidateSummary(candidates)
                throw ScriptError(
                    message: "Ambiguous stack name '\(ambiguousAlias)': \(names)",
                    line: handler.line,
                    handler: handler.name
                )
            case .started:
                break
            }

        case .clickAt, .disableCmd, .enableCmd,
              .helpCmd, .debugCmd, .dialCmd,
              .runCmd, .copyTemplate:
            break

        case .exportPaint(let nameExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            #if canImport(AppKit)
            let layer = document.paintLayer(forCardId: context.currentCardId)
                ?? CardPaintLayer(cardId: context.currentCardId, width: 1, height: 1, rgbaData: Data(count: 4))
            guard let png = PaintImageCodec.encodePNG(layer) else {
                throw ScriptError(message: "Could not export paint.", line: handler.line, handler: handler.name)
            }
            do {
                try await context.fileProvider.writeData(png, named: name)
            } catch let e as FileAccessError {
                throw ScriptError(message: e.scriptMessage, line: handler.line, handler: handler.name)
            }
            #else
            throw ScriptError(message: "Paint export is not available on this platform.", line: handler.line, handler: handler.name)
            #endif

        case .importPaint(let nameExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            #if canImport(AppKit)
            let data: Data
            do {
                data = try await context.fileProvider.readData(named: name)
            } catch let e as FileAccessError {
                throw ScriptError(message: e.scriptMessage, line: handler.line, handler: handler.name)
            }
            guard let layer = PaintImageCodec.decodePNG(data, cardId: context.currentCardId) else {
                throw ScriptError(message: "Could not import paint. The file is not a valid image.", line: handler.line, handler: handler.name)
            }
            document.setPaintLayer(layer)
            #else
            throw ScriptError(message: "Paint import is not available on this platform.", line: handler.line, handler: handler.name)
            #endif

        case .readCmd(let pathExpr, let startExpr, let mode):
            let name = try await evaluate(pathExpr, env: &env, document: document, context: context)
            do {
                let contents = try await context.fileProvider.readFile(named: name)
                env.it = try await boundedRead(
                    contents,
                    startExpr: startExpr,
                    mode: mode,
                    env: &env,
                    document: document,
                    context: context
                )
            } catch let e as FileAccessError {
                throw ScriptError(message: e.scriptMessage, line: handler.line, handler: handler.name)
            }

        case .writeCmd(let dataExpr, let pathExpr, let placement):
            let data = try await evaluate(dataExpr, env: &env, document: document, context: context)
            let name = try await evaluate(pathExpr, env: &env, document: document, context: context)
            do {
                let contents = try await placedWriteContents(
                    data: data,
                    path: name,
                    placement: placement,
                    env: &env,
                    document: document,
                    context: context
                )
                try await context.fileProvider.writeFile(contents, named: name)
            } catch let e as FileAccessError {
                throw ScriptError(message: e.scriptMessage, line: handler.line, handler: handler.name)
            }
        }
    }

    private func handleClassicBuiltInCommand(
        normalizedName: String,
        args: [Value],
        document: HypeDocument,
        context: ExecutionContext,
        navigationTarget: inout UUID?,
        env: inout Environment
    ) -> Bool {
        switch normalizedName {
        case "arrowkey":
            let direction = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            switch direction {
            case "left":
                navigationTarget = CardNavigator.navigate(direction: .previous, currentCardId: context.currentCardId, document: document)
            case "right":
                navigationTarget = CardNavigator.navigate(direction: .next, currentCardId: context.currentCardId, document: document)
            case "up", "down":
                // HyperCard uses the recent-card stack for up/down. Hype's
                // runtime card history is async, so keep this command safe and
                // deterministic at interpreter level; explicit `push`/`pop` is
                // already supported for stack history traversal.
                navigationTarget = nil
            default:
                navigationTarget = nil
            }
            if let navigationTarget {
                env.effectiveCurrentCardId = navigationTarget
            }
            return true
        default:
            return false
        }
    }

    private func boundedRead(
        _ contents: String,
        startExpr: Expression?,
        mode: FileReadMode,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> String {
        let startOffset = try await fileReadStartOffset(
            contents: contents,
            startExpr: startExpr,
            env: &env,
            document: document,
            context: context
        )
        let start = contents.index(contents.startIndex, offsetBy: startOffset)
        let remainder = String(contents[start...])
        switch mode {
        case .entireFile:
            return remainder
        case .charCount(let countExpr):
            let countText = try await evaluate(countExpr, env: &env, document: document, context: context)
            let count = max(0, clampedInt(toNumber(countText)))
            let end = remainder.index(remainder.startIndex, offsetBy: min(count, remainder.count))
            return String(remainder[..<end])
        case .until(let delimiterExpr):
            let delimiterText = try await evaluate(delimiterExpr, env: &env, document: document, context: context)
            if delimiterText.lowercased() == "eof" {
                return remainder
            }
            guard !delimiterText.isEmpty else { return remainder }
            if let range = remainder.range(of: delimiterText) {
                return String(remainder[..<range.upperBound])
            }
            return remainder
        }
    }

    private func fileReadStartOffset(
        contents: String,
        startExpr: Expression?,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Int {
        guard let startExpr else { return 0 }
        let startText = try await evaluate(startExpr, env: &env, document: document, context: context)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if startText.isEmpty || startText == "start" {
            return 0
        }
        let raw = clampedInt(toNumber(startText))
        if raw < 0 {
            return max(0, contents.count + raw)
        }
        if raw == 0 { return 0 }
        return min(contents.count, raw - 1)
    }

    private func placedWriteContents(
        data: String,
        path: String,
        placement: FileWritePlacement,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> String {
        switch placement {
        case .replace:
            return data
        case .start:
            let existing = try await existingFileContentsOrEmpty(path: path, context: context)
            return data + existing
        case .end:
            let existing = try await existingFileContentsOrEmpty(path: path, context: context)
            return existing + data
        case .offset(let offsetExpr):
            let existing = try await existingFileContentsOrEmpty(path: path, context: context)
            let offsetText = try await evaluate(offsetExpr, env: &env, document: document, context: context)
            let raw = clampedInt(toNumber(offsetText))
            let offset = raw < 0 ? max(0, existing.count + raw) : min(existing.count, max(0, raw - 1))
            let index = existing.index(existing.startIndex, offsetBy: offset)
            return String(existing[..<index]) + data + String(existing[index...])
        }
    }

    private func existingFileContentsOrEmpty(path: String, context: ExecutionContext) async throws -> String {
        do {
            return try await context.fileProvider.readFile(named: path)
        } catch FileAccessError.notFound {
            return ""
        }
    }

    // MARK: - Sort key evaluation helper

    /// Evaluate a sort-by expression in the given card context, returning the
    /// sort key as a plain string.
    ///
    /// For `objectRef` expressions that target a field or button the HyperCard
    /// semantics are to return the part's *text content*, not its UUID (which
    /// is what the generic `evaluate` path returns for part references). This
    /// helper special-cases that path so `sort cards by field "Name"` produces
    /// the field's text rather than its ID.
    private func evaluateSortKey(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> String {
        if case .objectRef(let ref) = expr {
            let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            let ltype = ref.objectType.lowercased()
            if ltype == "field" || ltype == "fld" || ltype == "button" || ltype == "btn" {
                if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                    return document.parts[idx].textContent
                }
            }
        }
        return try await evaluate(expr, env: &env, document: document, context: context)
    }

    // MARK: - Sort container (1B.sort lines/items)

    /// Execute `sort [lines|items] of <container> [ascending|descending] [text|numeric] [by <expr>]`.
    ///
    /// Split the container by chunkType, evaluate sort keys, sort stably, write back.
    /// `dateTime` and `international` styles degrade to text (documented).
    private func executeSortContainer(
        chunkType: ChunkType,
        containerExpr: Expression,
        direction: SortDirection,
        style: SortStyle,
        byExpr: Expression?,
        env: inout Environment,
        document: inout HypeDocument,
        context: ExecutionContext,
        handler: Handler,
        instructionCount: inout Int,
        navigationTarget: inout UUID?,
        projectNavigationTarget: inout ProjectNavigationTarget?
    ) async throws {
        let containerValue = try await evaluate(containerExpr, env: &env, document: document, context: context)
        guard !containerValue.isEmpty else { return }

        // Split using the same logic as evaluateChunk.
        let elements: [String]
        switch chunkType {
        case .word:
            elements = containerValue.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        case .char, .character:
            elements = containerValue.map(String.init)
        case .item:
            let delimChar = env.itemDelimiter.first ?? ","
            elements = containerValue.split(separator: delimChar, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        case .line:
            elements = splitLines(containerValue)
        }
        guard elements.count > 1 else { return }

        // Evaluate sort key per element. If `by` is present, bind `each` to the element.
        var keyed: [(element: String, key: String)] = []
        for element in elements {
            let key: String
            if let keyExpr = byExpr {
                // Bind `each` as a local variable for the key expression.
                env.setVariable("each", element)
                key = try await evaluate(keyExpr, env: &env, document: document, context: context)
            } else {
                key = element
            }
            keyed.append((element: element, key: key))
        }

        // Determine sort order.
        let useNumeric: Bool
        switch style {
        case .numeric:
            useNumeric = true
        case .text, .dateTime, .international:
            // .dateTime and .international degrade to text for now.
            useNumeric = keyed.allSatisfy {
                let d = Double($0.key)
                return d != nil && d!.isFinite
            }
        }

        let sorted: [(element: String, key: String)]
        if useNumeric {
            sorted = keyed.sorted { a, b in
                let aVal = Double(a.key) ?? 0
                let bVal = Double(b.key) ?? 0
                return direction == .ascending ? aVal < bVal : aVal > bVal
            }
        } else {
            sorted = keyed.sorted { a, b in
                let cmp = a.key.compare(b.key, options: .caseInsensitive)
                return direction == .ascending
                    ? cmp == .orderedAscending
                    : cmp == .orderedDescending
            }
        }

        // Rejoin with the appropriate delimiter.
        let joinedDelim: String
        switch chunkType {
        case .word: joinedDelim = " "
        case .char, .character: joinedDelim = ""
        case .item: joinedDelim = env.itemDelimiter
        case .line: joinedDelim = "\n"
        }
        let newValue = sorted.map(\.element).joined(separator: joinedDelim)

        // Write back to the container.
        switch containerExpr {
        case .variable(let name):
            env.setVariable(name, newValue)
        case .it:
            env.it = newValue
        case .objectRef(let ref):
            let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env,
                                       document: document, currentCardId: context.currentCardId) {
                document.parts[idx].textContent = newValue
            }
        default:
            break
        }
    }

    // MARK: - Date/time conversion helper

    /// Convert a date/time value to the requested HyperCard format string.
    ///
    /// The `source` is accepted as:
    /// - An integer seconds-since-epoch value (e.g., `"0"`)
    /// - An ISO-8601 or common locale date string parsed via `DateFormatter`
    /// - Any of the HyperCard `dateItems` comma-separated format
    ///
    /// The `format` keyword vocabulary mirrors HyperCard:
    /// - `"seconds"` → Unix epoch integer
    /// - `"dateItems"` → comma-separated `year,month,day,hour,minute,second,weekday`
    /// - `"short date"` → locale short date (e.g. `"5/29/26"`)
    /// - `"abbreviated date"` / `"abbrev date"` / `"abbr date"` → medium date (e.g. `"May 29, 2026"`)
    /// - `"long date"` → full date (e.g. `"Friday, May 29, 2026"`)
    /// - `"short time"` → short time (e.g. `"3:04 PM"`)
    /// - `"long time"` → medium time with seconds (e.g. `"3:04:05 PM"`)
    /// - Combinations like `"long date and long time"` are split and rendered with a space.
    ///
    /// All formatters use `en_US_POSIX` locale so output is deterministic in tests.
    /// When the source cannot be parsed the original value is returned unchanged.
    private func convertDateTime(_ source: String, toFormat format: String) -> String {
        guard let date = parseHyperCardDate(source) else { return source }
        let fmtLower = format.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Handle compound formats: "long date and long time", "short date and short time", etc.
        if let andRange = fmtLower.range(of: " and ") {
            let leftFmt = String(fmtLower[fmtLower.startIndex..<andRange.lowerBound])
            let rightFmt = String(fmtLower[andRange.upperBound...])
            let left = formatHyperCardDate(date, formatKeyword: leftFmt)
            let right = formatHyperCardDate(date, formatKeyword: rightFmt)
            return "\(left) \(right)"
        }
        return formatHyperCardDate(date, formatKeyword: fmtLower)
    }

    /// Parse a string into a `Date` using the formats HyperCard scripts commonly produce.
    private func parseHyperCardDate(_ source: String) -> Date? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        // 1. Bare integer — treat as seconds since epoch.
        if let seconds = Double(trimmed), seconds.isFinite {
            return Date(timeIntervalSince1970: seconds)
        }
        // 2. HyperCard dateItems: "year,month,day,hour,minute,second,weekday"
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        if parts.count >= 6 {
            let nums = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count >= 6 {
                var comps = DateComponents()
                comps.year   = nums[0]
                comps.month  = nums[1]
                comps.day    = nums[2]
                comps.hour   = nums[3]
                comps.minute = nums[4]
                comps.second = nums[5]
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "UTC")!
                if let date = cal.date(from: comps) { return date }
            }
        }
        // 3. Try common string formats with en_US_POSIX locale and UTC timezone
        // so parsing is deterministic regardless of the host machine's locale.
        let utc = TimeZone(identifier: "UTC")!
        let candidates = [
            "M/d/yy",
            "M/d/yyyy",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "EEEE, MMMM d, yyyy",
            "h:mm a",
            "h:mm:ss a",
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
        ]
        for fmt in candidates {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = utc
            df.dateFormat = fmt
            if let date = df.date(from: trimmed) { return date }
        }
        return nil
    }

    /// Format a `Date` using a single HyperCard format keyword.
    ///
    /// All formatters use UTC timezone so output is deterministic regardless
    /// of the machine's local timezone. This matches the test expectation that
    /// epoch 0 formats as January 1, 1970 everywhere.
    private func formatHyperCardDate(_ date: Date, formatKeyword: String) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        let utc = TimeZone(identifier: "UTC")!
        switch formatKeyword {
        case "seconds":
            return String(Int(date.timeIntervalSince1970))
        case "dateitems":
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = utc
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
            let y  = comps.year   ?? 0
            let mo = comps.month  ?? 0
            let d  = comps.day    ?? 0
            let h  = comps.hour   ?? 0
            let mi = comps.minute ?? 0
            let s  = comps.second ?? 0
            let wd = comps.weekday ?? 1   // 1=Sunday in Gregorian, matches HyperCard
            return "\(y),\(mo),\(d),\(h),\(mi),\(s),\(wd)"
        case "short date":
            let df = DateFormatter()
            df.locale = posix
            df.timeZone = utc
            df.dateFormat = "M/d/yy"
            return df.string(from: date)
        case "abbreviated date", "abbrev date", "abbr date":
            let df = DateFormatter()
            df.locale = posix
            df.timeZone = utc
            df.dateFormat = "MMM d, yyyy"
            return df.string(from: date)
        case "long date":
            let df = DateFormatter()
            df.locale = posix
            df.timeZone = utc
            df.dateFormat = "EEEE, MMMM d, yyyy"
            return df.string(from: date)
        case "short time":
            let df = DateFormatter()
            df.locale = posix
            df.timeZone = utc
            df.dateFormat = "h:mm a"
            return df.string(from: date)
        case "long time":
            let df = DateFormatter()
            df.locale = posix
            df.timeZone = utc
            df.dateFormat = "h:mm:ss a"
            return df.string(from: date)
        default:
            // Unrecognised keyword — fall back to long date format.
            return formatHyperCardDate(date, formatKeyword: "long date")
        }
    }

    private func evaluateExternalArgumentExpression(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
        let evaluated = try await evaluate(expr, env: &env, document: document, context: context)
        if evaluated.isEmpty, case .variable(let name) = expr {
            return name
        }
        return evaluated
    }

    private func stackLibraryCandidateSummary(_ candidates: [HypeStackLibraryEntry]) -> String {
        candidates
            .map { $0.stackName.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
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
            partIndex = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId)
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
        context.profiler?.recordExpression(expressionKind(expr))
        switch expr {
        case .literal(let val):
            return val

        case .variable(let name):
            // Lowercase the name exactly once.  Previously `name.lowercased()` was
            // called up to four times per variable access (switch, two `.keys.contains`
            // checks, and `getVariable`'s own re-lowercasing).  One allocation per access.
            let key = name.lowercased()

            // Check constants first — these shadow user variables (HyperCard semantics).
            switch key {
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
            case "formfeed": return "\u{0C}"
            case "null": return "\u{00}"
            // Well-known HyperTalk system properties accepted as
            // bare identifiers (no `the` prefix required). Users
            // and AI models routinely write `put mouseLoc into m`
            // or `put ticks into t` rather than the more formal
            // `put the mouseLoc into m`. Fall through to the
            // property evaluator when the variable name matches one
            // of these so the bare form produces the same value as
            // the articled form. A user-declared local or global of
            // the same name takes precedence — checked below via a
            // direct dictionary lookup (avoids building a `.keys` view).
            case "mouseloc", "mouseh", "mousev",
                 "date", "time", "ticks", "seconds",
                 "paramcount", "params",
                 "hoveredsprite", "spriteundermouse", "hoveredspritename":
                // User variable takes precedence over the system property alias.
                // Use dictionary lookup rather than `.keys.contains` to avoid
                // allocating the keys view.
                if env.locals[key] != nil || env.globalNames.contains(key) {
                    return env.getVariableKey(key)
                }
                return try await evaluateProperty(
                    name, target: nil,
                    env: &env, document: document, context: context
                )
            default: break
            }
            // Not a constant or system property — look up as a user variable.
            // Use the pre-computed `key` to avoid a second lowercasing in getVariable.
            return env.getVariableKey(key)

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

        case .messageBox:
            // Read the global message box container.
            return env.globals[Self.messageBoxKey] ?? ""

        case .binary(let left, let op, let right):
            let lVal = try await evaluate(left, env: &env, document: document, context: context)
            let rVal = try await evaluate(right, env: &env, document: document, context: context)
            return evaluateBinary(lVal, op, rVal)

        case .unary(let op, let operand):
            let val = try await evaluate(operand, env: &env, document: document, context: context)
            switch op {
            case .negate: return formatNumber(-toNumber(val))
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
            if let handlerValue = try await evaluateHandlerFunctionIfAvailable(
                name: name,
                args: evaluatedArgs,
                env: &env,
                document: document,
                context: context,
                handler: Handler(name: name, handlerType: .function, params: [], body: [], line: 0)
            ) {
                return handlerValue
            }
            return try await evaluateBuiltIn(name, args: evaluatedArgs, env: &env, document: document, context: context)

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
            let identVal = try await evaluateObjectRefIdentifier(ref.identifier, env: &env, document: document, context: context)
            if let partIndex = findPartIndex(ref.objectType, identifier: identVal, env: &env, document: document, currentCardId: context.currentCardId),
               document.parts[partIndex].partType == .field || document.parts[partIndex].partType == .button {
                return document.parts[partIndex].textContent
            }
            return resolveObjectRef(ref.objectType, identifier: identVal, document: document, context: context)

        case .scopedObjectRef(let object, let owner):
            if let partIndex = try await findScopedPartIndex(
                object: object,
                owner: owner,
                env: &env,
                document: document,
                context: context
            ) {
                if document.parts[partIndex].partType == .field || document.parts[partIndex].partType == .button {
                    return document.parts[partIndex].textContent
                }
                return document.parts[partIndex].id.uuidString
            }
            return ""

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
            let col = clampedInt(toNumber(try await evaluate(colExpr, env: &env, document: document, context: context)))
            let row = clampedInt(toNumber(try await evaluate(rowExpr, env: &env, document: document, context: context)))
            let tilemapName = try await evaluate(tilemapExpr, env: &env, document: document, context: context)
            guard let location = nodeLocation(
                named: tilemapName,
                objectType: "tilemap",
                document: document,
                currentCardId: context.currentCardId
            ),
                  let tmSpec = location.node.tileMapSpec
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
            case "date": return parseHyperCardDate(val) != nil ? "true" : "false"
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
            case "date": return parseHyperCardDate(val) != nil ? "false" : "true"
            case "empty": return val.isEmpty ? "false" : "true"
            default: return "true"
            }

        case .thereIsA(let objectType, let nameExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let found = objectExistsInScope(
                objectType: objectType, name: name,
                env: env, document: document, currentCardId: context.currentCardId
            )
            return found ? "true" : "false"

        case .thereIsNo(let objectType, let nameExpr):
            let name = try await evaluate(nameExpr, env: &env, document: document, context: context)
            let found = objectExistsInScope(
                objectType: objectType, name: name,
                env: env, document: document, currentCardId: context.currentCardId
            )
            return found ? "false" : "true"

        case .askMeshy(let promptExpr, let styleExpr):
            // Expression form: `ask meshy "<prompt>" [with style <s>]`
            //
            // Synchronous-only — the async callback form is handled exclusively
            // by Statement.askMeshy. Security gate and off-main-thread Keychain
            // reads are the provider's responsibility, matching the existing
            // Statement.askMeshy sync path (Phase 3 M3 pattern).
            //
            // Returns the new asset name on success; "" on gate refusal, missing
            // provider, or any provider error. This matches the sync Statement
            // form's degradation contract so callers can always do:
            //   put ask meshy "barrel" into newModel
            //   if newModel is not empty then ...
            let promptText = try await evaluate(promptExpr, env: &env, document: document, context: context)
            let styleText = try await evaluateOptional(styleExpr, env: &env, document: document, context: context)
            guard let provider = context.meshyProvider else {
                return ""
            }
            do {
                let assetName = try await provider.generateSync(
                    prompt: promptText,
                    style: styleText,
                    model: nil,
                    document: document
                )
                return assetName
            } catch {
                return ""
            }
        }
    }

    // MARK: - Binary operations

    /// Unified comparison: numeric when both operands parse as finite numbers,
    /// otherwise case-insensitive lexical. Returns -1, 0, or +1.
    ///
    /// Classic HyperCard rule (HyperTalk_Reference.md §10523-10542):
    /// `=`/`is` "same value"; relational operators "can be arithmetic, text,
    /// or logical." The key decision is: if *both* sides parse as finite numbers,
    /// use numeric order; otherwise fall back to case-insensitive string order.
    /// This means `5 = 5.0` → true and `"apple" < "banana"` → true.
    private func compareValues(_ l: Value, _ r: Value) -> Int {
        let lt = l.trimmingCharacters(in: .whitespaces)
        let rt = r.trimmingCharacters(in: .whitespaces)
        if let ld = Double(lt), let rd = Double(rt), ld.isFinite && rd.isFinite {
            if ld < rd { return -1 }
            if ld > rd { return  1 }
            return 0
        }
        switch l.compare(r, options: .caseInsensitive) {
        case .orderedAscending:  return -1
        case .orderedDescending: return  1
        case .orderedSame:       return  0
        }
    }

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
            return divisor != 0 ? formatNumber((toNumber(lVal) / divisor).rounded(.towardZero)) : "0"
        // Route all six comparison operators through compareValues for unified
        // numeric-vs-lexical semantics (B1 fix).
        case .equal:          return compareValues(lVal, rVal) == 0  ? "true" : "false"
        case .notEqual:       return compareValues(lVal, rVal) != 0  ? "true" : "false"
        case .lessThan:       return compareValues(lVal, rVal) <  0  ? "true" : "false"
        case .greaterThan:    return compareValues(lVal, rVal) >  0  ? "true" : "false"
        case .lessOrEqual:    return compareValues(lVal, rVal) <= 0  ? "true" : "false"
        case .greaterOrEqual: return compareValues(lVal, rVal) >= 0  ? "true" : "false"
        case .and:            return (isTruthy(lVal) && isTruthy(rVal)) ? "true" : "false"
        case .or:             return (isTruthy(lVal) || isTruthy(rVal)) ? "true" : "false"
        }
    }

    private func generateAIResponse(
        prompt: String,
        model: String?,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
        let response = try await RuntimeAwareAIScriptingProvider(
            baseProvider: context.aiProvider,
            document: document
        ).generate(prompt: prompt, model: model)
        await context.speechOutputProvider.speakAIResponse(response, source: "HypeTalk AI")
        return response
    }

    // MARK: - Built-in functions

    private func evaluateBuiltIn(
        _ name: String,
        args: [Value],
        env: inout Environment,
        document: HypeDocument,
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
            let max = Swift.max(1, clampedInt(toNumber(args.first ?? "0")))
            return String(Int.random(in: 1...max))
        case "abs":
            return formatNumber(abs(toNumber(args.first ?? "0")))
        case "round":
            return formatNumber(toNumber(args.first ?? "0").rounded())
        case "trunc":
            return formatNumber(toNumber(args.first ?? "0").rounded(.towardZero))
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
        case "atan2":
            guard args.count >= 2 else { return "0" }
            return formatNumber(Foundation.atan2(toNumber(args[0]), toNumber(args[1])))
        case "sqrt": return formatNumber(Foundation.sqrt(toNumber(args.first ?? "0")))
        case "exp": return formatNumber(Foundation.exp(toNumber(args.first ?? "0")))
        case "ln": return formatNumber(Foundation.log(toNumber(args.first ?? "0")))
        case "log2": return formatNumber(Foundation.log2(toNumber(args.first ?? "0")))

        // String functions
        case "chartonum":
            let str = args.first ?? ""
            return str.isEmpty ? "0" : String(Int(str.unicodeScalars.first?.value ?? 0))
        case "numtochar":
            let num = clampedInt(toNumber(args.first ?? "0"))
            guard num > 0, num < 65536, let scalar = UnicodeScalar(num) else { return "" }
            return String(Character(scalar))
        case "value":
            // Evaluate the argument string as a HypeTalk expression, reusing the
            // `do` block's security gates (depth + byte limit).
            let exprText = args.first ?? ""
            guard !exprText.isEmpty else { return "" }
            guard context.nestedEvalDepth < Self.maxNestedEvalDepth else { return exprText }
            guard exprText.utf8.count <= Self.maxDoEvalBytes else { return exprText }
            var lexer = Lexer(source: exprText)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            guard let parsedExpr = try? parser.parseExpression() else { return exprText }
            // Classic `value()` of a bare word that is not a defined variable
            // returns the word itself (e.g. value("hello") -> "hello"), rather
            // than the empty string Hype yields for an undefined variable.
            if case .variable(let vname) = parsedExpr, env.getVariable(vname).isEmpty {
                return exprText
            }
            var childContext = context
            childContext.nestedEvalDepth = context.nestedEvalDepth + 1
            return (try? await evaluate(parsedExpr, env: &env, document: document, context: childContext)) ?? exprText

        // Date and time functions
        case "date":
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: Date())
        case "time":
            return formatHyperCardTime(style: .short)
        case "ticks":
            return String(Int(Date().timeIntervalSince1970 * 60))
        case "seconds":
            return String(Int(Date().timeIntervalSince1970))
        case "number":
            return args.first ?? "0"

        case "ollama":
            switch args.count {
            case 1:
                return try await generateAIResponse(prompt: args[0], model: nil, document: context.document, context: context)
            case 2:
                return try await generateAIResponse(prompt: args[1], model: args[0], document: context.document, context: context)
            default:
                return ""
            }
        case "aimodel", "ollamamodel":
            return context.aiProvider.currentModel()
        case "aimodels", "ollamamodels":
            return try await context.aiProvider.availableModels().joined(separator: "\n")

        // Mouse functions — position trio reads live context state to match property forms.
        // `mouse` and `mouseClick` have no live source on context today; keep static.
        case "mouse": return "up"
        case "mouseclick": return "false"
        case "mouseh":    return formatNumber(context.mouseX)
        case "mousev":    return formatNumber(context.mouseY)
        case "mouseloc":  return "\(formatNumber(context.mouseX)),\(formatNumber(context.mouseY))"

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

        // `target` function — descriptor of the original dispatch recipient.
        case "target":
            return descriptorForObject(id: context.originalTargetId, document: document,
                                       context: context, form: .short)
        case "result": return env.result
        case "param":
            let index = clampedInt(toNumber(args.first ?? "1"))
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

        // Phase 2: click-info getters — read the runtime's last-click state.
        case "clickh":
            return formatNumber(await context.runtimeProvider?.clickState()?.clickH ?? 0)
        case "clickv":
            return formatNumber(await context.runtimeProvider?.clickState()?.clickV ?? 0)
        case "clickloc":
            if let cs = await context.runtimeProvider?.clickState() {
                return "\(formatNumber(cs.clickH)),\(formatNumber(cs.clickV))"
            }
            return "0,0"
        case "clicktext":
            return await context.runtimeProvider?.clickState()?.clickText ?? ""
        case "clickchunk":
            return await context.runtimeProvider?.clickState()?.clickChunk ?? ""
        case "clickline":
            return await context.runtimeProvider?.clickState()?.clickLine ?? ""

        // Phase 2: found-text getters — read the runtime's found state.
        case "foundtext":
            return await context.runtimeProvider?.foundState()?.foundText ?? ""
        case "foundchunk":
            return await context.runtimeProvider?.foundState()?.foundChunk ?? ""
        case "foundfield":
            return await context.runtimeProvider?.foundState()?.foundField ?? ""
        case "foundline":
            return await context.runtimeProvider?.foundState()?.foundLine ?? ""

        // Phase 2: selected-text getters — read the runtime's selection state.
        // `selectedButton` and `selectedLoc` have no model backing here (they
        // require live UI state); they return empty, which matches HyperCard when
        // no radio group / location is active.
        case "selectedtext":
            return await context.runtimeProvider?.selectedState()?.selectedText ?? ""
        case "selectedchunk":
            return await context.runtimeProvider?.selectedState()?.selectedChunk ?? ""
        case "selectedfield":
            return await context.runtimeProvider?.selectedState()?.selectedField ?? ""
        case "selectedline":
            return await context.runtimeProvider?.selectedState()?.selectedLine ?? ""
        case "selectedbutton", "selectedloc":
            return ""
        case "sound":
            return await context.systemProvider.currentSoundName()
        case "musicstate":
            return await context.systemProvider.currentMusicState()
        case "applemusicstate":
            return await context.systemProvider.currentAppleMusicState(engine: .application)
        case "applemusicposition", "applemusictime":
            return formatNumber(await context.systemProvider.currentAppleMusicPosition(engine: .application))
        case "applemusicauthorization", "applemusicstatus":
            return await context.systemProvider.appleMusicAuthorizationStatus().rawValue
        case "applemusiccapabilities":
            let caps = await context.systemProvider.appleMusicCapabilities()
            return [
                "authorization=\(caps.authorization.rawValue)",
                "canPlayCatalogContent=\(caps.canPlayCatalogContent)",
                "canBecomeSubscriber=\(caps.canBecomeSubscriber)",
                "hasCloudLibraryEnabled=\(caps.hasCloudLibraryEnabled)",
                "supportsLibraryMutation=\(caps.supportsLibraryMutation)"
            ].joined(separator: "\n")
        case "musicpatterns":
            return context.document.musicLibrary.patterns.map(\.name).joined(separator: "\n")
        case "musicinstruments":
            return MusicInstrumentCatalog.displayList
        case "programs":
            return "Hype"
        case "menus":
            // Return the titles of every top-level menu in the application menu bar,
            // newline-separated, via the HostApplicationProvider.
            let titles = await context.hostProvider.menuTitles()
            return titles.joined(separator: "\n")
        case "destination":
            // HyperCard `the destination` — the current stack's name (minimal implementation).
            return context.document.stack.name
        case "stacks":
            return "Hype"

        // Phase 4: Meshy webhook payload parser built-in.
        // Usage: meshy_parse_webhook(the body)
        // Returns "task_id,status,glb_url" or "" on parse failure.
        // No HMAC verification (acknowledged design decision — C18).
        case "meshy_parse_webhook":
            let body = args.first ?? ""
            return MeshyWebhookPayload.parse(jsonBody: body)?.toCSV() ?? ""

        default:
            var callDocument = document
            callDocument.scriptGlobals = env.globals
            let result = await context.externalRegistry.invoke(
                HyperCardExternalCall(name: name, kind: .xfcn, arguments: args),
                context: HyperCardExternalCallContext(
                    targetId: context.targetId,
                    currentCardId: context.currentCardId,
                    document: callDocument
                )
            )
            for (key, value) in result.runtimeGlobals {
                env.globals[key.lowercased()] = value
            }
            env.result = result.result
            return result.value
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
        context.profiler?.recordPropertyRead(property)
        let lower = property.lowercased()

        // Global properties (no target).
        if target == nil {
            switch lower {
            case "aimodel", "currentaimodel", "ollamamodel":
                return RuntimeAwareAIScriptingProvider(
                    baseProvider: context.aiProvider,
                    document: document
                ).currentModel()
            case "aimodels", "availableaimodels", "ollamamodels":
                return try await RuntimeAwareAIScriptingProvider(
                    baseProvider: context.aiProvider,
                    document: document
                ).availableModels().joined(separator: "\n")
            case "aiavailable":
                let status = await RuntimeAIStatusResolver.status(baseProvider: context.aiProvider, document: document)
                return String(status.availability.isAvailable)
            case "aiprovider":
                let status = await RuntimeAIStatusResolver.status(baseProvider: context.aiProvider, document: document)
                return status.providerName
            case "aistatus":
                let status = await RuntimeAIStatusResolver.status(baseProvider: context.aiProvider, document: document)
                return status.availability.message
            case "aicapabilities":
                let status = await RuntimeAIStatusResolver.status(baseProvider: context.aiProvider, document: document)
                return status.capabilities.map(\.rawValue).joined(separator: "\n")
            case "activatelistener", "speechlistener", "listeneractive":
                return (await context.runtimeProvider?.isSpeechListenerActive()) == true ? "true" : "false"
            case "userlevel", "user level", "user_level":
                return String(document.stack.userLevel)
            case "date":
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: Date())
            case "shortdate", "short date":
                return formatHyperCardDate(Date(), formatKeyword: "short date")
            case "abbrevdate", "abbrev date", "abbreviateddate", "abbreviated date", "abbrdate", "abbr date":
                return formatHyperCardDate(Date(), formatKeyword: "abbrev date")
            case "longdate", "long date":
                return formatHyperCardDate(Date(), formatKeyword: "long date")
            case "time", "shorttime", "short time", "abbrevtime", "abbrev time",
                 "abbreviatedtime", "abbreviated time", "abbrtime", "abbr time":
                return formatHyperCardTime(style: .short)
            case "longtime", "long time":
                return formatHyperCardTime(style: .long)
            case "englishtime", "english time":
                return formatHyperCardTime(style: .english)
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
                return env.itemDelimiter
            case "numberformat":
                return "0.######"
            case "lockscreen":
                return "false"
            case "editbkgnd":
                return "false"
            case "sound":
                return await context.systemProvider.currentSoundName()
            case "musicstate":
                return await context.systemProvider.currentMusicState()
            case "applemusicstate":
                return await context.systemProvider.currentAppleMusicState(engine: .application)
            case "applemusicposition", "applemusictime":
                return formatNumber(await context.systemProvider.currentAppleMusicPosition(engine: .application))
            case "applemusicauthorization", "applemusicstatus":
                return await context.systemProvider.appleMusicAuthorizationStatus().rawValue
            case "applemusiccapabilities":
                let caps = await context.systemProvider.appleMusicCapabilities()
                return [
                    "authorization=\(caps.authorization.rawValue)",
                    "canPlayCatalogContent=\(caps.canPlayCatalogContent)",
                    "canBecomeSubscriber=\(caps.canBecomeSubscriber)",
                    "hasCloudLibraryEnabled=\(caps.hasCloudLibraryEnabled)",
                    "supportsLibraryMutation=\(caps.supportsLibraryMutation)"
                ].joined(separator: "\n")
            case "musicpatterns":
                return document.musicLibrary.patterns.map(\.name).joined(separator: "\n")
            case "musicinstruments":
                return MusicInstrumentCatalog.displayList
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
            // Message box container: accessible as `the message`, `msg`, `message box`.
            case "message", "msg", "messagebox", "message box":
                return env.globals[Self.messageBoxKey] ?? ""
            // `the target` — descriptor of the original dispatch recipient.
            case "target",
                 "short target", "shorttarget",
                 "abbrev target", "abbreviated target", "abbrevtarget", "abbreviatedtarget":
                return descriptorForObject(id: context.originalTargetId, document: document,
                                           context: context, form: .short)
            case "long target", "longtarget":
                return descriptorForObject(id: context.originalTargetId, document: document,
                                           context: context, form: .long)
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
            case "recentcards", "recent cards":
                return await context.runtimeProvider?.recentCards() ?? ""

            // Phase 2: click-info properties
            case "clickh":
                return formatNumber(await context.runtimeProvider?.clickState()?.clickH ?? 0)
            case "clickv":
                return formatNumber(await context.runtimeProvider?.clickState()?.clickV ?? 0)
            case "clickloc":
                if let cs = await context.runtimeProvider?.clickState() {
                    return "\(formatNumber(cs.clickH)),\(formatNumber(cs.clickV))"
                }
                return "0,0"
            case "clicktext":
                return await context.runtimeProvider?.clickState()?.clickText ?? ""
            case "clickchunk":
                return await context.runtimeProvider?.clickState()?.clickChunk ?? ""
            case "clickline":
                return await context.runtimeProvider?.clickState()?.clickLine ?? ""

            // Phase 2: found-text properties
            case "foundtext":
                return await context.runtimeProvider?.foundState()?.foundText ?? ""
            case "foundchunk":
                return await context.runtimeProvider?.foundState()?.foundChunk ?? ""
            case "foundfield":
                return await context.runtimeProvider?.foundState()?.foundField ?? ""
            case "foundline":
                return await context.runtimeProvider?.foundState()?.foundLine ?? ""

            // Phase 2: selected-text properties
            case "selectedtext":
                return await context.runtimeProvider?.selectedState()?.selectedText ?? ""
            case "selectedchunk":
                return await context.runtimeProvider?.selectedState()?.selectedChunk ?? ""
            case "selectedfield":
                return await context.runtimeProvider?.selectedState()?.selectedField ?? ""
            case "selectedline":
                return await context.runtimeProvider?.selectedState()?.selectedLine ?? ""
            case "selectedbutton", "selectedloc":
                return ""

            // Phase 2: menus and destination
            case "menus":
                let titles = await context.hostProvider.menuTitles()
                return titles.joined(separator: "\n")
            case "destination":
                return document.stack.name

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
            return String(countChunks(chunkType, in: value, itemDelimiter: env.itemDelimiter))
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

        if case .scopedObjectRef(let object, let owner) = targetExpr,
           let idx = try await findScopedPartIndex(
               object: object,
               owner: owner,
               env: &env,
               document: document,
               context: context
           ) {
            return partPropertyValue(document.parts[idx], property: property, document: document, context: context)
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
            case "name", "shortname", "short name", "abbrevname", "abbrev name",
                 "abbreviatedname", "abbreviated name", "abbrname", "abbr name",
                 "longname", "long name":
                return document.stack.name
            case "defaultfont", "default_font", "textfont", "font":
                return document.stack.defaultFont
            case "width":       return String(document.stack.width)
            case "height":      return String(document.stack.height)
            case "script":      return document.stack.script
            case "webassetsallowed", "web_assets_allowed":
                return String(document.stack.webAssetsAllowed)
            case "aicontextcount", "ai_context_count", "contextcount", "context_count":
                return String(document.aiContextLibrary.itemCount)
            case "aicontextsummary", "ai_context_summary", "contextsummary", "context_summary":
                return document.aiContextLibrary.promptSummary(maxItems: 20)
            case "aicontextcloudsharingallowed", "ai_context_cloud_sharing_allowed", "contextcloudsharingallowed":
                return String(document.stack.aiContextCloudSharingAllowed)
            case "runtimemode", "runtime_mode", "runtimemodeenabled", "runtime_mode_enabled":
                return String(document.stack.runtimeModeEnabled)
            case "userlevel", "user level", "user_level":
                return String(document.stack.userLevel)
            case "runtimeaiproviderpolicy", "runtime_ai_provider_policy", "aiproviderpolicy":
                return document.stack.runtimeAISettings.providerPolicy.rawValue
            case "runtimeaitoolsallowed", "runtime_ai_tools_allowed":
                return String(document.stack.runtimeAISettings.allowRuntimeSideEffectTools)
            case "runtimeaiallowedtools", "runtime_ai_allowed_tools":
                return document.stack.runtimeAISettings.allowedToolNames.joined(separator: ",")
            case "runtimeaipersisttranscript", "runtime_ai_persist_transcript":
                return String(document.stack.runtimeAISettings.persistTranscript)
            case "targetplatforms", "target_platforms":
                return document.stack.deploymentTargets.selectedPlatforms.map(\.rawValue).joined(separator: ",")
            case "primarytargetplatform", "primary_target_platform":
                return document.stack.deploymentTargets.primaryPlatform.rawValue
            case "layoutpolicy", "targetlayoutpolicy", "target_layout_policy":
                return document.stack.deploymentTargets.layoutPolicy.rawValue
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

        if case .objectRef(let ref) = targetExpr, ref.objectType == "window" {
            let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            return hyperCardWindowPropertyValue(
                windowName: ident,
                property: property,
                env: env,
                document: document,
                currentCardId: context.currentCardId
            )
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
            case "short name", "shortname",
                 "abbrev name", "abbreviated name",
                 "abbrevname", "abbreviatedname":
                return card?.name ?? ""
            case "long name", "longname":
                if let card = card {
                    return "card \"\(card.name)\""
                }
                return ""
            case "id":
                return card?.id.uuidString ?? ""
            case "shortid", "short id", "longid", "long id":
                guard let card else { return "" }
                if let legacyCardId = legacyCardId(for: card, document: document) {
                    return String(legacyCardId)
                }
                return card.id.uuidString
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
            if let idx = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
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
        case "short name", "shortname",
             "abbrev name", "abbreviated name",
             "abbrevname", "abbreviatedname":
            return part.name
        case "long name", "longname":
            // Full path: "card button "X" of card "Y""
            return descriptorForObject(id: part.id, document: document, context: context, form: .long)
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
        case "textsize": return formatNumber(part.textSize)
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
        case "selectedtime", "selected_time":   return part.selectedTime
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
        case "duration":
            if part.partType == .video {
                return formatNumber(part.videoDuration)
            } else if part.partType == .appleMusicBrowser {
                return formatNumber(part.musicDuration)
            } else {
                return formatNumber(part.audioDuration)
            }
        case "outputpath", "output_path", "filepath", "file_path": return part.audioOutputPath
        case "format":              return part.audioFormat
        case "saveinstack", "save_in_stack", "embedinstack", "embed_in_stack", "embedded", "audioembedded":
            return part.audioEmbedInStack ? "true" : "false"
        case "audiosize", "audio_size", "audiodatasize", "audio_data_size":
            return String(part.audioData?.count ?? 0)
        // AudioKit music controls
        case "musicpattern", "music_pattern", "patternname", "pattern_name":
            return part.musicPatternName
        case "musicinstrument", "music_instrument", "instrument":
            return part.musicInstrumentName
        case "musictempo", "music_tempo", "tempo", "bpm":
            return formatNumber(Double(part.musicTempo))
        case "musickeycount", "music_key_count", "keycount", "key_count", "keys", "keyboardkeys", "keyboard_keys":
            return String(MusicKeyboardKeyCount.normalize(part.musicKeyCount))
        case "showcontroltype", "show_control_type", "showtype", "show_type":
            return part.musicShowControlType ? "true" : "false"
        case "showmusicpattern", "show_music_pattern", "showpattern", "show_pattern":
            return part.musicShowPattern ? "true" : "false"
        case "showmusicinstrument", "show_music_instrument", "showinstrument", "show_instrument", "showinstrumentpopup", "show_instrument_popup":
            return part.musicShowInstrument ? "true" : "false"
        case "showmusictempo", "show_music_tempo", "showtempo", "show_tempo":
            return part.musicShowTempo ? "true" : "false"
        case "musicloop", "music_loop", "loop", "looping":
            return part.musicLoop ? "true" : "false"
        case "musicvolume", "music_volume", "volume":
            return formatNumber(part.musicVolume)
        case "musictracks", "music_tracks", "trackdata", "track_data":
            return part.musicTrackData
        case "musicsource", "music_source":
            return part.musicSourceKind == MusicSourceKind.hypePattern.rawValue
                ? part.musicPatternName
                : [part.musicSourceKind, part.musicSourceType, part.musicSourceID].joined(separator: ":")
        case "musicsourcekind", "music_source_kind", "sourcekind", "source_kind":
            return part.musicSourceKind
        case "applemusicid", "apple_music_id", "musicid", "music_id":
            return part.musicSourceID
        case "applemusictype", "apple_music_type", "musictype", "music_type":
            return part.musicSourceType
        case "applemusictitle", "apple_music_title", "musictitle", "music_title":
            return part.musicSourceTitle
        case "applemusicartist", "apple_music_artist", "musicartist", "music_artist":
            return part.musicSourceArtist
        case "applemusicalbum", "apple_music_album", "musicalbum", "music_album":
            return part.musicSourceAlbum
        case "artwork", "artworkurl", "artwork_url", "musicartwork", "music_artwork":
            return part.musicArtworkURL
        case "musicposition", "music_position", "positionseconds", "position_seconds":
            return formatNumber(part.musicPosition)
        case "musicduration", "music_duration", "durationseconds", "duration_seconds":
            if part.partType == .appleMusicBrowser || !part.musicSourceID.isEmpty {
                return formatNumber(part.musicDuration)
            }
            return formatNumber(part.audioDuration)
        case "musicqueue", "music_queue", "queuedata", "queue_data":
            return part.musicQueueData
        case "musicsearchterm", "music_search_term", "searchterm", "search_term":
            return part.musicSearchTerm
        case "musicsearchscope", "music_search_scope", "searchscope", "search_scope":
            return part.musicSearchScope
        // Scene3D
        case "imagefilter", "image_filter", "filter": return part.imageFilter
        case "imagefilterintensity", "image_filter_intensity", "filterintensity", "filter_intensity": return formatNumber(part.imageFilterIntensity)
        case "object":
            return Scene3DModelBindingResolver.displayModel(for: part)
        case "model":
            return Scene3DModelBindingResolver.displayModel(for: part)
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
        case "currenttime", "current_time":
            return formatNumber(part.videoCurrentTime)
        case "playrate", "play_rate", "rate":
            return formatNumber(part.videoPlayRate)
        case "popupitems", "popup_items":
            return part.popupItems
        case "htmlcontent", "html_content":
            return part.htmlContent
        // SpriteArea-specific properties (read from SpriteAreaSpec JSON)
        case "scalemode", "scale_mode":
            if let partIndex = document.parts.firstIndex(where: { $0.id == part.id }),
               let spec = spriteAreaSpec(partIndex: partIndex, document: document) {
                return spec.scaleMode.rawValue
            }
            return ""
        case "showsphysics", "shows_physics":
            if let partIndex = document.parts.firstIndex(where: { $0.id == part.id }),
               let spec = spriteAreaSpec(partIndex: partIndex, document: document) {
                return spec.showsPhysics ? "true" : "false"
            }
            return "false"
        case "showsfps", "shows_fps":
            if let partIndex = document.parts.firstIndex(where: { $0.id == part.id }),
               let spec = spriteAreaSpec(partIndex: partIndex, document: document) {
                return spec.showsFPS ? "true" : "false"
            }
            return "false"
        case "showsnodecount", "shows_node_count":
            if let partIndex = document.parts.firstIndex(where: { $0.id == part.id }),
               let spec = spriteAreaSpec(partIndex: partIndex, document: document) {
                return spec.showsNodeCount ? "true" : "false"
            }
            return "false"
        case "scenename", "scene_name", "activescene", "active_scene":
            if let partIndex = document.parts.firstIndex(where: { $0.id == part.id }),
               let spec = spriteAreaSpec(partIndex: partIndex, document: document) {
                return spec.activeScene?.name ?? ""
            }
            return ""
        case "scenecount", "scene_count":
            if let partIndex = document.parts.firstIndex(where: { $0.id == part.id }),
               let spec = spriteAreaSpec(partIndex: partIndex, document: document) {
                return String(spec.scenes.count)
            }
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
            return clampedInt(toNumber(str))
        }

        // MARK: Fast path — allocation-free single-index scan
        //
        // For the dominant case of `.single` with a positive 1-based index we
        // scan for the Nth boundary without materialising the full parts array.
        // Sentinels last(-1)/middle(0)/any(-2) and range accesses fall through
        // to the full-split path below where we need the element count.
        if case .single(let indexExpr) = range {
            let idx = await indexValue(indexExpr)

            switch idx {
            case 1...:
                // Positive 1-based index: fast scan.
                switch chunkType {
                case .char, .character:
                    // Characters are Unicode scalars; index directly.
                    let charIdx = source.index(source.startIndex, offsetBy: idx - 1, limitedBy: source.endIndex)
                    guard let ci = charIdx, ci < source.endIndex else { return "" }
                    return String(source[ci])

                case .word:
                    // Scan for the Nth whitespace-delimited word without splitting.
                    var wordCount = 0
                    var i = source.startIndex
                    while i < source.endIndex {
                        // Skip leading whitespace.
                        while i < source.endIndex && source[i].isWhitespace { source.formIndex(after: &i) }
                        guard i < source.endIndex else { break }
                        // Mark start of word.
                        let wordStart = i
                        wordCount += 1
                        // Advance to end of word.
                        while i < source.endIndex && !source[i].isWhitespace { source.formIndex(after: &i) }
                        if wordCount == idx { return String(source[wordStart..<i]) }
                    }
                    return ""

                case .item:
                    // Scan for the Nth delimiter-separated item, trimming whitespace.
                    let delimChar = env.itemDelimiter.first ?? ","
                    var itemCount = 0
                    var i = source.startIndex
                    var itemStart = i
                    while true {
                        let atEnd = (i == source.endIndex)
                        if atEnd || source[i] == delimChar {
                            itemCount += 1
                            if itemCount == idx {
                                return source[itemStart..<i]
                                    .trimmingCharacters(in: .whitespaces)
                            }
                            if atEnd { break }
                            source.formIndex(after: &i)
                            itemStart = i
                        } else {
                            source.formIndex(after: &i)
                        }
                    }
                    return ""

                case .line:
                    // Scan lines delimited by \r\n, \r, or \n.
                    var lineCount = 0
                    var i = source.startIndex
                    var lineStart = i
                    while i < source.endIndex {
                        let ch = source[i]
                        if ch == "\r" || ch == "\n" {
                            lineCount += 1
                            if lineCount == idx { return String(source[lineStart..<i]) }
                            // Consume \r\n as a single separator.
                            source.formIndex(after: &i)
                            if ch == "\r", i < source.endIndex, source[i] == "\n" {
                                source.formIndex(after: &i)
                            }
                            lineStart = i
                        } else {
                            source.formIndex(after: &i)
                        }
                    }
                    // Last line (no trailing newline).
                    lineCount += 1
                    if lineCount == idx { return String(source[lineStart...]) }
                    return ""
                }

            default:
                // Sentinels: last(-1), middle(0), any(-2).
                // These require knowing the total count, so fall through to
                // the full-split path below.
                break
            }
        }

        // MARK: Full-split path — used for sentinels, range access, and line ranges.
        //
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
            // Honor the runtime itemDelimiter (default ","). Per the HyperTalk Reference,
            // coordinate/rect/loc structures use hardcoded "," and are not affected here —
            // only explicit item-chunk expressions go through evaluateChunk.
            let delim = env.itemDelimiter
            if delim == "," {
                parts = source.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                let delimChar = delim.first ?? ","
                parts = source.split(separator: delimChar, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
        case .line:
            parts = splitLines(source)
        }

        func indexValueFull(_ expr: Expression) async -> Int {
            // Re-evaluate — only reached from the full-split path.
            let str = (try? await evaluate(expr, env: &env, document: document, context: context)) ?? ""
            return clampedInt(toNumber(str))
        }

        switch range {
        case .single(let indexExpr):
            let idx = await indexValueFull(indexExpr)
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
            let from = max(1, await indexValueFull(fromExpr))
            let to = min(parts.count, await indexValueFull(toExpr))
            guard from <= to, from >= 1 else { return "" }
            let separator: String
            switch chunkType {
            case .word: separator = " "
            case .char, .character: separator = ""
            case .item: separator = env.itemDelimiter
            case .line: separator = "\n"
            }
            return parts[(from - 1)..<to].joined(separator: separator)
        }
    }

    // MARK: - Chunk write

    /// Write `value` into a chunk-addressed container.
    ///
    /// Mirrors `evaluateChunk` addressing (sentinels, clamping, no-ops) through
    /// `ChunkWriter`, then writes the mutated container back via the appropriate
    /// setter.  Nested chunk paths (e.g. `put "Z" into char 2 of word 3 of v`)
    /// recurse depth-first: the outermost call handles the innermost container,
    /// applying inner levels always `.into` so intermediate containers are not
    /// double-modified.
    ///
    /// - Note: `env.it` is touched **only** when the target expression is `.it`.
    ///   All other container writes go through `env.setVariable` or
    ///   `document.parts[idx].textContent`.
    private func performChunkPut(
        chunkType: ChunkType,
        range: ChunkRange,
        source: Expression,
        preposition: Preposition,
        value: Value,
        env: inout Environment,
        document: inout HypeDocument,
        context: ExecutionContext,
        handler: Handler
    ) async throws {
        // Step 1: Resolve the chunk-range expressions to concrete Int sentinels,
        // mirroring the indexValue helper inside evaluateChunk.
        func indexInt(_ expr: Expression) async -> Int {
            let str = (try? await evaluate(expr, env: &env, document: document, context: context)) ?? ""
            return clampedInt(toNumber(str))
        }

        let resolvedIndices: ChunkWriter.ResolvedIndices
        switch range {
        case .single(let idxExpr):
            let idx = await indexInt(idxExpr)
            resolvedIndices = .single(idx)
        case .range(let fromExpr, let toExpr):
            let from = await indexInt(fromExpr)
            let to   = await indexInt(toExpr)
            // Clamp range sentinels so ChunkWriter gets valid lo/hi or returns nil.
            // We pass the raw sentinel values and let ChunkWriter resolve them;
            // but we need a concrete range struct — use .range(from, to) resolved
            // by ChunkWriter.resolveRange against the actual container parts count.
            resolvedIndices = .range(from, to)
        }

        // Step 2: Dispatch based on the source container kind.
        switch source {

        case .chunk(let innerType, let innerRange, let innerSource):
            // Nested chunk (e.g. `put "Z" into char 2 of word 3 of v`):
            //   chunkType/range addresses the OUTER level (char 2).
            //   innerType/innerRange/innerSource is the inner container (word 3 of v).
            //
            // Algorithm:
            //   1. Read the current value of the inner chunk (word 3 of v).
            //   2. Apply the outer-level mutation (char 2 of that ← "Z").
            //   3. Recurse: write the result back as the new value of (word 3 of v), using .into.
            let innerSourceValue = (try? await evaluate(innerSource, env: &env, document: document, context: context)) ?? ""
            let innerOld = await evaluateChunk(innerType, range: innerRange, source: innerSourceValue, env: &env, document: document, context: context)
            let innerNew = ChunkWriter.apply(
                chunkType: chunkType,
                indices: resolvedIndices,
                preposition: preposition,
                container: innerOld,
                value: value,
                itemDelimiter: env.itemDelimiter
            )
            // Recurse: write innerNew into the inner container, always using .into.
            try await performChunkPut(
                chunkType: innerType,
                range: innerRange,
                source: innerSource,
                preposition: .into,
                value: innerNew,
                env: &env,
                document: &document,
                context: context,
                handler: handler
            )

        case .variable(let name):
            let old = env.getVariable(name)
            let new = ChunkWriter.apply(
                chunkType: chunkType,
                indices: resolvedIndices,
                preposition: preposition,
                container: old,
                value: value,
                itemDelimiter: env.itemDelimiter
            )
            env.setVariable(name, new)

        case .it:
            // The only allowed env.it write in this function.
            let new = ChunkWriter.apply(
                chunkType: chunkType,
                indices: resolvedIndices,
                preposition: preposition,
                container: env.it,
                value: value,
                itemDelimiter: env.itemDelimiter
            )
            env.it = new

        case .objectRef(let ref):
            let ident = try await evaluate(ref.identifier, env: &env, document: document, context: context)
            if let partIndex = findPartIndex(ref.objectType, identifier: ident, env: &env, document: document, currentCardId: context.currentCardId) {
                let old = document.parts[partIndex].textContent
                let new = ChunkWriter.apply(
                    chunkType: chunkType,
                    indices: resolvedIndices,
                    preposition: preposition,
                    container: old,
                    value: value,
                    itemDelimiter: env.itemDelimiter
                )
                document.parts[partIndex].textContent = new
            } else {
                throw ScriptError(
                    message: "Can't put into a chunk of that container",
                    line: handler.line,
                    handler: handler.name
                )
            }

        case .scopedObjectRef(let object, let owner):
            if let partIndex = try await findScopedPartIndex(
                object: object,
                owner: owner,
                env: &env,
                document: document,
                context: context
            ) {
                let old = document.parts[partIndex].textContent
                let new = ChunkWriter.apply(
                    chunkType: chunkType,
                    indices: resolvedIndices,
                    preposition: preposition,
                    container: old,
                    value: value,
                    itemDelimiter: env.itemDelimiter
                )
                document.parts[partIndex].textContent = new
            } else {
                throw ScriptError(
                    message: "Can't put into a chunk of that container",
                    line: handler.line,
                    handler: handler.name
                )
            }

        default:
            // Unwritable expression kind (literals, function calls, property reads, etc.)
            throw ScriptError(
                message: "Can't put into a chunk of that container",
                line: handler.line,
                handler: handler.name
            )
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

    private func countChunks(_ chunkType: ChunkType, in source: Value, itemDelimiter: String = ",") -> Int {
        switch chunkType {
        case .word:
            return source.split(separator: " ", omittingEmptySubsequences: true).count
        case .char, .character:
            return source.count
        case .item:
            let delimChar = itemDelimiter.first ?? ","
            return source.split(separator: delimChar, omittingEmptySubsequences: false).count
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

    // MARK: - Phase 2: find / select helpers

    /// Search for `searchTerm` using the given `mode` in all field parts
    /// across the document's cards.  The search starts from `startingCardId` and
    /// wraps around — HyperCard's default behaviour.
    ///
    /// - Parameters:
    ///   - mode: `normal` (word-prefix), `word` (whole-word), `whole` (phrase), `string`/`chars` (substring).
    ///   - inFieldName: When set, restrict search to the named field only.
    ///
    /// Returns a fully-populated `FoundState` on the first hit, or `nil` when the
    /// term does not appear in any field.
    private func findTextInDocument(
        _ searchTerm: String,
        mode: FindMode = .normal,
        document: HypeDocument,
        startingCardId: UUID,
        inFieldName: String? = nil
    ) -> FoundState? {
        guard !searchTerm.isEmpty else { return nil }
        let lowerTerm = searchTerm.lowercased()

        let sortedCards = document.sortedCards
        guard !sortedCards.isEmpty else { return nil }

        let startIndex = sortedCards.firstIndex(where: { $0.id == startingCardId }) ?? 0
        let orderedCards = Array(sortedCards[startIndex...]) + Array(sortedCards[..<startIndex])

        for card in orderedCards {
            let cardFields = document.partsForCard(card.id).filter { $0.partType == .field }
            let bgFields   = document.partsForBackground(card.backgroundId).filter { $0.partType == .field }
            var fields     = cardFields + bgFields

            if let fieldName = inFieldName {
                fields = fields.filter { $0.name.lowercased() == fieldName.lowercased() }
            }

            for field in fields {
                let text = field.textContent
                let lowerText = text.lowercased()
                guard let range = findMatch(in: lowerText, term: lowerTerm, mode: mode) else { continue }

                let charStart = lowerText.distance(from: lowerText.startIndex, to: range.lowerBound) + 1
                let charEnd   = charStart + lowerText.distance(from: range.lowerBound, to: range.upperBound) - 1

                let fieldDescriptor = "field \"\(field.name)\""
                let foundChunk      = "char \(charStart) to \(charEnd) of \(fieldDescriptor)"
                let prefix      = String(text[..<text.index(text.startIndex, offsetBy: charStart - 1)])
                let lineNumber  = prefix.components(separatedBy: "\n").count
                let foundLine   = "line \(lineNumber) of \(fieldDescriptor)"

                let originalStart = text.index(text.startIndex, offsetBy: charStart - 1)
                let matchLen = min(charEnd - charStart + 1, text.count - (charStart - 1))
                let originalEnd   = text.index(originalStart, offsetBy: matchLen)
                let foundText     = String(text[originalStart..<originalEnd])

                return FoundState(
                    foundText: foundText,
                    foundChunk: foundChunk,
                    foundField: fieldDescriptor,
                    foundLine: foundLine,
                    cardId: card.id
                )
            }
        }
        return nil
    }

    /// Return the range of the first match of `term` in `text` according to `mode`.
    private func findMatch(in text: String, term: String, mode: FindMode) -> Range<String.Index>? {
        guard !term.isEmpty else { return nil }
        switch mode {
        case .string, .chars:
            // Substring match (any occurrence).
            return text.range(of: term)
        case .whole:
            // Whole-phrase match — term must appear as a complete phrase.
            // We match with word-boundary awareness: preceded/followed by non-word or string edge.
            return text.range(of: term)   // simple substring for now; phrase = substring
        case .word:
            // Whole-word match: term must be surrounded by non-word chars or string edges.
            var searchStart = text.startIndex
            while searchStart < text.endIndex {
                guard let range = text.range(of: term, range: searchStart..<text.endIndex) else { break }
                let beforeOk = range.lowerBound == text.startIndex ||
                    !text[text.index(before: range.lowerBound)].isLetter &&
                    !text[text.index(before: range.lowerBound)].isNumber
                let afterOk = range.upperBound == text.endIndex ||
                    !text[range.upperBound].isLetter &&
                    !text[range.upperBound].isNumber
                if beforeOk && afterOk { return range }
                searchStart = text.index(after: range.lowerBound)
            }
            return nil
        case .normal:
            // Word-prefix: term matches at the start of any word.
            var searchStart = text.startIndex
            while searchStart < text.endIndex {
                guard let range = text.range(of: term, range: searchStart..<text.endIndex) else { break }
                let beforeOk = range.lowerBound == text.startIndex ||
                    !text[text.index(before: range.lowerBound)].isLetter &&
                    !text[text.index(before: range.lowerBound)].isNumber
                if beforeOk { return range }
                searchStart = text.index(after: range.lowerBound)
            }
            return nil
        }
    }

    /// Build a `SelectedState` from a `select <expr>` AST expression.
    ///
    /// Handles two forms:
    ///   1. `select field "Name"` — selects the entire text of the named field.
    ///   2. `select chunk of field "Name"` — selects a specific chunk (via `.chunk`
    ///      wrapping an `.objectRef`).
    ///
    /// Returns `nil` when the expression cannot be resolved (unknown field, etc.).
    private func resolveSelectExpression(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async -> SelectedState? {
        switch expr {

        case .objectRef(let ref)
            where ref.objectType.lowercased() == "field" || ref.objectType.lowercased() == "fld":
            // `select field "Name"` — select the whole field.
            let ident = try? await evaluate(ref.identifier, env: &env, document: document, context: context)
            guard let ident,
                  let idx = findPartIndex(ref.objectType, identifier: ident, env: &env,
                                          document: document, currentCardId: context.currentCardId)
            else { return nil }
            let field = document.parts[idx]
            let text  = field.textContent
            let fieldDesc = "field \"\(field.name)\""
            let lineCount = text.isEmpty ? 1 : text.components(separatedBy: "\n").count
            return SelectedState(
                selectedText:  text,
                selectedChunk: text.isEmpty ? "char 0 of \(fieldDesc)"
                                            : "char 1 to \(text.count) of \(fieldDesc)",
                selectedField: fieldDesc,
                selectedLine:  "line 1 to \(lineCount) of \(fieldDesc)"
            )

        case .chunk(let chunkType, let range, let source):
            // `select char 3 to 7 of field "Notes"` — evaluate chunk source to get
            // the field text, then compute the selected substring.
            guard case .objectRef(let ref) = source,
                  ref.objectType.lowercased() == "field" || ref.objectType.lowercased() == "fld"
            else {
                // Non-field chunk: evaluate and store generic selected text only.
                let text = await evaluateChunk(chunkType, range: range, source: "",
                                              env: &env, document: document, context: context)
                return SelectedState(selectedText: text, selectedChunk: "", selectedField: "", selectedLine: "")
            }

            let ident = try? await evaluate(ref.identifier, env: &env, document: document, context: context)
            guard let ident,
                  let idx = findPartIndex(ref.objectType, identifier: ident, env: &env,
                                          document: document, currentCardId: context.currentCardId)
            else { return nil }
            let field     = document.parts[idx]
            let fieldDesc = "field \"\(field.name)\""
            let sourceVal = field.textContent
            let selectedText = await evaluateChunk(chunkType, range: range, source: sourceVal,
                                                    env: &env, document: document, context: context)

            // Build a char-range chunk descriptor for selectedChunk.
            let lowerSource = sourceVal.lowercased()
            let lowerSel    = selectedText.lowercased()
            let selectedChunk: String
            let selectedLine: String
            if let matchRange = lowerSource.range(of: lowerSel), !selectedText.isEmpty {
                let charStart = lowerSource.distance(from: lowerSource.startIndex, to: matchRange.lowerBound) + 1
                let charEnd   = charStart + selectedText.count - 1
                selectedChunk = "char \(charStart) to \(charEnd) of \(fieldDesc)"
                let prefix    = String(sourceVal[..<sourceVal.index(sourceVal.startIndex, offsetBy: charStart - 1)])
                let lineNum   = prefix.components(separatedBy: "\n").count
                selectedLine  = "line \(lineNum) of \(fieldDesc)"
            } else {
                selectedChunk = "char 0 of \(fieldDesc)"
                selectedLine  = "line 1 of \(fieldDesc)"
            }

            return SelectedState(
                selectedText:  selectedText,
                selectedChunk: selectedChunk,
                selectedField: fieldDesc,
                selectedLine:  selectedLine
            )

        default:
            // Unrecognised expression form — evaluate as text only.
            let text = (try? await evaluate(expr, env: &env, document: document, context: context)) ?? ""
            return SelectedState(selectedText: text, selectedChunk: "", selectedField: "", selectedLine: "")
        }
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
        if let legacyCardId = legacyCardId(fromNavigationDestination: trimmed),
           let cardId = resolveLocalLegacyCardId(legacyCardId, document: document) {
            return document.cards.firstIndex(where: { $0.id == cardId })
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
        case "musicplayer", "music":
            if let part = document.parts.first(where: { $0.partType == .musicPlayer && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "pianokeyboard", "keyboard":
            if let part = document.parts.first(where: { $0.partType == .pianoKeyboard && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "stepsequencer", "sequencer":
            if let part = document.parts.first(where: { $0.partType == .stepSequencer && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "musicmixer", "mixer":
            if let part = document.parts.first(where: { $0.partType == .musicMixer && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "applemusicbrowser", "musicbrowser":
            if let part = document.parts.first(where: { $0.partType == .appleMusicBrowser && $0.name.lowercased() == identifier.lowercased() }) {
                return part.id.uuidString
            }
        case "musicqueue":
            if let part = document.parts.first(where: { $0.partType == .musicQueue && $0.name.lowercased() == identifier.lowercased() }) {
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
        case "sprite", "label", "shape", "emitter", "audio", "tilemap", "camera", "crop", "effect", "light", "group":
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
        _ target: Expression?,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> UUID? {
        guard let target else {
            return context.targetId
        }
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

    private func evaluateNavigationExpression(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
        let value = try await evaluate(expr, env: &env, document: document, context: context)
        if value.isEmpty, case .variable(let name) = expr {
            return name
        }
        return value
    }

    private func evaluateObjectRefIdentifier(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
        let value = try await evaluate(expr, env: &env, document: document, context: context)
        if value.isEmpty, case .variable(let name) = expr {
            return name
        }
        return value
    }

    private func evaluateSendMessageExpression(
        _ expr: Expression,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Value {
        let value = try await evaluate(expr, env: &env, document: document, context: context)
        if value.isEmpty, case .variable(let name) = expr {
            return name
        }
        return value
    }

    // MARK: - Navigation resolution

    private func resolveNavigation(_ dest: String, document: HypeDocument, currentCardId: UUID) -> UUID? {
        let trimmed = dest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        switch lower {
        case "next":
            return CardNavigator.navigate(direction: .next, currentCardId: currentCardId, document: document)
        case "next marked card":
            return navigateToNextMarkedCard(currentCardId: currentCardId, document: document)
        case "previous", "prev", "back":
            return CardNavigator.navigate(direction: .previous, currentCardId: currentCardId, document: document)
        case "first":
            return CardNavigator.navigate(direction: .first, currentCardId: currentCardId, document: document)
        case "last":
            return CardNavigator.navigate(direction: .last, currentCardId: currentCardId, document: document)
        case "card", "this", "this card", "current card":
            return currentCardId
        default:
            if let legacyCardId = legacyCardId(fromNavigationDestination: trimmed),
               let cardId = resolveLocalLegacyCardId(legacyCardId, document: document) {
                return cardId
            }
            // Try by card name.
            if let card = document.cards.first(where: { $0.name.lowercased() == lower }) {
                return card.id
            }
            return nil
        }
    }

    private func navigateToNextMarkedCard(currentCardId: UUID, document: HypeDocument) -> UUID? {
        let cards = document.sortedCards
        guard let currentIndex = cards.firstIndex(where: { $0.id == currentCardId }) else {
            return cards.first(where: \.marked)?.id
        }
        let laterCards = cards.dropFirst(currentIndex + 1)
        if let marked = laterCards.first(where: \.marked) {
            return marked.id
        }
        return cards.prefix(currentIndex + 1).first(where: \.marked)?.id
    }

    private func legacyCardId(fromNavigationDestination destination: String) -> Int? {
        let lower = destination.lowercased()
        for prefix in ["card id ", "id "] where lower.hasPrefix(prefix) {
            let rawId = destination.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(rawId)
        }
        return nil
    }

    private func resolveLocalLegacyCardId(_ legacyCardId: Int, document: HypeDocument) -> UUID? {
        guard let entry = currentStackLibraryEntry(in: document),
              let cardReference = entry.cardReferences.first(where: { $0.legacyCardId == legacyCardId }),
              let cardId = cardReference.hypeCardId,
              document.cards.contains(where: { $0.id == cardId }) else {
            return nil
        }
        return cardId
    }

    private func legacyCardId(for card: Card, document: HypeDocument) -> Int? {
        currentStackLibraryEntry(in: document)?.cardReferences.first {
            $0.hypeCardId == card.id
        }?.legacyCardId
    }

    private func currentStackLibraryEntry(in document: HypeDocument) -> HypeStackLibraryEntry? {
        switch document.stackLibrary.resolution(for: document.stack.name) {
        case .resolved(let entry):
            return entry
        case .ambiguous(_, let candidates):
            if let currentEntry = stackLibraryEntryContainingCurrentDocumentCards(candidates, document: document) {
                return currentEntry
            }
            let stackKey = HypeStackLibrary.lookupKey(document.stack.name)
            return document.stackLibrary.entries.first { $0.lookupKeys.contains(stackKey) }
        case .missing:
            return stackLibraryEntryContainingCurrentDocumentCards(document.stackLibrary.entries, document: document)
        }
    }

    private func stackLibraryEntryContainingCurrentDocumentCards(
        _ entries: [HypeStackLibraryEntry],
        document: HypeDocument
    ) -> HypeStackLibraryEntry? {
        let cardIds = Set(document.cards.map(\.id))
        return entries.first { entry in
            entry.cardReferences.contains { reference in
                reference.hypeCardId.map { cardIds.contains($0) } ?? false
            }
        }
    }

    private func implicitProjectNavigationTarget(
        cardValue: String,
        preferredStackName: String,
        document: HypeDocument
    ) -> ProjectNavigationTarget? {
        let trimmed = cardValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              legacyCardId(fromNavigationDestination: trimmed) == nil,
              UUID(uuidString: trimmed) == nil else {
            return nil
        }

        if let currentEntry = currentStackLibraryEntry(in: document),
           let card = resolveStackLibraryCardReference(trimmed, in: currentEntry) {
            return projectNavigationTarget(card: card, entry: currentEntry)
        }

        let preferredStackName = preferredStackName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferredStackName.isEmpty,
           let preferredEntry = exactOrUniqueStackLibraryEntry(preferredStackName, document: document),
           let card = resolveStackLibraryCardReference(trimmed, in: preferredEntry) {
            return projectNavigationTarget(card: card, entry: preferredEntry)
        }

        let matches = document.stackLibrary.entries.flatMap { entry in
            entry.cardReferences.compactMap { card -> (HypeStackLibraryEntry, HypeStackLibraryCardReference)? in
                HypeStackLibrary.lookupKey(card.name) == HypeStackLibrary.lookupKey(trimmed) ? (entry, card) : nil
            }
        }
        guard matches.count == 1, let match = matches.first else {
            return nil
        }
        return projectNavigationTarget(card: match.1, entry: match.0)
    }

    private func exactOrUniqueStackLibraryEntry(
        _ stackName: String,
        document: HypeDocument
    ) -> HypeStackLibraryEntry? {
        switch document.stackLibrary.resolution(for: stackName) {
        case .resolved(let entry):
            return entry
        case .ambiguous(_, let candidates):
            return exactStackNameMatch(stackName, in: candidates)
        case .missing:
            return nil
        }
    }

    private func resolveProjectNavigationTarget(
        cardValue: String,
        stackValue: String,
        document: HypeDocument,
        handler: Handler
    ) throws -> ProjectNavigationTarget {
        let stackName = stackValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry: HypeStackLibraryEntry
        switch document.stackLibrary.resolution(for: stackName) {
        case .resolved(let resolved):
            entry = resolved
        case .ambiguous(let alias, let candidates):
            if let exact = exactStackNameMatch(stackValue, in: candidates) {
                entry = exact
                break
            }
            let names = candidates.map(\.stackName).joined(separator: ", ")
            throw ScriptError(message: "Ambiguous stack name '\(alias)': \(names)", line: handler.line, handler: handler.name)
        case .missing(let alias):
            throw ScriptError(message: "Stack not found: \(alias)", line: handler.line, handler: handler.name)
        }

        guard let card = resolveStackLibraryCardReference(cardValue, in: entry) else {
            throw ScriptError(
                message: "Card not found in stack '\(entry.stackName)': \(cardValue)",
                line: handler.line,
                handler: handler.name
            )
        }
        return projectNavigationTarget(card: card, entry: entry)
    }

    private func projectNavigationTarget(
        card: HypeStackLibraryCardReference,
        entry: HypeStackLibraryEntry
    ) -> ProjectNavigationTarget {
        ProjectNavigationTarget(
            stackEntryId: entry.id,
            stackName: entry.stackName,
            stackAlias: entry.primaryAlias,
            packagePath: entry.packagePath,
            documentPath: entry.documentPath,
            legacyCardId: card.legacyCardId,
            cardName: card.name,
            sortIndex: card.sortIndex,
            hypeCardId: card.hypeCardId
        )
    }

    private func exactStackNameMatch(
        _ stackValue: String,
        in candidates: [HypeStackLibraryEntry]
    ) -> HypeStackLibraryEntry? {
        candidates.first { entry in entry.stackName == stackValue }
    }

    private func resolveStackLibraryCardReference(
        _ cardValue: String,
        in entry: HypeStackLibraryEntry
    ) -> HypeStackLibraryCardReference? {
        let trimmed = cardValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("id ") {
            let rawId = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            if let legacyId = Int(rawId) {
                return entry.cardReferences.first { $0.legacyCardId == legacyId }
            }
        }
        if let legacyId = Int(trimmed),
           let byIndex = entry.cardReferences.first(where: { ($0.sortIndex ?? -1) == legacyId - 1 }) {
            return byIndex
        }
        if let uuid = UUID(uuidString: trimmed),
           let byUUID = entry.cardReferences.first(where: { $0.hypeCardId == uuid }) {
            return byUUID
        }
        return entry.cardReferences.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower
        }
    }

    private func cardLogLabel(_ cardId: UUID, document: HypeDocument) -> String {
        guard let card = document.cards.first(where: { $0.id == cardId }) else {
            return "unknown card"
        }
        let trimmedName = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return "card \"\(trimmedName)\""
        }
        if let index = document.sortedCards.firstIndex(where: { $0.id == cardId }) {
            return "card \(index + 1)"
        }
        return "card"
    }

    private func cardActionTitle(_ cardId: UUID, document: HypeDocument) -> String {
        "Go to \(cardLogLabel(cardId, document: document))"
    }

    private func cardReferenceURL(stackId: UUID, cardId: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = "hype"
        components.host = "card"
        components.queryItems = [
            URLQueryItem(name: "stack", value: stackId.uuidString),
            URLQueryItem(name: "id", value: cardId.uuidString),
        ]
        return components.url
    }

    // MARK: - Helpers

    private func findPart(_ identifier: Value, document: HypeDocument) -> Part? {
        if let idx = findPartIndexGeneral(identifier, document: document) {
            return document.parts[idx]
        }
        return nil
    }

    private func findScopedPartIndex(
        object: ObjectRefExpr,
        owner: ObjectRefExpr,
        env: inout Environment,
        document: HypeDocument,
        context: ExecutionContext
    ) async throws -> Int? {
        let objectIdent = try await evaluateObjectRefIdentifier(object.identifier, env: &env, document: document, context: context)
        let parts: [Part]
        switch owner.objectType.lowercased() {
        case "card":
            let ownerIdent = try await evaluateObjectRefIdentifier(owner.identifier, env: &env, document: document, context: context)
            guard let cardIndex = cardIndex(forIdentifier: ownerIdent, document: document, currentCardId: context.currentCardId) else {
                return nil
            }
            parts = document.partsForCard(document.cards[cardIndex].id)
        case "background", "bg":
            let ownerIdent = try await evaluateObjectRefIdentifier(owner.identifier, env: &env, document: document, context: context)
            guard let backgroundIndex = backgroundIndex(forIdentifier: ownerIdent, document: document, currentCardId: context.currentCardId) else {
                return nil
            }
            parts = document.partsForBackground(document.backgrounds[backgroundIndex].id)
        default:
            return nil
        }
        let targetType: PartType?
        switch object.objectType.lowercased() {
        case "field", "fld": targetType = .field
        case "button", "btn": targetType = .button
        default: targetType = nil
        }
        let matched: Part?
        if let number = Int(objectIdent), number > 0 {
            let typed = parts.filter { targetType == nil || $0.partType == targetType }
            matched = number <= typed.count ? typed[number - 1] : nil
        } else {
            matched = parts.first {
                (targetType == nil || $0.partType == targetType) &&
                $0.name.lowercased() == objectIdent.lowercased()
            }
        }
        guard let matched else { return nil }
        return document.parts.firstIndex(where: { $0.id == matched.id })
    }

    /// Find a part's index by object type and identifier, scoped to the current card.
    private func findPartIndex(
        _ objectType: String,
        identifier: Value,
        env: inout Environment,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Int? {
        let normalizedType = objectType.lowercased()
        let normalizedIdentifier = identifier.lowercased()
        let cacheKey = PartLookupKey(
            objectType: normalizedType,
            identifier: normalizedIdentifier,
            currentCardId: currentCardId
        )
        if let cached = env.partLookupCache[cacheKey] {
            return cached
        }

        let targetType: PartType?
        switch normalizedType {
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
        case "musicplayer", "music": targetType = .musicPlayer
        case "pianokeyboard", "keyboard": targetType = .pianoKeyboard
        case "stepsequencer", "sequencer": targetType = .stepSequencer
        case "musicmixer", "mixer": targetType = .musicMixer
        case "applemusicbrowser", "musicbrowser": targetType = .appleMusicBrowser
        case "musicqueue": targetType = .musicQueue
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
        if let part = allParts.first(where: {
            (targetType == nil || $0.partType == targetType) &&
            $0.name.lowercased() == normalizedIdentifier
        }) {
            let index = document.parts.firstIndex(where: { $0.id == part.id })
            env.partLookupCache[cacheKey] = index
            return index
        }

        // Try by number (1-based)
        if let num = Int(identifier), num > 0 {
            let typed = allParts.filter { targetType == nil || $0.partType == targetType }
            if num <= typed.count {
                let part = typed[num - 1]
                let index = document.parts.firstIndex(where: { $0.id == part.id })
                env.partLookupCache[cacheKey] = index
                return index
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
            env: &env,
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
            env: &env,
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
            if loc.config.chartType == .spider { return series.color }
            // Resolve per-point color with fallback to series color,
            // matching the ChartHostView rendering logic.
            return point.color.isEmpty ? series.color : point.color
        case "rawcolor", "raw_color":
            if loc.config.chartType == .spider { return "" }
            return point.color
        case "value", "current", "currentvalue", "current_value":
            return formatNumber(point.value)
        case "min", "minimum", "minimumvalue", "minimum_value":
            return formatNumber(point.minimumValue)
        case "max", "maximum", "maximumvalue", "maximum_value":
            return formatNumber(point.maximumValue)
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
            env.invalidatePartLookupCache()
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
            document.parts[partIndex].family = clampedInt(toNumber(value))
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
        case "currenttime", "current_time":
            document.parts[partIndex].videoCurrentTime = max(0, toNumber(value))
        case "playrate", "play_rate", "rate":
            // SECURITY (review Finding 2): reject NaN/Inf and bound to AVPlayer's
            // practical rate range so an absurd script value can't poison the
            // player's playback engine. Negative (reverse) is intentionally allowed.
            let requestedRate = toNumber(value)
            document.parts[partIndex].videoPlayRate = requestedRate.isFinite ? max(-4.0, min(requestedRate, 4.0)) : 1.0
        // Calendar-specific writes — settable on .calendar parts.
        // Empty string clears the bound (NSDatePicker.minDate/maxDate accept nil).
        case "selecteddate", "selected_date":
            document.parts[partIndex].selectedDate = value
        case "selectedtime", "selected_time":
            document.parts[partIndex].selectedTime = value
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
            document.parts[partIndex].pdfCurrentPage = clampedInt(toNumber(value))
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
        case "saveinstack", "save_in_stack", "embedinstack", "embed_in_stack", "embedded", "audioembedded":
            document.parts[partIndex].audioEmbedInStack = isTruthy(value)
        // AudioKit music controls
        case "musicpattern", "music_pattern", "patternname", "pattern_name":
            document.parts[partIndex].musicPatternName = value
        case "musicinstrument", "music_instrument", "instrument":
            document.parts[partIndex].musicInstrumentName = MusicInstrumentCatalog.resolve(value).name
        case "musictempo", "music_tempo", "tempo", "bpm":
            document.parts[partIndex].musicTempo = Double(MusicTempo.clamp(toNumber(value)))
        case "musickeycount", "music_key_count", "keycount", "key_count", "keys", "keyboardkeys", "keyboard_keys":
            document.parts[partIndex].musicKeyCount = MusicKeyboardKeyCount.normalize(clampedInt(toNumber(value).rounded()))
        case "showcontroltype", "show_control_type", "showtype", "show_type":
            document.parts[partIndex].musicShowControlType = isTruthy(value)
        case "showmusicpattern", "show_music_pattern", "showpattern", "show_pattern":
            document.parts[partIndex].musicShowPattern = isTruthy(value)
        case "showmusicinstrument", "show_music_instrument", "showinstrument", "show_instrument", "showinstrumentpopup", "show_instrument_popup":
            document.parts[partIndex].musicShowInstrument = isTruthy(value)
        case "showmusictempo", "show_music_tempo", "showtempo", "show_tempo":
            document.parts[partIndex].musicShowTempo = isTruthy(value)
        case "musicloop", "music_loop", "loop", "looping":
            document.parts[partIndex].musicLoop = isTruthy(value)
        case "musicvolume", "music_volume", "volume":
            document.parts[partIndex].musicVolume = min(1, max(0, toNumber(value)))
        case "musictracks", "music_tracks", "trackdata", "track_data":
            document.parts[partIndex].musicTrackData = value
        case "musicsource", "music_source":
            if let ref = AppleMusicItemRef.decodeSource(value) {
                document.parts[partIndex].musicSourceKind = ref.source.rawValue
                document.parts[partIndex].musicSourceType = ref.kind.rawValue
                document.parts[partIndex].musicSourceID = ref.id
                document.parts[partIndex].musicSourceTitle = ref.titleSnapshot
                document.parts[partIndex].musicSourceArtist = ref.artistSnapshot
                document.parts[partIndex].musicSourceAlbum = ref.albumSnapshot
                document.parts[partIndex].musicArtworkURL = ref.artworkURLSnapshot
                document.parts[partIndex].musicDuration = max(0, ref.durationSnapshot ?? 0)
                document.parts[partIndex].musicPosition = 0
            } else {
                document.parts[partIndex].musicSourceKind = MusicSourceKind.hypePattern.rawValue
                document.parts[partIndex].musicPatternName = value
            }
        case "musicsourcekind", "music_source_kind", "sourcekind", "source_kind":
            document.parts[partIndex].musicSourceKind = MusicSourceKind.parse(value).rawValue
        case "applemusicid", "apple_music_id", "musicid", "music_id":
            document.parts[partIndex].musicSourceID = value
        case "applemusictype", "apple_music_type", "musictype", "music_type":
            document.parts[partIndex].musicSourceType = AppleMusicItemKind.parse(value)?.rawValue ?? value
        case "applemusictitle", "apple_music_title", "musictitle", "music_title":
            document.parts[partIndex].musicSourceTitle = value
        case "applemusicartist", "apple_music_artist", "musicartist", "music_artist":
            document.parts[partIndex].musicSourceArtist = value
        case "applemusicalbum", "apple_music_album", "musicalbum", "music_album":
            document.parts[partIndex].musicSourceAlbum = value
        case "artwork", "artworkurl", "artwork_url", "musicartwork", "music_artwork":
            document.parts[partIndex].musicArtworkURL = value
        case "musicposition", "music_position", "positionseconds", "position_seconds":
            document.parts[partIndex].musicPosition = max(0, toNumber(value))
        case "musicduration", "music_duration", "durationseconds", "duration_seconds":
            document.parts[partIndex].musicDuration = max(0, toNumber(value))
        case "musicqueue", "music_queue", "queuedata", "queue_data":
            document.parts[partIndex].musicQueueData = value
        case "musicsearchterm", "music_search_term", "searchterm", "search_term":
            document.parts[partIndex].musicSearchTerm = value
        case "musicsearchscope", "music_search_scope", "searchscope", "search_scope":
            document.parts[partIndex].musicSearchScope = AppleMusicSearchScope(rawValue: value.lowercased())?.rawValue ?? AppleMusicSearchScope.catalog.rawValue
        // Scene3D
        case "imagefilter", "image_filter", "filter":
            document.parts[partIndex].imageFilter = value.lowercased() == "none" ? "" : value.lowercased()
        case "imagefilterintensity", "image_filter_intensity", "filterintensity", "filter_intensity":
            document.parts[partIndex].imageFilterIntensity = max(0, min(1, toNumber(value)))
        case "object", "modelasset", "model_asset", "assetname", "asset_name":
            let partId = document.parts[partIndex].id
            _ = Scene3DModelBindingResolver.bindModelOrObject(
                value: value,
                to: &document.parts[partIndex],
                repository: document.assetRepository,
                resolvePath: { resolveScene3DPath($0, partId: partId, context: context) }
            )
        case "model":
            let partId = document.parts[partIndex].id
            _ = Scene3DModelBindingResolver.bindModelOrObject(
                value: value,
                to: &document.parts[partIndex],
                repository: document.assetRepository,
                resolvePath: { resolveScene3DPath($0, partId: partId, context: context) }
            )
        case "modelurl", "model_url", "sceneurl", "scene_url":
            // Legacy alias: route through the resolver so STL files auto-
            // convert whether the author uses `object` or `modelURL`.
            let partId = document.parts[partIndex].id
            _ = Scene3DModelBindingResolver.bindPath(
                value: value,
                to: &document.parts[partIndex],
                resolvePath: { resolveScene3DPath($0, partId: partId, context: context) }
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
            let n = clampedInt(toNumber(value))
            document.parts[partIndex].progressDecimals = max(0, min(10, n))
        case "decimals":
            // Shared alias — dispatch by part type. Mirrors the
            // gauge.decimals contract for both: 0 = integral steps
            // (default), capped at 10 for sane formatting.
            let n = clampedInt(toNumber(value))
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
            let n = clampedInt(toNumber(value))
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

    private func applyHyperCardWindowPropertySet(
        windowName: String,
        property: String,
        value: Value,
        env: inout Environment,
        document: inout HypeDocument,
        currentCardId: UUID
    ) {
        let normalizedWindow = AssetRepository.classicMediaLookupKey(windowName)
        let normalizedProperty = property.lowercased()
        env.globals["hypercard.window.\(normalizedWindow).\(normalizedProperty)"] = value

        guard let partIndex = hyperCardWindowPartIndex(
            windowName: windowName,
            document: document,
            currentCardId: currentCardId
        ) else {
            return
        }

        switch normalizedProperty {
        case "loop":
            if document.parts[partIndex].partType == .video {
                document.parts[partIndex].videoLoop = isTruthy(value)
            }
        case "rate":
            if document.parts[partIndex].partType == .video {
                document.parts[partIndex].videoAutoplay = (Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) != 0
            }
        case "audiolevel":
            if document.parts[partIndex].partType == .video {
                document.parts[partIndex].videoVolume = normalizedClassicSoundVolume(value)
            }
        case "mute":
            if document.parts[partIndex].partType == .video {
                document.parts[partIndex].videoVolume = isTruthy(value) ? 0 : normalizedClassicSoundVolume(
                    env.globals["hypercard.sound.volume"] ?? "255"
                )
            }
        case "windowname":
            document.parts[partIndex].name = value
            env.invalidatePartLookupCache()
        case "movie":
            if let asset = document.assetRepository.asset(byClassicMediaName: value, kind: .videoClip) {
                document.parts[partIndex].videoAssetRef = document.assetRepository.assetRef(for: asset)
                document.parts[partIndex].videoURL = "asset://\(asset.id.uuidString)"
                document.parts[partIndex].name = value
                if asset.width > 0 {
                    document.parts[partIndex].width = Double(asset.width)
                }
                if asset.height > 0 {
                    document.parts[partIndex].height = Double(asset.height)
                }
                env.invalidatePartLookupCache()
            }
        case "windowrect", "rect":
            let values = classicNumberList(value)
            if values.count >= 4 {
                document.parts[partIndex].left = values[0]
                document.parts[partIndex].top = values[1]
                document.parts[partIndex].width = max(1, values[2] - values[0])
                document.parts[partIndex].height = max(1, values[3] - values[1])
            }
        case "windowloc", "loc":
            let values = classicNumberList(value)
            if values.count >= 2 {
                document.parts[partIndex].left = values[0]
                document.parts[partIndex].top = values[1]
            }
        default:
            break
        }
    }

    private func setHyperCardWindowVisibility(
        windowName: Value,
        visible: Bool,
        env: inout Environment,
        document: inout HypeDocument,
        currentCardId: UUID
    ) {
        let normalizedWindow = AssetRepository.classicMediaLookupKey(windowName)
        env.globals["hypercard.window.\(normalizedWindow).visible"] = visible ? "true" : "false"
        guard let partIndex = hyperCardWindowPartIndex(
            windowName: windowName,
            document: document,
            currentCardId: currentCardId
        ) else {
            return
        }
        document.parts[partIndex].visible = visible
    }

    private func closeHyperCardWindow(
        windowName: Value,
        env: inout Environment,
        document: inout HypeDocument,
        currentCardId: UUID
    ) {
        let normalizedWindow = AssetRepository.classicMediaLookupKey(windowName)
        env.globals["hypercard.window.\(normalizedWindow).exists"] = "false"
        env.globals["hypercard.window.\(normalizedWindow).visible"] = "false"
        document.parts.removeAll { part in
            part.cardId == currentCardId &&
                isHyperCardCompatibilityWindowPart(part) &&
                AssetRepository.classicMediaLookupKey(part.name) == normalizedWindow
        }
        env.invalidatePartLookupCache()
    }

    private func applyHyperCardWindowMessage(
        message: Value,
        windowName: Value,
        env: inout Environment,
        document: inout HypeDocument,
        currentCardId: UUID
    ) {
        let normalizedWindow = AssetRepository.classicMediaLookupKey(windowName)
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedMessage.isEmpty else { return }

        env.globals["hypercard.window.\(normalizedWindow).lastmessage"] = normalizedMessage
        let countKey = "hypercard.window.\(normalizedWindow).message.\(normalizedMessage).count"
        let priorCount = Int(env.globals[countKey] ?? "0") ?? 0
        env.globals[countKey] = String(priorCount + 1)

        guard let partIndex = hyperCardWindowPartIndex(
            windowName: windowName,
            document: document,
            currentCardId: currentCardId
        ) else {
            return
        }

        switch normalizedMessage {
        case "play":
            document.parts[partIndex].visible = true
            if document.parts[partIndex].partType == .video {
                document.parts[partIndex].videoAutoplay = true
                env.globals["hypercard.window.\(normalizedWindow).rate"] = "1.0"
            }
        case "pause", "stop":
            if document.parts[partIndex].partType == .video {
                document.parts[partIndex].videoAutoplay = false
                env.globals["hypercard.window.\(normalizedWindow).rate"] = "0.0"
            }
        case "movieidle", "idle":
            break
        default:
            break
        }
    }

    private func hyperCardWindowPropertyValue(
        windowName: Value,
        property: Value,
        env: Environment,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Value {
        let normalizedWindow = AssetRepository.classicMediaLookupKey(windowName)
        let normalizedProperty = property.lowercased()
        if let value = env.globals["hypercard.window.\(normalizedWindow).\(normalizedProperty)"] {
            return value
        }
        if normalizedWindow == "card window" {
            switch normalizedProperty {
            case "rect", "windowrect":
                return "0,0,\(document.stack.width),\(document.stack.height)"
            case "loc", "windowloc":
                return "0,0"
            case "visible":
                return "true"
            default:
                break
            }
        }
        guard let partIndex = hyperCardWindowPartIndex(
            windowName: windowName,
            document: document,
            currentCardId: currentCardId
        ) else {
            return ""
        }
        let part = document.parts[partIndex]
        switch normalizedProperty {
        case "rect", "windowrect":
            return [
                part.left,
                part.top,
                part.left + part.width,
                part.top + part.height
            ].map(formatNumber).joined(separator: ",")
        case "loc", "windowloc":
            return "\(formatNumber(part.left)),\(formatNumber(part.top))"
        case "scroll", "scrollpos":
            return "0,0"
        case "visible":
            return part.visible ? "true" : "false"
        default:
            return ""
        }
    }

    // MARK: - there is a / there is no helpers (B6)

    /// Returns true when an object of the given type and name exists in the
    /// current card's scope (card parts + background parts).
    private func objectExistsInScope(
        objectType: String,
        name: String,
        env: Environment,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Bool {
        let lower = objectType.lowercased()
        let lowerName = name.lowercased()
        switch lower {
        case "window":
            return hyperCardWindowExists(name, env: env, document: document, currentCardId: currentCardId)
        case "card", "cd":
            return document.cards.contains { $0.name.lowercased() == lowerName }
        case "background", "bg", "bkgnd":
            return document.backgrounds.contains { $0.name.lowercased() == lowerName }
        default:
            // Map objectType to PartType for buttons/fields/images/etc.
            // Restrict to parts visible on the current card or its background.
            let cardParts = document.partsForCard(currentCardId)
            let bgId = document.cards.first(where: { $0.id == currentCardId })?.backgroundId
            let bgParts = bgId.map { document.partsForBackground($0) } ?? []
            let visibleParts = cardParts + bgParts
            return visibleParts.contains { part in
                guard part.name.lowercased() == lowerName else { return false }
                // If the objectType matches a known PartType, filter by it.
                if let targetType = PartType(rawValue: lower) {
                    return part.partType == targetType
                }
                // Plural/alias forms: "buttons", "fields", "btn", "fld"
                switch lower {
                case "buttons", "btn":  return part.partType == .button
                case "fields", "fld":   return part.partType == .field
                case "images":          return part.partType == .image
                default:                return true   // unknown type — match any part
                }
            }
        }
    }

    // MARK: - the target descriptor (B8 / 1A.the target)

    /// Descriptor form for the target/originalTarget expression.
    private enum DescriptorForm {
        case short   // "button \"OK\"" or "card \"Home\""
        case long    // "card button \"OK\" of card \"Home\"" (full path)
    }

    /// Return a HyperCard-style identifying string for `id` in `document`.
    ///
    /// Short/abbreviated form: `button "OK"`, `card "Home"`, `stack "Myst"`.
    /// Long form: `card button "OK" of card "Home"`.
    private func descriptorForObject(
        id: UUID,
        document: HypeDocument,
        context: ExecutionContext,
        form: DescriptorForm = .short
    ) -> String {
        if let description = context.scriptContext?.objectDescriptions[id] {
            return description
        }
        if let part = document.parts.first(where: { $0.id == id }) {
            let typeStr = part.partType.rawValue   // e.g. "button", "field"
            let partDesc = "\(typeStr) \"\(part.name)\""
            if form == .short {
                return partDesc
            }
            // Long form: prepend "card " prefix and card path.
            let cardId = part.cardId ?? context.currentCardId
            let card = document.cards.first(where: { $0.id == cardId })
            let cardDesc = card.map { "card \"\($0.name)\"" } ?? "card id \(cardId)"
            return "card \(partDesc) of \(cardDesc)"
        }
        if let card = document.cards.first(where: { $0.id == id }) {
            return card.name.isEmpty ? "card id \(id)" : "card \"\(card.name)\""
        }
        if let bg = document.backgrounds.first(where: { $0.id == id }) {
            return bg.name.isEmpty ? "background id \(id)" : "background \"\(bg.name)\""
        }
        if document.stack.id == id {
            return "stack \"\(document.stack.name)\""
        }
        return "object id \(id)"
    }

    private func hyperCardWindowExists(
        _ windowName: Value,
        env: Environment,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Bool {
        let normalizedWindow = AssetRepository.classicMediaLookupKey(windowName)
        if isTruthy(env.globals["hypercard.window.\(normalizedWindow).exists"] ?? "") {
            return true
        }
        return hyperCardWindowPartIndex(windowName: windowName, document: document, currentCardId: currentCardId) != nil
    }

    private func hyperCardWindowPartIndex(
        windowName: Value,
        document: HypeDocument,
        currentCardId: UUID
    ) -> Int? {
        let normalizedWindow = AssetRepository.classicMediaLookupKey(windowName)
        return document.parts.lastIndex { part in
            let normalizedPartName = AssetRepository.classicMediaLookupKey(part.name)
            let normalizedClassicWindowName = classicCompatibilityWindowName(from: part)
            return part.cardId == currentCardId &&
                isHyperCardCompatibilityWindowPart(part) &&
                (normalizedPartName == normalizedWindow || normalizedClassicWindowName == normalizedWindow)
        }
    }

    private func isHyperCardCompatibilityWindowPart(_ part: Part) -> Bool {
        part.helpText == "hypercard-playqt" ||
            part.helpText.hasPrefix("hypercard-playqt\n") ||
            part.helpText == "hypercard-picture"
    }

    private func classicCompatibilityWindowName(from part: Part) -> String? {
        for line in part.helpText.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("window=") else { continue }
            let value = String(trimmed.dropFirst("window=".count))
            let normalized = AssetRepository.classicMediaLookupKey(value)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private func normalizedClassicSoundVolume(_ rawValue: Value) -> Double {
        let parsed = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 255
        return min(255, max(0, parsed.rounded())) / 255
    }

    private func classicNumberList(_ rawValue: Value) -> [Double] {
        rawValue
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
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
            if config.chartType == .spider { return }
            config.series[loc.seriesIndex].data[loc.pointIndex].color = value
        case "value", "current", "currentvalue", "current_value":
            let newValue = toNumber(value)
            if config.chartType == .spider {
                let point = config.series[loc.seriesIndex].data[loc.pointIndex]
                config.series[loc.seriesIndex].data[loc.pointIndex].value = config.clampedSpiderValue(newValue, for: point)
            } else {
                config.series[loc.seriesIndex].data[loc.pointIndex].value = newValue
            }
        case "min", "minimum", "minimumvalue", "minimum_value":
            config.series[loc.seriesIndex].data[loc.pointIndex].minimumValue = toNumber(value)
            config.series[loc.seriesIndex].data[loc.pointIndex].normalizeRangeAndValue(includeCurrentValue: false)
        case "max", "maximum", "maximumvalue", "maximum_value":
            config.series[loc.seriesIndex].data[loc.pointIndex].maximumValue = toNumber(value)
            config.series[loc.seriesIndex].data[loc.pointIndex].normalizeRangeAndValue(includeCurrentValue: false)
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
            guard config.chartType != .spider else { return nil }
            return config.xAxisLabel
        case "yaxislabel", "y_axis_label", "ylabel", "y_label":
            guard config.chartType != .spider else { return nil }
            return config.yAxisLabel
        case "showlegend", "show_legend":
            return config.showLegend ? "true" : "false"
        case "showgrid", "show_grid":
            return config.showGrid ? "true" : "false"
        case "charttype", "chart_type":
            return config.chartType.rawValue
        case "interactable", "interactive":
            return config.interactable ? "true" : "false"
        case "spiderringcount", "spider_ring_count":
            return String(config.spiderRingCount)
        case "spidergridcolor", "spider_grid_color":
            return config.spiderGridColor
        case "spideraxiscolor", "spider_axis_color":
            return config.spiderAxisColor
        case "spiderlabelcolor", "spider_label_color":
            return config.spiderLabelColor
        case "spiderfillopacity", "spider_fill_opacity":
            return formatNumber(config.spiderFillOpacity)
        case "spiderpointradius", "spider_point_radius":
            return formatNumber(config.spiderPointRadius)
        case "spidershowvaluelabels", "spider_show_value_labels":
            return config.spiderShowValueLabels ? "true" : "false"
        case "spiderdecimalplaces", "spider_decimal_places", "decimalplaces", "decimal_places":
            return String(config.spiderDecimalPlaces)
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
            guard config.chartType != .spider else { return false }
            config.xAxisLabel = value
        case "yaxislabel", "y_axis_label", "ylabel", "y_label":
            guard config.chartType != .spider else { return false }
            config.yAxisLabel = value
        case "showlegend", "show_legend":
            config.showLegend = isTruthy(value)
        case "showgrid", "show_grid":
            config.showGrid = isTruthy(value)
        case "charttype", "chart_type":
            if let t = ChartType.fromUserValue(value) {
                config.chartType = t
            } else {
                return false
            }
        case "interactable", "interactive":
            config.interactable = isTruthy(value)
        case "spiderringcount", "spider_ring_count":
            config.spiderRingCount = Int(ChartConfig.clamp(
                toNumber(value),
                min: Double(ChartConfig.spiderMinimumRingCount),
                max: Double(ChartConfig.spiderMaximumRingCount)
            ))
        case "spidergridcolor", "spider_grid_color":
            config.spiderGridColor = ChartConfig.normalizedHex(value, fallback: config.spiderGridColor)
        case "spideraxiscolor", "spider_axis_color":
            config.spiderAxisColor = ChartConfig.normalizedHex(value, fallback: config.spiderAxisColor)
        case "spiderlabelcolor", "spider_label_color":
            config.spiderLabelColor = ChartConfig.normalizedHex(value, fallback: config.spiderLabelColor)
        case "spiderfillopacity", "spider_fill_opacity":
            config.spiderFillOpacity = ChartConfig.clamp(toNumber(value), min: 0, max: 1)
        case "spiderpointradius", "spider_point_radius":
            config.spiderPointRadius = ChartConfig.clamp(toNumber(value), min: 1, max: 12)
        case "spidershowvaluelabels", "spider_show_value_labels":
            config.spiderShowValueLabels = isTruthy(value)
        case "spiderdecimalplaces", "spider_decimal_places", "decimalplaces", "decimal_places":
            config.spiderDecimalPlaces = Int(ChartConfig.clamp(
                toNumber(value),
                min: Double(ChartConfig.spiderMinimumDecimalPlaces),
                max: Double(ChartConfig.spiderMaximumDecimalPlaces)
            ))
        default:
            return false
        }
        document.parts[partIndex].chartData = config.toJSON()
        return true
    }

    private func upsertMusicAsset(
        pattern: MusicPatternSpec,
        requestedName: String,
        document: inout HypeDocument
    ) -> String {
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let assetName = trimmed.isEmpty ? "\(pattern.name).wav" : trimmed
        let data = MusicPatternRenderer.wavData(for: pattern)
        let musicTags = ["music", "generated", "audiokit"]
        if let existing = document.assetRepository.asset(byName: assetName) {
            document.assetRepository.updateAsset(id: existing.id) { asset in
                asset.kind = .audioClip
                asset.mimeType = "audio/wav"
                asset.data = data
                asset.tags = Array(Set(asset.tags + musicTags)).sorted()
            }
        } else {
            document.assetRepository.addAsset(Asset(
                name: assetName,
                kind: .audioClip,
                mimeType: "audio/wav",
                data: data,
                tags: musicTags
            ))
        }
        return assetName
    }

    private func encodeAppleMusicRefs(_ refs: [AppleMusicItemRef]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(refs),
              let json = String(data: data, encoding: .utf8) else {
            return refs.map(\.encodedSource).joined(separator: "\n")
        }
        return json
    }

    /// Convert a HypeTalk value to a number. Non-numeric strings become 0.
    private func toNumber(_ value: Value) -> Double {
        Double(value) ?? 0
    }

    /// Convert a script-derived Double to Int without trapping. NaN -> 0;
    /// values beyond Int's range clamp to Int.min/Int.max. Scripts can produce
    /// arbitrary doubles (`10 ^ 30`, "nan"), and a stack script must never be
    /// able to crash the host process (unsaved-document data loss).
    private func clampedInt(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= Double(Int.max) { return Int.max }
        if d <= Double(Int.min) { return Int.min }
        return Int(d)
    }

    /// Format a number, dropping .0 for integers.
    ///
    /// Uses `Int(exactly:)` so that integral doubles outside Int64 range
    /// (e.g. 1e30) fall through to `String(n)` ("1e+30") rather than
    /// trapping. Behavior for all in-range values is byte-identical to before.
    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded(.towardZero) && !n.isInfinite && !n.isNaN {
            if let i = Int(exactly: n.rounded(.towardZero)) {
                return String(i)
            }
        }
        return String(n)
    }

    /// Check if a HypeTalk value is truthy.
    ///
    /// Classic HyperCard truth: only `"true"` (case-insensitive) and any non-zero
    /// number are truthy. `"yes"`, `"on"`, and other English affirmatives are FALSY.
    /// This matches the HypeTalk guide and classic HyperCard behaviour.
    private func isTruthy(_ value: Value) -> Bool {
        let lower = value.lowercased()
        return lower == "true" || (Double(value).map { $0 != 0 } ?? false)
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
        if let cached = SpriteAreaMutationScope.current?.spriteAreaSpec(partIndex: partIndex, document: document) {
            return cached
        }
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
        if let batch = SpriteAreaMutationScope.current {
            return batch.mutateSpriteAreaSpec(partIndex: partIndex, document: document, transform: transform)
        }
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
        if let batch = SpriteAreaMutationScope.current {
            return batch.mutateActiveScene(partIndex: partIndex, document: document, transform: transform)
        }
        return mutateSpriteAreaSpec(partIndex: partIndex, document: &document) { spec in
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
                node.tileMapSpec?.columns = clampedInt(toNumber(value))
            }
        case "rows":
            if node.tileMapSpec != nil {
                node.tileMapSpec?.rows = clampedInt(toNumber(value))
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
        case "particlelifetime" where node.nodeType == .emitter, "lifetime" where node.nodeType == .emitter:
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.particleLifetime = toNumber(value)
        case "particlespeed" where node.nodeType == .emitter, "speed" where node.nodeType == .emitter:
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
        case "particlelifetime" where node.nodeType == .emitter, "lifetime" where node.nodeType == .emitter:
            return formatNumber(node.emitterSpec?.particleLifetime ?? 2)
        case "particlespeed" where node.nodeType == .emitter, "speed" where node.nodeType == .emitter:
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

    private func statementKind(_ stmt: Statement) -> String {
        switch stmt {
        case .put: return "put"
        case .get: return "get"
        case .set: return "set"
        case .go: return "go"
        case .goInStack: return "goInStack"
        case .ifThenElse: return "ifThenElse"
        case .repeatForever: return "repeatForever"
        case .repeatCount: return "repeatCount"
        case .repeatWhile: return "repeatWhile"
        case .repeatWith: return "repeatWith"
        case .exitRepeat: return "exitRepeat"
        case .nextRepeat: return "nextRepeat"
        case .passMessage: return "passMessage"
        case .exitHandler: return "exitHandler"
        case .returnValue: return "returnValue"
        case .globalDecl: return "globalDecl"
        case .ask: return "ask"
        case .askAI: return "askAI"
        case .askMeshy: return "askMeshy"
        case .remeshAsset: return "remeshAsset"
        case .retextureAsset: return "retextureAsset"
        case .answer: return "answer"
        case .say: return "say"
        case .activateListener: return "activateListener"
        case .visual: return "visual"
        case .send: return "send"
        case .expressionStatement: return "expressionStatement"
        case .doBlock: return "doBlock"
        case .animateProperty: return "animateProperty"
        case .playSound: return "playSound"
        case .playStop: return "playStop"
        case .createMusicPattern: return "createMusicPattern"
        case .playMusicPattern: return "playMusicPattern"
        case .stopMusic: return "stopMusic"
        case .pauseMusic: return "pauseMusic"
        case .resumeMusic: return "resumeMusic"
        case .exportMusicPattern: return "exportMusicPattern"
        case .authorizeAppleMusic: return "authorizeAppleMusic"
        case .searchAppleMusic: return "searchAppleMusic"
        case .playAppleMusic: return "playAppleMusic"
        case .seekAppleMusic: return "seekAppleMusic"
        case .pauseAppleMusic: return "pauseAppleMusic"
        case .resumeAppleMusic: return "resumeAppleMusic"
        case .stopAppleMusic: return "stopAppleMusic"
        case .beep: return "beep"
        case .waitDuration: return "waitDuration"
        case .waitCondition: return "waitCondition"
        case .createCard: return "createCard"
        case .createBackground: return "createBackground"
        case .createButton: return "createButton"
        case .createField: return "createField"
        case .showAllCards: return "showAllCards"
        case .addTo: return "addTo"
        case .subtractFrom: return "subtractFrom"
        case .multiplyBy: return "multiplyBy"
        case .divideBy: return "divideBy"
        case .deleteObject: return "deleteObject"
        case .findText: return "findText"
        case .selectObject: return "selectObject"
        case .sortCards: return "sortCards"
        case .hideObject: return "hideObject"
        case .showObject: return "showObject"
        case .lockScreen: return "lockScreen"
        case .unlockScreen: return "unlockScreen"
        case .openStack: return "openStack"
        case .convert: return "convert"
        case .closeWindow: return "closeWindow"
        case .saveStack: return "saveStack"
        case .quitApp: return "quitApp"
        case .editScriptOf: return "editScriptOf"
        case .chooseTool: return "chooseTool"
        case .markCard: return "markCard"
        case .unmarkCard: return "unmarkCard"
        case .typeText: return "typeText"
        case .requestURL: return "requestURL"
        case .listenHTTP: return "listenHTTP"
        case .listenTCP: return "listenTCP"
        case .connectTCP: return "connectTCP"
        case .sendToConnection: return "sendToConnection"
        default: return "other"
        }
    }

    private func expressionKind(_ expr: Expression) -> String {
        switch expr {
        case .literal: return "literal"
        case .variable: return "variable"
        case .it: return "it"
        case .me: return "me"
        case .this: return "this"
        case .binary: return "binary"
        case .unary: return "unary"
        case .await: return "await"
        case .functionCall: return "functionCall"
        case .propertyAccess: return "propertyAccess"
        case .headerAccess: return "headerAccess"
        case .chunk: return "chunk"
        case .objectRef: return "objectRef"
        case .scopedObjectRef: return "scopedObjectRef"
        case .chartDataPointRef: return "chartDataPointRef"
        case .tileAt: return "tileAt"
        case .not: return "not"
        case .contains: return "contains"
        case .stringConcat: return "stringConcat"
        case .spacedConcat: return "spacedConcat"
        case .empty: return "empty"
        case .isIn: return "isIn"
        case .isNotIn: return "isNotIn"
        case .isWithin: return "isWithin"
        case .isNotWithin: return "isNotWithin"
        case .isA: return "isA"
        case .isNotA: return "isNotA"
        case .thereIsA: return "thereIsA"
        case .thereIsNo: return "thereIsNo"
        case .askMeshy: return "askMeshy"
        case .messageBox: return "messageBox"
        }
    }
}

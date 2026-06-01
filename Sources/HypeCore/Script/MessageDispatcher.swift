import Foundation

/// Minimal `TextOutputStream` that writes to stderr. Used by the
/// parse-error reporter below instead of `FileHandle.standardError
/// .write(...)` because `print(_:to:)` with a TextOutputStream is
/// safer under concurrent callers than direct FileHandle access.
private struct StderrOutputStream: TextOutputStream {
    mutating func write(_ string: String) {
        fputs(string, stderr)
    }
}

private final class _DispatchResultBox: @unchecked Sendable {
    var result: ExecutionResult?
}

private enum _DispatchSyncGate {
    static let semaphore = DispatchSemaphore(value: 1)
}

private final class HypeTalkScriptParseCache: @unchecked Sendable {
    static let shared = HypeTalkScriptParseCache()

    private let lock = NSLock()
    private var entries: [String: Script] = [:]
    private var order: [String] = []
    private let maxEntries = 256

    func parsedScript(for source: String) throws -> Script {
        lock.lock()
        if let cached = entries[source] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let parsed = try parser.parse()

        lock.lock()
        if entries[source] == nil {
            entries[source] = parsed
            order.append(source)
            if order.count > maxEntries {
                let evicted = order.removeFirst()
                entries.removeValue(forKey: evicted)
            }
        }
        lock.unlock()

        return parsed
    }
}

/// Dispatches messages through the HyperCard-style object hierarchy:
/// part -> card -> background -> stack.
public struct ScriptDispatchContext: Sendable {
    /// Ordered chain from the most-specific SpriteKit target up to the owning part.
    public var hierarchyPrefix: [UUID]
    /// Scripts for synthetic or non-part targets such as scene and node objects.
    public var objectScripts: [UUID: String]
    /// Human-readable descriptions for synthetic or non-part targets.
    public var objectDescriptions: [UUID: String]

    public init(
        hierarchyPrefix: [UUID],
        objectScripts: [UUID: String] = [:],
        objectDescriptions: [UUID: String] = [:]
    ) {
        self.hierarchyPrefix = hierarchyPrefix
        self.objectScripts = objectScripts
        self.objectDescriptions = objectDescriptions
    }
}

public struct MessageDispatcher: Sendable {

    /// Sentinel UUID representing the app-level ("Hype") script — the final link in the message chain.
    public static let hypeScriptSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public init() {}

    /// Returns true when the message hierarchy contains a handler for `message`.
    ///
    /// Classic HyperTalk lets scripts call local handlers with command-style
    /// syntax, for example `Buzzer 2`. The parser keeps that syntax as an
    /// `externalCommand` until runtime can decide whether the name is actually
    /// an imported XCMD or a normal handler in the current pass-up path.
    public func hasHandler(
        message: String,
        targetId: UUID,
        document: HypeDocument,
        currentCardId: UUID,
        appScript: String = "",
        scriptContext: ScriptDispatchContext? = nil
    ) -> Bool {
        let chain = buildHierarchy(
            targetId: targetId,
            document: document,
            currentCardId: currentCardId,
            scriptContext: scriptContext
        )
        let aliases = Self.handlerAliases(for: message.lowercased())
        for objectId in chain {
            guard let script = findScript(
                objectId: objectId,
                document: document,
                appScript: appScript,
                scriptContext: scriptContext
            ) else { continue }
            guard let parsedScript = try? HypeTalkScriptParseCache.shared.parsedScript(for: script) else { continue }
            if parsedScript.handlers.contains(where: { aliases.contains($0.name.lowercased()) }) {
                return true
            }
        }
        return false
    }

    /// Dispatch a message through the hierarchy, returning the
    /// result from the first handler that does not pass it.
    ///
    /// Parse errors encountered along the way are:
    /// - Printed to stderr with `[HypeTalk parse error]` prefix so
    ///   they show up in Console.app / `log stream` for debugging.
    /// - Collected and returned on the `ExecutionResult.error`
    ///   field (as a `ScriptError` with line number) so the view
    ///   layer can optionally surface them in the UI.
    ///
    /// This replaces the previous behaviour where
    /// `try? parser.parse()` silently swallowed every parse
    /// failure, which meant a user with a syntactically invalid
    /// script saw exactly nothing — no dispatch, no error, no
    /// feedback of any kind. That was the meta-cause of the
    /// reported "idle event is not firing" bug.
    public func dispatch(
        message: String,
        params: [Value],
        targetId: UUID,
        document: HypeDocument,
        currentCardId: UUID,
        dialogProvider: DialogProvider = StubDialogProvider(),
        drawingProvider: DrawingProvider = StubDrawingProvider(),
        systemProvider: SystemProvider = StubSystemProvider(),
        hostProvider: any HostApplicationProvider = StubHostApplicationProvider(),
        aiProvider: any AIScriptingProvider = StubAIScriptingProvider(),
        speechOutputProvider: SpeechOutputProvider = StubSpeechOutputProvider(),
        runtimeProvider: (any ScriptRuntimeProviding)? = nil,
        appScript: String = "",
        mouseX: Double = 0,
        mouseY: Double = 0,
        scriptContext: ScriptDispatchContext? = nil,
        nestedSendDepth: Int = 0,
        fileProvider: any FileAccessProvider = StubFileAccessProvider()
    ) -> ExecutionResult {
        _DispatchSyncGate.semaphore.wait()
        defer { _DispatchSyncGate.semaphore.signal() }
        let semaphore = DispatchSemaphore(value: 0)
        let box = _DispatchResultBox()
        let completeDispatch: @Sendable () async -> Void = {
            box.result = await dispatchAsync(
                message: message,
                params: params,
                targetId: targetId,
                document: document,
                currentCardId: currentCardId,
                dialogProvider: dialogProvider,
                drawingProvider: drawingProvider,
                systemProvider: systemProvider,
                hostProvider: hostProvider,
                aiProvider: aiProvider,
                speechOutputProvider: speechOutputProvider,
                appScript: appScript,
                mouseX: mouseX,
                mouseY: mouseY,
                scriptContext: scriptContext,
                runtimeProvider: runtimeProvider,
                nestedSendDepth: nestedSendDepth,
                fileProvider: fileProvider
            )
            semaphore.signal()
        }
        if Thread.isMainThread {
            Task.detached {
                await completeDispatch()
            }
        } else {
            Task { @MainActor in
                await completeDispatch()
            }
        }
        semaphore.wait()
        if let result = box.result {
            return result
        }
        let error = ScriptError(message: "Dispatch timed out", line: 0, handler: message)
        HypeLogger.shared.scriptError(error, source: "Runtime", context: "Message dispatch")
        return ExecutionResult(status: .error, error: error)
    }

    public func dispatchAsync(
        message: String,
        params: [Value],
        targetId: UUID,
        document: HypeDocument,
        currentCardId: UUID,
        dialogProvider: DialogProvider = StubDialogProvider(),
        drawingProvider: DrawingProvider = StubDrawingProvider(),
        systemProvider: SystemProvider = StubSystemProvider(),
        hostProvider: any HostApplicationProvider = StubHostApplicationProvider(),
        aiProvider: any AIScriptingProvider = StubAIScriptingProvider(),
        meshyProvider: (any MeshyScriptingProvider)? = nil,
        speechOutputProvider: SpeechOutputProvider = StubSpeechOutputProvider(),
        appScript: String = "",
        mouseX: Double = 0,
        mouseY: Double = 0,
        scriptContext: ScriptDispatchContext? = nil,
        runtimeProvider: (any ScriptRuntimeProviding)? = nil,
        nestedSendDepth: Int = 0,
        fileProvider: any FileAccessProvider = StubFileAccessProvider()
    ) async -> ExecutionResult {
        let chain = buildHierarchy(
            targetId: targetId,
            document: document,
            currentCardId: currentCardId,
            scriptContext: scriptContext
        )
        var currentDocument = document
        var latestModifiedDocument: HypeDocument? = nil
        var carriedNavigationTarget: UUID? = nil
        var carriedProjectNavigationTarget: ProjectNavigationTarget? = nil
        var carriedShowAllCards = false
        var carriedVisualEffect: String? = nil
        var carriedVisualEffectDuration: Double? = nil

        // Accumulate parse errors from every script in the chain.
        // If *no* handler ever runs, we still want to surface the
        // first parse error so the user sees at least one concrete
        // explanation of why nothing happened.
        var firstParseError: ScriptError? = nil

        for objectId in chain {
            guard let script = findScript(
                objectId: objectId,
                document: currentDocument,
                appScript: appScript,
                scriptContext: scriptContext
            ) else { continue }
            guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            // Tokenize and parse the script. Repeated idle/frame
            // dispatches hit the same source every tick, so cache
            // successful parses by exact source text.
            let parsedScript: Script
            do {
                parsedScript = try HypeTalkScriptParseCache.shared.parsedScript(for: script)
            } catch let error as ParseError {
                let description = error.errorDescription ?? String(describing: error)
                let ownerDescription = Self.describeObject(
                    objectId: objectId,
                    document: currentDocument,
                    scriptContext: scriptContext
                )
                let fullMessage = "[HypeTalk parse error] in script on \(ownerDescription): \(description)"
                var stderr = StderrOutputStream()
                print(fullMessage, to: &stderr)
                let line = Self.extractLineNumber(from: description) ?? 0
                let actionURL = Self.scriptErrorActionURL(
                    objectId: objectId,
                    document: currentDocument,
                    line: line,
                    message: fullMessage
                )
                HypeLogger.shared.log(
                    .error,
                    Self.messageWithHypeReference(fullMessage, actionURL: actionURL),
                    source: "Parser",
                    actionTitle: actionURL == nil ? nil : "Open script",
                    actionURL: actionURL
                )
                if firstParseError == nil {
                    // Extract the line number from the ParseError if
                    // possible (errorDescription is "Line N: ...").
                    firstParseError = ScriptError(
                        message: fullMessage,
                        line: line,
                        handler: message,
                        objectId: objectId
                    )
                }
                continue
            } catch {
                let fullMessage = "[HypeTalk parse error] \(error.localizedDescription)"
                var stderr = StderrOutputStream()
                print(fullMessage, to: &stderr)
                let actionURL = Self.scriptErrorActionURL(
                    objectId: objectId,
                    document: currentDocument,
                    line: 0,
                    message: fullMessage
                )
                HypeLogger.shared.log(
                    .error,
                    Self.messageWithHypeReference(fullMessage, actionURL: actionURL),
                    source: "Parser",
                    actionTitle: actionURL == nil ? nil : "Open script",
                    actionURL: actionURL
                )
                if firstParseError == nil {
                    firstParseError = ScriptError(
                        message: fullMessage,
                        line: 0,
                        handler: message,
                        objectId: objectId
                    )
                }
                continue
            }

            // Look for a matching handler. Handler names are matched
            // case-insensitively; we also accept a small set of
            // "common-sense" aliases so authors can write the more
            // natural English form (`on enter` for `enterKey`,
            // `on tab` for `tabInField`, etc.).
            let aliasedNames = Self.handlerAliases(for: message.lowercased())
            guard let handler = parsedScript.handlers.first(where: {
                aliasedNames.contains($0.name.lowercased())
            }) else { continue }

            // Execute the handler.
            let context = ExecutionContext(
                targetId: objectId,
                currentCardId: currentCardId,
                document: currentDocument,
                dialogProvider: dialogProvider,
                drawingProvider: drawingProvider,
                systemProvider: systemProvider,
                hostProvider: hostProvider,
                aiProvider: aiProvider,
                speechOutputProvider: speechOutputProvider,
                runtimeProvider: runtimeProvider,
                meshyProvider: meshyProvider,
                mouseX: mouseX,
                mouseY: mouseY,
                appScript: appScript,
                nestedSendDepth: nestedSendDepth,
                fileProvider: fileProvider
            )
            let interpreter = Interpreter()
            var result = await interpreter.executeAsync(handler: handler, params: params, context: context)
            if let modifiedDocument = result.modifiedDocument {
                currentDocument = modifiedDocument
                latestModifiedDocument = modifiedDocument
            }
            if let navigationTarget = result.navigationTarget {
                carriedNavigationTarget = navigationTarget
            }
            if let projectNavigationTarget = result.projectNavigationTarget {
                carriedProjectNavigationTarget = projectNavigationTarget
            }
            if result.showAllCards {
                carriedShowAllCards = true
            }
            if let visualEffect = result.visualEffect {
                carriedVisualEffect = visualEffect
            }
            if let visualEffectDuration = result.visualEffectDuration {
                carriedVisualEffectDuration = visualEffectDuration
            }

            // If the handler produced a runtime error, patch the
            // error's `objectId` so the view layer can open the
            // script editor for the offending object. The interpreter
            // itself has no easy way to stamp this field because
            // errors are thrown from deeply nested statement
            // execution — here, at the dispatch site, we know exactly
            // which object's script was running, so we fill it in.
            //
            // We also print runtime errors to stderr with the same
            // `[HypeTalk runtime error]` prefix used for parse errors,
            // so they show up in Console.app / `log stream` for
            // debugging without depending on the UI layer wiring.
            if result.status == .error, let err = result.error {
                var patched = err
                if patched.objectId == nil {
                    patched.objectId = objectId
                }
                let ownerDescription = Self.describeObject(
                    objectId: objectId,
                    document: currentDocument,
                    scriptContext: scriptContext
                )
                let runtimeMessage = "[HypeTalk runtime error] in handler '\(patched.handler)' on \(ownerDescription) (line \(patched.line)): \(patched.message)"
                var stderr = StderrOutputStream()
                print(runtimeMessage, to: &stderr)
                let actionURL = Self.scriptErrorActionURL(
                    objectId: objectId,
                    document: currentDocument,
                    line: patched.line,
                    message: runtimeMessage
                )
                HypeLogger.shared.log(
                    .error,
                    Self.messageWithHypeReference(runtimeMessage, actionURL: actionURL),
                    source: "Runtime",
                    actionTitle: actionURL == nil ? nil : "Open script",
                    actionURL: actionURL
                )
                result.error = patched
                if result.modifiedDocument == nil {
                    result.modifiedDocument = latestModifiedDocument
                }
                if result.navigationTarget == nil {
                    result.navigationTarget = carriedNavigationTarget
                }
                if result.projectNavigationTarget == nil {
                    result.projectNavigationTarget = carriedProjectNavigationTarget
                }
                if !result.showAllCards {
                    result.showAllCards = carriedShowAllCards
                }
                if result.visualEffect == nil {
                    result.visualEffect = carriedVisualEffect
                }
                if result.visualEffectDuration == nil {
                    result.visualEffectDuration = carriedVisualEffectDuration
                }
            }

            // If the handler passed the message, continue up the
            // hierarchy BUT preserve side effects (navigation,
            // visual effect). A script like:
            //
            //   on mouseUp
            //     visual effect dissolve
            //     go next
            //     pass mouseUp
            //   end mouseUp
            //
            // sets the visual effect and navigation target BEFORE
            // passing. If the handler set a navigation target,
            // return immediately — navigation + transition should
            // fire without waiting for the rest of the chain.
            // Without this, the dispatcher drops everything when
            // it continues to the next handler.
            if result.status == .passed {
                if result.navigationTarget != nil || result.projectNavigationTarget != nil || result.showAllCards {
                    // Force status to .completed so applyDispatchResult
                    // processes the navigation and visual effect.
                    var finalResult = result
                    finalResult.status = .completed
                    finalResult.modifiedDocument = latestModifiedDocument
                    finalResult.navigationTarget = carriedNavigationTarget
                    finalResult.projectNavigationTarget = carriedProjectNavigationTarget
                    finalResult.showAllCards = carriedShowAllCards
                    finalResult.visualEffect = carriedVisualEffect
                    finalResult.visualEffectDuration = carriedVisualEffectDuration
                    return finalResult
                }
                continue
            }
            if result.modifiedDocument == nil {
                result.modifiedDocument = latestModifiedDocument
            }
            if result.navigationTarget == nil {
                result.navigationTarget = carriedNavigationTarget
            }
            if result.projectNavigationTarget == nil {
                result.projectNavigationTarget = carriedProjectNavigationTarget
            }
            if !result.showAllCards {
                result.showAllCards = carriedShowAllCards
            }
            if result.visualEffect == nil {
                result.visualEffect = carriedVisualEffect
            }
            if result.visualEffectDuration == nil {
                result.visualEffectDuration = carriedVisualEffectDuration
            }
            return result
        }

        // No handler caught the message. If we hit a parse error
        // along the way, report it so the view layer can display it
        // — this is the critical improvement over the previous
        // "silent failure" behaviour.
        if let parseErr = firstParseError {
            return ExecutionResult(
                status: .error,
                returnValue: nil,
                modifiedDocument: latestModifiedDocument,
                error: parseErr,
                navigationTarget: carriedNavigationTarget,
                projectNavigationTarget: carriedProjectNavigationTarget,
                showAllCards: carriedShowAllCards,
                visualEffect: carriedVisualEffect,
                visualEffectDuration: carriedVisualEffectDuration
            )
        }
        return ExecutionResult(
            status: .completed,
            returnValue: nil,
            modifiedDocument: latestModifiedDocument,
            navigationTarget: carriedNavigationTarget,
            projectNavigationTarget: carriedProjectNavigationTarget,
            showAllCards: carriedShowAllCards,
            visualEffect: carriedVisualEffect,
            visualEffectDuration: carriedVisualEffectDuration
        )
    }

    /// Returns the set of handler names that should match a given
    /// dispatched message. The dispatched name is always included;
    /// a small alias table lets authors use the more natural English
    /// form (`on enter` matches `enterKey`, `on tab` matches
    /// `tabInField`, etc.) without forcing them to memorize the
    /// engine's exact event names.
    ///
    /// Aliases are bidirectional: dispatching `enterKey` matches
    /// handlers named either `enterKey` OR `enter`, and dispatching
    /// `enter` matches both names too. This means a script written
    /// against either form keeps working.
    static func handlerAliases(for message: String) -> Set<String> {
        // Each tuple is a synonym group; case-insensitive.
        let groups: [Set<String>] = [
            ["enter", "enterkey"],
            ["tab", "tabinfield"],
            ["return", "returninfield"],
            ["closefield", "change"],   // common confusion — change is JS-style
            ["mouseup", "click"],       // very common alias
            ["keydown", "keypress"],
        ]
        let lower = message.lowercased()
        for group in groups where group.contains(lower) {
            return group
        }
        return [lower]
    }

    /// Human-readable description of the object that owns a
    /// script, used in parse error messages so users can see which
    /// card / background / stack / part the error came from.
    private static func describeObject(
        objectId: UUID,
        document: HypeDocument,
        scriptContext: ScriptDispatchContext?
    ) -> String {
        if let description = scriptContext?.objectDescriptions[objectId] {
            return description
        }
        if let part = document.parts.first(where: { $0.id == objectId }) {
            return "\(part.partType.rawValue) \"\(part.name)\""
        }
        if let card = document.cards.first(where: { $0.id == objectId }) {
            return card.name.isEmpty ? "card id \(objectId)" : "card \"\(card.name)\""
        }
        if let bg = document.backgrounds.first(where: { $0.id == objectId }) {
            return bg.name.isEmpty ? "background id \(objectId)" : "background \"\(bg.name)\""
        }
        if document.stack.id == objectId {
            return "stack \"\(document.stack.name)\""
        }
        if let entry = document.stackLibrary.entries.first(where: { $0.id == objectId }) {
            return "used stack \"\(entry.stackName)\""
        }
        if objectId == Self.hypeScriptSentinel {
            return "Hype (app-level script)"
        }
        return "object id \(objectId)"
    }

    /// Extract a leading "Line N: ..." prefix from a ParseError
    /// description and return N. Returns nil if the format doesn't
    /// match.
    private static func extractLineNumber(from description: String) -> Int? {
        // ParseError.errorDescription currently formats as
        // "Line N: expected X, got Y (Ztype)". Parse the leading
        // "Line N" prefix without committing to a regex.
        guard description.hasPrefix("Line ") else { return nil }
        let afterLine = description.dropFirst("Line ".count)
        let numberPart = afterLine.prefix { $0.isNumber }
        return Int(numberPart)
    }

    private static func messageWithHypeReference(_ message: String, actionURL: URL?) -> String {
        guard let actionURL else { return message }
        return "\(message) | hype-ref=\(actionURL.absoluteString)"
    }

    private static func scriptErrorActionURL(
        objectId: UUID,
        document: HypeDocument,
        line: Int,
        message: String
    ) -> URL? {
        var items = [
            URLQueryItem(name: "stack", value: document.stack.id.uuidString),
            URLQueryItem(name: "line", value: "\(line)"),
            URLQueryItem(name: "message", value: message),
        ]
        if document.parts.contains(where: { $0.id == objectId }) {
            items.append(URLQueryItem(name: "target", value: "part"))
            items.append(URLQueryItem(name: "id", value: objectId.uuidString))
        } else if document.cards.contains(where: { $0.id == objectId }) {
            items.append(URLQueryItem(name: "target", value: "card"))
            items.append(URLQueryItem(name: "id", value: objectId.uuidString))
        } else if document.backgrounds.contains(where: { $0.id == objectId }) {
            items.append(URLQueryItem(name: "target", value: "background"))
            items.append(URLQueryItem(name: "id", value: objectId.uuidString))
        } else if document.stack.id == objectId {
            items.append(URLQueryItem(name: "target", value: "stack"))
        } else if objectId == Self.hypeScriptSentinel {
            items.append(URLQueryItem(name: "target", value: "hype"))
        } else {
            items.append(URLQueryItem(name: "target", value: "object"))
            items.append(URLQueryItem(name: "id", value: objectId.uuidString))
        }

        var components = URLComponents()
        components.scheme = "hype"
        components.host = "script-error"
        components.queryItems = items
        return components.url
    }

    /// Build the message-passing hierarchy chain from the target up to
    /// the stack, then through currently used imported stack scripts.
    private func buildHierarchy(
        targetId: UUID,
        document: HypeDocument,
        currentCardId: UUID,
        scriptContext: ScriptDispatchContext?
    ) -> [UUID] {
        var chain: [UUID] = {
            let prefix = scriptContext?.hierarchyPrefix ?? []
            if prefix.isEmpty { return [targetId] }
            return prefix
        }()

        let anchorId = chain.last ?? targetId

        // If target is a part, add card -> background -> stack.
        if let part = document.parts.first(where: { $0.id == anchorId }) {
            if let cardId = part.cardId {
                if !chain.contains(cardId) {
                    chain.append(cardId)
                }
                if let card = document.cards.first(where: { $0.id == cardId }) {
                    chain.append(card.backgroundId)
                }
            } else if let bgId = part.backgroundId {
                chain.append(bgId)
            }
        } else if let card = document.cards.first(where: { $0.id == anchorId }) {
            // Target is a card — add background -> stack.
            chain.append(card.backgroundId)
        }

        chain.append(document.stack.id)
        chain.append(contentsOf: usedStackEntries(in: document).map(\.id))
        chain.append(Self.hypeScriptSentinel)

        // Deduplicate while preserving order.
        var seen = Set<UUID>()
        return chain.filter { seen.insert($0).inserted }
    }

    private func usedStackEntries(in document: HypeDocument) -> [HypeStackLibraryEntry] {
        var seen = Set<UUID>()
        var entries: [HypeStackLibraryEntry] = []
        for alias in document.stackLibrary.usedStackAliases {
            guard case .resolved(let entry) = document.stackLibrary.resolution(for: alias),
                  seen.insert(entry.id).inserted else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// Find the script associated with an object ID (part, card, background, stack, or app).
    private func findScript(
        objectId: UUID,
        document: HypeDocument,
        appScript: String = "",
        scriptContext: ScriptDispatchContext?
    ) -> String? {
        if let script = scriptContext?.objectScripts[objectId] {
            return script.isEmpty ? nil : script
        }
        // Check parts.
        if let part = document.parts.first(where: { $0.id == objectId }) {
            return part.script.isEmpty ? nil : part.script
        }
        // Check cards.
        if let card = document.cards.first(where: { $0.id == objectId }) {
            return card.script.isEmpty ? nil : card.script
        }
        // Check backgrounds.
        if let bg = document.backgrounds.first(where: { $0.id == objectId }) {
            return bg.script.isEmpty ? nil : bg.script
        }
        // Check stack.
        if document.stack.id == objectId {
            return document.stack.script.isEmpty ? nil : document.stack.script
        }
        if let entry = document.stackLibrary.entries.first(where: { $0.id == objectId }) {
            return entry.stackScript?.isEmpty == false ? entry.stackScript : nil
        }
        // Check app-level (Hype) script — sentinel UUID.
        if objectId == Self.hypeScriptSentinel {
            return appScript.isEmpty ? nil : appScript
        }
        return nil
    }
}

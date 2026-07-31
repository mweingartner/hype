import Foundation

public struct HypeTalkScriptTraceSource: Sendable, Codable, Equatable {
    public var kind: String
    public var objectId: UUID?

    public init(kind: String, objectId: UUID? = nil) {
        self.kind = kind
        self.objectId = objectId
    }
}

public struct HypeTalkScriptTraceContext: Sendable, Codable, Equatable {
    public var executionId: UUID
    public var handlerExecutionId: UUID
    public var message: String
    public var handler: String
    public var ownerDescription: String
    public var source: HypeTalkScriptTraceSource
    public var line: Int
    public var callDepth: Int

    public init(
        executionId: UUID = UUID(),
        handlerExecutionId: UUID = UUID(),
        message: String,
        handler: String,
        ownerDescription: String,
        source: HypeTalkScriptTraceSource,
        line: Int,
        callDepth: Int = 0
    ) {
        self.executionId = executionId
        self.handlerExecutionId = handlerExecutionId
        self.message = message
        self.handler = handler
        self.ownerDescription = ownerDescription
        self.source = source
        self.line = line
        self.callDepth = callDepth
    }
}

public struct HypeTalkVariableScopeSnapshot: Sendable, Codable, Equatable {
    public var locals: [String: String]
    public var globals: [String: String]
    public var it: String
    public var result: String

    public init(
        locals: [String: String] = [:],
        globals: [String: String] = [:],
        it: String = "",
        result: String = ""
    ) {
        self.locals = locals
        self.globals = globals
        self.it = it
        self.result = result
    }

    public func value(scope: String, name: String) -> String? {
        let normalizedScope = scope.lowercased()
        let key = name.lowercased()
        switch normalizedScope {
        case "local", "locals":
            return locals[key]
        case "global", "globals":
            return globals[key]
        case "special", "system":
            if key == "it" { return it }
            if key == "result", !result.isEmpty { return result }
            if key == "the result" { return result }
            return nil
        default:
            return locals[key] ?? globals[key]
        }
    }
}

public struct HypeTalkScriptBreakpoint: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var sourceKind: String
    public var objectId: UUID?
    public var handler: String?
    public var line: Int?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        sourceKind: String = "",
        objectId: UUID? = nil,
        handler: String? = nil,
        line: Int? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.objectId = objectId
        self.handler = handler
        self.line = line
        self.isEnabled = isEnabled
    }

    public func matches(_ entry: HypeTalkScriptTraceEntry) -> Bool {
        guard isEnabled else { return false }
        let normalizedKind = sourceKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedKind.isEmpty && normalizedKind != entry.source.kind.lowercased() { return false }
        if let objectId, objectId != entry.source.objectId { return false }
        if let handler, !handler.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           handler.lowercased() != entry.handler.lowercased() {
            return false
        }
        if let line, line > 0, line != entry.line { return false }
        return true
    }
}

public struct HypeTalkScriptWatchpoint: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var scope: String
    public var name: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        scope: String = "auto",
        name: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.scope = scope
        self.name = name
        self.isEnabled = isEnabled
    }
}

public struct HypeTalkScriptWatchpointHit: Sendable, Codable, Equatable {
    public var watchpointId: UUID
    public var scope: String
    public var name: String
    public var oldValue: String?
    public var newValue: String

    public init(watchpointId: UUID, scope: String, name: String, oldValue: String?, newValue: String) {
        self.watchpointId = watchpointId
        self.scope = scope
        self.name = name
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

public struct HypeTalkScriptPauseState: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var context: HypeTalkScriptTraceContext
    public var variables: HypeTalkVariableScopeSnapshot
    public var breakpointHits: [UUID]
    public var reason: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        context: HypeTalkScriptTraceContext,
        variables: HypeTalkVariableScopeSnapshot,
        breakpointHits: [UUID],
        reason: String = "breakpoint"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.context = context
        self.variables = variables
        self.breakpointHits = breakpointHits
        self.reason = reason
    }
}

public struct HypeTalkScriptTraceEntry: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var executionId: UUID?
    public var handlerExecutionId: UUID?
    public var message: String
    public var handler: String
    public var ownerDescription: String
    public var source: HypeTalkScriptTraceSource
    public var line: Int
    public var status: String
    public var durationMilliseconds: Double
    public var diagnostics: HypeTalkExecutionDiagnostics
    public var variables: HypeTalkVariableScopeSnapshot
    public var breakpointHits: [UUID]
    public var watchpointHits: [HypeTalkScriptWatchpointHit]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        executionId: UUID? = nil,
        handlerExecutionId: UUID? = nil,
        message: String,
        handler: String,
        ownerDescription: String,
        source: HypeTalkScriptTraceSource,
        line: Int,
        status: String,
        durationMilliseconds: Double,
        diagnostics: HypeTalkExecutionDiagnostics,
        variables: HypeTalkVariableScopeSnapshot = HypeTalkVariableScopeSnapshot(),
        breakpointHits: [UUID] = [],
        watchpointHits: [HypeTalkScriptWatchpointHit] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.executionId = executionId
        self.handlerExecutionId = handlerExecutionId
        self.message = message
        self.handler = handler
        self.ownerDescription = ownerDescription
        self.source = source
        self.line = line
        self.status = status
        self.durationMilliseconds = durationMilliseconds
        self.diagnostics = diagnostics
        self.variables = variables
        self.breakpointHits = breakpointHits
        self.watchpointHits = watchpointHits
    }
}

public struct HypeTalkRuntimeBudgetSummary: Sendable, Codable, Equatable {
    public static let defaultFrameBudgetMilliseconds = 16.67

    public var durationMilliseconds: Double
    public var budgetMilliseconds: Double
    public var budgetPercent: Double
    public var frameEquivalents: Double
    public var pressure: String

    public init(durationMilliseconds: Double, budgetMilliseconds: Double = Self.defaultFrameBudgetMilliseconds) {
        let normalizedBudget = max(0.001, budgetMilliseconds)
        self.durationMilliseconds = durationMilliseconds
        self.budgetMilliseconds = normalizedBudget
        self.budgetPercent = (durationMilliseconds / normalizedBudget) * 100.0
        self.frameEquivalents = durationMilliseconds / normalizedBudget
        switch self.budgetPercent {
        case ..<5:
            self.pressure = "minimal"
        case ..<25:
            self.pressure = "noticeable"
        case ..<75:
            self.pressure = "heavy"
        default:
            self.pressure = "over-budget"
        }
    }
}

public struct HypeTalkScriptTraceSnapshot: Sendable, Equatable {
    public var isEnabled: Bool
    public var entries: [HypeTalkScriptTraceEntry]
    public var breakpoints: [HypeTalkScriptBreakpoint]
    public var watchpoints: [HypeTalkScriptWatchpoint]
    public var pausedState: HypeTalkScriptPauseState?

    public init(
        isEnabled: Bool,
        entries: [HypeTalkScriptTraceEntry],
        breakpoints: [HypeTalkScriptBreakpoint] = [],
        watchpoints: [HypeTalkScriptWatchpoint] = [],
        pausedState: HypeTalkScriptPauseState? = nil
    ) {
        self.isEnabled = isEnabled
        self.entries = entries
        self.breakpoints = breakpoints
        self.watchpoints = watchpoints
        self.pausedState = pausedState
    }
}

public final class HypeTalkScriptTraceRecorder: @unchecked Sendable {
    public static let shared = HypeTalkScriptTraceRecorder()

    private let lock = NSLock()
    private var enabled = false
    private var entries: [HypeTalkScriptTraceEntry] = []
    private var breakpoints: [HypeTalkScriptBreakpoint] = []
    private var watchpoints: [HypeTalkScriptWatchpoint] = []
    private var lastWatchpointValues: [UUID: String] = [:]
    private var pausedState: HypeTalkScriptPauseState?
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private struct PendingStep {
        var reason: String
        var executionId: UUID
        var callDepth: Int
    }

    private var pendingStep: PendingStep?
    private var pendingTraceBreakpointHits: [UUID: [UUID]] = [:]
    private let maximumEntries = 2_000

    public init() {}

    public var isEnabled: Bool {
        lock.withLock { enabled }
    }

    public func setEnabled(_ enabled: Bool) {
        var continuation: CheckedContinuation<Void, Never>?
        lock.withLock {
            self.enabled = enabled
            if enabled {
                continuation = nil
            } else {
                continuation = pauseContinuation
                pauseContinuation = nil
                pausedState = nil
                pendingStep = nil
                pendingTraceBreakpointHits.removeAll(keepingCapacity: true)
            }
        }
        continuation?.resume()
    }

    public func pauseIfNeeded(
        context: HypeTalkScriptTraceContext,
        variables: HypeTalkVariableScopeSnapshot,
        lineBreakpointsOnly: Bool = false
    ) async -> Double {
        let started = Date()
        var didPause = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var shouldResumeImmediately = false
            lock.withLock {
                guard enabled, pausedState == nil else {
                    shouldResumeImmediately = true
                    return
                }
                let probe = HypeTalkScriptTraceEntry(
                    message: context.message,
                    handler: context.handler,
                    ownerDescription: context.ownerDescription,
                    source: context.source,
                    line: context.line,
                    status: "paused",
                    durationMilliseconds: 0,
                    diagnostics: HypeTalkExecutionDiagnostics(),
                    variables: variables
                )
                let breakpointHits = breakpoints
                    .filter { breakpoint in
                        if lineBreakpointsOnly, breakpoint.line == nil { return false }
                        return breakpoint.matches(probe)
                    }
                    .map(\.id)
                let stepMatches: Bool
                if let pendingStep, pendingStep.executionId == context.executionId {
                    stepMatches = pendingStep.reason == "stepInto"
                        || context.callDepth <= pendingStep.callDepth
                } else {
                    stepMatches = false
                }
                guard !breakpointHits.isEmpty || stepMatches else {
                    shouldResumeImmediately = true
                    return
                }
                let stepReason = stepMatches ? pendingStep?.reason : nil
                pendingStep = nil
                didPause = true
                pausedState = HypeTalkScriptPauseState(
                    context: context,
                    variables: variables,
                    breakpointHits: breakpointHits,
                    reason: breakpointHits.isEmpty ? (stepReason ?? "step") : "breakpoint"
                )
                if !breakpointHits.isEmpty {
                    pendingTraceBreakpointHits[context.handlerExecutionId, default: []]
                        .append(contentsOf: breakpointHits)
                }
                pauseContinuation = continuation
            }
            if didPause {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("hype.scriptDebuggerDidPause"), object: nil)
                }
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
        return didPause ? Date().timeIntervalSince(started) * 1000 : 0
    }

    public func resumePausedExecution() -> Bool {
        var continuation: CheckedContinuation<Void, Never>?
        var didResume = false
        lock.withLock {
            continuation = pauseContinuation
            didResume = pauseContinuation != nil || pausedState != nil
            pauseContinuation = nil
            pausedState = nil
        }
        continuation?.resume()
        return didResume
    }

    public func stepIntoPausedExecution() -> Bool {
        resumePausedExecution(stepReason: "stepInto")
    }

    public func stepOverPausedExecution() -> Bool {
        resumePausedExecution(stepReason: "stepOver")
    }

    private func resumePausedExecution(stepReason: String) -> Bool {
        var continuation: CheckedContinuation<Void, Never>?
        var didResume = false
        lock.withLock {
            continuation = pauseContinuation
            didResume = pauseContinuation != nil || pausedState != nil
            if didResume, let pausedState {
                pendingStep = PendingStep(
                    reason: stepReason,
                    executionId: pausedState.context.executionId,
                    callDepth: pausedState.context.callDepth
                )
            }
            pauseContinuation = nil
            pausedState = nil
        }
        continuation?.resume()
        return didResume
    }

    public func record(_ entry: HypeTalkScriptTraceEntry) {
        lock.withLock {
            guard enabled else { return }
            var annotatedEntry = entry
            let matchingBreakpointHits = breakpoints
                .filter { $0.matches(entry) }
                .map(\.id)
            let pendingHits = entry.handlerExecutionId.flatMap {
                pendingTraceBreakpointHits.removeValue(forKey: $0)
            } ?? []
            annotatedEntry.breakpointHits = stableUniqueBreakpointHits(pendingHits + matchingBreakpointHits)
            annotatedEntry.watchpointHits = watchpointHits(for: entry.variables)
            entries.append(annotatedEntry)
            if entries.count > maximumEntries {
                entries.removeFirst(entries.count - maximumEntries)
            }
        }
    }

    public func clear() {
        var continuation: CheckedContinuation<Void, Never>?
        lock.withLock {
            entries.removeAll(keepingCapacity: true)
            lastWatchpointValues.removeAll(keepingCapacity: true)
            continuation = pauseContinuation
            pauseContinuation = nil
            pausedState = nil
            pendingStep = nil
            pendingTraceBreakpointHits.removeAll(keepingCapacity: true)
        }
        continuation?.resume()
    }

    public func resetDebuggerState() {
        var continuation: CheckedContinuation<Void, Never>?
        lock.withLock {
            enabled = false
            entries.removeAll(keepingCapacity: true)
            breakpoints.removeAll(keepingCapacity: true)
            watchpoints.removeAll(keepingCapacity: true)
            lastWatchpointValues.removeAll(keepingCapacity: true)
            continuation = pauseContinuation
            pauseContinuation = nil
            pausedState = nil
            pendingStep = nil
            pendingTraceBreakpointHits.removeAll(keepingCapacity: true)
        }
        continuation?.resume()
    }

    public func addBreakpoint(_ breakpoint: HypeTalkScriptBreakpoint) -> HypeTalkScriptBreakpoint {
        lock.withLock {
            breakpoints.append(breakpoint)
            return breakpoint
        }
    }

    public func removeBreakpoint(id: UUID) {
        lock.withLock {
            breakpoints.removeAll { $0.id == id }
        }
    }

    public func setBreakpoints(_ breakpoints: [HypeTalkScriptBreakpoint]) {
        lock.withLock {
            self.breakpoints = breakpoints
        }
    }

    private func stableUniqueBreakpointHits(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        var result: [UUID] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    public func addWatchpoint(_ watchpoint: HypeTalkScriptWatchpoint) -> HypeTalkScriptWatchpoint {
        lock.withLock {
            watchpoints.append(watchpoint)
            if let value = HypeTalkScriptTraceRecorder.latestVariables(in: entries).value(scope: watchpoint.scope, name: watchpoint.name) {
                lastWatchpointValues[watchpoint.id] = value
            }
            return watchpoint
        }
    }

    public func removeWatchpoint(id: UUID) {
        lock.withLock {
            watchpoints.removeAll { $0.id == id }
            lastWatchpointValues.removeValue(forKey: id)
        }
    }

    public func setWatchpoints(_ watchpoints: [HypeTalkScriptWatchpoint]) {
        lock.withLock {
            self.watchpoints = watchpoints
            let latestVariables = HypeTalkScriptTraceRecorder.latestVariables(in: entries)
            lastWatchpointValues = watchpoints.reduce(into: [UUID: String]()) { values, watchpoint in
                if let value = latestVariables.value(scope: watchpoint.scope, name: watchpoint.name) {
                    values[watchpoint.id] = value
                }
            }
        }
    }

    public func snapshot() -> HypeTalkScriptTraceSnapshot {
        lock.withLock {
            HypeTalkScriptTraceSnapshot(
                isEnabled: enabled,
                entries: entries,
                breakpoints: breakpoints,
                watchpoints: watchpoints,
                pausedState: pausedState
            )
        }
    }

    private func watchpointHits(for variables: HypeTalkVariableScopeSnapshot) -> [HypeTalkScriptWatchpointHit] {
        var hits: [HypeTalkScriptWatchpointHit] = []
        for watchpoint in watchpoints where watchpoint.isEnabled {
            guard let value = variables.value(scope: watchpoint.scope, name: watchpoint.name) else { continue }
            let previousValue = lastWatchpointValues[watchpoint.id]
            lastWatchpointValues[watchpoint.id] = value
            if let previousValue, previousValue != value {
                hits.append(
                    HypeTalkScriptWatchpointHit(
                        watchpointId: watchpoint.id,
                        scope: watchpoint.scope,
                        name: watchpoint.name,
                        oldValue: previousValue,
                        newValue: value
                    )
                )
            }
        }
        return hits
    }

    private static func latestVariables(in entries: [HypeTalkScriptTraceEntry]) -> HypeTalkVariableScopeSnapshot {
        entries.last?.variables ?? HypeTalkVariableScopeSnapshot()
    }
}

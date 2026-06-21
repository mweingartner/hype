import Foundation
import Testing
@testable import HypeCore

@Suite("HypeTalk script trace recorder")
struct HypeTalkScriptTraceRecorderTests {
    @Test("records only while enabled and clears entries")
    func recordsOnlyWhileEnabledAndClears() {
        let recorder = HypeTalkScriptTraceRecorder()
        let entry = HypeTalkScriptTraceEntry(
            message: "mouseUp",
            handler: "mouseUp",
            ownerDescription: "button \"Run\"",
            source: HypeTalkScriptTraceSource(kind: "part", objectId: UUID()),
            line: 1,
            status: "completed",
            durationMilliseconds: 1.25,
            diagnostics: HypeTalkExecutionDiagnostics(statements: 3, expressions: 2)
        )

        recorder.record(entry)
        #expect(recorder.snapshot().entries.isEmpty)

        recorder.setEnabled(true)
        recorder.record(entry)

        let snapshot = recorder.snapshot()
        #expect(snapshot.isEnabled)
        #expect(snapshot.entries == [entry])

        recorder.clear()
        #expect(recorder.snapshot().entries.isEmpty)
    }

    @Test("runtime budget summary describes script frame pressure")
    func runtimeBudgetSummaryDescribesFramePressure() {
        let minimal = HypeTalkRuntimeBudgetSummary(durationMilliseconds: 0.4, budgetMilliseconds: 16.0)
        #expect(minimal.pressure == "minimal")
        #expect(abs(minimal.budgetPercent - 2.5) < 0.001)
        #expect(abs(minimal.frameEquivalents - 0.025) < 0.001)

        let overBudget = HypeTalkRuntimeBudgetSummary(durationMilliseconds: 32.0, budgetMilliseconds: 16.0)
        #expect(overBudget.pressure == "over-budget")
        #expect(abs(overBudget.budgetPercent - 200.0) < 0.001)
        #expect(abs(overBudget.frameEquivalents - 2.0) < 0.001)
    }

    @Test("breakpoints annotate matching trace entries")
    func breakpointsAnnotateMatchingEntries() throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        let sourceId = UUID()
        let breakpoint = recorder.addBreakpoint(
            HypeTalkScriptBreakpoint(
                sourceKind: "part",
                objectId: sourceId,
                handler: "mouseUp",
                line: 4
            )
        )

        recorder.record(
            HypeTalkScriptTraceEntry(
                message: "mouseUp",
                handler: "mouseUp",
                ownerDescription: "button \"Run\"",
                source: HypeTalkScriptTraceSource(kind: "part", objectId: sourceId),
                line: 4,
                status: "completed",
                durationMilliseconds: 1,
                diagnostics: HypeTalkExecutionDiagnostics()
            )
        )

        let entry = try #require(recorder.snapshot().entries.last)
        #expect(entry.breakpointHits == [breakpoint.id])
    }

    @Test("watchpoints fire only after a scoped variable changes")
    func watchpointsFireAfterScopedVariableChanges() throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        let watchpoint = recorder.addWatchpoint(HypeTalkScriptWatchpoint(scope: "local", name: "count"))

        let source = HypeTalkScriptTraceSource(kind: "part", objectId: UUID())
        recorder.record(
            HypeTalkScriptTraceEntry(
                message: "mouseUp",
                handler: "mouseUp",
                ownerDescription: "button \"Run\"",
                source: source,
                line: 1,
                status: "completed",
                durationMilliseconds: 1,
                diagnostics: HypeTalkExecutionDiagnostics(),
                variables: HypeTalkVariableScopeSnapshot(locals: ["count": "1"])
            )
        )
        #expect(recorder.snapshot().entries.last?.watchpointHits.isEmpty == true)

        recorder.record(
            HypeTalkScriptTraceEntry(
                message: "mouseUp",
                handler: "mouseUp",
                ownerDescription: "button \"Run\"",
                source: source,
                line: 1,
                status: "completed",
                durationMilliseconds: 1,
                diagnostics: HypeTalkExecutionDiagnostics(),
                variables: HypeTalkVariableScopeSnapshot(locals: ["count": "2"])
            )
        )

        let hit = try #require(recorder.snapshot().entries.last?.watchpointHits.first)
        #expect(hit.watchpointId == watchpoint.id)
        #expect(hit.oldValue == "1")
        #expect(hit.newValue == "2")
    }

    @Test("message dispatch records handler trace with profiling data")
    func dispatchRecordsHandlerTrace() async throws {
        let recorder = HypeTalkScriptTraceRecorder()

        var document = HypeDocument.newDocument()
        let cardId = try #require(document.sortedCards.first?.id)
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = """
        on mouseUp
          put "ok" into gResult
        end mouseUp
        """
        document.addPart(button)

        recorder.setEnabled(true)

        _ = await MessageDispatcher(scriptTraceRecorder: recorder).dispatchAsync(
            message: "mouseUp",
            params: [],
            targetId: button.id,
            document: document,
            currentCardId: cardId
        )

        let entry = try #require(recorder.snapshot().entries.last)
        #expect(entry.message == "mouseUp")
        #expect(entry.handler == "mouseUp")
        #expect(entry.source.kind == "part")
        #expect(entry.source.objectId == button.id)
        #expect(entry.status == "completed")
        #expect(entry.durationMilliseconds >= 0)
        #expect(entry.diagnostics.handlerInvocations == 1)
        #expect(entry.diagnostics.statements >= 1)
        #expect(entry.variables.locals["gresult"] == "ok")
    }

    @Test("breakpoint halts dispatch before handler body and resumes with inspected state")
    func breakpointHaltsDispatchBeforeHandlerBody() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        defer { _ = recorder.resumePausedExecution() }

        var document = HypeDocument.newDocument()
        document.scriptGlobals["gFlag"] = "before"
        let cardId = try #require(document.sortedCards.first?.id)
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = """
        on mouseUp
          global gFlag
          put "after" into gFlag
        end mouseUp
        """
        document.addPart(button)

        _ = recorder.addBreakpoint(
            HypeTalkScriptBreakpoint(
                sourceKind: "part",
                objectId: button.id,
                handler: "mouseUp"
            )
        )
        recorder.setEnabled(true)

        let dispatchTask = Task {
            await MessageDispatcher(scriptTraceRecorder: recorder).dispatchAsync(
                message: "mouseUp",
                params: [],
                targetId: button.id,
                document: document,
                currentCardId: cardId
            )
        }

        let pause = try await waitForPause(recorder)
        #expect(pause.context.handler == "mouseUp")
        #expect(pause.variables.globals["gflag"] == "before")
        #expect(pause.breakpointHits.count == 1)
        #expect(recorder.snapshot().entries.isEmpty)

        #expect(recorder.resumePausedExecution())
        let result = await dispatchTask.value
        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.scriptGlobals["gflag"] == "after")
        #expect(recorder.snapshot().pausedState == nil)

        let entry = try #require(recorder.snapshot().entries.last)
        #expect(entry.breakpointHits == pause.breakpointHits)
        #expect(entry.variables.globals["gflag"] == "after")
    }

    @Test("step into resumes paused execution and halts at next handler entry")
    func stepIntoResumesAndHaltsAtNextHandlerEntry() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        defer { _ = recorder.resumePausedExecution() }

        let sourceId = UUID()
        _ = recorder.addBreakpoint(
            HypeTalkScriptBreakpoint(sourceKind: "part", objectId: sourceId, handler: "mouseUp", line: 1)
        )
        recorder.setEnabled(true)

        let firstPause = Task {
            await recorder.pauseIfNeeded(
                context: HypeTalkScriptTraceContext(
                    message: "mouseUp",
                    handler: "mouseUp",
                    ownerDescription: "button \"Run\"",
                    source: HypeTalkScriptTraceSource(kind: "part", objectId: sourceId),
                    line: 1
                ),
                variables: HypeTalkVariableScopeSnapshot()
            )
        }
        _ = try await waitForPause(recorder)
        #expect(recorder.stepIntoPausedExecution())
        _ = await firstPause.value

        let secondPause = Task {
            await recorder.pauseIfNeeded(
                context: HypeTalkScriptTraceContext(
                    message: "openCard",
                    handler: "openCard",
                    ownerDescription: "card \"Next\"",
                    source: HypeTalkScriptTraceSource(kind: "card", objectId: UUID()),
                    line: 1
                ),
                variables: HypeTalkVariableScopeSnapshot(locals: ["step": "next"])
            )
        }
        let pause = try await waitForPause(recorder)
        #expect(pause.reason == "stepInto")
        #expect(pause.breakpointHits.isEmpty)
        #expect(pause.variables.locals["step"] == "next")
        #expect(recorder.resumePausedExecution())
        _ = await secondPause.value
    }

    @Test("execution controls are no-ops when nothing is paused")
    func executionControlsAreNoOpsWhenNothingIsPaused() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)

        #expect(!recorder.resumePausedExecution())
        #expect(!recorder.stepIntoPausedExecution())
        #expect(!recorder.stepOverPausedExecution())

        let elapsed = await recorder.pauseIfNeeded(
            context: traceContext(handler: "mouseUp", line: 1),
            variables: HypeTalkVariableScopeSnapshot()
        )
        #expect(elapsed == 0)
        #expect(recorder.snapshot().pausedState == nil)
    }

    @Test("non-matching breakpoints do not halt execution")
    func nonMatchingBreakpointsDoNotHaltExecution() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        _ = recorder.addBreakpoint(
            HypeTalkScriptBreakpoint(
                sourceKind: "part",
                objectId: UUID(),
                handler: "mouseUp",
                line: 7
            )
        )

        let elapsed = await recorder.pauseIfNeeded(
            context: traceContext(handler: "openCard", line: 1),
            variables: HypeTalkVariableScopeSnapshot()
        )

        #expect(elapsed == 0)
        #expect(recorder.snapshot().pausedState == nil)
    }

    @Test("continue releases a breakpoint pause without scheduling a step")
    func continueReleasesBreakpointPauseWithoutSchedulingStep() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        _ = recorder.addBreakpoint(HypeTalkScriptBreakpoint(sourceKind: "part", handler: "mouseUp", line: 1))

        let pauseTask = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "mouseUp", line: 1),
                variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "break"])
            )
        }
        let pause = try await waitForPause(recorder)
        #expect(pause.reason == "breakpoint")
        #expect(recorder.resumePausedExecution())
        _ = await pauseTask.value

        let elapsed = await recorder.pauseIfNeeded(
            context: traceContext(handler: "nextHandler", line: 2),
            variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "next"])
        )
        #expect(elapsed == 0)
        #expect(recorder.snapshot().pausedState == nil)
    }

    @Test("step into is one-shot and uses the next handler entry")
    func stepIntoIsOneShot() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        _ = recorder.addBreakpoint(HypeTalkScriptBreakpoint(sourceKind: "part", handler: "mouseUp", line: 1))

        let firstPause = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "mouseUp", line: 1),
                variables: HypeTalkVariableScopeSnapshot()
            )
        }
        _ = try await waitForPause(recorder)
        #expect(recorder.stepIntoPausedExecution())
        _ = await firstPause.value

        let secondPause = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "openCard", line: 2),
                variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "stepped"])
            )
        }
        let pause = try await waitForPause(recorder)
        #expect(pause.reason == "stepInto")
        #expect(pause.breakpointHits.isEmpty)
        #expect(pause.variables.locals["phase"] == "stepped")
        #expect(recorder.resumePausedExecution())
        _ = await secondPause.value

        let elapsed = await recorder.pauseIfNeeded(
            context: traceContext(handler: "thirdHandler", line: 3),
            variables: HypeTalkVariableScopeSnapshot()
        )
        #expect(elapsed == 0)
        #expect(recorder.snapshot().pausedState == nil)
    }

    @Test("step over reports a distinct pause reason")
    func stepOverReportsDistinctPauseReason() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        _ = recorder.addBreakpoint(HypeTalkScriptBreakpoint(sourceKind: "part", handler: "mouseUp", line: 1))

        let firstPause = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "mouseUp", line: 1),
                variables: HypeTalkVariableScopeSnapshot()
            )
        }
        _ = try await waitForPause(recorder)
        #expect(recorder.stepOverPausedExecution())
        _ = await firstPause.value

        let secondPause = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "openCard", line: 2),
                variables: HypeTalkVariableScopeSnapshot()
            )
        }
        let pause = try await waitForPause(recorder)
        #expect(pause.reason == "stepOver")
        #expect(recorder.resumePausedExecution())
        _ = await secondPause.value
    }

    @Test("breakpoint match takes precedence over pending step reason")
    func breakpointTakesPrecedenceOverPendingStepReason() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        _ = recorder.addBreakpoint(HypeTalkScriptBreakpoint(sourceKind: "part", handler: "mouseUp", line: 1))
        let secondBreakpoint = recorder.addBreakpoint(
            HypeTalkScriptBreakpoint(sourceKind: "part", handler: "openCard", line: 2)
        )

        let firstPause = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "mouseUp", line: 1),
                variables: HypeTalkVariableScopeSnapshot()
            )
        }
        _ = try await waitForPause(recorder)
        #expect(recorder.stepIntoPausedExecution())
        _ = await firstPause.value

        let secondPause = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "openCard", line: 2),
                variables: HypeTalkVariableScopeSnapshot()
            )
        }
        let pause = try await waitForPause(recorder)
        #expect(pause.reason == "breakpoint")
        #expect(pause.breakpointHits == [secondBreakpoint.id])
        #expect(recorder.resumePausedExecution())
        _ = await secondPause.value
    }

    @Test("clear and disabling tracing release halted execution")
    func clearAndDisableReleaseHaltedExecution() async throws {
        try await assertPausedExecutionIsReleased { recorder in
            recorder.clear()
        }
        try await assertPausedExecutionIsReleased { recorder in
            recorder.setEnabled(false)
        }
    }

    @Test("reset releases halted execution and clears debugger state")
    func resetReleasesHaltedExecutionAndClearsDebuggerState() async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        _ = recorder.addBreakpoint(HypeTalkScriptBreakpoint(sourceKind: "part", handler: "mouseUp", line: 1))
        _ = recorder.addWatchpoint(HypeTalkScriptWatchpoint(scope: "local", name: "phase"))
        recorder.record(
            HypeTalkScriptTraceEntry(
                message: "mouseUp",
                handler: "mouseUp",
                ownerDescription: "button \"Run\"",
                source: HypeTalkScriptTraceSource(kind: "part", objectId: UUID()),
                line: 1,
                status: "completed",
                durationMilliseconds: 1,
                diagnostics: HypeTalkExecutionDiagnostics(),
                variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "before"])
            )
        )

        let pauseTask = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "mouseUp", line: 1),
                variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "paused"])
            )
        }
        _ = try await waitForPause(recorder)

        recorder.resetDebuggerState()
        _ = await pauseTask.value

        let snapshot = recorder.snapshot()
        #expect(!snapshot.isEnabled)
        #expect(snapshot.entries.isEmpty)
        #expect(snapshot.breakpoints.isEmpty)
        #expect(snapshot.watchpoints.isEmpty)
        #expect(snapshot.pausedState == nil)
    }

    private func waitForPause(
        _ recorder: HypeTalkScriptTraceRecorder,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> HypeTalkScriptPauseState {
        for _ in 0..<100 {
            if let pause = recorder.snapshot().pausedState {
                return pause
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Expected script execution to halt at breakpoint", sourceLocation: sourceLocation)
        throw PauseWaitError.timedOut
    }

    private func traceContext(
        sourceId: UUID = UUID(),
        handler: String,
        line: Int
    ) -> HypeTalkScriptTraceContext {
        HypeTalkScriptTraceContext(
            message: handler,
            handler: handler,
            ownerDescription: "button \"Run\"",
            source: HypeTalkScriptTraceSource(kind: "part", objectId: sourceId),
            line: line
        )
    }

    private func assertPausedExecutionIsReleased(
        by release: @escaping @Sendable (HypeTalkScriptTraceRecorder) -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let recorder = HypeTalkScriptTraceRecorder()
        recorder.setEnabled(true)
        _ = recorder.addBreakpoint(HypeTalkScriptBreakpoint(sourceKind: "part", handler: "mouseUp", line: 1))

        let pauseTask = Task {
            await recorder.pauseIfNeeded(
                context: traceContext(handler: "mouseUp", line: 1),
                variables: HypeTalkVariableScopeSnapshot()
            )
        }
        _ = try await waitForPause(recorder, sourceLocation: sourceLocation)
        release(recorder)
        _ = await pauseTask.value
        #expect(recorder.snapshot().pausedState == nil, sourceLocation: sourceLocation)
    }

    private enum PauseWaitError: Error {
        case timedOut
    }
}

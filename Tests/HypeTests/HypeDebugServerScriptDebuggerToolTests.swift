import Foundation
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("HypeDebugServer script debugger MCP tool hookup", .serialized)
struct HypeDebugServerScriptDebuggerToolTests {
    @Test("set tracing toggles the shared recorder for the future MCP control tool")
    func setTracingTogglesRecorder() async {
        await HypeDebugServerTestIsolation.shared.withMainActorLock {
            HypeTalkScriptTraceRecorder.shared.resetDebuggerState()
            defer { HypeTalkScriptTraceRecorder.shared.resetDebuggerState() }

            let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_set_script_tracing",
                arguments: ["enabled": .bool(true)]
            )

            #expect(result.isError == false)
            #expect(result.text.contains("\"isEnabled\" : true"))
        }
    }

    @Test("state returns newest trace entries with budget and diagnostics")
    func stateReturnsTraceEntries() async {
        await HypeDebugServerTestIsolation.shared.withMainActorLock {
            HypeTalkScriptTraceRecorder.shared.resetDebuggerState()
            defer { HypeTalkScriptTraceRecorder.shared.resetDebuggerState() }
            HypeTalkScriptTraceRecorder.shared.setEnabled(true)
            HypeTalkScriptTraceRecorder.shared.record(traceEntry(handler: "first", duration: 2, statements: 1))
            HypeTalkScriptTraceRecorder.shared.record(traceEntry(handler: "second", duration: 8, statements: 3))

            let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_get_script_debugger_state",
                arguments: [
                    "max_entries": .number(1),
                    "frame_budget_ms": .number(4),
                    "include_diagnostics": .bool(true),
                ]
            )

            #expect(result.isError == false)
            #expect(result.text.contains("\"entryCount\" : 2"))
            #expect(result.text.contains("\"returnedEntryCount\" : 1"))
            #expect(result.text.contains("\"handler\" : \"second\""))
            #expect(!result.text.contains("\"handler\" : \"first\""))
            #expect(result.text.contains("\"pressure\" : \"over-budget\""))
            #expect(result.text.contains("\"statements\" : 3"))
        }
    }

    @Test("clear removes recorded trace entries")
    func clearRemovesTraceEntries() async {
        await HypeDebugServerTestIsolation.shared.withMainActorLock {
            HypeTalkScriptTraceRecorder.shared.resetDebuggerState()
            defer { HypeTalkScriptTraceRecorder.shared.resetDebuggerState() }
            HypeTalkScriptTraceRecorder.shared.setEnabled(true)
            HypeTalkScriptTraceRecorder.shared.record(traceEntry(handler: "mouseUp", duration: 1, statements: 1))

            let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_clear_script_trace",
                arguments: [:]
            )

            #expect(result.isError == false)
            #expect(result.text.contains("\"entryCount\" : 0"))
        }
    }

    @Test("state returns breakpoints watchpoints and scoped variables")
    func stateReturnsDebuggerControlsAndVariables() async {
        await HypeDebugServerTestIsolation.shared.withMainActorLock {
            HypeTalkScriptTraceRecorder.shared.resetDebuggerState()
            defer { HypeTalkScriptTraceRecorder.shared.resetDebuggerState() }

            let breakpointResult = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_add_script_breakpoint",
                arguments: [
                    "source_kind": .string("part"),
                    "handler": .string("mouseUp"),
                    "line": .number(1),
                ]
            )
            let watchpointResult = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_add_script_watchpoint",
                arguments: [
                    "scope": .string("global"),
                    "name": .string("gCount"),
                ]
            )

            #expect(breakpointResult.isError == false)
            #expect(watchpointResult.isError == false)

            HypeTalkScriptTraceRecorder.shared.setEnabled(true)
            HypeTalkScriptTraceRecorder.shared.record(
                traceEntry(
                    handler: "mouseUp",
                    duration: 2,
                    statements: 1,
                    variables: HypeTalkVariableScopeSnapshot(
                        locals: ["localcount": "3"],
                        globals: ["gcount": "7"],
                        it: "done"
                    )
                )
            )

            let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_get_script_debugger_state",
                arguments: ["max_entries": .number(1)]
            )

            #expect(result.isError == false)
            #expect(result.text.contains("\"breakpoints\""))
            #expect(result.text.contains("\"watchpoints\""))
            #expect(result.text.contains("\"variables\""))
            #expect(result.text.contains("\"localcount\" : \"3\""))
            #expect(result.text.contains("\"gcount\" : \"7\""))
        }
    }

    @Test("state reports halted execution and resume continues it")
    func stateReportsPausedExecutionAndResumeContinuesIt() async throws {
        try await HypeDebugServerTestIsolation.shared.withMainActorLock {
            HypeTalkScriptTraceRecorder.shared.resetDebuggerState()
            defer { HypeTalkScriptTraceRecorder.shared.resetDebuggerState() }

            let sourceId = UUID()
            _ = HypeTalkScriptTraceRecorder.shared.addBreakpoint(
                HypeTalkScriptBreakpoint(sourceKind: "part", objectId: sourceId, handler: "mouseUp", line: 1)
            )
            HypeTalkScriptTraceRecorder.shared.setEnabled(true)

            let pauseTask = Task {
                await HypeTalkScriptTraceRecorder.shared.pauseIfNeeded(
                    context: HypeTalkScriptTraceContext(
                        message: "mouseUp",
                        handler: "mouseUp",
                        ownerDescription: "button \"Run\"",
                        source: HypeTalkScriptTraceSource(kind: "part", objectId: sourceId),
                        line: 1
                    ),
                    variables: HypeTalkVariableScopeSnapshot(locals: ["step": "entry"], globals: ["gflag": "before"])
                )
            }

            try await waitForPause()

            let state = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_get_script_debugger_state",
                arguments: [:]
            )
            #expect(state.isError == false)
            #expect(state.text.contains("\"pausedState\""))
            #expect(state.text.contains("\"step\" : \"entry\""))
            #expect(state.text.contains("\"gflag\" : \"before\""))

            let resume = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_resume_script_execution",
                arguments: [:]
            )
            #expect(resume.isError == false)
            #expect(resume.text.contains("\"resumed\" : true"))

            let pausedMilliseconds = await pauseTask.value
            #expect(pausedMilliseconds >= 0)
            #expect(HypeTalkScriptTraceRecorder.shared.snapshot().pausedState == nil)
        }
    }

    @Test("step control tools resume halted execution")
    func stepControlToolsResumePausedExecution() async throws {
        try await HypeDebugServerTestIsolation.shared.withMainActorLock {
            try await expectStepToolResumesPausedExecution(
                toolName: "hype_step_into_script_execution",
                expectedMessage: "Script execution stepped into."
            )
            try await expectStepToolResumesPausedExecution(
                toolName: "hype_step_over_script_execution",
                expectedMessage: "Script execution stepped over."
            )
        }
    }

    @Test("open trace source validates source arguments before posting editor request")
    func openTraceSourceValidatesArguments() async {
        await HypeDebugServerTestIsolation.shared.withMainActorLock {
            let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
                name: "hype_open_script_trace_source",
                arguments: ["source_kind": .string("part")]
            )

            #expect(result.isError == true)
            #expect(result.text.contains("Unsupported trace source kind"))
        }
    }

    private func traceEntry(
        handler: String,
        duration: Double,
        statements: Int,
        variables: HypeTalkVariableScopeSnapshot = HypeTalkVariableScopeSnapshot()
    ) -> HypeTalkScriptTraceEntry {
        HypeTalkScriptTraceEntry(
            message: "mouseUp",
            handler: handler,
            ownerDescription: "button \"Run\"",
            source: HypeTalkScriptTraceSource(kind: "part", objectId: UUID()),
            line: 1,
            status: "success",
            durationMilliseconds: duration,
            diagnostics: HypeTalkExecutionDiagnostics(statements: statements),
            variables: variables
        )
    }

    private func waitForPause(
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        for _ in 0..<100 {
            if HypeTalkScriptTraceRecorder.shared.snapshot().pausedState != nil {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Expected script execution to halt at breakpoint", sourceLocation: sourceLocation)
        throw PauseWaitError.timedOut
    }

    private func expectStepToolResumesPausedExecution(
        toolName: String,
        expectedMessage: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        HypeTalkScriptTraceRecorder.shared.resetDebuggerState()
        defer { HypeTalkScriptTraceRecorder.shared.resetDebuggerState() }

        let sourceId = UUID()
        _ = HypeTalkScriptTraceRecorder.shared.addBreakpoint(
            HypeTalkScriptBreakpoint(sourceKind: "part", objectId: sourceId, handler: "mouseUp", line: 1)
        )
        HypeTalkScriptTraceRecorder.shared.setEnabled(true)

        let pauseTask = Task {
            await HypeTalkScriptTraceRecorder.shared.pauseIfNeeded(
                context: HypeTalkScriptTraceContext(
                    message: "mouseUp",
                    handler: "mouseUp",
                    ownerDescription: "button \"Run\"",
                    source: HypeTalkScriptTraceSource(kind: "part", objectId: sourceId),
                    line: 1
                ),
                variables: HypeTalkVariableScopeSnapshot(locals: ["step": toolName])
            )
        }

        try await waitForPause(sourceLocation: sourceLocation)

        let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
            name: toolName,
            arguments: [:]
        )
        #expect(result.isError == false, sourceLocation: sourceLocation)
        #expect(result.text.contains("\"resumed\" : true"), sourceLocation: sourceLocation)
        #expect(result.text.contains(expectedMessage), sourceLocation: sourceLocation)

        _ = await pauseTask.value
        #expect(HypeTalkScriptTraceRecorder.shared.snapshot().pausedState == nil, sourceLocation: sourceLocation)
    }

    private enum PauseWaitError: Error {
        case timedOut
    }
}

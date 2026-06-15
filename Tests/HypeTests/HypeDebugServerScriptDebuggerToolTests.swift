import Foundation
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("HypeDebugServer script debugger MCP tool hookup")
struct HypeDebugServerScriptDebuggerToolTests {
    @Test("set tracing toggles the shared recorder for the future MCP control tool")
    func setTracingTogglesRecorder() {
        HypeTalkScriptTraceRecorder.shared.setEnabled(false)
        HypeTalkScriptTraceRecorder.shared.clear()
        defer {
            HypeTalkScriptTraceRecorder.shared.setEnabled(false)
            HypeTalkScriptTraceRecorder.shared.clear()
        }

        let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
            name: "hype_set_script_tracing",
            arguments: ["enabled": .bool(true)]
        )

        #expect(result.isError == false)
        #expect(result.text.contains("\"isEnabled\" : true"))
    }

    @Test("state returns newest trace entries with budget and diagnostics")
    func stateReturnsTraceEntries() throws {
        HypeTalkScriptTraceRecorder.shared.setEnabled(false)
        HypeTalkScriptTraceRecorder.shared.clear()
        defer {
            HypeTalkScriptTraceRecorder.shared.setEnabled(false)
            HypeTalkScriptTraceRecorder.shared.clear()
        }
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

    @Test("clear removes recorded trace entries")
    func clearRemovesTraceEntries() {
        HypeTalkScriptTraceRecorder.shared.setEnabled(true)
        HypeTalkScriptTraceRecorder.shared.record(traceEntry(handler: "mouseUp", duration: 1, statements: 1))
        defer {
            HypeTalkScriptTraceRecorder.shared.setEnabled(false)
            HypeTalkScriptTraceRecorder.shared.clear()
        }

        let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
            name: "hype_clear_script_trace",
            arguments: [:]
        )

        #expect(result.isError == false)
        #expect(result.text.contains("\"entryCount\" : 0"))
    }

    @Test("open trace source validates source arguments before posting editor request")
    func openTraceSourceValidatesArguments() {
        let result = HypeDebugServer.shared.callScriptDebuggerControlTool(
            name: "hype_open_script_trace_source",
            arguments: ["source_kind": .string("part")]
        )

        #expect(result.isError == true)
        #expect(result.text.contains("Unsupported trace source kind"))
    }

    private func traceEntry(handler: String, duration: Double, statements: Int) -> HypeTalkScriptTraceEntry {
        HypeTalkScriptTraceEntry(
            message: "mouseUp",
            handler: handler,
            ownerDescription: "button \"Run\"",
            source: HypeTalkScriptTraceSource(kind: "part", objectId: UUID()),
            line: 1,
            status: "success",
            durationMilliseconds: duration,
            diagnostics: HypeTalkExecutionDiagnostics(statements: statements)
        )
    }
}

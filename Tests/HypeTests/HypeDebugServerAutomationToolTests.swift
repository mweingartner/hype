import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("HypeDebugServer automation tools", .serialized)
struct HypeDebugServerAutomationToolTests {
    @Test("window automation lists and focuses Hype windows without AX")
    func windowAutomationListsAndFocusesWindows() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Automation Probe Script Debugger"
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        let list = HypeDebugServer.shared.callWindowAutomationControlTool(
            name: "hype_list_windows",
            arguments: [:]
        )

        #expect(list.isError == false)
        #expect(list.text.contains("Automation Probe Script Debugger"))
        #expect(list.text.contains("\"kind\" : \"script_debugger\""))

        let focus = HypeDebugServer.shared.callWindowAutomationControlTool(
            name: "hype_focus_window",
            arguments: ["title": .string("Automation Probe")]
        )

        #expect(focus.isError == false)
        #expect(focus.text.contains("\"result\" : \"Window focused.\""))

        let wait = await HypeDebugServer.shared.callWindowWaitControlTool(
            name: "hype_wait_for_window",
            arguments: [
                "title": .string("Automation Probe"),
                "timeout_ms": .number(250),
            ]
        )

        #expect(wait.isError == false)
        #expect(wait.text.contains("\"matched\" : true"))
    }

    @Test("debugger wait tool returns the current pause state")
    func debuggerWaitReturnsPauseState() async throws {
        try await HypeDebugServerTestIsolation.shared.withMainActorLock {
            resetRecorder()
            defer { resetRecorder() }

            let sourceId = UUID()
            _ = HypeTalkScriptTraceRecorder.shared.addBreakpoint(
                HypeTalkScriptBreakpoint(sourceKind: "part", objectId: sourceId, handler: "mouseUp", line: 1)
            )
            HypeTalkScriptTraceRecorder.shared.setEnabled(true)

            let pauseTask = Task {
                await HypeTalkScriptTraceRecorder.shared.pauseIfNeeded(
                    context: traceContext(sourceId: sourceId, handler: "mouseUp", line: 1),
                    variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "initial"])
                )
            }

            try await waitUntilPaused()

            let result = await HypeDebugServer.shared.callDebuggerWaitControlTool(
                name: "hype_wait_for_debugger_pause",
                arguments: [
                    "reason": .string("breakpoint"),
                    "handler": .string("mouseUp"),
                    "timeout_ms": .number(250),
                ]
            )

            #expect(result.isError == false)
            #expect(result.text.contains("\"matched\" : true"))
            #expect(result.text.contains("\"phase\" : \"initial\""))

            _ = HypeTalkScriptTraceRecorder.shared.resumePausedExecution()
            _ = await pauseTask.value
        }
    }

    @Test("step and wait resumes then reports the next pause")
    func stepAndWaitReportsNextPause() async throws {
        try await HypeDebugServerTestIsolation.shared.withMainActorLock {
            resetRecorder()
            defer { resetRecorder() }

            let sourceId = UUID()
            _ = HypeTalkScriptTraceRecorder.shared.addBreakpoint(
                HypeTalkScriptBreakpoint(sourceKind: "part", objectId: sourceId, handler: "mouseUp", line: 1)
            )
            HypeTalkScriptTraceRecorder.shared.setEnabled(true)

            let firstPause = Task {
                await HypeTalkScriptTraceRecorder.shared.pauseIfNeeded(
                    context: traceContext(sourceId: sourceId, handler: "mouseUp", line: 1),
                    variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "first"])
                )
            }
            try await waitUntilPaused()

            let stepWait = Task {
                await HypeDebugServer.shared.callDebuggerWaitControlTool(
                    name: "hype_step_script_execution_and_wait",
                    arguments: [
                        "step": .string("into"),
                        "reason": .string("stepInto"),
                        "timeout_ms": .number(1_000),
                    ]
                )
            }
            _ = await firstPause.value

            let secondPause = Task {
                await HypeTalkScriptTraceRecorder.shared.pauseIfNeeded(
                    context: traceContext(sourceId: sourceId, handler: "nextHandler", line: 2),
                    variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "second"])
                )
            }

            let result = await stepWait.value
            #expect(result.isError == false)
            #expect(result.text.contains("\"resumed\" : true"))
            #expect(result.text.contains("\"reason\" : \"stepInto\""))
            #expect(result.text.contains("\"phase\" : \"second\""))

            _ = HypeTalkScriptTraceRecorder.shared.resumePausedExecution()
            _ = await secondPause.value
        }
    }

    @Test("script editor automation toggles and reports line breakpoints")
    func scriptEditorAutomationTogglesBreakpoints() async throws {
        try await HypeDebugServerTestIsolation.shared.withMainActorLock {
            resetRecorder()
            var document = HypeDocument.newDocument(name: "Editor Automation")
            let cardId = try #require(document.sortedCards.first?.id)
            var button = Part(partType: .button, cardId: cardId, name: "Run")
            button.script = "on mouseUp\n  put 1 into x\nend mouseUp"
            document.addPart(button)
            installActiveDocument(document)
            defer {
                HypeDocumentMutationCoordinator.shared.activeDocumentBinding = nil
                HypeDocumentMutationCoordinator.shared.activeCardId = nil
                resetRecorder()
            }

            let add = HypeDebugServer.shared.callScriptEditorAutomationControlTool(
                name: "hype_toggle_script_editor_breakpoint",
            arguments: [
                "object_type": .string("part"),
                "id_or_name": .string("Run"),
                "line": .number(1),
                "action": .string("add"),
            ]
        )

            #expect(add.isError == false)
            #expect(add.text.contains("\"isSet\" : true"))

            let state = HypeDebugServer.shared.callScriptEditorAutomationControlTool(
                name: "hype_get_script_editor_state",
                arguments: [
                    "object_type": .string("part"),
                    "id_or_name": .string("Run"),
                ]
            )

        #expect(state.isError == false)
        #expect(state.text.contains("\"scriptLineCount\" : 3"))
        #expect(state.text.contains("\"breakpointLines\""))
        #expect(state.text.contains("1"))

        let unsupportedLine = HypeDebugServer.shared.callScriptEditorAutomationControlTool(
            name: "hype_toggle_script_editor_breakpoint",
            arguments: [
                "object_type": .string("part"),
                "id_or_name": .string("Run"),
                "line": .number(2),
                "action": .string("add"),
            ]
        )

        #expect(unsupportedLine.isError)
        #expect(unsupportedLine.text.contains("handler entries"))

        let remove = HypeDebugServer.shared.callScriptEditorAutomationControlTool(
            name: "hype_toggle_script_editor_breakpoint",
            arguments: [
                "object_type": .string("part"),
                "id_or_name": .string("Run"),
                "line": .number(1),
                "action": .string("remove"),
            ]
        )

            #expect(remove.isError == false)
            #expect(remove.text.contains("\"isSet\" : false"))
        }
    }

    @Test("MCP control tool registry exposes automation hooks")
    func mcpRegistryExposesAutomationHooks() async {
        await HypeDebugServerTestIsolation.shared.withMainActorLock {
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_list_windows"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_focus_window"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_wait_for_window"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_wait_for_debugger_pause"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_step_script_execution_and_wait"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_get_script_editor_state"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_toggle_script_editor_breakpoint"))
        }
    }

    private func installActiveDocument(_ document: HypeDocument) {
        var wrapper = HypeDocumentWrapper()
        wrapper.document = document
        HypeDocumentMutationCoordinator.shared.activeDocumentBinding = Binding(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        HypeDocumentMutationCoordinator.shared.activeCardId = document.sortedCards.first?.id
    }

    private func traceContext(sourceId: UUID, handler: String, line: Int) -> HypeTalkScriptTraceContext {
        HypeTalkScriptTraceContext(
            message: handler,
            handler: handler,
            ownerDescription: "button \"Run\"",
            source: HypeTalkScriptTraceSource(kind: "part", objectId: sourceId),
            line: line
        )
    }

    private func waitUntilPaused(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<100 {
            if HypeTalkScriptTraceRecorder.shared.snapshot().pausedState != nil {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Expected debugger pause", sourceLocation: sourceLocation)
        throw AutomationTestError.pauseTimedOut
    }

    private func resetRecorder() {
        HypeTalkScriptTraceRecorder.shared.resetDebuggerState()
    }

    private enum AutomationTestError: Error {
        case pauseTimedOut
    }
}

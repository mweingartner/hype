import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
private final class DebugAlertDismissTarget: NSObject {
    weak var window: NSWindow?

    @objc func dismiss(_ sender: Any?) {
        window?.orderOut(nil)
    }
}

@MainActor
@Suite("HypeDebugServer automation tools", .serialized)
struct HypeDebugServerAutomationToolTests {
    @Test("displayed debug opens match the package's internal stack name")
    func displayedDebugOpenUsesInternalStackName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-debug-open-\(UUID().uuidString)", isDirectory: true)
        let packageURL = root.appendingPathComponent("renamed-agent-fixture.hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try HypeSQLiteStackStore().save(
            HypeDocument.newDocument(name: "Internal Acceptance Name"),
            toPackageAt: packageURL
        )

        #expect(
            HypeDebugOpenedDocumentIdentity.expectedStackName(at: packageURL)
                == "Internal Acceptance Name"
        )
    }

    @Test("script editor window identity includes the originating stack")
    func scriptEditorWindowIdentityIncludesStack() {
        let target = ScriptTarget.part(UUID())
        let first = scriptEditorWindowIdentityKey(stackId: UUID(), target: target)
        let second = scriptEditorWindowIdentityKey(stackId: UUID(), target: target)

        #expect(first != second)
        #expect(first.hasSuffix(target.identityKey))
        #expect(second.hasSuffix(target.identityKey))
    }

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

    @Test("alert automation reports modal details and dismisses by button")
    func alertAutomationReportsAndDismissesModal() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled, .docModalWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Save Error"
        panel.isReleasedWhenClosed = false
        defer { panel.close() }

        let message = NSTextField(labelWithString: "Invalid or corrupted save file")
        message.frame = NSRect(x: 24, y: 170, width: 420, height: 24)
        let details = NSTextField(labelWithString: "The package could not be opened.")
        details.frame = NSRect(x: 24, y: 130, width: 420, height: 24)
        let dismissTarget = DebugAlertDismissTarget()
        dismissTarget.window = panel
        let dismissButton = NSButton(
            title: "Dismiss",
            target: dismissTarget,
            action: #selector(DebugAlertDismissTarget.dismiss(_:))
        )
        dismissButton.frame = NSRect(x: 360, y: 20, width: 96, height: 32)
        panel.contentView?.addSubview(message)
        panel.contentView?.addSubview(details)
        panel.contentView?.addSubview(dismissButton)
        panel.makeKeyAndOrderFront(nil)

        let list = HypeDebugServer.shared.callWindowAutomationControlTool(
            name: "hype_list_alerts",
            arguments: [:]
        )
        #expect(list.isError == false)
        #expect(list.text.contains("Invalid or corrupted save file"))
        #expect(list.text.contains("The package could not be opened."))
        #expect(list.text.contains("Dismiss"))

        let dismiss = HypeDebugServer.shared.callWindowAutomationControlTool(
            name: "hype_dismiss_alert",
            arguments: [
                "message": .string("corrupted save"),
                "button": .string("Dismiss"),
            ]
        )

        #expect(dismiss.isError == false)
        #expect(dismiss.text.contains("\"pressedButton\" : \"Dismiss\""))
        #expect(panel.isVisible == false)
    }

    @Test("debugger wait tool returns immediately and exposes the pause through polling")
    func debuggerWaitReturnsPollablePauseState() async throws {
        try await HypeDebugServerTestIsolation.shared.withMainActorLock {
            resetRecorder()
            defer { resetRecorder() }

            let sourceId = UUID()
            let executionId = UUID()
            _ = HypeTalkScriptTraceRecorder.shared.addBreakpoint(
                HypeTalkScriptBreakpoint(sourceKind: "part", objectId: sourceId, handler: "mouseUp", line: 1)
            )
            HypeTalkScriptTraceRecorder.shared.setEnabled(true)

            let pauseTask = Task {
                await HypeTalkScriptTraceRecorder.shared.pauseIfNeeded(
                    context: traceContext(
                        executionId: executionId,
                        sourceId: sourceId,
                        handler: "mouseUp",
                        line: 1
                    ),
                    variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "initial"])
                )
            }

            try await waitUntilPaused()

            let start = await HypeDebugServer.shared.callDebuggerWaitControlTool(
                name: "hype_wait_for_debugger_pause",
                arguments: [
                    "reason": .string("breakpoint"),
                    "handler": .string("mouseUp"),
                    "timeout_ms": .number(250),
                ]
            )

            #expect(start.isError == false)
            let operationId = try operationId(from: start.text)
            let operation = try await pollDebugOperation(operationId)
            #expect(operation["status"] as? String == "completed")
            let result = try operationToolResult(operation)
            #expect(result["matched"] as? Bool == true)
            let pause = try #require(result["pausedState"] as? [String: Any])
            let variables = try #require(pause["variables"] as? [String: Any])
            let locals = try #require(variables["locals"] as? [String: Any])
            #expect(locals["phase"] as? String == "initial")

            let forget = HypeDebugServer.shared.callDebugOperationControlTool(
                name: "hype_forget_debug_operation",
                arguments: ["operation_id": .string(operationId)]
            )
            #expect(forget.isError == false)
            #expect(forget.text.contains("\"forgotten\" : true"))
            let missing = HypeDebugServer.shared.callDebugOperationControlTool(
                name: "hype_poll_debug_operation",
                arguments: ["operation_id": .string(operationId)]
            )
            #expect(missing.isError == true)
            #expect(missing.text.contains("Unknown or expired"))

            _ = HypeTalkScriptTraceRecorder.shared.resumePausedExecution()
            _ = await pauseTask.value
        }
    }

    @Test("step and wait returns immediately then reports the next pause through polling")
    func stepAndWaitReportsNextPollablePause() async throws {
        try await HypeDebugServerTestIsolation.shared.withMainActorLock {
            resetRecorder()
            defer { resetRecorder() }

            let sourceId = UUID()
            let executionId = UUID()
            _ = HypeTalkScriptTraceRecorder.shared.addBreakpoint(
                HypeTalkScriptBreakpoint(sourceKind: "part", objectId: sourceId, handler: "mouseUp", line: 1)
            )
            HypeTalkScriptTraceRecorder.shared.setEnabled(true)

            let firstPause = Task {
                await HypeTalkScriptTraceRecorder.shared.pauseIfNeeded(
                    context: traceContext(
                        executionId: executionId,
                        sourceId: sourceId,
                        handler: "mouseUp",
                        line: 1
                    ),
                    variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "first"])
                )
            }
            try await waitUntilPaused()

            let start = await HypeDebugServer.shared.callDebuggerWaitControlTool(
                name: "hype_step_script_execution_and_wait",
                arguments: [
                    "step": .string("into"),
                    "reason": .string("stepInto"),
                    "timeout_ms": .number(1_000),
                ]
            )
            #expect(start.isError == false)
            let operationId = try operationId(from: start.text)
            _ = await firstPause.value

            let secondPause = Task {
                await HypeTalkScriptTraceRecorder.shared.pauseIfNeeded(
                    context: traceContext(
                        executionId: executionId,
                        sourceId: sourceId,
                        handler: "nextHandler",
                        line: 2
                    ),
                    variables: HypeTalkVariableScopeSnapshot(locals: ["phase": "second"])
                )
            }

            let operation = try await pollDebugOperation(operationId)
            #expect(operation["status"] as? String == "completed")
            let result = try operationToolResult(operation)
            #expect(result["resumed"] as? Bool == true)
            let pause = try #require(result["pausedState"] as? [String: Any])
            #expect(pause["reason"] as? String == "stepInto")
            let variables = try #require(pause["variables"] as? [String: Any])
            let locals = try #require(variables["locals"] as? [String: Any])
            #expect(locals["phase"] as? String == "second")

            _ = HypeTalkScriptTraceRecorder.shared.resumePausedExecution()
            _ = await secondPause.value
        }
    }

    @Test("debugger wait start does not block when no pause exists")
    func debuggerWaitStartIsNonblocking() async throws {
        try await HypeDebugServerTestIsolation.shared.withMainActorLock {
            resetRecorder()
            defer { resetRecorder() }

            let start = await HypeDebugServer.shared.callDebuggerWaitControlTool(
                name: "hype_wait_for_debugger_pause",
                arguments: ["timeout_ms": .number(250)]
            )

            #expect(start.isError == false)
            let payload = try jsonObject(from: start.text)
            #expect(payload["status"] as? String == "pending")
            let operationId = try #require(payload["operationId"] as? String)
            let terminal = try await pollDebugOperation(operationId)
            #expect(terminal["status"] as? String == "failed")
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

        let addBodyLine = HypeDebugServer.shared.callScriptEditorAutomationControlTool(
            name: "hype_toggle_script_editor_breakpoint",
            arguments: [
                "object_type": .string("part"),
                "id_or_name": .string("Run"),
                "line": .number(2),
                "action": .string("add"),
            ]
        )

        #expect(addBodyLine.isError == false)
        #expect(addBodyLine.text.contains("\"isSet\" : true"))
        #expect(addBodyLine.text.contains("2"))

        let rejectBlankLine = HypeDebugServer.shared.callScriptEditorAutomationControlTool(
            name: "hype_toggle_script_editor_breakpoint",
            arguments: [
                "object_type": .string("part"),
                "id_or_name": .string("Run"),
                "line": .number(3),
                "action": .string("add"),
            ]
        )

        #expect(rejectBlankLine.isError == true)
        #expect(rejectBlankLine.text.contains("not a handler declaration or executable statement"))

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
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_list_alerts"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_dismiss_alert"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_wait_for_debugger_pause"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_step_script_execution_and_wait"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_poll_debug_operation"))
            #expect(HypeMCPToolBridge.mcpControlToolNames.contains("hype_forget_debug_operation"))
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

    private func traceContext(
        executionId: UUID = UUID(),
        sourceId: UUID,
        handler: String,
        line: Int
    ) -> HypeTalkScriptTraceContext {
        HypeTalkScriptTraceContext(
            executionId: executionId,
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
        HypeDebugServer.shared.resetDebugOperationsForTesting()
    }

    private func operationId(from text: String) throws -> String {
        let object = try jsonObject(from: text)
        guard let operationId = object["operationId"] as? String else {
            throw AutomationTestError.invalidOperationPayload
        }
        return operationId
    }

    private func pollDebugOperation(_ operationId: String) async throws -> [String: Any] {
        for _ in 0..<100 {
            let result = HypeDebugServer.shared.callDebugOperationControlTool(
                name: "hype_poll_debug_operation",
                arguments: ["operation_id": .string(operationId)]
            )
            guard !result.isError else {
                throw AutomationTestError.invalidOperationPayload
            }
            let operation = try jsonObject(from: result.text)
            if operation["status"] as? String != "pending" {
                return operation
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw AutomationTestError.operationTimedOut
    }

    private func operationToolResult(_ operation: [String: Any]) throws -> [String: Any] {
        guard let result = operation["result"] as? [String: Any] else {
            throw AutomationTestError.invalidOperationPayload
        }
        return result
    }

    private func jsonObject(from text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutomationTestError.invalidOperationPayload
        }
        return object
    }

    private enum AutomationTestError: Error {
        case pauseTimedOut
        case operationTimedOut
        case invalidOperationPayload
    }
}

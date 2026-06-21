import Foundation
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("HypeDebugServer menu automation", .serialized)
struct HypeDebugServerMenuAutomationTests {
    @Test("lists debug-server menu automation commands")
    func listsMenuAutomationCommands() {
        let result = HypeDebugServer.shared.callMenuAutomationControlTool(
            name: "hype_list_menu_commands",
            arguments: [:]
        )

        #expect(result.isError == false)
        #expect(result.text.contains("\"id\" : \"script_debugger\""))
        #expect(result.text.contains("\"id\" : \"show_console\""))
        #expect(result.text.contains("\"id\" : \"select_tool\""))
    }

    @Test("trigger menu command posts script debugger notification")
    func triggerScriptDebuggerPostsNotification() {
        let capture = MenuNotificationCapture()
        let observer = NotificationCenter.default.addObserver(
            forName: .openScriptDebugger,
            object: nil,
            queue: nil
        ) { _ in
            capture.didPost = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = HypeDebugServer.shared.callMenuAutomationControlTool(
            name: "hype_trigger_menu_command",
            arguments: ["command": .string("script_debugger")]
        )

        #expect(result.isError == false)
        #expect(result.text.contains("\"notificationName\" : \"hype.openScriptDebugger\""))
        #expect(capture.didPost)
    }

    @Test("trigger menu command accepts visible labels")
    func triggerMenuCommandAcceptsVisibleLabels() {
        let capture = MenuNotificationCapture()
        let observer = NotificationCenter.default.addObserver(
            forName: .showConsole,
            object: nil,
            queue: nil
        ) { _ in
            capture.didPost = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = HypeDebugServer.shared.callMenuAutomationControlTool(
            name: "hype_trigger_menu_command",
            arguments: ["command": .string("Show Console")]
        )

        #expect(result.isError == false)
        #expect(result.text.contains("\"command\""))
        #expect(capture.didPost)
    }

    @Test("trigger document-scoped menu command posts stack id")
    func triggerDocumentScopedMenuCommandPostsStackId() throws {
        let stackId = UUID()
        let capture = MenuNotificationCapture()
        let observer = NotificationCenter.default.addObserver(
            forName: .navigateCard,
            object: nil,
            queue: nil
        ) { notification in
            capture.direction = notification.object as? NavigationDirection
            capture.stackId = notification.userInfo?[MenuCommandScoping.stackIdKey] as? UUID
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = HypeDebugServer.shared.callMenuAutomationControlTool(
            name: "hype_trigger_menu_command",
            arguments: [
                "command": .string("next_card"),
                "stack_id": .string(stackId.uuidString),
            ]
        )

        #expect(result.isError == false)
        #expect(capture.direction == .next)
        #expect(capture.stackId == stackId)
    }

    @Test("trigger select tool requires an argument")
    func triggerSelectToolRequiresArgument() {
        let result = HypeDebugServer.shared.callMenuAutomationControlTool(
            name: "hype_trigger_menu_command",
            arguments: ["command": .string("select_tool")]
        )

        #expect(result.isError)
        #expect(result.text.contains("requires argument"))
    }

    @Test("trigger select tool posts requested tool")
    func triggerSelectToolPostsRequestedTool() {
        let capture = MenuNotificationCapture()
        let observer = NotificationCenter.default.addObserver(
            forName: .selectTool,
            object: nil,
            queue: nil
        ) { notification in
            capture.tool = notification.object as? ToolName
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = HypeDebugServer.shared.callMenuAutomationControlTool(
            name: "hype_trigger_menu_command",
            arguments: [
                "command": .string("select_tool"),
                "argument": .string("button"),
            ]
        )

        #expect(result.isError == false)
        #expect(capture.tool == .button)
    }
}

private final class MenuNotificationCapture: @unchecked Sendable {
    var didPost = false
    var direction: NavigationDirection?
    var stackId: UUID?
    var tool: ToolName?
}
